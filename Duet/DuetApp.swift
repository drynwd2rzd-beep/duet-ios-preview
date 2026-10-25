import SwiftUI
import UIKit
import UserNotifications

@main
struct DuetApp: App {
    @StateObject private var store = NativeStore()
    var body: some Scene {
        WindowGroup { NativeRoot().environmentObject(store).preferredColorScheme(store.appearance) }
    }
}
struct NativeRoot: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    @State private var tab = "chats"
    @State private var path: [String] = []
    private var p: Palette { Palette(store.data.preferences, scheme) }
    var body: some View {
        NavigationStack(path: $path) {
            Group { if tab == "chats" { ChatsHome() } else { IdeasHome() } }
                .navigationDestination(for: String.self) { id in NativeChat(thread: id) }
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .bottom, spacing: 0) { if path.isEmpty { dock.padding(.top, 8).padding(.bottom, 8) } }
        }
        .background(p.background)
        .tint(p.accent)
        .environment(\.font, store.font(14))
        .sheet(isPresented: $store.settingsPresented) { NativeSettings().environmentObject(store).preferredColorScheme(store.appearance) }
        .overlay(alignment: .bottom) { if let text = store.toast { Label(text, systemImage: "checkmark").font(store.font(12)).padding(.horizontal, 16).padding(.vertical, 12).foregroundStyle(p.background).background(p.foreground, in: Capsule()).padding(.bottom, path.isEmpty ? 74 : 90).padding(.horizontal, 20).allowsHitTesting(false).accessibilityIdentifier("feedback.toast") } }
        .onChange(of: store.requestedThread) { _, value in if let value { path = [value]; store.requestedThread = nil } }
    }
    private var dock: some View {
        HStack(spacing: 4) { dockButton("chats", icon: "bubble.left", label: "聊天"); dockButton("ideas", icon: "lightbulb", label: "想法") }.padding(5).glassCapsule()
    }
    private func dockButton(_ id: String, icon: String, label: String) -> some View {
        Button { tab = id; UISelectionFeedbackGenerator().selectionChanged() } label: { Image(systemName: icon).font(.system(size: 19, weight: .regular)).frame(width: 72, height: 44).background(tab == id ? p.accent.opacity(0.1) : .clear, in: Capsule()) }.buttonStyle(.plain).foregroundStyle(tab == id ? p.accent : p.secondary).accessibilityLabel(label).accessibilityIdentifier("tab." + id)
    }
}

