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
    private(set) var headerColor: Color?
    private(set) var headerUsesLightStatusBar: Bool?
    private var headerColorToken = UUID().uuidString
    private let headerColorObserver = WebHeaderColorObserver()
    private var requestedURL: URL?
    private var isBackgroundLoading = false
    private var pendingNavigation: WKNavigation?
    private var pendingGeneration = 0
    private var clearNavigationAllowance = WebPageClearNavigationAllowance()
    var openExternalURL: ((URL) -> Void)?

    var isReady: Bool { loadState.isReady }
    var loadError: String? { loadState.errorMessage }

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
#if os(iOS)
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // The app uses light appearance. Keep native status-bar contrast changes
        // from changing the site's media queries and feeding back into detection.
        webView.overrideUserInterfaceStyle = .light
#endif
        webView.configuration.userContentController.add(headerColorObserver, contentWorld: .defaultClient, name: "forumIndexHeaderColor")
        headerColorObserver.onColor = { [weak self] message in
            guard let self,
                  let body = message.body as? [String: Any],
                  body["token"] as? String == self.headerColorToken,
                  let rgba = body["rgba"] as? [Double], rgba.count == 4,
                  rgba.allSatisfy({ $0.isFinite && (0...255).contains($0) }) else { return }
            // Compare relative luminance so status-bar text remains readable.
            let linear = rgba.prefix(3).map { component in
                let value = component / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            self.headerUsesLightStatusBar = 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2] < 0.179
            self.headerColor = Color(.sRGB, red: rgba[0] / 255, green: rgba[1] / 255, blue: rgba[2] / 255)
        }
    }

    func preload(_ url: URL, inBackground: Bool = false) {
        guard let url = WebNavigationPolicy.acceptedURL(url) else { return }
        isBackgroundLoading = inBackground
        // Keep the original request identity even if the site redirects while preloading.
        guard requestedURL != url else { return }
        requestedURL = url
        clearNavigationAllowance.cancel()
        webView.isHidden = true
        webView.stopLoading()
        currentURL = url
        resetHeaderColor()
        pendingGeneration = loadState.beginLoading()
#if DEBUG
        if ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TESTING"] == "1",
           let html = ProcessInfo.processInfo.environment["FORUM_INDEX_UI_TEST_HTML"] {
            pendingNavigation = webView.loadHTMLString(html, baseURL: url)
            return
        }
#endif
        pendingNavigation = webView.load(URLRequest(url: url))
    }

    func retry() {
        guard let url = currentURL else { return }
        requestedURL = nil
        preload(url)
    }

    func clear() {
        webView.stopLoading()
        webView.isHidden = true
        pendingNavigation = nil
        currentURL = nil
        requestedURL = nil
        isBackgroundLoading = false
        loadState.clear()
        resetHeaderColor()
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
        webView.callAsyncJavaScript(WebHeaderColorObserver.script,
                                   arguments: ["token": headerColorToken],
                                   in: nil, in: .defaultClient, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard navigation !== pendingNavigation, loadState.isReady else { return }
        currentURL = WebNavigationPolicy.acceptedURL(webView.url) ?? currentURL
        pendingNavigation = navigation
        resetHeaderColor()
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
        // Automatic HTTPS redirects (including a forum's domain migration) belong
        // to this page load. Only hand explicitly tapped external links to Safari.
        if navigationAction.navigationType == .linkActivated,
           navigationAction.targetFrame?.isMainFrame != false,
           let url = WebNavigationPolicy.externalURL(navigationAction.request.url, relativeTo: currentURL) {
            if !isBackgroundLoading { openExternalURL?(url) }
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

    private func resetHeaderColor() {
        headerColor = nil
        headerUsesLightStatusBar = nil
        headerColorToken = UUID().uuidString
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
