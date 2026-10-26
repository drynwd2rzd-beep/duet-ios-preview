import SwiftUI
import UIKit
import CoreText
import UserNotifications
import ImageIO

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
    var bridgeJob: String? = nil
    var bridgeError: String? = nil
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
    var userCallName: String? = nil
    var groupCallName: String? = nil
}
struct ModelSelection: Codable { var source = "chatgpt-web"; var model: String? = nil; var effort: String? = nil }
struct ModelChoice: Identifiable {
    var id: String { source + ":" + model }
    var source: String; var model: String; var name: String; var effort: String?; var images: Bool
    var isDefault = false
    var efforts: [String] = []
    static let effortOrder = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra"]
    var availableEfforts: [String] { Self.effortOrder.filter { efforts.contains($0) } }
    var effortLabel: String { Self.effortName(effort, source: source) }
    static func effortName(_ effort: String?, source: String) -> String {
        switch effort?.lowercased() {
        case "none": return source == "chatgpt-web" ? "即时" : "关闭"
        case "minimal": return "极低"
        case "low": return "低"
        case "medium": return "中"
        case "high": return "高"
        case "xhigh": return "更高"
        case "max": return "最高"
        case "ultra": return "极致"
        default: return effort ?? "跟随模型默认"
        }
    }
    static func ordered(_ choices: [ModelChoice]) -> [ModelChoice] {
        choices.sorted { a, b in
            if a.source != b.source { return a.source == "chatgpt-web" }
            if a.isDefault != b.isDefault { return a.isDefault }
            let av = a.version, bv = b.version
            for index in 0..<max(av.count, bv.count) {
                let ai = index < av.count ? av[index] : 0, bi = index < bv.count ? bv[index] : 0
                if ai != bi { return ai > bi }
            }
            if a.variant != b.variant { return a.variant < b.variant }
            return a.model.localizedStandardCompare(b.model) == .orderedAscending
        }
    }
    private var version: [Int] {
        guard let range = model.range(of: #"\d+(?:\.\d+)*"#, options: .regularExpression) else { return [] }
        return model[range].split(separator: ".").compactMap { Int($0) }
    }
    private var variant: Int { ["astra", "sol", "terra", "luna"].firstIndex(where: { model.lowercased().contains($0) }) ?? 99 }
}
struct BackdropOptions: Codable, Equatable {
    var zoom = 1.0
    var x = 0.0
    var y = 0.0
    var blur = 0.0
    var dim = 0.12
    var headerFade = 0.9
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
    var replyNotifications: Bool? = nil
    var remindersEnabled: Bool? = nil
    var notificationPreview: Bool? = nil
}
struct NativeState: Codable {
    var schema = 1
    var people: [String: Person] = ["self": Person(id: "self", name: "我"), "gpt": Person(id: "gpt", name: "ChatGPT"), "claude": Person(id: "claude", name: "Claude"), "group": Person(id: "group", name: "我们仨")]
    var messages: [String: [ChatMessage]] = [:]
    var pinned = ["group"]
    var ideas: [Idea] = []
    var personas = ["gpt": Persona(), "claude": Persona()]
    var routes: [String: ModelSelection]? = nil
    var backgrounds: [String: String] = [:]
    var backdropOptions: [String: BackdropOptions]? = nil
    var drafts: [String: String] = [:]
    var draftAttachments: [String: [ChatAttachment]]? = nil
    var preferences = Preferences()
}

@MainActor
final class NativeStore: ObservableObject {
    @Published var data = NativeState() { didSet { scheduleSave() } }
    @Published var settingsPresented = false
    @Published var toast: String? = nil
    @Published var requestedThread: String? = nil
    @Published var requestedIdea: UUID? = nil
    var activeThread: String? = nil
    @Published var requestedMessage: UUID? = nil
    private var persistenceTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private let imageCache: NSCache<NSString, UIImage> = { let cache = NSCache<NSString, UIImage>(); cache.countLimit = 50; cache.totalCostLimit = 64 * 1024 * 1024; return cache }()
    private let luminanceCache = NSCache<NSString, NSNumber>()
    let directory: URL
    let testMode: Bool
    lazy var relay = NativeRelay(store: self)
    let notifications = NativeNotifications()