struct ChatsHome: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    @State private var search = ""
    private var p: Palette { Palette(store.data.preferences, scheme) }
    private var ordered: [String] { let base = ["group", "gpt", "claude"]; return base.sorted { a, b in let ai = store.data.pinned.firstIndex(of: a) ?? 99; let bi = store.data.pinned.firstIndex(of: b) ?? 99; return ai == bi ? base.firstIndex(of: a)! < base.firstIndex(of: b)! : ai < bi }.filter { search.isEmpty || store.name($0).localizedCaseInsensitiveContains(search) || preview($0).localizedCaseInsensitiveContains(search) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 9) { Text(Date.now.formatted(.dateTime.month(.twoDigits).day().weekday(.wide))).font(store.font(11)).foregroundStyle(p.secondary); Text("Chats").font(store.font(32, weight: .medium)).foregroundStyle(p.accent) }.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 20)
            HStack(spacing: 8) { Image(systemName: "magnifyingglass").foregroundStyle(p.secondary); TextField("搜索", text: $search).font(store.font(16)).accessibilityIdentifier("home.search"); if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(p.secondary) }.accessibilityLabel("清除搜索") } }.padding(12).background(p.surface, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 20).padding(.bottom, 10)
            if ordered.isEmpty { QuietEmpty(icon: "magnifyingglass", title: "没有找到会话", detail: "试试伙伴的名字或消息里的关键词。"); Spacer() }
            else { List { ForEach(ordered, id: \.self) { id in NavigationLink(value: id) { threadRow(id) }.buttonStyle(.plain).accessibilityIdentifier("thread." + id).listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20)).listRowSeparator(.hidden).listRowBackground(Color.clear).swipeActions(edge: .leading, allowsFullSwipe: true) { Button { store.pin(id) } label: { Label(store.data.pinned.contains(id) ? "取消置顶" : "置顶", systemImage: store.data.pinned.contains(id) ? "pin.slash" : "pin") }.tint(p.accent) } } }.listStyle(.plain).scrollContentBackground(.hidden).environment(\.defaultMinListRowHeight, 0) }
        }.background(p.background).foregroundStyle(p.foreground)
    }
    private func threadRow(_ id: String) -> some View {
        HStack(spacing: 12) {
            Avatar(id: id, size: id == "group" ? 54 : 46)
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) { Text(store.name(id)).font(store.font(14, weight: .medium)).lineLimit(1); if store.data.pinned.contains(id) { Image(systemName: "pin").font(.system(size: 10)).foregroundStyle(p.secondary) }; Spacer(minLength: 4); Text(store.data.messages[id]?.last?.date.formatted(date: .omitted, time: .shortened) ?? "").font(store.font(11)).foregroundStyle(p.secondary) }
                Text(preview(id)).font(store.font(12)).foregroundStyle(p.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.horizontal, 14).padding(.vertical, 17).frame(minHeight: 88).background(store.data.pinned.contains(id) ? p.accent.opacity(0.065) : p.surface, in: RoundedRectangle(cornerRadius: 22))
    }
    private func preview(_ id: String) -> String { guard let last = store.data.messages[id]?.last else { return "" }; if !last.text.isEmpty { return last.text.replacingOccurrences(of: "\n", with: " ") }; return last.attachments.allSatisfy(\.photo) ? "[\(last.attachments.count) 张照片]" : "[文件] " + last.attachments.map(\.name).joined(separator: "、") }
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
            HStack {
                Text("Ideas").font(store.font(32, weight: .medium)).foregroundStyle(p.accent); Spacer()
                Button { store.settingsPresented = true } label: { Image(systemName: "gearshape").font(.system(size: 18)).frame(width: 40, height: 40).glassCircle() }.accessibilityLabel("设置").accessibilityIdentifier("open.settings")
                Button { editing = Idea(later: filter == 1) } label: { Image(systemName: "plus").font(.system(size: 19)).frame(width: 40, height: 40).glassCircle() }.accessibilityLabel("记录想法").accessibilityIdentifier("idea.add")
            }.padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 22)
            HStack(spacing: 8) { ForEach(Array(["今天", "以后", "全部"].enumerated()), id: \.offset) { index, label in Button { filter = index } label: { Text(label).font(store.font(12)).padding(.horizontal, 17).padding(.vertical, 9).foregroundStyle(filter == index ? p.accent : p.secondary).background(filter == index ? p.accent.opacity(0.1) : p.surface, in: Capsule()) }.buttonStyle(.plain) } }.padding(.horizontal, 20).padding(.bottom, 12)
            if items.isEmpty { QuietEmpty(icon: "lightbulb", title: "还没有想法", detail: "随手记下，之后再慢慢完善。"); Button("记一笔") { editing = Idea(later: filter == 1) }.font(store.font(13)).frame(maxWidth: .infinity); Spacer() }
            else { List { ForEach(items) { idea in ideaRow(idea).listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20)).listRowSeparator(.hidden).listRowBackground(Color.clear).swipeActions(edge: .leading) { Button { toggle(idea) } label: { Label(idea.done ? "恢复" : "完成", systemImage: "checkmark") }.tint(p.accent) }.swipeActions(edge: .trailing, allowsFullSwipe: false) { Button(role: .destructive) { store.deleteIdea(idea.id) } label: { Label("删除", systemImage: "trash") }; Button { reminder = idea } label: { Label("提醒", systemImage: "bell") }.tint(p.accent) } } }.listStyle(.plain).scrollContentBackground(.hidden) }
        }.background(p.background).foregroundStyle(p.foreground)
        .sheet(item: $editing) { IdeaEditor(idea: $0).environmentObject(store) }
        .sheet(item: $reminder) { ReminderEditor(idea: $0).environmentObject(store) }
    }
    private func ideaRow(_ idea: Idea) -> some View {
        HStack(spacing: 11) {
            Button { toggle(idea) } label: { Image(systemName: idea.done ? "checkmark.circle" : idea.task ? "circle" : "lightbulb").font(.system(size: 20, weight: .light)).foregroundStyle(idea.done ? p.accent : p.secondary).frame(width: 30, height: 44) }.buttonStyle(.plain).accessibilityLabel(idea.done ? "恢复待办" : "完成待办")
            Button { editing = idea } label: { VStack(alignment: .leading, spacing: 5) { Text(idea.text).font(store.font(13)).lineSpacing(3).strikethrough(idea.done).foregroundStyle(idea.done ? p.secondary : p.foreground).multilineTextAlignment(.leading); HStack(spacing: 5) { Text((idea.task ? "待办" : "想法") + " · " + (idea.later ? "以后" : "今天")); if let date = idea.reminder { Image(systemName: "bell"); Text(date.formatted(.dateTime.month().day().hour().minute())) } }.font(store.font(11)).foregroundStyle(p.secondary) }.frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
            Menu { Button("编辑", systemImage: "square.and.pencil") { editing = idea }; Button("提醒", systemImage: "bell") { reminder = idea }; Button("和 AI 聊聊", systemImage: "bubble.left") { store.data.drafts["group"] = "一起聊聊这个想法：" + idea.text; store.requestedThread = "group" }; Button("删除", systemImage: "trash", role: .destructive) { store.deleteIdea(idea.id) } } label: { Image(systemName: "ellipsis").frame(width: 30, height: 44).foregroundStyle(p.secondary) }
        }.padding(.horizontal, 10).padding(.vertical, 13).background(p.surface, in: RoundedRectangle(cornerRadius: 22))
    }
    private func toggle(_ idea: Idea) { if let i = store.data.ideas.firstIndex(where: { $0.id == idea.id }) { store.data.ideas[i].task = true; store.data.ideas[i].done.toggle(); UISelectionFeedbackGenerator().selectionChanged() } }
}

