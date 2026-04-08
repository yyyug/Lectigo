import UIKit
import Vision

final class VisionCaptionRecognizer: CaptionOCRRecognizing {
    func recognizeCaption(in image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else {
            throw VisionCaptionRecognizerError.invalidImage
        }

        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "zh-Hant", "zh-Hans", "ja-JP", "ko-KR"]
            request.minimumTextHeight = 0.03

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])

            let text = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")

            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }
}

enum VisionCaptionRecognizerError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Could not prepare the caption snapshot for OCR."
        }
    }
}
