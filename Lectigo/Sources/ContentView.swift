import SwiftUI

struct ContentView: View {
    @AppStorage("capture.crop.top.percent") private var cropTopPercent = 20.0
    @AppStorage("capture.crop.bottom.percent") private var cropBottomPercent = 0.0
    @AppStorage("capture.crop.left.percent") private var cropLeftPercent = 0.0
    @AppStorage("capture.crop.right.percent") private var cropRightPercent = 0.0
    @AppStorage("capture.interval.seconds") private var captureInterval = 0.5

    @StateObject private var webViewStore = WebViewStore()
    @StateObject private var monitor = VideoCaptionMonitor(
        recognizer: PaddleOCRCaptionRecognizer(),
        announcer: SpeechAnnouncer()
    )

    @State private var addressText = "https://www.youtube.com/"
    @State private var showingSettings = false
    @State private var isPreparingOCR = false
    @State private var isOCRReady = false
    @State private var ocrPreparationError = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("YouTube URL", text: $addressText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                Button("Open") {
                    openAddress()
                }
                .buttonStyle(.borderedProminent)

                Button("Settings") {
                    showingSettings = true
                }
                .buttonStyle(.bordered)
            }
            .padding(12)

            YouTubeWebView(store: webViewStore)
                .overlay(alignment: .bottom) {
                    monitorOverlay
                }
        }
        .onAppear {
            openAddress()
            monitor.attach(webView: webViewStore.webView)
            applyCaptureSettings()
            prepareOCRIfNeeded()
        }
        .onDisappear {
            monitor.stop()
        }
        .sheet(isPresented: $showingSettings) {
            settingsView
                .presentationDetents([.medium, .large])
        }
    }

    private var monitorOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(monitor.isRunning ? "Stop OCR" : "Start OCR") {
                    monitor.isRunning ? monitor.stop() : monitor.start()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!monitor.isRunning && !isOCRReady)

                Text(monitor.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if isPreparingOCR {
                Text("Initializing Paddle OCR")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !ocrPreparationError.isEmpty {
                Text(ocrPreparationError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            if !monitor.lastRecognizedText.isEmpty {
                Text(monitor.lastRecognizedText)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
    }

    private func openAddress() {
        guard let url = URL(string: normalizedAddress(addressText)) else {
            return
        }
        webViewStore.webView.load(URLRequest(url: url))
    }

    private func applyCaptureSettings() {
        var settings = CaptureSettings(
            cropTopPercent: cropTopPercent,
            cropBottomPercent: cropBottomPercent,
            cropLeftPercent: cropLeftPercent,
            cropRightPercent: cropRightPercent,
            captureInterval: captureInterval
        )
        settings.sanitize()
        cropTopPercent = settings.cropTopPercent
        cropBottomPercent = settings.cropBottomPercent
        cropLeftPercent = settings.cropLeftPercent
        cropRightPercent = settings.cropRightPercent
        captureInterval = settings.captureInterval
        monitor.updateSettings(settings)
    }

    private func prepareOCRIfNeeded() {
        guard !isPreparingOCR, !isOCRReady else { return }
        isPreparingOCR = true
        ocrPreparationError = ""

        Task {
            do {
                try await PaddleOCRCaptionRecognizer().prepare()
                await MainActor.run {
                    isOCRReady = true
                    isPreparingOCR = false
                }
            } catch {
                await MainActor.run {
                    isOCRReady = false
                    isPreparingOCR = false
                    ocrPreparationError = error.localizedDescription
                }
            }
        }
    }

    private var settingsView: some View {
        NavigationStack {
            Form {
                Section("Capture Area") {
                    percentageField(
                        title: "Trim Top (%)",
                        value: $cropTopPercent
                    )
                    percentageField(
                        title: "Trim Bottom (%)",
                        value: $cropBottomPercent
                    )
                    percentageField(
                        title: "Trim Left (%)",
                        value: $cropLeftPercent
                    )
                    percentageField(
                        title: "Trim Right (%)",
                        value: $cropRightPercent
                    )

                    Text("Example: above = 20 means the top 20% is cut off and only the lower 80% is captured.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Timing") {
                    decimalField(
                        title: "Capture Interval (Second)",
                        value: $captureInterval
                    )

                    Text("0.5 captures and recognizes twice per second.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        applyCaptureSettings()
                        showingSettings = false
                    }
                }
            }
            .onDisappear {
                applyCaptureSettings()
            }
        }
    }

    private func percentageField(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
    }

    private func decimalField(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(1...2)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
    }

    private func normalizedAddress(_ value: String) -> String {
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return value
        }
        return "https://\(value)"
    }
}
