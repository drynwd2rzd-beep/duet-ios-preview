import SwiftUI
import UIKit
import CoreText
import UserNotifications

struct Person: Codable, Identifiable {
    var id: String
    var name: String
    var avatar: String? = nil
}
struct ChatAttachment: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var path: String
    var photo: Bool
    var bytes: Int
}
struct ChatMessage: Codable, Identifiable {
    var id = UUID()
    var author: String
    var text: String
    var attachments: [ChatAttachment] = []
    var date = Date()
    var status = "sample"
    var recipients: [String] = []
    var demo = false
    var edited = false
}
struct Idea: Codable, Identifiable {
    var id = UUID()
    var text = ""
    var later = false
    var task = false
    var done = false
    var reminder: Date? = nil
}
struct Memory: Codable, Identifiable {
    var id = UUID()
    var text = ""
    var kind = "关于你"
    var group = false
    var thread: String? = nil
    var message: UUID? = nil
    var date = Date()
}
struct Persona: Codable {
    var identity = ""
    var values = ""
    var relationship = ""
    var voice = ""
    var memories: [Memory] = []
}
struct UserFont: Codable, Identifiable {
    var id = UUID()
    var label: String
    var postScriptName: String
    var path: String
}
struct Preferences: Codable {
    var appearance = "system"
    var theme = "rose"
    var customHex = "A76D87"
    var background = "porcelain"
    var typography = "native"
    var selectedFont: UUID? = nil
    var textScale = 1.0
    var fonts: [UserFont] = []
    var autoDiscuss = false
    var rounds = 2
}
struct NativeState: Codable {
    var schema = 1
    var people: [String: Person] = ["self": Person(id: "self", name: "我"), "gpt": Person(id: "gpt", name: "ChatGPT"), "claude": Person(id: "claude", name: "Claude"), "group": Person(id: "group", name: "我们仨")]
    var messages: [String: [ChatMessage]] = [:]
    var pinned = ["group"]
    var ideas: [Idea] = [Idea(text: "确定双 AI 聊天 App 的界面", task: true), Idea(text: "聊天时的灵感，可以直接保存到这里"), Idea(text: "给周末留一点安静的时间", later: true)]
    var personas = ["gpt": Persona(), "claude": Persona()]
    var models = ["gpt": "跟随官网", "claude": "跟随官网"]
    var strengths = ["gpt": "自动", "claude": "自动"]
    var backgrounds: [String: String] = [:]
    var drafts: [String: String] = [:]
    var preferences = Preferences()
}

@MainActor
final class NativeStore: ObservableObject {
    @Published var data = NativeState() { didSet { scheduleSave() } }
    @Published var settingsPresented = false
    @Published var toast: String? = nil
    @Published var replyingThread: String? = nil
    @Published var requestedThread: String? = nil
    var requestedMessage: UUID? = nil
    private var persistenceTask: Task<Void, Never>?
    private var replyTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    let directory: URL
    let testMode: Bool

    init() {
        testMode = ProcessInfo.processInfo.arguments.contains("--uitesting")
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent(testMode ? "DuetUITest-" + UUID().uuidString : "DuetNative", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let raw = try? Data(contentsOf: directory.appendingPathComponent("state.json")), let saved = try? JSONDecoder().decode(NativeState.self, from: raw) { data = saved }
        else { migrateLegacyPreferences() }
        registerFonts()
        if data.messages.isEmpty { seedMessages() }
        for thread in ["gpt", "claude", "group"] {
            var messages = data.messages[thread] ?? []
            for i in messages.indices where messages[i].status == "sending" || messages[i].status == "replying" { messages[i].status = messages[i].author == "me" ? "failed" : "stopped" }
            data.messages[thread] = messages
        }
    }

    func name(_ id: String) -> String { data.people[id == "me" ? "self" : id]?.name ?? id }
    func profile(_ id: String) -> Person { data.people[id] ?? Person(id: id, name: id) }
    var appearance: ColorScheme? { data.preferences.appearance == "dark" ? .dark : data.preferences.appearance == "light" ? .light : nil }
    func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let scaled = size * data.preferences.textScale
        if data.preferences.typography == "custom", let id = data.preferences.selectedFont, let file = data.preferences.fonts.first(where: { $0.id == id }) { return .custom(file.postScriptName, size: scaled, relativeTo: .body).weight(weight) }
        if data.preferences.typography == "artistic" { return .system(size: scaled, weight: weight, design: .serif) }
        return .system(size: scaled, weight: weight)
    }
    func url(_ relative: String) -> URL { directory.appendingPathComponent(relative) }
    func image(_ path: String?) -> UIImage? { guard let path else { return nil }; return UIImage(contentsOfFile: url(path).path) }

