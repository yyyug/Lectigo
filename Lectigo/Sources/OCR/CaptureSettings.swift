import Foundation

struct CaptureSettings {
    var cropTopPercent: Double = 20
    var cropBottomPercent: Double = 0
    var cropLeftPercent: Double = 0
    var cropRightPercent: Double = 0
    var captureInterval: Double = 0.5

    mutating func sanitize() {
        cropTopPercent = Self.clampedPercent(cropTopPercent)
        cropBottomPercent = Self.clampedPercent(cropBottomPercent)
        cropLeftPercent = Self.clampedPercent(cropLeftPercent)
        cropRightPercent = Self.clampedPercent(cropRightPercent)
        captureInterval = min(max(captureInterval, 0.1), 10.0)

        if cropTopPercent + cropBottomPercent >= 100 {
            cropBottomPercent = max(0, 99 - cropTopPercent)
        }
        if cropLeftPercent + cropRightPercent >= 100 {
            cropRightPercent = max(0, 99 - cropLeftPercent)
        }
    }

    private static func clampedPercent(_ value: Double) -> Double {
        min(max(value, 0), 99)
    }
}
