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
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) { NativePush.shared.registered(deviceToken) }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) { NativePush.shared.failed(error) }
}

@MainActor
final class NativeNotifications: NSObject, UNUserNotificationCenterDelegate {
    private weak var store: NativeStore?
    private let center = UNUserNotificationCenter.current()
    func install(store: NativeStore) { self.store = store; center.delegate = self; NativePush.shared.install(store); if !store.testMode { Task { let settings = await center.notificationSettings(); if [.authorized, .provisional].contains(settings.authorizationStatus) { NativePush.shared.register() } } } }
    func authorize() async -> Bool {
        do { let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge]); if granted { NativePush.shared.register() }; return granted }
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
        guard !NativePush.shared.serverReady else { return }
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
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let thread = notification.request.content.userInfo["thread"] as? String
        return await MainActor.run { if let thread, self.store?.activeThread == thread, UIApplication.shared.applicationState == .active { return [] }; return [.banner, .sound, .list] }
    }
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
    private var pending = false
    var continuing: Bool { pending }
    func register() {
        // Cancel any legacy progress task. Waiting for a network reply no longer
        // schedules a system-visible continued-processing activity.
        let identifier = (Bundle.main.bundleIdentifier ?? "app.duet.preview") + ".reply"
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }
    func begin() {
        guard !pending else { return }; pending = true
        finiteTask = UIApplication.shared.beginBackgroundTask(withName: "Duet reply") { Task { @MainActor in self.pending = false; self.endFinite(); self.onExpiration?() } }
    }
    func progress(_ completed: Int) { }
    func finish(success: Bool) { pending = false; endFinite() }
    private func endFinite() { if finiteTask != .invalid { UIApplication.shared.endBackgroundTask(finiteTask); finiteTask = .invalid } }
}
