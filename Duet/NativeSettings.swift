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
            ScrollView {
                VStack(spacing: 12) {
                    NavigationLink(value: SettingsRoute.profile("self")) { HStack(spacing: 14) { Avatar(id: "self", size: 54); VStack(alignment: .leading, spacing: 5) { Text(store.name("self")).font(store.font(17, weight: .medium)); Text("我的头像与名字").font(store.font(11)).foregroundStyle(p.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(p.secondary) }.padding(14).background(p.accent.opacity(0.065), in: RoundedRectangle(cornerRadius: 22)) }.buttonStyle(.plain).accessibilityIdentifier("settings.profile")
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        tile(.appearance, icon: "paintpalette", title: "外观与字体", detail: "主题 · 字体 · 背景", id: "settings.appearance")
                        tile(.people, icon: "person.2", title: "管理伙伴", detail: "名字与头像", id: "settings.people")
                        tile(.personas, icon: "note.text", title: "个性化与记忆", detail: "角色与共同经历", id: "settings.personas")
                        tile(.accounts, icon: "link", title: "电脑连接", detail: "GPT · Windows 消息桥", id: "settings.accounts")
                    }
                    VStack(spacing: 0) { row(.notifications, icon: "bell", title: "提醒通知", detail: "本地通知"); Divider().opacity(0.4); row(.automation, icon: "arrow.2.squarepath", title: "自动讨论", detail: store.data.preferences.autoDiscuss ? "\(store.data.preferences.rounds) 轮" : "关闭") }.padding(.horizontal, 14).background(p.surface, in: RoundedRectangle(cornerRadius: 22))
                    Text("原生版 · GPT 通过电脑上的 Codex 连接").font(store.font(11)).foregroundStyle(p.secondary).padding(.top, 5)
                }.padding(20)
            }.background(p.background).foregroundStyle(p.foreground).sheetTitle("设置")
            .navigationDestination(for: SettingsRoute.self) { settingsDestination($0) }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("关闭设置").accessibilityIdentifier("settings.close") } }
        }.tint(p.accent).presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(32).onAppear { if store.relay.pendingPairing != nil { settingsPath = [.accounts] } }
    }
    private func tile(_ route: SettingsRoute, icon: String, title: String, detail: String, id: String) -> some View {
        NavigationLink(value: route) { VStack(alignment: .leading, spacing: 7) { Image(systemName: icon).font(.system(size: 21, weight: .light)).foregroundStyle(p.accent).padding(.bottom, 3); Text(title).font(store.font(13, weight: .medium)); Text(detail).font(store.font(11)).foregroundStyle(p.secondary) }.frame(maxWidth: .infinity, minHeight: 81, alignment: .leading).padding(16).background(p.surface, in: RoundedRectangle(cornerRadius: 22)) }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
    private func row(_ route: SettingsRoute, icon: String, title: String, detail: String) -> some View {
        NavigationLink(value: route) { HStack(spacing: 11) { Image(systemName: icon).font(.system(size: 18, weight: .light)).foregroundStyle(p.accent); Text(title).font(store.font(12)); Spacer(); Text(detail).font(store.font(11)).foregroundStyle(p.secondary); Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(p.secondary) }.padding(.vertical, 16) }.buttonStyle(.plain)
    }
}

