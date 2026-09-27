#if os(macOS)
import SwiftUI

struct MacTopicStarAction: FocusedValueKey {
    typealias Value = MacTopicStarAction
    let isStarred: Bool
    let toggle: () -> Void
}

extension FocusedValues {
    var topicStar: MacTopicStarAction? {
        get { self[MacTopicStarAction.self] }
        set { self[MacTopicStarAction.self] = newValue }
    }
}
#endif
