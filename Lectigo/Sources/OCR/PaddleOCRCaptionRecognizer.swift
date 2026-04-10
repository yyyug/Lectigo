import UIKit

final class PaddleOCRCaptionRecognizer: CaptionOCRRecognizing {
    func prepare() async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                autoreleasepool {
                    var error: NSError?
                    let prepared = PaddleOCRBridge.prepare(&error)
                    if let error {
                        continuation.resume(throwing: error)
                    } else if prepared {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: NSError(
                            domain: "Lectigo.PaddleOCRCaptionRecognizer",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Paddle OCR initialization failed."]
                        ))
                    }
                }
            }
        }
    }

    func recognizeCaption(in image: UIImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                autoreleasepool {
                    var error: NSError?
                    let text = PaddleOCRBridge.recognizeText(in: image, error: &error)
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            }
        }
    }
}
