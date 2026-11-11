import Foundation
import Testing
import DartCore
import DartVision
import DartTestSupport
@testable import DartUI

/// A position-dependent probe of the tests (ARCHITECTURE.md §8.7: the test defines its own rule, independent of
/// lot G4): one fixed round target of radius 30 mm centred at (0, 50) mm. An impact on or inside it scores 10.
private struct CameraFlowDiscRules: TurnBasedRules {
    static let descriptor = GameDescriptor(
        id: GameID("cameraFlowDisc"), name: LocalizedText(verbatim: "Disc"), shortName: LocalizedText(verbatim: "Disc"),
        summary: LocalizedText(verbatim: "Disc"), pitch: LocalizedText(verbatim: "Disc"), players: 1...2, options: [],
        playStyle: .board, origin: .dartsee, priority: 1, dependsOnPosition: true)
    /// Centre and radius, tenths of a millimetre.
    static let centre = (x: 0, y: 500)
    static let radius = 300

    var points: [Int]

    init(configuration: GameConfiguration, random: inout SeededRandom) throws {
        points = Array(repeating: 0, count: configuration.players.count)
    }

    var roundLimit: Int? { 5 }
    func isEliminated(_ player: PlayerIndex) -> Bool { false }
    mutating func turnStarted(_ context: TurnContext, random: inout SeededRandom, events: inout [GameEvent]) {}

    mutating func dartThrown(_ hit: Hit, _ context: TurnContext, random: inout SeededRandom,
                             events: inout [GameEvent]) -> DartVerdict {
        let player = context.currentPlayer
        guard let impact = context.impact else {
            events.append(.noEffect(player: player))
            return .turnContinues
        }
        let dx = impact.x - Self.centre.x, dy = impact.y - Self.centre.y
        if dx * dx + dy * dy <= Self.radius * Self.radius {
            points[player] += 10
            events.append(.blobDestroyed(player: player, blob: 0, points: 10))
        } else {
            events.append(.noEffect(player: player))
        }
        return .turnContinues
    }

    mutating func turnClosed(_ context: TurnContext, events: inout [GameEvent]) {}
    func ranks() -> [Int] { Ranking.ranks(keys: points.map { [-$0] }) }

    func presentation(_ context: TurnContext) -> RulesPresentation {
        RulesPresentation(title: Self.descriptor.name,
                          rows: points.indices.map { PlayerRow(player: $0, primary: ScoreValue(points[$0]), facts: ["points": .int(points[$0])]) })
    }
}

/// `DartProposal(observation:thresholds:)` (ARCHITECTURE.md §8.4.8): origin, hit, position, choices, the three
/// certainties on the game-aware tier, and the tip at the edge of a target in a position-dependent game.
@Suite struct CameraFlowProposalTests {
    private func discMatch() throws -> GameMatch {
        let configuration = GameConfiguration(gameID: CameraFlowDiscRules.descriptor.id, players: testPlayers(1), seed: 1)
        return try GameMatch(definition: GameDefinition(rules: CameraFlowDiscRules.self), configuration: configuration,
                             startedAt: Date(timeIntervalSinceReferenceDate: 0))
    }

    @Test @MainActor func observation_givesItsHitPositionChoicesAndOrigin() {
        let id = CameraFlowSupport.id(1)
        let observation = DartObservation(
            id: id, visit: 2, indexInVisit: 1, timestamp: 3, tip: BoardPoint(x: 2, y: 101),
            uncertainty: TipUncertainty(sigmaAlong: 0.85, sigmaAcross: 0.37, axis: SIMD2(0, 1)),
            candidates: [HitCandidate(hit: .treble(20), probability: 0.7), HitCandidate(hit: .single(20), probability: 0.3)],
            nearbyHits: [.treble(1), .treble(5), .single(1)], confidence: 0.7, tier: .medium, flags: [], source: .liveCamera)
        let proposal = DartProposal(observation: observation, thresholds: .standard)
        #expect(proposal.id == id && proposal.hit == .treble(20) && proposal.position == BoardPoint(x: 2, y: 101))
        #expect(proposal.choices == [.treble(20), .single(20), .treble(1), .treble(5)])
        let origins: [(ObservationSource, DartOrigin)] = [(.liveCamera, .camera), (.scan, .scan), (.handheldPhoto, .photo),
                                                          (.tappedOnPhoto, .photo)]
        for (source, origin) in origins {
            let seen = CameraFlowSupport.observation(id, .single(5), source: source)
            #expect(DartProposal(observation: seen, thresholds: .standard).origin == origin, "\(source)")
        }
        // The journal record keeps the identifier of the observation.
        #expect(proposal.record(needsReview: true).id == id && proposal.record(needsReview: true).origin == .camera)
    }

