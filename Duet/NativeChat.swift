import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import AVFoundation
import QuickLook

struct GalleryRequest: Identifiable { var id = UUID(); var photos: [ChatAttachment]; var index: Int }
struct DocumentRequest: Identifiable { var id = UUID(); var url: URL }
struct MemoryRequest: Identifiable { var id = UUID(); var provider: String; var memory: Memory }

struct NativeChat: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let thread: String
    @State private var text = ""
    @State private var attachments: [ChatAttachment] = []
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var filesPresented = false
    @State private var cameraPresented = false
    @State private var cameraUnavailable = false
    @State private var infoPresented = false
    @State private var gallery: GalleryRequest? = nil
    @State private var document: DocumentRequest? = nil
    @State private var idea: Idea? = nil
    @State private var memory: MemoryRequest? = nil
    @State private var memoryMessage: ChatMessage? = nil
    @State private var editing: UUID? = nil
    @State private var showSearch = false
    @State private var query = ""
    @State private var searchKind = "全部"
    @State private var filterDate = false
    @State private var selectedDate = Date()
    @State private var searchIndex = 0
    @FocusState private var inputFocused: Bool
    private var p: Palette { Palette(store.data.preferences, scheme) }
    private var messages: [ChatMessage] { store.data.messages[thread] ?? [] }
    private var filtering: Bool { showSearch && (!query.isEmpty || searchKind != "全部" || filterDate) }
    private var visibleMessages: [ChatMessage] {
        guard filtering else { return messages }
        return messages.filter { message in
            if searchKind == "照片" && !message.attachments.contains(where: \.photo) { return false }
            if searchKind == "文件" && !message.attachments.contains(where: { !$0.photo }) { return false }
            if searchKind == "文字" && message.text.isEmpty { return false }
            if filterDate && !Calendar.current.isDate(message.date, inSameDayAs: selectedDate) { return false }
            return query.isEmpty || (message.text + " " + message.attachments.map(\.name).joined(separator: " ")).localizedCaseInsensitiveContains(query)
        }
    }
    private var mentionQuery: String? {
        guard thread == "group", let range = text.range(of: "@", options: .backwards) else { return nil }
        let suffix = String(text[range.upperBound...]); return suffix.contains(where: \.isWhitespace) || suffix.count > 24 ? nil : suffix
    }
    private var mentionChoices: [String] { guard let query = mentionQuery else { return [] }; return ["gpt", "claude", "all"].filter { query.isEmpty || ($0 == "all" ? "所有人" : store.name($0)).localizedCaseInsensitiveContains(query) } }

    var body: some View {
        ZStack {
            p.background.ignoresSafeArea()
            if let file = store.data.backgrounds[thread], let image = store.image(file) { Image(uiImage: image).resizable().scaledToFill().opacity(p.dark ? 0.22 : 0.3).ignoresSafeArea().allowsHitTesting(false) }
            chatScroll
        }
        .clipped()
        .foregroundStyle(p.foreground)
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { VStack(spacing: 4) { Avatar(id: thread, size: thread == "group" ? 36 : 32); Text(store.name(thread)).font(store.font(12, weight: .medium)).lineLimit(1) }.accessibilityIdentifier("chat.identity") }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { withAnimation { showSearch.toggle() }; if !showSearch { query = ""; searchKind = "全部"; filterDate = false } } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("搜索聊天").accessibilityIdentifier("chat.search")
                Button { inputFocused = false; infoPresented = true } label: { Image(systemName: "ellipsis") }.accessibilityLabel("会话选项").accessibilityIdentifier("chat.options")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { if showSearch { searchControls } }
        .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .onAppear { text = store.data.drafts[thread] ?? "" }
        .onDisappear { store.data.drafts[thread] = text; store.persist() }
        .onChange(of: text) { _, value in store.data.drafts[thread] = value }
        .onChange(of: photoSelection) { _, items in Task { for item in items { do { if let data = try await item.loadTransferable(type: Data.self), attachments.count < 8 { attachments.append(try store.savePhoto(data)) } } catch { store.notice(error.localizedDescription) } }; photoSelection = [] } }
        .fileImporter(isPresented: $filesPresented, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in do { for url in try result.get().prefix(max(0, 8 - attachments.count)) { attachments.append(try store.saveFile(url)) } } catch { store.notice(error.localizedDescription) } }
        .sheet(isPresented: $infoPresented) { ConversationInfo(thread: thread).environmentObject(store) }
        .sheet(item: $idea) { IdeaEditor(idea: $0).environmentObject(store) }
        .sheet(item: $document) { FilePreview(url: $0.url).ignoresSafeArea() }
        .sheet(item: $memory) { request in MemoryEditor(provider: request.provider, memory: request.memory).environmentObject(store) }
        .fullScreenCover(item: $gallery) { request in NativeGallery(photos: request.photos, index: request.index).environmentObject(store) }
        .fullScreenCover(isPresented: $cameraPresented) { NativeCamera { image in cameraPresented = false; if let image, let data = image.jpegData(compressionQuality: 0.9) { do { attachments.append(try store.savePhoto(data, name: "拍摄的照片.jpg")) } catch { store.notice(error.localizedDescription) } } }.ignoresSafeArea() }
        .alert("相机暂时不可用", isPresented: $cameraUnavailable) { Button("知道了", role: .cancel) { } } message: { Text("请检查系统相机权限，或从照片中选择图片。") }
        .confirmationDialog("保存给哪位伙伴", isPresented: Binding(get: { memoryMessage != nil }, set: { if !$0 { memoryMessage = nil } })) { ForEach(["gpt", "claude"], id: \.self) { id in Button(store.name(id)) { if let message = memoryMessage { saveMemory(message, provider: id) }; memoryMessage = nil } } }
    }

    private var chatScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 17) {
                    if visibleMessages.isEmpty { QuietEmpty(icon: filtering ? "magnifyingglass" : "bubble.left", title: filtering ? "没有找到相关消息" : "从一句话开始", detail: filtering ? "换个关键词，或清除筛选。" : "和伙伴聊聊此刻的想法。") }
                    else {
                        Text("今天").font(store.font(11)).foregroundStyle(p.secondary).padding(.vertical, 8)
                        ForEach(Array(visibleMessages.enumerated()), id: \.element.id) { index, message in
                            MessageCell(message: message, showAuthor: index == 0 || visibleMessages[index - 1].author != message.author, thread: thread, onPhoto: { photos, index in inputFocused = false; gallery = GalleryRequest(photos: photos, index: index) }, onFile: { document = DocumentRequest(url: store.url($0.path)) }, onIdea: { idea = Idea(text: message.text) }, onMemory: { if message.author != "me" { saveMemory(message, provider: message.author) } else if thread != "group" { saveMemory(message, provider: thread) } else { memoryMessage = message } }, onEdit: { editing = message.id; text = message.text; inputFocused = true }).id(message.id)
                        }
                    }
                    Color.clear.frame(height: 1).id("chat.bottom")
                }.padding(.horizontal, 18).padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("chat.messages")
            .onChange(of: messages.count) { _, _ in if !filtering { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { proxy.scrollTo("chat.bottom", anchor: .bottom) } } }
            .onChange(of: searchIndex) { _, value in if !visibleMessages.isEmpty { proxy.scrollTo(visibleMessages[min(value, visibleMessages.count - 1)].id, anchor: .center) } }
            .onAppear { if let id = store.requestedMessage { proxy.scrollTo(id, anchor: .center); store.requestedMessage = nil } }
        }
    }
    private var searchControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(p.secondary); TextField("搜索聊天记录", text: $query).font(store.font(16)).accessibilityIdentifier("chat.search.input"); if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清除搜索") } }.padding(11).background(p.surface, in: RoundedRectangle(cornerRadius: 16))
            HStack(spacing: 9) {
                Picker("类型", selection: $searchKind) { ForEach(["全部", "文字", "照片", "文件"], id: \.self) { Text($0).tag($0) } }.labelsHidden().font(store.font(11))
                Button { filterDate.toggle() } label: { Image(systemName: "calendar").foregroundStyle(filterDate ? p.accent : p.secondary) }.accessibilityLabel("按日期筛选")
                if filterDate { DatePicker("日期", selection: $selectedDate, displayedComponents: .date).labelsHidden().datePickerStyle(.compact).font(store.font(11)) }
                Spacer(minLength: 0)
                Text(filtering ? "\(visibleMessages.count) 条" : "").font(store.font(11)).foregroundStyle(p.secondary)
                Button { searchIndex = max(0, searchIndex - 1) } label: { Image(systemName: "chevron.up") }.disabled(visibleMessages.isEmpty).accessibilityLabel("上一个结果")
                Button { searchIndex = min(max(0, visibleMessages.count - 1), searchIndex + 1) } label: { Image(systemName: "chevron.down") }.disabled(visibleMessages.isEmpty).accessibilityLabel("下一个结果")
            }.font(.system(size: 12))
        }.padding(.horizontal, 18).padding(.vertical, 10).background(p.background)
    }
    private var composer: some View {
        VStack(spacing: 9) {
            if !mentionChoices.isEmpty { HStack(spacing: 8) { ForEach(mentionChoices, id: \.self) { id in Button { chooseMention(id) } label: { HStack(spacing: 6) { if id != "all" { Avatar(id: id, size: 22) }; Text(id == "all" ? "所有人" : store.name(id)).font(store.font(12)) }.padding(.horizontal, 10).padding(.vertical, 8).background(p.surface, in: Capsule()) }.buttonStyle(.plain) }; Spacer(minLength: 0) }.padding(.horizontal, 14) }
            if !attachments.isEmpty { ScrollView(.horizontal) { HStack(spacing: 10) { ForEach(attachments) { item in ZStack(alignment: .topTrailing) { if item.photo, let image = store.image(item.path) { Image(uiImage: image).resizable().scaledToFill().frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 16)) } else { Label(item.name, systemImage: "doc").font(store.font(11)).lineLimit(2).frame(width: 120, height: 58).padding(7).background(p.surface, in: RoundedRectangle(cornerRadius: 16)) }; Button { attachments.removeAll { $0.id == item.id } } label: { Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.55)).font(.system(size: 20)) }.accessibilityLabel("移除附件") } } }.padding(.horizontal, 14) }.scrollIndicators(.hidden) }
            if editing != nil { HStack { Text("编辑消息").font(store.font(11)); Spacer(); Button { editing = nil; text = "" } label: { Image(systemName: "xmark") }.accessibilityLabel("取消编辑") }.foregroundStyle(p.secondary).padding(.horizontal, 18) }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button("相机", systemImage: "camera") { openCamera() }
                    PhotosPicker(selection: $photoSelection, maxSelectionCount: 8, matching: .images) { Label("照片", systemImage: "photo.on.rectangle") }
                    Button("文件", systemImage: "folder") { filesPresented = true }
                    Button("想法", systemImage: "lightbulb") { idea = Idea(text: text) }
                } label: { Image(systemName: "plus").font(.system(size: 21, weight: .regular)).frame(width: 44, height: 44).glassCircle() }.accessibilityLabel("添加内容").accessibilityIdentifier("message.attach")
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("发消息", text: $text, axis: .vertical).font(store.font(16)).lineLimit(1...5).padding(.vertical, 8).focused($inputFocused).accessibilityIdentifier("message.input")
                    if thread == "group" { Button { if !text.isEmpty && !text.hasSuffix(" ") { text += " " }; text += "@"; inputFocused = true } label: { Image(systemName: "at").font(.system(size: 18)).foregroundStyle(p.secondary).frame(width: 26, height: 36) }.accessibilityLabel("提及伙伴") }
                    Button { if store.replyingThread == thread { store.stopDemo() } else { send() } } label: { Image(systemName: store.replyingThread == thread ? "stop.fill" : "arrow.up").font(.system(size: 18, weight: .medium)).foregroundStyle(p.background).frame(width: 36, height: 36).background(p.accent.opacity(canSend ? 1 : 0.35), in: Circle()) }.disabled(!canSend).accessibilityLabel(store.replyingThread == thread ? "停止回复" : "发送消息").accessibilityIdentifier("message.send")
                }.padding(5).padding(.leading, 10).background(p.surface, in: RoundedRectangle(cornerRadius: 26))
            }.padding(.horizontal, 13)
        }.padding(.top, 10).padding(.bottom, 9).background(p.background.opacity(0.97))
    }
    private var canSend: Bool { store.replyingThread == thread || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty }
    private func send() { store.send(thread: thread, text: text, attachments: attachments, editing: editing); text = ""; attachments = []; editing = nil }
    private func chooseMention(_ id: String) { if let range = text.range(of: "@", options: .backwards) { text.replaceSubrange(range.lowerBound..., with: "@" + (id == "all" ? "所有人" : store.name(id)) + " ") }; inputFocused = true }
    private func saveMemory(_ message: ChatMessage, provider: String) { memory = MemoryRequest(provider: provider, memory: Memory(text: String(message.text.prefix(160)), thread: thread, message: message.id, date: message.date)) }
    private func openCamera() { inputFocused = false; Task { let available = UIImagePickerController.isSourceTypeAvailable(.camera); let granted = available ? await AVCaptureDevice.requestAccess(for: .video) : false; if granted { cameraPresented = true } else { cameraUnavailable = true } } }
}

