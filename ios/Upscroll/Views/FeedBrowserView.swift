import SwiftUI
@preconcurrency import WebKit

/// Full-screen WKWebView hosting the user's own short-video feed, with the platform bridge injected.
struct FeedBrowserView: UIViewRepresentable {
    let bridge: PlatformBridge
    let session: FeedSession

    /// Suffix that turns WKWebView's own UA into the exact Mobile Safari UA for this iOS version.
    /// WebKit fills in the real "iPhone OS x_y" part itself, so the UA never disagrees with the
    /// engine — a mismatch is one of the signals Google uses to refuse sign-in in embedded browsers.
    static var safariApplicationName: String {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return "Version/\(major).0 Mobile/15E148 Safari/604.1"
    }

    func makeCoordinator() -> Coordinator { Coordinator(bridge: bridge, session: session) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()               // persistent cookies: sign in once
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = false
        config.applicationNameForUserAgent = Self.safariApplicationName
        config.defaultWebpagePreferences.preferredContentMode = .mobile

        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(source: bridge.userScriptSource,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true))
        controller.add(context.coordinator, name: bridge.messageHandlerName)
        config.userContentController = controller

        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = true
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.isOpaque = false
        web.backgroundColor = .black
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        #if DEBUG
        if #available(iOS 16.4, *) { web.isInspectable = true }   // Safari ▸ Develop for the spike
        #endif
        session.web.webView = web
        context.coordinator.urlObservation = web.observe(\.url, options: [.initial, .new]) { [session] web, _ in
            let url = web.url
            Task { @MainActor in session.pageChanged(url) }
        }
        var start = session.settings.japaneseFeed ? WebController.feedURL(japanese: true) : bridge.startURL
        #if DEBUG
        // `-startURL <url>` for testing other pages (e.g. the Google sign-in page).
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-startURL"),
           i + 1 < ProcessInfo.processInfo.arguments.count,
           let u = URL(string: ProcessInfo.processInfo.arguments[i + 1]) { start = u }
        #endif
        web.load(URLRequest(url: start))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: coordinator.bridge.messageHandlerName)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        let bridge: PlatformBridge
        let session: FeedSession
        var urlObservation: NSKeyValueObservation?

        init(bridge: PlatformBridge, session: FeedSession) {
            self.bridge = bridge
            self.session = session
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let type = body["type"] as? String,
                  let payload = body["payload"] as? String,
                  let event = bridge.decode(type: type, json: payload) else { return }
            Task { @MainActor in session.handle(event) }
        }

        // Keep the user inside the feed: block app-store / intent:// "open in app" redirects.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
                decisionHandler(.allow); return
            }
            if scheme == "http" || scheme == "https" || scheme == "about" || scheme == "blob" || scheme == "data" {
                let host = url.host?.lowercased() ?? ""
                decisionHandler(host.hasSuffix("apps.apple.com") || host.hasSuffix("itunes.apple.com") ? .cancel : .allow)
            } else {
                // vnd.youtube://, youtube://, intent:// etc.
                Task { @MainActor in session.handle(.log("blocked app redirect: \(url.absoluteString.prefix(80))")) }
                decisionHandler(.cancel)
            }
        }

        // Google sign-in and other target=_blank links: load in the same view instead of dropping them.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let href = webView.url?.absoluteString ?? "?"
            Task { @MainActor in session.handle(.log("loaded \(href)")) }
        }
    }
}
