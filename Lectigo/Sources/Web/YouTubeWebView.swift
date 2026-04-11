import SwiftUI
import WebKit

final class WebViewStore: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var addressText = "https://www.youtube.com/"
    @Published private(set) var currentURL: URL?

    let webView: WKWebView
    private static let desktopSafariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = Self.desktopSafariUserAgent
        webView.navigationDelegate = self
    }

    func openCurrentAddress() {
        guard let url = URL(string: normalizedAddress(addressText)) else {
            return
        }
        currentURL = url
        webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateCurrentURL(from: webView)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        updateCurrentURL(from: webView)
    }

    private func updateCurrentURL(from webView: WKWebView) {
        currentURL = webView.url
        if let absoluteString = webView.url?.absoluteString, !absoluteString.isEmpty {
            addressText = absoluteString
        }
    }

    private func normalizedAddress(_ value: String) -> String {
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return value
        }
        return "https://\(value)"
    }
}

struct YouTubeWebView: UIViewRepresentable {
    let store: WebViewStore

    func makeUIView(context: Context) -> WKWebView {
        store.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
    }
}
