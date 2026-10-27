import ForumIndexCore
import Foundation
import Observation
#if os(iOS)
import DeviceCheck
import UIKit
#endif

@MainActor
@Observable
final class ReaderSceneModel {
    private static var sharedSignalStore: SignalStore?
    let store: ReaderStore
    let signalStore: SignalStore
    let preloader = WebPagePreloader()
    private var didLaunch = false

    init() {
        let client: any APIClientProtocol
        let signalClient: any SignalAPIClientProtocol
        let tokenStore: any SignalTokenStore
        let signalDefaults: UserDefaults
#if DEBUG
        if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TESTING"] == "1" {
            signalDefaults = UserDefaults(suiteName: ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_SIGNAL_DEFAULTS"] ?? UUID().uuidString)!
            let uiTestClient = UITestAPIClient()
            client = uiTestClient
            signalClient = uiTestClient
            tokenStore = UITestSignalTokenStore()
        } else {
            signalDefaults = .standard
            tokenStore = KeychainSignalTokenStore.shared
            let productionClient = URLSessionForumIndexAPIClient(bearerToken: { try? tokenStore.readToken() })
            client = productionClient
            signalClient = productionClient
        }
#else
        signalDefaults = .standard
        tokenStore = KeychainSignalTokenStore.shared
        let productionClient = URLSessionForumIndexAPIClient(bearerToken: { try? tokenStore.readToken() })
        client = productionClient
        signalClient = productionClient
#endif
        store = ReaderStore(
            apiClient: client,
            taxonomyCache: LaunchTaxonomyCache(apiClient: client)
        )
        if let shared = Self.sharedSignalStore {
            signalStore = shared
        } else {
            let shared = SignalStore(
                apiClient: signalClient,
                tokenStore: tokenStore,
                defaults: signalDefaults,
                deviceCheckToken: Self.deviceCheckToken
            )
            Self.sharedSignalStore = shared
            signalStore = shared
        }
    }

    func enrollAutomaticallyIfNeeded() async {
#if DEBUG
        if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TESTING"] == "1",
           ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_AUTO_ENROLL"] != "1" { return }
#endif
        await signalStore.enrollAutomaticallyIfNeeded(deviceName: DeviceIdentity.enrollmentName)
    }

    private static func deviceCheckToken() async throws -> String? {
#if os(iOS)
        let device = DCDevice.current
        guard device.isSupported else { return nil }
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            device.generateToken { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? DeviceCheckTokenError.unavailable)
                }
            }
        }
        return data.base64EncodedString()
#else
        return nil
#endif
    }

    func launchOnce() async {
        guard !didLaunch else { return }
        didLaunch = true
        await enrollAutomaticallyIfNeeded()
        await signalStore.refreshInstallation()
        await store.setForYouEligible(signalStore.forYouEligible)
        await store.launch()
        if Task.isCancelled { didLaunch = false }
    }
}

#if os(iOS)
private enum DeviceCheckTokenError: Error { case unavailable }
#endif

