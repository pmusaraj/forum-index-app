#if os(macOS)
import SwiftUI

struct MacReaderNavigationActions: FocusedValueKey {
    typealias Value = MacReaderNavigationActions

    let moveTopic: (Int) -> Void
    let moveSubject: (Int) -> Void
    let refresh: () -> Void
    let canRefresh: Bool
    let showShortcuts: () -> Void
    let toggleSidebar: () -> Void
    let showSettings: () -> Void
}

extension FocusedValues {
    var readerNavigation: MacReaderNavigationActions? {
        get { self[MacReaderNavigationActions.self] }
        set { self[MacReaderNavigationActions.self] = newValue }
    }
}
#endif
