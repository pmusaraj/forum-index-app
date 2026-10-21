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
    var onReadPost: (MarkdownPost, Date?) -> Void = { _, _ in }
    var onBeginning: () -> Void = {}
    @State private var didPosition = false
    @State private var hasScrolled = false
    @State private var isNearStart = false
    @State private var visiblePostFrames: [Int: CGRect] = [:]
    @State private var prependAnchor: Int?
    @State private var isRestoringPrevious = false
    @State private var previousRetry = 0
    @State private var attemptedPreviousRetry = 0
    @State private var showsSummary = false
    @State private var isNearEnd = false
    @State private var retryCount = 0
    @State private var attemptedRetry = 0
    @State private var titleVisibility = TopicTitleVisibility()
    @State private var titleHeight: CGFloat = 0
    @State private var scrollPhase = ScrollPhase.idle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollPosition = ScrollPosition()
    @State private var pageGeometry = TitleScrollGeometry(offset: 0, contentHeight: 0, viewportHeight: 0)
#if os(macOS)
    @ScaledMetric(relativeTo: .body) private var metadataFontSize = 15.0
#endif

    var body: some View {
        VStack(spacing: 0) {
            if reader.previousPageURL != nil || reader.initialPostID != nil {
                HStack {
                    Spacer()
                    Button("Back to top", systemImage: "arrow.up.to.line", action: onBeginning)
                        .font(.subheadline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                }
            }
            ScrollViewReader { proxy in
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
                        if reader.previousPageURL != nil {
                            HStack {
                                if reader.isLoadingPrevious { ProgressView() }
                                Button(reader.loadPreviousError == nil ? "Load earlier replies" : "Retry earlier replies") {
                                    previousRetry += 1
                                }
                            }
                            .accessibilityIdentifier("topic-earlier-replies")
                        }
                        ForEach(reader.posts) { post in
                            VStack(alignment: .leading, spacing: 16) {
                                if post.postNumber == reader.firstUnreadPostNumber, reader.firstUnreadPostNumber != nil {
                                    Text("New replies since last read".uppercased())
#if os(macOS)
                                        .font(.system(size: metadataFontSize))
#else
                                        .font(.subheadline)
#endif
                                        .tracking(2)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .accessibilityAddTraits(.isHeader)
                                        .accessibilityLabel("New replies since last read")
                                        .accessibilityIdentifier("topic-first-unread")
                                        .accessibilityValue("Post \(post.postNumber ?? 0)")
                                }
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
                                TopicReadMarker(post: post, isActive: isActive && didPosition && !reader.isLoadingPrevious) {
                                    recordRead($0)
                                }
                            }
                            .id(post.id)
                            .onGeometryChange(for: CGRect.self) { geometry in
                                geometry.frame(in: .scrollView(axis: .vertical))
                            } action: { frame in
                                guard isActive, reader.previousPageURL != nil else { return }
                                if frame.maxY > 0 && frame.minY < pageGeometry.viewportHeight {
                                    visiblePostFrames[post.id] = frame
                                } else {
                                    visiblePostFrames.removeValue(forKey: post.id)
                                }
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
                    .scrollTargetLayout()
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(.leading, safeAreaInsets.leading + 20)
                    .padding(.trailing, safeAreaInsets.trailing + 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
#if os(macOS)
                    // Keep the last link above the floating share, bookmark, and dismiss controls.
                    .padding(.bottom, safeAreaInsets.bottom + 110)
#else
                    .padding(.bottom, safeAreaInsets.bottom)
#endif
                    .frame(maxWidth: .infinity)
                }
                .scrollPosition($scrollPosition)
                .task {
                    if let id = reader.initialPostID { proxy.scrollTo(id, anchor: .top) }
                    didPosition = true
                }
                .onChange(of: reader.posts.first?.id) { _, _ in
                    if let anchor = prependAnchor {
                        // Restore the existing reply after inserting content above it.
                        scrollPosition.scrollTo(id: anchor, anchor: .top)
                    }
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.visibleRect.minY < 150
                } action: { _, nearStart in isNearStart = nearStart }
#if os(macOS)
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
                    if phase == .interacting { hasScrolled = true }
                }
                .onScrollGeometryChange(for: TitleScrollGeometry.self) { geometry in
                    TitleScrollGeometry(offset: geometry.visibleRect.minY,
                                        contentHeight: geometry.contentSize.height,
                                        viewportHeight: geometry.containerSize.height)
                } action: { _, geometry in
                    guard isActive else { return }
                    pageGeometry = geometry
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
                .task(id: TopicPaginationRequest(
                    url: isActive && didPosition && scrollPhase == .idle && (hasScrolled && isNearStart || previousRetry > 0)
                        ? reader.previousPageURL : nil,
                    retry: previousRetry
                )) {
                    guard isActive, didPosition, scrollPhase == .idle, !isRestoringPrevious,
                          hasScrolled && isNearStart || previousRetry != attemptedPreviousRetry else { return }
                    isRestoringPrevious = true
                    defer { isRestoringPrevious = false }
                    let retrying = previousRetry != attemptedPreviousRetry
                    attemptedPreviousRetry = previousRetry
                    let anchor = visiblePostFrames.min { $0.value.minY < $1.value.minY }
                    let restoration = anchor?.key ?? reader.posts.first?.id
                    prependAnchor = restoration
                    await reader.loadPreviousPage(retrying: retrying)
                    if reader.loadPreviousError != nil {
                        prependAnchor = nil
                    } else if let anchor = restoration {
                        await Task.yield()
                        scrollPosition.scrollTo(id: anchor, anchor: .top)
                        prependAnchor = nil
                    }
                }
            }
        }
        .background(Color("BrandBackground"), ignoresSafeAreaEdges: [])
    }
    private func recordRead(_ post: MarkdownPost) {
        guard isActive, didPosition, !reader.isLoadingPrevious else { return }
        if let number = post.postNumber {
            guard number > reader.readThrough else { return }
            reader.readThrough = number
        }
        var date = post.publishedAt
        if reader.nextPageURL == nil, post.id == reader.posts.last?.id, let latest = reader.latestReplyAt {
            date = max(date ?? .distantPast, latest)
        }
        onReadPost(post, date)
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
