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
        GeometryReader { geometry in
            // Expand first, then mask the entire material surface. Masking a
            // fixed-height view before ignoresSafeArea stretches its edge.
            let height = max(210, geometry.safeAreaInsets.top + 175)
            let stops = (0...16).map { index -> Gradient.Stop in
                let position = Double(index) / 16
                let opacity = (1 + cos(.pi * position)) / 2
                return .init(color: .white.opacity(opacity), location: CGFloat(position))
            }
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                p.background.opacity(0.28)
            }
            .frame(height: height)
            .mask(LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom))
            .opacity(strength)
        }.ignoresSafeArea(edges: .top).allowsHitTesting(false).accessibilityHidden(true)
    }
}
