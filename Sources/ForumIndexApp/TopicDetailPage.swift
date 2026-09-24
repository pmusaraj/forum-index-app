#if os(iOS)
import ForumIndexCore
import SwiftUI

struct TopicDetailPage: View {
    let topic: Topic
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
                    bookmark: Bookmark(title: topic.title, url: url, forumName: topic.forum.name, topicID: topic.id),
                    topic: topic, bookmarkData: $bookmarkData, safeAreaInsets: safeAreaInsets, dismissAction: goBack
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
        .task {
            guard preloader == nil else { return }
            let loader = WebPagePreloader()
            if !topic.forum.supportsMarkdown, let url = topic.presentableURL { loader.preload(url) }
            preloader = loader
        }
        .onDisappear {
            preloader?.clear()
            preloader = nil
        }
    }
}
#endif
