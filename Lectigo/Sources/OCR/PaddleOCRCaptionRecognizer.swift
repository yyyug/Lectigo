import UIKit

final class PaddleOCRCaptionRecognizer: CaptionOCRRecognizing {
    func prepare() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                autoreleasepool {
                    do {
                        try PaddleOCRBridge.prepare()
                        continuation.resume(returning: ())
                    } catch {
                        continuation.resume(throwing: error)
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
