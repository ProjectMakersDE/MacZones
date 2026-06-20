import Foundation

/// A named layout. Zones are stored per screen (keyed by a stable display id),
/// so one profile can describe different layouts for each monitor.
struct Profile: Codable, Equatable {
    var name: String
    /// screenKey -> zones
    var screens: [String: [Zone]]

    init(name: String, screens: [String: [Zone]] = [:]) {
        self.name = name
        self.screens = screens
    }

    /// Merge edited per-screen zones into this profile. Keys present in `edited`
    /// are updated (an empty array clears that screen); keys *absent* from
    /// `edited` — e.g. monitors that weren't connected during the edit — are
    /// left untouched so their zones are never lost.
    mutating func mergeScreens(_ edited: [String: [Zone]]) {
        for (key, zones) in edited {
            if zones.isEmpty {
                screens.removeValue(forKey: key)
            } else {
                screens[key] = zones
            }
        }
    }
}
