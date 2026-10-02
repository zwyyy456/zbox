import Foundation
import Observation

@MainActor
@Observable
final class ScreenshotHostingSettings {
    private let defaults: UserDefaults
    private(set) var profiles: [ScreenshotHostingProfile] = []
    private(set) var errorMessage: String?
    var selectedID: UUID? {
        didSet { defaults.set(selectedID?.uuidString, forKey: "plugin.screenshot.hosting.selected") }
    }
    var selected: ScreenshotHostingProfile? { profiles.first { $0.id == selectedID } }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        selectedID = defaults.string(forKey: "plugin.screenshot.hosting.selected").flatMap(UUID.init(uuidString:))
        if let data = defaults.data(forKey: "plugin.screenshot.hosting.profiles") {
            do { profiles = try JSONDecoder().decode([ScreenshotHostingProfile].self, from: data) }
            catch { errorMessage = String(localized: "Stored image host settings could not be read.") }
        }
    }

    func save(_ profile: ScreenshotHostingProfile, credentials: ScreenshotHostCredentials) throws {
        try profile.validate()
        try credentials.validate(for: profile.provider)
        var next = profiles
        if let index = next.firstIndex(where: { $0.id == profile.id }) { next[index] = profile }
        else { next.append(profile) }
        let data = try JSONEncoder().encode(next)
        try ScreenshotCredentialStore.save(credentials, for: profile.id)
        defaults.set(data, forKey: "plugin.screenshot.hosting.profiles")
        profiles = next
        if selectedID == nil { selectedID = profile.id }
        errorMessage = nil
    }

    func delete(_ id: UUID) throws {
        let next = profiles.filter { $0.id != id }
        let data = try JSONEncoder().encode(next)
        try ScreenshotCredentialStore.delete(id)
        defaults.set(data, forKey: "plugin.screenshot.hosting.profiles")
        profiles = next
        if selectedID == id { selectedID = profiles.first?.id }
    }
}
