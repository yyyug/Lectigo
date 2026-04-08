import UIKit

protocol CaptionOCRRecognizing {
    func recognizeCaption(in image: UIImage) async throws -> String
}
