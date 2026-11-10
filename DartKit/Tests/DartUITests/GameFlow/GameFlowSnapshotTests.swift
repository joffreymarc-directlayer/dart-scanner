import Foundation
import CoreGraphics
import SwiftUI
import Testing
import DartCore
import DartGames
@testable import DartUI

/// The game-flow snapshots (§8.11): the screens of the table, their fixtures, and every screen rendered to a
/// picture that is not empty, in both languages, on a phone and on an iPad.
@MainActor
@Suite struct GameFlowSnapshotTests {
    private static let background: (Int, Int, Int) = (0x0E, 0x11, 0x14)

    /// Renders as SnapshotTool does, at one pixel per point, and counts the pixels that are not the background.
    private func render(_ screen: SnapshotScreen, _ device: SnapshotDevice, _ language: AppLanguage) throws -> (drawn: Int, bytes: [UInt8]) {
        let renderer = ImageRenderer(content: SnapshotCatalog.framed(screen.make(device), device: device, language: language))
        renderer.proposedSize = ProposedViewSize(device.size)
        renderer.scale = 1
        let image = try #require(renderer.cgImage, "render failed: \(screen.id)@\(device.rawValue)")
        #expect(image.width == Int(device.size.width) && image.height == Int(device.size.height))
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn: Int = try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                                 bytesPerRow: width * 4, space: space,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            var count = 0
            for pixel in stride(from: 0, to: buffer.count, by: 4) {
                let r = Int(buffer[pixel]), g = Int(buffer[pixel + 1]), b = Int(buffer[pixel + 2])
                if abs(r - Self.background.0) > 6 || abs(g - Self.background.1) > 6 || abs(b - Self.background.2) > 6 {
                    count += 1
                }
            }
            return count
        }
        return (drawn, bytes)
    }

    @Test func screens_areThoseOfTheDocument() {
        let screens = SnapshotCatalog.gameFlowScreens
        let devices = Dictionary(screens.map { ($0.id, Set($0.devices)) }, uniquingKeysWith: { first, _ in first })
        let required: [String: Set<SnapshotDevice>] = [
            "home": [.phonePortrait, .padLandscape],
            "setup-killer": [.phonePortrait], "setup-x01": [.phonePortrait], "players": [.phonePortrait],
            "play-killer": Set(SnapshotDevice.allCases), "play-x01": [.phonePortrait, .padLandscape],
            "play-cricket": [.phonePortrait], "play-highscore": [.phonePortrait], "play-beertap": [.phonePortrait],
            "play-football": [.phonePortrait], "play-radar": [.phonePortrait, .padLandscape], "play-golf": [.phonePortrait],
            "correction": [.phonePortrait], "results": [.phonePortrait, .padLandscape], "settings": [.phonePortrait],
        ]
        for (id, expected) in required {
            let actual = devices[id] ?? []
            #expect(expected.isSubset(of: actual), "\(id): \(actual)")
        }
        // Every file name is unique in the whole catalogue, and the game flow comes after the kernel.
        let all = SnapshotCatalog.all.map(\.id)
        #expect(Set(all).count == all.count)
        #expect(Array(all.dropFirst(SnapshotCatalog.kernelScreens.count).prefix(screens.count)) == screens.map(\.id))
    }

    @Test func everyScreen_rendersOnAPhoneAndAnIPad_inBothLanguages() throws {
        for screen in SnapshotCatalog.gameFlowScreens {
            for device in [SnapshotDevice.phonePortrait, .padLandscape] {
                let french = try render(screen, device, .fr)
                let english = try render(screen, device, .en)
                #expect(french.drawn > 5_000, "\(screen.id)@\(device.rawValue) is empty: \(french.drawn)")
                #expect(english.drawn > 5_000, "\(screen.id)@\(device.rawValue) (en) is empty: \(english.drawn)")
                // The texts follow the language of the frame.
                #expect(french.bytes != english.bytes, "\(screen.id)@\(device.rawValue): same picture in both languages")
            }
        }
    }

    @Test func fixtures_areThoseOfTheTable() throws {
        // play-killer: Killer Facile, 4 players, round 4, two darts, one "à vérifier"; the zones of the mock-up.
        let killer = try #require(GameFlowFixtures.killerInRound4())
        #expect(killer.snapshot.round == 4 && killer.players.count == 4 && killer.snapshot.variant?.fr == "Facile")
        #expect(killer.currentTurn.map(\.hit) == [.single(20), .treble(6)] && killer.currentTurn.map(\.needsReview) == [false, true])
        #expect(killer.snapshot.players.map { $0.facts["zone"] } == [[17, 3, 19], [20, 1, 18], [6, 10, 15], [8, 11, 14]])
        #expect(killer.snapshot.players.map { $0.facts["lives"] } == [3, 2, 1, 3])
        // play-x01: 501 double out, 24 left.
        let x01 = try #require(GameFlowFixtures.x01InRound6())
        #expect(x01.snapshot.players.map { $0.facts["remaining"] } == [187, 24, 262] && x01.snapshot.round == 6)
        #expect(x01.snapshot.highlights.map(\.zone) == [.double(12)])
        // play-beertap: glass of 50 cl, 3 full glasses, the next one at 40.
        let beer = try #require(GameFlowFixtures.beerTapInRound2())
        #expect(beer.snapshot.players[0].facts["glasses"] == 3 && beer.snapshot.players[0].facts["level"] == 40)
        #expect(beer.snapshot.highlights.isEmpty)
        // play-football: side A to throw, "A 2 – 1 B", the ball on +1.
        let football = try #require(GameFlowFixtures.footballInRound2())
        #expect(football.snapshot.facts["sideGoals"] == [2, 1] && football.snapshot.facts["ball"] == 1)
        #expect(football.snapshot.players[football.snapshot.currentPlayer].facts["side"] == 0)
        // play-radar: the discs of board-discs, one damaged; a board at regulation proportions.
        let radar = try #require(GameFlowFixtures.radarInRound1())
        #expect(radar.snapshot.highlights.map(\.zone) == KernelSnapshotFixtures.radarDiscs.map(\.zone))
        #expect(radar.snapshot.highlights.compactMap(\.strength) == [2, 3, 2, 2, 1])
        #expect(radar.definition.descriptor.boardGeometry == .standard && radar.currentTurn.allSatisfy { $0.position != nil })
        // play-golf: hole 4 of 9, par 3; −2 and +3.
        let golf = try #require(GameFlowFixtures.golfOnHole4())
        #expect(golf.snapshot.objective?.fr == "Trou 4 / 9 · par 3")
        #expect(golf.snapshot.players.map { $0.facts["toPar"] } == [-2, 3])
        // results: Killer at four finished; Football with its title.
        let results = try #require(GameFlowFixtures.killerFinished())
        #expect(results.phase == .finished && results.snapshot.ranks == [1, 3, 2, 4] && results.snapshot.winnerTitle == nil)
        let footballResults = try #require(GameFlowFixtures.footballFinished())
        #expect(footballResults.snapshot.winnerTitle?.fr == "Le camp A gagne" && footballResults.snapshot.ranks == [1, 3, 1, 3])
        // correction: T19 "à vérifier", six hits.
        #expect(GameFlowFixtures.correction.choices.count == 6 && GameFlowFixtures.correction.needsReview)
        // Two runs draw the same games.
        #expect(GameFlowFixtures.killerInRound4()?.record == killer.record)
    }
}
