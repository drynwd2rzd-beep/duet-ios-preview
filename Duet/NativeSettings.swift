import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UserNotifications

@ViewBuilder
func settingsDestination(_ route: SettingsRoute) -> some View {
    switch route {
    case .appearance: AppearanceSettings()
    case .people: PeopleSettings()
    case .profile(let id): ProfileEditor(id: id)
    case .personas: PersonaChooser()
    case .persona(let id): PersonaSettings(provider: id)
    case .accounts: AccountSettings()
    case .automation: AutomationSettings()
    case .notifications: NotificationSettings()
    case .model(let id): ModelSettings(provider: id)
    case .background(let id): ChatBackgroundSettings(thread: id)
    case .role(let id, let key): RoleEditor(provider: id, key: key)
    case .history: HistorySettings()
    }
}

struct NativeSettings: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @State private var settingsPath: [SettingsRoute] = []
    private var p: Palette { Palette(store.data.preferences, scheme) }
    var body: some View {
        NavigationStack(path: $settingsPath) {
            Form {
                Section { NavigationLink(value: SettingsRoute.profile("self")) { HStack(spacing: 14) { Avatar(id: "self", size: 48); VStack(alignment: .leading, spacing: 5) { Text(store.name("self")).font(store.font(17, weight: .medium)); Text("我的资料").font(store.font(12)).foregroundStyle(p.secondary) } }.padding(.vertical, 6) }.accessibilityIdentifier("settings.profile") }
                Section {
                    row(.accounts, icon: "link", title: "电脑连接", detail: store.relay.state, id: "settings.accounts")
                    row(.personas, icon: "person.text.rectangle", title: "个性化与记忆", id: "settings.personas")
                    row(.people, icon: "person.crop.circle", title: "名字与头像", id: "settings.people")
                }
                Section {
                    row(.appearance, icon: "paintpalette", title: "外观与字体", id: "settings.appearance")
                    row(.notifications, icon: "bell", title: "提醒通知", id: "settings.notifications")
                    row(.automation, icon: "arrow.2.squarepath", title: "自动讨论", detail: store.data.preferences.autoDiscuss ? "开启" : "关闭", id: "settings.automation")
                }
                Section { row(.history, icon: "clock.arrow.circlepath", title: "聊天记录", id: "settings.history") }
            }.listSectionSpacing(18).contentMargins(.top, 12).scrollContentBackground(.hidden).background(p.background).foregroundStyle(p.foreground)
                .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }.matteToolbar() }
                .navigationDestination(for: SettingsRoute.self) { settingsDestination($0) }
        }.tint(p.accent).presentationBackground(p.background).presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(LayoutMetrics.sheet)
            .onAppear { if store.relay.pendingPairing != nil { settingsPath = [.accounts] } }
            .onChange(of: store.relay.pendingPairing?.url) { _, value in if value != nil { settingsPath = [.accounts] } }
    }
    private func row(_ route: SettingsRoute, icon: String, title: String, detail: String = "", id: String) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 18, weight: .regular)).foregroundStyle(p.secondary).frame(width: 24)
                Text(title).font(store.font(15)).layoutPriority(1)
                Spacer(minLength: 8)
                if !detail.isEmpty { Text(detail).font(store.font(12)).foregroundStyle(p.secondary).lineLimit(1) }
            }
        }.accessibilityIdentifier(id)
    }
}

