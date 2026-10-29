import ForumIndexCore
import SwiftUI

/// Opens a saved topic with the same Markdown/web reader used by the feed.
struct BookmarkReaderView: View {
    let bookmark: Bookmark
    @Bindable var signals: SignalStore
    @Binding var bookmarkData: Data
    @State private var preloader = WebPagePreloader()

    var body: some View {
        GeometryReader { geometry in
            WebPageSheet(
                preloader: preloader, signals: signals,
                bookmark: bookmark, topic: bookmark.topic,
                bookmarkData: $bookmarkData, safeAreaInsets: geometry.safeAreaInsets
            )
            .ignoresSafeArea(.container)
        }
        .task {
            // Older bookmarks may not contain topic metadata; use the in-app web view.
            if bookmark.topic?.usesMarkdownReader != true {
                preloader.preload(bookmark.url)
            }
        }
        .onDisappear { preloader.clear() }
    }
}
