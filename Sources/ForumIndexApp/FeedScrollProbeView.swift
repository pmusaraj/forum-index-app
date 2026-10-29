#if os(iOS)
import UIKit

final class FeedScrollProbeView: UIView {
    private let restorer: FeedScrollRestorer

    init(restorer: FeedScrollRestorer) {
        self.restorer = restorer
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        var ancestor = superview
        while let view = ancestor {
            if let scrollView = view as? UIScrollView {
                restorer.attach(scrollView)
                return
            }
            ancestor = view.superview
        }
    }
}
#endif
