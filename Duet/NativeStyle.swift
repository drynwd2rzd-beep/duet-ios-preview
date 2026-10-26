import SwiftUI
import UIKit

private struct ChatViewport: Equatable {
    var bottom: Bool
    var height: CGFloat
    var viewportHeight: CGFloat
}

enum LayoutMetrics {
    static let page: CGFloat = 22
    static let section: CGFloat = 20
    static let rowGap: CGFloat = 12
    static let card: CGFloat = 18
    static let field: CGFloat = 14
    static let sheet: CGFloat = 24
}

struct TypingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    var body: some View {
        Group {
            if reduceMotion { dots(phase: nil) }
            else { PhaseAnimator([0, 1, 2]) { phase in dots(phase: phase) } animation: { _ in .easeInOut(duration: 0.4) } }
        }.accessibilityElement(children: .ignore)
    }
    private func dots(phase: Int?) -> some View {
        HStack(spacing: 5) { ForEach(0..<3) { index in Circle().fill(color).frame(width: 5, height: 5).opacity(phase == nil || phase == index ? 0.9 : 0.3).offset(y: phase == index ? -1 : 0) } }
    }
}

struct Palette {
    let background: Color
    let foreground: Color
    let secondary: Color
    let surface: Color
    let accent: Color
    let mine: Color
    let dark: Bool
    init(_ settings: Preferences, _ scheme: ColorScheme) {
        dark = scheme == .dark
        let backgrounds = ["porcelain": ["FAF9F7", "19191D"], "blush": ["FAF1F5", "261B23"], "cream": ["FAF5EE", "252019"], "mist": ["F1F5FA", "19212A"]]
        background = Color(uiColor: UIColor(hex: (backgrounds[settings.background] ?? backgrounds["porcelain"]!)[dark ? 1 : 0]))
        foreground = Color(uiColor: UIColor(hex: dark ? "ECECEF" : "29272C"))
        secondary = Color(uiColor: UIColor(hex: dark ? "B2B2BA" : "74747B"))
        surface = foreground.opacity(dark ? 0.075 : 0.035)
        let themes = ["rose": ["876D7C", "C4B2BC"], "blue": ["5B708D", "A4BCD6"], "sage": ["5D7A6E", "A7C9B6"], "apricot": ["8E6D4B", "D6BB95"]]
        accent = Color(uiColor: UIColor(hex: settings.theme == "custom" ? settings.customHex : (themes[settings.theme] ?? themes["rose"]!)[dark ? 1 : 0]))
        mine = accent.opacity(dark ? 0.12 : 0.07)
    }
}
extension View {
    func mattePanel(radius: CGFloat = LayoutMetrics.card) -> some View { modifier(MatteSurface(radius: radius)) }
    func matteCircle() -> some View { modifier(MatteSurface(radius: 100)) }
    @ViewBuilder func trackChatBottom(_ binding: Binding<Bool>, following: Binding<Bool>, interacting: Binding<Bool>, contentChanged: @escaping () -> Void) -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollGeometryChange(for: ChatViewport.self) { geometry in
                ChatViewport(bottom: geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height + geometry.contentInsets.bottom - 72, height: geometry.contentSize.height, viewportHeight: geometry.containerSize.height)
            } action: { old, value in
                binding.wrappedValue = value.bottom
                if interacting.wrappedValue { following.wrappedValue = value.bottom }
                if old.height != value.height || old.viewportHeight != value.viewportHeight { contentChanged() }
            }.onScrollPhaseChange { old, phase in
                if phase == .interacting || phase == .decelerating { interacting.wrappedValue = true }
                else if phase == .idle { if old == .interacting || old == .decelerating { following.wrappedValue = binding.wrappedValue }; interacting.wrappedValue = false }
            }
        }
        else { self.simultaneousGesture(DragGesture(minimumDistance: 8).onChanged { value in interacting.wrappedValue = true; if value.translation.height > 8 { following.wrappedValue = false } }.onEnded { _ in interacting.wrappedValue = false }) }
    }
}
struct BrandMark: View {
    var id: String
    var size: CGFloat = 16
    var body: some View { Image(id == "claude" ? "BrandClaude" : "BrandGPT").renderingMode(.template).resizable().scaledToFit().frame(width: size, height: size).accessibilityLabel(id == "claude" ? "Claude" : "ChatGPT") }
}
struct Avatar: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    var id: String
    var size: CGFloat = 44
    var composite = true
    private var p: Palette { Palette(store.data.preferences, scheme) }
    var body: some View {
        if id == "group", store.profile("group").avatar == nil, composite {
            ZStack {
                Avatar(id: "gpt", size: size * 0.59).offset(x: -size * 0.23, y: -size * 0.19)
                Avatar(id: "claude", size: size * 0.59).offset(x: size * 0.23, y: -size * 0.19)
                Avatar(id: "self", size: size * 0.59).overlay(Circle().stroke(p.background, lineWidth: 2)).offset(y: size * 0.23)
            }.frame(width: size, height: size).accessibilityLabel(store.name("gpt") + "、" + store.name("claude") + "和" + store.name("self"))
        } else {
            ZStack {
                Circle().fill(fill)
                if let image = store.image(store.profile(id).avatar) { Image(uiImage: image).resizable().scaledToFill().frame(width: size, height: size).clipShape(Circle()) }
                else if id == "gpt" || id == "claude" { BrandMark(id: id, size: size * 0.52).foregroundStyle(p.foreground) }
                else { Image(systemName: id == "group" ? "person.3" : "person.crop.circle").font(.system(size: size * 0.49, weight: .ultraLight)).foregroundStyle(p.accent) }
            }.frame(width: size, height: size).clipShape(Circle()).accessibilityLabel(store.name(id) + "的头像")
        }
    }
    private var fill: Color {
        if id == "gpt" { return Color(uiColor: UIColor(hex: p.dark ? "293B36" : "E7EFEB")) }
        if id == "claude" { return Color(uiColor: UIColor(hex: p.dark ? "47382F" : "F3E6DC")) }
        return p.foreground.opacity(0.05)
    }
}
struct QuietEmpty: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    var icon: String
    var title: String
    var detail: String
    var body: some View {
        let p = Palette(store.data.preferences, scheme)
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 23, weight: .light)).foregroundStyle(p.accent).frame(width: 48, height: 48).background(p.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: LayoutMetrics.field))
            Text(title).font(store.font(14, weight: .medium)).foregroundStyle(p.foreground)
            Text(detail).font(store.font(12)).foregroundStyle(p.secondary).multilineTextAlignment(.center).lineSpacing(4)
        }.frame(maxWidth: .infinity).padding(.vertical, 44).padding(.horizontal, 24)
    }
}
struct PrimaryAction: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    var title: String
    var action: () -> Void
    var body: some View {
        let p = Palette(store.data.preferences, scheme)
        Button(action: action) { Text(title).font(store.font(14, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 12).foregroundStyle(p.background).background(p.accent, in: RoundedRectangle(cornerRadius: LayoutMetrics.field)) }.buttonStyle(.plain)
    }
}

private struct MatteSurface: ViewModifier {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    let radius: CGFloat
    func body(content: Content) -> some View {
        let p = Palette(store.data.preferences, scheme)
        content.background(p.background, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(p.foreground.opacity(0.065), lineWidth: 0.5))
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder func matteToolbar() -> some ToolbarContent {
        if #available(iOS 26.0, *) { self.sharedBackgroundVisibility(.hidden) }
        else { self }
    }
}
struct SheetTitle: ViewModifier {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    var title: String
    var back = true
    func body(content: Content) -> some View {
        content.navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden(back)
            .presentationBackground(Palette(store.data.preferences, scheme).background)
            .toolbar {
                ToolbarItem(placement: .principal) { Text(title).font(store.font(17, weight: .medium)) }.matteToolbar()
                if back { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 19)).frame(width: 32, height: 44).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("返回") }.matteToolbar() }
            }
    }
}
extension View { func sheetTitle(_ title: String, back: Bool = true) -> some View { modifier(SheetTitle(title: title, back: back)) } }
enum SettingsRoute: Hashable {
    case appearance, people, profile(String), personas, persona(String), accounts, automation, notifications, model(String), background(String), role(String, String), history
}

