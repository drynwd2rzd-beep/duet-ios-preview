import SwiftUI
import UIKit
import UserNotifications

@main
struct DuetApp: App {
    @UIApplicationDelegateAdaptor(DuetAppDelegate.self) private var appDelegate
    @StateObject private var store = NativeStore()
    var body: some Scene {
        WindowGroup { NativeRoot().environmentObject(store).preferredColorScheme(store.appearance).onOpenURL { store.relay.stagePairing($0) } }
    }
}
struct NativeRoot: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = "chats"
    @State private var chatPath: [String] = []
    private var p: Palette { Palette(store.data.preferences, scheme) }
    var body: some View {
        ZStack {
            NavigationStack(path: $chatPath) {
                ChatsHome()
                .navigationDestination(for: String.self) { id in NativeChat(thread: id) }
                .toolbar(.hidden, for: .navigationBar)
            }.opacity(tab == "chats" ? 1 : 0).allowsHitTesting(tab == "chats").accessibilityHidden(tab != "chats")
            NavigationStack { IdeasHome().toolbar(.hidden, for: .navigationBar) }
                .opacity(tab == "ideas" ? 1 : 0).allowsHitTesting(tab == "ideas").accessibilityHidden(tab != "ideas")
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { if tab != "chats" || chatPath.isEmpty { matteTabs } }
        .background(p.background)
        .tint(p.accent)
        .environment(\.font, store.font(14))
        .sheet(isPresented: $store.settingsPresented) { NativeSettings().environmentObject(store).preferredColorScheme(store.appearance) }
        .overlay(alignment: .bottom) { if let text = store.toast { Label(text, systemImage: "checkmark").font(store.font(12)).padding(.horizontal, 16).padding(.vertical, 12).foregroundStyle(p.background).background(p.foreground, in: Capsule()).padding(.bottom, 90).padding(.horizontal, 20).allowsHitTesting(false).accessibilityIdentifier("feedback.toast") } }
        .onChange(of: store.requestedThread) { _, value in if let value { tab = "chats"; chatPath = [value]; store.requestedThread = nil } }
        .onChange(of: store.requestedIdea) { _, value in if value != nil { tab = "ideas" } }
        .onAppear { store.notifications.install(store: store); if !store.testMode { store.relay.connect() } }
        .onChange(of: scenePhase) { _, phase in if !store.testMode { store.relay.sceneChanged(phase); if phase == .active { store.reconcileReminders() } else if phase == .background { store.persist() } } }
    }
    private var matteTabs: some View {
        HStack(spacing: 34) {
            tabButton("chats", label: "聊天", icon: "bubble.left")
            tabButton("ideas", label: "想法", icon: "lightbulb")
        }.padding(.horizontal, 22).padding(.vertical, 4)
            .background(p.background, in: Capsule())
            .overlay(Capsule().stroke(p.foreground.opacity(0.055), lineWidth: 0.5))
            .padding(.top, 8).padding(.bottom, 7)
    }
    private func tabButton(_ value: String, label: String, icon: String) -> some View {
        Button { tab = value } label: {
            Image(systemName: icon).font(.system(size: 21, weight: tab == value ? .medium : .regular))
                .foregroundStyle(tab == value ? p.accent : p.secondary).frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier("tab." + value)
            .accessibilityAddTraits(tab == value ? .isSelected : [])
    }
}

struct ChatsHome: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    @State private var pendingPin: String? = nil
    private var p: Palette { Palette(store.data.preferences, scheme) }
    private var ordered: [String] {
        let base = ["group", "gpt", "claude"]
        return base.sorted { a, b in
            let ai = store.data.pinned.firstIndex(of: a) ?? 99
            let bi = store.data.pinned.firstIndex(of: b) ?? 99
            return ai == bi ? base.firstIndex(of: a)! < base.firstIndex(of: b)! : ai < bi
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Chats").font(store.font(24, weight: .medium)).foregroundStyle(p.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, LayoutMetrics.page).padding(.top, 18).padding(.bottom, 18)
                .accessibilityIdentifier("home.header")
            List {
                Section {
                    ForEach(ordered, id: \.self) { id in
                        Button { store.requestedThread = id } label: { threadRow(id).contentShape(Rectangle()) }
                            .buttonStyle(.plain).accessibilityIdentifier("thread." + id)
                            .listRowInsets(EdgeInsets(top: 11, leading: 12, bottom: 11, trailing: 12))
                            .listRowSeparator(id == ordered.last ? .hidden : .visible)
                            .listRowSeparatorTint(p.foreground.opacity(0.065))
                            .listRowBackground(p.dark ? p.surface : Color.white.opacity(0.78))
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button { changePin(id) } label: { Label(store.data.pinned.contains(id) ? "取消置顶" : "置顶", systemImage: store.data.pinned.contains(id) ? "pin.slash" : "pin") }.tint(p.accent).disabled(pendingPin != nil)
                            }
                    }
                }
            }.listStyle(.insetGrouped).listSectionSpacing(LayoutMetrics.section)
                .scrollContentBackground(.hidden).contentMargins(.top, 0)
        }.background(p.background).foregroundStyle(p.foreground)
    }
    private func changePin(_ id: String) {
        guard pendingPin == nil else { return }; pendingPin = id
        Task { @MainActor in
            // Let the native swipe drawer close before its row moves.
            try? await Task.sleep(nanoseconds: 350_000_000)
            withAnimation(.easeInOut(duration: 0.22)) { store.pin(id) }
            pendingPin = nil
        }
    }
    private func threadRow(_ id: String) -> some View {
        HStack(spacing: 11) {
            Avatar(id: id, size: id == "group" ? 44 : 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(store.name(id)).font(store.font(15, weight: .medium)).lineLimit(1)
                    if store.data.pinned.contains(id) { Image(systemName: "pin.fill").font(.system(size: 8)).foregroundStyle(p.secondary.opacity(0.65)) }
                    Spacer(minLength: 4)
                    Text(store.data.messages[id]?.last?.date.formatted(date: .omitted, time: .shortened) ?? "")
                        .font(store.font(10)).foregroundStyle(p.secondary)
                }
                if !preview(id).isEmpty { Text(preview(id)).font(store.font(12)).foregroundStyle(p.secondary).lineLimit(1) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(minHeight: 44)
    }
    private func preview(_ id: String) -> String {
        guard let last = store.data.messages[id]?.last else { return "" }
        if !last.text.isEmpty { return last.text.replacingOccurrences(of: "\n", with: " ") }
        if last.bridgeJob != nil { return last.status == "replying" ? "正在回复…" : last.status == "failed" ? "回复未完成" : "已停止" }
        guard !last.attachments.isEmpty else { return "" }
        return last.attachments.allSatisfy(\.photo) ? "[\(last.attachments.count) 张照片]" : "[文件] " + last.attachments.map(\.name).joined(separator: "、")
    }
}

struct IdeasHome: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    @State private var filter = 0
    @State private var editing: Idea? = nil
    @State private var reminder: Idea? = nil
    private var p: Palette { Palette(store.data.preferences, scheme) }
    private var items: [Idea] { store.data.ideas.filter { filter == 2 || $0.later == (filter == 1) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Ideas").font(store.font(24, weight: .medium)).foregroundStyle(p.foreground)
                Spacer()
                Button { store.settingsPresented = true } label: { Image(systemName: "gearshape").font(.system(size: 16)).frame(width: 36, height: 36).matteCircle() }.accessibilityLabel("设置").accessibilityIdentifier("open.settings")
                Button { editing = Idea(later: filter == 1) } label: { Image(systemName: "plus").font(.system(size: 18)).frame(width: 36, height: 36).matteCircle() }.accessibilityLabel("记录想法").accessibilityIdentifier("idea.add")
            }.padding(.horizontal, LayoutMetrics.page).padding(.top, 14).padding(.bottom, 16)
            Picker("想法范围", selection: $filter) { Text("今天").tag(0); Text("以后").tag(1); Text("全部").tag(2) }
                .pickerStyle(.segmented).controlSize(.small).padding(.horizontal, LayoutMetrics.page).padding(.bottom, 12)
            if items.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("留一点位置，给新的想法。").font(store.font(13)).foregroundStyle(p.secondary)
                    Button { editing = Idea(later: filter == 1) } label: { Label("记一笔", systemImage: "square.and.pencil").font(store.font(13)) }
                }.padding(.horizontal, LayoutMetrics.page + 4).padding(.top, 28)
                Spacer()
            } else {
                List {
                    Section {
                        ForEach(items) { idea in
                            ideaRow(idea)
                                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                                .listRowSeparatorTint(p.foreground.opacity(0.065))
                                .listRowBackground(p.dark ? p.surface : Color.white.opacity(0.78))
                                .swipeActions(edge: .leading) { Button { toggle(idea) } label: { Label(idea.done ? "恢复" : "完成", systemImage: "checkmark") }.tint(p.accent) }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) { store.deleteIdea(idea.id) } label: { Label("删除", systemImage: "trash") }
                                    Button { reminder = idea } label: { Label("提醒", systemImage: "bell") }.tint(p.accent)
                                }
                        }
                    }
                }.listStyle(.insetGrouped).scrollContentBackground(.hidden).contentMargins(.top, 0)
            }
        }.background(p.background).foregroundStyle(p.foreground)
            .sheet(item: $editing) { IdeaEditor(idea: $0).environmentObject(store) }
            .sheet(item: $reminder) { ReminderEditor(idea: $0).environmentObject(store) }
            .onAppear { openRequestedIdea() }.onChange(of: store.requestedIdea) { _, _ in openRequestedIdea() }
    }
    private func ideaRow(_ idea: Idea) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Button { toggle(idea) } label: { Image(systemName: idea.done ? "checkmark.circle" : idea.task ? "circle" : "lightbulb").font(.system(size: 17, weight: .light)).foregroundStyle(idea.done ? p.accent : p.secondary).frame(width: 24, height: 28) }
                .buttonStyle(.plain).accessibilityLabel(idea.done ? "恢复待办" : "完成待办")
            Button { editing = idea } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(idea.text).font(store.font(14)).lineSpacing(3).lineLimit(3).strikethrough(idea.done)
                        .foregroundStyle(idea.done ? p.secondary : p.foreground).multilineTextAlignment(.leading)
                    if let date = idea.reminder { Label(date.formatted(.dateTime.month().day().hour().minute()), systemImage: "bell").font(store.font(10)).foregroundStyle(p.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 3)
            }.buttonStyle(.plain)
        }.frame(minHeight: 30)
            .contentShape(Rectangle())
            .contextMenu {
                Button("编辑", systemImage: "square.and.pencil") { editing = idea }
                Button("提醒", systemImage: "bell") { reminder = idea }
                Button("和 AI 聊聊", systemImage: "bubble.left") { store.data.drafts["group"] = "一起聊聊这个想法：" + idea.text; store.requestedThread = "group" }
                Button("删除", systemImage: "trash", role: .destructive) { store.deleteIdea(idea.id) }
            }
    }
    private func toggle(_ idea: Idea) { store.toggleIdea(idea.id) }
    private func openRequestedIdea() { if let id = store.requestedIdea, let idea = store.data.ideas.first(where: { $0.id == id }) { editing = idea; store.requestedIdea = nil } }
}

