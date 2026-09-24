import SwiftUI
import Textual

struct TopicBlockQuoteStyle: StructuredText.BlockQuoteStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color("BrandSurface"))
                .textual.frame(width: .fontScaled(0.2))
            configuration.label
                .foregroundStyle(.secondary)
                .textual.padding(.horizontal, .fontScaled(1))
        }
    }
}
