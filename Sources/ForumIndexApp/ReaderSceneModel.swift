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
            window: "5d",
            subjectAreas: [
                SubjectArea(id: 1, name: "AI", slug: "ai", topicCount: 20, subjects: []),
                SubjectArea(id: 2, name: "Technology", slug: "technology", topicCount: 20, subjects: []),
                SubjectArea(id: 3, name: "Sports", slug: "sport", topicCount: 20, subjects: []),
                SubjectArea(id: 4, name: "Creative", slug: "creative", topicCount: 20, subjects: []),
                SubjectArea(id: 5, name: "Markets", slug: "markets", topicCount: 20, subjects: []),
                SubjectArea(id: 6, name: "Jobs", slug: "jobs", topicCount: 20, subjects: []),
                SubjectArea(id: 7, name: "Gaming", slug: "gaming", topicCount: 20, subjects: []),
                SubjectArea(id: 8, name: "Community", slug: "community", topicCount: 20, subjects: []),
                SubjectArea(
                    id: 9,
                    name: "Far Right Category With Long Name",
                    slug: "far-right",
                    topicCount: 20,
                    subjects: [],
                    secondary: true
                ),
                SubjectArea(
                    id: 10,
                    name: "Culture",
                    slug: "culture",
                    topicCount: 20,
                    subjects: [],
                    secondary: true
                )
            ]
        )
    }

    func fetchMainTopics(page: Int) async throws -> TopicFeedEnvelope {
        if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_SLOW_FEED"] == "1" {
            try await Task.sleep(for: .seconds(8))
        }
        return feed(forumID: 1, category: "Main")
    }

    func fetchParentTopics(slug: String, page: Int) async throws -> TopicFeedEnvelope {
        return switch slug {
        case "ai": feed(forumID: 2, category: "AI")
        case "far-right": feed(forumID: 3, category: "Far Right")
        default: feed(forumID: 4, category: slug)
        }
    }

    func fetchChildTopics(slug: String, page: Int) async throws -> TopicFeedEnvelope {
        return feed(forumID: 5, category: slug)
    }

    private func feed(forumID: Int, category: String) -> TopicFeedEnvelope {
        let forum = ForumSummary(
            id: forumID,
            name: "\(category) Fixture Forum with a deliberately long community name that exceeds sixty characters",
            slug: "fixture-\(forumID)",
            baseURL: URL(string: "https://example.com")
        )
        let topics = (1...20).map { id in
            Topic(
                id: id,
                title: "\(category) fixture topic \(id)",
                url: URL(string: "https://example.com/topics/\(id)"),
                excerpt: nil,
                forum: forum,
                publishedAt: id == 1 ? .now : Date(timeIntervalSinceNow: -86_400),
                replyCount: id
            )
        }
        return TopicFeedEnvelope(count: topics.count, results: topics)
    }
}
#endif
