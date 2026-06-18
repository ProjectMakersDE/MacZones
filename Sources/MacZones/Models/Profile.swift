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
}
