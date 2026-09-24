#if os(iOS)
import UIKit

/// Leave the system's leading-edge back gesture to the navigation controller.
final class EdgeRespectingPagingScrollView: UIScrollView {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            let translation = panGestureRecognizer.translation(in: self)
            let startX = panGestureRecognizer.location(in: self).x - translation.x - bounds.minX
            let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
            let leadingDistance = isRTL ? bounds.width - startX : startX
            // This also rejects leftward drags originating at the back edge.
            guard leadingDistance > max(44, isRTL ? safeAreaInsets.right : safeAreaInsets.left) else { return false }
            guard abs(translation.x) > abs(translation.y) else { return false }
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}
#endif
