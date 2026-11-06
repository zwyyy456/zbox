import AppKit
import Observation

@MainActor @Observable
final class ScreenshotUploadSession {
    private let hosting: ScreenshotHostingSettings
    private let clipboardCoordinator: ClipboardAccessCoordinator
    @ObservationIgnored private let status: (String?) -> Void
    @ObservationIgnored private let changed: () -> Void
    @ObservationIgnored private let completed: () -> Void
    private var statusMessage: String? { didSet { status(statusMessage) } }
    init(hosting: ScreenshotHostingSettings, coordinator: ClipboardAccessCoordinator,
         status: @escaping (String?) -> Void, changed: @escaping () -> Void,
         completed: @escaping () -> Void) {
        self.hosting = hosting
        clipboardCoordinator = coordinator
        self.status = status
        self.changed = changed
        self.completed = completed
    }
    private var uploadTask: Task<Void, Never>?
    private var uploadID: UUID?
    private var closesAfterUpload = false
    private var pendingUpload: ScreenshotUploadSnapshot?
    var canRetryUpload: Bool { pendingUpload != nil && !isUploading }
    private(set) var isUploading = false {
        didSet { changed() }
    }
    private(set) var uploadProgress = 0.0
    private(set) var uploadedURL: URL?
    private(set) var uploadHostName = ""

    func discardUpload() {
        cancelUpload()
        closesAfterUpload = false
        uploadedURL = nil
        pendingUpload = nil
    }

    func cancelUpload() {
        if isUploading { statusMessage = String(localized: "Upload cancelled. The host may already have received the image.") }
        uploadID = nil
        uploadTask?.cancel()
        uploadTask = nil
        isUploading = false
        uploadProgress = 0
    }

    func copyUploadedLink() {
        guard let uploadedURL else { return }
        if ScreenshotClipboard.copyLink(uploadedURL, format: hosting.linkFormat, to: .general, coordinator: clipboardCoordinator) {
            statusMessage = String(localized: "Link copied.")
            if closesAfterUpload { completed() }
        }
    }

    func retryUpload() {
        guard let snapshot = pendingUpload, !isUploading else { return }
        guard hosting.profiles.contains(snapshot.profile) else {
            statusMessage = String(localized: "The host configuration changed. Start a new upload to use the new settings.")
            return
        }
        do {
            let credentials = try ScreenshotCredentialStore.load(snapshot.profile.id)
            try credentials.validate(for: snapshot.profile.provider)
            let id = startUploadState(hostName: snapshot.profile.name)
            let clipboardCount = snapshot.copiesLink ? NSPasteboard.general.changeCount : nil
            uploadTask = Task { [weak self] in
                do { try await self?.send(snapshot, credentials: credentials, id: id, clipboardCount: clipboardCount) }
                catch { self?.handleUploadError(error, id: id) }
            }
        } catch { statusMessage = (error as? ScreenshotUploadError)?.localizedDescription ?? ScreenshotUploadError.keychain.localizedDescription }
    }

    func beginUpload(quality: Double, image: CGImage, edit: ScreenshotEdit, format: ScreenshotFormat, copiesLink: Bool, closesEditor: Bool = false) {
        guard let profile = hosting.selected else {
            statusMessage = String(localized: "Choose an image host in Screenshot settings first.")
            return
        }
        let credentials: ScreenshotHostCredentials
        do {
            try profile.validate()
            credentials = try ScreenshotCredentialStore.load(profile.id)
            try credentials.validate(for: profile.provider)
        } catch {
            statusMessage = (error as? ScreenshotUploadError)?.localizedDescription ?? ScreenshotUploadError.keychain.localizedDescription
            return
        }
        let id = startUploadState(hostName: profile.name)
        closesAfterUpload = closesEditor
        pendingUpload = nil
        let clipboardCount = copiesLink ? NSPasteboard.general.changeCount : nil
        let filename = "Screenshot-" + id.uuidString.lowercased() + "." + format.rawValue
        uploadTask = Task { [weak self] in
            do {
                let data = try await ScreenshotRenderer.export(image: image, edit: edit, format: format, quality: quality)
                try Task.checkCancellation()
                guard let self, uploadID == id else { return }
                let snapshot = ScreenshotUploadSnapshot(profile: profile, image: data, format: format,
                    filename: filename, copiesLink: copiesLink)
                pendingUpload = snapshot
                try await send(snapshot, credentials: credentials, id: id, clipboardCount: clipboardCount)
            } catch { self?.handleUploadError(error, id: id) }
        }
    }

    private func startUploadState(hostName: String) -> UUID {
        let id = UUID()
        uploadID = id
        isUploading = true
        uploadProgress = 0
        uploadHostName = hostName
        uploadedURL = nil
        statusMessage = nil
        return id
    }

    private func send(_ snapshot: ScreenshotUploadSnapshot, credentials: ScreenshotHostCredentials, id: UUID, clipboardCount: Int?) async throws {
        let linkFormat = hosting.linkFormat
        let url = try await ScreenshotUploader.upload(profile: snapshot.profile, credentials: credentials,
            image: snapshot.image, format: snapshot.format, filename: snapshot.filename) { [weak self] value in
                Task { @MainActor [weak self] in
                    guard self?.uploadID == id else { return }
                    self?.uploadProgress = value
                }
            }
        try Task.checkCancellation()
        guard uploadID == id else { return }
        uploadedURL = url
        isUploading = false
        uploadID = nil
        uploadTask = nil
        pendingUpload = nil
        statusMessage = String(localized: "Upload complete. The link is ready to copy.")
        if let clipboardCount {
            if ScreenshotClipboard.copyLink(url, format: linkFormat, to: .general,
                    coordinator: clipboardCoordinator, ifUnchangedSince: clipboardCount) {
                statusMessage = String(localized: "Upload complete. Link copied.")
                if closesAfterUpload { completed() }
            } else {
                statusMessage = String(localized: "Upload complete. Your clipboard changed, so the link was not copied. Use Copy Link when ready.")
            }
        }
    }

    private func handleUploadError(_ error: Error, id: UUID) {
        guard !Task.isCancelled, uploadID == id else { return }
        isUploading = false
        uploadID = nil
        uploadTask = nil
        statusMessage = (error as? ScreenshotUploadError)?.localizedDescription
            ?? (error as? ScreenshotError)?.localizedDescription ?? ScreenshotUploadError.network.localizedDescription
    }

}
