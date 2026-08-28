import ForumIndexCore
import SwiftUI

private let bookmarksKey = "bookmarks"

private struct Bookmark: Codable, Identifiable {
    let title: String
    let url: URL
    let forumName: String

    var id: String { url.absoluteString }

    static func load(from data: Data) -> [Bookmark] {
        (try? JSONDecoder().decode([Bookmark].self, from: data)) ?? []
    }

    static func data(for bookmarks: [Bookmark]) -> Data {
        (try? JSONEncoder().encode(bookmarks)) ?? Data()
    }
}

private enum SheetRoute: Identifiable {
    case web(Bookmark)
    case bookmarks

    var id: String {
        switch self {
        case .web: "web"
        case .bookmarks: "bookmarks"
        }
    }
}

struct ContentView: View {
    @Bindable var model: ReaderSceneModel
    @AppStorage(bookmarksKey) private var bookmarkData = Data()
    @State private var activation = TopicActivationState()
    @State private var sheetRoute: SheetRoute?
    @State private var pageID: String?
    @State private var pageSelectionTask: Task<Void, Never>?
    @State private var topicRowBaselines: [String: [TopicPresentationID: CGFloat]] = [:]
    @State private var topicRowScrollAnchors: [String: [TopicPresentationID: CGFloat]] = [:]
    @State private var topicListTopBaselines: [String: CGFloat] = [:]
    @State private var topicListFirstRows: [String: TopicPresentationID] = [:]
    @State private var topicListPendingResets: Set<String> = []
    @State private var topicListScrollAnchors: [String: CGFloat] = [:]
    @State private var topicListTitleHidden: [String: Bool] = [:]
    @State private var isReaderTitleHidden = false

