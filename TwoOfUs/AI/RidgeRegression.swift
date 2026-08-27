import Foundation

/// Closed-form ridge regression — the whole "model" under Phase 2's
/// champion/challenger. Deliberately not Create ML: with a few hundred rows
/// and a handful of engineered features, the normal equations solve in
/// microseconds, run identically on the simulator and in CI, and are
/// deterministic enough to unit-test — none of which holds for an on-device
/// Create ML training pass. If a linear challenger ever proves too weak,
/// that's the moment to reach for boosted trees, with the same gate.
enum RidgeRegression {

    /// Fits w minimizing ‖Xw − y‖² + λ‖w‖², via (XᵀX + λI)w = Xᵀy with
    /// Gaussian elimination. Returns nil when there's nothing to fit or the
    /// system is degenerate (which λ > 0 makes effectively impossible).
    static func fit(rows: [[Double]], targets: [Double], lambda: Double = 1.0) -> [Double]? {
        guard let width = rows.first?.count, width > 0,
              rows.count == targets.count, rows.count >= width,
              lambda >= 0 else { return nil }
        guard rows.allSatisfy({ $0.count == width }) else { return nil }

        // A = XᵀX + λI, b = Xᵀy
        var a = [[Double]](repeating: [Double](repeating: 0, count: width), count: width)
        var b = [Double](repeating: 0, count: width)
        for (row, y) in zip(rows, targets) {
            for i in 0..<width {
                b[i] += row[i] * y
                for j in i..<width {
                    a[i][j] += row[i] * row[j]
                }
            }
        }
        for i in 0..<width {
            a[i][i] += lambda
            for j in 0..<i { a[i][j] = a[j][i] }   // mirror the upper triangle
        }

        // Gaussian elimination with partial pivoting.
        var x = b
        for col in 0..<width {
            var pivot = col
            for r in (col + 1)..<width where abs(a[r][col]) > abs(a[pivot][col]) {
                pivot = r
            }
            guard abs(a[pivot][col]) > 1e-12 else { return nil }
            if pivot != col {
                a.swapAt(pivot, col)
                x.swapAt(pivot, col)
            }
            for r in (col + 1)..<width {
                let factor = a[r][col] / a[col][col]
                guard factor != 0 else { continue }
                for c in col..<width { a[r][c] -= factor * a[col][c] }
                x[r] -= factor * x[col]
            }
        }
        for col in stride(from: width - 1, through: 0, by: -1) {
            for r in (col + 1)..<width { x[col] -= a[col][r] * x[r] }
            x[col] /= a[col][col]
        }
        return x
    }

    static func predict(coefficients: [Double], features: [Double]) -> Double {
        zip(coefficients, features).reduce(0) { $0 + $1.0 * $1.1 }
    }
}