    @Test @MainActor func tiers_giveTheThreeCertainties() throws {
        let match = try CameraFlowSupport.highScoreMatch()
        let cases: [(Double, Certainty)] = [(0.97, .certain), (0.85, .certain), (0.7, .needsReview), (0.5, .needsReview),
                                            (0.49, .undecided), (0.1, .undecided)]
        for (confidence, expected) in cases {
            let observation = CameraFlowSupport.observation(CameraFlowSupport.id(2), .single(19), confidence: confidence)
            #expect(DartProposal(observation: observation, thresholds: .standard).certainty(match) == expected, "\(confidence)")
        }
        // Raised thresholds (accuracy degraded): 0.9 is no longer high.
        var raised = ConfidenceThresholds.standard
        raised.high = 0.95
        let observation = CameraFlowSupport.observation(CameraFlowSupport.id(3), .single(19), confidence: 0.9)
        #expect(DartProposal(observation: observation, thresholds: raised).certainty(match) == .needsReview)
    }

    @Test @MainActor func aDoubtBetweenHitsOfEqualEffect_doesNotBotherThePlayer() throws {
        // In the disc game every hit at the same tip has the same effect: S11 or S14, the dart is certain.
        let match = try discMatch()
        let candidates = [HitCandidate(hit: .single(11), probability: 0.6), HitCandidate(hit: .single(14), probability: 0.4)]
        let tip = BoardPoint(x: -120, y: 30)
        let observation = CameraFlowSupport.observation(CameraFlowSupport.id(4), .single(11), tip: tip, confidence: 0.6,
                                                        candidates: candidates)
        #expect(DartProposal(observation: observation, thresholds: .standard).certainty(match) == .certain)
        // In "Meilleur score" the two hits score differently: the doubt stays.
        let highScore = try CameraFlowSupport.highScoreMatch()
        #expect(DartProposal(observation: observation, thresholds: .standard).certainty(highScore) == .needsReview)
        // A capped observation stays below the high tier however its candidates collapse.
        let warmUp = CameraFlowSupport.observation(CameraFlowSupport.id(5), .single(11), tip: tip, confidence: 0.6,
                                                   candidates: candidates, flags: .warmUp)
        #expect(DartProposal(observation: warmUp, thresholds: .standard).certainty(match) == .needsReview)
    }

    // MARK: Mandatory test of §8.7: a tip at the edge of a target

    @Test @MainActor func tipAtTheEdgeOfATarget_isToBeChecked_unlessThePlayerPlacedIt() throws {
        let match = try discMatch()
        #expect(match.definition.descriptor.dependsOnPosition)
        func certainty(_ tip: BoardPoint, _ source: ObservationSource = .liveCamera,
                       axis: SIMD2<Double> = SIMD2(0, 1)) -> Certainty {
            let observation = CameraFlowSupport.observation(CameraFlowSupport.id(6), BoardGeometry.standard.hit(at: tip), tip: tip,
                                                            confidence: 0.95, source: source, sigmaAlong: 0.85,
                                                            sigmaAcross: 0.37, axis: axis)
            return DartProposal(observation: observation, thresholds: .standard).certainty(match)
        }
        // The edge of the target is at y = 80 above its centre: 0.3 mm inside, then 5 mm inside.
        #expect(certainty(BoardPoint(x: 0, y: 79.7)) == .needsReview)
        #expect(certainty(BoardPoint(x: 0, y: 75)) == .certain)
        // Same tip at the edge, but placed by the player on a photo: certain.
        #expect(certainty(BoardPoint(x: 0, y: 79.7), .tappedOnPhoto) == .certain)
        // Across the dart too: the axis along the edge, the normal across it (sigmaAcross 0.37 mm).
        #expect(certainty(BoardPoint(x: 0, y: 79.7), axis: SIMD2(1, 0)) == .needsReview)
        #expect(certainty(BoardPoint(x: 0, y: 79.5), axis: SIMD2(1, 0)) == .certain)
        // Outside, far from the edge, and outside, close to it.
        #expect(certainty(BoardPoint(x: 0, y: 90)) == .certain)
        #expect(certainty(BoardPoint(x: 0, y: 80.4)) == .needsReview)
        // Without sigmas the check is off.
        let blind = CameraFlowSupport.observation(CameraFlowSupport.id(7), .single(20), tip: BoardPoint(x: 0, y: 79.7),
                                                  confidence: 0.95, sigmaAlong: 0, sigmaAcross: 0)
        #expect(DartProposal(observation: blind, thresholds: .standard).certainty(match) == .certain)
    }

    @Test @MainActor func theEdgeCheck_isOnlyForPositionDependentGames() throws {
        let highScore = try CameraFlowSupport.highScoreMatch()
        // A tip 0.2 mm from the treble wire of "Meilleur score", but with one candidate: high, certain.
        let observation = CameraFlowSupport.observation(CameraFlowSupport.id(8), .treble(20), tip: BoardPoint(x: 0, y: 99.2))
        #expect(DartProposal(observation: observation, thresholds: .standard).certainty(highScore) == .certain)
    }
}
