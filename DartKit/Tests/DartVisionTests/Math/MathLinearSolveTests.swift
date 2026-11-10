import Foundation
import Testing
@testable import DartVision

/// Gaussian elimination with partial pivoting and the normal equations (VISION.md §4.2).
@Suite struct MathLinearSolveTests {
    @Test func solve_smallSystems() throws {
        // 2x + y = 5, x − 3y = −8 → x = 1, y = 3.
        let x = try #require(LinearSolve.solve([2, 1, 1, -3], [5, -8]))
        #expect(abs(x[0] - 1) < 1e-12 && abs(x[1] - 3) < 1e-12)
        // A zero on the diagonal needs the pivoting: [[0, 1], [1, 0]].
        let swapped = try #require(LinearSolve.solve([0, 1, 1, 0], [7, 9]))
        #expect(swapped == [9, 7])
        // A random 8x8 system: A·x reproduces b.
        var random = SupportRandom(seed: 0x15)
        let n = 8
        let a = (0..<(n * n)).map { _ in random.uniform(-10...10) }
        let truth = (0..<n).map { _ in random.uniform(-5...5) }
        let b = (0..<n).map { row in (0..<n).reduce(0.0) { $0 + a[row * n + $1] * truth[$1] } }
        let solved = try #require(LinearSolve.solve(a, b))
        #expect(zip(solved, truth).allSatisfy { abs($0 - $1) < 1e-9 })
    }

    @Test func solve_refusesSingularAndMalformedSystems() {
        #expect(LinearSolve.solve([1, 2, 2, 4], [1, 2]) == nil)
        #expect(LinearSolve.solve([1e-13, 0, 0, 1], [1, 1]) == nil)
        #expect(LinearSolve.solve([1e-13, 0, 0, 1], [1, 1], minPivot: 1e-14) != nil)
        #expect(LinearSolve.solve([1, 2, 3], [1, 2]) == nil)
        #expect(LinearSolve.solve([], []) == nil)
        #expect(LinearSolve.solve([1, .nan, 0, 1], [1, 1]) == nil)
        #expect(LinearSolve.solve([1, 0, 0, 1], [.infinity, 1]) == nil)
    }

    @Test func leastSquares_fitsALineThroughNoisyPoints() throws {
        // y = 2x + 1 sampled exactly: the fit is exact; a weight of zero ignores an outlier.
        let xs: [Double] = [0, 1, 2, 3, 4]
        let rows = xs.map { [$0, 1.0] }
        let exact = try #require(LinearSolve.leastSquares(rows: rows, values: xs.map { 2 * $0 + 1 }, unknowns: 2))
        #expect(abs(exact[0] - 2) < 1e-12 && abs(exact[1] - 1) < 1e-12)
        var values = xs.map { 2 * $0 + 1 }
        values[2] = 100
        let weighted = try #require(LinearSolve.leastSquares(rows: rows, values: values, weights: [1, 1, 0, 1, 1], unknowns: 2))
        #expect(abs(weighted[0] - 2) < 1e-12 && abs(weighted[1] - 1) < 1e-12)
        // Inconsistent shapes and underdetermined systems are refused.
        #expect(LinearSolve.leastSquares(rows: rows, values: [1], unknowns: 2) == nil)
        #expect(LinearSolve.leastSquares(rows: [[1, 2]], values: [1], unknowns: 2) == nil)
        #expect(LinearSolve.leastSquares(rows: rows, values: values, weights: [1], unknowns: 2) == nil)
        #expect(LinearSolve.leastSquares(rows: [[1, 2], [2, 4], [3, 6]], values: [1, 2, 3], unknowns: 2) == nil)
    }
}
