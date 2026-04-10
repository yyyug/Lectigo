import UIKit

final class SpeechAnnouncer {
    var isVoiceOverEnabled: Bool {
        UIAccessibility.isVoiceOverRunning
    }

    func speak(_ text: String) {
        guard !text.isEmpty, UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    func stop() {
    }
}