struct AppearanceSettings: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    @State private var fontImporter = false
    private var p: Palette { Palette(store.data.preferences, scheme) }
    var body: some View {
        Form {
            Section { Picker("外观", selection: $store.data.preferences.appearance) { Text("系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }.pickerStyle(.segmented).accessibilityIdentifier("appearance.mode") }
            Section {
                Button { store.data.preferences.typography = "native"; store.data.preferences.selectedFont = nil } label: { HStack { Text("苹果系统字体"); Spacer(); if store.data.preferences.typography == "native" { Image(systemName: "checkmark") } } }.accessibilityIdentifier("font.native")
                ForEach(store.data.preferences.fonts) { font in
                    Button { store.data.preferences.typography = "custom"; store.data.preferences.selectedFont = font.id } label: { HStack(spacing: 12) { Text("Aa").font(.custom(font.postScriptName, size: 22)); Text(font.label).lineLimit(1); Spacer(); if store.data.preferences.selectedFont == font.id && store.data.preferences.typography == "custom" { Image(systemName: "checkmark") } } }.swipeActions { Button("移除", role: .destructive) { store.removeFont(font) } }
                }
                Button { fontImporter = true } label: { Label("导入字体", systemImage: "doc.badge.plus") }.accessibilityIdentifier("font.import")
            } header: { Text("全局字体") } footer: { Text("支持 TTF / OTF，标题和正文一起生效；缺失字符使用系统字体。") }
            Section("颜色") {
                Picker("主题色", selection: $store.data.preferences.theme) { Text("雾玫").tag("rose"); Text("雾蓝").tag("blue"); Text("苔绿").tag("sage"); Text("奶杏").tag("apricot"); Text("自定义").tag("custom") }
                ColorPicker("自定义颜色", selection: Binding(get: { Color(uiColor: UIColor(hex: store.data.preferences.customHex)) }, set: { color in var r: CGFloat = 0; var g: CGFloat = 0; var b: CGFloat = 0; UIColor(color).getRed(&r, green: &g, blue: &b, alpha: nil); store.data.preferences.customHex = String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255)); store.data.preferences.theme = "custom" }), supportsOpacity: false)
                Picker("页面背景", selection: $store.data.preferences.background) { Text("暖白").tag("porcelain"); Text("浅粉").tag("blush"); Text("奶杏").tag("cream"); Text("雾蓝").tag("mist") }
            }
            Section("文字大小") { HStack(spacing: 16) { Text("\(Int(store.data.preferences.textScale * 100))%").monospacedDigit().font(store.font(12)).foregroundStyle(p.secondary); Slider(value: $store.data.preferences.textScale, in: 0.9...1.3, step: 0.05) } }
        }.font(store.font(15)).listSectionSpacing(18).contentMargins(.top, 12).scrollContentBackground(.hidden).background(p.background).foregroundStyle(p.foreground).sheetTitle("外观与字体")
            .sheet(isPresented: $fontImporter) { NativeFontPicker { url in fontImporter = false; guard let url else { return }; do { try store.importFont(url) } catch { store.notice(error.localizedDescription) } }.ignoresSafeArea() }
    }
}

struct PeopleSettings: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    private var p: Palette { Palette(store.data.preferences, scheme) }
    var body: some View {
        List { ForEach(["self", "gpt", "claude", "group"], id: \.self) { id in NavigationLink(value: SettingsRoute.profile(id)) { HStack(spacing: 14) { Avatar(id: id, size: 44); VStack(alignment: .leading, spacing: 5) { Text(store.name(id)).font(store.font(16, weight: .medium)).lineLimit(1); Text(id == "self" ? "我的资料" : id == "group" ? "三人群聊" : id == "gpt" ? "ChatGPT" : "Claude").font(store.font(12)).foregroundStyle(p.secondary) } }.padding(.vertical, 5) }.accessibilityIdentifier("profile." + id) } }.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(p.background).foregroundStyle(p.foreground).sheetTitle("名字与头像")
    }
}
struct ProfileEditor: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let id: String
    @State private var edited = Person(id: "self", name: "")
    @State private var selection: PhotosPickerItem? = nil
    var body: some View {
        let p = Palette(store.data.preferences, scheme)
        ScrollView { VStack(spacing: 18) {
            if let image = store.image(edited.avatar) { Image(uiImage: image).resizable().scaledToFill().frame(width: 80, height: 80).clipShape(Circle()) } else { Avatar(id: id, size: 80) }
            PhotosPicker(selection: $selection, matching: .images) { Text("选择头像照片").font(store.font(13)) }
            VStack(alignment: .leading, spacing: 8) { Text("显示名称").font(store.font(11)).foregroundStyle(p.secondary); TextField("名字", text: $edited.name).font(store.font(16)).padding(14).background(p.surface, in: RoundedRectangle(cornerRadius: LayoutMetrics.field)).accessibilityIdentifier("profile.name") }.padding(.top, 8)
            PrimaryAction(title: "保存") { store.saveProfile(edited); dismiss() }.disabled(edited.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("profile.save")
            if id == "self" { Text("未设置单独称呼时，伙伴会使用这里的名字。").font(store.font(12)).foregroundStyle(p.secondary) }
        }.padding(LayoutMetrics.page) }.background(p.background).sheetTitle(id == "self" ? "我的资料" : "名字与头像").onAppear { edited = store.profile(id) }.onChange(of: selection) { _, item in Task { do { if let raw = try await item?.loadTransferable(type: Data.self) { edited.avatar = try store.savePhoto(raw).path } } catch { store.notice(error.localizedDescription) } } }
    }
}

