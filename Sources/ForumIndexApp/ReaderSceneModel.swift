import ForumIndexCore
import Foundation
import Observation

@MainActor
@Observable
final class ReaderSceneModel {
    let store: ReaderStore
    let preloader = WebPagePreloader()
    private var didLaunch = false

    init() {
        let client: any APIClientProtocol
#if DEBUG
        if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TESTING"] == "1" {
            client = UITestAPIClient()
        } else {
            client = URLSessionForumIndexAPIClient()
        }
#else
        client = URLSessionForumIndexAPIClient()
#endif
        store = ReaderStore(
            apiClient: client,
            taxonomyCache: LaunchTaxonomyCache(apiClient: client)
        )
    }

    func launchOnce() async {
        guard !didLaunch else { return }
        await store.launch()
        if !Task.isCancelled {
            didLaunch = true
        }
    }
}

#if DEBUG
private struct UITestAPIClient: APIClientProtocol {
    func fetchTaxonomy() async throws -> NavigationEnvelope {
        NavigationEnvelope(
            version: "v2",
            window: "7d",
            subjectAreas: [
                SubjectArea(id: 1, name: "AI", slug: "ai", topicCount: 20, subjects: [])
            ]
        )
    }

    func fetchMainTopics() async throws -> TopicFeedEnvelope {
        feed()
    }

    func fetchParentTopics(slug: String) async throws -> TopicFeedEnvelope {
        feed()
    }

    func fetchChildTopics(slug: String) async throws -> TopicFeedEnvelope {
        feed()
    }

    private func feed() -> TopicFeedEnvelope {
        let forum = ForumSummary(
            id: 1,
            name: "Fixture Forum",
            slug: "fixture",
            baseURL: URL(string: "https://example.com")
        )
        let topics = (1...20).map { id in
            Topic(
                id: id,
                title: "Fixture topic \(id)",
                url: URL(string: "https://example.com/topics/\(id)"),
                excerpt: nil,
                forum: forum,
                replyCount: id
            )
        }
        return TopicFeedEnvelope(count: topics.count, results: topics)
    }
}
#endif
