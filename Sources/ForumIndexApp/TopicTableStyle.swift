import SwiftUI
import Textual

struct TopicTableStyle: StructuredText.TableStyle {
    @Environment(\.displayScale) private var displayScale

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .textual.tableCellSpacing(horizontal: 0, vertical: 0)
            .textual.blockSpacing(.init(top: 0, bottom: 16))
            .textual.tableBackground { layout in
                Canvas { context, size in
                    guard let header = layout.rowIndices.first else { return }
                    let row = layout.rowBounds(header)
                    let bounds = CGRect(x: 0, y: row.minY, width: size.width, height: row.height)
                    context.fill(
                        Path(roundedRect: bounds, cornerRadius: 6),
                        with: .color(Color("BrandSurface"))
                    )
                }
            }
            .textual.tableOverlay { layout in
                Canvas { context, size in
                    // The header fill separates it from the body; only body rows need rules.
                    for row in layout.rowIndices.dropFirst().dropLast() {
                        let bounds = CGRect(
                            x: 0,
                            y: layout.rowBounds(row).maxY,
                            width: size.width,
                            height: 1 / displayScale
                        )
                        context.fill(Path(bounds), with: .color(Color("BrandBorder")))
                    }
                }
            }
    }
}