struct PersonaChooser: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(store.data.preferences, scheme)
        List { ForEach(["gpt", "claude"], id: \.self) { id in NavigationLink(value: SettingsRoute.persona(id)) { HStack(spacing: 14) { Avatar(id: id, size: 44); VStack(alignment: .leading, spacing: 5) { Text(store.name(id)).font(store.font(16, weight: .medium)); Text("角色、称呼与记忆").font(store.font(12)).foregroundStyle(p.secondary) } }.padding(.vertical, 6) }.accessibilityIdentifier("persona." + id) } }.listStyle(.insetGrouped).scrollContentBackground(.hidden).background(p.background).foregroundStyle(p.foreground).sheetTitle("个性化与记忆")
    }
}
let roleNames = ["identity": "身份与背景", "values": "偏好与立场", "relationship": "你们的相处", "voice": "表达与习惯"]
func roleText(_ persona: Persona, _ key: String) -> String { switch key { case "identity": return persona.identity; case "values": return persona.values; case "relationship": return persona.relationship; default: return persona.voice } }
struct PersonaSettings: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    let provider: String
    @State private var tab = 0
    @State private var editing: Memory? = nil
    private var p: Palette { Palette(store.data.preferences, scheme) }
    private var persona: Persona { store.data.personas[provider] ?? Persona() }
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 13) { Avatar(id: provider, size: 50); VStack(alignment: .leading, spacing: 5) { Text(store.name(provider)).font(store.font(18, weight: .medium)); Text(provider == "gpt" ? "ChatGPT" : "Claude").font(store.font(11)).foregroundStyle(p.secondary) }; Spacer() }.padding(.horizontal, 20).padding(.top, 16)
            Picker("内容", selection: $tab) { Text("角色档案").tag(0); Text("记忆").tag(1) }.pickerStyle(.segmented).padding(.horizontal, 20)
            if tab == 0 { ScrollView { VStack(spacing: 9) { ForEach(["identity", "values", "relationship", "voice"], id: \.self) { key in NavigationLink(value: SettingsRoute.role(provider, key)) { HStack { VStack(alignment: .leading, spacing: 7) { Text(roleNames[key]!).font(store.font(13, weight: .medium)); Text(roleText(persona, key).isEmpty ? "点此自由设定" : roleText(persona, key)).font(store.font(11)).foregroundStyle(p.secondary).lineLimit(2) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(p.secondary) }.padding(15).background(p.surface, in: RoundedRectangle(cornerRadius: LayoutMetrics.field)) }.buttonStyle(.plain) }; Text("角色与记忆分别保存。连接成功后，会随你发出的消息交给对应伙伴。").font(store.font(11)).foregroundStyle(p.secondary).lineSpacing(4).padding(.vertical, 12) }.padding(20) } }
            else { List { Section("对你的称呼") { TextField("私聊 · 留空跟随我的名字", text: callName(group: false)).accessibilityIdentifier("persona.private-call-name"); TextField("群聊 · 留空跟随我的名字", text: callName(group: true)).accessibilityIdentifier("persona.group-call-name"); Text("只影响这位伙伴。群聊不使用私聊称呼；留空时使用“" + store.name("self") + "”。").font(store.font(11)).foregroundStyle(p.secondary) }; Section("确认保存的记忆") { if persona.memories.isEmpty { Text("记下你希望它记住的事。").font(store.font(12)).foregroundStyle(p.secondary) }; ForEach(persona.memories) { item in Button { editing = item } label: { VStack(alignment: .leading, spacing: 6) { Text(item.text).font(store.font(13)).foregroundStyle(p.foreground); Text(item.kind + " · " + (item.group ? "群聊也可用" : "仅这个伙伴")).font(store.font(11)).foregroundStyle(p.secondary) }.padding(.vertical, 5) }.buttonStyle(.plain).swipeActions { Button(role: .destructive) { store.data.personas[provider]?.memories.removeAll { $0.id == item.id } } label: { Label("删除", systemImage: "trash") } } } } }.scrollContentBackground(.hidden) }
        }.background(p.background).foregroundStyle(p.foreground).sheetTitle("个性化").toolbar { if tab == 1 { ToolbarItem(placement: .topBarTrailing) { Button { editing = Memory() } label: { Image(systemName: "plus") }.accessibilityLabel("添加记忆") }.matteToolbar() } }.sheet(item: $editing) { MemoryEditor(provider: provider, memory: $0).environmentObject(store) }
    }
    private func callName(group: Bool) -> Binding<String> { Binding(get: { (group ? persona.groupCallName : persona.userCallName) ?? "" }, set: { value in var edited = persona; if group { edited.groupCallName = String(value.prefix(24)) } else { edited.userCallName = String(value.prefix(24)) }; store.data.personas[provider] = edited }) }
}
struct RoleEditor: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let provider: String
    let key: String
    @State private var text = ""
    var body: some View { Form { TextField("描述它的个性、经历或相处方式…", text: $text, axis: .vertical).lineLimit(8...16).font(store.font(16)); Button("保存") { var persona = store.data.personas[provider] ?? Persona(); switch key { case "identity": persona.identity = text; case "values": persona.values = text; case "relationship": persona.relationship = text; default: persona.voice = text }; store.data.personas[provider] = persona; store.notice("已保存角色设定", success: true); dismiss() } }.sheetTitle(roleNames[key] ?? "角色设定").onAppear { text = roleText(store.data.personas[provider] ?? Persona(), key) } }
}
struct MemoryEditor: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let provider: String
    @State var memory: Memory
    var body: some View {
        NavigationStack { Form {
            TextField("希望它记住的事…", text: $memory.text, axis: .vertical).lineLimit(4...10).font(store.font(16))
            Picker("分类", selection: $memory.kind) { ForEach(["关于你", "共同经历", "相处习惯"], id: \.self) { Text($0).tag($0) } }
            Toggle("允许群聊使用", isOn: $memory.group)
            if let thread = memory.thread, let message = memory.message { Section("来自聊天 · " + memory.date.formatted(.dateTime.month().day())) { Button("查看来源消息") { store.requestedMessage = message; store.settingsPresented = false; store.requestedThread = thread; dismiss() } } }
            Text("仅保存你确认的内容；两个伙伴的私聊记忆分别保存。").font(store.font(11)).foregroundStyle(.secondary)
        }.sheetTitle("保存给 " + store.name(provider), back: false).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }.matteToolbar(); ToolbarItem(placement: .confirmationAction) { Button("保存") { store.saveMemory(memory, provider: provider); dismiss() }.disabled(memory.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }.matteToolbar() } }.presentationDetents([.medium, .large]).presentationCornerRadius(LayoutMetrics.sheet)
    }
}

