import Testing
import DartCore
import DartTestSupport

/// Smoke test of the target (ARCHITECTURE.md §13.2): DartCore links, and a whole game runs through the kernel
/// and the journal. The detailed tests of DartCore are in the other `Smoke…Tests` files of this folder.
@Suite struct SmokeTests {
    @Test func aWholeGameRunsThroughTheKernelAndTheJournal() throws {
        var match = try SmokeFixtures.registry.match(.x01, ["startScore": 301], players: 2, seed: 1)
        match.play("T20, T20, T20 | S20, S1, MISS | T20, S11, DB")
        #expect(match.phase == .finished && match.snapshot.finishReason == .victory)
        #expect(match.fact(0, "remaining") == 0 && match.fact(1, "remaining") == 280)
        #expect(match.snapshot.ranks == [1, 2] && match.snapshot.winners == [0])
        // Undo everything: back to the initial state.
        while match.canUndo { match.undo() }
        #expect(match.phase == .throwing && match.fact(0, "remaining") == 301 && match.entries.isEmpty)
    }
}
