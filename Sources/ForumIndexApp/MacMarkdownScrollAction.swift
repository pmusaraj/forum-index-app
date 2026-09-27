#if os(macOS)
import SwiftUI

struct MacMarkdownScrollAction: FocusedValueKey {
    typealias Value = MacMarkdownScrollAction
    let scroll: (Int) -> Void
}

extension FocusedValues {
    var markdownScroll: MacMarkdownScrollAction? {
        get { self[MacMarkdownScrollAction.self] }
        set { self[MacMarkdownScrollAction.self] = newValue }
    }
}
#endif
