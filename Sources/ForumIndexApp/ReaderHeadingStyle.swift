import SwiftUI
import Textual

struct ReaderHeadingStyle: StructuredText.HeadingStyle {
    @Environment(\.readerTypography) private var typography

    func makeBody(configuration: Configuration) -> some View {
        let scale: CGFloat = switch configuration.headingLevel {
        case 1: 1.22
        case 2: 1.11
        default: 1
        }
        configuration.label
            .textual.fontScale(scale)
            .fontWeight(.semibold)
            .textual.lineSpacing(.fontScaled(0.18))
            .textual.blockSpacing(.fontScaled(
                top: typography.headingGap / typography.bodySize,
                bottom: 10 / typography.bodySize
            ))
    }
}
