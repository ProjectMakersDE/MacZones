import Foundation
import CoreGraphics

/// Detects a deliberate "shake" gesture from a stream of drag positions:
/// several quick horizontal direction reversals within a short time window.
/// Pure arithmetic, no allocation per event of note — cheap to run on every
/// drag event.
final class ShakeDetector {
    private var lastX: CGFloat?
    private var lastDirection: Int = 0          // -1, 0, +1
    private var reversalTimes: [TimeInterval] = []

    // Tuning
    private let minStep: CGFloat = 6            // ignore tiny jitter (points)
    private let window: TimeInterval = 0.6      // reversals must happen within this
    private let requiredReversals = 3           // this many = a shake
    private let cooldown: TimeInterval = 0.8    // don't retrigger immediately
    private var lastTrigger: TimeInterval = 0

    func reset() {
        lastX = nil
        lastDirection = 0
        reversalTimes.removeAll(keepingCapacity: true)
    }

    /// Feed a new cursor position. Returns true once when a shake is recognised.
    func feed(x: CGFloat, time: TimeInterval) -> Bool {
        defer { lastX = x }
        guard let prev = lastX else { return false }

        let dx = x - prev
        guard abs(dx) >= minStep else { return false }

        let dir = dx > 0 ? 1 : -1
        if lastDirection != 0 && dir != lastDirection {
            reversalTimes.append(time)
            reversalTimes.removeAll { time - $0 > window }

            if reversalTimes.count >= requiredReversals, time - lastTrigger > cooldown {
                lastTrigger = time
                reversalTimes.removeAll(keepingCapacity: true)
                lastDirection = dir
                return true
            }
        }
        lastDirection = dir
        return false
    }
}
