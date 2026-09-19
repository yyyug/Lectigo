import Combine
import CoreImage
import CoreMedia
import ScreenCaptureKit
import UIKit

/// Captures the selected app's screen via ScreenCaptureKit (iOS 27+), runs OCR
/// on the subtitle area at a fixed interval, publishes the latest caption line,
/// and announces new text through `SpeechAnnouncer`.
final class ScreenCaptureCaptionController: NSObject, ObservableObject {
    @Published private(set) var statusText = "Ready"
    @Published private(set) var isCapturing = false
    @Published var currentCaption = ""

    private let recognizer: CaptionOCRRecognizing
    private let announcer = SpeechAnnouncer()
    private var settings = CaptureSettings()
    private let ciContext = CIContext()

    private var stream: SCStream?
    private var isStreamAddPending = false
    private var timer: Timer?
    private var latestPixelBuffer: CVPixelBuffer?
    private var isProcessingFrame = false
    private var lastAnnouncedText = ""
    private var didConfigurePicker = false

    init(recognizer: CaptionOCRRecognizing) {
        self.recognizer = recognizer
        super.init()
    }

    func applySettings(_ newSettings: CaptureSettings) {
        var sanitized = newSettings
        sanitized.sanitize()
        settings = sanitized
    }

    func prepare() async {
        do {
            try await recognizer.prepare()
            statusText = "Ready"
        } catch {
            statusText = "OCR prepare failed: \(error.localizedDescription)"
        }
    }

    func start() {
        guard !isCapturing else { return }
        let picker = SCContentSharingPicker.shared
        if !didConfigurePicker {
            var pickerConfig = SCContentSharingPickerConfiguration()
            pickerConfig.showsMicrophoneControl = false
            pickerConfig.showsCameraControl = false
            picker.defaultConfiguration = pickerConfig
            didConfigurePicker = true
        }
        picker.add(self)
        statusText = "Select content to capture"
        picker.present()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        latestPixelBuffer = nil
        SCContentSharingPicker.shared.remove(self)
        guard let stream else {
            teardownStream()
            return
        }
        stream.stopCapture { [weak self] _ in
            self?.teardownStream()
        }
    }

    private func teardownStream() {
        timer?.invalidate()
        timer = nil
        latestPixelBuffer = nil
        stream = nil
        isCapturing = false
    }
}

// MARK: - SCContentSharingPickerObserver

extension ScreenCaptureCaptionController: SCContentSharingPickerObserver {
    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        if let stream {
            beginCapturing(with: stream)
        } else {
            createStream(for: filter)
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        statusText = isCapturing ? "Capturing" : "Capture cancelled"
    }

    func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        isCapturing = false
        statusText = "Capture failed: \(error.localizedDescription)"
    }
}

// MARK: - SCStreamDelegate

extension ScreenCaptureCaptionController: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        teardownStream()
        statusText = "Capture stopped: \(error.localizedDescription)"
    }
}

// MARK: - SCStreamOutput

extension ScreenCaptureCaptionController: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        latestPixelBuffer = pixelBuffer
    }
}

// MARK: - Stream / frame handling

private extension ScreenCaptureCaptionController {
    func createStream(for filter: SCContentFilter) {
        guard !isStreamAddPending else { return }

        let config = SCStreamConfiguration()
        config.width = 1920
        config.height = 1080

        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        isStreamAddPending = true
        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
            newStream.startCapture { [weak self] error in
                guard let self else { return }
                self.isStreamAddPending = false
                if let error {
                    self.statusText = "Capture start failed: \(error.localizedDescription)"
                    return
                }
                self.stream = newStream
                self.beginCapturing(with: newStream)
            }
        } catch {
            isStreamAddPending = false
            statusText = "Capture setup failed: \(error.localizedDescription)"
        }
    }

    func beginCapturing(with stream: SCStream) {
        self.stream = stream
        isCapturing = true
        statusText = "Capturing"
        restartTimer()
    }

    func restartTimer() {
        timer?.invalidate()
        let interval = max(settings.captureInterval, 0.1)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.processLatestFrame()
        }
    }

    func processLatestFrame() {
        guard isCapturing, !isProcessingFrame, let pixelBuffer = latestPixelBuffer else { return }
        isProcessingFrame = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isProcessingFrame = false }
            do {
                let image = try self.croppedUIImage(from: pixelBuffer)
                let text = try await self.recognizer.recognizeCaption(in: image)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                self.currentCaption = trimmed
                if self.shouldAnnounce(trimmed) {
                    self.lastAnnouncedText = trimmed
                    self.announcer.speak(trimmed)
                }
            } catch {
                // Keep the previous caption; transient OCR errors are expected.
            }
        }
    }

    func croppedUIImage(from pixelBuffer: CVPixelBuffer) throws -> UIImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent.integral
        guard let cgImage = ciContext.createCGImage(ciImage, from: extent) else {
            throw ScreenCaptureCaptionError.frameConversionFailed
        }

        let sourceImage = UIImage(cgImage: cgImage)
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let leftInset = width * settings.cropLeftPercent / 100
        let rightInset = width * settings.cropRightPercent / 100
        let topInset = height * settings.cropTopPercent / 100
        let bottomInset = height * settings.cropBottomPercent / 100
        let cropRect = CGRect(
            x: leftInset,
            y: topInset,
            width: max(width - leftInset - rightInset, 1),
            height: max(height - topInset - bottomInset, 1)
        ).integral

        guard let croppedCGImage = sourceImage.cgImage?.cropping(to: cropRect) else {
            throw ScreenCaptureCaptionError.frameCropFailed
        }
        return UIImage(cgImage: croppedCGImage)
    }

    func shouldAnnounce(_ text: String) -> Bool {
        let current = normalized(text)
        let previous = normalized(lastAnnouncedText)
        guard !current.isEmpty else { return false }
        guard !previous.isEmpty else { return true }
        return similarityPercent(between: current, and: previous) < settings.announcementSimilarityPercent
    }

    func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func similarityPercent(between lhs: String, and rhs: String) -> Double {
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

private enum ScreenCaptureCaptionError: LocalizedError {
    case frameConversionFailed
    case frameCropFailed

    var errorDescription: String? {
        switch self {
        case .frameConversionFailed:
            return "Could not convert the captured frame for OCR."
        case .frameCropFailed:
            return "Could not crop the captured frame for OCR."
        }
    }
}