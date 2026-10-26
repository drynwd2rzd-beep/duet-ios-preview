import SwiftUI
import UIKit
import UserNotifications
import BackgroundTasks

@MainActor
final class DuetAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NativeBackground.shared.register()
        return true
    }
}

@MainActor
final class NativeNotifications: NSObject, UNUserNotificationCenterDelegate {
    private weak var store: NativeStore?
    private let center = UNUserNotificationCenter.current()
    func install(store: NativeStore) { self.store = store; center.delegate = self }
    func authorize() async -> Bool {
        do { return try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
        catch { return false }
    }
    func syncReminders(_ ideas: [Idea]) async {
        let pending = await center.pendingNotificationRequests()
        let legacyIDs = Set(ideas.map { $0.id.uuidString })
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("idea.") || legacyIDs.contains($0.identifier) }.map(\.identifier))
        guard store?.data.preferences.remindersEnabled != false else { return }
        let settings = await center.notificationSettings()
        guard [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) else { return }
        let upcoming = ideas.filter { !$0.done && ($0.reminder ?? .distantPast) > .now }.sorted { $0.reminder! < $1.reminder! }
        for idea in upcoming.prefix(60) {
            guard let date = idea.reminder else { continue }
            let content = UNMutableNotificationContent()
            content.title = idea.task ? "Duet · 待办提醒" : "Duet · 想法提醒"
            content.body = idea.text; content.sound = .default; content.threadIdentifier = "ideas"
            content.userInfo = ["ideaID": idea.id.uuidString]
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            try? await center.add(UNNotificationRequest(identifier: "idea." + idea.id.uuidString, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
    }
    func removeReminder(_ id: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString, "idea." + id.uuidString])
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString, "idea." + id.uuidString])
    }
    func clearReplies(_ channels: [String]) {
        Task { let items = await center.deliveredNotifications(); center.removeDeliveredNotifications(withIdentifiers: items.filter { $0.request.identifier.hasPrefix("reply.") && channels.contains($0.request.content.threadIdentifier) }.map { $0.request.identifier }) }
    }
    func reply(id: String, thread: String, name: String, text: String) {
        guard let store, !store.testMode, store.data.preferences.replyNotifications != false else { return }
        guard UIApplication.shared.applicationState != .active || store.activeThread != thread else { return }
        var seen = UserDefaults.standard.stringArray(forKey: "duet.notifiedReplies.v1") ?? []
        guard !seen.contains(id) else { return }
        seen.append(id); UserDefaults.standard.set(Array(seen.suffix(200)), forKey: "duet.notifiedReplies.v1")
        let content = UNMutableNotificationContent()
        content.title = name + " 回复了你"
        content.body = store.data.preferences.notificationPreview == false ? "打开 Duet 查看回复" : String(text.prefix(160))
        content.sound = .default; content.threadIdentifier = thread; content.userInfo = ["thread": thread,"messageID":id]
        Task { try? await center.add(UNNotificationRequest(identifier: "reply." + id, content: content, trigger: nil)) }
    }
    func test() async -> Bool {
        guard await authorize() else { return false }
        let content = UNMutableNotificationContent(); content.title = "Duet"; content.body = "通知已准备好。"; content.sound = .default
        do { try await center.add(UNNotificationRequest(identifier: "duet.notification-test", content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false))); return true }
        catch { return false }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound, .list] }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let thread = response.notification.request.content.userInfo["thread"] as? String
        let ideaID = response.notification.request.content.userInfo["ideaID"] as? String
        let messageID = response.notification.request.content.userInfo["messageID"] as? String
        await MainActor.run {
            self.store?.settingsPresented = false
            if let thread, ["gpt", "claude", "group"].contains(thread) { self.store?.requestedMessage = messageID.flatMap(UUID.init(uuidString:)); self.store?.requestedThread = thread }
            if let ideaID, let id = UUID(uuidString: ideaID) { self.store?.requestedIdea = id }
        }
    }
}

@MainActor
final class NativeBackground {
    static let shared = NativeBackground()
    var onExpiration: (() -> Void)?
    private var finiteTask: UIBackgroundTaskIdentifier = .invalid
    private var continuedTask: BGTask?
    private var pending = false
    private var registered = false
    private var phase = 0
    private var identifier: String { (Bundle.main.bundleIdentifier ?? "app.duet.preview") + ".reply" }
    var continuing: Bool { pending || continuedTask != nil }
    func register() {
        guard !registered else { return }
        if #available(iOS 26.0, *) {
            let permitted = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
            guard permitted.contains(identifier) else { return }
            registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
                Task { @MainActor in
                    guard let task = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
                    guard self.pending else { task.setTaskCompleted(success: true); return }
                    self.continuedTask = task; task.progress.totalUnitCount = 4; task.progress.completedUnitCount = Int64(self.phase)
                    task.expirationHandler = { Task { @MainActor in self.pending = false; self.continuedTask = nil; self.onExpiration?(); task.setTaskCompleted(success: false) } }
                }
            }
        }
    }
    func begin() {
        guard !pending else { return }; pending = true; phase = 1
        finiteTask = UIApplication.shared.beginBackgroundTask(withName: "Duet reply") { Task { @MainActor in
            self.endFinite()
            if self.continuedTask == nil { self.pending = false; self.onExpiration?() }
        } }
        if #available(iOS 26.0, *), registered {
            let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "Duet", subtitle: "正在等待伙伴回复")
            request.strategy = .fail
            try? BGTaskScheduler.shared.submit(request)
        }
    }
    func progress(_ completed: Int) {
        phase = max(phase, min(4, completed))
        if #available(iOS 26.0, *), let task = continuedTask as? BGContinuedProcessingTask { task.progress.completedUnitCount = Int64(phase) }
    }
    func finish(success: Bool) {
        guard pending || continuedTask != nil else { return }
        pending = false
        if let task = continuedTask { if success { progress(4) }; task.setTaskCompleted(success: success); continuedTask = nil }
        if #available(iOS 26.0, *), registered { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier) }
        endFinite()
    }
    private func endFinite() { if finiteTask != .invalid { UIApplication.shared.endBackgroundTask(finiteTask); finiteTask = .invalid } }
}
