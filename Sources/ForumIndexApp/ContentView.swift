import ForumIndexCore
import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

private let bookmarksKey = "bookmarks"
private let subjectsKey = "selected-subjects-v1"
private let openedTopicsKey = "opened-topics-v1"
private let deviceNameOverrideKey = DeviceIdentity.overrideKey
private let defaultSubjectSlugs = [
    "for_you", "trending", "ai", "technology", "creative", "markets", "opensource", "jobs", "gaming",
    "audio", "community", "web-dev", "sport", "lifestyle", "science"
]

private struct SubjectSelection: Codable {
    var orderedIDs: [String]
    var forYouIntroduced: Bool? = nil

    static func load(from data: Data) -> SubjectSelection? {
        try? JSONDecoder().decode(Self.self, from: data)
    }

    var data: Data {
        (try? JSONEncoder().encode(self)) ?? Data()
    }
}

private enum OpenedTopics {
    static func load(from data: Data) -> Set<String> {
        Set((try? JSONDecoder().decode([String].self, from: data)) ?? [])
    }

    static func data(for ids: Set<String>) -> Data {
        (try? JSONEncoder().encode(ids.sorted())) ?? Data()
    }
}

private func subjectDisplayName(_ destination: ReaderDestination) -> String {
    let name = switch destination.slug.lowercased() {
    case "technology": "Tech"
    case "web-dev": "Web Development"
    default: destination.parentName
    }
    return ForumPresentation.displayName(name)
}

private enum SheetRoute: Identifiable {
    case web(Bookmark, topic: Topic)
    case about(TopicAboutRoute)
    case bookmarks
    case signals
#if os(macOS)
    case keyboardShortcuts
#endif

    var id: String {
        switch self {
        case .web: "web"
        case .about: "about"
        case .bookmarks: "bookmarks"
        case .signals: "signals"
#if os(macOS)
        case .keyboardShortcuts: "keyboard-shortcuts"
#endif
        }
    }
}

struct ContentView: View {
    @AppStorage(AppAppearance.defaultsKey) private var appearance: AppAppearance = .auto
    @State private var webHeaderUsesLightStatusBar: Bool?
#if os(iOS)
    @State private var systemColorScheme: ColorScheme?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
#endif
    @Environment(\.colorScheme) private var colorScheme

    private var readerColorScheme: ColorScheme {
#if os(iOS)
        appearance.colorScheme ?? systemColorScheme ?? colorScheme
#else
        appearance.colorScheme ?? colorScheme
#endif
    }

    @Environment(\.scenePhase) private var scenePhase
    @Bindable var model: ReaderSceneModel
    @AppStorage(bookmarksKey) private var bookmarkData = Data()
    @AppStorage("bookmarkReplyRefreshAt") private var bookmarkReplyRefreshAt = 0.0
    @AppStorage(subjectsKey) private var subjectData = Data()
    @AppStorage(openedTopicsKey) private var openedTopicData = Data()
    @State private var activation = TopicActivationState()
    @State private var sheetRoute: SheetRoute?
    @State private var pendingAboutTopic: TopicAboutRoute?
    @State private var showingSubjectPicker = false
    @State private var reportError: String?
    @State private var pageID: String?
    @State private var pageSelectionTask: Task<Void, Never>?
    @State private var detailPath: [TopicDetailRoute] = []
    @State private var detailSession: TopicDetailSession?
    @State private var detailDestinationID: String?
    @State private var highlightedTopicID: TopicPresentationID?

#if os(macOS)
    @State private var showingStarred = false
    @State private var selectedBookmark: Bookmark?
    @State private var showingMacSidebar = true
#endif

    @ViewBuilder
    private var platformContent: some View {
#if os(macOS)
        macReader
#else
        navigationContent
#endif
    }