    var body: some View {
        NavigationStack {
            Group {
                switch model.store.taxonomyState {
                case .initialLoading:
                    ProgressView("Loading topics…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .emptyTaxonomy:
                    unavailable(
                        title: "No topics yet",
                        message: "There are no active topic areas for this week.",
                        retryTitle: "Refresh",
                        action: { await model.store.refreshTaxonomy() }
                    )
                case let .failed(message):
                    unavailable(
                        title: "Couldn’t load topics",
                        message: message,
                        retryTitle: "Try Again",
                        action: { await model.store.retryTaxonomy() }
                    )
                case .loaded, .refreshing:
                    GeometryReader { proxy in
                        reader
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    }
                }
            }
#if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
#else
            .navigationTitle("Forum Index")
            .toolbar {
                ToolbarItem {
                    bookmarksButton
                }
                ToolbarItem {
                    Button {
                        Task { await model.store.refreshFeed() }
                    } label: {
                        Label("Refresh topics", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(model.store.selectedDestination == nil || model.store.feedState.kind == .refreshing)
                    .help("Refresh the current topic list")
                }
            }
#endif
        }
        .task {
#if DEBUG
            if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_RESET_BOOKMARKS"] == "1" {
                bookmarkData = Data()
            }
#endif
            await model.launchOnce()
        }
        .onChange(of: model.store.selectedDestination?.id, initial: true) { _, destinationID in
            let wasPresentingWebPage = activation.presentedURL != nil
            activation.destinationDidChange(to: destinationID)
            if wasPresentingWebPage, activation.presentedURL == nil {
                sheetRoute = nil
            }
            model.preloader.clear()
        }
        .sheet(item: $sheetRoute, onDismiss: { activation.dismissPresentation() }) { route in
            switch route {
            case let .web(bookmark):
                WebPageSheet(
                    preloader: model.preloader,
                    bookmark: bookmark,
                    bookmarkData: $bookmarkData
                )
            case .bookmarks:
                BookmarksSheet(bookmarkData: $bookmarkData)
            }
        }
    }

    @ViewBuilder
    private var reader: some View {
        Group {
#if os(iOS)
            VStack(spacing: 0) {
                taxonomyHeader
                Divider()
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(pagerParentDestinations) { destination in
                            feedContent(for: destination)
                                .containerRelativeFrame(.horizontal)
                                .id(destination.id)
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("feed-page-\(destination.id)")
                                .accessibilityHidden(destination.id != pageID)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $pageID)
                .accessibilityIdentifier("feed-pager")
                .onChange(of: pageID) { _, destinationID in
                    updateReaderTitle(for: destinationID)
                    pageSelectionTask?.cancel()
                    guard let destinationID,
                          destinationID != model.store.selectedDestination?.id,
                          let destination = model.store.parentDestinations.first(where: { $0.id == destinationID }) else { return }
                    pageSelectionTask = Task { @MainActor in
                        guard !Task.isCancelled, pageID == destinationID else { return }
                        await model.store.selectDestination(destination)
                    }
                }
                .onChange(of: pagerParentDestinations.map(\.id), initial: true) { _, destinationIDs in
                    guard let destinationID = model.store.selectedDestination?.id,
                          pageID.map({ !destinationIDs.contains($0) }) ?? true else { return }
                    pageID = destinationID
                }
                .onPreferenceChange(TopicListOffsetPreferenceKey.self) { offsets in
                    if #available(iOS 18.0, *) { return }
                    guard let destinationID = pageID, let rowOffsets = offsets[destinationID] else { return }
                    updateReaderTitle(for: destinationID, rowOffsets: rowOffsets)
                }
            }
#else
            readerPage
#endif
        }
        .overlay(alignment: .topTrailing) {
            if model.store.taxonomyState == .refreshing || model.store.feedState.kind == .refreshing {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
                    .background(.regularMaterial, in: Capsule())
                    .padding()
                    .accessibilityLabel("Refreshing topics")
            }
        }
        .contentShape(Rectangle())
    }

    private var readerPage: some View {
        VStack(spacing: 0) {
            taxonomyHeader
            Divider()
            if let destination = model.store.selectedDestination {
                feedContent(for: destination)
            }
        }
    }

    private var primaryParentDestinations: [ReaderDestination] {
        model.store.parentDestinations.filter { !$0.isSecondary }
    }

    private var secondaryParentDestinations: [ReaderDestination] {
        model.store.parentDestinations.filter(\.isSecondary)
    }

    private var pagerParentDestinations: [ReaderDestination] {
        var destinations = primaryParentDestinations
        let selectedID = pageID ?? model.store.selectedDestination?.id
        if let selectedID,
           let secondary = secondaryParentDestinations.first(where: { $0.id == selectedID }) {
            destinations.append(secondary)
        }
        return destinations
    }

    private var taxonomyHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
#if os(iOS)
            if !isReaderTitleHidden {
                HStack {
                    Text("Forum Index")
                        .font(.largeTitle.bold())
                        .accessibilityIdentifier("reader-title")
                    Spacer()
                    bookmarksButton
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
#endif
            ScrollViewReader { proxy in
                chipRow(
                    primaryParentDestinations,
                    usesParentLabel: true,
                    secondaryDestinations: secondaryParentDestinations
                ) { destination in
                    model.store.selectedDestination?.id == destination.id
                } action: { destination in
                    select(destination)
                }
                .onChange(of: model.store.selectedDestination?.id, initial: true) { _, destinationID in
                    guard let destinationID else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(destinationID)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, isReaderTitleHidden ? 6 : 14)
        .padding(.bottom, 12)
        .background(Color.primary.opacity(0.025))
    }

    private func chipRow(
        _ destinations: [ReaderDestination],
        usesParentLabel: Bool = false,
        usesShortAllLabel: Bool = false,
        secondaryDestinations: [ReaderDestination] = [],
        selected: @escaping (ReaderDestination) -> Bool,
        action: @escaping (ReaderDestination) -> Void
    ) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(destinations) { destination in
                    let isSelected = selected(destination)
                    let chipLabel = usesParentLabel
                        ? destination.parentName
                        : (destination.isAll && usesShortAllLabel ? "All" : destination.label)
                    Button {
                        action(destination)
                    } label: {
                        Text(chipLabel)
                            .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .background(
                                isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .id(destination.id)
                    .accessibilityLabel(chipLabel == "All" ? "All topics" : chipLabel)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                    .accessibilityHint("Shows topics in this category")
                }
                if !secondaryDestinations.isEmpty {
                    let selectedSecondary = secondaryDestinations.first {
                        $0.id == model.store.selectedDestination?.id
                    }
                    Menu {
                        ForEach(secondaryDestinations) { destination in
                            let isSelected = destination.id == selectedSecondary?.id
                            Button { action(destination) } label: {
                                if isSelected {
                                    Label(destination.parentName, systemImage: "checkmark")
                                } else {
                                    Text(destination.parentName)
                                }
                            }
                            .accessibilityValue(isSelected ? "Selected" : "Not selected")
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedSecondary?.parentName ?? "More")
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .font(.subheadline.weight(selectedSecondary == nil ? .regular : .semibold))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .foregroundStyle(selectedSecondary == nil ? Color.primary : Color.white)
                        .background(
                            selectedSecondary == nil ? Color.secondary.opacity(0.12) : Color.accentColor,
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        selectedSecondary.map { "More, \($0.parentName)" } ?? "More"
                    )
                    .accessibilityValue(selectedSecondary?.parentName ?? "Not selected")
                    .accessibilityHint("Shows additional subjects")
                }
            }
        }
    }

    @ViewBuilder
    private func feedContent(for destination: ReaderDestination) -> some View {
        switch model.store.feedState(for: destination) {
        case .initialLoading:
            TopicListSkeleton(destinationID: destination.id)
        case .empty:
            unavailable(
                title: "No conversations",
                message: "No trending topics were found in this category.",
                retryTitle: "Refresh",
                action: { await model.store.refreshFeed(destination) }
            )
        case let .failed(rows, message) where rows.isEmpty:
            unavailable(
                title: "Couldn’t load conversations",
                message: message,
                retryTitle: "Try Again",
                action: { await model.store.refreshFeed(destination) }
            )
        case let .failed(rows, message):
            topicList(rows, destination: destination, failureMessage: message)
        case let .loaded(rows), let .refreshing(rows):
            topicList(rows, destination: destination)
        }
    }

    @ViewBuilder
    private func topicList(
        _ topics: [Topic],
        destination: ReaderDestination,
        failureMessage: String? = nil
    ) -> some View {
        let list = List {
            if let failureMessage {
                FeedFailureBanner(message: failureMessage) {
                    Task { await model.store.refreshFeed(destination) }
                }
                .listRowSeparator(.hidden)
            }
            ForEach(Array(topics.prefix(30).enumerated()), id: \.element.presentationID) { index, topic in
                TopicRow(topic: topic) {
                    activate(topic)
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: TopicListOffsetPreferenceKey.self,
                            value: [
                                destination.id: [
                                    topic.presentationID: proxy.frame(in: .named(destination.id)).minY
                                ]
                            ]
                        )
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: index == 0 ? 36 : 10, leading: 16, bottom: 10, trailing: 16))
            }
        }
        .listStyle(.plain)
        .coordinateSpace(name: destination.id)
        .onAppear {
            topicListFirstRows[destination.id] = topics.first?.presentationID
        }

#if os(iOS)
        if #available(iOS 18.0, *) {
            list
                .refreshable { await model.store.refreshFeed(destination) }
                .onChange(of: topics.map(\.presentationID)) { _, _ in
                    topicOrderDidChange(topics, for: destination.id)
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, offset in
                    updateReaderTitle(for: destination.id, scrollOffset: offset)
                }
        } else {
            list
                .refreshable { await model.store.refreshFeed(destination) }
                .onChange(of: topics.map(\.presentationID)) { _, _ in
                    topicOrderDidChange(topics, for: destination.id)
                }
        }
#else
        list
#endif
    }

    private func select(_ destination: ReaderDestination) {
#if os(iOS)
        pageID = destination.id
#else
        Task { await model.store.selectDestination(destination) }
#endif
    }

    private func updateReaderTitle(for destinationID: String?) {
        setReaderTitleHidden(destinationID.flatMap { topicListTitleHidden[$0] } ?? false)
    }

    @available(iOS 18.0, *)
    private func updateReaderTitle(for destinationID: String, scrollOffset: CGFloat) {
        let hidden = topicListTitleHidden[destinationID] ?? false
        var anchor = topicListScrollAnchors[destinationID] ?? max(scrollOffset, 0)

        if hidden {
            anchor = max(anchor, scrollOffset)
            if scrollOffset <= anchor - 50 {
                topicListTitleHidden[destinationID] = false
                anchor = scrollOffset
            }
        } else {
            anchor = max(min(anchor, scrollOffset), 0)
            if scrollOffset >= anchor + 100 {
                topicListTitleHidden[destinationID] = true
                anchor = scrollOffset
            }
        }

        topicListScrollAnchors[destinationID] = anchor
        if pageID == destinationID {
            setReaderTitleHidden(topicListTitleHidden[destinationID] ?? false)
        }
    }

    private func updateReaderTitle(
        for destinationID: String,
        rowOffsets: [TopicPresentationID: CGFloat]
    ) {
        guard !rowOffsets.isEmpty else { return }
        let firstRow = topicListFirstRows[destinationID]
        if topicListTopBaselines[destinationID] == nil,
           let firstRow,
           let offset = rowOffsets[firstRow] {
            topicListTopBaselines[destinationID] = offset
        }
        if topicListPendingResets.contains(destinationID) {
            guard let firstRow,
                  let offset = rowOffsets[firstRow],
                  let top = topicListTopBaselines[destinationID],
                  offset <= top + 2 else { return }
            topicRowBaselines[destinationID] = rowOffsets
            topicRowScrollAnchors[destinationID] = rowOffsets
            topicListPendingResets.remove(destinationID)
            return
        }

        var baselines = topicRowBaselines[destinationID] ?? [:]
        var anchors = topicRowScrollAnchors[destinationID] ?? [:]
        for (row, offset) in rowOffsets {
            baselines[row] = baselines[row] ?? offset
            anchors[row] = anchors[row] ?? offset
        }

        let hidden = topicListTitleHidden[destinationID] ?? false
        if hidden {
            for (row, offset) in rowOffsets {
                anchors[row] = min(anchors[row] ?? offset, offset)
            }
            if rowOffsets.contains(where: { row, offset in offset >= (anchors[row] ?? offset) + 50 }) {
                topicListTitleHidden[destinationID] = false
                anchors = rowOffsets
            }
        } else {
            for (row, offset) in rowOffsets {
                anchors[row] = min(max(anchors[row] ?? offset, offset), baselines[row] ?? offset)
            }
            if rowOffsets.contains(where: { row, offset in offset <= (anchors[row] ?? offset) - 100 }) {
                topicListTitleHidden[destinationID] = true
                anchors = rowOffsets
            }
        }

        topicRowBaselines[destinationID] = baselines
        topicRowScrollAnchors[destinationID] = anchors
        setReaderTitleHidden(topicListTitleHidden[destinationID] ?? false)
    }

    private func topicOrderDidChange(_ topics: [Topic], for destinationID: String) {
        topicListFirstRows[destinationID] = topics.first?.presentationID
        topicListScrollAnchors[destinationID] = nil
        if topics.isEmpty {
            topicRowBaselines[destinationID] = nil
            topicRowScrollAnchors[destinationID] = nil
            topicListPendingResets.remove(destinationID)
        } else {
            topicListPendingResets.insert(destinationID)
        }
    }

    private func setReaderTitleHidden(_ hidden: Bool) {
        guard isReaderTitleHidden != hidden else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            isReaderTitleHidden = hidden
        }
    }

