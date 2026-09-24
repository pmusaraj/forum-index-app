import Foundation
#if os(iOS)
import UIKit
#endif

enum DeviceIdentity {
    static let overrideKey = "device-name-override"

    @MainActor static var detectedName: String {
#if os(iOS)
        UIDevice.current.name
#else
        Host.current().localizedName ?? "Mac"
#endif
    }

    @MainActor static var enrollmentName: String {
        let override = UserDefaults.standard.string(forKey: overrideKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = override.isEmpty ? detectedName : override
        return String(String.UnicodeScalarView(name.unicodeScalars.prefix(100)))
    }
}
