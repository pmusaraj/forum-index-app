#if os(iOS)
import ForumIndexCore
import SwiftUI

struct TopicDetailPage: View {
    let topic: Topic
    let isSelected: Bool
    @Bindable var signals: SignalStore
    @Binding var bookmarkData: Data
    let safeAreaInsets: EdgeInsets
    let goBack: () -> Void
    @State private var preloader: WebPagePreloader?

    var body: some View {
        Group {
            if let preloader, let url = topic.presentableURL {
                WebPageSheet(
                    preloader: preloader, signals: signals,
                    bookmark: Bookmark(title: topic.title, url: url, forumName: topic.forum.name, topicID: topic.id, topic: topic),
                    topic: topic, bookmarkData: $bookmarkData, safeAreaInsets: safeAreaInsets, dismissAction: goBack, isSelected: isSelected
                )
            } else {
                ProgressView("Loading topic…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
            }
        }
        .background {
            Color("BrandSurface").ignoresSafeArea(.container, edges: .top)
        }
        .task(id: isSelected) {
            if preloader == nil { preloader = WebPagePreloader() }
            if isSelected, !topic.usesMarkdownReader, let url = topic.presentableURL {
                preloader?.preload(url)
            }
        }
        .onDisappear {
            preloader?.clear()
            preloader = nil
        }
    }
}
#endif
