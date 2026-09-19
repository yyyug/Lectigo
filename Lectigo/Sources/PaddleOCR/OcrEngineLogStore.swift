import Foundation
import Combine

/// Lightweight in-memory ring buffer of OCR engine log lines, surfaced on the Text
/// Recognition settings screen so OCR failures can be diagnosed on-device.
final class OcrEngineLogStore: ObservableObject {
    static let shared = OcrEngineLogStore()
    @Published private(set) var lines: [String] = []
    private let lock = NSLock()
    private let maxLines = 200

    var allLines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }

    func add(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)"
        lock.lock()
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        lock.unlock()
    }

    func clear() {
        lock.lock()
        lines.removeAll()
        lock.unlock()
    }
}