struct MessageCell: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    let message: ChatMessage
    let showAuthor: Bool
    let thread: String
    var onPhoto: ([ChatAttachment], Int) -> Void
    var onFile: (ChatAttachment) -> Void
    var onIdea: () -> Void
    var onMemory: () -> Void
    var onEdit: () -> Void
    private var mine: Bool { message.author == "me" }
    private var p: Palette { Palette(store.data.preferences, scheme) }
    var body: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
            if showAuthor { HStack(spacing: 6) { if mine { Text(store.name("self")); Avatar(id: "self", size: 20) } else { BrandMark(id: message.author, size: 15); Text(store.name(message.author)); if message.demo { Text("交互演示").foregroundStyle(p.accent) } } }.font(store.font(11)).foregroundStyle(p.secondary).padding(.horizontal, 5) }
            if !message.attachments.filter(\.photo).isEmpty { NativePhotoStack(photos: message.attachments.filter(\.photo), open: onPhoto) }
            ForEach(message.attachments.filter { !$0.photo }) { file in Button { onFile(file) } label: { HStack(spacing: 10) { Image(systemName: "doc").font(.system(size: 23, weight: .light)).foregroundStyle(p.accent); VStack(alignment: .leading, spacing: 4) { Text(file.name).font(store.font(12)).lineLimit(2); Text(ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file)).font(store.font(11)).foregroundStyle(p.secondary) }; Spacer(minLength: 0) }.padding(13).frame(maxWidth: 245).background(p.surface, in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain) }
            if !message.text.isEmpty || message.status == "replying" {
                Group { if message.text.isEmpty { HStack(spacing: 5) { ForEach(0..<3) { _ in Circle().fill(p.secondary).frame(width: 5, height: 5) } }.frame(height: 18).accessibilityLabel("演示回复中") } else { Text(message.text).font(store.font(14)).lineSpacing(4).textSelection(.enabled).multilineTextAlignment(.leading) } }
                    .padding(.horizontal, 15).padding(.vertical, 11)
                    .background(mine ? p.mine : p.surface, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: mine ? 20 : 7, bottomTrailingRadius: mine ? 7 : 20, topTrailingRadius: 20))
                    .contextMenu { Button("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text; store.notice("已复制") }; if mine { Button("编辑并重发", systemImage: "square.and.pencil", action: onEdit) }; Button("保存为想法", systemImage: "lightbulb", action: onIdea); Button("加入伙伴记忆", systemImage: "note.text", action: onMemory) }
            }
            if ["sending", "failed", "replying", "stopped", "demo"].contains(message.status) { status }
        }.frame(maxWidth: min(UIScreen.main.bounds.width * 0.82, 380), alignment: mine ? .trailing : .leading).frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }
    private var status: some View {
        HStack(spacing: 6) {
            if message.status == "sending" { ProgressView().controlSize(.mini); Text("发送中") }
            if message.status == "failed" { Image(systemName: "exclamationmark.circle"); Text("未发送 · 账号未连接"); Button("重试") { store.retry(thread, id: message.id) }.foregroundStyle(p.accent) }
            if message.status == "replying" { Image(systemName: "ellipsis"); Text("演示回复中") }
            if message.status == "stopped" { Image(systemName: "pause"); Text("已停止演示") }
            if message.status == "demo" { Image(systemName: "checkmark"); Text("演示结束") }
        }.font(store.font(11)).foregroundStyle(p.secondary).padding(.horizontal, 4)
    }
}

struct FilePreview: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url) }
    func makeUIViewController(context: Context) -> QLPreviewController { let controller = QLPreviewController(); controller.dataSource = context.coordinator; return controller }
    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) { }
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(_ url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
