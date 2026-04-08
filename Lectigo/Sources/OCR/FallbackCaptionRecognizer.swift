import UIKit

final class FallbackCaptionRecognizer: CaptionOCRRecognizing {
    private let primary: CaptionOCRRecognizing
    private let fallback: CaptionOCRRecognizing

    init(primary: CaptionOCRRecognizing, fallback: CaptionOCRRecognizing) {
        self.primary = primary
        self.fallback = fallback
    }

    func recognizeCaption(in image: UIImage) async throws -> String {
        do {
            return try await primary.recognizeCaption(in: image)
        } catch {
            return try await fallback.recognizeCaption(in: image)
        }
    }
}
