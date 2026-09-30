import SwiftUI
import Textual

struct TopicThematicBreakStyle: StructuredText.ThematicBreakStyle {
    func makeBody(configuration: Configuration) -> some View {
#if os(macOS)
        Divider()
            .textual.blockSpacing(.init(top: 24, bottom: 24))
#else
        Rectangle()
            .fill(Color("BrandBorder"))
            .textual.frame(height: .fontScaled(0.25))
            .textual.blockSpacing(.init(top: 24, bottom: 24))
#endif
    }
}