struct AccountSettings: View {
    @EnvironmentObject private var store: NativeStore
    var body: some View { NativeBridgeSettings(relay: store.relay) }
}
struct AutomationSettings: View {
    @EnvironmentObject private var store: NativeStore
    var body: some View { Form { Toggle("允许伙伴轮流补充", isOn: $store.data.preferences.autoDiscuss); Picker("每次讨论", selection: $store.data.preferences.rounds) { ForEach(1...3, id: \.self) { Text("\($0) 轮").tag($0) } }; Text("群聊里可以 @ 指定伙伴。当前消息桥最多允许伙伴接续一次，Claude 尚未连接。").font(store.font(11)).foregroundStyle(.secondary) }.sheetTitle("自动讨论") }
}
struct NotificationSettings: View {
    @EnvironmentObject private var store: NativeStore
    @ObservedObject private var push = NativePush.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var status = "检查中"
    @State private var pending = 0
    var body: some View { Form {
        Section("系统权限") { LabeledContent("通知", value: status); Button("开启通知") { Task { _ = await store.notifications.authorize(); store.reconcileReminders(); await refresh() } }; Button("打开系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }
        Section("想法与待办") { Toggle("定时提醒", isOn: Binding(get: { store.data.preferences.remindersEnabled != false }, set: { store.data.preferences.remindersEnabled = $0; store.reconcileReminders() })); LabeledContent("已安排的提醒", value: "\(pending)").accessibilityIdentifier("notifications.pending") }
        Section("远程推送") { LabeledContent("设备注册", value: push.status); Text(push.serverStatus).font(store.font(11)).foregroundStyle(.secondary); Button("重新检查推送") { push.register(); store.relay.registerPush() } }
        Section("聊天") { Toggle("AI 回复完成提醒", isOn: Binding(get: { store.data.preferences.replyNotifications != false }, set: { value in store.data.preferences.replyNotifications = value; if value { Task { _ = await store.notifications.authorize(); await refresh() } } })); Toggle("显示回复预览", isOn: Binding(get: { store.data.preferences.notificationPreview != false }, set: { store.data.preferences.notificationPreview = $0 })); Text("正在查看的聊天不弹出重复提醒。发送后切到后台，会在系统允许的续时内接收回复；强制关闭 App 后的即时通知需要 APNs 推送服务。").font(store.font(11)).foregroundStyle(.secondary) }
        Button("发送测试通知") { Task { let ok = await store.notifications.test(); store.notice(ok ? "3 秒后显示测试通知" : "系统通知未允许，请在设置中开启"); await refresh() } }.accessibilityIdentifier("notifications.test")
    }.sheetTitle("提醒通知").task { await refresh() }.onChange(of: store.data.preferences.replyNotifications) { _, _ in store.relay.registerPush() }.onChange(of: store.data.preferences.notificationPreview) { _, _ in store.relay.registerPush() }.onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } } }
    private func refresh() async { let settings = await UNUserNotificationCenter.current().notificationSettings(); switch settings.authorizationStatus { case .authorized, .provisional, .ephemeral: status = "已允许"; case .denied: status = "未允许"; default: status = "尚未申请" }; pending = await UNUserNotificationCenter.current().pendingNotificationRequests().filter { $0.identifier.hasPrefix("idea.") }.count }
}
struct ModelSettings: View {
    @EnvironmentObject private var store: NativeStore
    let provider: String
    var thread: String? = nil
    private var channel: String { thread ?? provider }
    private var selected: ModelSelection { store.selection(thread: channel, provider: provider) }
    var body: some View {
        Form {
            Section(store.name(provider)) { LabeledContent("已选模型", value: store.relay.modelLabel(provider, thread: channel)) }
            if provider == "gpt" {
                ForEach(["chatgpt-web", "codex-chatgpt"], id: \.self) { source in
                    Section(source == "chatgpt-web" ? "ChatGPT 聊天模型" : "Codex 模型") {
                        let choices = store.relay.modelChoices.filter { $0.source == source }
                        if choices.isEmpty { Text(source == "chatgpt-web" ? "请连接电脑上的网页连接器" : "连接电脑后读取 Codex 账号的可用模型").font(store.font(12)).foregroundStyle(.secondary) }
                        ForEach(choices) { choice in Button { store.select(choice, thread: channel, provider: provider) } label: {
                            HStack { VStack(alignment: .leading, spacing: 5) { Text(choice.name); Text(source == "chatgpt-web" ? "思考强度 · 跟随官网" : "思考强度 · " + (choice.effort ?? "跟随模型默认")).font(store.font(11)).foregroundStyle(.secondary) }; Spacer(); if selected.source == choice.source && (selected.model == choice.model || selected.model == nil && choices.first?.id == choice.id) { Image(systemName: "checkmark") } }
                        }.accessibilityIdentifier("model." + choice.id) }
                    }
                }
                Section { Text("聊天模型使用 ChatGPT 聊天额度；Codex 模型使用 Work/Codex 额度。思考强度跟随所选模型；不会在失败时擅自换到另一种连接。").font(store.font(11)).foregroundStyle(.secondary); Button("刷新可用模型") { store.relay.refreshModels() } }
            }
            else { Text("Claude 尚未接入，暂时无法选择模型。").font(store.font(11)).foregroundStyle(.secondary) }
        }.sheetTitle("模型与思考强度").onAppear { store.relay.refreshStatus(); store.relay.refreshModels() }
    }
}
struct HistorySettings: View {
    @EnvironmentObject private var store: NativeStore
    @State private var clearing: [String] = []
    var body: some View { Form {
        Section("清空过往消息") { ForEach(["gpt", "claude", "group"], id: \.self) { thread in Button(role: .destructive) { clearing = [thread] } label: { LabeledContent(store.name(thread), value: "\(store.data.messages[thread]?.count ?? 0) 条") } }; Button("清空全部聊天记录", role: .destructive) { clearing = ["gpt", "claude", "group"] }.accessibilityIdentifier("history.clear-all") }
        Text("手机与电脑消息桥同步清空，未完成的回复会停止。角色设定、独立保存的记忆和想法不受影响。离线操作会在重连后同步清空。").font(store.font(11)).foregroundStyle(.secondary)
    }.sheetTitle("聊天记录").confirmationDialog("清空所选聊天记录？此操作无法撤回。", isPresented: Binding(get: { !clearing.isEmpty }, set: { if !$0 { clearing = [] } }), titleVisibility: .visible) { Button("清空记录", role: .destructive) { store.relay.clearHistory(clearing); clearing = [] }; Button("取消", role: .cancel) { clearing = [] } } }
}
struct ChatBackgroundSettings: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    let thread: String
    @State private var selected: PhotosPickerItem? = nil
    @State private var options = BackdropOptions()
    @GestureState private var drag = CGSize.zero
    private var p: Palette { Palette(store.data.preferences, scheme) }
    private var previewOptions: BackdropOptions { var value = options; value.x = max(-1, min(1, value.x + Double(drag.width / 140))); value.y = max(-1, min(1, value.y + Double(drag.height / 180))); return value }
    var body: some View {
        Form {
            Section {
                ZStack(alignment: .top) {
                    NativeBackdrop(thread: thread, options: previewOptions)
                    VStack(spacing: 6) { Avatar(id: thread, size: 32); Text(store.name(thread)).font(store.font(12, weight: .medium)); Spacer(); Text("背景预览").font(store.font(12)).foregroundStyle(p.foreground).padding(12).mattePanel(radius: LayoutMetrics.field) }.padding(20)
                }.frame(height: 290).clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.card))
                    .gesture(DragGesture().updating($drag) { value, state, _ in state = value.translation }.onEnded { value in options.x = max(-1, min(1, options.x + Double(value.translation.width / 140))); options.y = max(-1, min(1, options.y + Double(value.translation.height / 180))) })
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).accessibilityIdentifier("background.preview")
            }
            Section {
                PhotosPicker(selection: $selected, matching: .images) { Label("选择背景图片", systemImage: "photo") }.accessibilityIdentifier("background.choose")
                if store.data.backgrounds[thread] != nil { Button("恢复全局纯色", role: .destructive) { store.replaceBackground(nil, thread: thread); options = BackdropOptions() } }
            }
            if store.data.backgrounds[thread] != nil {
                Section { adjustment("缩放", value: $options.zoom, range: 1...2); adjustment("模糊", value: $options.blur, range: 0...16); adjustment("压暗", value: $options.dim, range: 0...0.7); Button("重置图片调整") { options = BackdropOptions() } } header: { Text("图片效果") } footer: { Text("在预览中拖动图片调整裁切位置。仅用于这个聊天。") }
            }
            Section { adjustment("渐隐强度", value: $options.headerFade, range: 0...1) } header: { Text("顶部渐隐") }
        }.scrollContentBackground(.hidden).background(p.background).sheetTitle("聊天背景")
            .onAppear { options = store.backdrop(thread) }
            .onChange(of: options) { _, value in store.setBackdrop(value, thread: thread) }
            .onChange(of: selected) { _, item in Task { do { if let data = try await item?.loadTransferable(type: Data.self) { let file = try store.savePhoto(data); store.replaceBackground(file.path, thread: thread); options.zoom = 1; options.x = 0; options.y = 0 } } catch { store.notice(error.localizedDescription) } } }
    }
    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View { VStack(alignment: .leading, spacing: 10) { Text(title).font(store.font(13)); Slider(value: value, in: range) }.padding(.vertical, 4) }
}