struct AppearanceSettings: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    @State private var fontImporter = false
    private var p: Palette { Palette(store.data.preferences, scheme) }
    private let themeNames = ["rose": "雾玫", "blue": "雾蓝", "sage": "苔绿", "apricot": "奶杏"]
    private let backgroundNames = ["porcelain": "暖白", "blush": "浅粉", "cream": "奶杏", "mist": "雾蓝"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("外观", selection: $store.data.preferences.appearance) { Text("系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }.pickerStyle(.segmented).accessibilityIdentifier("appearance.mode")
                section("字体") {
                    HStack(spacing: 12) { fontChoice("native", title: "原生字体", detail: "系统字体"); fontChoice("artistic", title: "全局艺术字体", detail: "原生衬线字体") }
                    ForEach(store.data.preferences.fonts) { font in HStack { Button { store.data.preferences.typography = "custom"; store.data.preferences.selectedFont = font.id } label: { HStack { Text("Aa 字").font(.custom(font.postScriptName, size: 22)); Text(font.label).font(store.font(12)).lineLimit(1); Spacer(); if store.data.preferences.typography == "custom" && store.data.preferences.selectedFont == font.id { Image(systemName: "checkmark") } }.padding(12) }.buttonStyle(.plain); Button { store.data.preferences.fonts.removeAll { $0.id == font.id }; if store.data.preferences.selectedFont == font.id { store.data.preferences.typography = "native"; store.data.preferences.selectedFont = nil } } label: { Image(systemName: "trash").frame(width: 36, height: 44) }.accessibilityLabel("移除字体") }.background(p.surface, in: RoundedRectangle(cornerRadius: 16)) }
                    Button { fontImporter = true } label: { Label("导入字体", systemImage: "plus").font(store.font(13)).frame(minHeight: 44) }.accessibilityIdentifier("font.import")
                    Text("TTF / OTF · 保存在设备 · 缺失字符使用系统字体").font(store.font(11)).foregroundStyle(p.secondary)
                }
                section("主题色") { HStack(spacing: 20) { ForEach(["rose", "blue", "sage", "apricot"], id: \.self) { id in Button { store.data.preferences.theme = id } label: { VStack(spacing: 8) { Circle().fill(themeColor(id)).frame(width: 32, height: 32).overlay { if store.data.preferences.theme == id { Circle().stroke(p.accent, lineWidth: 1.5).padding(-4) } }; Text(themeNames[id]!).font(store.font(11)).foregroundStyle(p.secondary) } }.buttonStyle(.plain) } }; ColorPicker("自定义主题色", selection: Binding(get: { Color(uiColor: UIColor(hex: store.data.preferences.customHex)) }, set: { color in var r: CGFloat = 0; var g: CGFloat = 0; var b: CGFloat = 0; UIColor(color).getRed(&r, green: &g, blue: &b, alpha: nil); store.data.preferences.customHex = String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255)); store.data.preferences.theme = "custom" }), supportsOpacity: false).font(store.font(13)).padding(.top, 10) }
                section("纯色背景") { HStack(spacing: 20) { ForEach(["porcelain", "blush", "cream", "mist"], id: \.self) { id in Button { store.data.preferences.background = id } label: { VStack(spacing: 8) { Circle().fill(backgroundColor(id)).frame(width: 32, height: 32).overlay(Circle().stroke(store.data.preferences.background == id ? p.accent : p.secondary.opacity(0.2), lineWidth: store.data.preferences.background == id ? 2 : 1)); Text(backgroundNames[id]!).font(store.font(11)).foregroundStyle(p.secondary) } }.buttonStyle(.plain) } } }
                section("文字大小") { HStack { Text("\(Int(store.data.preferences.textScale * 100))%").font(store.font(12)).monospacedDigit().frame(width: 45); Slider(value: $store.data.preferences.textScale, in: 0.9...1.3, step: 0.05).tint(p.accent) }; Text("标题和正文统一跟随全局字体。").font(store.font(11)).foregroundStyle(p.secondary) }
            }.padding(20)
        }.background(p.background).foregroundStyle(p.foreground).sheetTitle("外观与字体")
        .fileImporter(isPresented: $fontImporter, allowedContentTypes: [UTType(filenameExtension: "ttf") ?? .data, UTType(filenameExtension: "otf") ?? .data]) { result in do { try store.importFont(result.get()) } catch { store.notice(error.localizedDescription) } }
    }
    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View { VStack(alignment: .leading, spacing: 12) { Text(title).font(store.font(11)).foregroundStyle(p.secondary); content() } }
    private func fontChoice(_ id: String, title: String, detail: String) -> some View {
        Button { store.data.preferences.typography = id } label: { VStack(alignment: .leading, spacing: 7) { Text("Aa").font(.system(size: 27, design: id == "native" ? .default : .serif)); Text(title).font(store.font(12, weight: .medium)); Text(detail).font(store.font(11)).foregroundStyle(p.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(14).background(store.data.preferences.typography == id ? p.accent.opacity(0.08) : p.surface, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(store.data.preferences.typography == id ? p.accent.opacity(0.3) : .clear, lineWidth: 1)) }.buttonStyle(.plain)
    }
    private func themeColor(_ id: String) -> Color { var settings = store.data.preferences; settings.theme = id; return Palette(settings, scheme).accent }
    private func backgroundColor(_ id: String) -> Color { var settings = store.data.preferences; settings.background = id; return Palette(settings, scheme).background }
}

struct PeopleSettings: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    private var p: Palette { Palette(store.data.preferences, scheme) }
    var body: some View {
        ScrollView { LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) { ForEach(["self", "gpt", "claude", "group"], id: \.self) { id in NavigationLink(value: SettingsRoute.profile(id)) { VStack(spacing: 9) { Avatar(id: id, size: 50); Text(store.name(id)).font(store.font(13, weight: .medium)).lineLimit(1); Text(id == "self" ? "我的资料" : id == "group" ? "三人群聊" : id == "gpt" ? "ChatGPT" : "Claude").font(store.font(11)).foregroundStyle(p.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 20).background(p.surface, in: RoundedRectangle(cornerRadius: 22)) }.buttonStyle(.plain).accessibilityIdentifier("profile." + id) } }.padding(20) }.background(p.background).foregroundStyle(p.foreground).sheetTitle("名字与头像")
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
            VStack(alignment: .leading, spacing: 8) { Text("显示名称").font(store.font(11)).foregroundStyle(p.secondary); TextField("名字", text: $edited.name).font(store.font(16)).padding(14).background(p.surface, in: RoundedRectangle(cornerRadius: 16)).accessibilityIdentifier("profile.name") }.padding(.top, 8)
            PrimaryAction(title: "保存") { store.saveProfile(edited); dismiss() }.disabled(edited.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("profile.save")
            if id == "self" { Text("伙伴会使用这里的名字称呼你。").font(store.font(11)).foregroundStyle(p.secondary) }
        }.padding(24) }.background(p.background).sheetTitle(id == "self" ? "我的资料" : "名字与头像").onAppear { edited = store.profile(id) }.onChange(of: selection) { _, item in Task { do { if let raw = try await item?.loadTransferable(type: Data.self) { edited.avatar = try store.savePhoto(raw).path } } catch { store.notice(error.localizedDescription) } } }
    }
}

