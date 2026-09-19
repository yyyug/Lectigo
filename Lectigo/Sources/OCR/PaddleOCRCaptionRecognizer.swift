import UIKit

final class PaddleOCRCaptionRecognizer: CaptionOCRRecognizing {
    private let sessionManager = ORTSessionManager()
    private var engine: OCREngine?

    func prepare() async throws {
        try await sessionManager.loadModels(executionProvider: .cpu)
        engine = try OCREngine(sessionManager: sessionManager)
    }

    func recognizeCaption(in image: UIImage) async throws -> String {
        guard let engine else {
            throw PaddleCaptionRecognizerError.engineNotPrepared
        }
        guard let cgImage = image.cgImage else {
            throw PaddleCaptionRecognizerError.invalidImage
        }
        let run = try await engine.run(cgImage)
        let text = run.results
            .map(\.text)
            .joined(separator: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum PaddleCaptionRecognizerError: LocalizedError {
    case engineNotPrepared
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .engineNotPrepared:
            return "The PaddleOCR engine has not been prepared yet."
        case .invalidImage:
            return "Could not prepare the caption snapshot for PaddleOCR."
        }
    }
}