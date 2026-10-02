import SwiftUI

struct ScreenshotHostingView: View {
    @Bindable var settings: ScreenshotHostingSettings
    let plugin: ScreenshotPlugin
    @State private var editing: ScreenshotHostingProfile?
    @State private var errorMessage: String?
    @State private var confirmsDelete = false

    var body: some View {
        Section("Image Hosting") {
            Picker("Default Host", selection: $settings.selectedID) {
                Text("None").tag(nil as UUID?)
                ForEach(settings.profiles) { Text($0.name).tag(Optional($0.id)) }
            }
            HStack {
                Button("Add Host…") { editing = ScreenshotHostingProfile() }
                Button("Edit…") { editing = settings.selected }.disabled(settings.selected == nil)
                Button("Remove", role: .destructive) { confirmsDelete = true }.disabled(settings.selected == nil)
            }
            Button("Upload Test Image", action: plugin.uploadTestImage)
                .disabled(settings.selected == nil || plugin.isUploading || plugin.isExporting)
            Text("The test uploads a generated image to the selected host. It does not capture your screen. Public access must be configured at the host.")
                .font(.caption).foregroundStyle(.secondary)
            if plugin.isUploading {
                ProgressView(value: plugin.uploadProgress)
                Button("Cancel Upload", action: plugin.cancelUpload)
            }
            if plugin.uploadedURL != nil { Button("Copy Link", action: plugin.copyUploadedLink) }
            if let error = errorMessage ?? settings.errorMessage { Text(error).foregroundStyle(.red) }
        }
        .sheet(item: $editing) { profile in ScreenshotHostEditor(settings: settings, initial: profile) }
        .confirmationDialog("Remove this image host and its saved credentials?", isPresented: $confirmsDelete) {
            Button("Remove", role: .destructive) {
                guard let id = settings.selectedID else { return }
                do { try settings.delete(id); errorMessage = nil }
                catch { errorMessage = ScreenshotUploadError.keychain.localizedDescription }
            }
        }
    }
}

private struct ScreenshotHostEditor: View {
    let settings: ScreenshotHostingSettings
    @State private var profile: ScreenshotHostingProfile
    @State private var credentials = ScreenshotHostCredentials()
    @State private var errorMessage: String?
    @State private var credentialsLoaded = false
    @Environment(\.dismiss) private var dismiss

    init(settings: ScreenshotHostingSettings, initial: ScreenshotHostingProfile) {
        self.settings = settings
        _profile = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $profile.name)
                Picker("Provider", selection: $profile.provider) {
                    ForEach(ScreenshotHost.allCases) { Text($0.title).tag($0) }
                }.disabled(settings.profiles.contains(where: { $0.id == profile.id }))
                if profile.provider == .smms {
                    Text("SM.MS uploads have moved to S.EE. Enter a S.EE API key; the old SM.MS upload endpoint is no longer used.")
                        .font(.caption).foregroundStyle(.secondary)
                    SecureField("S.EE API Key", text: $credentials.secretKey)
                } else {
                    TextField(profile.provider == .upyun ? "Service Name" : "Bucket", text: $profile.bucket)
                    if profile.provider.needsRegion {
                        TextField("Region", text: $profile.region)
                        Text(regionHint).font(.caption).foregroundStyle(.secondary)
                    }
                    if profile.provider.needsEndpoint {
                        TextField("Upload Endpoint (HTTPS)", text: $profile.endpoint)
                        Text(profile.provider == .r2 ? "https://<account-id>.r2.cloudflarestorage.com" : "https://upload.qiniup.com")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("Public Base URL (HTTPS)", text: $profile.publicBaseURL)
                    Text("Use the bucket's public URL or a CDN domain, without the object path. zbox does not change bucket permissions or generate expiring links.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Object Path Prefix", text: $profile.prefix)
                    TextField(profile.provider == .upyun ? "Operator" : "Access Key / Secret ID", text: $credentials.accessKey)
                    SecureField(profile.provider == .upyun ? "Operator Password" : "Secret Key", text: $credentials.secretKey)
                    if [.r2, .s3, .oss, .cos].contains(profile.provider) {
                        SecureField("Session Token (optional)", text: $credentials.sessionToken)
                    }
                }
                Text("Credentials are stored in Keychain on this Mac.").font(.caption).foregroundStyle(.secondary)
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }.formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    do { try settings.save(profile, credentials: credentials); dismiss() }
                    catch { errorMessage = (error as? ScreenshotUploadError)?.localizedDescription ?? ScreenshotUploadError.keychain.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(!credentialsLoaded)
            }.padding()
        }.frame(width: 560, height: 610)
        .onAppear {
            do { credentials = try ScreenshotCredentialStore.load(profile.id); credentialsLoaded = true }
            catch { errorMessage = ScreenshotUploadError.keychain.localizedDescription }
        }
        .onChange(of: profile.provider) { _, _ in
            credentials = ScreenshotHostCredentials()
            profile.bucket = ""; profile.region = ""; profile.endpoint = ""; profile.publicBaseURL = ""
        }
    }

    private var regionHint: String {
        switch profile.provider {
        case .s3: "us-east-1"
        case .oss: "cn-hangzhou"
        case .cos: "ap-guangzhou"
        default: ""
        }
    }
}
