import SwiftUI
import WebKit

@MainActor
final class VideoCaptionMonitor: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "OCR stopped"
    @Published private(set) var lastRecognizedText = ""

    private weak var webView: WKWebView?
    private let recognizer: CaptionOCRRecognizing
    private let announcer: SpeechAnnouncer
    private var timer: Timer?
    private var isProcessingFrame = false
    private var lastSpokenText = ""

    init(recognizer: CaptionOCRRecognizing, announcer: SpeechAnnouncer) {
        self.recognizer = recognizer
        self.announcer = announcer
    }

    func attach(webView: WKWebView) {
        self.webView = webView
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        statusText = "Watching video captions"
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.processFrameIfNeeded()
            }
        }
        timer?.fire()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        isProcessingFrame = false
        statusText = "OCR stopped"
        announcer.stop()
    }

    private func processFrameIfNeeded() async {
        guard isRunning, !isProcessingFrame, let webView else { return }
        isProcessingFrame = true
        defer { isProcessingFrame = false }

        guard await isVideoPlaying(in: webView) else {
            statusText = "Video is not playing"
            return
        }

        do {
            let snapshot = try await takeCaptionSnapshot(from: webView)
            let recognizedText = try await recognizer.recognizeCaption(in: snapshot)
            guard !recognizedText.isEmpty else {
                statusText = "No caption text detected"
                return
            }

            lastRecognizedText = recognizedText
            statusText = "Caption recognized"

            if shouldSpeak(recognizedText) {
                lastSpokenText = recognizedText
                announcer.speak(recognizedText)
            }
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func isVideoPlaying(in webView: WKWebView) async -> Bool {
        await withCheckedContinuation { continuation in
            let script = """
            (() => {
              const video = document.querySelector('video');
              return !!video && !video.paused && !video.ended && video.readyState > 2;
            })();
            """
            webView.evaluateJavaScript(script) { result, _ in
                continuation.resume(returning: (result as? Bool) == true)
            }
        }
    }

    private func takeCaptionSnapshot(from webView: WKWebView) async throws -> UIImage {
        let bounds = webView.bounds
        let captionHeight = max(bounds.height * 0.35, 180)
        let cropRect = CGRect(
            x: 0,
            y: max(bounds.height - captionHeight, 0),
            width: bounds.width,
            height: min(captionHeight, bounds.height)
        )

        let configuration = WKSnapshotConfiguration()
        configuration.rect = cropRect
        configuration.afterScreenUpdates = false

        return try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: configuration) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? CaptionMonitorError.snapshotFailed)
                }
            }
        }
    }

    private func shouldSpeak(_ text: String) -> Bool {
        normalized(text) != normalized(lastSpokenText)
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CaptionMonitorError: LocalizedError {
    case snapshotFailed

    var errorDescription: String? {
        switch self {
        case .snapshotFailed:
            return "Could not capture a web view snapshot."
        }
    }
}