#if DEBUG
private struct UITestAPIClient: APIClientProtocol, SignalAPIClientProtocol {
    func fetchFeeds() async throws -> FeedCatalog {
        if let json = ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_FEEDS"] {
            return try JSONDecoder().decode(FeedCatalog.self, from: Data(json.utf8))
        }
        return FeedCatalog(feeds: [])
    }
    func fetchDiscoveredTopics(feed: DiscoveredFeed, page: Int) async throws -> TopicFeedEnvelope {
        try await fetchMainTopics(page: page)
    }

    func fetchTaxonomy() async throws -> NavigationEnvelope {
        if let json = ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_TAXONOMY"] {
            return try JSONDecoder().decode(NavigationEnvelope.self, from: Data(json.utf8))
        }
        return NavigationEnvelope(
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

    func fetchForYouTopics(page: Int) async throws -> TopicFeedEnvelope {
        try await fetchMainTopics(page: page)
    }

    func fetchMainTopics(page: Int) async throws -> TopicFeedEnvelope {
        if let json = ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_FEED"] {
            return try JSONDecoder().decode(TopicFeedEnvelope.self, from: Data(json.utf8))
        }
        if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_SLOW_FEED"] == "1" {
            try await Task.sleep(for: .seconds(8))
        }
        if let json = ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_TOPIC"],
           let topic = try? JSONDecoder().decode(Topic.self, from: Data(json.utf8)) {
            return TopicFeedEnvelope(count: 1, results: [topic])
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

    func enrollForSignals(inviteCode: String) async throws -> String { "ui-test-token" }
    func createInstallation(displayName: String, deviceName: String, deviceCheckToken: String?) async throws -> SignalEnrollment {
        SignalEnrollment(
            token: "ui-test-token",
            installation: SignalInstallation(
                publicID: "A7K-29Q",
                displayName: displayName,
                deviceName: deviceName,
                deviceVerified: true,
                trusted: false
            )
        )
    }
    private var nicknameDefaults: UserDefaults {
        UserDefaults(suiteName: ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_SIGNAL_DEFAULTS"] ?? "ForumIndexUITestNicknames")!
    }

    func fetchInstallation(bearerToken: String) async throws -> SignalInstallation {
        SignalInstallation(
            publicID: "A7K-29Q",
            displayName: nicknameDefaults.string(forKey: "ui-test-nickname") ?? "Penar",
            deviceName: "iPhone",
            deviceVerified: true,
            trusted: ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_TRUSTED"] == "1",
            forYouEligible: ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_FOR_YOU_ELIGIBLE"] == "1"
        )
    }
    func updateInstallation(deviceName: String, bearerToken: String) async throws -> SignalInstallation {
        SignalInstallation(
            publicID: "A7K-29Q",
            displayName: nicknameDefaults.string(forKey: "ui-test-nickname") ?? "Penar",
            deviceName: deviceName,
            deviceVerified: true,
            trusted: false
        )
    }
    func updateDisplayName(_ displayName: String, bearerToken: String) async throws -> SignalInstallation {
        nicknameDefaults.set(displayName, forKey: "ui-test-nickname")
        return try await fetchInstallation(bearerToken: bearerToken)
    }
    func setSignal(topicID: Int, value: Int, bearerToken: String) async throws {}
    func reportAction(topicID: Int, action: String, active: Bool, bearerToken: String) async throws {
        if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_FAIL_ACTION"] == "1" {
            throw URLError(.cannotConnectToHost)
        }
    }
    func submitFeedback(_ submission: FeedbackSubmission, bearerToken: String) async throws {
        if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_FEEDBACK_AVAILABLE"] != "1" {
            throw ForumIndexAPIError.httpStatus(404)
        }
    }
    func submitForum(url: String, bearerToken: String) async throws {}
    func revokeInstallation(bearerToken: String) async throws {}

    private func feed(forumID: Int, category: String) -> TopicFeedEnvelope {
        let forum = ForumSummary(
            id: forumID,
            name: "\(category) Fixture Forum with a deliberately long community name that exceeds sixty characters",
            slug: "fixture-\(forumID)",
            baseURL: URL(string: "https://example.com"),
            supportsMarkdown: ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_PAGING"] == "1"
        )
        let topics = (1...20).map { id in
            Topic(
                id: id,
                title: "\(category) fixture topic \(id)",
                url: id == 1 && ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_URLLESS_TOPIC"] == "1"
                    ? nil
                    : URL(string: "https://example.com/topics/\(id)"),
                excerpt: nil,
                forum: forum,
                publishedAt: id == 1 ? .now : Date(timeIntervalSinceNow: -86_400),
                replyCount: id
            )
        }
        return TopicFeedEnvelope(count: topics.count, results: topics)
    }
}

private final class UITestSignalTokenStore: SignalTokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String? = ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_ENROLLED"] == "1"
        ? "ui-test-token"
        : nil

    func readToken() throws -> String? { lock.withLock { token } }
    func saveToken(_ token: String) throws { lock.withLock { self.token = token } }
    func deleteToken() throws { lock.withLock { token = nil } }
    func deleteToken(matching expected: String) throws -> Bool {
        lock.withLock {
            guard token == expected else { return false }
            token = nil
            return true
        }
    }
}
#endif
