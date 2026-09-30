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
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        TopicTitleElement(title: title)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { titleHeight = $0 }
                        HStack(spacing: 14) {
                            if let date = publishedAt {
                                Text(date, format: .dateTime.month(.abbreviated).day().year())
                            }
                            if let replyCount {
                                Label("\(replyCount) \(replyCount == 1 ? "reply" : "replies")", systemImage: "bubble.left")
                            }
                        }
#if os(macOS)
                        .font(.system(size: metadataFontSize))
#else
                        .font(.caption)
#endif
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("topic-preview-details")
                        ExternalSignalLinks(signals: externalSignals)
                    }
                    ForEach(reader.posts) { post in
#if os(macOS)
                        Divider()
#else
                        Divider().overlay(Color("BrandSurface"))
#endif
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
#if os(macOS)
                    if reader.nextPageURL == nil && !reader.isLoadingMore && reader.loadMoreError == nil {
                        Divider()
                        Link(destination: url) {
                            Label("Open topic on \(url.host() ?? url.absoluteString)",
                                  systemImage: "arrow.up.right.square")
                                .font(.system(size: metadataFontSize))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 8)
                        }
                        .environment(\.openURL, OpenURLAction { .systemAction($0) })
                        .accessibilityHint("Opens this topic in your browser")
                        .accessibilityIdentifier("topic-browser-footer")
                    }
#endif
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
                .padding(.bottom, safeAreaInsets.bottom + 170)
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