    private func scheduleSave() {
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled, let self else { return }
            self.persist()
        }
    }
    func persist() {
        do { let raw = try JSONEncoder().encode(data); try raw.write(to: directory.appendingPathComponent("state.json"), options: .atomic) }
        catch { toast = "未能保存到设备，请检查可用空间" }
    }
    func notice(_ text: String, success: Bool = false) {
        toastTask?.cancel()
        toast = text
        if success { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        toastTask = Task { [weak self] in try? await Task.sleep(nanoseconds: 2_400_000_000); if !Task.isCancelled { self?.toast = nil } }
    }
    func pin(_ thread: String) {
        if data.pinned.contains(thread) { data.pinned.removeAll { $0 == thread }; notice("已取消置顶") }
        else { data.pinned.insert(thread, at: 0); notice("已置顶") }
        UISelectionFeedbackGenerator().selectionChanged()
    }
    func saveProfile(_ profile: Person) { var p = profile; p.name = String(p.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24)); guard !p.name.isEmpty else { return }; data.people[p.id] = p; notice("已更新资料", success: true) }

    func savePhoto(_ raw: Data, name: String = "照片.jpg") throws -> ChatAttachment {
        guard raw.count <= 24 * 1024 * 1024, let image = UIImage(data: raw) else { throw LocalError.message("无法读取这张照片，或图片超过 24 MB") }
        let ratio = min(1, 2000 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let jpeg = scaled.jpegData(compressionQuality: 0.88) else { throw LocalError.message("无法保存照片") }
        let path = UUID().uuidString + ".jpg"; try jpeg.write(to: url(path), options: .atomic)
        return ChatAttachment(name: name, path: path, photo: true, bytes: jpeg.count)
    }
    func saveFile(_ source: URL) throws -> ChatAttachment {
        let access = source.startAccessingSecurityScopedResource(); defer { if access { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) <= 20 * 1024 * 1024 else { throw LocalError.message("请选择不超过 20 MB 的文件") }
        let ext = String(source.pathExtension.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(12))
        let path = UUID().uuidString + (ext.isEmpty ? "" : "." + ext)
        try FileManager.default.copyItem(at: source, to: url(path))
        return ChatAttachment(name: source.lastPathComponent, path: path, photo: false, bytes: values.fileSize ?? 0)
    }
    func importFont(_ source: URL) throws {
        guard ["ttf", "otf"].contains(source.pathExtension.lowercased()) else { throw LocalError.message("原生字体支持 TTF 或 OTF 文件") }
        guard data.preferences.fonts.count < 6 else { throw LocalError.message("最多添加 6 款字体，请先移除一款") }
        let file = try saveFile(source)
        var error: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(url(file.path) as CFURL, .process, &error), let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url(file.path) as CFURL) as? [CTFontDescriptor], let descriptor = descriptors.first else { throw LocalError.message("字体无法载入，请换一个文件") }
        let font = CTFontCreateWithFontDescriptor(descriptor, 16, nil)
        let entry = UserFont(label: source.deletingPathExtension().lastPathComponent, postScriptName: CTFontCopyPostScriptName(font) as String, path: file.path)
        data.preferences.fonts.append(entry); data.preferences.selectedFont = entry.id; data.preferences.typography = "custom"
        notice("已应用字体", success: true)
    }
    private func registerFonts() {
        for file in data.preferences.fonts { CTFontManagerRegisterFontsForURL(url(file.path) as CFURL, .process, nil) }
    }

    func recipients(_ text: String, thread: String) -> [String] {
        guard thread == "group" else { return [thread] }
        if text.contains("@所有人") { return ["gpt", "claude"] }
        let found = ["gpt", "claude"].filter { text.contains("@" + name($0)) || text.contains("@" + ($0 == "gpt" ? "ChatGPT" : "Claude")) }
        return found.isEmpty ? ["gpt", "claude"] : found
    }
    func send(thread: String, text: String, attachments: [ChatAttachment], editing: UUID? = nil) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty else { return }
        let targets = recipients(text, thread: thread)
        var id = UUID()
        if let editing, let i = data.messages[thread]?.firstIndex(where: { $0.id == editing }) {
            data.messages[thread]![i].text = text; data.messages[thread]![i].status = "sending"; data.messages[thread]![i].edited = true; data.messages[thread]![i].recipients = targets; id = editing
        } else {
            let message = ChatMessage(author: "me", text: String(text.prefix(10000)), attachments: attachments, status: "sending", recipients: targets); id = message.id; data.messages[thread, default: []].append(message)
        }
        data.drafts[thread] = ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        markFailed(thread, id: id)
    }
    private func markFailed(_ thread: String, id: UUID) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard let self, let i = self.data.messages[thread]?.firstIndex(where: { $0.id == id }), self.data.messages[thread]![i].status == "sending" else { return }
            self.data.messages[thread]![i].status = "failed"
        }
    }
    func retry(_ thread: String, id: UUID) { guard let i = data.messages[thread]?.firstIndex(where: { $0.id == id }) else { return }; data.messages[thread]![i].status = "sending"; markFailed(thread, id: id); notice("体验版尚未连接 AI 账号") }
    func stopDemo() {
        replyTask?.cancel()
        if let thread = replyingThread, let i = data.messages[thread]?.lastIndex(where: { $0.status == "replying" }) { data.messages[thread]![i].status = "stopped" }
        replyingThread = nil
    }
    func demo(_ thread: String) {
        stopDemo(); settingsPresented = false; requestedThread = thread; replyingThread = thread
        let targets = thread == "group" ? ["gpt", "claude"] : [thread]
        let queue = Array(repeating: targets, count: thread == "group" && data.preferences.autoDiscuss ? data.preferences.rounds : 1).flatMap { $0 }
        replyTask = Task { [weak self] in
            guard let self else { return }
            for author in queue {
                guard !Task.isCancelled else { return }
                let message = ChatMessage(author: author, text: "", status: "replying", demo: true)
                self.data.messages[thread, default: []].append(message)
                let text = "这是一段原生回复交互演示。真实 AI 尚未连接，你可以随时停止。"
                try? await Task.sleep(nanoseconds: 300_000_000)
                for end in 1...text.count {
                    guard !Task.isCancelled, let i = self.data.messages[thread]?.firstIndex(where: { $0.id == message.id }) else { return }
                    self.data.messages[thread]![i].text = String(text.prefix(end)); try? await Task.sleep(nanoseconds: 65_000_000)
                }
                if let i = self.data.messages[thread]?.firstIndex(where: { $0.id == message.id }) { self.data.messages[thread]![i].status = "demo" }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            self.replyingThread = nil
        }
    }
    func saveIdea(_ idea: Idea) {
        var item = idea; item.text = item.text.trimmingCharacters(in: .whitespacesAndNewlines); guard !item.text.isEmpty else { return }
        if let i = data.ideas.firstIndex(where: { $0.id == item.id }) { data.ideas[i] = item } else { data.ideas.insert(item, at: 0) }
        persist(); notice("已保存想法", success: true)
    }
    func deleteIdea(_ id: UUID) { data.ideas.removeAll { $0.id == id }; UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString]) }
    func setReminder(_ idea: Idea) async {
        guard let date = idea.reminder, date > Date() else { notice("请选择将来的提醒时间"); return }
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            saveIdea(idea)
            guard granted else { notice("提醒已记录，系统通知尚未允许"); return }
            let content = UNMutableNotificationContent(); content.title = "Duet · 想法"; content.body = idea.text; content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            try await center.add(UNNotificationRequest(identifier: idea.id.uuidString, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
            notice("已设置提醒", success: true)
        } catch { notice("提醒没有设置成功：" + error.localizedDescription) }
    }
    func saveMemory(_ memory: Memory, provider: String) { guard !memory.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; if let i = data.personas[provider]?.memories.firstIndex(where: { $0.id == memory.id }) { data.personas[provider]!.memories[i] = memory } else { data.personas[provider, default: Persona()].memories.insert(memory, at: 0) }; notice("已保存记忆", success: true) }

    private func migrateLegacyPreferences() {
        guard !testMode, let raw = UserDefaults.standard.data(forKey: "duet.preview.preferences.v1"), let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any], let old = object["privateContent"] as? [String: Any] else { return }
        if let profiles = old["profiles"] as? [String: [String: Any]] { for (id, p) in profiles where data.people[id] != nil { if let name = p["name"] as? String { data.people[id]!.name = String(name.prefix(24)) } } }
        if let theme = old["theme"] as? String { data.preferences.theme = theme }
        if let appearance = old["appearance"] as? String { data.preferences.appearance = appearance }
        if let preferences = old["preferences"] as? [String: Any] { data.preferences.autoDiscuss = preferences["autoDiscuss"] as? Bool ?? false; data.preferences.rounds = preferences["rounds"] as? Int ?? 2; data.preferences.textScale = preferences["textScale"] as? Double ?? 1; data.preferences.background = preferences["background"] as? String ?? "porcelain"; data.preferences.typography = preferences["fontMode"] as? String == "artistic" ? "artistic" : "native" }
        if let ideas = old["ideas"] as? [[String: Any]], !ideas.isEmpty { data.ideas = ideas.compactMap { item in guard let text = item["title"] as? String else { return nil }; return Idea(text: text, later: item["when"] as? String == "later", task: item["kind"] as? String == "task", done: item["done"] as? Bool ?? false) } }
        if let personas = old["personas"] as? [String: [String: Any]] { for id in ["gpt", "claude"] { guard let p = personas[id] else { continue }; data.personas[id] = Persona(identity: p["identity"] as? String ?? "", values: p["values"] as? String ?? "", relationship: p["relationship"] as? String ?? "", voice: p["voice"] as? String ?? "", memories: (p["memories"] as? [[String: Any]] ?? []).compactMap { m in guard let text = m["text"] as? String else { return nil }; return Memory(text: text, kind: m["kind"] as? String == "shared" ? "共同经历" : "关于你", group: m["group"] as? Bool ?? false) }) } }
    }

    private func seedMessages() {
        var scenes: [ChatAttachment] = []
        for index in 0..<3 { if let image = scene(index), let jpeg = image.jpegData(compressionQuality: 0.9), let attachment = try? savePhoto(jpeg, name: "风景示例 \(index + 1).jpg") { scenes.append(attachment) } }
        data.messages = ["group": [ChatMessage(author: "me", text: "周末想出去走走，\n你们觉得这些地方怎么样？"), ChatMessage(author: "me", text: "", attachments: scenes), ChatMessage(author: "gpt", text: "我会选第二张。海边的颜色很安静，适合慢慢走，也不用把行程排得太满。"), ChatMessage(author: "claude", text: "我也喜欢海边。带上相机和一本书，留一点时间，什么也不做。")], "gpt": [ChatMessage(author: "me", text: "帮我把这个想法拆成几个步骤。"), ChatMessage(author: "gpt", text: "先确定界面，再验证账号连接，最后测试单聊、群聊和提醒。")], "claude": [ChatMessage(author: "me", text: "有时候想到一个点子，过一会就忘了。"), ChatMessage(author: "claude", text: "先记下原话就好。等你有空时，我们再一起把它变得具体。")]]
    }
    private func scene(_ index: Int) -> UIImage? {
        let palette = [["E7C5BB", "F5E1CA", "8FA7A1", "607D7D"], ["B6CED4", "E9DDD2", "8FADAF", "5C858D"], ["D4C9D7", "F3D8C4", "9A9EAE", "6D7D8A"]][index]
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 640, height: 520), format: format).image { context in
            let cg = context.cgContext
            let colors = [UIColor(hex: palette[0]).cgColor, UIColor(hex: palette[1]).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) { cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: 520), options: []) }
            UIColor(hex: "FFF4DC").setFill(); UIBezierPath(ovalIn: CGRect(x: CGFloat(420 - index * 65), y: CGFloat(100 + index * 20), width: 80, height: 80)).fill()
            UIColor(hex: palette[2]).setFill(); let back = UIBezierPath(); back.move(to: CGPoint(x: 0, y: 320)); back.addCurve(to: CGPoint(x: 382, y: 277), controlPoint1: CGPoint(x: 130, y: 155), controlPoint2: CGPoint(x: 240, y: 353)); back.addCurve(to: CGPoint(x: 640, y: 222), controlPoint1: CGPoint(x: 500, y: 205), controlPoint2: CGPoint(x: 550, y: 260)); back.addLine(to: CGPoint(x: 640, y: 520)); back.addLine(to: CGPoint(x: 0, y: 520)); back.close(); back.fill()
            UIColor(hex: palette[3]).setFill(); let front = UIBezierPath(); front.move(to: CGPoint(x: 0, y: 410)); front.addCurve(to: CGPoint(x: 464, y: 364), controlPoint1: CGPoint(x: 170, y: 302), controlPoint2: CGPoint(x: 295, y: 486)); front.addQuadCurve(to: CGPoint(x: 640, y: 393), controlPoint: CGPoint(x: 560, y: 318)); front.addLine(to: CGPoint(x: 640, y: 520)); front.addLine(to: CGPoint(x: 0, y: 520)); front.close(); front.fill()
        }
    }
}
enum LocalError: LocalizedError { case message(String); var errorDescription: String? { if case let .message(text) = self { return text }; return nil } }
extension UIColor { convenience init(hex: String) { let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0; self.init(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1) } }
