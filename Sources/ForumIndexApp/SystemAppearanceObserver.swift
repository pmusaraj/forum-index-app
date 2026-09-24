#if os(iOS)
import SwiftUI
import UIKit

/// Reads the system theme independently of website-specific status-bar contrast.
struct SystemAppearanceObserver: UIViewRepresentable {
    @Binding var colorScheme: ColorScheme?

    func makeUIView(context: Context) -> AppearanceObservationView {
        AppearanceObservationView()
    }

    func updateUIView(_ view: AppearanceObservationView, context: Context) {
        view.onChange = { if colorScheme != $0 { colorScheme = $0 } }
        view.observeScene()
    }
}

#endif
