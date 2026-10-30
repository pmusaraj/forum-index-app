import SwiftUI
import Textual

struct ReaderParagraphStyle: StructuredText.ParagraphStyle {
    @Environment(\.readerTypography) private var typography

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .textual.lineSpacing(.fontScaled(typography.leading))
            .textual.blockSpacing(.fontScaled(top: 0, bottom: typography.paragraphGap / typography.bodySize))
    }
}
