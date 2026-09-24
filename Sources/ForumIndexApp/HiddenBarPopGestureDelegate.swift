#if os(iOS)
import UIKit

/// Allows UIKit's interactive pop while this detail screen hides its navigation bar.
final class HiddenBarPopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var navigationController: UINavigationController?
    weak var originalDelegate: UIGestureRecognizerDelegate?

    init(navigationController: UINavigationController, originalDelegate: UIGestureRecognizerDelegate?) {
        self.navigationController = navigationController
        self.originalDelegate = originalDelegate
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController,
              navigationController.viewControllers.count > 1,
              navigationController.transitionCoordinator == nil else { return false }
        if navigationController.isNavigationBarHidden { return true }
        return originalDelegate?.gestureRecognizerShouldBegin?(gestureRecognizer) ?? true
    }

}
#endif
