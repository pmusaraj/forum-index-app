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
    private(set) var loadState = WebPageLoadState()
    private var pendingNavigation: WKNavigation?
    private var pendingGeneration = 0

    var isReady: Bool { loadState.isReady }
    var loadError: String? { loadState.errorMessage }

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
        pendingGeneration = loadState.beginLoading()
        pendingNavigation = webView.load(URLRequest(url: url))
    }

    func retry() {
        guard let url = currentURL else { return }
        currentURL = nil
        preload(url)
    }

    func clear() {
        webView.stopLoading()
        pendingNavigation = nil
        currentURL = nil
        loadState.clear()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard navigation === pendingNavigation else { return }
        currentURL = WebNavigationPolicy.acceptedURL(webView.url) ?? currentURL
        loadState.commit(pendingGeneration)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard navigation !== pendingNavigation, loadState.isReady else { return }
        currentURL = WebNavigationPolicy.acceptedURL(webView.url) ?? currentURL
        pendingNavigation = navigation
        pendingGeneration = loadState.beginLoading()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: any Error
    ) {
        fail(navigation, error: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: any Error
    ) {
        fail(navigation, error: error)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard navigationAction.targetFrame?.isMainFrame != false else { return .allow }
        return WebNavigationPolicy.allows(navigationAction.request.url) ? .allow : .cancel
    }

    private func fail(_ navigation: WKNavigation?, error: any Error) {
        guard navigation === pendingNavigation else { return }
        loadState.fail(pendingGeneration, message: error.localizedDescription)
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
