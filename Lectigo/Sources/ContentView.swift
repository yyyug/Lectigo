import SwiftUI

struct ContentView: View {
    @StateObject private var webViewStore = WebViewStore()
    @StateObject private var monitor = VideoCaptionMonitor(
        recognizer: FallbackCaptionRecognizer(
            primary: PaddleOCRCaptionRecognizer(),
            fallback: VisionCaptionRecognizer()
        ),
        announcer: SpeechAnnouncer()
    )

    @State private var addressText = "https://m.youtube.com/"

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("YouTube URL", text: $addressText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                Button("Open") {
                    openAddress()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)

            YouTubeWebView(store: webViewStore)
                .overlay(alignment: .bottom) {
                    monitorOverlay
                }
        }
        .onAppear {
            openAddress()
            monitor.attach(webView: webViewStore.webView)
        }
        .onDisappear {
            monitor.stop()
        }
    }

    private var monitorOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(monitor.isRunning ? "Stop OCR" : "Start OCR") {
                    monitor.isRunning ? monitor.stop() : monitor.start()
                }
                .buttonStyle(.borderedProminent)

                Text(monitor.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !monitor.lastRecognizedText.isEmpty {
                Text(monitor.lastRecognizedText)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
    }

    private func openAddress() {
        guard let url = URL(string: normalizedAddress(addressText)) else {
            return
        }
        webViewStore.webView.load(URLRequest(url: url))
    }

    private func normalizedAddress(_ value: String) -> String {
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return value
        }
        return "https://\(value)"
    }
}