    private var navigationContent: some View {
        NavigationStack(path: $detailPath) {
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
            .background(Color("BrandBackground").ignoresSafeArea())
#if os(iOS)
            .navigationTitle("Topics")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TopicDetailRoute.self) { _ in
                if let session = detailSession {
                    GeometryReader { geometry in
                        TopicPager(count: session.topics.count, selectedIndex: session.currentIndex, onSelect: detailDidSelect,
                                   onHeaderStyleChange: { webHeaderUsesLightStatusBar = $0 }) { index in
                            TopicDetailPage(topic: session.topics[index], signals: model.signalStore,
                                            bookmarkData: $bookmarkData, safeAreaInsets: geometry.safeAreaInsets,
                                            goBack: { detailPath = [] })
                                .environment(\.colorScheme, readerColorScheme)
                        }
                        .ignoresSafeArea(.container)
                    }
                    .onDisappear { webHeaderUsesLightStatusBar = nil }
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
#else
            .navigationTitle("Forum Index")
            .toolbar {
                ToolbarItem {
                    bookmarksButton
                }
                ToolbarItem {
                    signalSettingsButton
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
    }

    var body: some View {
        platformContent
#if os(iOS)
        // Website contrast controls system chrome only. Native content follows the chosen appearance.
        .environment(\.colorScheme, readerColorScheme)
        .background(SystemAppearanceObserver(colorScheme: $systemColorScheme))
        .preferredColorScheme(
            detailPath.isEmpty ? appearance.colorScheme
                : (webHeaderUsesLightStatusBar.map { $0 ? .dark : .light } ?? appearance.colorScheme)
        )
#else
        .preferredColorScheme(appearance.colorScheme)
#endif
        .task {
#if DEBUG
            if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_RESET_APPEARANCE"] == "1" {
                appearance = .auto
            }
            if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_RESET_BOOKMARKS"] == "1" {
                bookmarkData = Data()
            }
            if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_RESET_SUBJECTS"] == "1" {
                subjectData = Data()
                pageID = nil
            }
            if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_RESET_OPENED_TOPICS"] == "1" {
                openedTopicData = Data()
            }
            if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_RESET_DEVICE_NAME"] == "1" {
                UserDefaults.standard.removeObject(forKey: deviceNameOverrideKey)
            }
#endif
            bookmarkData = Bookmark.data(for: Bookmark.load(from: bookmarkData))
            await model.launchOnce()
        }
        .task(id: "\(scenePhase)-\(Bookmark.load(from: bookmarkData).map(\.id).joined(separator: "|"))") {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await refreshBookmarkReplies()
                do { try await Task.sleep(for: .seconds(Bookmark.replyCheckInterval)) } catch { return }
            }
        }
        .task(id: model.signalStore.forYouEligible) {
            await model.store.setForYouEligible(model.signalStore.forYouEligible)
            introduceForYouIfNeeded()
        }
        .task(id: subjectPreloadID) {
            await model.store.preloadNextSubject(in: visibleParentDestinations)
        }
        .onChange(of: detailPath) { _, path in
            if path.isEmpty, let session = detailSession {
                highlightedTopicID = session.currentID
                activation.dismissPresentation()
            }
        }
        .onChange(of: model.store.selectedDestination?.id, initial: true) { _, destinationID in
            let wasPresentingWebPage = activation.presentedURL != nil
            activation.destinationDidChange(to: destinationID)
            if wasPresentingWebPage, activation.presentedURL == nil {
                sheetRoute = nil
            }
            model.preloader.clear()
        }
        .sheet(item: $sheetRoute, onDismiss: {
            activation.dismissPresentation()
            model.preloader.clear()
            if let route = pendingAboutTopic {
                pendingAboutTopic = nil
                activate(route.topic, in: route.topics, destination: route.destination)
            }
        }) { route in
            switch route {
            case let .about(about):
                TopicAboutSheet(topic: about.topic) {
                    pendingAboutTopic = about
                    sheetRoute = nil
                }
            case let .web(bookmark, topic):
                GeometryReader { geometry in
                    WebPageSheet(
                        preloader: model.preloader,
                        signals: model.signalStore,
                        bookmark: bookmark,
                        topic: topic,
                        bookmarkData: $bookmarkData,
                        safeAreaInsets: geometry.safeAreaInsets
                    )
                    .ignoresSafeArea(.container)
                }
#if os(macOS)
            case .keyboardShortcuts:
                MacKeyboardShortcutsView()
#endif
            case .bookmarks:
                BookmarksSheet(signals: model.signalStore, bookmarkData: $bookmarkData)
            case .signals:
                SignalEnrollmentView(colorScheme: readerColorScheme, signals: model.signalStore)
#if os(iOS)
                    .presentationDetents([.fraction(0.9)])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.thickMaterial)
#endif
            }
        }
