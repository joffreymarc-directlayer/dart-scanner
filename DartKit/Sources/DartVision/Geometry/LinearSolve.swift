import Foundation

/// Small dense linear systems, solved by Gaussian elimination with partial pivoting (VISION.md §4.2).
/// Internal to DartVision: the DLT (8x8), the handle refinement (8x8) and the conic fit (5x5) all go through here.
enum LinearSolve {
    /// Solves `A x = b` for a square system. `matrix` is row-major, `count * count` values, `rhs` has `count` values.
    /// Nil when the sizes do not match, when a value is not finite, or when a pivot is smaller in magnitude than
    /// `minPivot` (singular or degenerate input).
    static func solve(_ matrix: [Double], _ rhs: [Double], minPivot: Double = 1e-12) -> [Double]? {
        let n = rhs.count
        guard n > 0, matrix.count == n * n else { return nil }
        var a = matrix
        var b = rhs
        for value in a where !value.isFinite { return nil }
        for value in b where !value.isFinite { return nil }

        for column in 0..<n {
            // Partial pivoting: the largest magnitude of the column, at or below the diagonal.
            var pivotRow = column
            var pivotMagnitude = abs(a[column * n + column])
            for row in (column + 1)..<n {
                let magnitude = abs(a[row * n + column])
                if magnitude > pivotMagnitude {
                    pivotMagnitude = magnitude
                    pivotRow = row
                }
            }
            guard pivotMagnitude >= minPivot, pivotMagnitude.isFinite else { return nil }
            if pivotRow != column {
                for k in 0..<n {
                    a.swapAt(column * n + k, pivotRow * n + k)
                }
                b.swapAt(column, pivotRow)
            }
            let pivot = a[column * n + column]
            for row in (column + 1)..<n {
                let factor = a[row * n + column] / pivot
                if factor == 0 { continue }
                a[row * n + column] = 0
                for k in (column + 1)..<n {
                    a[row * n + k] -= factor * a[column * n + k]
                }
                b[row] -= factor * b[column]
            }
        }

        var x = [Double](repeating: 0, count: n)
        for row in stride(from: n - 1, through: 0, by: -1) {
            var sum = b[row]
            for k in (row + 1)..<n {
                sum -= a[row * n + k] * x[k]
            }
            let value = sum / a[row * n + row]
            guard value.isFinite else { return nil }
            x[row] = value
        }
        return x
    }

    /// Weighted linear least squares through the normal equations `(AᵀWA) x = AᵀW b`.
    /// `rows[i]` is one equation with `unknowns` coefficients, `values[i]` its right-hand side and `weights[i]`
    /// its weight (1 when `weights` is nil). Nil when the input is inconsistent or the normal matrix is singular.
    static func leastSquares(rows: [[Double]], values: [Double], weights: [Double]? = nil, unknowns: Int,
                             minPivot: Double = 1e-12) -> [Double]? {
        guard unknowns > 0, rows.count == values.count, rows.count >= unknowns else { return nil }
        if let weights, weights.count != rows.count { return nil }
        var normal = [Double](repeating: 0, count: unknowns * unknowns)
        var right = [Double](repeating: 0, count: unknowns)
        for (index, row) in rows.enumerated() {
            guard row.count == unknowns else { return nil }
            let weight = weights?[index] ?? 1
            for i in 0..<unknowns {
                let scaled = weight * row[i]
                if scaled == 0 { continue }
                right[i] += scaled * values[index]
                for j in 0..<unknowns {
                    normal[i * unknowns + j] += scaled * row[j]
                }
            }
        }
        return solve(normal, right, minPivot: minPivot)
    }
}
