import SwiftUI

@main
struct ForumIndexApp: App {
    var body: some Scene {
        WindowGroup {
            ReaderSceneRoot()
#if os(macOS)
                .frame(minWidth: 900, minHeight: 560)
                .ignoresSafeArea(.container, edges: .top)
#endif
        }
#if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1270, height: 800)
        .commands { MacReaderCommands() }
#endif
    }
}

private struct ReaderSceneRoot: View {
    @State private var model = ReaderSceneModel()

    var body: some View {
        ContentView(model: model)
    }
}
