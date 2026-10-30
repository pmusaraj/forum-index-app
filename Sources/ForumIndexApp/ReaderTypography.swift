import SwiftUI

enum ReaderTypography: String, CaseIterable, Identifiable {
    static let defaultsKey = "reader-typography"

    case compact, spacious

    var id: String { rawValue }
    var title: String { self == .compact ? "Compact" : "Spacious" }

    var bodySize: CGFloat { self == .spacious ? 18 : 16 }
    var titleSize: CGFloat { self == .spacious ? 24 : 22 }
    var inset: CGFloat { self == .spacious ? 28 : 24 }
    var paragraphGap: CGFloat { self == .spacious ? 22 : 16 }
    var leading: CGFloat { self == .spacious ? 0.4 : 0.18 }
    var headingGap: CGFloat { self == .spacious ? 30 : 24 }
    var listGap: CGFloat { self == .spacious ? 8 : 5 }
}

extension EnvironmentValues {
    @Entry var readerTypography: ReaderTypography = .compact
}
