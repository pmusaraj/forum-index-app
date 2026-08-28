import ForumIndexCore
import SwiftUI

struct ContentView: View {
    @Bindable var model: ReaderSceneModel
    @State private var activation = TopicActivationState()
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
            .navigationTitle("Forum Index")
#if os(macOS)
            .toolbar {
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
        .task { await model.launchOnce() }
        .onChange(of: model.store.selectedDestination?.id, initial: true) { _, destinationID in
            activation.destinationDidChange(to: destinationID)
            model.preloader.clear()
        }
        .sheet(isPresented: presentationBinding) {
            WebPageSheet(preloader: model.preloader)
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
        .padding(.top, 14)
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
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: index == 0 ? 36 : 10, leading: 16, bottom: 10, trailing: 16))
            }
        }
        .listStyle(.plain)

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

    private func activate(_ topic: Topic) {
        let action = activation.activate(url: topic.presentableURL)
        switch action {
        case .none:
            model.preloader.clear()
        case let .present(url):
            model.preloader.preload(url)
        }
    }

    private var presentationBinding: Binding<Bool> {
        Binding(
            get: { activation.presentedURL != nil },
            set: { isPresented in
                if !isPresented { activation.dismissPresentation() }
            }
        )
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
                    if let publishedAt = topic.publishedAt,
                       ForumPresentation.shouldShowDate(publishedAt) {
                        Text("·")
                            .accessibilityHidden(true)
                        Text(publishedAt, format: .dateTime.month(.abbreviated).day().year())
                    }
                    Spacer(minLength: 8)
                    Text(replyLabel)
                        .fixedSize()
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
        var parts = [topic.title, topic.forum.name, replyLabel]
        if let publishedAt = topic.publishedAt,
           ForumPresentation.shouldShowDate(publishedAt) {
            parts.append("Published \(publishedAt.formatted(date: .long, time: .omitted))")
        }
        return parts.joined(separator: ", ")
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

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
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel("Close topic")
            .padding(8)
        }
        .presentationDragIndicator(.visible)
#if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
#else
        .ignoresSafeArea(edges: .bottom)
#endif
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
                    if let url = preloader.currentURL {
                        Button("Open in Safari") { openURL(url) }
                    }
                }
            }
            .padding(32)
        } else {
            ProgressView("Loading topic…")
                .accessibilityIdentifier("topic-loading")
        }
    }
}
