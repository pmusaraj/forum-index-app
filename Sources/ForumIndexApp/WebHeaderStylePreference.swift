import SwiftUI

struct WebHeaderStylePreference: PreferenceKey {
    static let defaultValue: Bool? = nil

    static func reduce(value: inout Bool?, nextValue: () -> Bool?) {
        value = nextValue() ?? value
    }
}
