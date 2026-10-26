import Foundation
import SwiftUI
import UIKit
import Security

private final class RelaySessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
struct RelayPairing { var url: String; var token: String }
@MainActor
final class NativeRelay: ObservableObject {
    @Published var state = "未连接" { didSet { store?.objectWillChange.send() } }
    @Published var connected = false
    @Published var lastFailure: String? = nil
    @Published var agents: [String: Bool] = [:]
    @Published var agentKinds: [String: String] = [:]
    @Published var modelNames: [String: String] = [:]
    @Published var modelChoices: [ModelChoice] = []
    private var sourceConnections: [String: Bool] = [:]
    private var capabilities: [String: Any] = [:]
    @Published var pendingPairing: RelayPairing? = nil
    private weak var store: NativeStore?
    private var task: URLSessionWebSocketTask?
    private let delegate = RelaySessionDelegate()
    private lazy var session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    private var receiver: Task<Void, Never>?
    private var reconnect: Task<Void, Never>?
    private var outbox: [String: Data] = [:]
    private var clearIntents: [String: [String]] = [:]
    private var enqueueTickets: [String: UUID] = [:]
    private var pendingAssets: Set<String> = []
    private var enqueuing: Set<String> = []
    private var jobs: [String: [String: Any]] = [:]
    private var wanted = false
    private var generation = UUID()
    private var retryDelay: UInt64 = 1
    var address: String { UserDefaults.standard.string(forKey: "duet.bridge.url.v1") ?? "" }
    var token: String { (try? Self.readToken()) ?? "" }
    var configured: Bool { !address.isEmpty && !token.isEmpty }
    var ordinaryChat: Bool { agentKinds["gpt"] == "chatgpt-web" || agentKinds["gpt"] == "gpt-router" && sourceConnections["chatgpt-web"] == true }
    var connectionLabel: String {
        guard connected else { return "等待电脑连接" }
        if agentKinds["gpt"] == "gpt-router" { return "ChatGPT 网页 / Codex" }
        if ordinaryChat { return "ChatGPT 普通聊天网页" }
        if agentKinds["gpt"] == "codex-chatgpt" { return "Codex · Work/Codex 额度" }
        return "跟随电脑消息桥"
    }
    func modelLabel(_ provider: String, thread: String? = nil) -> String {
        guard connected else { return "等待电脑连接" }
        if provider == "gpt", let thread, let store {
            let selected = store.selection(thread: thread, provider: provider)
            if let choice = modelChoices.first(where: { $0.source == selected.source && (selected.model == nil || $0.model == selected.model) }) { return choice.name }
            if selected.source == "codex-chatgpt" { return "Codex · 默认模型" }
        }
        if let name = modelNames[provider], !name.isEmpty { return name }
        if provider == "claude" { return "尚未连接" }
        if ordinaryChat { return "普通聊天 · 等待网页连接器" }
        if agentKinds[provider] == "codex-chatgpt" { return "Codex · 账号默认模型" }
        return "跟随电脑"
    }
    func refreshStatus() { send(["type": "status"]) }
    func refreshModels() { if capabilities["models"] as? Bool == true { send(["type": "models"]) } }
    init(store: NativeStore) {
        self.store = store
        if let raw = try? Data(contentsOf: store.directory.appendingPathComponent("bridge-outbox.json")), let saved = try? JSONDecoder().decode([String: Data].self, from: raw) { outbox = saved }
        if let raw = try? Data(contentsOf: store.directory.appendingPathComponent("bridge-clear-outbox.json")), let saved = try? JSONDecoder().decode([String: [String]].self, from: raw) { clearIntents = saved }
    }
    private static func validAddress(_ raw: String) throws -> URL {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme?.lowercased() == "wss", url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { throw LocalError.message("请输入 wss:// 开头的电脑消息桥地址") }
        return url
    }
    func configure(address: String, token: String) throws {
        let url = try Self.validAddress(address)
        let clean = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 32 && clean.count <= 300 else { throw LocalError.message("配对码不完整，请重新从电脑复制") }
        try Self.saveToken(clean)
        UserDefaults.standard.set(url.absoluteString, forKey: "duet.bridge.url.v1")
        pendingPairing = nil; disconnect(); connect()
    }
    func stagePairing(_ url: URL) {
        guard url.scheme == "duet", url.host == "pair", let encoded = url.fragment, encoded.count < 3000 else { return }
        var base64 = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64), let object = try? JSONSerialization.jsonObject(with: data) as? [String: String], let address = object["url"], let token = object["token"], (try? Self.validAddress(address)) != nil, token.count >= 32 && token.count <= 300 else { return }
        pendingPairing = RelayPairing(url: address, token: token)
        store?.settingsPresented = true
    }
    func connect() {
        guard let store, !store.testMode, configured else { state = "未配置电脑连接"; return }
        wanted = true
        guard task == nil else { return }
        reconnect?.cancel(); let ticket = UUID(); generation = ticket
        guard let url = try? Self.validAddress(address) else { state = "连接地址无效"; return }
        var request = URLRequest(url: url); request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization"); request.timeoutInterval = 20
        let socket = session.webSocketTask(with: request); socket.maximumMessageSize = 24 * 1024 * 1024; task = socket; state = "连接中"; socket.resume()
        receiver = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard let self, self.generation == ticket else { return }
                    let data: Data
                    switch message { case .data(let raw): data = raw; case .string(let text): data = Data(text.utf8); @unknown default: continue }
                    guard data.count <= 24 * 1024 * 1024, let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    self.receive(event)
                }
            } catch { guard let self, self.generation == ticket else { return }; self.connectionLost(error) }
        }
    }
    func disconnect() { wanted = false; generation = UUID(); reconnect?.cancel(); receiver?.cancel(); task?.cancel(with: .goingAway, reason: nil); task = nil; connected = false; agents = [:]; agentKinds = [:]; modelNames = [:]; state = "未连接" }
    private func connectionLost(_ error: Error? = nil) {
        if let response = task?.response as? HTTPURLResponse, response.statusCode >= 400 {
            lastFailure = response.statusCode == 401 ? "配对码未通过验证，请重新扫码并保存连接。" : "服务器拒绝连接（HTTP \(response.statusCode)）。"
        } else if let error { lastFailure = "\(error.localizedDescription)（\((error as NSError).code)）" }
        pendingAssets.removeAll()
        receiver?.cancel(); task?.cancel(with: .goingAway, reason: nil); task = nil; connected = false; agents = [:]; modelNames = [:]; state = "连接已断开，等待重连"
        guard wanted else { return }
        let seconds = retryDelay; retryDelay = min(30, retryDelay * 2)
        reconnect = Task { [weak self] in try? await Task.sleep(nanoseconds: seconds * 1_000_000_000); if !Task.isCancelled { self?.connect() } }
    }
    private func send(_ event: [String: Any]) { guard let raw = try? JSONSerialization.data(withJSONObject: event) else { return }; send(raw) }
    private func send(_ raw: Data) {
        guard connected, let task, let text = String(data: raw, encoding: .utf8) else { return }
        let ticket = generation
        Task { [weak self] in do { try await task.send(.string(text)) } catch { if self?.generation == ticket { self?.connectionLost(error) } } }
    }
    private func saveOutbox() throws { guard let store else { return }; try JSONEncoder().encode(outbox).write(to: store.directory.appendingPathComponent("bridge-outbox.json"), options: .atomic) }
    private func saveClearIntents() throws { guard let store else { return }; try JSONEncoder().encode(clearIntents).write(to: store.directory.appendingPathComponent("bridge-clear-outbox.json"), options: .atomic) }
    private var clearingChannels: Set<String> { Set(clearIntents.values.flatMap { $0 }) }
    func isClearing(_ thread: String) -> Bool { clearingChannels.contains(thread) }
    private var hasWork: Bool { !outbox.isEmpty || !enqueuing.isEmpty || jobs.values.contains { ["queued", "thinking"].contains($0["state"] as? String ?? "") } }
    func sceneChanged(_ phase: ScenePhase) { if phase == .active { connect(); refreshStatus() } else if phase == .background && !hasWork { disconnect() } }
    func backgroundExpired() { if UIApplication.shared.applicationState != .active { disconnect(); store?.persist() } }
    private func finishBackgroundIfIdle() { if !hasWork { NativeBackground.shared.finish(success: true); if UIApplication.shared.applicationState == .background { disconnect() } } }
    func clearHistory(_ requested: [String]) {
        guard let store else { return }
        let channels = Array(Set(requested).intersection(["gpt", "claude", "group"]))
        guard !channels.isEmpty else { return }
        if connected && capabilities["historyClear"] as? Bool != true { store.notice("请先更新电脑消息桥，避免旧记录再次同步"); return }
        for channel in channels { enqueueTickets[channel] = UUID(); stop(channel) }
        let intent = UUID().uuidString.lowercased()
        if configured { clearIntents[intent] = channels }
        for (id, raw) in outbox { if let item = try? JSONSerialization.jsonObject(with: raw) as? [String: Any], channels.contains(item["channel"] as? String ?? "") { outbox.removeValue(forKey: id) } }
        jobs = jobs.filter { !channels.contains($0.value["channel"] as? String ?? "") }
        do { try saveClearIntents(); try saveOutbox() } catch { store.notice("清理尚未保存，请重试"); return }
        store.removeChatHistory(channels)
        if connected { send(["type": "history.clear", "id": intent, "channels": channels]) }
        else if configured { connect() }
        store.notice(connected || !configured ? "已清空聊天记录" : "已清空本机，重连后同步电脑")
        finishBackgroundIfIdle()
    }
    func enqueue(_ message: ChatMessage, thread: String) {
        guard let store else { return }
        guard !isClearing(thread) else { failLocal(message.id, thread: thread, reason: "正在同步清空记录，请稍后重试"); return }
        guard message.attachments.count <= 6, message.attachments.allSatisfy(\.photo) else { failLocal(message.id, thread: thread, reason: "每次最多发送 6 张照片；普通文件的 AI 收发尚未接入"); return }
        if !message.attachments.isEmpty && connected && capabilities["attachments"] as? Bool != true { failLocal(message.id, thread: thread, reason: "请先更新电脑消息桥以发送照片"); return }
        guard configured else { failLocal(message.id, thread: thread, reason: "请先在设置里连接电脑消息桥"); return }
        let key = message.id.uuidString.lowercased()
        if let raw = outbox[key] { if connected { send(raw) } else { connect() }; return }
        guard !enqueuing.contains(key) else { return }; enqueuing.insert(key)
        if enqueueTickets[thread] == nil { enqueueTickets[thread] = UUID() }; let ticket = enqueueTickets[thread]
        NativeBackground.shared.begin()
        if store.data.preferences.replyNotifications != false { Task { _ = await store.notifications.authorize() } }
        Task {
          defer { enqueuing.remove(key); finishBackgroundIfIdle() }
          do {
            if outbox[key] == nil {
                var partners: [String: Any] = [:]
                for id in ["gpt", "claude"] {
                    let persona = store.data.personas[id] ?? Persona()
                    partners[id] = ["name": store.name(id), "callName": persona.userCallName ?? "", "groupCallName": persona.groupCallName ?? "", "role": [persona.identity, persona.values, persona.relationship, persona.voice].filter { !$0.isEmpty }.joined(separator: "\n"), "memories": persona.memories.map { ["text": $0.text, "group": $0.group] as [String: Any] }]
                }
                let selected = store.selection(thread: thread)
                let payload: [String: Any] = ["type": "message", "id": key, "channel": thread, "text": message.text, "recipients": message.recipients, "context": ["viewerName": store.name("self"), "partners": partners, "autoDiscuss": store.data.preferences.autoDiscuss, "route": ["source": selected.source, "model": selected.model ?? ""]]]
                let paths = message.attachments.map { (id: $0.id.uuidString.lowercased(), name: $0.name, url: store.url($0.path)) }
                let raw = try await Task.detached(priority: .userInitiated) {
                    var encoded = payload
                    if !paths.isEmpty { encoded["attachments"] = try paths.map { file -> [String: Any] in let bytes = try Data(contentsOf: file.url); guard bytes.count <= 2 * 1024 * 1024 else { throw LocalError.message("单张照片不能超过 2 MB") }; return ["id": file.id, "name": file.name, "mime": "image/jpeg", "base64": bytes.base64EncodedString()] } }
                    return try JSONSerialization.data(withJSONObject: encoded)
                }.value
                guard ticket == enqueueTickets[thread] else { return }
                guard raw.count < 18 * 1024 * 1024 else { throw LocalError.message("照片或上下文过大，请减少照片后重试") }
                outbox[key] = raw
            }
            try saveOutbox(); store.persist()
            if connected, let raw = outbox[key] { send(raw) } else { connect() }
          } catch { outbox.removeValue(forKey: key); failLocal(message.id, thread: thread, reason: error.localizedDescription) }
        }
    }
    private func failLocal(_ id: UUID, thread: String, reason: String) {
        guard let store, let index = store.data.messages[thread]?.firstIndex(where: { $0.id == id }) else { return }
        store.data.messages[thread]![index].status = "failed"; store.data.messages[thread]![index].bridgeError = reason
    }
    func isReplying(_ thread: String) -> Bool { jobs.values.contains { ($0["channel"] as? String) == thread && ["queued", "thinking"].contains($0["state"] as? String ?? "") } }
    func stop(_ thread: String) { for job in jobs.values where (job["channel"] as? String) == thread && ["queued", "thinking"].contains(job["state"] as? String ?? "") { if let trigger = job["triggerId"] as? String { send(["type": "cancel", "triggerId": trigger]) } } }
    func retryJob(_ id: String) { guard connected else { store?.notice("请先连接电脑消息桥"); connect(); return }; send(["type": "retry", "id": id]) }
    private func receive(_ event: [String: Any]) {
        switch event["type"] as? String {
        case "ready":
            capabilities = event["capabilities"] as? [String: Any] ?? [:]
            let values = event["agents"] as? [String: [String: Any]] ?? [:]
            agentKinds = values.compactMapValues { $0["kind"] as? String }
            connected = true; state = "已连接电脑"; lastFailure = nil; retryDelay = 1
            send(["type": "status"])
            if capabilities["historyClear"] as? Bool == true { for (id, channels) in clearIntents { send(["type": "history.clear", "id": id, "channels": channels]) } }
            for raw in outbox.values { send(raw) }
        case "status":
            let values = event["agents"] as? [String: [String: Any]] ?? [:]
            agents = values.mapValues { ($0["connected"] as? Bool) == true }
            agentKinds = values.compactMapValues { $0["kind"] as? String }
            modelNames = values.compactMapValues { $0["model"] as? String }
            sourceConnections = Dictionary(uniqueKeysWithValues: ((values["gpt"]?["sources"] as? [[String: Any]]) ?? []).compactMap { value in guard let id = value["source"] as? String else { return nil }; return (id, value["connected"] as? Bool == true) })
            state = agents["gpt"] == true ? (ordinaryChat ? "普通 GPT 聊天已连接" : "GPT 已连接") : (ordinaryChat ? "电脑已连接，等待网页连接器" : "电脑已连接，GPT 待连接")
        case "history":
            guard let channel = event["channel"] as? String else { return }
            guard !clearingChannels.contains(channel) else { return }
            // Preview examples are not real conversation history. Keep actual sends and replies.
            store?.data.messages[channel]?.removeAll { $0.status == "sample" }
            for message in event["messages"] as? [[String: Any]] ?? [] { upsert(message, thread: channel) }
            for job in event["jobs"] as? [[String: Any]] ?? [] { updateJob(job) }
            store?.data.messages[channel]?.sort { $0.date < $1.date }
        case "models":
            modelChoices = (event["models"] as? [[String: Any]] ?? []).compactMap { item in guard let source = item["source"] as? String, ["chatgpt-web", "codex-chatgpt"].contains(source), let model = item["model"] as? String, let name = item["name"] as? String else { return nil }; return ModelChoice(source: source, model: model, name: name, effort: item["effort"] as? String, images: item["images"] as? Bool == true) }
            store?.objectWillChange.send()
        case "asset":
            guard let store, let asset = event["asset"] as? String, pendingAssets.remove(asset) != nil, let encoded = event["base64"] as? String, encoded.count <= 2_800_000, let bytes = Data(base64Encoded: encoded), bytes.count <= 2 * 1024 * 1024 else { return }
            let referenced = store.data.messages.filter { !clearingChannels.contains($0.key) }.values.flatMap { $0 }.flatMap(\.attachments).contains { $0.path == asset }
            if referenced, UIImage(data: bytes) != nil { try? bytes.write(to: store.url(asset), options: .atomic); store.objectWillChange.send() }
        case "history.cleared":
            let channels = (event["channels"] as? [String] ?? []).filter { ["gpt", "claude", "group"].contains($0) }
            if let id = event["id"] as? String { clearIntents.removeValue(forKey: id); try? saveClearIntents() }
            jobs = jobs.filter { !channels.contains($0.value["channel"] as? String ?? "") }; store?.removeChatHistory(channels)
        case "ack":
            guard let id = event["id"] as? String, let uuid = UUID(uuidString: id), let channel = event["channel"] as? String, let store else { return }
            if let i = store.data.messages[channel]?.firstIndex(where: { $0.id == uuid }) { store.data.messages[channel]![i].status = "delivered"; store.data.messages[channel]![i].bridgeError = nil }
            if event["cleared"] as? Bool == true { store.data.messages[channel]?.removeAll { $0.id == uuid } }
            outbox.removeValue(forKey: id.lowercased()); try? saveOutbox(); store.persist()
            NativeBackground.shared.progress(2)
        case "delta": if let message = event["message"] as? [String: Any], let channel = event["channel"] as? String, !clearingChannels.contains(channel) { upsert(message, thread: channel, notify: true) }
        case "reply.status": updateJob(event)
        case "reply.progress":
            if let id = event["id"] as? String, let channel = event["channel"] as? String, let text = event["message"] as? String, let store, let i = store.data.messages[channel]?.firstIndex(where: { $0.bridgeJob == id }) { store.data.messages[channel]![i].bridgeError = text }
        case "reply.chunk":
            guard let job = event["id"] as? String, let channel = event["channel"] as? String, let chunk = event["text"] as? String, let store, let i = store.data.messages[channel]?.firstIndex(where: { $0.bridgeJob == job && $0.status == "replying" }) else { return }
            store.data.messages[channel]![i].text += chunk
        case "error":
            let reason = event["message"] as? String ?? "电脑消息桥返回了错误"
            if let id = event["id"] as? String, let raw = outbox[id], let item = try? JSONSerialization.jsonObject(with: raw) as? [String: Any], let channel = item["channel"] as? String, let uuid = UUID(uuidString: id), event["code"] as? String != "INTERNAL_ERROR" { outbox.removeValue(forKey: id); try? saveOutbox(); failLocal(uuid, thread: channel, reason: reason) }
            store?.notice(reason)
        default: break
        }
    }
    private func upsert(_ object: [String: Any], thread: String, notify: Bool = false) {
        guard ["gpt", "claude", "group"].contains(thread), let store, let idText = object["id"] as? String, let id = UUID(uuidString: idText), let sender = object["sender"] as? String, ["user", "gpt", "claude"].contains(sender), let text = object["text"] as? String else { return }
        let author = sender == "user" ? "me" : sender
        let existed = store.data.messages[thread]?.contains(where: { $0.id == id }) == true
        let job = (object["replyTo"] as? String).map { $0.lowercased() + ":" + sender }
        let found = store.data.messages[thread]?.firstIndex(where: { $0.id == id || (job != nil && $0.bridgeJob == job) })
        let date = Date(timeIntervalSince1970: (object["time"] as? Double ?? Date.now.timeIntervalSince1970 * 1000) / 1000)
        var message = ChatMessage(id: id, author: author, text: text, date: date, status: author == "me" ? "delivered" : "received", demo: object["demo"] as? Bool ?? false)
        message.bridgeJob = job
        if let found { message.attachments = store.data.messages[thread]![found].attachments; store.data.messages[thread]![found] = message }
        else { store.data.messages[thread, default: []].append(message) }
        if message.attachments.isEmpty, let files = object["attachments"] as? [[String: Any]], let index = store.data.messages[thread]?.firstIndex(where: { $0.id == id }) {
            let restored: [ChatAttachment] = files.prefix(6).compactMap { file in
                guard let photoID = file["id"] as? String, let uuid = UUID(uuidString: photoID), let asset = file["asset"] as? String, asset.range(of: "^[0-9a-f-]{73}\\.(jpg|png)$", options: .regularExpression) != nil, let bytes = file["bytes"] as? Int, bytes <= 2 * 1024 * 1024 else { return nil }
                if !FileManager.default.fileExists(atPath: store.url(asset).path), pendingAssets.insert(asset).inserted { send(["type": "asset.get", "asset": asset]) }
                return ChatAttachment(id: uuid, name: file["name"] as? String ?? "照片", path: asset, photo: true, bytes: bytes)
            }
            store.data.messages[thread]![index].attachments = restored
        }
        if notify && !existed && author != "me" && !message.demo { store.notifications.reply(id: id.uuidString, thread: thread, name: store.name(author), text: text); NativeBackground.shared.progress(4) }
    }
    private func updateJob(_ object: [String: Any]) {
        guard let id = object["id"] as? String, let thread = object["channel"] as? String, ["gpt", "claude", "group"].contains(thread), let author = object["provider"] as? String, ["gpt", "claude"].contains(author), let status = object["state"] as? String, let store else { return }
        guard !clearingChannels.contains(thread) else { return }
        jobs[id] = object; store.objectWillChange.send()
        defer { finishBackgroundIfIdle() }
        if status == "thinking" { NativeBackground.shared.progress(3) }
        let i = store.data.messages[thread]?.firstIndex(where: { $0.bridgeJob == id })
        if status == "completed" {
            if let i, store.data.messages[thread]![i].status == "replying" { if store.data.messages[thread]![i].text.isEmpty { store.data.messages[thread]!.remove(at: i) } else { store.data.messages[thread]![i].status = "received" } }
            return
        }
        if status == "queued" || status == "thinking" {
            if let i { store.data.messages[thread]![i].status = "replying"; store.data.messages[thread]![i].text = ""; store.data.messages[thread]![i].bridgeError = nil }
            else { var message = ChatMessage(author: author, text: "", status: "replying", demo: object["demo"] as? Bool ?? false); message.bridgeJob = id; store.data.messages[thread, default: []].append(message) }
        } else if ["error", "cancelled", "interrupted"].contains(status) {
            let reason = (object["error"] as? [String: Any])?["message"] as? String ?? "回复没有完成，请稍后重试"
            if let i { store.data.messages[thread]![i].status = status == "cancelled" ? "stopped" : "failed"; store.data.messages[thread]![i].bridgeError = reason }
            else { var message = ChatMessage(author: author, text: "", status: status == "cancelled" ? "stopped" : "failed"); message.bridgeJob = id; message.bridgeError = reason; store.data.messages[thread, default: []].append(message) }
        }
    }
    private static var keychainQuery: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "app.duet.preview.bridge", kSecAttrAccount as String: "pairing-token"] }
    private static func readToken() throws -> String? { var query = keychainQuery; query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne; var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &result); if status == errSecItemNotFound { return nil }; guard status == errSecSuccess, let data = result as? Data else { throw LocalError.message("无法读取配对码") }; return String(data: data, encoding: .utf8) }
    private static func saveToken(_ token: String) throws { let values: [String: Any] = [kSecValueData as String: Data(token.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]; let status = SecItemUpdate(keychainQuery as CFDictionary, values as CFDictionary); if status == errSecItemNotFound { var entry = keychainQuery; values.forEach { entry[$0.key] = $0.value }; guard SecItemAdd(entry as CFDictionary, nil) == errSecSuccess else { throw LocalError.message("无法保存配对码") } } else if status != errSecSuccess { throw LocalError.message("无法保存配对码") } }
}

