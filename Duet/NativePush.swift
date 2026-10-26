import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class NativePush: ObservableObject {
    static let shared = NativePush()
    @Published var status = "尚未注册"
    @Published var serverStatus = "等待电脑推送服务"
    var serverReady = false
    private weak var store: NativeStore?
    private var token: String?
    private var requested = false
    private var installationID: String {
        if let id = UserDefaults.standard.string(forKey: "duet.push.installation") { return id }
        let id = UUID().uuidString.lowercased(); UserDefaults.standard.set(id, forKey: "duet.push.installation"); return id
    }
    func install(_ store: NativeStore) { self.store = store }
    func register() {
        guard store?.testMode != true, !requested else { return }
        requested = true; status = "正在向 Apple 注册"
        UIApplication.shared.registerForRemoteNotifications()
    }
    func registered(_ bytes: Data) {
        token = bytes.map { String(format: "%02x", $0) }.joined()
        status = "设备注册成功"; store?.relay.registerPush()
    }
    func failed(_ error: Error) {
        requested = false; token = nil; serverReady = false
        let detail = (error as NSError).localizedDescription
        status = detail.contains("aps-environment") ? "当前签名未包含推送授权" : "注册未完成（\((error as NSError).code)）"
        serverStatus = "\(detail.prefix(200))"
    }
    func payload() -> [String: Any]? {
        guard let token, let store else { return nil }
        return ["type": "push.register", "installationId": installationID, "token": token, "topic": Bundle.main.bundleIdentifier ?? "app.duet.preview", "environment": environment(), "enabled": store.data.preferences.replyNotifications != false, "preview": store.data.preferences.notificationPreview != false, "names": ["gpt": store.name("gpt"), "claude": store.name("claude")]]
    }
    func received(_ event: [String: Any]) { serverReady = event["ready"] as? Bool == true; serverStatus = event["message"] as? String ?? (serverReady ? "远程推送已连接" : "电脑推送服务待配置") }
    private func environment() -> String {
        if let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"), let data = try? Data(contentsOf: url), let start = data.range(of: Data("<?xml".utf8)), let end = data.range(of: Data("</plist>".utf8)), start.lowerBound < end.upperBound, let profile = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil) as? [String: Any], let rights = profile["Entitlements"] as? [String: Any], let value = rights["aps-environment"] as? String { return value == "development" ? "sandbox" : "production" }
        return "production"
    }
}
