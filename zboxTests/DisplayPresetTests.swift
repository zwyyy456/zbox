import Foundation
import Testing
@testable import zbox

@MainActor
struct DisplayPresetTests {
    @Test func persistsExactModesAndKeepsCommandIdentityWhenRenamed() throws {
        let suite = "DisplayPresetTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DisplayPresetStore(defaults: defaults)
        let mode = DisplayModeSpec(width: 1920, height: 1080, pixelWidth: 3840, pixelHeight: 2160, refreshMillihertz: 59940)
        var preset = DisplayPreset(name: "Work", selections: [DisplaySelection(displayID: "screen", displayName: "Screen", mode: mode)])
        let id = preset.commandID
        try store.save(preset)
        preset.name = "Read"
        try store.save(preset)
        let loaded = DisplayPresetStore(defaults: defaults)
        #expect(loaded.presets == [preset])
        #expect(loaded.presets[0].commandID == id)
        try loaded.delete(preset.id)
        #expect(DisplayPresetStore(defaults: defaults).presets.isEmpty)
    }
}