struct PersonaChooser: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let p = Palette(store.data.preferences, scheme)
        ScrollView { HStack(spacing: 12) { ForEach(["gpt", "claude"], id: \.self) { id in NavigationLink(value: SettingsRoute.persona(id)) { VStack(spacing: 10) { Avatar(id: id, size: 48); Text(store.name(id)).font(store.font(13, weight: .medium)); Text("角色档案与记忆").font(store.font(11)).foregroundStyle(p.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 22).background(p.surface, in: RoundedRectangle(cornerRadius: 22)) }.buttonStyle(.plain) } }.padding(20) }.background(p.background).foregroundStyle(p.foreground).sheetTitle("个性化与记忆")
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
            if tab == 0 { ScrollView { VStack(spacing: 9) { ForEach(["identity", "values", "relationship", "voice"], id: \.self) { key in NavigationLink(value: SettingsRoute.role(provider, key)) { HStack { VStack(alignment: .leading, spacing: 7) { Text(roleNames[key]!).font(store.font(13, weight: .medium)); Text(roleText(persona, key).isEmpty ? "点此自由设定" : roleText(persona, key)).font(store.font(11)).foregroundStyle(p.secondary).lineLimit(2) }; Spacer(); Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(p.secondary) }.padding(15).background(p.surface, in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain) }; Text("角色与记忆分别保存。连接成功后，会随你发出的消息交给对应伙伴。").font(store.font(11)).foregroundStyle(p.secondary).lineSpacing(4).padding(.vertical, 12) }.padding(20) } }
            else { List { Section { VStack(alignment: .leading, spacing: 6) { Text("对你的称呼 · 随我的资料同步").font(store.font(11)).foregroundStyle(p.secondary); Text(store.name("self")).font(store.font(17, weight: .medium)) }.padding(.vertical, 4) }; Section("确认保存的记忆") { if persona.memories.isEmpty { Text("记下你希望它记住的事。").font(store.font(12)).foregroundStyle(p.secondary) }; ForEach(persona.memories) { item in Button { editing = item } label: { VStack(alignment: .leading, spacing: 6) { Text(item.text).font(store.font(13)).foregroundStyle(p.foreground); Text(item.kind + " · " + (item.group ? "群聊也可用" : "仅这个伙伴")).font(store.font(11)).foregroundStyle(p.secondary) }.padding(.vertical, 5) }.buttonStyle(.plain).swipeActions { Button(role: .destructive) { store.data.personas[provider]?.memories.removeAll { $0.id == item.id } } label: { Label("删除", systemImage: "trash") } } } } }.scrollContentBackground(.hidden) }
        }.background(p.background).foregroundStyle(p.foreground).sheetTitle("个性化").toolbar { if tab == 1 { ToolbarItem(placement: .topBarTrailing) { Button { editing = Memory() } label: { Image(systemName: "plus") }.accessibilityLabel("添加记忆") } } }.sheet(item: $editing) { MemoryEditor(provider: provider, memory: $0).environmentObject(store) }
    }
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
        }.sheetTitle("保存给 " + store.name(provider)).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { store.saveMemory(memory, provider: provider); dismiss() }.disabled(memory.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } } }.presentationDetents([.medium, .large]).presentationCornerRadius(32)
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
    @State private var status = "检查中"
    var body: some View { Form { LabeledContent("系统通知", value: status); Text("第一次保存提醒时，会申请系统通知权限。提醒内容保存在设备上。").font(store.font(12)).foregroundStyle(.secondary); Button("打开系统设置") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } } }.sheetTitle("提醒通知").task { let settings = await UNUserNotificationCenter.current().notificationSettings(); switch settings.authorizationStatus { case .authorized, .provisional, .ephemeral: status = "已允许"; case .denied: status = "未允许"; default: status = "尚未申请" } } }
}
struct ModelSettings: View {
    @EnvironmentObject private var store: NativeStore
    let provider: String
    private var options: [String] { ["跟随官网"] }
    var body: some View {
        Form { Section(store.name(provider)) { ForEach(options, id: \.self) { option in Button { store.data.models[provider] = option } label: { HStack { Text(option).font(store.font(14)); Spacer(); if store.data.models[provider] == option { Image(systemName: "checkmark") } } } } }; Section("思考强度") { Picker("强度", selection: Binding(get: { store.data.strengths[provider] ?? "自动" }, set: { store.data.strengths[provider] = $0 })) { ForEach(["自动", "轻量", "标准", "深入"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).disabled(true) }; Text("当前使用电脑上 Codex 账号的默认模型。手机端模型与强度切换尚未接入。").font(store.font(11)).foregroundStyle(.secondary) }.sheetTitle("模型与思考强度")
    }
}
struct ChatBackgroundSettings: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    let thread: String
    @State private var selected: PhotosPickerItem? = nil
    var body: some View {
        let p = Palette(store.data.preferences, scheme)
        ScrollView { VStack(spacing: 18) {
            if let image = store.image(store.data.backgrounds[thread]) { Image(uiImage: image).resizable().scaledToFill().frame(height: 180).clipped().clipShape(RoundedRectangle(cornerRadius: 22)) } else { QuietEmpty(icon: "photo", title: "跟随全局纯色", detail: "为这段聊天选择一张自己的背景图。") }
            PhotosPicker(selection: $selected, matching: .images) { Text("选择自己的图片").font(store.font(14)).frame(maxWidth: .infinity).padding(13).background(p.accent.opacity(0.1), in: Capsule()) }
            if store.data.backgrounds[thread] != nil { Button("恢复全局背景") { store.data.backgrounds.removeValue(forKey: thread) }.font(store.font(13)) }
            Text("仅用于 " + store.name(thread) + "，其他页面沿用全局纯色。").font(store.font(11)).foregroundStyle(p.secondary)
        }.padding(20) }.background(p.background).sheetTitle("聊天背景").onChange(of: selected) { _, item in Task { do { if let data = try await item?.loadTransferable(type: Data.self) { store.data.backgrounds[thread] = try store.savePhoto(data).path } } catch { store.notice(error.localizedDescription) } } }
    }
}

struct ConversationInfo: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    let thread: String
    @State private var idea: Idea? = nil
    private var p: Palette { Palette(store.data.preferences, scheme) }
    var body: some View {
        NavigationStack {
            ScrollView { VStack(spacing: 16) {
                Avatar(id: thread, size: 62)
                Text(store.name(thread)).font(store.font(19, weight: .medium))
                HStack(spacing: 8) { ForEach(thread == "group" ? ["gpt", "claude"] : [thread], id: \.self) { provider in NavigationLink(value: SettingsRoute.model(provider)) { HStack(spacing: 6) { BrandMark(id: provider, size: 15); Text((store.data.models[provider] ?? "跟随官网") + " · " + (store.data.strengths[provider] ?? "自动")).font(store.font(11)).lineLimit(1); Image(systemName: "chevron.down").font(.system(size: 10)) }.padding(11).background(p.surface, in: Capsule()) }.buttonStyle(.plain) } }
                HStack(spacing: 10) {
                    NavigationLink(value: SettingsRoute.profile(thread)) { quick("名字与头像", icon: "person.crop.circle") }.buttonStyle(.plain)
                    NavigationLink(value: SettingsRoute.background(thread)) { quick("聊天背景", icon: "photo") }.buttonStyle(.plain)
                    Button { let last = store.data.messages[thread]?.last(where: { $0.author == "me" && !$0.text.isEmpty }); idea = Idea(text: last?.text ?? "") } label: { quick("记录想法", icon: "lightbulb") }.buttonStyle(.plain)
                }
                Button { store.pin(thread) } label: { Label(store.data.pinned.contains(thread) ? "取消置顶" : "置顶会话", systemImage: store.data.pinned.contains(thread) ? "pin.slash" : "pin").font(store.font(11)).foregroundStyle(p.secondary).padding(8) }
            }.padding(20) }.background(p.background).foregroundStyle(p.foreground).navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("关闭会话选项") } }.navigationDestination(for: SettingsRoute.self) { settingsDestination($0) }
        }.presentationDetents([.height(390), .large]).presentationDragIndicator(.visible).presentationCornerRadius(32).sheet(item: $idea) { IdeaEditor(idea: $0).environmentObject(store) }
    }
    private func quick(_ title: String, icon: String) -> some View { VStack(spacing: 10) { Image(systemName: icon).font(.system(size: 21, weight: .light)).foregroundStyle(p.accent); Text(title).font(store.font(11)) }.frame(maxWidth: .infinity).padding(.vertical, 16).background(p.surface, in: RoundedRectangle(cornerRadius: 22)) }
}
