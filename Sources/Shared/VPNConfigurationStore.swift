import Foundation

enum VPNConfigurationStore {
    private static var rootURL: URL { AppGroup.xrayDataURL }

    private static var profilesURL: URL {
        rootURL.appendingPathComponent("profiles.json")
    }

    private static var preferencesURL: URL {
        rootURL.appendingPathComponent("preferences.json")
    }

    static func loadProfiles() -> [VPNProfile] {
        let decoder = JSONDecoder()
        guard let data = try? Data(contentsOf: profilesURL),
              let profiles = try? decoder.decode([VPNProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    static func saveProfiles(_ profiles: [VPNProfile]) throws {
        try ensureRoot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profiles)
        try data.write(to: profilesURL, options: .atomic)
    }

    static func loadPreferences() -> VPNPreferences {
        let decoder = JSONDecoder()
        guard let data = try? Data(contentsOf: preferencesURL),
              let preferences = try? decoder.decode(VPNPreferences.self, from: data) else {
            return VPNPreferences()
        }
        return preferences
    }

    static func savePreferences(_ preferences: VPNPreferences) throws {
        try ensureRoot()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences)
        try data.write(to: preferencesURL, options: .atomic)
    }

    static func activeProfile(preferences: VPNPreferences, profiles: [VPNProfile]) -> VPNProfile? {
        guard let id = preferences.activeProfileID else { return nil }
        return profiles.first { $0.id == id }
    }

    static func reset() throws {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: profilesURL)
        try? fileManager.removeItem(at: preferencesURL)
    }

    private static func ensureRoot() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }
}