    private func activate(_ topic: Topic) {
        let action = activation.activate(url: topic.presentableURL)
        switch action {
        case .none:
            model.preloader.clear()
        case let .present(url):
            model.preloader.preload(url)
            sheetRoute = .web(Bookmark(title: topic.title, url: url, forumName: topic.forum.name))
        }
    }

    private var bookmarksButton: some View {
        Button { sheetRoute = .bookmarks } label: {
            Image(systemName: "bookmark")
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel("Show bookmarks")
    }

    private func unavailable(
        title: String,
        message: String,
        retryTitle: String,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: "text.bubble")
        } description: {
            Text(message)
        } actions: {
            Button(retryTitle) { Task { await action() } }
        }
    }
}

private struct TopicListOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: [String: [TopicPresentationID: CGFloat]] = [:]

    static func reduce(
        value: inout [String: [TopicPresentationID: CGFloat]],
        nextValue: () -> [String: [TopicPresentationID: CGFloat]]
    ) {
        for (destinationID, offsets) in nextValue() {
            value[destinationID, default: [:]].merge(offsets) { _, new in new }
        }
    }
}

private struct TopicListSkeleton: View {
    let destinationID: String

    var body: some View {
        List(0..<6, id: \.self) { index in
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .frame(height: 18)
                RoundedRectangle(cornerRadius: 4)
                    .frame(width: index.isMultiple(of: 2) ? 220 : 280, height: 18)
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 3)
                        .frame(width: 16, height: 16)
                    RoundedRectangle(cornerRadius: 4)
                        .frame(width: 150, height: 13)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .frame(width: 54, height: 13)
                }
            }
            .foregroundStyle(Color.secondary.opacity(0.16))
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: index == 0 ? 36 : 10, leading: 16, bottom: 10, trailing: 16))
        }
        .listStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading conversations")
        .accessibilityIdentifier("topic-list-skeleton-\(destinationID)")
    }
}

