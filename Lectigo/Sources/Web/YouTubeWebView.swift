import SwiftUI
import WebKit

final class WebViewStore: NSObject, ObservableObject, WKNavigationDelegate {
    enum PlaybackState: String, Equatable {
        case idle
        case playing
        case paused
    }

    @Published private(set) var playbackState: PlaybackState = .idle

    let webView: WKWebView
    private let playbackBridge = PlaybackBridge()

    private static let playbackMessageName = "lectigoPlayback"
    private static let playbackObserverScript = #"""
    (() => {
      if (window.__lectigoPlaybackBootstrapInstalled) {
        if (window.__lectigoInstallPlaybackObserver) {
          window.__lectigoInstallPlaybackObserver();
        }
        return;
      }

      window.__lectigoPlaybackBootstrapInstalled = true;

      const sendState = (state) => {
        try {
          window.webkit.messageHandlers.lectigoPlayback.postMessage({ state });
        } catch (_) {
        }
      };

      const currentState = (video) => {
        if (!video) {
          return 'idle';
        }
        if (!video.paused && !video.ended && video.readyState > 2) {
          return 'playing';
        }
        return 'paused';
      };

      const bindVideo = (video) => {
        if (!video || video.__lectigoPlaybackBound) {
          return;
        }

        video.__lectigoPlaybackBound = true;
        ['play', 'playing', 'pause', 'ended', 'emptied', 'abort', 'suspend', 'waiting'].forEach((eventName) => {
          video.addEventListener(eventName, () => {
            sendState(currentState(video));
          });
        });
      };

      window.__lectigoInstallPlaybackObserver = () => {
        const video = document.querySelector('video');
        bindVideo(video);
        sendState(currentState(video));
      };

      window.__lectigoInstallPlaybackObserver();
      window.setInterval(() => {
        window.__lectigoInstallPlaybackObserver();
      }, 1000);
    })();
    """#

    init() {
        let configuration = WKWebViewConfiguration()
        let userContentController = WKUserContentController()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController = userContentController

        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        playbackBridge.store = self
        userContentController.add(playbackBridge, name: Self.playbackMessageName)
        userContentController.addUserScript(
            WKUserScript(
                source: Self.playbackObserverScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: false
            )
        )

        self.webView.allowsBackForwardNavigationGestures = true
        self.webView.navigationDelegate = self
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.playbackMessageName)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        installPlaybackObserver(in: webView)
    }

    fileprivate func updatePlaybackState(from value: Any?) {
        let nextState: PlaybackState

        if let body = value as? [String: Any],
           let state = body["state"] as? String,
           let parsedState = PlaybackState(rawValue: state) {
            nextState = parsedState
        } else if let state = value as? String,
                  let parsedState = PlaybackState(rawValue: state) {
            nextState = parsedState
        } else {
            nextState = .idle
        }

        guard playbackState != nextState else { return }
        playbackState = nextState
    }

    private func installPlaybackObserver(in webView: WKWebView) {
        webView.evaluateJavaScript("window.__lectigoInstallPlaybackObserver && window.__lectigoInstallPlaybackObserver();") { [weak self] result, _ in
            self?.updatePlaybackState(from: result)
        }
    }
}

private final class PlaybackBridge: NSObject, WKScriptMessageHandler {
    weak var store: WebViewStore?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        store?.updatePlaybackState(from: message.body)
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
