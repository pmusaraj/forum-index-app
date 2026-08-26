import ForumIndexCore
import Observation

@MainActor
@Observable
final class ReaderSceneModel {
    let store: ReaderStore
    let preloader = WebPagePreloader()
    private var didLaunch = false

    init() {
        let client = URLSessionForumIndexAPIClient()
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
