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
    @AppStorage(ReaderTypography.defaultsKey) private var typography: ReaderTypography = .compact

    var body: some View {
        ContentView(model: model)
            .environment(\.readerTypography, typography)
#if DEBUG
            .task {
                if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TESTING"] == "1",
                   ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_RESET_TYPOGRAPHY"] == "1" {
                    UserDefaults.standard.removeObject(forKey: ReaderTypography.defaultsKey)
                }
            }
#endif
#if DEBUG && os(macOS)
            .onAppear {
                guard ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TESTING"] == "1",
                      ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_TYPOGRAPHY_CAPTURE"] == "1" else { return }
                // Match the viewport across all four typography comparison captures.
                if let window = NSApp.windows.first {
                    window.setContentSize(NSSize(width: 1408, height: 1100))
                    window.center()
                }
            }
#endif
    }
}
