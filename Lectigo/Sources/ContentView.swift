import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            CaptureTabView()
                .tabItem {
                    Label("Capture", systemImage: "camera")
                }
            SettingsTabView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
    }
}

// MARK: - Capture Tab

private struct CaptureTabView: View {
    @AppStorage("capture.crop.top.percent") private var cropTopPercent = 20.0
    @AppStorage("capture.crop.bottom.percent") private var cropBottomPercent = 0.0
    @AppStorage("capture.crop.left.percent") private var cropLeftPercent = 0.0
    @AppStorage("capture.crop.right.percent") private var cropRightPercent = 0.0
    @AppStorage("capture.interval.seconds") private var captureInterval = 0.5
    @AppStorage("announcement.similarity.percent") private var announcementSimilarityPercent = 80.0
    @AppStorage("ocr.engine") private var ocrEngineRaw = CaptionEngine.paddle.rawValue
    @StateObject private var controller: ScreenCaptureCaptionController

    init() {
        let engineRaw = UserDefaults.standard.string(forKey: "ocr.engine") ?? CaptionEngine.paddle.rawValue
        let engine = CaptionEngine(rawValue: engineRaw) ?? .paddle
        _controller = StateObject(wrappedValue: ScreenCaptureCaptionController(recognizer: engine.makeRecognizer()))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                statusCard

                Spacer()

                currentCaptionView

                Spacer()

                captureButton
            }
            .padding()
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                applyCaptureSettings()
                await controller.prepare()
            }
            .onDisappear {
                if controller.isCapturing {
                    controller.stop()
                }
            }
        }
    }

    private func applyCaptureSettings() {
        var settings = CaptureSettings(
            cropTopPercent: cropTopPercent,
            cropBottomPercent: cropBottomPercent,
            cropLeftPercent: cropLeftPercent,
            cropRightPercent: cropRightPercent,
            captureInterval: captureInterval,
            announcementSimilarityPercent: announcementSimilarityPercent
        )
        settings.sanitize()
        controller.applySettings(settings)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(controller.statusText, systemImage: controller.isCapturing ? "dot.radiowaves.left.and.right" : "camera.fill")
                .font(.subheadline)
                .foregroundStyle(controller.isCapturing ? Color.green : Color.primary)

            Text("Choose the app window playing the video. Lectigo will OCR the subtitle area and announce new caption lines with VoiceOver.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private var currentCaptionView: some View {
        Text(controller.currentCaption.isEmpty ? "No caption yet" : controller.currentCaption)
            .font(.title2)
            .fontWeight(.semibold)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding()
            .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityLabel(controller.currentCaption.isEmpty ? "No caption yet" : "Current caption")
    }

    private var captureButton: some View {
        Button {
            if controller.isCapturing {
                controller.stop()
            } else {
                controller.start()
            }
        } label: {
            Label(
                controller.isCapturing ? "Stop Capture" : "Start Capturing",
                systemImage: controller.isCapturing ? "stop.circle.fill" : "record.circle"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(controller.isCapturing ? .red : .blue)
    }
}

// MARK: - Settings Tab

private struct SettingsTabView: View {
    @AppStorage("capture.crop.top.percent") private var cropTopPercent = 20.0
    @AppStorage("capture.crop.bottom.percent") private var cropBottomPercent = 0.0
    @AppStorage("capture.crop.left.percent") private var cropLeftPercent = 0.0
    @AppStorage("capture.crop.right.percent") private var cropRightPercent = 0.0
    @AppStorage("capture.interval.seconds") private var captureInterval = 0.5
    @AppStorage("announcement.similarity.percent") private var announcementSimilarityPercent = 80.0
    @AppStorage("ocr.engine") private var ocrEngineRaw = CaptionEngine.paddle.rawValue

    private var ocrEngineBinding: Binding<CaptionEngine> {
        Binding(
            get: { CaptionEngine(rawValue: ocrEngineRaw) ?? .paddle },
            set: { ocrEngineRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Text Recognition") {
                    Picker("OCR Engine", selection: ocrEngineBinding) {
                        ForEach(CaptionEngine.allCases, id: \.self) { engine in
                            Text(engine.displayName).tag(engine)
                        }
                    }
                    Text("iOS Vision uses the built-in on-device recognition. PaddleOCR uses the bundled ONNX models. The change applies the next time you start capturing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Capture Area") {
                    percentageField(title: "Trim Top (%)", value: $cropTopPercent)
                    percentageField(title: "Trim Bottom (%)", value: $cropBottomPercent)
                    percentageField(title: "Trim Left (%)", value: $cropLeftPercent)
                    percentageField(title: "Trim Right (%)", value: $cropRightPercent)

                    Text("Example: top = 20 keeps the lower 80% of the captured frame for OCR.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Timing") {
                    decimalField(title: "Capture Interval (Second)", value: $captureInterval)
                    Text("0.5 captures and recognizes twice per second while capture is active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Announcement") {
                    percentageField(title: "Similarity Threshold (%)", value: $announcementSimilarityPercent)
                    Text("If the new text is 80% similar or more to the previous announcement, it will not be announced again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear {
                applyCaptureSettings()
            }
        }
    }

    private func applyCaptureSettings() {
        var settings = CaptureSettings(
            cropTopPercent: cropTopPercent,
            cropBottomPercent: cropBottomPercent,
            cropLeftPercent: cropLeftPercent,
            cropRightPercent: cropRightPercent,
            captureInterval: captureInterval,
            announcementSimilarityPercent: announcementSimilarityPercent
        )
        settings.sanitize()
        cropTopPercent = settings.cropTopPercent
        cropBottomPercent = settings.cropBottomPercent
        cropLeftPercent = settings.cropLeftPercent
        cropRightPercent = settings.cropRightPercent
        captureInterval = settings.captureInterval
        announcementSimilarityPercent = settings.announcementSimilarityPercent
    }

    private func percentageField(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
        }
    }

    private func decimalField(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(1...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
        }
    }
}

// MARK: - OCR Engine Selection

enum CaptionEngine: String, CaseIterable {
    case paddle = "paddle"
    case vision = "vision"

    var displayName: String {
        switch self {
        case .paddle: return "PaddleOCR"
        case .vision: return "iOS Vision (Built-in)"
        }
    }

    func makeRecognizer() -> any CaptionOCRRecognizing {
        switch self {
        case .paddle: return PaddleOCRCaptionRecognizer()
        case .vision: return VisionCaptionRecognizer()
        }
    }
}