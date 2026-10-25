import Foundation
import SwiftUI
import Security

private final class RelaySessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
struct RelayPairing { var url: String; var token: String }
@MainActor
final class NativeRelay: ObservableObject {
    @Published var state = "未连接" { didSet { store?.objectWillChange.send() } }
    @Published var connected = false
    @Published var agents: [String: Bool] = [:]
    @Published var pendingPairing: RelayPairing? = nil
    private weak var store: NativeStore?
    private var task: URLSessionWebSocketTask?
    private let delegate = RelaySessionDelegate()
    private lazy var session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
    private var receiver: Task<Void, Never>?
    private var reconnect: Task<Void, Never>?
    private var outbox: [String: Data] = [:]
    private var jobs: [String: [String: Any]] = [:]
    private var wanted = false
    private var generation = UUID()
    private var retryDelay: UInt64 = 1
    var address: String { UserDefaults.standard.string(forKey: "duet.bridge.url.v1") ?? "" }
    var token: String { (try? Self.readToken()) ?? "" }
    var configured: Bool { !address.isEmpty && !token.isEmpty }
    init(store: NativeStore) {
        self.store = store
        if let raw = try? Data(contentsOf: store.directory.appendingPathComponent("bridge-outbox.json")), let saved = try? JSONDecoder().decode([String: Data].self, from: raw) { outbox = saved }
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
        let socket = session.webSocketTask(with: request); task = socket; state = "连接中"; socket.resume()
        receiver = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard let self, self.generation == ticket else { return }
                    let data: Data
                    switch message { case .data(let raw): data = raw; case .string(let text): data = Data(text.utf8); @unknown default: continue }
                    guard data.count <= 1024 * 1024, let event = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                    self.receive(event)
                }
            } catch { guard let self, self.generation == ticket else { return }; self.connectionLost() }
        }
    }
    func disconnect() { wanted = false; generation = UUID(); reconnect?.cancel(); receiver?.cancel(); task?.cancel(with: .goingAway, reason: nil); task = nil; connected = false; state = "未连接"; agents = [:] }
    private func connectionLost() {
        receiver?.cancel(); task?.cancel(with: .goingAway, reason: nil); task = nil; connected = false; state = "连接已断开，等待重连"
        guard wanted else { return }
        let seconds = retryDelay; retryDelay = min(30, retryDelay * 2)
        reconnect = Task { [weak self] in try? await Task.sleep(nanoseconds: seconds * 1_000_000_000); if !Task.isCancelled { self?.connect() } }
    }
    private func send(_ event: [String: Any]) { guard let raw = try? JSONSerialization.data(withJSONObject: event) else { return }; send(raw) }
    private func send(_ raw: Data) {
        guard connected, let task, let text = String(data: raw, encoding: .utf8) else { return }
        let ticket = generation
        Task { [weak self] in do { try await task.send(.string(text)) } catch { if self?.generation == ticket { self?.connectionLost() } } }
    }
    private func saveOutbox() throws { guard let store else { return }; try JSONEncoder().encode(outbox).write(to: store.directory.appendingPathComponent("bridge-outbox.json"), options: .atomic) }
    func enqueue(_ message: ChatMessage, thread: String) {
        guard let store else { return }
        guard message.attachments.isEmpty else { failLocal(message.id, thread: thread, reason: "消息桥当前只支持文字，照片和文件稍后接入"); return }
        guard configured else { failLocal(message.id, thread: thread, reason: "请先在设置里连接电脑消息桥"); return }
        let key = message.id.uuidString.lowercased()
        do {
            if outbox[key] == nil {
                var partners: [String: Any] = [:]
                for id in ["gpt", "claude"] {
                    let persona = store.data.personas[id] ?? Persona()
                    partners[id] = ["name": store.name(id), "role": [persona.identity, persona.values, persona.relationship, persona.voice].filter { !$0.isEmpty }.joined(separator: "\n"), "memories": persona.memories.map { ["text": $0.text, "group": $0.group] as [String: Any] }]
                }
                let payload: [String: Any] = ["type": "message", "id": key, "channel": thread, "text": message.text, "recipients": message.recipients, "context": ["viewerName": store.name("self"), "partners": partners, "autoDiscuss": store.data.preferences.autoDiscuss]]
                let raw = try JSONSerialization.data(withJSONObject: payload)
                guard raw.count < 60000 else { throw LocalError.message("本次角色或记忆内容过长，请精简后重试") }
                outbox[key] = raw
            }
            try saveOutbox(); store.persist()
            if connected, let raw = outbox[key] { send(raw) } else { connect() }
        } catch { outbox.removeValue(forKey: key); failLocal(message.id, thread: thread, reason: error.localizedDescription) }
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
            connected = true; state = "已连接电脑"; retryDelay = 1
            send(["type": "status"])
            for raw in outbox.values { send(raw) }
        case "status":
            let values = event["agents"] as? [String: [String: Any]] ?? [:]
            agents = values.mapValues { ($0["connected"] as? Bool) == true }; state = agents["gpt"] == true ? "GPT 已连接" : "电脑已连接，GPT 待登录"
        case "history":
            guard let channel = event["channel"] as? String else { return }
            for message in event["messages"] as? [[String: Any]] ?? [] { upsert(message, thread: channel) }
            for job in event["jobs"] as? [[String: Any]] ?? [] { updateJob(job) }
        case "ack":
            guard let id = event["id"] as? String, let uuid = UUID(uuidString: id), let channel = event["channel"] as? String, let store else { return }
            if let i = store.data.messages[channel]?.firstIndex(where: { $0.id == uuid }) { store.data.messages[channel]![i].status = "delivered"; store.data.messages[channel]![i].bridgeError = nil }
            outbox.removeValue(forKey: id.lowercased()); try? saveOutbox(); store.persist()
        case "delta": if let message = event["message"] as? [String: Any], let channel = event["channel"] as? String { upsert(message, thread: channel) }
        case "reply.status": updateJob(event)
        case "reply.chunk":
            guard let job = event["id"] as? String, let channel = event["channel"] as? String, let chunk = event["text"] as? String, let store, let i = store.data.messages[channel]?.firstIndex(where: { $0.bridgeJob == job && $0.status == "replying" }) else { return }
            store.data.messages[channel]![i].text += chunk
        case "error": store?.notice(event["message"] as? String ?? "电脑消息桥返回了错误")
        default: break
        }
    }
    private func upsert(_ object: [String: Any], thread: String) {
        guard ["gpt", "claude", "group"].contains(thread), let store, let idText = object["id"] as? String, let id = UUID(uuidString: idText), let sender = object["sender"] as? String, ["user", "gpt", "claude"].contains(sender), let text = object["text"] as? String else { return }
        let author = sender == "user" ? "me" : sender
        let job = (object["replyTo"] as? String).map { $0.lowercased() + ":" + sender }
        let found = store.data.messages[thread]?.firstIndex(where: { $0.id == id || (job != nil && $0.bridgeJob == job) })
        let date = Date(timeIntervalSince1970: (object["time"] as? Double ?? Date.now.timeIntervalSince1970 * 1000) / 1000)
        var message = ChatMessage(id: id, author: author, text: text, date: date, status: author == "me" ? "delivered" : "received", demo: object["demo"] as? Bool ?? false)
        message.bridgeJob = job
        if let found { message.attachments = store.data.messages[thread]![found].attachments; store.data.messages[thread]![found] = message }
        else { store.data.messages[thread, default: []].append(message) }
    }
    private func updateJob(_ object: [String: Any]) {
        guard let id = object["id"] as? String, let thread = object["channel"] as? String, ["gpt", "claude", "group"].contains(thread), let author = object["provider"] as? String, ["gpt", "claude"].contains(author), let status = object["state"] as? String, let store else { return }
        jobs[id] = object; store.objectWillChange.send()
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
            HStack { Image(systemName: relay.connected ? "checkmark.circle" : "link").foregroundStyle(p.accent); Text(relay.state).font(store.font(14)); Spacer() }.padding(16).background(p.surface, in: RoundedRectangle(cornerRadius: 22))
            HStack(spacing: 12) { ForEach(["gpt", "claude"], id: \.self) { id in VStack(spacing: 10) { Avatar(id: id, size: 44); Text(store.name(id)).font(store.font(13, weight: .medium)); Text(relay.agents[id] == true ? "已连接" : "未连接").font(store.font(11)).foregroundStyle(p.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 18).background(p.surface, in: RoundedRectangle(cornerRadius: 22)) } }
            Text("电脑消息桥地址").font(store.font(11)).foregroundStyle(p.secondary)
            TextField("wss://…/ws", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().font(store.font(16)).padding(14).background(p.surface, in: RoundedRectangle(cornerRadius: 16)).accessibilityIdentifier("bridge.address")
            SecureField("电脑上的配对码", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled().font(store.font(16)).padding(14).background(p.surface, in: RoundedRectangle(cornerRadius: 16)).accessibilityIdentifier("bridge.token")
            Text("保存后，你发送的消息会交给这个地址对应的电脑。GPT 使用电脑上为 Duet 登录的 Codex 账号。").font(store.font(12)).foregroundStyle(p.secondary).lineSpacing(4)
            PrimaryAction(title: "保存并连接") { do { try relay.configure(address: address, token: token) } catch { store.notice(error.localizedDescription) } }.accessibilityIdentifier("bridge.connect")
            if relay.connected { Button("断开连接") { relay.disconnect() }.font(store.font(13)).frame(maxWidth: .infinity) }
            Text("当前先支持文字消息；Claude、照片和文件的真实收发尚未接入。配对码保存在本机钥匙串。").font(store.font(11)).foregroundStyle(p.secondary).lineSpacing(4)
        }.padding(20) }.background(p.background).foregroundStyle(p.foreground).sheetTitle("电脑连接").onAppear { address = relay.pendingPairing?.url ?? relay.address; token = relay.pendingPairing?.token ?? relay.token }
    }
}
