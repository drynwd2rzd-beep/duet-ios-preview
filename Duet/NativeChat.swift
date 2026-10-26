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
    @Environment(\.dismiss) private var dismiss
    let thread: String
    @State private var text = ""
    @State private var attachments: [ChatAttachment] = []
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var photosPresented = false
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
    @State private var nearBottom = true
    @State private var followingLatest = true
    @State private var userScrolling = false
    @State private var importingPhotos = false
    @State private var photoImportTask: Task<Void, Never>? = nil
    @FocusState private var inputFocused: Bool
    private var chatScheme: ColorScheme { store.chatColorScheme(thread, fallback: scheme) }
    private var p: Palette { Palette(store.data.preferences, chatScheme) }
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
            NativeBackdrop(thread: thread).ignoresSafeArea()
            chatScroll
                .overlay(alignment: .top) { ChatHeaderFade(thread: thread) }
                .safeAreaInset(edge: .top, spacing: 0) { VStack(spacing: 0) { Text(store.name(thread)).font(store.font(12, weight: .medium)).lineLimit(1).frame(maxWidth: .infinity).padding(.top, 2).padding(.bottom, 8); if showSearch { searchControls } } }
                .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        }
        .environment(\.colorScheme, chatScheme)
        .foregroundStyle(p.foreground)
        .toolbarColorScheme(chatScheme, for: .navigationBar)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 20, weight: .regular)).frame(width: 32, height: 44).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("返回") }.matteToolbar()
            ToolbarItem(placement: .principal) { Button { inputFocused = false; infoPresented = true } label: { Avatar(id: thread, size: 42).contentShape(Circle()) }.buttonStyle(.plain).accessibilityLabel("会话选项，" + store.name(thread)).accessibilityIdentifier("chat.options") }.matteToolbar()
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { withAnimation { showSearch.toggle() }; if !showSearch { query = ""; searchKind = "全部"; filterDate = false } } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("搜索聊天").accessibilityIdentifier("chat.search")
            }.matteToolbar()
        }
        .onAppear { text = store.data.drafts[thread] ?? ""; attachments = store.data.draftAttachments?[thread] ?? []; store.activeThread = thread }
        .onDisappear { photoImportTask?.cancel(); importingPhotos = false; store.data.drafts[thread] = text; store.setDraftAttachments(attachments, thread: thread); if store.activeThread == thread { store.activeThread = nil }; store.persist() }
        .onChange(of: text) { _, value in store.data.drafts[thread] = value }
        .onChange(of: attachments) { _, value in store.setDraftAttachments(value, thread: thread) }
        .photosPicker(isPresented: $photosPresented, selection: $photoSelection, maxSelectionCount: max(1, 6 - attachments.count), matching: .images)
        .onChange(of: photoSelection) { _, items in guard !items.isEmpty else { return }; photoImportTask?.cancel(); importingPhotos = true; photoImportTask = Task { defer { if !Task.isCancelled { photoSelection = []; importingPhotos = false } }; for item in items { guard !Task.isCancelled else { return }; do { if let data = try await item.loadTransferable(type: Data.self), !Task.isCancelled, attachments.count < 6 { attachments.append(try store.savePhoto(data)) } } catch { if !Task.isCancelled { store.notice(error.localizedDescription) } } } } }
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
        let snapshot = visibleMessages
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if snapshot.isEmpty { QuietEmpty(icon: filtering ? "magnifyingglass" : "bubble.left", title: filtering ? "没有找到相关消息" : "从一句话开始", detail: filtering ? "换个关键词，或清除筛选。" : "和伙伴聊聊此刻的想法。") }
                    else {
                        ForEach(Array(snapshot.enumerated()), id: \.element.id) { index, message in
                            if index == 0 || !Calendar.current.isDate(message.date, inSameDayAs: snapshot[index - 1].date) { Text(message.date.formatted(.dateTime.month().day())).font(store.font(11)).foregroundStyle(p.secondary).padding(.vertical, 8) }
                            MessageCell(message: message, showAuthor: index == 0 || snapshot[index - 1].author != message.author, thread: thread, onPhoto: { photos, index in inputFocused = false; gallery = GalleryRequest(photos: photos, index: index) }, onFile: { document = DocumentRequest(url: store.url($0.path)) }, onIdea: { idea = Idea(text: message.text) }, onMemory: { if message.author != "me" { saveMemory(message, provider: message.author) } else if thread != "group" { saveMemory(message, provider: thread) } else { memoryMessage = message } }, onEdit: { editing = message.id; text = message.text; inputFocused = true }, onModel: { inputFocused = false; infoPresented = true }).padding(.top, index > 0 && snapshot[index - 1].author != message.author ? 12 : 0).id(message.id)
                        }
                    }
                    Color.clear.frame(height: 1).id("chat.bottom")
                }.padding(.horizontal, LayoutMetrics.page).padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .trackChatBottom($nearBottom, following: $followingLatest, interacting: $userScrolling) { scrollLatest(proxy) }
            .accessibilityIdentifier("chat.messages")
            .onChange(of: messages.count) { _, _ in if messages.last?.author == "me" { followingLatest = true }; scrollLatest(proxy) }
            .onChange(of: messages.last?.text) { _, _ in scrollLatest(proxy) }
            .onChange(of: inputFocused) { _, _ in scrollLatest(proxy) }
            .onChange(of: searchIndex) { _, value in if !visibleMessages.isEmpty { proxy.scrollTo(visibleMessages[min(value, visibleMessages.count - 1)].id, anchor: .center) } }
            .onChange(of: store.requestedMessage) { _, id in if let id, messages.contains(where: { $0.id == id }) { followingLatest = false; proxy.scrollTo(id, anchor: .center); store.requestedMessage = nil } }
            .task(id: thread) { await Task.yield(); if let id = store.requestedMessage, messages.contains(where: { $0.id == id }) { followingLatest = false; proxy.scrollTo(id, anchor: .center); store.requestedMessage = nil } else { followingLatest = true; proxy.scrollTo("chat.bottom", anchor: .bottom) } }
        }
    }
    private func scrollLatest(_ proxy: ScrollViewProxy) {
        guard followingLatest, !userScrolling, !filtering else { return }
        Task { @MainActor in await Task.yield(); guard followingLatest, !userScrolling, !filtering else { return }; proxy.scrollTo("chat.bottom", anchor: .bottom) }
    }
    private var searchControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(p.secondary); TextField("搜索聊天记录", text: $query).font(store.font(16)).accessibilityIdentifier("chat.search.input"); if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.accessibilityLabel("清除搜索") } }.padding(11).background(p.surface, in: RoundedRectangle(cornerRadius: LayoutMetrics.field))
            HStack(spacing: 9) {
                Picker("类型", selection: $searchKind) { ForEach(["全部", "文字", "照片", "文件"], id: \.self) { Text($0).tag($0) } }.labelsHidden().font(store.font(11))
                Button { filterDate.toggle() } label: { Image(systemName: "calendar").foregroundStyle(filterDate ? p.accent : p.secondary) }.accessibilityLabel("按日期筛选")
                if filterDate { DatePicker("日期", selection: $selectedDate, displayedComponents: .date).labelsHidden().datePickerStyle(.compact).font(store.font(11)) }
                Spacer(minLength: 0)
                Text(filtering ? "\(visibleMessages.count) 条" : "").font(store.font(11)).foregroundStyle(p.secondary)
                Button { searchIndex = max(0, searchIndex - 1) } label: { Image(systemName: "chevron.up") }.disabled(visibleMessages.isEmpty).accessibilityLabel("上一个结果")
                Button { searchIndex = min(max(0, visibleMessages.count - 1), searchIndex + 1) } label: { Image(systemName: "chevron.down") }.disabled(visibleMessages.isEmpty).accessibilityLabel("下一个结果")
            }.font(.system(size: 12))
        }.padding(.horizontal, LayoutMetrics.page).padding(.vertical, 10).background(p.background)
    }
    private var composer: some View {
        VStack(spacing: 9) {
            if importingPhotos { ProgressView("正在处理照片").font(store.font(12)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, LayoutMetrics.page) }
            if !mentionChoices.isEmpty { HStack(spacing: 8) { ForEach(mentionChoices, id: \.self) { id in Button { chooseMention(id) } label: { HStack(spacing: 6) { if id != "all" { Avatar(id: id, size: 22) }; Text(id == "all" ? "所有人" : store.name(id)).font(store.font(12)) }.padding(.horizontal, 10).padding(.vertical, 8).background(p.surface, in: Capsule()) }.buttonStyle(.plain) }; Spacer(minLength: 0) }.padding(.horizontal, 14) }
            if !attachments.isEmpty { ScrollView(.horizontal) { HStack(spacing: 10) { ForEach(attachments) { item in ZStack(alignment: .topTrailing) { if item.photo, let image = store.image(item.path) { Image(uiImage: image).resizable().scaledToFill().frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.field)) } else { Label(item.name, systemImage: "doc").font(store.font(11)).lineLimit(2).frame(width: 120, height: 58).padding(7).background(p.surface, in: RoundedRectangle(cornerRadius: LayoutMetrics.field)) }; Button { attachments.removeAll { $0.id == item.id } } label: { Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.55)).font(.system(size: 20)) }.accessibilityLabel("移除附件") } } }.padding(.horizontal, 14) }.scrollIndicators(.hidden) }
            if editing != nil { HStack { Text("编辑消息").font(store.font(11)); Spacer(); Button { editing = nil; text = "" } label: { Image(systemName: "xmark") }.accessibilityLabel("取消编辑") }.foregroundStyle(p.secondary).padding(.horizontal, LayoutMetrics.page) }
            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button("相机", systemImage: "camera") { openCamera() }
                    Button("照片", systemImage: "photo.on.rectangle") { inputFocused = false; photosPresented = true }.disabled(attachments.count >= 6 || importingPhotos).accessibilityIdentifier("attachment.photos")
                    Button("文件", systemImage: "folder") { filesPresented = true }
                    Button("想法", systemImage: "lightbulb") { idea = Idea(text: text) }
                } label: { Image(systemName: "plus").font(.system(size: 21, weight: .regular)).frame(width: 44, height: 44).matteCircle() }.accessibilityLabel("添加内容").accessibilityIdentifier("message.attach")
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("发消息", text: $text, axis: .vertical).font(store.font(16)).lineLimit(1...5).padding(.vertical, 8).focused($inputFocused).accessibilityIdentifier("message.input")
                    if thread == "group" { Button { if !text.isEmpty && !text.hasSuffix(" ") { text += " " }; text += "@"; inputFocused = true } label: { Image(systemName: "at").font(.system(size: 18)).foregroundStyle(p.secondary).frame(width: 26, height: 36) }.accessibilityLabel("提及伙伴") }
                    Button { if stopsReply { store.stopReplies(thread) } else { send() } } label: { Image(systemName: stopsReply ? "stop.fill" : "arrow.up").font(.system(size: 18, weight: .medium)).foregroundStyle(p.background).frame(width: 36, height: 36).background(p.accent.opacity(canSend ? 1 : 0.35), in: Circle()) }.disabled(!canSend).accessibilityLabel(stopsReply ? "停止回复" : "发送消息").accessibilityIdentifier("message.send")
                }.padding(5).padding(.leading, 10).mattePanel(radius: 26)
            }.padding(.horizontal, LayoutMetrics.page)
        }.padding(.top, 10).padding(.bottom, 9)
    }
    private var hasDraft: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty }
    private var stopsReply: Bool { store.isReplying(thread) && !hasDraft }
    private var canSend: Bool { !store.relay.isClearing(thread) && !importingPhotos && (hasDraft || stopsReply) }
    private func send() { userScrolling = false; followingLatest = true; store.send(thread: thread, text: text, attachments: attachments, editing: editing); text = ""; attachments = []; editing = nil }
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
    var onModel: () -> Void
    private var mine: Bool { message.author == "me" }
    private var p: Palette { Palette(store.data.preferences, scheme) }
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
        if mine { Spacer(minLength: 20) }
        else { Avatar(id: message.author, size: 28).opacity(showAuthor ? 1 : 0).padding(.top, showAuthor ? 22 : 0) }
        VStack(alignment: mine ? .trailing : .leading, spacing: 6) {
            if showAuthor && !mine { Button(action: onModel) { HStack(spacing: 5) { BrandMark(id: message.author, size: 12); Text(store.name(message.author)); Image(systemName: "chevron.down").font(.system(size: 8)); if message.demo { Text("交互演示") } }.font(store.font(11)).foregroundStyle(p.secondary).padding(.horizontal, 4) }.buttonStyle(.plain) }
            if !message.attachments.filter(\.photo).isEmpty { NativePhotoStack(photos: message.attachments.filter(\.photo), open: onPhoto) }
            ForEach(message.attachments.filter { !$0.photo }) { file in Button { onFile(file) } label: { HStack(spacing: 10) { Image(systemName: "doc").font(.system(size: 23, weight: .light)).foregroundStyle(p.accent); VStack(alignment: .leading, spacing: 4) { Text(file.name).font(store.font(12)).lineLimit(2); Text(ByteCountFormatter.string(fromByteCount: Int64(file.bytes), countStyle: .file)).font(store.font(11)).foregroundStyle(p.secondary) }; Spacer(minLength: 0) }.padding(13).frame(maxWidth: 245).background(p.surface, in: RoundedRectangle(cornerRadius: LayoutMetrics.field)) }.buttonStyle(.plain) }
            if !message.text.isEmpty || message.status == "replying" {
                VStack(alignment: .trailing, spacing: 6) { if message.text.isEmpty { TypingIndicator(color: p.secondary).frame(height: 18).accessibilityLabel("正在回复") } else { Text(message.text).font(store.font(16)).lineSpacing(4).textSelection(.enabled).multilineTextAlignment(.leading); Text(message.date.formatted(date: .omitted, time: .shortened)).font(store.font(10)).foregroundStyle(p.secondary) } }
                    .padding(.horizontal, 15).padding(.vertical, 11)
                    .background { RoundedRectangle(cornerRadius: LayoutMetrics.card).fill(p.background); RoundedRectangle(cornerRadius: LayoutMetrics.card).fill(mine ? p.mine : p.surface) }
                    .contextMenu { Button("复制", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text; store.notice("已复制") }; if mine { Button("编辑并重发", systemImage: "square.and.pencil", action: onEdit) }; Button("保存为想法", systemImage: "lightbulb", action: onIdea); Button("加入伙伴记忆", systemImage: "note.text", action: onMemory) }
            }
            if ["sending", "failed", "stopped", "demo"].contains(message.status) { status }
        }.frame(maxWidth: min(UIScreen.main.bounds.width * 0.78, 380), alignment: mine ? .trailing : .leading)
        if mine { Avatar(id: "self", size: 28).opacity(showAuthor ? 1 : 0) }
        else { Spacer(minLength: 12) }
        }.frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }
    private var status: some View {
        HStack(spacing: 6) {
            if message.status == "sending" { ProgressView().controlSize(.mini); Text("发送中") }
            if message.status == "failed" { Image(systemName: "exclamationmark.circle"); Text(message.bridgeError ?? "未发送，请检查电脑连接"); Button("重试") { store.retry(thread, id: message.id) }.foregroundStyle(p.accent) }
            if message.status == "stopped" { Image(systemName: "pause"); Text(message.demo ? "已停止演示" : "已停止") }
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
