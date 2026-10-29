import Foundation
#if os(iOS)
import UIKit
#endif

/// List does not publish scrolling row geometry reliably. Observe its native offset
/// without replacing its delegate or retaining the list after its page is evicted.
@MainActor
final class FeedScrollRestorer {
    private let destinationID: String
    private let memory: FeedScrollMemory
#if os(iOS)
    private weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?
    private var isRestoring = false
#endif

    init(destinationID: String, memory: FeedScrollMemory) {
        self.destinationID = destinationID
        self.memory = memory
    }

#if os(iOS)
    func attach(_ scrollView: UIScrollView) {
        guard self.scrollView !== scrollView else { return }
        observation?.invalidate()
        observation = nil
        self.scrollView = scrollView
        isRestoring = true
        startObserving()
        Task { @MainActor [weak self, weak scrollView] in
            await Task.yield()
            guard let self, let scrollView, self.scrollView === scrollView else { return }
            scrollView.layoutIfNeeded()
            if let offset = self.memory.offsets[self.destinationID] {
                let minimum = -scrollView.adjustedContentInset.top
                let maximum = max(minimum, scrollView.contentSize.height - scrollView.bounds.height
                                  + scrollView.adjustedContentInset.bottom)
                scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x,
                                                   y: min(max(offset, minimum), maximum)), animated: false)
            }
            self.isRestoring = false
        }
    }
#endif

    func startObserving() {
#if os(iOS)
        guard observation == nil, let scrollView else { return }
        observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.recordOffset() }
        }
#endif
    }

    func stopObserving() {
#if os(iOS)
        recordOffset()
        observation?.invalidate()
        observation = nil
#endif
    }

#if os(iOS)
    private func recordOffset() {
        guard !isRestoring, observation != nil, let scrollView else { return }
        memory.offsets[destinationID] = scrollView.contentOffset.y
    }
#endif
}
