#if os(iOS)
import UIKit
import WebKit

/// Keeps website chrome inside the usable viewport while its background fills the screen.
final class WebViewportView: UIView {
    private let webView: WKWebView
    private var backgroundObservation: NSKeyValueObservation?
    var headerColor: UIColor? {
        didSet { backgroundColor = headerColor ?? webView.underPageBackgroundColor }
    }
    var contentInsets: UIEdgeInsets = .zero {
        didSet {
            guard contentInsets != oldValue else { return }
            setNeedsLayout()
        }
    }

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        backgroundColor = webView.underPageBackgroundColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset = .zero
        webView.scrollView.scrollIndicatorInsets = .zero
        addSubview(webView)
        backgroundObservation = webView.observe(\.underPageBackgroundColor, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.backgroundColor = self.headerColor ?? self.webView.underPageBackgroundColor
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Scroll insets scroll away; viewport bounds keep fixed and sticky headers visible.
        webView.frame = bounds.inset(by: contentInsets)
    }
}
#endif
