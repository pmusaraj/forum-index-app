import SwiftUI

@main
struct ForumIndexApp: App {
    var body: some Scene {
        WindowGroup {
            ReaderSceneRoot()
        }
    }
}

private struct ReaderSceneRoot: View {
    @State private var model = ReaderSceneModel()

    var body: some View {
        ContentView(model: model)
    }
}
