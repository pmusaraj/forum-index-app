import SwiftUI

struct FeedScrollReader<Content: View>: View {
    @ViewBuilder let content: (ScrollViewProxy, FeedScrollRestorer) -> Content
    @State private var restorer: FeedScrollRestorer

    init(destinationID: String, memory: FeedScrollMemory,
         @ViewBuilder content: @escaping (ScrollViewProxy, FeedScrollRestorer) -> Content) {
        self.content = content
        _restorer = State(initialValue: FeedScrollRestorer(destinationID: destinationID, memory: memory))
    }

    var body: some View {
        ScrollViewReader { proxy in
            content(proxy, restorer)
                .onAppear { restorer.startObserving() }
                .onDisappear { restorer.stopObserving() }
        }
    }
}
