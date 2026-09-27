import ForumIndexCore
import SwiftUI

struct TopicAboutSheet: View {
    let topic: Topic
    let openTopic: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var detail: ForumDetail?
    @State private var failed = false
    @State private var loadAttempt = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Topic") {
                    Text(topic.title)
                        .font(.headline)
                    Text(ExcerptNormalizer.plainText(topic.excerpt) ?? "No excerpt available.")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if topic.presentableURL != nil {
                        Button("Open topic", systemImage: "doc.text", action: openTopic)
                            .accessibilityHint("Opens in the app")
                            .accessibilityIdentifier("topic-about-open-topic")
                    }
                }
                Section("Community") {
                    Text(ForumPresentation.displayName(topic.forum.name))
                        .font(.headline)
                    if let detail {
                        Text(detail.description ?? "No description available.")
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else if failed {
                        Text("Couldn’t load community information.")
                            .foregroundStyle(.secondary)
                        Button("Retry") { loadAttempt += 1 }
                    } else {
                        ProgressView("Loading community information…")
                    }
                    if let url = detail?.siteURL ?? topic.forum.baseURL {
                        Link(destination: url) {
                            Label("Community website", systemImage: "safari")
                        }
                        .accessibilityHint("Opens in your browser")
                    }
                    if let url = detail?.organizationURL {
                        Link(destination: url) {
                            Label("Parent website", systemImage: "safari")
                        }
                        .accessibilityHint("Opens in your browser")
                        .accessibilityIdentifier("topic-about-parent-link")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("About")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .environment(\.openURL, OpenURLAction { .systemAction($0) })
#if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
#endif
        .task(id: loadAttempt) { await loadCommunity() }
    }

    private func loadCommunity() async {
        guard detail == nil else { return }
        failed = false
        do {
            let result: ForumDetail
#if DEBUG
            if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TESTING"] == "1",
               let fixture = ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_FORUM_DETAIL"] {
                result = try JSONDecoder().decode(ForumDetailEnvelope.self, from: Data(fixture.utf8)).forum
            } else {
                result = try await URLSessionForumIndexAPIClient().fetchForum(id: topic.forum.id)
            }
#else
            result = try await URLSessionForumIndexAPIClient().fetchForum(id: topic.forum.id)
#endif
            try Task.checkCancellation()
            detail = result
        } catch {
            guard !Task.isCancelled else { return }
            failed = true
        }
    }
}
