import SwiftUI

struct TopicImageLightbox: View {
    let image: TopicImage
    @Environment(\.dismiss) private var dismiss
    @State private var zoom = 1.0
    @GestureState private var magnification = 1.0
    @State private var retryID = UUID()

    private var scale: Double { min(max(zoom * magnification, 1), 5) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(image.label).lineLimit(1)
                Spacer()
                Button("Zoom out", systemImage: "minus.magnifyingglass") { zoom = max(1, zoom - 1) }
                    .disabled(zoom <= 1)
                Button("Zoom in", systemImage: "plus.magnifyingglass") { zoom = min(5, zoom + 1) }
                    .disabled(zoom >= 5)
                    .accessibilityIdentifier("image-lightbox-zoom-in")
                Button("Fit", action: resetZoom)
                Button("Close", systemImage: "xmark", action: close)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("image-lightbox-close")
            }
            .labelStyle(.iconOnly)
            .padding()
            GeometryReader { geometry in
                AsyncImage(url: image.url) { phase in
                    switch phase {
                    case .success(let loaded):
                        ScrollView([.horizontal, .vertical]) {
                            loaded.resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: geometry.size.width * scale, height: geometry.size.height * scale)
                                .accessibilityHidden(false)
                                .accessibilityLabel(image.label)
                                .accessibilityIdentifier("image-lightbox-image")
                        }
                        .defaultScrollAnchor(.center)
                        .gesture(MagnifyGesture()
                            .updating($magnification) { value, state, _ in state = value.magnification }
                            .onEnded { value in zoom = min(max(zoom * value.magnification, 1), 5) })
                    case .failure:
                        ContentUnavailableView {
                            Label("Couldn’t load image", systemImage: "photo")
                        } actions: {
                            Button("Retry") { retryID = UUID() }
                        }
                    default:
                        ProgressView("Loading image…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .id(retryID)
            }
        }
        .foregroundStyle(.white)
        .background(.black)
        .preferredColorScheme(.dark)
#if os(macOS)
        .frame(minWidth: 640, idealWidth: 1000, minHeight: 480, idealHeight: 750)
#endif
    }

    private func resetZoom() { zoom = 1 }
    private func close() { dismiss() }
}
