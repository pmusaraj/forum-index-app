import ForumIndexCore
import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

@MainActor private var currentDeviceName: String {
#if os(iOS)
    UIDevice.current.model
#else
    "Mac"
#endif
}

private let bookmarksKey = "bookmarks"
private let subjectsKey = "selected-subjects-v1"
private let openedTopicsKey = "opened-topics-v1"
private let defaultSubjectSlugs = [
    "main", "ai", "technology", "sport", "creative", "markets", "jobs", "gaming", "community"
]

private struct SubjectSelection: Codable {
    var orderedIDs: [String]

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
    let name = destination.slug.caseInsensitiveCompare("technology") == .orderedSame
        ? "Tech"
        : destination.parentName
    return ForumPresentation.displayName(name)
}

private struct Bookmark: Codable, Identifiable {
    let title: String
    let url: URL
    let forumName: String
    let topicID: Int?

    init(title: String, url: URL, forumName: String, topicID: Int? = nil) {
        self.title = title
        self.url = url
        self.forumName = forumName
        self.topicID = topicID
    }

    var id: String { url.absoluteString }

    static func load(from data: Data) -> [Bookmark] {
        (try? JSONDecoder().decode([Bookmark].self, from: data)) ?? []
    }

    static func data(for bookmarks: [Bookmark]) -> Data {
        (try? JSONEncoder().encode(bookmarks)) ?? Data()
    }

    static func toggling(_ bookmark: Bookmark, in data: Data) -> Data {
        var bookmarks = load(from: data)
        if let index = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks.remove(at: index)
        } else {
            bookmarks.append(bookmark)
        }
        return self.data(for: bookmarks)
    }
}

private enum SheetRoute: Identifiable {
    case web(Bookmark, topicID: Int)
    case bookmarks
    case signals

    var id: String {
        switch self {
        case .web: "web"
        case .bookmarks: "bookmarks"
        case .signals: "signals"
        }
    }
}

struct ContentView: View {
    @Bindable var model: ReaderSceneModel
    @AppStorage(bookmarksKey) private var bookmarkData = Data()
    @AppStorage(subjectsKey) private var subjectData = Data()
    @AppStorage(openedTopicsKey) private var openedTopicData = Data()
    @State private var activation = TopicActivationState()
    @State private var sheetRoute: SheetRoute?
    @State private var showingSubjectPicker = false
    @State private var reportError: String?
    @State private var pageID: String?
    @State private var pageSelectionTask: Task<Void, Never>?

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
            .background(Color("BrandBackground").ignoresSafeArea())
#if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
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
        .preferredColorScheme(.light)
        .task {
#if DEBUG
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
#endif
            await model.launchOnce()
        }
        .task(id: subjectPreloadID) {
            await model.store.preloadNextSubject(in: visibleParentDestinations)
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
        }) { route in
            switch route {
            case let .web(bookmark, topicID):
                WebPageSheet(
                    preloader: model.preloader,
                    signals: model.signalStore,
                    bookmark: bookmark,
                    topicID: topicID,
                    bookmarkData: $bookmarkData
                )
            case .bookmarks:
                BookmarksSheet(signals: model.signalStore, bookmarkData: $bookmarkData)
            case .signals:
                SignalEnrollmentView(signals: model.signalStore)
            }
        }
        .popover(isPresented: $showingSubjectPicker) {
            SubjectPicker(
                destinations: model.store.parentDestinations,
                selectedIDs: Binding(
                    get: { visibleParentDestinations.map(\.id) },
                    set: { ids in applySubjectSelection(ids) }
                )
            )
#if os(iOS)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
#else
            .frame(width: 380, height: 620)
#endif
        }
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
        let savedIDs = SubjectSelection.load(from: subjectData)?.orderedIDs ?? []
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
        subjectData = SubjectSelection(orderedIDs: resolved).data
        if let selectedID = model.store.selectedDestination?.id,
           !resolved.contains(selectedID),
           let destination = model.store.parentDestinations.first(where: { $0.id == resolved[0] }) {
            select(destination)
        }
    }

    private var taxonomyHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