    init(directory customDirectory: URL? = nil, testMode testing: Bool? = nil) {
        testMode = testing ?? ProcessInfo.processInfo.arguments.contains("--uitesting")
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = customDirectory ?? base.appendingPathComponent(testMode ? "DuetUITest-" + UUID().uuidString : "DuetNative", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let raw = try? Data(contentsOf: directory.appendingPathComponent("state.json")), let saved = try? JSONDecoder().decode(NativeState.self, from: raw) { data = saved }
        else { migrateLegacyPreferences() }
        registerFonts()
        if data.preferences.typography == "artistic" { data.preferences.typography = "native" }
        for thread in ["gpt", "claude", "group"] {
            var messages = data.messages[thread] ?? []
            for i in messages.indices where messages[i].status == "sending" || messages[i].status == "replying" { messages[i].status = messages[i].author == "me" ? "failed" : "stopped" }
            data.messages[thread] = messages
        }
        #if DEBUG
        if testMode && ProcessInfo.processInfo.arguments.contains("--uitest-history") {
            data.messages["gpt"] = (0..<65).map { ChatMessage(author: $0 % 2 == 0 ? "me" : "gpt", text: $0 == 64 ? "Latest test reply" : "Earlier message \($0)", status: "received") }
        }
        if testMode && ProcessInfo.processInfo.arguments.contains("--uitest-models") {
            relay.connected = true
            relay.modelChoices = ModelChoice.ordered([
                ModelChoice(source: "chatgpt-web", model: "GPT-6", name: "GPT-6", effort: nil, images: true, efforts: ["high", "none", "medium"]),
                ModelChoice(source: "codex-chatgpt", model: "gpt-6-sol", name: "GPT-6 Sol", effort: "medium", images: true, isDefault: true, efforts: ["high", "low", "medium"])
            ])
        }
        if testMode && (ProcessInfo.processInfo.arguments.contains("--uitest-wallpaper") || ProcessInfo.processInfo.arguments.contains("--uitest-wallpaper-dark")) {
            let dark = ProcessInfo.processInfo.arguments.contains("--uitest-wallpaper-dark")
            let image = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 844)).image { context in
                (dark ? UIColor(white: 0.08, alpha: 1) : UIColor(red: 0.82, green: 0.73, blue: 0.66, alpha: 1)).setFill(); context.fill(CGRect(x: 0, y: 0, width: 390, height: 844))
                for index in 0..<20 {
                    (dark ? UIColor(white: index % 2 == 0 ? 0.16 : 0.24, alpha: 1) : (index % 2 == 0 ? UIColor.darkGray : UIColor.white)).setFill()
                    context.fill(CGRect(x: CGFloat(index * 22), y: 0, width: 9, height: 844))
                }
            }
            if let bytes = image.pngData() { try? bytes.write(to: directory.appendingPathComponent("uitest-wallpaper.png")); data.backgrounds["gpt"] = "uitest-wallpaper.png" }
        }
        #endif
        notifications.install(store: self)
        NativeBackground.shared.onExpiration = { [weak self] in self?.relay.backgroundExpired() }
    }

