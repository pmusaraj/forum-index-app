import ForumIndexCore
import SwiftUI

struct TopicArticleView: View {
    let title: String
    let publishedAt: Date?
    let replyCount: Int?
    let externalSignals: [ExternalSignal]
    @Bindable var reader: MarkdownTopicReader
    let url: URL
    var safeAreaInsets = EdgeInsets()
    let isActive: Bool
    @State private var showsSummary = false
    @State private var isNearEnd = false
    @State private var retryCount = 0
    @State private var attemptedRetry = 0
    @State private var titleVisibility = TopicTitleVisibility()
    @State private var titleHeight: CGFloat = 0
    @State private var scrollPhase = ScrollPhase.idle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
#if os(macOS)
    @ScaledMetric(relativeTo: .body) private var metadataFontSize = 15.0
    @State private var scrollPosition = ScrollPosition()
    @State private var pageGeometry = TitleScrollGeometry(offset: 0, contentHeight: 0, viewportHeight: 0)
#endif

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        TopicTitleElement(title: title)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { titleHeight = $0 }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 12) {
                                TopicAuthorByline(
                                    post: reader.startsTopic ? reader.posts.first : nil,
                                    publishedAt: publishedAt ?? (reader.startsTopic ? reader.posts.first?.publishedAt : nil)
                                )
                                Spacer(minLength: 8)
                                summaryButton
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                TopicAuthorByline(
                                    post: reader.startsTopic ? reader.posts.first : nil,
                                    publishedAt: publishedAt ?? (reader.startsTopic ? reader.posts.first?.publishedAt : nil)
                                )
                                summaryButton.frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
#if os(macOS)
                        .font(.system(size: metadataFontSize))
#else
                        .font(.caption)
#endif
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("topic-preview-details")
                        if !externalSignals.isEmpty {
                            ExternalSignalLinks(signals: externalSignals)
                        }
                    }
                    if showsSummary, let summary = reader.summary {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("AI-generated summary")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .accessibilityAddTraits(.isHeader)
                            TopicMarkdownContent(markdown: summary, baseURL: url)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color("BrandSurface"), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("topic-ai-summary")
                    }
                    ForEach(reader.posts) { post in
                        if reader.startsTopic, post.id == reader.posts.first?.id {
                            TopicMarkdownContent(markdown: post.markdown, baseURL: url)
                            if let count = reader.replyCount ?? replyCount, count > 0 {
                                VStack(alignment: .leading, spacing: 12) {
                                    Divider()
                                    Text("\(count) \(count == 1 ? "reply" : "replies")")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .accessibilityAddTraits(.isHeader)
                                        .accessibilityIdentifier("topic-replies-heading")
                                }
                                .padding(.top, 8)
                            }
                        } else {
#if os(macOS)
                            Divider()
#else
                            Divider().overlay(Color("BrandSurface"))
#endif
                            TopicPostView(post: post, baseURL: url)
                        }
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
                    if reader.hasCompleteTopic {
                        TopicReaderFooter(title: title, replyCount: reader.replyCount ?? replyCount,
                                          participantCount: reader.participantCount, url: url)
                    }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.leading, safeAreaInsets.leading + 20)
                .padding(.trailing, safeAreaInsets.trailing + 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
#if os(macOS)
                // Keep the last link above the floating share, star, and dismiss controls.
                .padding(.bottom, safeAreaInsets.bottom + 110)
#else
                .padding(.bottom, safeAreaInsets.bottom)
#endif
                .frame(maxWidth: .infinity)
            }
#if os(macOS)
            .scrollPosition($scrollPosition)
            .background(MacMarkdownPageKeys(isActive: isActive, scroll: scrollPage))
            .focusedSceneValue(\.markdownScroll, isActive ? MacMarkdownScrollAction(scroll: scrollPage) : nil)
#endif
            .onScrollGeometryChange(for: Bool.self) { geometry in
                TopicPagination.isNearEnd(
                    contentHeight: geometry.contentSize.height,
                    visibleBottom: geometry.visibleRect.maxY,
                    viewportHeight: geometry.containerSize.height
                )
            } action: { _, nearEnd in
                isNearEnd = nearEnd
            }
            .onScrollPhaseChange { _, phase in
                scrollPhase = phase
            }
            .onScrollGeometryChange(for: TitleScrollGeometry.self) { geometry in
                TitleScrollGeometry(offset: geometry.visibleRect.minY,
                                    contentHeight: geometry.contentSize.height,
                                    viewportHeight: geometry.containerSize.height)
            } action: { _, geometry in
                guard isActive else { return }
#if os(macOS)
                pageGeometry = geometry
#endif
                titleVisibility.update(
                    offset: geometry.offset, titleBottom: titleHeight + 12,
                    contentHeight: geometry.contentHeight, viewportHeight: geometry.viewportHeight,
                    isScrolling: scrollPhase == .interacting || scrollPhase == .decelerating
                )
            }
            .accessibilityIdentifier("topic-markdown-preview")
            .overlay(alignment: .top) {
                if isActive && titleVisibility.isVisible {
                    TopicTitleElement(title: title, isCompact: true)
                        .frame(maxWidth: 720, alignment: .leading)
                        .padding(.leading, safeAreaInsets.leading + 20)
                        .padding(.trailing, safeAreaInsets.trailing + 20)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(Color("BrandBackground"))
                        .overlay(alignment: .bottom) { Divider() }
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                }
            }
            .clipped()
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: titleVisibility.isVisible)
            .onChange(of: isActive) { _, _ in titleVisibility = TopicTitleVisibility() }
            .task(id: TopicPaginationRequest(url: isActive && isNearEnd ? reader.nextPageURL : nil, retry: retryCount)) {
                guard isActive, isNearEnd else { return }
                let retrying = retryCount != attemptedRetry
                attemptedRetry = retryCount
                await reader.loadNextPage(retrying: retrying)
            }
        }
        .background(Color("BrandBackground"), ignoresSafeAreaEdges: [])
    }
    @ViewBuilder
    private var summaryButton: some View {
        if reader.summary != nil {
            Button {
                showsSummary.toggle()
            } label: {
                Text(showsSummary ? "Hide AI summary" : "AI summary")
                    .fixedSize()
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityValue(showsSummary ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("topic-summary-toggle")
        }
    }

#if os(macOS)
    private func scrollPage(_ direction: Int) {
        guard isActive else { return }
        let distance = max(0, pageGeometry.viewportHeight - 60)
        let maximum = max(0, pageGeometry.contentHeight - pageGeometry.viewportHeight)
        let target = min(maximum, max(0, pageGeometry.offset + CGFloat(direction) * distance))
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            scrollPosition.scrollTo(y: target)
        }
    }
#endif

}

private struct TitleScrollGeometry: Equatable {
    let offset: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
}