struct ConversationInfo: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    let thread: String
    @State private var idea: Idea? = nil
    @State private var clearPresented = false
    private var p: Palette { Palette(store.data.preferences, scheme) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) { Avatar(id: thread, size: 48); Text(store.name(thread)).font(store.font(17, weight: .medium)) }.padding(.vertical, 6)
                    ForEach(thread == "group" ? ["gpt", "claude"] : [thread], id: \.self) { provider in
                        NavigationLink(destination: ModelSettings(provider: provider, thread: thread)) { HStack(spacing: 10) { BrandMark(id: provider, size: 17); Text(store.relay.modelLabel(provider, thread: thread)).font(store.font(14)) } }.accessibilityIdentifier("chat.model." + provider)
                    }
                }
                Section {
                    NavigationLink(value: SettingsRoute.profile(thread)) { Label("名字与头像", systemImage: "person.crop.circle") }
                    NavigationLink(value: SettingsRoute.background(thread)) { Label("聊天背景", systemImage: "photo") }.accessibilityIdentifier("chat.background")
                    Button { let last = store.data.messages[thread]?.last(where: { $0.author == "me" && !$0.text.isEmpty }); idea = Idea(text: last?.text ?? "") } label: { Label("记录想法", systemImage: "lightbulb") }
                    Button { store.pin(thread) } label: { Label(store.data.pinned.contains(thread) ? "取消置顶" : "置顶会话", systemImage: store.data.pinned.contains(thread) ? "pin.slash" : "pin") }
                }
                Section { Button("清空聊天记录", role: .destructive) { clearPresented = true }.accessibilityIdentifier("chat.clear-history") }
            }.listSectionSpacing(18).contentMargins(.top, 12).scrollContentBackground(.hidden).background(p.background).foregroundStyle(p.foreground).sheetTitle("会话选项", back: false)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("关闭会话选项") }.matteToolbar() }
                .navigationDestination(for: SettingsRoute.self) { settingsDestination($0) }
        }.presentationBackground(p.background).presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(LayoutMetrics.sheet)
            .sheet(item: $idea) { IdeaEditor(idea: $0).environmentObject(store) }
            .onAppear { store.relay.refreshStatus(); store.relay.refreshModels() }
            .confirmationDialog("清空这个聊天的全部消息？", isPresented: $clearPresented, titleVisibility: .visible) { Button("清空记录", role: .destructive) { store.relay.clearHistory([thread]); dismiss() }; Button("取消", role: .cancel) { } } message: { Text("会同步清空电脑上的会话记录，并停止当前回复。独立保存的记忆保留。") }
    }
}
