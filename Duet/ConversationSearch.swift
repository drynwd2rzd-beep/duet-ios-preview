import SwiftUI

struct ConversationSearch: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    let thread: String
    @State private var query = ""
    @State private var kind = "全部"
    @State private var dateFilter = false
    @State private var date = Date()
    @FocusState private var focused: Bool
    private var p: Palette { Palette(store.data.preferences, scheme) }
    private var hits: [ChatMessage] {
        (store.data.messages[thread] ?? []).reversed().filter { message in
            guard !message.text.isEmpty || !message.attachments.isEmpty else { return false }
            if kind == "照片" && !message.attachments.contains(where: \.photo) { return false }
            if kind == "文件" && !message.attachments.contains(where: { !$0.photo }) { return false }
            if kind == "文字" && message.text.isEmpty { return false }
            if dateFilter && !Calendar.current.isDate(message.date, inSameDayAs: date) { return false }
            return query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (message.text + " " + message.attachments.map(\.name).joined(separator: " ")).localizedCaseInsensitiveContains(query.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
    var body: some View {
        let resultGroups = Dictionary(grouping: hits) { Calendar.current.startOfDay(for: $0.date) }
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(p.secondary)
                    TextField("搜索这段对话", text: $query).font(store.font(16)).focused($focused).submitLabel(.search).accessibilityIdentifier("search.input")
                    if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(p.secondary) }.buttonStyle(.plain).accessibilityLabel("清除关键词") }
                }.padding(.horizontal, 14).padding(.vertical, 12).background(p.surface, in: RoundedRectangle(cornerRadius: LayoutMetrics.field)).padding(.horizontal, LayoutMetrics.page).padding(.top, 16)
                HStack(spacing: 23) {
                    ForEach(["全部", "文字", "照片", "文件"], id: \.self) { value in
                        Button { kind = value } label: {
                            VStack(spacing: 9) { Text(value).font(store.font(13, weight: kind == value ? .medium : .regular)).foregroundStyle(kind == value ? p.foreground : p.secondary); Capsule().fill(kind == value ? p.accent : .clear).frame(height: 2) }
                        }.buttonStyle(.plain).accessibilityIdentifier("search.kind." + value).accessibilityAddTraits(kind == value ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                    Button { focused = false; withAnimation(.easeInOut(duration: 0.2)) { dateFilter.toggle() } } label: { Image(systemName: "calendar").font(.system(size: 17)).foregroundStyle(dateFilter ? p.accent : p.secondary).frame(width: 32, height: 34) }.buttonStyle(.plain).accessibilityLabel(dateFilter ? "取消日期筛选" : "按日期筛选")
                }.padding(.horizontal, LayoutMetrics.page).padding(.top, 18).padding(.bottom, 8)
                if dateFilter { DatePicker("日期", selection: $date, displayedComponents: .date).datePickerStyle(.graphical).tint(p.accent).padding(.horizontal, LayoutMetrics.page).accessibilityIdentifier("search.date") }
                if resultGroups.isEmpty {
                    VStack(spacing: 9) { Image(systemName: "text.magnifyingglass").font(.system(size: 25, weight: .light)).foregroundStyle(p.secondary); Text(query.isEmpty ? "这段对话里还没有相关内容" : "没有找到相关消息").font(store.font(14)).foregroundStyle(p.secondary) }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(resultGroups.keys.sorted(by: >), id: \.self) { day in
                            Section {
                                ForEach(resultGroups[day] ?? []) { message in result(message) }
                            } header: { Text(dayLabel(day)).font(store.font(11, weight: .medium)).foregroundStyle(p.secondary).textCase(nil) }
                            .listSectionSeparator(.hidden)
                        }
                    }.listStyle(.plain).scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively)
                }
            }.background(p.background).foregroundStyle(p.foreground).sheetTitle("搜索", back: false)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() }.font(store.font(14, weight: .medium)).accessibilityIdentifier("search.close") }.matteToolbar() }
        }.tint(p.accent).presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(LayoutMetrics.sheet).presentationBackground(p.background)
            .task { try? await Task.sleep(nanoseconds: 250_000_000); guard !Task.isCancelled else { return }; focused = true }
    }
    private func result(_ message: ChatMessage) -> some View {
        Button {
            focused = false; dismiss()
            Task { @MainActor in try? await Task.sleep(nanoseconds: 200_000_000); store.requestedMessage = message.id }
        } label: {
            HStack(alignment: .top, spacing: 11) {
                Avatar(id: message.author == "me" ? "self" : message.author, size: 30)
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text(store.name(message.author)).font(store.font(11, weight: .medium)); Spacer(); Text(message.date.formatted(date: .omitted, time: .shortened)).font(store.font(10)) }.foregroundStyle(p.secondary)
                    Text(highlighted(preview(message))).font(store.font(14)).lineSpacing(3).lineLimit(3).foregroundStyle(p.foreground).multilineTextAlignment(.leading)
                    if !message.attachments.isEmpty { Label(message.attachments.allSatisfy(\.photo) ? "\(message.attachments.count) 张照片" : message.attachments.map(\.name).joined(separator: "、"), systemImage: message.attachments.allSatisfy(\.photo) ? "photo" : "doc").font(store.font(11)).lineLimit(1).foregroundStyle(p.secondary) }
                }
            }.padding(.vertical, 8).contentShape(Rectangle())
        }.buttonStyle(.plain).listRowInsets(EdgeInsets(top: 8, leading: LayoutMetrics.page, bottom: 8, trailing: LayoutMetrics.page)).listRowBackground(p.background).listRowSeparatorTint(p.foreground.opacity(0.06)).accessibilityIdentifier("search.result." + message.id.uuidString)
    }
    private func preview(_ message: ChatMessage) -> String {
        let text = message.text.isEmpty ? (message.attachments.allSatisfy(\.photo) ? "照片" : "文件") : message.text.replacingOccurrences(of: "\n", with: " ")
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let match = keyword.isEmpty ? nil : text.range(of: keyword, options: .caseInsensitive)
        let start = match.flatMap { text.index($0.lowerBound, offsetBy: -32, limitedBy: text.startIndex) } ?? text.startIndex
        let end = text.index(start, offsetBy: 180, limitedBy: text.endIndex) ?? text.endIndex
        return (start > text.startIndex ? "…" : "") + String(text[start..<end]) + (end < text.endIndex ? "…" : "")
    }
    private func highlighted(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty, let source = text.range(of: keyword, options: .caseInsensitive), let range = result.range(of: String(text[source])) { result[range].foregroundColor = p.accent }
        return result
    }
    private func dayLabel(_ day: Date) -> String { Calendar.current.isDateInToday(day) ? "今天" : Calendar.current.isDateInYesterday(day) ? "昨天" : day.formatted(.dateTime.year().month().day()) }
}
