import Foundation
import CoreGraphics
import SwiftUI
import Testing
import DartCore
@testable import DartUI

/// The snapshot catalogue (ARCHITECTURE.md §8.4.10, §8.11): the four kernel screens, and the rule that every
/// screen of the catalogue renders to a picture that is not empty, as SnapshotTool renders it.
@MainActor
@Suite struct KernelSnapshotTests {
    /// What SnapshotTool does for one file, at one pixel per point.
    private func render(_ screen: SnapshotScreen, _ device: SnapshotDevice, _ language: AppLanguage) throws -> KernelBitmap {
        let renderer = ImageRenderer(content: SnapshotCatalog.framed(screen.make(device), device: device, language: language))
        renderer.proposedSize = ProposedViewSize(device.size)
        renderer.scale = 1
        return try KernelBitmap(#require(renderer.cgImage, "render failed: \(screen.id)@\(device.rawValue)"))
    }

    @Test func kernelScreens_areTheFourOfTheDocument_andTheSkeletonScreenIsGone() {
        #expect(SnapshotCatalog.kernelScreens.map(\.id) == ["board-plain", "board-zones", "board-discs", "components"])
        #expect(SnapshotCatalog.kernelScreens.allSatisfy { $0.devices == [.phonePortrait] })
        // The trial screen of lot F0 must not survive wave 1 (§8.4.10).
        #expect(!SnapshotCatalog.all.contains { $0.id == "skeleton" })
        // Kernel first, in the order of §8.11.
        #expect(Array(SnapshotCatalog.all.prefix(4)).map(\.id) == SnapshotCatalog.kernelScreens.map(\.id))
    }

    @Test func catalog_isNotEmpty_andEveryFileNameIsUnique() {
        let screens = SnapshotCatalog.all
        #expect(!screens.isEmpty)
        let files = screens.flatMap { screen in screen.devices.map { "\(screen.id)@\($0.rawValue)" } }
        #expect(Set(files).count == files.count)
        for screen in screens {
            #expect(!screen.id.isEmpty && !screen.devices.isEmpty)
            #expect(Set(screen.devices).count == screen.devices.count, "\(screen.id) lists a device twice")
            // A file name stem: lower case letters, digits and dashes.
            #expect(screen.id.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }, "\(screen.id)")
        }
    }

    @Test func everyScreenOfTheCatalog_rendersToAPictureThatIsNotEmpty_inBothLanguages() throws {
        for screen in SnapshotCatalog.all {
            for device in screen.devices {
                for language in AppLanguage.allCases {
                    let bitmap = try render(screen, device, language)
                    #expect(bitmap.width == Int(device.size.width) && bitmap.height == Int(device.size.height),
                            "\(screen.id)@\(device.rawValue)")
                    // Not empty: something else than the screen background is drawn. An entry view that is not
                    // written yet (an empty body) or a content that `ImageRenderer` cannot draw leaves 0 pixels; one
                    // line of 16 pt text is about a thousand. The bound stays low so that a sparse screen of
                    // another lot (`camera-denied`) is not taken for an empty one.
                    let drawn = bitmap.count(differingFrom: KernelPalette.background, tolerance: 6)
                    #expect(drawn > 1_000, "\(screen.id)@\(device.rawValue) (\(language.rawValue)) is empty: \(drawn) pixels")
                }
            }
        }
    }

    @Test func kernelScreens_renderOnEveryDevice() throws {
        // A kernel content is pure: it also renders at the three other sizes, in both width classes.
        for screen in SnapshotCatalog.kernelScreens {
            for device in SnapshotDevice.allCases {
                let bitmap = try render(screen, device, .fr)
                #expect(bitmap.count(differingFrom: KernelPalette.background, tolerance: 6) > 2_000, "\(screen.id)@\(device.rawValue)")
            }
        }
    }