#if os(iOS)
        .popover(isPresented: $showingSubjectPicker) {
            subjectPicker
                // NavigationStack has no intrinsic size when presented in an iPad popover.
                .frame(width: horizontalSizeClass == .regular ? 380 : nil,
                       height: horizontalSizeClass == .regular ? 620 : nil)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
#endif
        .alert("Report failed", isPresented: Binding(
            get: { reportError != nil },
            set: { if !$0 { reportError = nil } }
        )) {
            Button("OK") { reportError = nil }
        } message: {
            Text(reportError ?? "")
        }
    }

    @ViewBuilder
    private var reader: some View {
        Group {
#if os(iOS)
            VStack(spacing: 0) {
                taxonomyHeader
                SubjectPager(destinations: pagerParentDestinations, selection: $pageID) { destination in
                    feedContent(for: destination)
                }
                .onChange(of: pageID) { _, destinationID in
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
                    guard let firstID = destinationIDs.first else { return }
                    let selectedID = model.store.selectedDestination?.id
                    let targetID = pageID == nil
                        ? firstID
                        : selectedID.flatMap { destinationIDs.contains($0) ? $0 : nil } ?? firstID
                    if pageID != targetID {
                        pageID = targetID
                    }
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
            if let destination = model.store.selectedDestination {
                feedContent(for: destination)
            }
        }
        .onChange(of: visibleParentDestinations.map(\.id), initial: true) { oldIDs, newIDs in
            guard let firstID = newIDs.first,
                  oldIDs.isEmpty || model.store.selectedDestination.map({ !newIDs.contains($0.id) }) != false,
                  let destination = visibleParentDestinations.first(where: { $0.id == firstID }) else { return }
            select(destination)
        }
    }

    private var visibleParentDestinations: [ReaderDestination] {
        let available = model.store.parentDestinations
        guard !available.isEmpty else { return [] }
        let selection = SubjectSelection.load(from: subjectData)
        var savedIDs = selection?.orderedIDs ?? []
        if !savedIDs.isEmpty, model.store.forYouEligible, selection?.forYouIntroduced != true {
            savedIDs.removeAll { $0 == ReaderDestination.forYou.id }
            savedIDs.insert(ReaderDestination.forYou.id, at: 0)
        }
        let orderedIDs = savedIDs.isEmpty ? defaultSubjectIDs(in: available) : savedIDs
        let destinationsByID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        let resolved = orderedIDs.compactMap { destinationsByID[$0] }
        return resolved.isEmpty ? [available[0]] : resolved
    }

    private var pagerParentDestinations: [ReaderDestination] {
        visibleParentDestinations
    }

    private var subjectPreloadID: String {
        ([model.store.selectedDestination?.id ?? "none"] + visibleParentDestinations.map(\.id))
            .joined(separator: "|")
    }

    private func defaultSubjectIDs(in available: [ReaderDestination]) -> [String] {
        defaultSubjectSlugs.compactMap { slug in
            available.first { $0.slug.caseInsensitiveCompare(slug) == .orderedSame }?.id
        }
    }

    private func applySubjectSelection(_ ids: [String]) {
        let availableIDs = Set(model.store.parentDestinations.map(\.id))
        var seen = Set<String>()
        let resolved = ids.filter { availableIDs.contains($0) && seen.insert($0).inserted }
        guard !resolved.isEmpty else { return }
        let previous = SubjectSelection.load(from: subjectData)
        var saved = resolved
        // Keep a temporarily unavailable feed in its saved position.
        if !model.store.forYouEligible,
           let index = previous?.orderedIDs.firstIndex(of: ReaderDestination.forYou.id) {
            saved.insert(ReaderDestination.forYou.id, at: min(index, saved.count))
        }
        subjectData = SubjectSelection(
            orderedIDs: saved,
            forYouIntroduced: model.store.forYouEligible || previous?.forYouIntroduced == true
        ).data
        if let selectedID = model.store.selectedDestination?.id,
           !resolved.contains(selectedID),
           let destination = model.store.parentDestinations.first(where: { $0.id == resolved[0] }) {
            select(destination)
        }
    }

    private func introduceForYouIfNeeded() {
        guard model.store.forYouEligible,
              var selection = SubjectSelection.load(from: subjectData),
              !selection.orderedIDs.isEmpty,
              selection.forYouIntroduced != true else { return }
        selection.orderedIDs.removeAll { $0 == ReaderDestination.forYou.id }
        selection.orderedIDs.insert(ReaderDestination.forYou.id, at: 0)
        selection.forYouIntroduced = true
        subjectData = selection.data
    }

    private var taxonomyHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
#if os(iOS)
            HStack {
                ForumIndexLogo()
                .accessibilityIdentifier("reader-title")
                Spacer()
                bookmarksButton
                signalSettingsButton
            }
#endif
            ScrollViewReader { proxy in
                chipRow(pagerParentDestinations) { destination in
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
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func chipRow(
        _ destinations: [ReaderDestination],
        selected: @escaping (ReaderDestination) -> Bool,
        action: @escaping (ReaderDestination) -> Void
    ) -> some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(destinations) { destination in
                        let isSelected = selected(destination)
                        let chipLabel = subjectDisplayName(destination)
                        Button {
                            action(destination)
                        } label: {
                            Text(chipLabel)
                                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                .lineLimit(1)
                                .foregroundStyle(Color.primary)
                                .padding(.vertical, 7)
                                .overlay(alignment: .bottom) {
                                    if isSelected {
                                        Capsule()
                                            .fill(Color.accentColor)
                                            .frame(height: 3)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .id(destination.id)
                        .accessibilityLabel(chipLabel)
                        .accessibilityValue(isSelected ? "Selected" : "Not selected")
                        .accessibilityHint("Shows topics in this category")
                    }
                }
            }

            Button { showingSubjectPicker = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Customize subjects")
            .accessibilityHint("Choose and reorder subjects")
        }
    }

    private var subjectPicker: some View {
        SubjectPicker(
            destinations: model.store.parentDestinations,
            selectedIDs: Binding(
                get: { visibleParentDestinations.map(\.id) },
                set: { ids in applySubjectSelection(ids) }
            )
        )
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
        let openedIDs = OpenedTopics.load(from: openedTopicData)
        let bookmarkedURLs = Set(Bookmark.load(from: bookmarkData).map(\.url))
        let list = ScrollViewReader { scrollProxy in
            List {
                if let failureMessage {
                    FeedFailureBanner(message: failureMessage) {
                        Task { await model.store.refreshFeed(destination) }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                ForEach(topics, id: \.presentationID) { topic in
                    let saved = topic.presentableURL.map { bookmarkedURLs.contains($0) } ?? false
                    TopicRow(
                        topic: topic,
                        isOpened: openedIDs.contains(topicKey(topic)),
                        isHighlighted: highlightedTopicID == topic.presentationID,
                        action: { activate(topic, in: topics, destination: destination) }
                    )
                    .id(topic.presentationID)
                    .contextMenu {
                        Button("About", systemImage: "info.circle") {
                            sheetRoute = .about(TopicAboutRoute(topic: topic, topics: topics, destination: destination))
                        }
                        .accessibilityIdentifier("topic-context-about")
                        if topic.presentableURL != nil {
                            Button { toggleStar(for: topic) } label: {
                                Label(saved ? "Remove Bookmark" : "Bookmark", systemImage: saved ? "bookmark.fill" : "bookmark")
                            }
                            .accessibilityIdentifier("topic-context-star")
                        }
                        Menu("Report", systemImage: "exclamationmark.bubble") {
                            Button("Low quality") { report(topicID: topic.id, action: "low_quality") }
                                .accessibilityIdentifier("topic-report-low-quality")
                            Button("Inappropriate") { report(topicID: topic.id, action: "inappropriate") }
                                .accessibilityIdentifier("topic-report-inappropriate")
                            Button("Wrong subject") { report(topicID: topic.id, action: "wrong_subject") }
                                .accessibilityIdentifier("topic-report-wrong-subject")
                        }
                    }
                    // ponytail: List appearance is near-viewport; use geometry only if that prefetch distance proves costly.
                    .onAppear { warmAssetIfVisible(for: topic, in: destination) }
    #if os(iOS)
                    .onChange(of: pageID) { _, _ in warmAssetIfVisible(for: topic, in: destination) }
    #endif
                    .listRowSeparator(.visible, edges: .bottom)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
#if os(macOS)
                    .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions.width }
#endif
                    .listRowBackground(highlightedTopicID == topic.presentationID ? Color.accentColor.opacity(0.09) : Color.clear)
                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                }
                if model.store.canLoadNextPage(for: destination) {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .task(id: model.store.loadedPage(for: destination)) {
                            await model.store.loadNextPage(for: destination)
                        }
                        .accessibilityLabel("Loading more conversations")
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color("BrandBackground"), ignoresSafeAreaEdges: [])
#if os(macOS)
            .onChange(of: highlightedTopicID) { _, id in
                if let id { scrollProxy.scrollTo(id) }
            }
#endif
            .onChange(of: detailSession?.currentID) { _, currentID in
                guard detailDestinationID == destination.id, let currentID,
                      detailSession?.hasPaged == true else { return }
                // Position the underlying list before an interactive Back transition reveals it.
                scrollProxy.scrollTo(currentID, anchor: .center)
            }
            .onAppear {
                guard detailPath.isEmpty, detailDestinationID == destination.id,
                      let session = detailSession, session.hasPaged else { return }
                scrollProxy.scrollTo(session.currentID, anchor: .center)
            }
            .onChange(of: detailPath.isEmpty) { _, returned in
                guard returned, detailDestinationID == destination.id,
                      let session = detailSession, session.hasPaged else { return }
                scrollProxy.scrollTo(session.currentID, anchor: .center)
            }
        }


#if os(iOS)
        list.refreshable { await model.store.refreshFeed(destination) }
#else
        list
#endif
    }

    private func select(_ destination: ReaderDestination) {
#if os(iOS)
        pageID = destination.id
#else
        showingStarred = false
        selectedBookmark = nil
        highlightedTopicID = nil
        Task { await model.store.selectDestination(destination) }
#endif
    }


    private func warmAssetIfVisible(for topic: Topic, in destination: ReaderDestination) {
#if os(iOS)
        guard pageID == destination.id else { return }
#endif
        guard !topic.forum.supportsMarkdown else { return }
        model.preloader.warmAsset(for: topic)
    }

    private func activate(_ topic: Topic, in topics: [Topic], destination: ReaderDestination) {
#if os(macOS)
        guard let bookmark = bookmark(for: topic) else { return }
        highlightedTopicID = topic.presentationID
        selectedBookmark = bookmark
        markOpened(topic)
#else
        let action = activation.activate(url: topic.presentableURL)
        switch action {
        case .none:
            model.preloader.clear()
        case .present:
            markOpened(topic)
            guard let session = TopicDetailSession(topics: topics, selectedID: topic.presentationID) else { return }
            detailSession = session
            detailDestinationID = destination.id
            highlightedTopicID = nil
            detailPath = [.topics]
        }
#endif
    }

    private func detailDidSelect(_ index: Int) {
        guard let session = detailSession else { return }
        session.select(index: index)
        highlightedTopicID = session.currentID
        markOpened(session.currentTopic)
    }

    private func markOpened(_ topic: Topic) {
        var openedIDs = OpenedTopics.load(from: openedTopicData)
        openedIDs.insert(topicKey(topic))
        openedTopicData = OpenedTopics.data(for: openedIDs)
        Task { await model.signalStore.reportAction(topicID: topic.id, action: "read", active: true) }
    }

    private func topicKey(_ topic: Topic) -> String {
        "\(topic.forum.id):\(topic.id)"
    }

    private func bookmark(for topic: Topic) -> Bookmark? {
        guard let url = topic.presentableURL else { return nil }
        return Bookmark(title: topic.title, url: url, forumName: topic.forum.name, topicID: topic.id, topic: topic)
    }

    private func toggleStar(for topic: Topic) {
        guard let bookmark = bookmark(for: topic) else { return }
        let active = !Bookmark.load(from: bookmarkData).contains { $0.id == bookmark.id }
        bookmarkData = Bookmark.toggling(bookmark, in: bookmarkData)
        Task { await model.signalStore.reportAction(topicID: topic.id, action: "starred", active: active) }
    }

    private func report(topicID: Int, action: String) {
        guard model.signalStore.isEnrolled else {
            sheetRoute = .signals
            return
        }
        Task {
            reportError = await model.signalStore.reportAction(topicID: topicID, action: action, active: true)
        }
    }

    private func refreshBookmarkReplies() async {
        let now = Date().timeIntervalSince1970
        // Persist the cooldown across foreground transitions, windows, and app launches.
        guard now < bookmarkReplyRefreshAt || now - bookmarkReplyRefreshAt >= Bookmark.replyCheckInterval else { return }
        let candidates = Bookmark.replyCheckCandidates(in: bookmarkData)
        guard !candidates.isEmpty, !Task.isCancelled else { return }
        bookmarkReplyRefreshAt = now
        // Merge each response into current storage so reads and removals during a request survive.
        let client = BookmarkReplyClient()
        for bookmark in candidates {
            guard !Task.isCancelled else { return }
            let latest = try? await client.latestReply(for: bookmark.url)
            guard !Task.isCancelled else { return }
            var current = Bookmark.load(from: bookmarkData)
            guard let index = current.firstIndex(where: { $0.id == bookmark.id }) else { continue }
            if let latest { current[index].latestReplyAt = latest }
            bookmarkData = Bookmark.data(for: current)
        }
    }

    private var bookmarksButton: some View {
        Button { sheetRoute = .bookmarks } label: {
            BookmarkIcon(hasUnreadReplies: Bookmark.load(from: bookmarkData).contains { $0.hasUnreadReplies })
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel("Show bookmarks")
        .accessibilityValue(Bookmark.load(from: bookmarkData).contains { $0.hasUnreadReplies } ? "New replies" : "No new replies")
    }

    private var signalSettingsButton: some View {
        Button { sheetRoute = .signals } label: {
            Image(systemName: "gearshape")
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel("Contribution settings")
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

#if os(macOS)
private extension ContentView {
    var macReader: some View {
        // AppKit hosts each pane separately, so each pane must ignore the title-bar
        // safe area. Applying ignoresSafeArea only to the split view leaves a gap.
        HSplitView {
            if showingMacSidebar {
                MacReaderSidebar(
                    destinations: visibleParentDestinations,
                    selectedID: showingStarred ? nil : model.store.selectedDestination?.id,
                    showingStarred: showingStarred,
                    hasUnreadBookmarks: Bookmark.load(from: bookmarkData).contains { $0.hasUnreadReplies },
                    displayName: subjectDisplayName,
                    select: select,
                    showingSubjectPicker: $showingSubjectPicker,
                    showStarred: {
                        showingStarred = true
                        selectedBookmark = nil
                        highlightedTopicID = nil
                    },
                    showSettings: { sheetRoute = .signals },
                    subjectPicker: { subjectPicker.frame(width: 380, height: 620) }
                )
                .frame(minWidth: 170, idealWidth: 210, maxWidth: 280, maxHeight: .infinity)
                .background(Color("SidebarBackground"))
                .ignoresSafeArea(.container, edges: .top)
            }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Button(showingMacSidebar ? "Hide Sidebar" : "Show Sidebar", systemImage: "sidebar.left") {
                        showingMacSidebar.toggle()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Toggle Sidebar (Control-Command-S)")
                    Group {
                        if showingStarred {
                            Label("Bookmarks", systemImage: "bookmark")
                        } else {
                            Text(model.store.selectedDestination.map(subjectDisplayName) ?? "Topics")
                        }
                    }
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .gesture(WindowDragGesture())
                }
                .padding(.leading, showingMacSidebar ? 16 : 92)
                .padding(.trailing, 16)
                .padding(.vertical, 10)
                Divider()
                Group {
                    if showingStarred {
                        macStarredList
                    } else {
                        switch model.store.taxonomyState {
                        case .initialLoading:
                            ProgressView("Loading subjects…")
                        case .emptyTaxonomy:
                            unavailable(title: "No subjects yet", message: "No topic areas are available.",
                                        retryTitle: "Refresh", action: { await model.store.refreshTaxonomy() })
                        case let .failed(message):
                            unavailable(title: "Couldn’t load subjects", message: message,
                                        retryTitle: "Try Again", action: { await model.store.retryTaxonomy() })
                        case .loaded, .refreshing:
                            if let destination = model.store.selectedDestination {
                                feedContent(for: destination)
                                    .id(destination.id)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color("BrandBackground"))
            }
            .frame(minWidth: 330, idealWidth: 400, maxWidth: 530, maxHeight: .infinity)
            .background(Color("BrandBackground"))
            .ignoresSafeArea(.container, edges: .top)

            // Overlay content does not affect the split pane's preferred size.
            // Keep the same pane identity and sizing when selecting or dismissing a topic.
            Color("BrandBackground")
                .overlay {
                    if let selectedBookmark {
                        MacTopicDetailView(bookmark: selectedBookmark, signals: model.signalStore,
                                           bookmarkData: $bookmarkData) {
                            self.selectedBookmark = nil
                            highlightedTopicID = nil
                        }
                        .id(selectedBookmark.id)
                    } else {
                        ContentUnavailableView("Select a Topic", systemImage: "text.bubble",
                                               description: Text("Choose a conversation to start reading."))
                    }
                }
                .frame(minWidth: 420, idealWidth: 660, maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(.container, edges: .top)
        }
        .toolbar(.visible, for: .windowToolbar)
        .toolbarBackground(.hidden, for: .windowToolbar)
        .ignoresSafeArea(.container, edges: .top)
        .focusedSceneValue(\.readerNavigation, sheetRoute == nil && !showingSubjectPicker
            ? MacReaderNavigationActions(
                moveTopic: moveMacTopic, moveSubject: moveMacSubject,
                refresh: { Task { await model.store.refreshFeed() } },
                canRefresh: !showingStarred && model.store.selectedDestination != nil && model.store.feedState.kind != .refreshing,
                showShortcuts: { sheetRoute = .keyboardShortcuts },
                toggleSidebar: { showingMacSidebar.toggle() },
                showSettings: { sheetRoute = .signals }
            )
            : nil)
        .onChange(of: visibleParentDestinations.map(\.id), initial: true) { oldIDs, ids in
            guard !showingStarred, let first = visibleParentDestinations.first,
                  oldIDs.isEmpty || model.store.selectedDestination.map({ !ids.contains($0.id) }) ?? true else { return }
            select(first)
        }
    }

    func moveMacTopic(_ offset: Int) {
        if showingStarred {
            let bookmarks = Bookmark.load(from: bookmarkData)
            guard !bookmarks.isEmpty else { return }
            let current = bookmarks.firstIndex { $0.id == selectedBookmark?.id }
            let next = current.map { min(max($0 + offset, 0), bookmarks.count - 1) } ?? 0
            guard current != next else { return }
            openMacBookmark(bookmarks[next])
        } else {
            guard let destination = model.store.selectedDestination else { return }
            let topics = model.store.feedState(for: destination).rows.filter { $0.presentableURL != nil }
            guard !topics.isEmpty else { return }
            let current = topics.firstIndex { $0.presentableURL == selectedBookmark?.url }
            let next = current.map { min(max($0 + offset, 0), topics.count - 1) } ?? 0
            guard current != next else { return }
            activate(topics[next], in: topics, destination: destination)
        }
    }

    func moveMacSubject(_ offset: Int) {
        let subjects = visibleParentDestinations
        guard !subjects.isEmpty else { return }
        let current = showingStarred ? nil : subjects.firstIndex { $0.id == model.store.selectedDestination?.id }
        let next = current.map { min(max($0 + offset, 0), subjects.count - 1) } ?? 0
        guard current != next else { return }
        select(subjects[next])
    }

    func openMacBookmark(_ bookmark: Bookmark) {
        selectedBookmark = bookmark
        bookmarkData = Bookmark.markingRead(url: bookmark.url, in: bookmarkData)
        if let topicID = bookmark.topicID {
            Task { await model.signalStore.reportAction(topicID: topicID, action: "read", active: true) }
        }
    }

    @ViewBuilder
    var macStarredList: some View {
        let bookmarks = Bookmark.load(from: bookmarkData)
        if bookmarks.isEmpty {
            ContentUnavailableView("No Bookmarks", systemImage: "bookmark",
                                   description: Text("Topics you bookmark will appear here."))
                .safeAreaInset(edge: .bottom, spacing: 0) { BookmarkTrackingNote() }
        } else {
            ScrollViewReader { proxy in
                List(bookmarks) { bookmark in
                    Button {
                        openMacBookmark(bookmark)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(bookmark.title).font(.system(size: 15, weight: .semibold))
                                if bookmark.hasUnreadReplies {
                                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                                        .accessibilityHidden(true)
                                }
                            }
                            Text(ForumPresentation.displayName(bookmark.forumName))
                                .font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .padding(.vertical, 8)
                    }
                    .accessibilityValue(bookmark.hasUnreadReplies ? "New replies" : "Read")
                    .id(bookmark.id)
                    .buttonStyle(.plain)
                    .listRowBackground(selectedBookmark?.id == bookmark.id ? Color.accentColor.opacity(0.09) : Color.clear)
                    .accessibilityAddTraits(selectedBookmark?.id == bookmark.id ? .isSelected : [])
                    .contextMenu {
                        Button("Remove Bookmark", systemImage: "bookmark.slash") {
                            bookmarkData = Bookmark.toggling(bookmark, in: bookmarkData)
                            if let topicID = bookmark.topicID {
                                Task { await model.signalStore.reportAction(topicID: topicID, action: "starred", active: false) }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    BookmarkTrackingNote()
                }
                .onChange(of: selectedBookmark?.id) { _, id in
                    if let id { proxy.scrollTo(id) }
                }
            }
        }
    }
}
#endif

private struct SubjectPicker: View {
    let destinations: [ReaderDestination]
    @Binding var selectedIDs: [String]
    @Environment(\.dismiss) private var dismiss

    private var selectedDestinations: [ReaderDestination] {
        let byID = Dictionary(uniqueKeysWithValues: destinations.map { ($0.id, $0) })
        return selectedIDs.compactMap { byID[$0] }
    }

    private var otherDestinations: [ReaderDestination] {
        let selected = Set(selectedIDs)
        return destinations.filter { !selected.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(selectedDestinations) { destination in
                        subjectRow(destination, isSelected: true)
                    }
                    .onMove(perform: moveSubjects)
                } footer: {
                    Text("Checked subjects appear in the subject list. Drag to choose their order.")
                }
#if os(iOS)
                .environment(\.editMode, .constant(.active))
#endif

                if !otherDestinations.isEmpty {
                    Section("More subjects") {
                        ForEach(otherDestinations) { destination in
                            subjectRow(destination, isSelected: false)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .navigationTitle("Subjects")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("subject-picker")
    }

    private func subjectRow(_ destination: ReaderDestination, isSelected: Bool) -> some View {
        Button {
            toggle(destination)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(subjectDisplayName(destination))
                        .foregroundStyle(Color.primary)
                }

                Spacer()
#if os(macOS)
                if isSelected {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(Color.secondary)
                        .accessibilityHidden(true)
                }
#endif
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSelected && selectedIDs.count == 1)
        .accessibilityIdentifier("subject-toggle-\(destination.id)")
        .accessibilityLabel("\(isSelected ? "Hide" : "Show") \(subjectDisplayName(destination))")
        .accessibilityValue(isSelected ? "Checked" : "Unchecked")
        .accessibilityHint(isSelected && selectedIDs.count == 1
            ? "At least one subject must remain visible"
            : "Toggles this subject in the subject list")
    }

    private func toggle(_ destination: ReaderDestination) {
        if let index = selectedIDs.firstIndex(of: destination.id) {
            guard selectedIDs.count > 1 else { return }
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(destination.id)
        }
    }

    private func moveSubjects(from source: IndexSet, to destination: Int) {
        selectedIDs.move(fromOffsets: source, toOffset: destination)
    }
}

private struct SignalEnrollmentView: View {
    let colorScheme: ColorScheme
    @AppStorage(AppAppearance.defaultsKey) private var appearance: AppAppearance = .auto
    @Bindable var signals: SignalStore
    @State private var confirmingOptOut = false
    @State private var forumURL = ""
    @State private var isSubmittingForum = false
    @State private var forumSubmissionMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("The Forum Index is an app that lets you quickly scan forum topics across 1000+ Discourse forums. It lets you read, bookmark and flag topics. It uses the Markdown output of topics (where supported) for a fast read-only interface.")
                        .accessibilityIdentifier("settings-app-description")
                } header: {
                    Text("What is this app?")
                }

                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppAppearance.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("appearance-picker")
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Auto follows your device’s appearance.")
                }

                Section {
                    Text("Reads, stars, and reports are linked to a generated contributor profile. You can opt out below.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                if let installation = signals.installation {
                    Section("Contributor status") {
                        Label(
                            installation.trusted ? "Trusted contributor" : "Public contributor",
                            systemImage: installation.trusted ? "checkmark.seal.fill" : "person.crop.circle"
                        )
                        Label(
                            installation.deviceVerified ? "Apple verified" : "Apple unverified",
                            systemImage: installation.deviceVerified ? "checkmark.icloud.fill" : "icloud.slash"
                        )
                    }
                } else if signals.isEnrolled {
                    Section("Contributor status") {
                        Label("Contributions enabled", systemImage: "checkmark.circle.fill")
                        Button("Refresh contributor status") {
                            Task { await signals.refreshInstallation() }
                        }
                        .disabled(signals.isEnrolling)
                    }
                } else {
                    Section("Enable contributions") {
                        Text("Contribute actions from this device to improve topic ranking.")
                            .foregroundStyle(.secondary)
                        Button(action: enroll) {
                            Text(signals.isEnrolling ? "Enabling…" : "Enable contributions")
                                .frame(maxWidth: .infinity)
                        }
                            .buttonStyle(.borderedProminent)
                            .foregroundStyle(Color("BrandOnAccent"))
                            .controlSize(.large)
                            .buttonBorderShape(.capsule)
                            .disabled(signals.isEnrolling)
                            .accessibilityIdentifier("enable-contributions")
                            .accessibilityHint("Enrolls this device as a public contributor")
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Device name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(signals.installation?.displayName ?? signals.defaultDisplayName)
                            .accessibilityIdentifier("contribution-device-name")
                    }
                    .accessibilityElement(children: .contain)
                    Button("Generate new name", systemImage: "shuffle") {
                        Task { await signals.regenerateNickname() }
                    }
                    .disabled(signals.isEnrolling)
                    .accessibilityIdentifier("regenerate-device-name")
                    .accessibilityHint("Randomly chooses and saves a new nickname for this device")
                } header: {
                    Text("Device")
                } footer: {
                    Text("App admins use this nickname to identify your contributions. They can promote you to a trusted contributor, giving your activity more weight in topic rankings.")
                }

                if signals.installation?.trusted == true {
                    Section("Recommend a forum") {
                        TextField("Forum URL", text: $forumURL)
                            .textContentType(.URL)
                            .disabled(isSubmittingForum)
                            .accessibilityIdentifier("forum-submission-url")
                        Button(action: submitForum) {
                            Text(isSubmittingForum ? "Submitting…" : "Submit forum")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(Color("BrandOnAccent"))
                        .controlSize(.large)
                        .buttonBorderShape(.capsule)
                        .background(.quaternary, in: Capsule())
                        .disabled(forumURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingForum)
                        .accessibilityIdentifier("submit-forum")
                        if let forumSubmissionMessage {
                            Text(forumSubmissionMessage)
                                .foregroundStyle(forumSubmissionMessage == "Forum submitted for review." ? Color.secondary : Color.red)
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What is reported")
                            .font(.headline)
                        Text("Reads, star changes, and reports about low quality, inappropriate content, or the wrong subject.")
                        Text("Opening a topic counts as a read. Activity is sent only while contributions are enabled. Your stars stay saved on this device.")
                    }
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .listRowBackground(Color.clear)
                }

                Section {
                    NavigationLink {
                        FeedbackView(signals: signals)
                    } label: {
                        Label("Send feedback", systemImage: "bubble.left.and.bubble.right")
                    }
                    .accessibilityIdentifier("open-feedback")
                    .disabled(!signals.isEnrolled)
                } footer: {
                    if !signals.isEnrolled {
                        Text("Feedback is available to contributors. Enable contributions in Settings to send a message to the app admins.")
                    }
                }

                if signals.isEnrolled {
                    Section {
                        Button("Opt out of contributions", role: .destructive) {
                            confirmingOptOut = true
                        }
                        .disabled(signals.isEnrolling)
                        .accessibilityIdentifier("opt-out-contributions")
                    } footer: {
                        Text("Opting out stops reporting and revokes this device’s access. Local stars remain.")
                            .font(.body)
                    }
                }

                if let error = signals.contributionError ?? signals.enrollmentError {
                    Text(error)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("contribution-error")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
#if os(iOS)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 16, for: .scrollContent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if signals.isEnrolling && !signals.isEnrolled {
                    ProgressView().accessibilityLabel("Enabling contributions")
                }
            }
            .task {
                if signals.isEnrolled { await signals.refreshInstallation() }
            }
            .confirmationDialog(
                "Opt out of contributions?",
                isPresented: $confirmingOptOut,
                titleVisibility: .visible
            ) {
                Button("Opt out", role: .destructive, action: optOut)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Reporting will stop and this device’s access will be revoked. Local stars remain.")
            }
        }
        .preferredColorScheme(appearance.colorScheme ?? colorScheme)
#if os(macOS)
        .frame(minWidth: 420, minHeight: 580)
#endif
    }

    private func optOut() {
        Task { await signals.optOut() }
    }

    private func enroll() {
        Task {
            await signals.enroll(displayName: signals.defaultDisplayName, deviceName: DeviceIdentity.enrollmentName)
        }
    }

    private func submitForum() {
        guard !isSubmittingForum else { return }
        isSubmittingForum = true
        forumSubmissionMessage = nil
        Task {
            let error = await signals.submitForum(url: forumURL)
            forumSubmissionMessage = error ?? "Forum submitted for review."
            if error == nil { forumURL = "" }
            isSubmittingForum = false
        }
    }
}

private struct TopicListSkeleton: View {
    let destinationID: String
#if os(iOS)
    @ScaledMetric(relativeTo: .headline) private var iconSize = 36.0
#else
    @ScaledMetric(relativeTo: .headline) private var iconSize = 44.0
#endif

    var body: some View {
        List(0..<20, id: \.self) { index in
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 10)
                    .frame(width: iconSize, height: iconSize)
                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 4)
                        .frame(height: 18)
                    if index.isMultiple(of: 2) {
                        RoundedRectangle(cornerRadius: 4)
                            .frame(maxWidth: 220)
                            .frame(height: 18)
                    }
                    RoundedRectangle(cornerRadius: 4)
                        .frame(maxWidth: 180)
                        .frame(height: 13)
                }
            }
            .foregroundStyle(Color.secondary.opacity(0.16))
            .listRowSeparator(.visible, edges: .bottom)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
#if os(macOS)
            .alignmentGuide(.listRowSeparatorTrailing) { dimensions in dimensions.width }
#endif
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color("BrandBackground"), ignoresSafeAreaEdges: [])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading conversations")
        .accessibilityIdentifier("topic-list-skeleton-\(destinationID)")
    }
}

private struct TopicRow: View {
    let topic: Topic
    let isOpened: Bool
    let isHighlighted: Bool
    let action: () -> Void
#if os(macOS)
    @ScaledMetric(relativeTo: .headline) private var titleFontSize = 15.0
    private let metadataFont = Font.system(size: 13)
#else
    @ScaledMetric(relativeTo: .headline) private var titleFontSize = 18.0
    private let metadataFont = Font.footnote
#endif

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ForumIcon(forum: topic.forum)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text(topic.title)
                        .font(.system(size: titleFontSize, weight: .semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 4) {
                        Text(ForumPresentation.displayName(topic.forum.name))
                            .lineLimit(1)
                        HStack(spacing: 3) {
                            Image(systemName: "bubble.left")
                            Text("\(topic.replyCount)")
                        }
                        .fixedSize()
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(replyLabel)
                        ForEach(ExternalSignal.Source.allCases, id: \.self) { source in
                            if topic.externalSignals.contains(where: { $0.source == source }) {
                                ExternalSignalIcon(source: source)
                                    .padding(.leading, 4)
                            }
                        }
                    }
                    .font(metadataFont)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(topic.presentableURL == nil)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("topic-\(topic.forum.id)-\(topic.id)")
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isOpened ? "Opened" : "Not opened")
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
        .accessibilityHint(accessibilityHint)
        .opacity(isOpened ? 0.75 : 1)
    }

    private var accessibilityLabel: String {
        ([topic.title, ForumPresentation.displayName(topic.forum.name), replyLabel]
            + ExternalSignal.Source.allCases.filter { source in
                topic.externalSignals.contains { $0.source == source }
            }.map { "Discussed on \($0.name)" }).joined(separator: ", ")
    }

    private var accessibilityHint: String {
        topic.presentableURL == nil ? "No web page is available" : "Opens the topic preview"
    }

    private var replyLabel: String {
        "\(topic.replyCount) \(topic.replyCount == 1 ? "reply" : "replies")"
    }
}

private struct ForumIcon: View {
    let forum: ForumSummary
#if os(iOS)
    @ScaledMetric(relativeTo: .headline) private var iconSize = 36.0
#else
    @ScaledMetric(relativeTo: .headline) private var iconSize = 44.0
#endif

    var body: some View {
        AsyncImage(url: ForumPresentation.iconURL(for: forum)) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFit()
            default:
                fallback
            }
        }
        .frame(width: iconSize, height: iconSize)
        .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.24))
    }

    private var fallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: iconSize * 0.24)
                .fill(Color.secondary.opacity(0.1))
            Image(systemName: "globe")
                .font(.system(size: iconSize * 0.55, weight: .medium))
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

struct WebPageSheet: View {
    @Bindable var preloader: WebPagePreloader
    @Bindable var signals: SignalStore
    let bookmark: Bookmark
    let topic: Topic?
    @Binding var bookmarkData: Data
    var safeAreaInsets = EdgeInsets()
    var dismissAction: (() -> Void)? = nil
    @State private var linkedBookmark: Bookmark?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    private var isBookmarked: Bool {
        Bookmark.load(from: bookmarkData).contains { $0.id == currentBookmark.id }
    }

    private var currentBookmark: Bookmark { linkedBookmark ?? bookmark }

    var body: some View {
        ZStack {
            if let topic, topic.forum.supportsMarkdown {
                MarkdownTopicPreview(topic: topic, url: bookmark.url, preloader: preloader,
                                     safeAreaInsets: safeAreaInsets,
                                     onPageChange: updateDisplayedPage)
                    .id(bookmark.url)
            } else {
                PreloadedWebView(webView: preloader.webView, contentInsets: safeAreaInsets,
                                 headerColor: preloader.headerColor)
                    .preference(key: WebHeaderStylePreference.self, value: preloader.headerUsesLightStatusBar)
                    .opacity(preloader.isReady ? 1 : 0)
                    .allowsHitTesting(preloader.isReady)
                    .accessibilityHidden(!preloader.isReady)

                if !preloader.isReady {
                    loadingContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .overlay(alignment: .bottomTrailing) {
            TopicPreviewActions(
                url: currentBookmark.url, isBookmarked: isBookmarked,
                toggleBookmark: toggleBookmark, dismiss: { if let dismissAction { dismissAction() } else { dismiss() } }
            )
            .padding(.trailing, safeAreaInsets.trailing + 14)
            .padding(.bottom, safeAreaInsets.bottom + 40)
        }

        .presentationDragIndicator(.hidden)
        .task(id: bookmark.url) {
            bookmarkData = Bookmark.markingRead(url: bookmark.url, in: bookmarkData)
        }
        .onChange(of: bookmark.url) { linkedBookmark = nil }
        .onAppear {
            preloader.openExternalURL = { url in openURL(url) }
        }
        .onDisappear {
            preloader.openExternalURL = nil
        }
#if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        .focusedSceneValue(\.topicStar, MacTopicStarAction(isStarred: isBookmarked, toggle: toggleBookmark))
#endif
    }


    private func toggleBookmark() {
        let active = !isBookmarked
        let current = currentBookmark
        bookmarkData = Bookmark.toggling(current, in: bookmarkData)
        if let topicID = current.topicID {
            Task { await signals.reportAction(topicID: topicID, action: "starred", active: active) }
        }
    }

    private func updateDisplayedPage(url: URL, title: String) {
        linkedBookmark = url == bookmark.url ? nil
            : Bookmark(title: title, url: url, forumName: bookmark.forumName)
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
                Button("Retry") { preloader.retry() }
            }
            .padding(32)
        } else {
            ProgressView("Loading topic…")
                .accessibilityIdentifier("topic-loading")
        }
    }
}

struct WebActionButtonStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct BookmarksSheet: View {
    @Bindable var signals: SignalStore
    @Binding var bookmarkData: Data
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBookmark: Bookmark?

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
                            Button {
                                bookmarkData = Bookmark.markingRead(url: bookmark.url, in: bookmarkData)
                                selectedBookmark = bookmark
                                if let topicID = bookmark.topicID {
                                    Task { await signals.reportAction(topicID: topicID, action: "read", active: true) }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(bookmark.title).foregroundStyle(.primary)
                                        if bookmark.hasUnreadReplies {
                                            Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                                                .accessibilityHidden(true)
                                        }
                                    }
                                    Text(ForumPresentation.displayName(bookmark.forumName))
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(bookmark.hasUnreadReplies ? "New replies" : "Read")
                            .accessibilityHint("Opens in the app reader")
                            .accessibilityIdentifier("bookmark-\(bookmark.id)")
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BookmarkTrackingNote()
            }
            .navigationTitle("Bookmarks")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Label("Bookmarks", systemImage: "bookmark")
                        .labelStyle(.titleAndIcon)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
#if os(iOS)
        .fullScreenCover(item: $selectedBookmark) { bookmark in
            BookmarkReaderView(bookmark: bookmark, signals: signals, bookmarkData: $bookmarkData)
        }
#else
        .sheet(item: $selectedBookmark) { bookmark in
            BookmarkReaderView(bookmark: bookmark, signals: signals, bookmarkData: $bookmarkData)
        }
        .frame(minWidth: 420, minHeight: 480)
#endif
    }

    private func delete(at offsets: IndexSet) {
        var updated = bookmarks
        let deletedTopicIDs = offsets.compactMap { updated[$0].topicID }
        updated.remove(atOffsets: offsets)
        bookmarkData = Bookmark.data(for: updated)
        for topicID in deletedTopicIDs {
            Task { await signals.reportAction(topicID: topicID, action: "starred", active: false) }
        }
    }
}
