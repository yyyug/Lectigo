import AVFoundation
import AVKit
import Combine
import CoreImage
import Security
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var webViewStore: WebViewStore
    @StateObject private var sessionStore: BackendSessionStore
    @StateObject private var libraryStore: VideoLibraryStore
    @State private var selectedTab: RootTab = .browse

    init() {
        let sessionStore = BackendSessionStore()
        _webViewStore = StateObject(wrappedValue: WebViewStore())
        _sessionStore = StateObject(wrappedValue: sessionStore)
        _libraryStore = StateObject(wrappedValue: VideoLibraryStore(sessionStore: sessionStore))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            BrowseTabView(
                webViewStore: webViewStore,
                sessionStore: sessionStore,
                libraryStore: libraryStore,
                onOpenLibrary: { selectedTab = .library },
                onOpenSettings: { selectedTab = .settings }
            )
            .tabItem {
                Label("Browse", systemImage: "globe")
            }
            .tag(RootTab.browse)

            LibraryTabView(libraryStore: libraryStore)
            .tabItem {
                Label("Library", systemImage: "square.stack")
            }
            .tag(RootTab.library)

            SettingsTabView(sessionStore: sessionStore)
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
    @ObservedObject var sessionStore: BackendSessionStore
    @ObservedObject var libraryStore: VideoLibraryStore
    let onOpenLibrary: () -> Void
    let onOpenSettings: () -> Void

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
                .disabled(webViewStore.currentURL == nil || sessionStore.isLoggingIn)
            }
            .padding(12)

            if !sessionStore.isAuthenticated {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                    Text("Log in to the backend in Settings before downloading.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Settings") {
                        onOpenSettings()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

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
            if let remoteStatus = item.remoteStatus, !remoteStatus.isEmpty {
                Text("Backend: \(remoteStatus)")
                    .font(.caption2)
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
    @ObservedObject var sessionStore: BackendSessionStore

    @AppStorage("capture.crop.top.percent") private var cropTopPercent = 20.0
    @AppStorage("capture.crop.bottom.percent") private var cropBottomPercent = 0.0
    @AppStorage("capture.crop.left.percent") private var cropLeftPercent = 0.0
    @AppStorage("capture.crop.right.percent") private var cropRightPercent = 0.0
    @AppStorage("capture.interval.seconds") private var captureInterval = 0.5
    @AppStorage("announcement.similarity.percent") private var announcementSimilarityPercent = 80.0
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Backend")
                        .font(.headline)

                    TextField("Backend Base URL", text: $sessionStore.baseURLString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .onChange(of: sessionStore.baseURLString) { newValue in
                            sessionStore.updateBaseURL(newValue)
                        }

                    TextField("Username or Email", text: $sessionStore.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $password)

                    if sessionStore.isAuthenticated {
                        Button("Log Out", role: .destructive) {
                            password = ""
                            sessionStore.logout()
                        }
                    } else {
                        Button(sessionStore.isLoggingIn ? "Logging In..." : "Log In") {
                            let submittedPassword = password
                            Task {
                                await sessionStore.login(password: submittedPassword)
                                if sessionStore.isAuthenticated {
                                    password = ""
                                }
                            }
                        }
                        .disabled(sessionStore.isLoggingIn || sessionStore.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                    }

                    if let authMessage = sessionStore.authMessage {
                        Text(authMessage)
                            .font(.caption)
                            .foregroundStyle(sessionStore.isAuthenticated ? .secondary : .red)
                    }
                }

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
final class BackendSessionStore: ObservableObject {
    @Published var baseURLString: String
    @Published var username: String
    @Published private(set) var isAuthenticated: Bool
    @Published private(set) var isLoggingIn = false
    @Published var authMessage: String?

    private let tokenKey = "lectigo.backend.token"
    private let defaults = UserDefaults.standard
    private var accessToken: String?

    init() {
        self.baseURLString = defaults.string(forKey: "lectigo.backend.baseURL") ?? "https://your-server.example.com"
        self.username = defaults.string(forKey: "lectigo.backend.username") ?? ""
        self.accessToken = KeychainHelper.loadString(forKey: tokenKey)
        self.isAuthenticated = accessToken != nil
        if isAuthenticated, !username.isEmpty {
            self.authMessage = "Logged in as \(username)"
        }
    }

    func updateBaseURL(_ value: String) {
        baseURLString = value
        defaults.set(value, forKey: "lectigo.backend.baseURL")
    }

    func login(password: String) async {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        username = trimmedUsername
        defaults.set(trimmedUsername, forKey: "lectigo.backend.username")
        authMessage = nil
        isLoggingIn = true
        defer { isLoggingIn = false }

        do {
            let endpoint = try url(for: "/auth/login")
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(BackendLoginRequest(usernameOrEmail: trimmedUsername, password: password))

            let (data, response) = try await URLSession.shared.data(for: request)
            try BackendHTTPError.validate(response: response, data: data)
            let decoded = try BackendJSON.decoder.decode(BackendLoginResponse.self, from: data)
            accessToken = decoded.accessToken
            KeychainHelper.saveString(decoded.accessToken, forKey: tokenKey)
            isAuthenticated = true
            authMessage = "Logged in as \(decoded.username)"
        } catch {
            accessToken = nil
            isAuthenticated = false
            KeychainHelper.deleteString(forKey: tokenKey)
            authMessage = error.localizedDescription
        }
    }

    func logout() {
        accessToken = nil
        isAuthenticated = false
        authMessage = "Logged out"
        KeychainHelper.deleteString(forKey: tokenKey)
    }

    func url(for path: String) throws -> URL {
        let baseURL = try normalizedBaseURL()
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw BackendSessionError.invalidBaseURL
        }
        return url
    }

    func resolveDownloadURL(_ value: String) throws -> URL {
        if let absoluteURL = URL(string: value), absoluteURL.scheme != nil {
            return absoluteURL
        }
        return try url(for: value)
    }

    func authorizedRequest(url: URL, method: String = "GET", jsonBody: Data? = nil) throws -> URLRequest {
        guard let accessToken else {
            throw BackendSessionError.notAuthenticated
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        if let jsonBody {
            request.httpBody = jsonBody
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func normalizedBaseURL() throws -> URL {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw BackendSessionError.invalidBaseURL
        }

        let candidate = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"

        guard let url = URL(string: candidate), url.scheme != nil, url.host != nil else {
            throw BackendSessionError.invalidBaseURL
        }
        return url
    }
}

@MainActor
final class VideoLibraryStore: ObservableObject {
    @Published private(set) var items: [VideoLibraryItem] = []
    @Published private(set) var isProcessingQueue = false
    @Published var browserMessage: String?

    private let sessionStore: BackendSessionStore
    private let downloader: BackendVideoDownloadClient
    private var cancellables = Set<AnyCancellable>()

    init(sessionStore: BackendSessionStore) {
        self.sessionStore = sessionStore
        self.downloader = BackendVideoDownloadClient(sessionStore: sessionStore)
        load()
        sessionStore.$isAuthenticated
            .receive(on: RunLoop.main)
            .sink { [weak self] isAuthenticated in
                guard isAuthenticated else { return }
                self?.processQueueIfNeeded()
            }
            .store(in: &cancellables)
        processQueueIfNeeded()
    }

    var activeItems: [VideoLibraryItem] {
        items.filter { $0.status != .downloaded }
    }

    var downloadedItems: [VideoLibraryItem] {
        items.filter { $0.status == .downloaded }
    }

    func enqueueDownload(from url: URL) {
        guard sessionStore.isAuthenticated else {
            browserMessage = "Log in to the backend before downloading."
            return
        }

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
            thumbnailRelativePath: nil,
            backendJobID: nil,
            remoteStatus: nil,
            remoteDownloadURLString: nil,
            remoteFileID: nil,
            expiresAt: nil
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
        guard sessionStore.isAuthenticated else { return }
        guard let nextItem = items.first(where: {
            switch $0.status {
            case .queued, .requestingRemote, .downloadingRemote, .processing, .readyToFetch, .downloadingFile:
                return true
            case .downloaded, .failed, .expired:
                return false
            }
        }) else { return }

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

        items[index].status = .requestingRemote
        items[index].progressText = "Submitting URL to backend"
        items[index].errorText = nil
        persist()

        let destinationDirectory = VideoLibraryPaths.directoryForItem(id: itemID)
        do {
            let result = try await downloader.downloadVideo(
                from: sourceURL,
                itemID: itemID,
                destinationDirectory: destinationDirectory,
                progress: { update in
                    await MainActor.run {
                        self.applyProgress(update, for: itemID)
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
                if let backendError = error as? BackendVideoDownloadClient.Error, case .expired = backendError {
                    items[itemIndex].status = .expired
                } else {
                    items[itemIndex].status = .failed
                }
                items[itemIndex].progressText = "Download failed"
                items[itemIndex].errorText = error.localizedDescription
            }
            browserMessage = error.localizedDescription
            persist()
        }

        isProcessingQueue = false
        processQueueIfNeeded()
    }

    private func applyProgress(_ update: BackendDownloadProgress, for itemID: UUID) {
        guard let itemIndex = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[itemIndex].status = update.localStatus
        items[itemIndex].progressText = update.progressText
        if let title = update.title, !title.isEmpty {
            items[itemIndex].title = title
        }
        items[itemIndex].backendJobID = update.backendJobID ?? items[itemIndex].backendJobID
        items[itemIndex].remoteStatus = update.remoteStatus ?? items[itemIndex].remoteStatus
        items[itemIndex].remoteDownloadURLString = update.remoteDownloadURLString ?? items[itemIndex].remoteDownloadURLString
        items[itemIndex].remoteFileID = update.remoteFileID ?? items[itemIndex].remoteFileID
        items[itemIndex].expiresAt = update.expiresAt ?? items[itemIndex].expiresAt
        items[itemIndex].durationSeconds = update.durationSeconds ?? items[itemIndex].durationSeconds
        persist()
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
    var backendJobID: String?
    var remoteStatus: String?
    var remoteDownloadURLString: String?
    var remoteFileID: String?
    var expiresAt: Date?

    enum Status: String, Codable {
        case queued
        case requestingRemote
        case downloadingRemote
        case processing
        case readyToFetch
        case downloadingFile
        case downloaded
        case failed
        case expired
    }

    var displayTitle: String {
        title.isEmpty ? "Untitled Video" : title
    }

    var statusLabel: String {
        switch status {
        case .queued:
            return "Queued"
        case .requestingRemote:
            return "Submitting to Backend"
        case .downloadingRemote:
            return "Backend Downloading"
        case .processing:
            return "Backend Processing"
        case .readyToFetch:
            return "Ready to Fetch"
        case .downloadingFile:
            return "Downloading File"
        case .downloaded:
            return "Downloaded"
        case .failed:
            return "Failed"
        case .expired:
            return "Expired"
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

private struct BackendDownloadProgress {
    let localStatus: VideoLibraryItem.Status
    let progressText: String
    let title: String?
    let backendJobID: String?
    let remoteStatus: String?
    let remoteDownloadURLString: String?
    let remoteFileID: String?
    let expiresAt: Date?
    let durationSeconds: Double?
}

private final class BackendVideoDownloadClient {
    enum Error: LocalizedError {
        case failed(String)
        case expired
        case missingDownloadURL

        var errorDescription: String? {
            switch self {
            case .failed(let message):
                return message
            case .expired:
                return "The backend download expired before the app fetched the MP4."
            case .missingDownloadURL:
                return "The backend marked the job ready but did not provide a file download URL."
            }
        }
    }

    private let sessionStore: BackendSessionStore
    private let fileDownloader = BackendFileDownloader()

    init(sessionStore: BackendSessionStore) {
        self.sessionStore = sessionStore
    }

    func downloadVideo(
        from sourceURL: URL,
        itemID: UUID,
        destinationDirectory: URL,
        progress: @escaping (BackendDownloadProgress) async -> Void
    ) async throws -> DownloadedVideoResult {
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        await progress(BackendDownloadProgress(
            localStatus: .requestingRemote,
            progressText: "Submitting URL to backend",
            title: nil,
            backendJobID: nil,
            remoteStatus: "queued",
            remoteDownloadURLString: nil,
            remoteFileID: nil,
            expiresAt: nil,
            durationSeconds: nil
        ))

        let createdJob = try await createRemoteJob(sourceURL: sourceURL)
        var lastKnownTitle: String?
        while true {
            let jobStatus = try await fetchRemoteJob(jobID: createdJob.jobID)
            lastKnownTitle = jobStatus.title ?? lastKnownTitle

            let localStatus: VideoLibraryItem.Status
            switch jobStatus.status {
            case .queued:
                localStatus = .requestingRemote
            case .downloading:
                localStatus = .downloadingRemote
            case .processing:
                localStatus = .processing
            case .ready:
                localStatus = .readyToFetch
            case .failed:
                localStatus = .failed
            case .expired:
                localStatus = .expired
            }

            await progress(BackendDownloadProgress(
                localStatus: localStatus,
                progressText: jobStatus.progressText ?? localProgressText(for: jobStatus.status),
                title: jobStatus.title,
                backendJobID: createdJob.jobID,
                remoteStatus: jobStatus.status.rawValue,
                remoteDownloadURLString: jobStatus.downloadURL,
                remoteFileID: jobStatus.fileID,
                expiresAt: jobStatus.expiresAt,
                durationSeconds: jobStatus.durationSeconds
            ))

            switch jobStatus.status {
            case .queued, .downloading, .processing:
                try await Task.sleep(for: .seconds(2))
            case .failed:
                throw Error.failed(jobStatus.errorMessage ?? "The backend download job failed.")
            case .expired:
                throw Error.expired
            case .ready:
                guard let downloadURLString = jobStatus.downloadURL else {
                    throw Error.missingDownloadURL
                }
                let downloadURL = try await sessionStore.resolveDownloadURL(downloadURLString)
                let request = try await sessionStore.authorizedRequest(url: downloadURL)
                let fileName = sanitizedFileName(
                    from: jobStatus.fileName ?? lastKnownTitle ?? "\(itemID.uuidString).mp4",
                    preferredExtension: "mp4"
                )
                let localURL = try await fileDownloader.download(
                    request: request,
                    to: destinationDirectory,
                    preferredFileName: fileName,
                    progress: { fraction in
                        let percent = Int((fraction * 100).rounded())
                        await progress(BackendDownloadProgress(
                            localStatus: .downloadingFile,
                            progressText: "Downloading file \(percent)%",
                            title: jobStatus.title ?? lastKnownTitle,
                            backendJobID: createdJob.jobID,
                            remoteStatus: jobStatus.status.rawValue,
                            remoteDownloadURLString: jobStatus.downloadURL,
                            remoteFileID: jobStatus.fileID,
                            expiresAt: jobStatus.expiresAt,
                            durationSeconds: jobStatus.durationSeconds
                        ))
                    }
                )
                let duration = try await loadDuration(for: localURL)
                return DownloadedVideoResult(
                    fileURL: localURL,
                    title: (jobStatus.title ?? lastKnownTitle ?? localURL.deletingPathExtension().lastPathComponent).trimmingCharacters(in: .whitespacesAndNewlines),
                    durationSeconds: duration ?? jobStatus.durationSeconds
                )
            }
        }
    }

    private func createRemoteJob(sourceURL: URL) async throws -> BackendCreateDownloadResponse {
        let endpoint = try await sessionStore.url(for: "/downloads")
        let body = try JSONEncoder().encode(BackendCreateDownloadRequest(sourceURL: sourceURL.absoluteString))
        let request = try await sessionStore.authorizedRequest(url: endpoint, method: "POST", jsonBody: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try BackendHTTPError.validate(response: response, data: data)
        return try BackendJSON.decoder.decode(BackendCreateDownloadResponse.self, from: data)
    }

    private func fetchRemoteJob(jobID: String) async throws -> BackendJobStatusResponse {
        let endpoint = try await sessionStore.url(for: "/downloads/\(jobID)")
        let request = try await sessionStore.authorizedRequest(url: endpoint)
        let (data, response) = try await URLSession.shared.data(for: request)
        try BackendHTTPError.validate(response: response, data: data)
        return try BackendJSON.decoder.decode(BackendJobStatusResponse.self, from: data)
    }

    private func loadDuration(for fileURL: URL) async throws -> Double? {
        let asset = AVURLAsset(url: fileURL)
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? seconds : nil
    }

    private func sanitizedFileName(from rawValue: String, preferredExtension: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = rawValue.components(separatedBy: invalidCharacters).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? UUID().uuidString : trimmed
        if baseName.lowercased().hasSuffix(".\(preferredExtension.lowercased())") {
            return baseName
        }
        return "\(baseName).\(preferredExtension)"
    }

    private func localProgressText(for status: BackendRemoteJobStatus) -> String {
        switch status {
        case .queued:
            return "Queued on backend"
        case .downloading:
            return "Backend downloading source media"
        case .processing:
            return "Backend merging and preparing MP4"
        case .ready:
            return "Backend file ready"
        case .failed:
            return "Backend failed"
        case .expired:
            return "Backend file expired"
        }
    }
}

private final class BackendFileDownloader {
    func download(
        request: URLRequest,
        to directory: URL,
        preferredFileName: String,
        progress: @escaping (Double) async -> Void
    ) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporaryURL = directory.appendingPathComponent("partial-\(UUID().uuidString).tmp")
        let destinationURL = directory.appendingPathComponent(preferredFileName)
        try? FileManager.default.removeItem(at: temporaryURL)
        try? FileManager.default.removeItem(at: destinationURL)
        FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        try BackendHTTPError.validate(response: response, data: nil)

        let expectedLength = max(response.expectedContentLength, 0)
        let fileHandle = try FileHandle(forWritingTo: temporaryURL)
        var buffer = Data()
        var receivedBytes: Int64 = 0

        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 64 * 1024 {
                    try fileHandle.write(contentsOf: buffer)
                    receivedBytes += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    if expectedLength > 0 {
                        await progress(min(Double(receivedBytes) / Double(expectedLength), 1))
                    }
                }
            }

            if !buffer.isEmpty {
                try fileHandle.write(contentsOf: buffer)
                receivedBytes += Int64(buffer.count)
            }
            try fileHandle.close()
        } catch {
            try? fileHandle.close()
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }

        if expectedLength > 0 {
            await progress(min(Double(receivedBytes) / Double(expectedLength), 1))
        } else {
            await progress(1)
        }

        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        return destinationURL
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

private struct BackendLoginRequest: Encodable {
    let usernameOrEmail: String
    let password: String
}

private struct BackendLoginResponse: Decodable {
    let accessToken: String
    let username: String
}

private struct BackendCreateDownloadRequest: Encodable {
    let sourceURL: String
}

private struct BackendCreateDownloadResponse: Decodable {
    let jobID: String
    let status: String
}

private struct BackendJobStatusResponse: Decodable {
    let jobID: String
    let status: BackendRemoteJobStatus
    let title: String?
    let progressText: String?
    let durationSeconds: Double?
    let errorMessage: String?
    let downloadURL: String?
    let expiresAt: Date?
    let fileID: String?
    let fileName: String?
}

private enum BackendRemoteJobStatus: String, Decodable {
    case queued
    case downloading
    case processing
    case ready
    case failed
    case expired
}

private enum BackendJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private enum BackendSessionError: LocalizedError {
    case invalidBaseURL
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Enter a valid backend base URL in Settings first."
        case .notAuthenticated:
            return "Log in to the backend before downloading."
        }
    }
}

private enum BackendHTTPError: LocalizedError {
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let message):
            return message
        }
    }

    static func validate(response: URLResponse, data: Data?) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw requestFailed("The backend returned an invalid response.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let data,
               let object = try? JSONSerialization.jsonObject(with: data),
               let jsonObject = object as? [String: Any],
               let detail = jsonObject["detail"] as? String,
               !detail.isEmpty {
                throw requestFailed(detail)
            }
            if let data, let message = String(data: data, encoding: .utf8), !message.isEmpty {
                throw requestFailed(message)
            }
            throw requestFailed("The backend request failed with status \(httpResponse.statusCode).")
        }
    }
}

private enum KeychainHelper {
    static func saveString(_ value: String, forKey key: String) {
        let encoded = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: encoded
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func loadString(forKey key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    static func deleteString(forKey key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