    @Test func framedScreen_hasTheDarkBackground_andFollowsTheLanguage() throws {
        let screens = SnapshotCatalog.kernelScreens
        for screen in screens {
            let french = try render(screen, .phonePortrait, .fr), english = try render(screen, .phonePortrait, .en)
            // The corners of the frame are the screen background of DESIGN.md.
            for corner in [CGPoint(x: 1, y: 1), CGPoint(x: 391, y: 1), CGPoint(x: 1, y: 850), CGPoint(x: 391, y: 850)] {
                #expect(french.has(KernelPalette.background, at: corner), "\(screen.id)")
            }
            // Its texts are written in the language of the frame: the two pictures differ.
            var different = 0
            for y in stride(from: 0, to: 852, by: 2) {
                for x in stride(from: 0, to: 393, by: 2) where french.color(at: CGPoint(x: x, y: y)) != english.color(at: CGPoint(x: x, y: y)) {
                    different += 1
                }
            }
            #expect(different > 50, "\(screen.id): \(different)")
        }
    }

    @Test func boardScreens_showTheBoardOfTheDocument() throws {
        // "board-plain": the first board is the bare board with thick rings, under the 16 pt heading block.
        let plain = try render(SnapshotCatalog.kernelScreens[0], .phonePortrait, .fr)
        #expect(plain.count(differingFrom: KernelPalette.boardCream) < 393 * 852)
        #expect(plain.count(differingFrom: KernelPalette.boardRed) < 393 * 852 - 2_000)
        #expect(plain.count(differingFrom: KernelPalette.boardGreen) < 393 * 852 - 2_000)
        // "board-zones": the four player colours of the Killer zones are on the picture.
        let zones = try render(SnapshotCatalog.kernelScreens[1], .phonePortrait, .fr)
        for player in 0..<4 {
            #expect(zones.count(differingFrom: KernelPalette.players[player]) < 393 * 852 - 300, "player \(player)")
        }
        // "board-discs": amber outlines and labels of the five Radar targets.
        let discs = try render(SnapshotCatalog.kernelScreens[2], .phonePortrait, .fr)
        #expect(discs.count(differingFrom: KernelPalette.accent) < 393 * 852 - 1_000)
        // "components": the amber of the primary button and of the switch.
        let components = try render(SnapshotCatalog.kernelScreens[3], .phonePortrait, .fr)
        #expect(components.count(differingFrom: KernelPalette.accent) < 393 * 852 - 5_000)
        #expect(components.count(differingFrom: KernelPalette.surface) < 393 * 852 - 5_000)
    }

    @Test func fixtures_areThoseOfTheDocument() {
        // §8.11: the five Radar targets of RAD-1 (seed 1), labels and hit points.
        let discs = KernelSnapshotFixtures.radarDiscs
        #expect(discs.map(\.zone) == [.disc(x: -80, y: 95, radius: 40), .disc(x: 70, y: -65, radius: 40), .disc(x: 110, y: 65, radius: 28),
                                      .disc(x: 25, y: 15, radius: 28), .disc(x: 140, y: 0, radius: 16)])
        #expect(discs.compactMap(\.label) == ["+10", "+10", "+20", "+20", "+50"])
        #expect(discs.compactMap(\.strength) == [3, 3, 2, 2, 1])
        #expect(discs.allSatisfy { $0.role == .target && $0.owner == nil })
        // Killer at four players: four zones of three adjacent sectors, one per player, none shared.
        let zones = KernelSnapshotFixtures.killerZones
        #expect(Set(zones.compactMap(\.owner)) == [0, 1, 2, 3] && zones.count == 12)
        #expect(Set(zones.compactMap(\.zone.number)).count == 12)
        for owner in 0..<4 {
            let numbers = zones.filter { $0.owner == owner }.compactMap(\.zone.number)
            #expect(numbers.count == 3)
            let indices = numbers.map { BoardGeometry.standard.sectorIndex(of: $0) }.sorted()
            #expect(indices[2] - indices[0] == 2, "player \(owner): \(numbers) are not adjacent")
        }
        // One zone of each of the six roles on the second board.
        #expect(Set(KernelSnapshotFixtures.everyRole.map(\.role.rawValue)).count == 6)
    }
}