struct IdeaEditor: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    @State var idea: Idea
    var body: some View {
        NavigationStack { Form { TextField("记下此刻的想法…", text: $idea.text, axis: .vertical).lineLimit(5...10).font(store.font(16)).accessibilityIdentifier("idea.input"); Picker("放到", selection: $idea.later) { Text("今天").tag(false); Text("以后").tag(true) }; Toggle("待办", isOn: $idea.task) }.scrollContentBackground(.hidden).sheetTitle("想法", back: false).toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }.matteToolbar(); ToolbarItem(placement: .confirmationAction) { Button("保存") { store.saveIdea(idea); dismiss() }.disabled(idea.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("idea.save") }.matteToolbar() }.background(Palette(store.data.preferences, .light).background) }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible).presentationCornerRadius(LayoutMetrics.sheet)
    }
}
struct ReminderEditor: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    @State var idea: Idea
    @State private var date = Date.now.addingTimeInterval(3600)
    var body: some View {
        NavigationStack { Form { Text(idea.text).font(store.font(14)); DatePicker("提醒时间", selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute]); Button("保存提醒") { idea.reminder = date; Task { await store.setReminder(idea); dismiss() } }; if idea.reminder != nil { Button("取消提醒", role: .destructive) { idea.reminder = nil; UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [idea.id.uuidString]); store.saveIdea(idea); dismiss() } } }.sheetTitle("提醒", back: false).toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }.matteToolbar() } }.onAppear { date = idea.reminder ?? Date.now.addingTimeInterval(3600) }.presentationDetents([.medium, .large]).presentationCornerRadius(LayoutMetrics.sheet)
    }
}
