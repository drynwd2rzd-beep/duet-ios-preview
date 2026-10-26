import SwiftUI
import UIKit

enum LayoutMetrics {
    static let page: CGFloat = 20
    static let section: CGFloat = 16
    static let rowGap: CGFloat = 12
    static let card: CGFloat = 22
    static let field: CGFloat = 16
    static let sheet: CGFloat = 28
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
        let backgrounds = ["porcelain": ["FCFAFB", "1D181E"], "blush": ["FAF1F5", "261B23"], "cream": ["FAF5EE", "252019"], "mist": ["F1F5FA", "19212A"]]
        background = Color(uiColor: UIColor(hex: (backgrounds[settings.background] ?? backgrounds["porcelain"]!)[dark ? 1 : 0]))
        foreground = Color(uiColor: UIColor(hex: dark ? "ECECEF" : "29272C"))
        secondary = Color(uiColor: UIColor(hex: dark ? "ADADB7" : "85838D"))
        surface = foreground.opacity(dark ? 0.075 : 0.035)
        let themes = ["rose": ["9A647C", "C8A3B3"], "blue": ["5B708D", "A4BCD6"], "sage": ["5D7A6E", "A7C9B6"], "apricot": ["8E6D4B", "D6BB95"]]
        accent = Color(uiColor: UIColor(hex: settings.theme == "custom" ? settings.customHex : (themes[settings.theme] ?? themes["rose"]!)[dark ? 1 : 0]))
        mine = accent.opacity(dark ? 0.2 : 0.1)
    }
}
extension View {
    @ViewBuilder func nativePanel(radius: CGFloat = LayoutMetrics.card) -> some View {
        if #available(iOS 26.0, *) { self.glassEffect(.regular, in: .rect(cornerRadius: radius)) }
        else { self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius)) }
    }
    @ViewBuilder func glassCapsule() -> some View {
        if #available(iOS 26.0, *) { self.glassEffect(.regular, in: .capsule) }
        else { self.background(.ultraThinMaterial, in: Capsule()) }
    }
    @ViewBuilder func glassCircle() -> some View {
        if #available(iOS 26.0, *) { self.glassEffect(.regular.interactive(), in: .circle) }
        else { self.background(.ultraThinMaterial, in: Circle()) }
    }
    @ViewBuilder func trackChatBottom(_ binding: Binding<Bool>) -> some View {
        if #available(iOS 18.0, *) { self.onScrollGeometryChange(for: Bool.self) { geometry in geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 100 } action: { _, value in binding.wrappedValue = value } }
        else { self }
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
        Group { if #available(iOS 26.0, *) { Button(action: action) { Text(title).font(store.font(14, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.glassProminent) }
        else { Button(action: action) { Text(title).font(store.font(14, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 8) }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule) } }.tint(Palette(store.data.preferences, scheme).accent)
    }
}
struct SheetTitle: ViewModifier {
    @EnvironmentObject private var store: NativeStore
    var title: String
    func body(content: Content) -> some View { content.navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .principal) { Text(title).font(store.font(17, weight: .medium)) } } }
}
extension View { func sheetTitle(_ title: String) -> some View { modifier(SheetTitle(title: title)) } }
enum SettingsRoute: Hashable {
    case appearance, people, profile(String), personas, persona(String), accounts, automation, notifications, model(String), background(String), role(String, String), history
}

