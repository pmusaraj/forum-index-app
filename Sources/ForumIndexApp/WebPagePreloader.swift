import Foundation
import ForumIndexCore
import Observation
import SwiftUI
import WebKit

@MainActor
@Observable
final class WebPagePreloader: NSObject, WKNavigationDelegate {
    private static var warmupState = ForumAssetWarmupState()
    let webView: WKWebView
    private(set) var currentURL: URL?
    private(set) var loadState = WebPageLoadState()
    private var pendingNavigation: WKNavigation?
    private var pendingGeneration = 0
    private var clearNavigationAllowance = WebPageClearNavigationAllowance()
    var openExternalURL: ((URL) -> Void)?

    var isReady: Bool { loadState.isReady }
    var loadError: String? { loadState.errorMessage }

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func preload(_ url: URL) {
        guard let url = WebNavigationPolicy.acceptedURL(url), currentURL != url else { return }
        clearNavigationAllowance.cancel()
        webView.isHidden = true
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
        webView.isHidden = true
        pendingNavigation = nil
        currentURL = nil
        loadState.clear()
        clearNavigationAllowance.begin()
        webView.loadHTMLString("", baseURL: nil)
    }

    func warmAsset(for topic: Topic) {
        guard let url = Self.warmupState.assetURL(forForumID: topic.forum.id, topicURL: topic.presentableURL) else { return }
        Task {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
            request.httpMethod = "GET"
            _ = try? await URLSession.shared.data(for: request)
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard navigation === pendingNavigation else { return }
        currentURL = WebNavigationPolicy.acceptedURL(webView.url) ?? currentURL
        loadState.commit(pendingGeneration)
        webView.isHidden = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard navigation === pendingNavigation else { return }
        currentURL = WebNavigationPolicy.acceptedURL(webView.url) ?? currentURL
        loadState.finish(pendingGeneration)
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
        if clearNavigationAllowance.consumeIfAllowed(navigationAction.request.url) {
            return .allow
        }
        guard WebNavigationPolicy.allows(navigationAction.request.url) else { return .cancel }
        if navigationAction.navigationType == .linkActivated,
           let url = WebNavigationPolicy.externalURL(navigationAction.request.url, relativeTo: currentURL) {
            openExternalURL?(url)
            return .cancel
        }
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
            return .cancel
        }
        return .allow
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard currentURL != nil else { return }
        pendingNavigation = nil
        loadState.fail(pendingGeneration, message: "Web content stopped unexpectedly.")
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
