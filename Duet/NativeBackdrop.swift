import SwiftUI

struct NativeBackdrop: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    let thread: String
    var options: BackdropOptions? = nil
    var body: some View {
        let p = Palette(store.data.preferences, scheme)
        let settings = options ?? store.backdrop(thread)
        GeometryReader { geometry in
            ZStack {
                p.background
                if let image = store.image(store.data.backgrounds[thread]) {
                    let scale = max(geometry.size.width / image.size.width, geometry.size.height / image.size.height) * CGFloat(max(1, min(2, settings.zoom)))
                    let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
                        .position(x: geometry.size.width / 2 + (size.width - geometry.size.width) * CGFloat(max(-1, min(1, settings.x))) / 2, y: geometry.size.height / 2 + (size.height - geometry.size.height) * CGFloat(max(-1, min(1, settings.y))) / 2)
                        .blur(radius: max(0, min(16, settings.blur)))
                    Color.black.opacity(max(0, min(0.7, settings.dim)))
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct ChatHeaderFade: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.colorScheme) private var scheme
    let thread: String
    var body: some View {
        let p = Palette(store.data.preferences, scheme)
        let strength = store.backdrop(thread).headerFade
        LinearGradient(stops: [.init(color: p.background.opacity(strength), location: 0), .init(color: p.background.opacity(strength * 0.9), location: 0.45), .init(color: p.background.opacity(strength * 0.45), location: 0.75), .init(color: p.background.opacity(0), location: 1)], startPoint: .top, endPoint: .bottom)
            .frame(height: 150).ignoresSafeArea(edges: .top).allowsHitTesting(false).accessibilityHidden(true)
    }
}
