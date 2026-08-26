import Foundation
import ForumIndexCore
import Observation
import SwiftUI
import WebKit

@MainActor
@Observable
final class WebPagePreloader: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private(set) var currentURL: URL?
    private(set) var pageTitle: String?

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func preload(_ url: URL) {
        guard let url = WebNavigationPolicy.acceptedURL(url), currentURL != url else { return }
        webView.stopLoading()
        currentURL = url
        pageTitle = nil
        webView.load(URLRequest(url: url))
    }

    func clear() {
        webView.stopLoading()
        currentURL = nil
        pageTitle = nil
        webView.loadHTMLString("", baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageTitle = webView.title
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard navigationAction.targetFrame?.isMainFrame != false else { return .allow }
        return WebNavigationPolicy.allows(navigationAction.request.url) ? .allow : .cancel
    }
}

#if os(iOS)
import UIKit

struct PreloadedWebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#elseif os(macOS)
import AppKit

struct PreloadedWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#endif
