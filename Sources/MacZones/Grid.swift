import Foundation

/// Generates a tiled grid of zones covering the whole screen.
enum Grid {
    static func zones(columns: Int, rows: Int, gap: Double = 0) -> [Zone] {
        let c = max(1, columns)
        let r = max(1, rows)
        let g = max(0, min(gap, 0.1))
        let cellW = 1.0 / Double(c)
        let cellH = 1.0 / Double(r)

        var result: [Zone] = []
        for row in 0..<r {
            for col in 0..<c {
                var z = Zone(x: Double(col) * cellW + g / 2,
                             y: Double(row) * cellH + g / 2,
                             width: cellW - g,
                             height: cellH - g)
                z.normalize()
                result.append(z)
            }
        }
        return result
    }

    /// Capped at 6×6 (the most this tool supports).
    static let maxDivisions = 6

    /// A sensible starting column/row count for a screen of the given aspect
    /// ratio: ultra-wide (≈32:9) → 6×2, 16:9 → 3×2, 4:3 → 2×2.
    static func defaultDims(aspect: Double) -> (columns: Int, rows: Int) {
        let columns = min(maxDivisions, max(2, Int((aspect * 1.7).rounded())))
        return (columns, 2)
    }
}
