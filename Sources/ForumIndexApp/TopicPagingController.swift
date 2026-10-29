#if os(iOS)
import SwiftUI
import UIKit

final class TopicPagingController<Content: View>: UIViewController, UIScrollViewDelegate {
    private let pagingView = EdgeRespectingPagingScrollView()
    private let count: Int
    private var selectedIndex: Int
    private var onSelect: (Int) -> Void
    private var onHeaderStyleChange: (Bool?) -> Void
    private var content: (Int) -> Content
    private var pages: [Int: TopicHostingController<Content>] = [:]
    private var lastSize: CGSize = .zero
    private weak var configuredPopGesture: UIGestureRecognizer?
    private weak var contentPopGesture: UIGestureRecognizer?
    private var hiddenBarPopDelegate: HiddenBarPopGestureDelegate?
    private var originalPopEnabled = true

    init(count: Int, selectedIndex: Int, onSelect: @escaping (Int) -> Void, onHeaderStyleChange: @escaping (Bool?) -> Void, content: @escaping (Int) -> Content) {
        self.count = count
        self.selectedIndex = selectedIndex
        self.onSelect = onSelect
        self.onHeaderStyleChange = onHeaderStyleChange
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        pagingView.isPagingEnabled = true
        pagingView.showsHorizontalScrollIndicator = false
        pagingView.showsVerticalScrollIndicator = false
        pagingView.alwaysBounceVertical = false
        pagingView.bounces = false
        pagingView.contentInsetAdjustmentBehavior = .never
        pagingView.delegate = self
        pagingView.accessibilityIdentifier = "topic-detail-pager"
        view.addSubview(pagingView)
        updatePages()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        configureBackGesture()
        enableHiddenBarBackGesture()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let pop = configuredPopGesture, let delegate = hiddenBarPopDelegate,
           pop.delegate === delegate {
            pop.delegate = delegate.originalDelegate
            pop.isEnabled = originalPopEnabled
        }
        hiddenBarPopDelegate = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        pagingView.frame = view.bounds
        pagingView.contentSize = CGSize(width: view.bounds.width * CGFloat(count), height: view.bounds.height)
        layoutPages()
        if lastSize != view.bounds.size {
            lastSize = view.bounds.size
            pagingView.setContentOffset(CGPoint(x: CGFloat(selectedIndex) * lastSize.width, y: 0), animated: false)
        }
        configureBackGesture()
    }

    func update(selectedIndex: Int, onSelect: @escaping (Int) -> Void, onHeaderStyleChange: @escaping (Bool?) -> Void, content: @escaping (Int) -> Content) {
        self.onSelect = onSelect
        self.onHeaderStyleChange = onHeaderStyleChange
        self.content = content
        let changed = self.selectedIndex != selectedIndex
        self.selectedIndex = selectedIndex
        guard isViewLoaded else { return }
        updatePages()
        if changed { publishHeaderStyle() }
        if changed, !pagingView.isDragging, !pagingView.isDecelerating {
            pagingView.setContentOffset(CGPoint(x: CGFloat(selectedIndex) * view.bounds.width, y: 0), animated: false)
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settleSelection() }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settleSelection() }
    }

    private func settleSelection() {
        guard pagingView.bounds.width > 0 else { return }
        let index = min(max(Int((pagingView.contentOffset.x / pagingView.bounds.width).rounded()), 0), count - 1)
        guard index != selectedIndex else { return }
        selectedIndex = index
        updatePages()
        publishHeaderStyle()
        onSelect(index)
    }

    private func updatePages() {
        // Keep a bounded set of native pages, preserving each adjacent page's SwiftUI state.
        let retained = Set(max(0, selectedIndex - 1)...min(count - 1, selectedIndex + 1))
        for index in Array(pages.keys) where !retained.contains(index) {
            guard let page = pages.removeValue(forKey: index) else { continue }
            page.willMove(toParent: nil)
            page.view.removeFromSuperview()
            page.removeFromParent()
        }
        for index in [selectedIndex] + retained.filter({ $0 != selectedIndex }).sorted() {
            if let page = pages[index] {
                page.updateContent(content(index))
            } else {
                let page = TopicHostingController(content: content(index))
                page.onHeaderStyleChange = { [weak self] in self?.publishHeaderStyle() }
                // The pager fills the screen; each page applies its own content insets.
                page.safeAreaRegions = []
                page.view.backgroundColor = .systemBackground
                addChild(page)
                pagingView.addSubview(page.view)
                page.didMove(toParent: self)
                pages[index] = page
            }
        }
        layoutPages()
    }

    private func publishHeaderStyle() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.onHeaderStyleChange(self.pages[self.selectedIndex]?.usesLightStatusBar)
        }
    }

    private func layoutPages() {
        for (index, page) in pages {
            page.view.accessibilityElementsHidden = index != selectedIndex
            page.view.frame = CGRect(x: CGFloat(index) * view.bounds.width, y: 0,
                                     width: view.bounds.width, height: view.bounds.height)

        }
    }

    private func configureBackGesture() {
        if view.window != nil { enableHiddenBarBackGesture() }
        // iOS 26 has a separate content-area pop gesture. It yields to item paging;
        // the system's leading-edge pop takes priority over the pager below.
        if #available(iOS 26.0, *),
           let contentPop = navigationController?.interactiveContentPopGestureRecognizer,
           contentPopGesture !== contentPop {
            contentPop.require(toFail: pagingView.panGestureRecognizer)
            contentPopGesture = contentPop
        }
        guard let pop = navigationController?.interactivePopGestureRecognizer, configuredPopGesture !== pop else { return }
        // The pager must yield to UIKit's leading-edge interactive pop.
        pagingView.panGestureRecognizer.require(toFail: pop)
        configuredPopGesture = pop
    }

    private func enableHiddenBarBackGesture() {
        guard let navigationController,
              let pop = navigationController.interactivePopGestureRecognizer else { return }
        if let hiddenBarPopDelegate {
            pop.delegate = hiddenBarPopDelegate
            pop.isEnabled = true
            return
        }
        let delegate = HiddenBarPopGestureDelegate(navigationController: navigationController,
                                                  originalDelegate: pop.delegate)
        originalPopEnabled = pop.isEnabled
        hiddenBarPopDelegate = delegate
        pop.delegate = delegate
        pop.isEnabled = true
    }
}
#endif
