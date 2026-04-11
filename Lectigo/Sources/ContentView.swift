import AVFoundation
import AVKit
import Combine
import CoreImage
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var webViewStore = WebViewStore()
    @StateObject private var libraryStore = VideoLibraryStore()
    @State private var selectedTab: RootTab = .browse

    var body: some View {
        TabView(selection: $selectedTab) {
            BrowseTabView(webViewStore: webViewStore, libraryStore: libraryStore, onOpenLibrary: {
                selectedTab = .library
            })
            .tabItem {
                Label("Browse", systemImage: "globe")
            }
            .tag(RootTab.browse)

            LibraryTabView(libraryStore: libraryStore)
            .tabItem {
                Label("Library", systemImage: "square.stack")
            }
            .tag(RootTab.library)

            SettingsTabView()
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(RootTab.settings)
        }
        .task {
            webViewStore.openCurrentAddress()
        }
    }
}

private enum RootTab {
    case browse
    case library
    case settings
}

private struct BrowseTabView: View {
    @ObservedObject var webViewStore: WebViewStore
    @ObservedObject var libraryStore: VideoLibraryStore
    let onOpenLibrary: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("YouTube URL", text: $webViewStore.addressText)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                Button("Open") {
                    webViewStore.openCurrentAddress()
                }
                .buttonStyle(.borderedProminent)

                Button("Download") {
                    if let url = webViewStore.currentURL {
                        libraryStore.enqueueDownload(from: url)
                        onOpenLibrary()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(webViewStore.currentURL == nil)
            }
            .padding(12)

            if let browserMessage = libraryStore.browserMessage {
                Text(browserMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            YouTubeWebView(store: webViewStore)
        }
    }
}

private struct LibraryTabView: View {
    @ObservedObject var libraryStore: VideoLibraryStore

