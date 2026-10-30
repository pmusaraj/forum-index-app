import SwiftUI
import Textual

struct ReaderTypographyModifier: ViewModifier {
    @Environment(\.readerTypography) private var typography

    func body(content: Content) -> some View {
        content
            .textual.headingStyle(ReaderHeadingStyle())
            .textual.paragraphStyle(ReaderParagraphStyle())
            .textual.listItemSpacing(.fontScaled(top: 0, bottom: typography.listGap / typography.bodySize))
    }
}
