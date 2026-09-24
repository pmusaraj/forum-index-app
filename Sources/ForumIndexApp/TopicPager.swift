#if os(iOS)
import SwiftUI

struct TopicPager<Content: View>: UIViewControllerRepresentable {
    let count: Int
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    @ViewBuilder let content: (Int) -> Content

    func makeUIViewController(context: Context) -> TopicPagingController<Content> {
        TopicPagingController(count: count, selectedIndex: selectedIndex, onSelect: onSelect, content: content)
    }

    func updateUIViewController(_ controller: TopicPagingController<Content>, context: Context) {
        controller.update(selectedIndex: selectedIndex, onSelect: onSelect, content: content)
    }
}
#endif