    var body: some View {
        NavigationStack {
            List {
                if !libraryStore.activeItems.isEmpty {
                    Section("Downloading") {
                        ForEach(libraryStore.activeItems) { item in
                            ActiveDownloadRow(item: item)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        libraryStore.delete(item)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }

                Section("Downloaded") {
                    if libraryStore.downloadedItems.isEmpty {
                        Text("No downloaded videos yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(libraryStore.downloadedItems) { item in
                            NavigationLink {
                                LocalVideoPlayerScreen(item: item)
                            } label: {
                                DownloadedVideoRow(item: item)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    libraryStore.delete(item)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if libraryStore.isProcessingQueue {
                        ProgressView()
                    }
                }
            }
        }
    }
}

private struct ActiveDownloadRow: View {
    let item: VideoLibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.displayTitle)
                .font(.headline)
            Text(item.statusLabel)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !item.progressText.isEmpty {
                Text(item.progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let errorText = item.errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct DownloadedVideoRow: View {
    let item: VideoLibraryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.displayTitle)
                .font(.headline)
            if let durationText = item.durationText {
                Text(durationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let sourceURLString = item.sourceURLString {
                Text(sourceURLString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct LocalVideoPlayerScreen: View {
    let item: VideoLibraryItem

    @AppStorage("capture.crop.top.percent") private var cropTopPercent = 20.0
    @AppStorage("capture.crop.bottom.percent") private var cropBottomPercent = 0.0
    @AppStorage("capture.crop.left.percent") private var cropLeftPercent = 0.0
    @AppStorage("capture.crop.right.percent") private var cropRightPercent = 0.0
    @AppStorage("capture.interval.seconds") private var captureInterval = 0.5
    @AppStorage("announcement.similarity.percent") private var announcementSimilarityPercent = 80.0

    @StateObject private var controller = LocalPlaybackOCRController(
        recognizer: PaddleOCRCaptionRecognizer(),
        announcer: SpeechAnnouncer()
    )

    var body: some View {
        VStack(spacing: 0) {
            VideoPlayer(player: controller.player)
                .background(.black)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(controller.statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !controller.lastRecognizedText.isEmpty {
                            Text(controller.lastRecognizedText)
                                .font(.caption)
                                .lineLimit(3)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial)
                }
        }
        .navigationTitle(item.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await controller.prepareOCRIfNeeded()
            controller.loadVideo(from: item.localFileURL)
            controller.updateSettings(currentCaptureSettings())
        }
        .onDisappear {
            controller.stop()
        }
    }

    private func currentCaptureSettings() -> CaptureSettings {
        var settings = CaptureSettings(
            cropTopPercent: cropTopPercent,
            cropBottomPercent: cropBottomPercent,
            cropLeftPercent: cropLeftPercent,
            cropRightPercent: cropRightPercent,
            captureInterval: captureInterval,
            announcementSimilarityPercent: announcementSimilarityPercent
        )
        settings.sanitize()
        return settings
    }
}

private struct SettingsTabView: View {
    @AppStorage("capture.crop.top.percent") private var cropTopPercent = 20.0
    @AppStorage("capture.crop.bottom.percent") private var cropBottomPercent = 0.0
    @AppStorage("capture.crop.left.percent") private var cropLeftPercent = 0.0
    @AppStorage("capture.crop.right.percent") private var cropRightPercent = 0.0
    @AppStorage("capture.interval.seconds") private var captureInterval = 0.5
    @AppStorage("announcement.similarity.percent") private var announcementSimilarityPercent = 80.0

    var body: some View {
        NavigationStack {
            Form {
                Section("Capture Area") {
                    percentageField(title: "Trim Top (%)", value: $cropTopPercent)
                    percentageField(title: "Trim Bottom (%)", value: $cropBottomPercent)
                    percentageField(title: "Trim Left (%)", value: $cropLeftPercent)
                    percentageField(title: "Trim Right (%)", value: $cropRightPercent)

                    Text("Example: top = 20 keeps the lower 80% of the video frame for OCR.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Timing") {
                    decimalField(title: "Capture Interval (Second)", value: $captureInterval)
                    Text("0.5 captures and recognizes twice per second while local playback is active.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Announcement") {
                    percentageField(title: "Similarity Threshold (%)", value: $announcementSimilarityPercent)
                    Text("If the new text is 80% similar or more to the previous announcement, it will not be announced again. Users can change this value.")
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

@MainActor
final class VideoLibraryStore: ObservableObject {
    @Published private(set) var items: [VideoLibraryItem] = []
    @Published private(set) var isProcessingQueue = false
    @Published var browserMessage: String?

    private let downloader = OnDeviceYouTubeDownloader()

    init() {
        load()
        processQueueIfNeeded()
    }

    var activeItems: [VideoLibraryItem] {
        items.filter { $0.status != .downloaded }
    }

    var downloadedItems: [VideoLibraryItem] {
        items.filter { $0.status == .downloaded }
    }

    func enqueueDownload(from url: URL) {
        var item = VideoLibraryItem(
            id: UUID(),
            sourceURLString: url.absoluteString,
            title: url.lastPathComponent.isEmpty ? url.absoluteString : url.lastPathComponent,
            localRelativePath: nil,
            status: .queued,
            progressText: "Queued",
            errorText: nil,
            createdAt: Date(),
            durationSeconds: nil,
            thumbnailRelativePath: nil
        )
        if item.title.isEmpty {
            item.title = url.absoluteString
        }
        items.insert(item, at: 0)
        browserMessage = "Queued download for \(url.absoluteString)"
        persist()
        processQueueIfNeeded()
    }

    func delete(_ item: VideoLibraryItem) {
        if let fileURL = item.localFileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        if let containerURL = item.localDirectoryURL {
            try? FileManager.default.removeItem(at: containerURL)
        }
        items.removeAll { $0.id == item.id }
        persist()
    }

    private func processQueueIfNeeded() {
        guard !isProcessingQueue else { return }
        guard let nextItem = items.first(where: { $0.status == .queued }) else { return }

        isProcessingQueue = true
        Task {
            await runDownload(for: nextItem.id)
        }
    }

    private func runDownload(for itemID: UUID) async {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              let sourceURLString = items[index].sourceURLString,
              let sourceURL = URL(string: sourceURLString) else {
            isProcessingQueue = false
            processQueueIfNeeded()
            return
        }

        items[index].status = .downloading
        items[index].progressText = "Preparing download"
        items[index].errorText = nil
        persist()

        let destinationDirectory = VideoLibraryPaths.directoryForItem(id: itemID)
        do {
            let result = try await downloader.downloadVideo(
                from: sourceURL,
                itemID: itemID,
                destinationDirectory: destinationDirectory,
                progress: { [itemID] text in
                    await MainActor.run {
                        guard let itemIndex = self.items.firstIndex(where: { $0.id == itemID }) else { return }
                        self.items[itemIndex].progressText = text
                        self.persist()
                    }
                }
            )

            guard let itemIndex = items.firstIndex(where: { $0.id == itemID }) else {
                isProcessingQueue = false
                processQueueIfNeeded()
                return
            }

            let relativePath = result.fileURL.path.replacingOccurrences(of: VideoLibraryPaths.rootDirectory.path + "/", with: "")
            items[itemIndex].status = .downloaded
            items[itemIndex].title = result.title
            items[itemIndex].localRelativePath = relativePath
            items[itemIndex].progressText = "Download complete"
            items[itemIndex].durationSeconds = result.durationSeconds
            items[itemIndex].errorText = nil
            browserMessage = "Downloaded \(result.title)"
            persist()
        } catch {
            if let itemIndex = items.firstIndex(where: { $0.id == itemID }) {
                items[itemIndex].status = .failed
                items[itemIndex].progressText = "Download failed"
                items[itemIndex].errorText = error.localizedDescription
            }
            browserMessage = error.localizedDescription
            persist()
        }

        isProcessingQueue = false
        processQueueIfNeeded()
    }

    private func load() {
        do {
            let data = try Data(contentsOf: VideoLibraryPaths.indexFileURL)
            items = try JSONDecoder().decode([VideoLibraryItem].self, from: data)
        } catch {
            items = []
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: VideoLibraryPaths.rootDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(items)
            try data.write(to: VideoLibraryPaths.indexFileURL, options: .atomic)
        } catch {
            browserMessage = error.localizedDescription
        }
    }
}

private enum VideoLibraryPaths {
    static var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("LectigoLibrary", isDirectory: true)
    }

    static var indexFileURL: URL {
        rootDirectory.appendingPathComponent("library.json")
    }

    static func directoryForItem(id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }
}

struct VideoLibraryItem: Identifiable, Codable, Hashable {
    let id: UUID
    var sourceURLString: String?
    var title: String
    var localRelativePath: String?
    var status: Status
    var progressText: String
    var errorText: String?
    var createdAt: Date
    var durationSeconds: Double?
    var thumbnailRelativePath: String?

    enum Status: String, Codable {
        case queued
        case downloading
        case downloaded
        case failed
    }

    var displayTitle: String {
        title.isEmpty ? "Untitled Video" : title
    }

    var statusLabel: String {
        switch status {
        case .queued:
            return "Queued"
        case .downloading:
            return "Downloading"
        case .downloaded:
            return "Downloaded"
        case .failed:
            return "Failed"
        }
    }

    var localFileURL: URL? {
        guard let localRelativePath else { return nil }
        return VideoLibraryPaths.rootDirectory.appendingPathComponent(localRelativePath)
    }

    var localDirectoryURL: URL? {
        localFileURL?.deletingLastPathComponent()
    }

    var durationText: String? {
        guard let durationSeconds else { return nil }
        let totalSeconds = Int(durationSeconds.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct DownloadedVideoResult {
    let fileURL: URL
    let title: String
    let durationSeconds: Double?
}

private final class OnDeviceYouTubeDownloader {
    private let directVideoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv"]

    func downloadVideo(
        from sourceURL: URL,
        itemID: UUID,
        destinationDirectory: URL,
        progress: @escaping @Sendable (String) async -> Void
    ) async throws -> DownloadedVideoResult {
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        if isDirectMediaURL(sourceURL) {
            await progress("Downloading direct media")
            let (temporaryURL, _) = try await URLSession.shared.download(from: sourceURL)
            let fileName = sanitizedFileName(from: sourceURL.lastPathComponent.isEmpty ? itemID.uuidString : sourceURL.lastPathComponent)
            let destinationURL = destinationDirectory.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
            let duration = try await loadDuration(for: destinationURL)
            return DownloadedVideoResult(
                fileURL: destinationURL,
                title: destinationURL.deletingPathExtension().lastPathComponent,
                durationSeconds: duration
            )
        }

        await progress("Running bundled yt-dlp")
        let filePath = try await ToolRunnerBridge.downloadVideo(
            fromURLString: sourceURL.absoluteString,
            outputDirectory: destinationDirectory.path,
            progress: { line in
                Task {
                    await progress(line)
                }
            }
        )

        let resultURL = URL(fileURLWithPath: filePath)
        let duration = try await loadDuration(for: resultURL)
        return DownloadedVideoResult(
            fileURL: resultURL,
            title: resultURL.deletingPathExtension().lastPathComponent,
            durationSeconds: duration
        )
    }

    private func isDirectMediaURL(_ url: URL) -> Bool {
        directVideoExtensions.contains(url.pathExtension.lowercased())
    }

    private func sanitizedFileName(from rawValue: String) -> String {
        let fallback = UUID().uuidString + ".mp4"
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = rawValue.components(separatedBy: invalidCharacters).joined(separator: "_")
        return cleaned.isEmpty ? fallback : cleaned
    }

    private func loadDuration(for fileURL: URL) async throws -> Double? {
        let asset = AVURLAsset(url: fileURL)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? seconds : nil
    }
}

@MainActor
final class LocalPlaybackOCRController: ObservableObject {
    @Published private(set) var statusText = "Ready"
    @Published private(set) var lastRecognizedText = ""

    let player = AVPlayer()

    private let recognizer: PaddleOCRCaptionRecognizer
    private let announcer: SpeechAnnouncer
    private var settings = CaptureSettings()
    private let ciContext = CIContext()
    private var playerObservation: NSKeyValueObservation?
    private var currentItemObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var videoOutput: AVPlayerItemVideoOutput?
    private var timer: Timer?
    private var isProcessingFrame = false
    private var lastAnnouncedText = ""
    private var prepared = false

    init(recognizer: PaddleOCRCaptionRecognizer, announcer: SpeechAnnouncer) {
        self.recognizer = recognizer
        self.announcer = announcer
        observePlayer()
    }

    func prepareOCRIfNeeded() async {
        guard !prepared else { return }
        do {
            try await recognizer.prepare()
            prepared = true
            statusText = "Ready"
        } catch {
            statusText = error.localizedDescription
        }
    }

    func updateSettings(_ settings: CaptureSettings) {
        var sanitized = settings
        sanitized.sanitize()
        self.settings = sanitized
        if timer != nil {
            stopFrameTimer()
            startFrameTimer()
        }
    }

    func loadVideo(from fileURL: URL?) {
        stop(resetText: true)

        guard let fileURL else {
            statusText = "Video file is missing"
            return
        }

        let asset = AVURLAsset(url: fileURL)
        let item = AVPlayerItem(asset: asset)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        videoOutput = output
        player.replaceCurrentItem(with: item)
        statusText = "Ready to play"
    }

    func stop(resetText: Bool = true) {
        player.pause()
        player.replaceCurrentItem(with: nil)
        stopFrameTimer()
        videoOutput = nil
        if resetText {
            lastRecognizedText = ""
            lastAnnouncedText = ""
        }
        statusText = "Ready"
    }

    private func observePlayer() {
        playerObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.handlePlaybackStatus(player.timeControlStatus)
            }
        }

        currentItemObservation = player.observe(\.currentItem, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.bindEndObserver(for: player.currentItem)
            }
        }
    }

    private func bindEndObserver(for item: AVPlayerItem?) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        guard let item else { return }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stopFrameTimer()
                self?.statusText = "Playback ended"
            }
        }
    }

    private func handlePlaybackStatus(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            guard prepared else {
                statusText = "Initializing Paddle OCR"
                return
            }
            statusText = "Playing and recognizing"
            startFrameTimer()
        case .paused:
            stopFrameTimer()
            if player.currentItem != nil {
                statusText = "Playback paused"
            }
        case .waitingToPlayAtSpecifiedRate:
            stopFrameTimer()
            statusText = "Waiting for playback"
        @unknown default:
            stopFrameTimer()
            statusText = "Playback unavailable"
        }
    }

    private func startFrameTimer() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: settings.captureInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.processCurrentFrameIfNeeded()
            }
        }
        timer?.fire()
    }

    private func stopFrameTimer() {
        timer?.invalidate()
        timer = nil
        isProcessingFrame = false
    }

    private func processCurrentFrameIfNeeded() async {
        guard prepared, !isProcessingFrame, player.timeControlStatus == .playing, let videoOutput else { return }
        isProcessingFrame = true
        defer { isProcessingFrame = false }

        let itemTime = player.currentTime()
        guard let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else {
            statusText = "Waiting for video frame"
            return
        }

        do {
            let frameImage = try croppedUIImage(from: pixelBuffer)
            let recognizedText = try await recognizer.recognizeCaption(in: frameImage)
            guard !recognizedText.isEmpty else {
                statusText = "No caption text detected"
                return
            }

            lastRecognizedText = recognizedText
            statusText = announcer.isVoiceOverEnabled ? "Caption recognized" : "Caption recognized, VoiceOver is off"

            if shouldAnnounce(recognizedText) {
                lastAnnouncedText = recognizedText
                announcer.speak(recognizedText)
            }
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func croppedUIImage(from pixelBuffer: CVPixelBuffer) throws -> UIImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent.integral
        guard let cgImage = ciContext.createCGImage(ciImage, from: extent) else {
            throw LocalPlaybackError.frameConversionFailed
        }

        let sourceImage = UIImage(cgImage: cgImage)
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let leftInset = width * settings.cropLeftPercent / 100
        let rightInset = width * settings.cropRightPercent / 100
        let topInset = height * settings.cropTopPercent / 100
        let bottomInset = height * settings.cropBottomPercent / 100
        let cropRect = CGRect(
            x: leftInset,
            y: topInset,
            width: max(width - leftInset - rightInset, 1),
            height: max(height - topInset - bottomInset, 1)
        ).integral

        guard let croppedCGImage = sourceImage.cgImage?.cropping(to: cropRect) else {
            throw LocalPlaybackError.frameCropFailed
        }

        return UIImage(cgImage: croppedCGImage)
    }

    private func shouldAnnounce(_ text: String) -> Bool {
        let current = normalized(text)
        let previous = normalized(lastAnnouncedText)

        guard !current.isEmpty else { return false }
        guard !previous.isEmpty else { return true }

        return similarityPercent(between: current, and: previous) < settings.announcementSimilarityPercent
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func similarityPercent(between lhs: String, and rhs: String) -> Double {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)
        let maxLength = max(lhsChars.count, rhsChars.count)
        guard maxLength > 0 else { return 100 }

        var previous = Array(0...rhsChars.count)
        for (lhsIndex, lhsChar) in lhsChars.enumerated() {
            var current = [lhsIndex + 1] + Array(repeating: 0, count: rhsChars.count)
            for (rhsIndex, rhsChar) in rhsChars.enumerated() {
                let cost = lhsChar == rhsChar ? 0 : 1
                current[rhsIndex + 1] = min(
                    previous[rhsIndex + 1] + 1,
                    current[rhsIndex] + 1,
                    previous[rhsIndex] + cost
                )
            }
            previous = current
        }

        let distance = previous[rhsChars.count]
        return (1 - (Double(distance) / Double(maxLength))) * 100
    }
}

private enum LocalPlaybackError: LocalizedError {
    case frameConversionFailed
    case frameCropFailed

    var errorDescription: String? {
        switch self {
        case .frameConversionFailed:
            return "Could not convert the local video frame for OCR."
        case .frameCropFailed:
            return "Could not crop the local video frame for OCR."
        }
    }
}

private extension ToolRunnerBridge {
    static func downloadVideo(
        fromURLString: String,
        outputDirectory: String,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            ToolRunnerBridge.downloadVideo(
                fromURLString,
                outputDirectory: outputDirectory,
                progress: progress
            ) { filePath, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let filePath, !filePath.isEmpty {
                    continuation.resume(returning: filePath)
                } else {
                    continuation.resume(throwing: NSError(
                        domain: "Lectigo.ToolRunnerBridge",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Bundled downloader finished without producing a playable local file."]
                    ))
                }
            }
        }
    }
}
