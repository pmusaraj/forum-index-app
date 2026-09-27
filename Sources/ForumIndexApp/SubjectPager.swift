#if os(iOS)
import ForumIndexCore
import SwiftUI

/// Keeps transient scroll-position updates out of the shared reader state.
struct SubjectPager<Content: View>: View {
    let destinations: [ReaderDestination]
    @Binding var selection: String?
    @ViewBuilder let content: (ReaderDestination) -> Content
    @State private var scrollID: String?
    @State private var phase: ScrollPhase = .idle

    var body: some View {
        ScrollView(.horizontal) {
            // Keep each list mounted so returning to a subject preserves its offset.
            HStack(spacing: 0) {
                ForEach(destinations) { destination in
                    content(destination)
                        .containerRelativeFrame(.horizontal)
                        .id(destination.id)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("feed-page-\(destination.id)")
                        .accessibilityHidden(destination.id != selection)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrollID)
        .accessibilityIdentifier("feed-pager")
        .onScrollPhaseChange { _, newPhase in
            phase = newPhase
            if newPhase == .idle { commitSelection() }
        }
        .onChange(of: scrollID) { _, _ in
            // Also handles nonanimated and accessibility-driven scrolling.
            if phase == .idle { commitSelection() }
        }
        .onChange(of: selection, initial: true) { _, selectedID in
            if scrollID != selectedID { scrollID = selectedID }
        }
    }

    private func commitSelection() {
        guard let scrollID, destinations.contains(where: { $0.id == scrollID }),
              selection != scrollID else { return }
        selection = scrollID
    }
}
#endif
