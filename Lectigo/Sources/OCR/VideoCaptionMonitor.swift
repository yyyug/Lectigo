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
    private var settings = CaptureSettings()
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
        settings.sanitize()
        isRunning = true
        statusText = "Watching captions"
        timer = Timer.scheduledTimer(withTimeInterval: settings.captureInterval, repeats: true) { [weak self] _ in
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
        lastRecognizedText = ""
        statusText = "OCR stopped"
        announcer.stop()
    }

    func updateSettings(_ settings: CaptureSettings) {
        var sanitized = settings
        sanitized.sanitize()
        self.settings = sanitized

        if isRunning {
            stop()
            start()
        }
    }

    private func processFrameIfNeeded() async {
        guard isRunning, !isProcessingFrame, let webView else { return }
        isProcessingFrame = true
        defer { isProcessingFrame = false }

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

    private func takeCaptionSnapshot(from webView: WKWebView) async throws -> UIImage {
        let bounds = webView.bounds
        let leftInset = bounds.width * settings.cropLeftPercent / 100
        let rightInset = bounds.width * settings.cropRightPercent / 100
        let topInset = bounds.height * settings.cropTopPercent / 100
        let bottomInset = bounds.height * settings.cropBottomPercent / 100
        let cropRect = CGRect(
            x: leftInset,
            y: topInset,
            width: max(bounds.width - leftInset - rightInset, 1),
            height: max(bounds.height - topInset - bottomInset, 1)
        ).integral

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
        let current = normalized(text)
        let previous = normalized(lastSpokenText)

        guard !current.isEmpty else { return false }
        guard !previous.isEmpty else { return true }

        return similarityPercent(between: current, and: previous) < settings.announcementSimilarityPercent
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func similarityPercent(between lhs: String, and rhs: String) -> Double {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        let maxLength = max(lhsChars.count, rhsChars.count)
        guard maxLength > 0 else { return 100 }

        var previous = Array(0...rhsChars.count)
        for (lhsIndex, lhsChar) in lhsChars.enumerated() {
            var current = [lhsIndex + 1] + Array(repeating: 0, count: rhsChars.count)
            for (rhsIndex, rhsChar) in rhsChars.enumerated() {
                let cost = lhsChar == rhsChar ? 0 : 1
                current[rhsIndex + 1] = min(
                    previous[rhsIndex + 1] + 1,
                    current[rhsIndex] + 1,
                    previous[rhsIndex] + cost
                )
            }
            previous = current
        }

        let distance = previous[rhsChars.count]
        return (1 - (Double(distance) / Double(maxLength))) * 100
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
