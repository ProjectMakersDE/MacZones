import Foundation

/// Persists profiles + a couple of toggles to
/// ~/Library/Application Support/MacZones/profiles.json
final class ProfileStore {
    static let shared = ProfileStore()

    static let didChange = Notification.Name("MacZonesProfileStoreDidChange")

    private struct StoreData: Codable {
        var profiles: [Profile]
        var currentName: String
        var rightClickDragEnabled: Bool
        var shakeEnabled: Bool
        var seededScreens: [String]?      // optional for backward compatibility
        var autoCheckUpdates: Bool?       // optional for backward compatibility
    }

    private(set) var profiles: [Profile]
    private(set) var currentName: String
    private var seededScreens: Set<String>
    var rightClickDragEnabled: Bool { didSet { save() } }
    var shakeEnabled: Bool { didSet { save() } }
    var autoCheckUpdates: Bool { didSet { save() } }

    private init() {
        if let data = ProfileStore.load() {
            profiles = data.profiles.isEmpty ? [Profile(name: "Standard")] : data.profiles
            currentName = data.currentName
            rightClickDragEnabled = data.rightClickDragEnabled
            shakeEnabled = data.shakeEnabled
            seededScreens = Set(data.seededScreens ?? [])
            autoCheckUpdates = data.autoCheckUpdates ?? true
        } else {
            profiles = [Profile(name: "Standard")]
            currentName = "Standard"
            rightClickDragEnabled = true
            shakeEnabled = true
            seededScreens = []
            autoCheckUpdates = true
        }
        if !profiles.contains(where: { $0.name == currentName }) {
            currentName = profiles.first?.name ?? "Standard"
        }
    }

    /// Seed each given screen with a default grid the first time we encounter
    /// it, so zones appear out of the box. A screen the user later clears stays
    /// empty (it won't be re-seeded).
    func seedDefaultsIfNeeded(_ specs: [(key: String, columns: Int, rows: Int)]) {
        guard let idx = profiles.firstIndex(where: { $0.name == currentName }) else { return }
        var changed = false
        for spec in specs where !seededScreens.contains(spec.key) {
            if (profiles[idx].screens[spec.key] ?? []).isEmpty {
                profiles[idx].screens[spec.key] = Grid.zones(columns: spec.columns, rows: spec.rows)
            }
            seededScreens.insert(spec.key)
            changed = true
        }
        if changed { save() }
    }

    // MARK: Current profile access

    var current: Profile {
        profiles.first(where: { $0.name == currentName }) ?? profiles[0]
    }

    func zones(forScreen key: String) -> [Zone] {
        current.screens[key] ?? []
    }

    func setZones(_ zones: [Zone], forScreen key: String) {
        guard let idx = profiles.firstIndex(where: { $0.name == currentName }) else { return }
        if zones.isEmpty {
            profiles[idx].screens.removeValue(forKey: key)
        } else {
            profiles[idx].screens[key] = zones
        }
        save()
    }

    /// Merge the edited screens into the current profile (used by the editor on
    /// save). Only the screens the editor actually worked on — the ones
    /// connected during editing — are touched; zones for monitors that weren't
    /// connected at that moment are preserved instead of being wiped.
    func mergeScreens(_ screens: [String: [Zone]]) {
        guard let idx = profiles.firstIndex(where: { $0.name == currentName }) else { return }
        profiles[idx].mergeScreens(screens)
        save()
    }

    // MARK: Profile management

    func selectProfile(named name: String) {
        guard profiles.contains(where: { $0.name == name }) else { return }
        currentName = name
        save()
    }

    @discardableResult
    func addProfile(named name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !profiles.contains(where: { $0.name == trimmed }) else { return false }
        profiles.append(Profile(name: trimmed))
        currentName = trimmed
        save()
        return true
    }

    func deleteProfile(named name: String) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.name == name }
        if currentName == name { currentName = profiles.first?.name ?? "Standard" }
        save()
    }

    func renameProfile(from old: String, to new: String) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let idx = profiles.firstIndex(where: { $0.name == old }),
              !profiles.contains(where: { $0.name == trimmed }) else { return }
        profiles[idx].name = trimmed
        if currentName == old { currentName = trimmed }
        save()
    }

    // MARK: Persistence

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MacZones", isDirectory: true)
            .appendingPathComponent("profiles.json")
    }

    private static func load() -> StoreData? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(StoreData.self, from: data)
    }

    func save() {
        let data = StoreData(profiles: profiles,
                             currentName: currentName,
                             rightClickDragEnabled: rightClickDragEnabled,
                             shakeEnabled: shakeEnabled,
                             seededScreens: Array(seededScreens),
                             autoCheckUpdates: autoCheckUpdates)
        let url = ProfileStore.fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: url, options: .atomic)
        }
        NotificationCenter.default.post(name: ProfileStore.didChange, object: nil)
    }
}