struct NativeBridgeSettings: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var relay: NativeRelay
    @State private var address = ""
    @State private var token = ""
    var body: some View {
        let p = Palette(store.data.preferences, scheme)
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            HStack { Image(systemName: relay.connected ? "checkmark.circle" : "link").foregroundStyle(p.accent); Text(relay.state).font(store.font(14)); Spacer() }.padding(16).background(p.surface, in: RoundedRectangle(cornerRadius: LayoutMetrics.card))
            if let failure = relay.lastFailure { Text(failure).font(store.font(12)).foregroundStyle(p.secondary).textSelection(.enabled) }
            LabeledContent("GPT 连接", value: relay.connectionLabel).font(store.font(12)).foregroundStyle(p.secondary)
            HStack(spacing: 12) { ForEach(["gpt", "claude"], id: \.self) { id in VStack(spacing: 10) { Avatar(id: id, size: 44); Text(store.name(id)).font(store.font(13, weight: .medium)); Text(relay.agents[id] == true ? "已连接" : "未连接").font(store.font(11)).foregroundStyle(p.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 18).background(p.surface, in: RoundedRectangle(cornerRadius: LayoutMetrics.card)) } }
            Text("电脑消息桥地址").font(store.font(11)).foregroundStyle(p.secondary)
            TextField("wss://…/ws", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().font(store.font(16)).padding(14).background(p.surface, in: RoundedRectangle(cornerRadius: LayoutMetrics.field)).accessibilityIdentifier("bridge.address")
            SecureField("电脑上的配对码", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled().font(store.font(16)).padding(14).background(p.surface, in: RoundedRectangle(cornerRadius: LayoutMetrics.field)).accessibilityIdentifier("bridge.token")
            Text("保存后，你发送的消息会交给这个地址对应的电脑。普通聊天由电脑上的 Duet 网页连接器发送到已登录的 ChatGPT；当前连接方式以上方状态为准。").font(store.font(12)).foregroundStyle(p.secondary).lineSpacing(4)
            PrimaryAction(title: "保存并连接") { do { try relay.configure(address: address, token: token) } catch { store.notice(error.localizedDescription) } }.accessibilityIdentifier("bridge.connect")
            if relay.connected { Button("断开连接") { relay.disconnect() }.font(store.font(13)).frame(maxWidth: .infinity) }
            Text("支持普通聊天与单独选择的 Codex 模型、每次最多 6 张照片。照片仍待本机实测；Claude 与普通文件的 AI 收发尚未接入。配对码保存在本机钥匙串。").font(store.font(11)).foregroundStyle(p.secondary).lineSpacing(4)
        }.padding(20) }.background(p.background).foregroundStyle(p.foreground).sheetTitle("电脑连接").onAppear { address = relay.pendingPairing?.url ?? relay.address; token = relay.pendingPairing?.token ?? relay.token; relay.refreshStatus() }.onChange(of: relay.pendingPairing?.url) { _, value in if let value, let pairing = relay.pendingPairing { address = value; token = pairing.token } }
    }
}
