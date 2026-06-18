import Foundation

/// A single snap zone, stored in normalised coordinates relative to a screen's
/// *visible* frame, with a top-left origin (x→right, y→down). Normalised so the
/// same layout adapts to any resolution / scaling.
struct Zone: Codable, Identifiable, Equatable {
    var id: UUID
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(id: UUID = UUID(), x: Double, y: Double, width: Double, height: Double) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Clamp into [0,1] and enforce a sensible minimum size.
    mutating func normalize() {
        let minSize = 0.04
        width = min(max(width, minSize), 1)
        height = min(max(height, minSize), 1)
        x = min(max(x, 0), 1 - width)
        y = min(max(y, 0), 1 - height)
    }

    func contains(nx: Double, ny: Double) -> Bool {
        nx >= x && nx <= x + width && ny >= y && ny <= y + height
    }
}
