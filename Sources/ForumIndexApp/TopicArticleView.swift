import ForumIndexCore
import SwiftUI

struct TopicArticleView: View {
    let title: String
    let publishedAt: Date?
    let replyCount: Int?
    @Bindable var reader: MarkdownTopicReader
    let url: URL
    var safeAreaInsets = EdgeInsets()
    let isActive: Bool
    @State private var isNearEnd = false
    @State private var retryCount = 0
    @State private var attemptedRetry = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(title)
                            .font(.title2.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("topic-preview-title")
                        HStack(spacing: 14) {
                            if let date = publishedAt {
                                Text(date, format: .dateTime.month(.abbreviated).day().year())
                            }
                            if let replyCount {
                                Label("\(replyCount) \(replyCount == 1 ? "reply" : "replies")", systemImage: "bubble.left")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("topic-preview-details")
                    }
                    ForEach(reader.posts) { post in
                        Divider().overlay(Color("BrandSurface"))
                        TopicPostView(post: post, baseURL: url)
                    }
                    if reader.isLoadingMore {
                        ProgressView("Loading more replies…")
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("topic-loading-more")
                    } else if let error = reader.loadMoreError {
                        VStack(spacing: 8) {
                            Text(error).foregroundStyle(.secondary)
                            Button("Retry") { retryCount += 1 }
                        }
                        .frame(maxWidth: .infinity)
                    }

                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.leading, safeAreaInsets.leading + 20)
                .padding(.trailing, safeAreaInsets.trailing + 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
                .padding(.bottom, safeAreaInsets.bottom + 170)
                .frame(maxWidth: .infinity)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                TopicPagination.isNearEnd(
                    contentHeight: geometry.contentSize.height,
                    visibleBottom: geometry.visibleRect.maxY,
                    viewportHeight: geometry.containerSize.height
                )
            } action: { _, nearEnd in
                isNearEnd = nearEnd
            }
            .task(id: TopicPaginationRequest(url: isActive && isNearEnd ? reader.nextPageURL : nil, retry: retryCount)) {
                guard isActive, isNearEnd else { return }
                let retrying = retryCount != attemptedRetry
                attemptedRetry = retryCount
                await reader.loadNextPage(retrying: retrying)
            }
            .accessibilityIdentifier("topic-markdown-preview")
        }
        .background(Color("BrandBackground"), ignoresSafeAreaEdges: [])
    }
}
