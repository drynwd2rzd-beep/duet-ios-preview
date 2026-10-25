import SwiftUI
import UIKit
import WebKit

@main
struct DuetApp: App {
    @StateObject private var model = DuetModel()

    var body: some Scene {
        WindowGroup {
            DuetRoot(model: model)
                .preferredColorScheme(model.appearance)
        }
    }
}

struct DuetRoot: View {
    @ObservedObject var model: DuetModel

    var body: some View {
        ZStack(alignment: .bottom) {
            model.background.ignoresSafeArea()
            DuetWebView(model: model)
                .ignoresSafeArea(.container, edges: .bottom)
            if model.showDock && model.ready {
                nativeDock.padding(.bottom, 8)
            }
            if !model.ready && model.loadError == nil {
                VStack(spacing: 14) {
                    Text("Duet").font(.system(size: 30, weight: .medium, design: .serif))
                    ProgressView().tint(model.accent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(model.background)
            }
            if let error = model.loadError {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.clockwise").font(.title)
                    Text("页面暂时没有打开").font(.headline)
                    Text(error).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("重新打开") { model.loadApp() }.buttonStyle(.borderedProminent)
                }
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(model.background)
            }
        }
        .tint(model.accent)
        .fullScreenCover(isPresented: $model.showCamera) {
            NativeCamera { image in
                model.showCamera = false
                if let data = image?.jpegData(compressionQuality: 0.86) {
                    model.command(["action": "camera-photo", "url": "data:image/jpeg;base64," + data.base64EncodedString()])
                }
            }
            .ignoresSafeArea()
        }
        .alert("相机暂时不可用", isPresented: $model.cameraUnavailable) {
            Button("知道了", role: .cancel) { }
        } message: {
            Text("请检查设备相机和系统权限，也可以在聊天加号菜单中选择照片。")
        }
    }

    @ViewBuilder
    private var nativeDock: some View {
        if #available(iOS 26.0, *) {
            dockContent.glassEffect(.regular, in: .capsule)
        } else {
            dockContent.background(.ultraThinMaterial, in: Capsule())
        }
    }

    private var dockContent: some View {
        HStack(spacing: 4) {
            tab("chats", symbol: "bubble.left", label: "聊天")
            tab("ideas", symbol: "lightbulb", label: "想法")
        }
        .padding(5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("主导航")
    }

    private func tab(_ id: String, symbol: String, label: String) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            model.command(["action": "tab", "tab": id])
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .regular))
                .frame(width: 72, height: 44)
                .foregroundStyle(model.page == id ? model.accent : Color.secondary)
                .background {
                    if model.page == id {
                        Capsule().fill(model.accent.opacity(0.12))
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(model.page == id ? .isSelected : [])
    }
}

struct DuetWebView: UIViewRepresentable {
    @ObservedObject var model: DuetModel
    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
}

@MainActor
final class DuetModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    @Published var page = "chats"
    @Published var showDock = false
    @Published var ready = false
    @Published var background = Color(red: 252 / 255, green: 250 / 255, blue: 251 / 255)
    @Published var accent = Color(red: 154 / 255, green: 100 / 255, blue: 124 / 255)
    @Published var appearance: ColorScheme?
    @Published var loadError: String?
    @Published var showCamera = false
    @Published var cameraUnavailable = false
    private let stateKey = "duet.preview.preferences.v1"
    private var lastHaptic = Date.distantPast

    lazy var webView: WKWebView = makeWebView()

    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        let controller = WKUserContentController()
        controller.add(ScriptProxy(owner: self), name: "duet")
        if let data = UserDefaults.standard.data(forKey: stateKey),
           let text = String(data: data, encoding: .utf8),
           (try? JSONSerialization.jsonObject(with: data)) != nil {
            controller.addUserScript(WKUserScript(source: "window.duetInitialState = " + text + ";", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        config.userContentController = controller
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.scrollView.isScrollEnabled = false
        view.allowsBackForwardNavigationGestures = false
        view.scrollView.keyboardDismissMode = .interactive
        DispatchQueue.main.async { [weak self] in self?.loadApp() }
        return view
    }

    func loadApp() {
        ready = false
        loadError = nil
        guard let file = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Web") else {
            loadError = "安装包中的界面文件缺失。"
            return
        }
        webView.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
    }

    func command(_ command: [String: String]) {
        guard let data = try? JSONSerialization.data(withJSONObject: command),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.dispatchEvent(new CustomEvent('duet:native-command', {detail: " + json + "}));") { _, error in
            if let error { NSLog("Duet command failed: %@", error.localizedDescription) }
        }
    }

    func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              message.frameInfo.request.url?.isFileURL == true,
              let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "shell":
            let screen = body["screen"] as? String ?? "conversation"
            page = body["page"] as? String == "ideas" ? "ideas" : "chats"
            showDock = ["chats", "ideas"].contains(screen) && (body["modal"] as? Bool != true)
            appearance = body["viewer"] as? Bool == true ? .dark : (body["appearance"] as? String) == "dark" ? .dark : (body["appearance"] as? String) == "light" ? .light : nil
            if let color = Self.color(body["background"]) { background = color }
            if let color = Self.color(body["accent"]) { accent = color }
            ready = true
        case "persist":
            guard let value = body["snapshot"] as? [String: Any], JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value), data.count <= 16 * 1024 else { return }
            UserDefaults.standard.set(data, forKey: stateKey)
        case "haptic":
            guard Date().timeIntervalSince(lastHaptic) > 0.08 else { return }
            lastHaptic = Date()
            switch body["style"] as? String {
            case "success": UINotificationFeedbackGenerator().notificationOccurred(.success)
            case "selection": UISelectionFeedbackGenerator().selectionChanged()
            default: UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.65)
            }
        case "camera":
            if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true }
            else { cameraUnavailable = true }
        default: break
        }
    }

    private static func color(_ value: Any?) -> Color? {
        guard let values = value as? [Double], values.count == 3,
              values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        return Color(red: values[0], green: values[1], blue: values[2])
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("window.dispatchEvent(new Event('duet:native-ready'));")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loadError = error.localizedDescription }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { loadError = error.localizedDescription }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { loadApp() }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.isFileURL,
           let webRoot = Bundle.main.url(forResource: "Web", withExtension: nil),
           url.standardizedFileURL.path.hasPrefix(webRoot.standardizedFileURL.path + "/") {
            decisionHandler(.allow)
        } else if url.absoluteString == "about:blank" { decisionHandler(.allow) }
        else { decisionHandler(.cancel) }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(frame.isMainFrame && frame.request.url?.isFileURL == true && type == .camera ? .prompt : .deny)
    }
}

@MainActor
private final class ScriptProxy: NSObject, WKScriptMessageHandler {
    weak var owner: DuetModel?
    init(owner: DuetModel) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.receive(message) }
}

struct NativeCamera: UIViewControllerRepresentable {
    let finished: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let finished: (UIImage?) -> Void
        init(finished: @escaping (UIImage?) -> Void) { self.finished = finished }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { finished(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { finished(info[.originalImage] as? UIImage) }
    }
}
