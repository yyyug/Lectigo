import UIKit

protocol CaptionOCRRecognizing {
    func prepare() async throws
    func recognizeCaption(in image: UIImage) async throws -> String
}

extension CaptionOCRRecognizing {
    func prepare() async throws {}
}
