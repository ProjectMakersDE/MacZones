import Foundation

/// What a right-button release means while a left-drag snap session is (or was)
/// showing zones. Pure decision logic so it can be unit-tested without a display.
enum RightReleaseOutcome: Equatable {
    case dismiss        // turn zones off, no snap
    case singleFollow   // keep zones on; single zone under the cursor follows
    case freezeMulti    // keep zones on; freeze the multi-zone union as the selection
}

/// Classify a right-button press→release that happened during a left-drag.
///
/// - Parameters:
///   - holdDuration: seconds the right button was held.
///   - didExpand: true if, while held, the cursor reached a zone other than the anchor.
///   - zonesWereOnBeforePress: true if zones were already visible when the right button went down.
///   - tapMax: maximum duration that still counts as a "tap" (default 0.25s).
func classifyRightRelease(holdDuration: TimeInterval,
                          didExpand: Bool,
                          zonesWereOnBeforePress: Bool,
                          tapMax: TimeInterval = 0.25) -> RightReleaseOutcome {
    let isTap = holdDuration < tapMax && !didExpand
    if isTap && zonesWereOnBeforePress { return .dismiss }
    if didExpand { return .freezeMulti }
    return .singleFollow
}
