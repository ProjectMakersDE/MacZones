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
}
