import XCTest
@testable import MacZones

final class ProfileMergeTests: XCTestCase {
    private func zone(_ x: Double) -> Zone {
        Zone(x: x, y: 0, width: 0.5, height: 1)
    }

    /// The core data-loss bug: editing while a monitor is disconnected must NOT
    /// wipe that monitor's stored zones.
    func testMergePreservesDisconnectedScreenZones() {
        var profile = Profile(name: "Standard", screens: [
            "laptop": [zone(0)],
            "external": [zone(0.5)],
        ])

        // Editor session only saw "laptop" (external was unplugged), and the
        // user retiled it.
        profile.mergeScreens(["laptop": [zone(0), zone(0.5)]])

        XCTAssertEqual(profile.screens["laptop"]?.count, 2, "edited screen is updated")
        XCTAssertEqual(profile.screens["external"]?.count, 1, "disconnected screen is preserved")
    }

    /// A connected screen that the user explicitly cleared (empty array) is
    /// removed — that's a deliberate edit, not data loss.
    func testMergeEmptyClearsConnectedScreen() {
        var profile = Profile(name: "Standard", screens: [
            "laptop": [zone(0)],
            "external": [zone(0.5)],
        ])

        profile.mergeScreens(["laptop": []])

        XCTAssertNil(profile.screens["laptop"], "explicitly cleared screen is removed")
        XCTAssertEqual(profile.screens["external"]?.count, 1, "untouched screen is preserved")
    }

    /// A newly connected screen with zones is added.
    func testMergeAddsNewScreen() {
        var profile = Profile(name: "Standard", screens: ["laptop": [zone(0)]])

        profile.mergeScreens(["external": [zone(0.5)]])

        XCTAssertEqual(profile.screens["laptop"]?.count, 1)
        XCTAssertEqual(profile.screens["external"]?.count, 1)
    }
}