private struct TopicRow: View {
    let topic: Topic
    let action: () -> Void
    @ScaledMetric(relativeTo: .headline) private var titleFontSize = 18.0

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 7) {
                Text(topic.title)
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    ForumIcon(forum: topic.forum)
                        .accessibilityHidden(true)
                    Text(ForumPresentation.displayName(topic.forum.name))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    HStack(spacing: 3) {
                        Text("\(topic.replyCount)")
                        Image(systemName: "bubble.left")
                    }
                    .fixedSize()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(replyLabel)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(topic.presentableURL == nil)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("topic-\(topic.forum.id)-\(topic.id)")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    private var accessibilityLabel: String {
        [topic.title, topic.forum.name, replyLabel].joined(separator: ", ")
    }

    private var accessibilityHint: String {
        topic.presentableURL == nil ? "No web page is available" : "Opens the topic in a web view"
    }

    private var replyLabel: String {
        "\(topic.replyCount) \(topic.replyCount == 1 ? "reply" : "replies")"
    }
}

private struct ForumIcon: View {
    let forum: ForumSummary

    var body: some View {
        AsyncImage(url: ForumPresentation.iconURL(for: forum)) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFit()
            default:
                fallback
            }
        }
        .frame(width: 16, height: 16)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private var fallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
            Image(systemName: "globe")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct FeedFailureBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.callout)
                .lineLimit(2)
            Spacer()
            Button("Retry", action: retry)
        }
        .padding(12)
        .background(Color.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct WebPageSheet: View {
    @Bindable var preloader: WebPagePreloader
    let bookmark: Bookmark
    @Binding var bookmarkData: Data
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var isBookmarked: Bool {
        Bookmark.load(from: bookmarkData).contains { $0.id == bookmark.id }
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()

            PreloadedWebView(webView: preloader.webView)
                .opacity(preloader.isReady ? 1 : 0)
                .allowsHitTesting(preloader.isReady)
                .accessibilityHidden(!preloader.isReady)

            if !preloader.isReady {
                loadingContent
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                ShareLink(item: bookmark.url) {
                    Image(systemName: "square.and.arrow.up")
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Share topic")
                Spacer()
                Button(action: toggleBookmark) {
                    Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel(isBookmarked ? "Remove bookmark" : "Bookmark topic")
                Spacer()
                Button { openURL(bookmark.url) } label: {
                    Image(systemName: "safari")
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Open in Safari")
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Dismiss topic")
            }
            .font(.title3)
            .frame(maxWidth: 420)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(.regularMaterial)
        }
        .presentationDragIndicator(.visible)
#if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
#endif
    }

    private func toggleBookmark() {
        var bookmarks = Bookmark.load(from: bookmarkData)
        if let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.append(bookmark)
        }
        bookmarkData = Bookmark.data(for: bookmarks)
    }

    @ViewBuilder
    private var loadingContent: some View {
        if let error = preloader.loadError {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.circle")
                    .font(.title2)
                Text("Couldn’t load this topic")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                HStack {
                    Button("Retry") { preloader.retry() }
                    Button("Open in Safari") { openURL(bookmark.url) }
                }
            }
            .padding(32)
        } else {
            ProgressView("Loading topic…")
                .accessibilityIdentifier("topic-loading")
        }
    }
}

private struct BookmarksSheet: View {
    @Binding var bookmarkData: Data
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var bookmarks: [Bookmark] {
        Bookmark.load(from: bookmarkData)
    }

    var body: some View {
        NavigationStack {
            Group {
                if bookmarks.isEmpty {
                    ContentUnavailableView(
                        "No Bookmarks",
                        systemImage: "bookmark",
                        description: Text("Topics you bookmark will appear here.")
                    )
                } else {
                    List {
                        ForEach(bookmarks) { bookmark in
                            Button { openURL(bookmark.url) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bookmark.title)
                                        .foregroundStyle(.primary)
                                    Text(bookmark.forumName)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens in Safari")
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Bookmarks")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
#if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
#endif
    }

    private func delete(at offsets: IndexSet) {
        var updated = bookmarks
        updated.remove(atOffsets: offsets)
        bookmarkData = Bookmark.data(for: updated)
    }
}
