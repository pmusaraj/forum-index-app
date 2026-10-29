#if os(iOS)
import SwiftUI
import UIKit

/// A row supplies an unambiguous ancestor chain to its own List's scroll view.
struct FeedScrollProbe: UIViewRepresentable {
    let restorer: FeedScrollRestorer

    func makeUIView(context: Context) -> FeedScrollProbeView {
        FeedScrollProbeView(restorer: restorer)
    }

    func updateUIView(_ view: FeedScrollProbeView, context: Context) {}
}
#endif
