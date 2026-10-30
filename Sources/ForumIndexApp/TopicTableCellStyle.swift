import SwiftUI
import Textual

struct TopicTableCellStyle: StructuredText.TableCellStyle {
    func makeBody(configuration: Configuration) -> some View {
        let isHeader = configuration.row == 0

        configuration.label
            .textual.fontScale(isHeader ? 0.82 : 0.94)
            .fontWeight(isHeader ? .semibold : (configuration.column == 0 ? .medium : .regular))
            .foregroundStyle(isHeader ? .secondary : .primary)
            .textual.lineSpacing(.fontScaled(0.25))
            .padding(.horizontal, 12)
            .padding(.vertical, isHeader ? 10 : 12)
            .alignmentGuide(VerticalAlignment.center) { dimensions in
                dimensions[.top]
            }
    }
}