#if os(iOS)
            HStack {
                (
                    Text("forum")
                        .font(.custom("Avenir Next", size: 24, relativeTo: .title2).weight(.bold))
                    + Text("i")
                        .font(.custom("Avenir Next", size: 24, relativeTo: .title2).weight(.medium).italic())
                        .foregroundColor(Color.accentColor)
                    + Text("ndex")
                        .font(.custom("Avenir Next", size: 24, relativeTo: .title2).weight(.medium))
                        .foregroundColor(Color.accentColor)
                )
                .accessibilityLabel("Forum Index")
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
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Customize subjects")
            .accessibilityHint("Choose and reorder subjects")
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
        let openedIDs = OpenedTopics.load(from: openedTopicData)
        let list = List {
            if let failureMessage {
                FeedFailureBanner(message: failureMessage) {
                    Task { await model.store.refreshFeed(destination) }
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            ForEach(Array(topics.enumerated()), id: \.element.presentationID) { index, topic in
                let saved = bookmark(for: topic).map { bookmark in
                    Bookmark.load(from: bookmarkData).contains { $0.id == bookmark.id }
                } ?? false
                TopicRow(
                    topic: topic,
                    isOpened: openedIDs.contains(topicKey(topic)),
                    isStarred: saved,
                    action: { activate(topic) },
                    starAction: { toggleStar(for: topic) }
                )
                .contextMenu {
                    if topic.presentableURL != nil {
                        Button { toggleStar(for: topic) } label: {
                            Label(saved ? "Unstar" : "Star", systemImage: saved ? "star.fill" : "star")
                        }
                        .accessibilityIdentifier("topic-context-star")
                    }
                    Menu("Report", systemImage: "exclamationmark.bubble") {
                        Button("Low quality") { report(topicID: topic.id, action: "low_quality") }
                            .accessibilityIdentifier("topic-report-low-quality")
                        Button("Inappropriate") { report(topicID: topic.id, action: "inappropriate") }
                            .accessibilityIdentifier("topic-report-inappropriate")
                    }
                }
                // ponytail: List appearance is near-viewport; use geometry only if that prefetch distance proves costly.
                .onAppear { warmAssetIfVisible(for: topic, in: destination) }
#if os(iOS)
                .onChange(of: pageID) { _, _ in warmAssetIfVisible(for: topic, in: destination) }
#endif
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: index == 0 ? 36 : 10, leading: 16, bottom: 10, trailing: 16))
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
        .background(Color("BrandBackground"))

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
        Task { await model.store.selectDestination(destination) }
#endif
    }


    private func warmAssetIfVisible(for topic: Topic, in destination: ReaderDestination) {
#if os(iOS)
        guard pageID == destination.id else { return }
#endif
        model.preloader.warmAsset(for: topic)
    }

    private func activate(_ topic: Topic) {
        let action = activation.activate(url: topic.presentableURL)
        switch action {
        case .none:
            model.preloader.clear()
        case let .present(url):
            var openedIDs = OpenedTopics.load(from: openedTopicData)
            openedIDs.insert(topicKey(topic))
            openedTopicData = OpenedTopics.data(for: openedIDs)
            model.preloader.preload(url)
            Task { await model.signalStore.reportAction(topicID: topic.id, action: "read", active: true) }
            sheetRoute = .web(
                Bookmark(title: topic.title, url: url, forumName: topic.forum.name, topicID: topic.id),
                topicID: topic.id
            )
        }
    }

    private func topicKey(_ topic: Topic) -> String {
        "\(topic.forum.id):\(topic.id)"
    }

    private func bookmark(for topic: Topic) -> Bookmark? {
        guard let url = topic.presentableURL else { return nil }
        return Bookmark(title: topic.title, url: url, forumName: topic.forum.name, topicID: topic.id)
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
            await model.signalStore.reportAction(topicID: topicID, action: action, active: true)
            reportError = model.signalStore.contributionError
        }
    }

    private var bookmarksButton: some View {
        Button { sheetRoute = .bookmarks } label: {
            Image(systemName: "star")
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel("Show starred topics")
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
                    Text("Checked subjects appear in the top row. Drag to choose their order.")
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
            : "Toggles this subject in the top row")
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
    @Bindable var signals: SignalStore
    @State private var displayName = ""
    @State private var confirmingOptOut = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
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
                        TextField("Display name", text: $displayName)
                            .accessibilityIdentifier("contribution-display-name")
                            .accessibilityHint("Required public contributor name, up to 100 characters")
                            .onChange(of: displayName) { _, value in
                                if value.count > 100 { displayName = String(value.prefix(100)) }
                            }
                            .onSubmit { enroll() }
                        Button("Enable contributions") { enroll() }
                            .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || signals.isEnrolling)
                            .accessibilityIdentifier("enable-contributions")
                            .accessibilityHint("Enrolls this device as a public contributor")
                    }
                }

                Section {
                    Label("Star changes", systemImage: "star")
                    Label("Reads", systemImage: "book")
                    Label("Low quality reports", systemImage: "exclamationmark.bubble")
                    Label("Inappropriate reports", systemImage: "hand.raised")
                } header: {
                    Text("What is reported")
                } footer: {
                    Text("Opening a topic is reported as a read. Stars remain stored locally, and actions are reported only while contributions are enabled.")
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
                    }
                }

                if let error = signals.contributionError ?? signals.enrollmentError {
                    Text(error)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("contribution-error")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Contributions")
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
                Button("Opt out", role: .destructive) { Task { await signals.optOut() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Reporting will stop and this device’s access will be revoked. Local stars remain.")
            }
        }
#if os(macOS)
        .frame(minWidth: 420, minHeight: 580)
#endif
    }

    private func enroll() {
        Task { await signals.enroll(displayName: displayName, deviceName: currentDeviceName) }
    }
}

