import SwiftUI
import UIKit

struct NativePhotoStack: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let photos: [ChatAttachment]
    var open: ([ChatAttachment], Int) -> Void
    @State private var index = 0
    @State private var drag: CGFloat = 0
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if expanded {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: min(3, photos.count)), spacing: 6) { ForEach(Array(photos.enumerated()), id: \.element.id) { position, photo in Button { open(photos, position) } label: { if let image = store.image(photo.path) { Image(uiImage: image).resizable().scaledToFill().frame(width: 67, height: 72).clipShape(RoundedRectangle(cornerRadius: 12)) } }.buttonStyle(.plain).accessibilityLabel("查看第 \(position + 1) 张照片") } }.frame(width: 218)
                Button { withAnimation(animation) { expanded = false } } label: { Image(systemName: "square.stack").font(.system(size: 14)).padding(8).glassCircle() }.accessibilityLabel("叠放照片")
            } else {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        ForEach((0..<min(3, photos.count)).reversed(), id: \.self) { layer in
                            if let image = store.image(photos[(index + layer) % photos.count].path) {
                                Image(uiImage: image).resizable().scaledToFill().frame(width: 196, height: 157).clipShape(RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.85), lineWidth: 2.5)).shadow(color: .black.opacity(0.08), radius: 6, y: 3).rotationEffect(.degrees(layer == 0 ? Double(drag / 16) : layer == 1 ? 6 : -7)).offset(x: layer == 0 ? drag : CGFloat(layer * 3 - 2), y: CGFloat(layer == 0 ? 5 : -layer * 3))
                            }
                        }
                    }.frame(width: 218, height: 182).contentShape(Rectangle()).onTapGesture { open(photos, index) }.simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { value in if abs(value.translation.width) > abs(value.translation.height) { drag = max(-110, min(110, value.translation.width)) } }.onEnded { value in if abs(value.translation.width) > 35 && abs(value.translation.width) > abs(value.translation.height) { withAnimation(animation) { index = (index + (value.translation.width < 0 ? 1 : photos.count - 1)) % photos.count; drag = 0 } } else { withAnimation(animation) { drag = 0 } } }).accessibilityLabel("\(photos.count) 张照片，点击查看大图").accessibilityIdentifier("photo.stack")
                    Button { withAnimation(animation) { expanded = true } } label: { Label("\(index + 1) / \(photos.count)", systemImage: "photo.on.rectangle").font(store.font(11)).padding(.horizontal, 9).padding(.vertical, 7).foregroundStyle(.white).background(.black.opacity(0.45), in: Capsule()) }.buttonStyle(.plain).offset(x: -4, y: -3).accessibilityLabel("展开全部照片")
                }
            }
        }
    }
    private var animation: Animation? { reduceMotion ? nil : .spring(response: 0.33, dampingFraction: 0.86) }
}

struct NativeGallery: View {
    @EnvironmentObject private var store: NativeStore
    @Environment(\.dismiss) private var dismiss
    let photos: [ChatAttachment]
    @State var index: Int
    @State private var zoomed = false
    @State private var offset: CGFloat = 0
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack { Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 17)).frame(width: 40, height: 40).glassCircle() }.accessibilityLabel("关闭照片").accessibilityIdentifier("photo.close"); Spacer(); Text("\(index + 1) / \(photos.count)").font(store.font(12)).foregroundStyle(.white.opacity(0.8)); Spacer(); Color.clear.frame(width: 40, height: 40) }.padding(.horizontal, 18).padding(.vertical, 8)
                TabView(selection: $index) { ForEach(Array(photos.enumerated()), id: \.element.id) { position, photo in ZoomablePhoto(image: store.image(photo.path), identity: photo.path, zoomChanged: { if index == position { zoomed = $0 } }).tag(position).accessibilityIdentifier("photo.zoomable") } }.tabViewStyle(.page(indexDisplayMode: .never)).offset(y: offset).onChange(of: index) { _, _ in zoomed = false }
                ScrollView(.horizontal) { HStack(spacing: 6) { ForEach(Array(photos.enumerated()), id: \.element.id) { position, photo in Button { index = position } label: { if let image = store.image(photo.path) { Image(uiImage: image).resizable().scaledToFill().frame(width: 34, height: 40).clipShape(RoundedRectangle(cornerRadius: 6)).opacity(index == position ? 1 : 0.45) } }.buttonStyle(.plain) } }.frame(maxWidth: .infinity).padding(16) }.frame(height: 76)
            }
        }.foregroundStyle(.white).preferredColorScheme(.dark).simultaneousGesture(DragGesture(minimumDistance: 25).onChanged { value in if !zoomed && value.translation.height > 0 && value.translation.height > abs(value.translation.width) { offset = value.translation.height * 0.75 } }.onEnded { value in if !zoomed && value.translation.height > 100 && value.translation.height > abs(value.translation.width) { dismiss() } else { withAnimation(.easeOut(duration: 0.2)) { offset = 0 } } })
    }
}

struct ZoomablePhoto: UIViewRepresentable {
    let image: UIImage?
    let identity: String
    var zoomChanged: (Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(zoomChanged: zoomChanged) }
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = PhotoScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 4
        scroll.bouncesZoom = true
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.backgroundColor = .clear
        let imageView = UIImageView(image: image); imageView.contentMode = .scaleAspectFit; imageView.isUserInteractionEnabled = true
        scroll.addSubview(imageView); scroll.photo = imageView
        context.coordinator.imageView = imageView
        context.coordinator.identity = identity
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:))); doubleTap.numberOfTapsRequired = 2; scroll.addGestureRecognizer(doubleTap)
        scroll.panGestureRecognizer.isEnabled = false
        return scroll
    }
    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.zoomChanged = zoomChanged
        if context.coordinator.identity != identity { context.coordinator.identity = identity; context.coordinator.imageView?.image = image; uiView.setZoomScale(1, animated: false) }
    }
    final class PhotoScrollView: UIScrollView {
        weak var photo: UIImageView?
        private var previousSize = CGSize.zero
        override func layoutSubviews() { super.layoutSubviews(); if bounds.size != previousSize && zoomScale <= 1.001 { previousSize = bounds.size; photo?.frame = CGRect(origin: .zero, size: bounds.size); contentSize = bounds.size } }
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        var identity = ""
        var zoomChanged: (Bool) -> Void
        init(zoomChanged: @escaping (Bool) -> Void) { self.zoomChanged = zoomChanged }
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        func scrollViewDidZoom(_ scrollView: UIScrollView) { let zoomed = scrollView.zoomScale > 1.01; scrollView.panGestureRecognizer.isEnabled = zoomed; zoomChanged(zoomed) }
        @objc func doubleTap(_ recognizer: UITapGestureRecognizer) { guard let scroll = recognizer.view as? UIScrollView else { return }; scroll.setZoomScale(scroll.zoomScale > 1.01 ? 1 : 2.2, animated: true) }
    }
}

struct NativeCamera: UIViewControllerRepresentable {
    let finished: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(finished: finished) }
    func makeUIViewController(context: Context) -> UIImagePickerController { let picker = UIImagePickerController(); picker.sourceType = .camera; picker.cameraCaptureMode = .photo; picker.delegate = context.coordinator; return picker }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) { }
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let finished: (UIImage?) -> Void
        init(finished: @escaping (UIImage?) -> Void) { self.finished = finished }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { finished(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { finished(info[.originalImage] as? UIImage) }
    }
}
