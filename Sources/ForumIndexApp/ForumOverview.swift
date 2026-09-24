import ForumIndexCore
import SwiftUI

struct ForumOverview: View {
    let forumID: Int
    @State private var detail: ForumDetail?
    @State private var failed = false
    @State private var loadAttempt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let detail {
                HStack(spacing: 10) {
                    AsyncImage(url: detail.forum.iconURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Image(systemName: "globe").foregroundStyle(.secondary)
                    }
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .accessibilityHidden(true)
                    Text(ForumPresentation.displayName(detail.forum.name))
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                }
                Text(detail.description ?? "No description available.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                Divider()
                if let url = detail.siteURL {
                    Link(destination: url) {
                        Label("Open forum in browser", systemImage: "arrow.up.right.square")
                            .frame(minHeight: 44)
                    }
                    .accessibilityHint("Opens in your browser")
                    .accessibilityIdentifier("forum-overview-forum-link")
                }
                if let url = detail.organizationURL {
                    Link(destination: url) {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Organization website", systemImage: "globe")
                            Text(url.host() ?? url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44)
                    }
                    .accessibilityHint("Opens in your browser")
                    .accessibilityIdentifier("forum-overview-organization-link")
                }
            } else if failed {
                Text("Couldn’t load site information.")
                    .font(.subheadline)
                Button("Retry") { loadAttempt += 1 }
                    .frame(minHeight: 44)
            } else {
                ProgressView("Loading site information…")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(width: 300, alignment: .leading)
        .environment(\.openURL, OpenURLAction { .systemAction($0) })
        .task(id: loadAttempt) { await load() }
    }

    private func load() async {
        guard detail == nil else { return }
        failed = false
        do {
            let result: ForumDetail
#if DEBUG
            if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TESTING"] == "1",
               let fixture = ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_FORUM_DETAIL"] {
                result = try JSONDecoder().decode(ForumDetailEnvelope.self, from: Data(fixture.utf8)).forum
            } else {
                result = try await URLSessionForumIndexAPIClient().fetchForum(id: forumID)
            }
#else
            result = try await URLSessionForumIndexAPIClient().fetchForum(id: forumID)
#endif
            try Task.checkCancellation()
            detail = result
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
        }
    }
}
