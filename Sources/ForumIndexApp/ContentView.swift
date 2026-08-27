import ForumIndexCore
import SwiftUI

private enum SwipeAxis {
    case horizontal
    case vertical
}

struct ContentView: View {
    @Bindable var model: ReaderSceneModel
    @State private var activation = TopicActivationState()
    @GestureState private var isDragging = false
    @State private var swipeAxis: SwipeAxis?
    @State private var interactiveOffset: CGFloat = 0
    @State private var transitionOffset: CGFloat = 0
    @State private var isPaging = false

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
                        reader(width: proxy.size.width)
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

    private func reader(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            taxonomyHeader
            Divider()
            feedContent
                .simultaneousGesture(horizontalNavigationGesture(width: width))
                .onChange(of: isDragging) { _, active in
                    if !active, !isPaging, swipeAxis != nil {
                        settleInteractiveSwipe()
                    }
                }
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
        .offset(x: transitionOffset + interactiveOffset)
        .allowsHitTesting(!isPaging)
    }

    private var taxonomyHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            chipRow(model.store.parentDestinations, usesParentLabel: true) { destination in
                model.store.selectedDestination?.id == destination.id
            } action: { destination in
                Task { await model.store.selectDestination(destination) }
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
                    .accessibilityLabel(chipLabel == "All" ? "All topics" : chipLabel)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                    .accessibilityHint("Shows topics in this category")
                }
            }
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        switch model.store.feedState {
        case .initialLoading:
            ProgressView("Loading conversations…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            unavailable(
                title: "No conversations",
                message: "No trending topics were found in this category.",
                retryTitle: "Refresh",
                action: { await model.store.refreshFeed() }
            )
        case let .failed(rows, message) where rows.isEmpty:
            unavailable(
                title: "Couldn’t load conversations",
                message: message,
                retryTitle: "Try Again",
                action: { await model.store.refreshFeed() }
            )
        case let .failed(rows, message):
            topicList(rows, failureMessage: message)
        case let .loaded(rows), let .refreshing(rows):
            topicList(rows)
        }
    }

    @ViewBuilder
    private func topicList(_ topics: [Topic], failureMessage: String? = nil) -> some View {
        let list = List {
            if let failureMessage {
                FeedFailureBanner(message: failureMessage) {
                    Task { await model.store.refreshFeed() }
                }
                .listRowSeparator(.hidden)
            }
            ForEach(Array(topics.prefix(30).enumerated()), id: \.element.presentationID) { index, topic in
                TopicRow(
                    topic: topic,
                    featured: index == 0
                ) {
                    activate(topic)
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: index == 0 ? 36 : 10, leading: 16, bottom: 10, trailing: 16))
            }
        }
        .listStyle(.plain)

#if os(iOS)
        list.refreshable { await model.store.refreshFeed() }
#else
        list
#endif
    }

    private func horizontalNavigationGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                guard !isPaging else { return }
                let horizontal = value.translation.width
                let vertical = value.translation.height
                if swipeAxis == nil, max(abs(horizontal), abs(vertical)) >= 10 {
                    swipeAxis = abs(horizontal) > abs(vertical) * 1.15 ? .horizontal : .vertical
                }
                if swipeAxis == .horizontal {
                    interactiveOffset = horizontal
                }
            }
            .onEnded { value in
                let horizontal = value.translation.width
                let predicted = value.predictedEndTranslation.width
                guard !isPaging, swipeAxis == .horizontal else {
                    settleInteractiveSwipe()
                    return
                }
                let committedDistance = abs(horizontal) >= min(max(width * 0.16, 44), 72)
                    || abs(predicted) >= min(max(width * 0.28, 88), 140)
                guard committedDistance else {
                    settleInteractiveSwipe()
                    return
                }
                let direction: ReaderNavigationDirection = horizontal < 0 ? .next : .previous
                guard let target = model.store.adjacentParent(for: direction) else {
                    settleInteractiveSwipe()
                    return
                }
                page(direction, target: target, width: width, startingOffset: interactiveOffset)
            }
    }

    private func settleInteractiveSwipe() {
        swipeAxis = nil
        withAnimation(.easeOut(duration: 0.18)) {
            interactiveOffset = 0
        }
    }

    private func page(
        _ direction: ReaderNavigationDirection,
        target: ReaderDestination,
        width: CGFloat,
        startingOffset: CGFloat
    ) {
        isPaging = true
        let outgoing = direction == .next ? -max(width, 1) : max(width, 1)
        let incoming = -outgoing

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            transitionOffset = startingOffset
            interactiveOffset = 0
            swipeAxis = nil
        }

        withAnimation(.easeOut(duration: 0.18)) {
            transitionOffset = outgoing
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            var incomingTransaction = Transaction()
            incomingTransaction.disablesAnimations = true
            withTransaction(incomingTransaction) {
                transitionOffset = incoming
            }
            let navigation = Task { @MainActor in
                await model.store.selectDestination(target)
            }
            await Task.yield()
            withAnimation(.easeOut(duration: 0.2)) {
                transitionOffset = 0
            }
            try? await Task.sleep(for: .milliseconds(200))
            isPaging = false
            await navigation.value
        }
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

private struct TopicRow: View {
    let topic: Topic
    let featured: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Text(topic.title)
                    .font(featured ? .title3.weight(.semibold) : .headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    ForumIcon(forum: topic.forum)
                        .accessibilityHidden(true)
                    Text(topic.forum.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 5) {
                    Text(replyLabel)
                    if let publishedAt = topic.publishedAt {
                        Text("·")
                            .accessibilityHidden(true)
                        Text(publishedAt, format: .dateTime.month(.abbreviated).day().year())
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(topic.presentableURL == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }

    private var accessibilityLabel: String {
        var parts = [topic.title, topic.forum.name, replyLabel]
        if let publishedAt = topic.publishedAt {
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

    var body: some View {
        NavigationStack {
            PreloadedWebView(webView: preloader.webView)
                .navigationTitle(displayTitle)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
#if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
#else
        .ignoresSafeArea(edges: .bottom)
#endif
    }

    private var displayTitle: String {
        let title = preloader.pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty { return title }
        return preloader.currentURL?.host ?? "Topic"
    }
}
