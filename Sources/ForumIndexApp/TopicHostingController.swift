#if os(iOS)
import SwiftUI
import UIKit

final class TopicHostingController<Content: View>: UIHostingController<AnyView> {
    private(set) var usesLightStatusBar: Bool?
    var onHeaderStyleChange: (() -> Void)?

    init(content: Content) {
        super.init(rootView: AnyView(EmptyView()))
        updateContent(content)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func updateContent(_ content: Content) {
        rootView = AnyView(content.onPreferenceChange(WebHeaderStylePreference.self) { [weak self] light in
            Task { @MainActor [weak self] in
                guard let self, self.usesLightStatusBar != light else { return }
                self.usesLightStatusBar = light
                self.onHeaderStyleChange?()
            }
        })
    }
}
#endif