struct IdeaEditor: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    @State var idea: Idea
    var body: some View {
        NavigationStack { Form { TextField("记下此刻的想法…", text: $idea.text, axis: .vertical).lineLimit(5...10).font(store.font(16)).accessibilityIdentifier("idea.input"); Picker("放到", selection: $idea.later) { Text("今天").tag(false); Text("以后").tag(true) }; Toggle("待办", isOn: $idea.task) }.scrollContentBackground(.hidden).sheetTitle("想法").toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("保存") { store.saveIdea(idea); dismiss() }.disabled(idea.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("idea.save") } }.background(Palette(store.data.preferences, .light).background) }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible).presentationCornerRadius(32)
    }
}
struct ReminderEditor: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    @State var idea: Idea
    @State private var date = Date.now.addingTimeInterval(3600)
    var body: some View {
        NavigationStack { Form { Text(idea.text).font(store.font(14)); DatePicker("提醒时间", selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute]); Button("保存提醒") { idea.reminder = date; Task { await store.setReminder(idea); dismiss() } }; if idea.reminder != nil { Button("取消提醒", role: .destructive) { idea.reminder = nil; UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [idea.id.uuidString]); store.saveIdea(idea); dismiss() } } }.sheetTitle("提醒").toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } } }.onAppear { date = idea.reminder ?? Date.now.addingTimeInterval(3600) }.presentationDetents([.medium, .large]).presentationCornerRadius(32)
    }
}
