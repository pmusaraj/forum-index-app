#if os(macOS)
import ForumIndexCore
import SwiftUI

/// Owns a web loader for one selection, independent of feed prefetching and settings sheets.
struct MacTopicDetailView: View {
    let bookmark: Bookmark
    @Bindable var signals: SignalStore
    @Binding var bookmarkData: Data
    let dismiss: () -> Void
    @State private var preloader = WebPagePreloader()

    var body: some View {
        WebPageSheet(preloader: preloader, signals: signals, bookmark: bookmark,
                     topic: bookmark.topic, bookmarkData: $bookmarkData, dismissAction: dismiss)
            .task {
                if bookmark.topic?.forum.supportsMarkdown != true {
                    preloader.preload(bookmark.url)
                }
            }
            .onDisappear { preloader.clear() }
    }
}
#endif