private struct TopicListSkeleton: View {
    let destinationID: String

    var body: some View {
        List(0..<20, id: \.self) { index in
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
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: index == 0 ? 36 : 10, leading: 16, bottom: 10, trailing: 16))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color("BrandBackground"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading conversations")
        .accessibilityIdentifier("topic-list-skeleton-\(destinationID)")
    }
}

private struct TopicRow: View {
    let topic: Topic
    let isOpened: Bool
    let isStarred: Bool
    let action: () -> Void
    let starAction: () -> Void
    @ScaledMetric(relativeTo: .headline) private var titleFontSize = 18.0

    var body: some View {
        HStack(spacing: 8) {
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
            .accessibilityValue(isOpened ? "Opened" : "Not opened")
            .accessibilityHint(accessibilityHint)

            Button(action: starAction) {
                Image(systemName: isStarred ? "star.fill" : "star")
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .disabled(topic.presentableURL == nil)
            .accessibilityLabel(isStarred ? "Unstar topic" : "Star topic")
            .accessibilityIdentifier("topic-\(isStarred ? "unstar" : "star")-\(topic.forum.id)-\(topic.id)")
        }
        .opacity(isOpened ? 0.75 : 1)
    }

    private var accessibilityLabel: String {
        [topic.title, ForumPresentation.displayName(topic.forum.name), replyLabel].joined(separator: ", ")
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
    @Bindable var signals: SignalStore
    let bookmark: Bookmark
    let topicID: Int
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
        .overlay(alignment: .bottom) {
            HStack(spacing: 4) {
                ShareLink(item: bookmark.url) {
                    Image(systemName: "square.and.arrow.up")
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Share topic")
                Button(action: toggleBookmark) {
                    Image(systemName: isBookmarked ? "star.fill" : "star")
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel(isBookmarked ? "Unstar topic" : "Star topic")
                .accessibilityIdentifier("topic-web-star")
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Dismiss topic")
            }
            .font(.title3)
            .frame(maxWidth: 420)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 52)
            .safeAreaPadding(.bottom)
            .background(.regularMaterial)
        }

        .presentationDragIndicator(.hidden)
        .onAppear {
            preloader.openExternalURL = { url in openURL(url) }
        }
        .onDisappear {
            preloader.openExternalURL = nil
        }
#if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
#endif
    }

    private func toggleBookmark() {
        let active = !isBookmarked
        bookmarkData = Bookmark.toggling(bookmark, in: bookmarkData)
        Task { await signals.reportAction(topicID: topicID, action: "starred", active: active) }
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

private struct BookmarksSheet: View {
    @Bindable var signals: SignalStore
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
                        "No Starred Topics",
                        systemImage: "star",
                        description: Text("Topics you star will appear here.")
                    )
                } else {
                    List {
                        ForEach(bookmarks) { bookmark in
                            Button {
                                openURL(bookmark.url)
                                if let topicID = bookmark.topicID {
                                    Task { await signals.reportAction(topicID: topicID, action: "read", active: true) }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(bookmark.title)
                                        .foregroundStyle(.primary)
                                    Text(ForumPresentation.displayName(bookmark.forumName))
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
            .navigationTitle("Starred")
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
        let deletedTopicIDs = offsets.compactMap { updated[$0].topicID }
        updated.remove(atOffsets: offsets)
        bookmarkData = Bookmark.data(for: updated)
        for topicID in deletedTopicIDs {
            Task { await signals.reportAction(topicID: topicID, action: "starred", active: false) }
        }
    }
}