    func name(_ id: String) -> String { data.people[id == "me" ? "self" : id]?.name ?? id }
    func profile(_ id: String) -> Person { data.people[id] ?? Person(id: id, name: id) }
    var appearance: ColorScheme? { data.preferences.appearance == "dark" ? .dark : data.preferences.appearance == "light" ? .light : nil }
    func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let scaled = size * data.preferences.textScale
        if data.preferences.typography == "custom", let id = data.preferences.selectedFont, let file = data.preferences.fonts.first(where: { $0.id == id }) { return .custom(file.postScriptName, size: scaled, relativeTo: .body).weight(weight) }
        return .system(size: scaled, weight: weight)
    }
    func url(_ relative: String) -> URL { directory.appendingPathComponent(relative) }
    func image(_ path: String?) -> UIImage? { guard let path else { return nil }; if let cached = imageCache.object(forKey: path as NSString) { return cached }; guard let image = UIImage(contentsOfFile: url(path).path) else { return nil }; imageCache.setObject(image, forKey: path as NSString, cost: Int(image.size.width * image.size.height * image.scale * image.scale * 4)); return image }
    func backdrop(_ thread: String) -> BackdropOptions { data.backdropOptions?[thread] ?? BackdropOptions() }
    func chatColorScheme(_ thread: String, fallback: ColorScheme) -> ColorScheme {
        guard let path = data.backgrounds[thread], let image = image(path), let cgImage = image.cgImage else { return fallback }
        let luminance: Double
        if let cached = luminanceCache.object(forKey: path as NSString) { luminance = cached.doubleValue }
        else {
            var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
            let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
                guard let context = CGContext(data: bytes.baseAddress, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
                context.setFillColor(UIColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
                context.interpolationQuality = .low; context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 32, height: 32)); return true
            }
            guard rendered else { return fallback }
            var total = 0.0
            for offset in stride(from: 0, to: pixels.count, by: 4) { total += 0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1]) + 0.0722 * Double(pixels[offset + 2]) }
            luminance = total / (255 * 32 * 32)
            luminanceCache.setObject(NSNumber(value: luminance), forKey: path as NSString)
        }
        return luminance * (1 - max(0, min(0.7, backdrop(thread).dim))) < 0.5 ? .dark : .light
    }
    func setBackdrop(_ options: BackdropOptions, thread: String) { if data.backdropOptions == nil { data.backdropOptions = [:] }; data.backdropOptions?[thread] = options }
    func replaceBackground(_ file: String?, thread: String) { let old = data.backgrounds[thread]; data.backgrounds[thread] = file; if let old, old != file { pruneFiles([old]) }; persist() }

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
        guard raw.count <= 24 * 1024 * 1024, let source = CGImageSourceCreateWithData(raw as CFData, [kCGImageSourceShouldCache: false] as CFDictionary), let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1600, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw LocalError.message("无法读取这张照片，或图片超过 24 MB") }
        let scaled = UIImage(cgImage: thumbnail); let size = scaled.size
        guard let jpeg = scaled.jpegData(compressionQuality: 0.78), jpeg.count <= 2 * 1024 * 1024 else { throw LocalError.message("照片压缩后仍超过 2 MB，请选择较小的图片") }
        let path = UUID().uuidString + ".jpg"; try jpeg.write(to: url(path), options: .atomic)
        imageCache.setObject(scaled, forKey: path as NSString, cost: Int(size.width * size.height * 4))
        return ChatAttachment(name: name, path: path, photo: true, bytes: jpeg.count)
    }
    func saveFile(_ source: URL) throws -> ChatAttachment {
        let access = source.startAccessingSecurityScopedResource(); defer { if access { source.stopAccessingSecurityScopedResource() } }
        let ext = String(source.pathExtension.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(12))
        let path = UUID().uuidString + (ext.isEmpty ? "" : "." + ext)
        if (try? source.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true { try? FileManager.default.startDownloadingUbiquitousItem(at: source) }
        var coordinationError: NSError?; var readError: Error?; var bytes = 0
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { available in
            do {
                let values = try available.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= 20 * 1024 * 1024 else { throw LocalError.message("请选择不超过 20 MB 的完整文件") }
                try FileManager.default.copyItem(at: available, to: url(path)); bytes = size
            } catch { readError = error }
        }
        if let error = coordinationError { throw error }; if let error = readError { throw error }
        return ChatAttachment(name: source.lastPathComponent, path: path, photo: false, bytes: bytes)
    }
    func importFont(_ source: URL) throws {
        guard ["ttf", "otf"].contains(source.pathExtension.lowercased()) else { throw LocalError.message("原生字体支持 TTF 或 OTF 文件") }
        guard data.preferences.fonts.count < 6 else { throw LocalError.message("最多添加 6 款字体，请先移除一款") }
        let file = try saveFile(source)
        var keep = false; defer { if !keep { try? FileManager.default.removeItem(at: url(file.path)) } }
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url(file.path) as CFURL) as? [CTFontDescriptor], let descriptor = descriptors.first else { throw LocalError.message("无法读取字体，请选择完整的 TTF 或 OTF 文件") }
        let font = CTFontCreateWithFontDescriptor(descriptor, 16, nil)
        let entry = UserFont(label: source.deletingPathExtension().lastPathComponent, postScriptName: CTFontCopyPostScriptName(font) as String, path: file.path)
        if let existing = data.preferences.fonts.first(where: { $0.postScriptName == entry.postScriptName }) { data.preferences.selectedFont = existing.id; data.preferences.typography = "custom"; notice("已应用已导入的字体", success: true); return }
        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url(file.path) as CFURL, .process, &error)
        if !registered { let detail = error?.takeRetainedValue(); guard detail.map({ CFErrorGetCode($0) == CTFontManagerError.alreadyRegistered.rawValue }) == true, UIFont(name: entry.postScriptName, size: 16) != nil else { throw LocalError.message("系统无法注册此字体，请检查字体文件是否完整") } }
        keep = true
        data.preferences.fonts.append(entry); data.preferences.selectedFont = entry.id; data.preferences.typography = "custom"
        notice("已应用字体", success: true)
    }
    func removeFont(_ entry: UserFont) {
        if data.preferences.selectedFont == entry.id { data.preferences.typography = "native"; data.preferences.selectedFont = nil }
        data.preferences.fonts.removeAll { $0.id == entry.id }
        CTFontManagerUnregisterFontsForURL(url(entry.path) as CFURL, .process, nil)
        try? FileManager.default.removeItem(at: url(entry.path)); persist()
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
        let originalFiles = editing.flatMap { id in data.messages[thread]?.first(where: { $0.id == id })?.attachments } ?? []
        let message = ChatMessage(author: "me", text: String(text.prefix(10000)), attachments: attachments.isEmpty ? originalFiles : attachments, status: "sending", recipients: targets, edited: editing != nil)
        data.messages[thread, default: []].append(message)
        data.drafts[thread] = ""
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #if DEBUG
        if testMode && ProcessInfo.processInfo.arguments.contains("--uitest-replies") {
            if let index = data.messages[thread]?.indices.last { data.messages[thread]![index].status = "delivered" }
            let reply = ChatMessage(author: "gpt", text: "", status: "replying")
            data.messages[thread, default: []].append(reply)
            if ProcessInfo.processInfo.arguments.contains("--uitest-hold-replies") { return }
            Task { @MainActor in
                for line in 0..<18 {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    guard let index = data.messages[thread]?.firstIndex(where: { $0.id == reply.id }) else { return }
                    data.messages[thread]![index].text += "Streaming line \(line)\n"
                }
                if let index = data.messages[thread]?.firstIndex(where: { $0.id == reply.id }) { data.messages[thread]![index].text += "Stream reply complete"; data.messages[thread]![index].status = "received" }
            }
            return
        }
        #endif
        relay.enqueue(message, thread: thread)
    }
    func selection(thread: String, provider: String = "gpt") -> ModelSelection { data.routes?[thread + ":" + provider] ?? ModelSelection() }
    func select(_ choice: ModelChoice, thread: String, provider: String = "gpt") {
        let previous = selection(thread: thread, provider: provider)
        let effort = previous.source == choice.source && previous.model == choice.model && choice.efforts.contains(previous.effort ?? "") ? previous.effort : nil
        if data.routes == nil { data.routes = [:] }; data.routes?[thread + ":" + provider] = ModelSelection(source: choice.source, model: choice.model, effort: effort); persist()
    }
    func selectEffort(_ effort: String?, thread: String, provider: String = "gpt") {
        var selected = selection(thread: thread, provider: provider)
        let choice = ModelChoice.ordered(relay.modelChoices).first { $0.source == selected.source && (selected.model == nil || $0.model == selected.model) }
        if let effort { guard choice?.availableEfforts.contains(effort) == true else { notice("这个模型未提供所选强度"); return }; if selected.model == nil { selected.model = choice?.model } }
        selected.effort = effort
        if data.routes == nil { data.routes = [:] }; data.routes?[thread + ":" + provider] = selected; persist()
    }
    func reconcileReminders() { Task { await notifications.syncReminders(data.ideas) } }
    func toggleIdea(_ id: UUID) { if let i = data.ideas.firstIndex(where: { $0.id == id }) { data.ideas[i].task = true; data.ideas[i].done.toggle(); reconcileReminders(); UISelectionFeedbackGenerator().selectionChanged() } }
    func retry(_ thread: String, id: UUID) { guard let i = data.messages[thread]?.firstIndex(where: { $0.id == id }) else { return }; if let job = data.messages[thread]![i].bridgeJob { relay.retryJob(job) } else { data.messages[thread]![i].status = "sending"; data.messages[thread]![i].bridgeError = nil; relay.enqueue(data.messages[thread]![i], thread: thread) } }
    func isReplying(_ thread: String) -> Bool {
        #if DEBUG
        if testMode && ProcessInfo.processInfo.arguments.contains("--uitest-replies") { return data.messages[thread]?.contains(where: { $0.status == "replying" }) == true }
        #endif
        return relay.isReplying(thread)
    }
    func stopReplies(_ thread: String) { relay.stop(thread) }
    func saveIdea(_ idea: Idea) {
        var item = idea; item.text = item.text.trimmingCharacters(in: .whitespacesAndNewlines); guard !item.text.isEmpty else { return }
        if let i = data.ideas.firstIndex(where: { $0.id == item.id }) { data.ideas[i] = item } else { data.ideas.insert(item, at: 0) }
        persist(); reconcileReminders(); notice("已保存想法", success: true)
    }
    func deleteIdea(_ id: UUID) { data.ideas.removeAll { $0.id == id }; notifications.removeReminder(id); reconcileReminders() }
    func setReminder(_ idea: Idea) async {
        guard let date = idea.reminder, date > Date() else { notice("请选择将来的提醒时间"); return }
        let granted = await notifications.authorize()
        saveIdea(idea)
        guard granted else { notice("提醒已记录，系统通知尚未允许"); return }
        await notifications.syncReminders(data.ideas)
        notice("已设置提醒", success: true)
    }
    func removeChatHistory(_ channels: [String]) {
        let removed = channels.flatMap { data.messages[$0] ?? [] }.flatMap(\.attachments).map(\.path)
        for channel in channels { data.messages[channel] = [] }
        for key in Array(data.personas.keys) { if var persona = data.personas[key] { persona.memories = persona.memories.map { item in var updated = item; if let thread = item.thread, channels.contains(thread) { updated.thread = nil; updated.message = nil }; return updated }; data.personas[key] = persona } }
        notifications.clearReplies(channels)
        pruneFiles(removed)
        persist()
    }
    private func pruneFiles(_ candidates: [String]) {
        let retained = Set(data.messages.values.flatMap { $0 }.flatMap(\.attachments).map(\.path) + (data.draftAttachments ?? [:]).values.flatMap { $0 }.map(\.path) + data.people.values.compactMap(\.avatar) + Array(data.backgrounds.values) + data.preferences.fonts.map(\.path))
        for path in Set(candidates).subtracting(retained) where !path.contains("/") && !path.contains("\\") { imageCache.removeObject(forKey: path as NSString); luminanceCache.removeObject(forKey: path as NSString); try? FileManager.default.removeItem(at: url(path)) }
    }
    func setDraftAttachments(_ files: [ChatAttachment], thread: String) { let old = data.draftAttachments?[thread] ?? []; if data.draftAttachments == nil { data.draftAttachments = [:] }; data.draftAttachments?[thread] = files; pruneFiles(old.map(\.path)); }
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


}
enum LocalError: LocalizedError { case message(String); var errorDescription: String? { if case let .message(text) = self { return text }; return nil } }
extension UIColor { convenience init(hex: String) { let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0; self.init(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1) } }
