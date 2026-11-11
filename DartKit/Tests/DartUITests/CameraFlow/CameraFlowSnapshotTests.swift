import Foundation
import CoreGraphics
import SwiftUI
import AVFoundation
import Testing
import DartCore
import DartVision
@testable import DartUI

/// The camera-flow snapshots (ARCHITECTURE.md §8.11) and the pieces of the screens that can be checked without a
/// device: the screens of the table, drawn with synthetic frames in both languages; the placement of overlays on
/// an image; the cause of a capture interruption on macOS; the real service before it starts.
@MainActor
@Suite struct CameraFlowSnapshotTests {
    private static let background: (Int, Int, Int) = (0x0E, 0x11, 0x14)

    /// Renders as SnapshotTool does, at one pixel per point: the pixels that are not the background, and the bytes.
    private func render(_ screen: SnapshotScreen, _ device: SnapshotDevice, _ language: AppLanguage) throws -> (drawn: Int, bytes: [UInt8]) {
        let renderer = ImageRenderer(content: SnapshotCatalog.framed(screen.make(device), device: device, language: language))
        renderer.proposedSize = ProposedViewSize(device.size)
        renderer.scale = 1
        let image = try #require(renderer.cgImage, "render failed: \(screen.id)@\(device.rawValue)")
        let width = image.width, height = image.height
        #expect(width == Int(device.size.width) && height == Int(device.size.height))
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

    @Test func screens_areThoseOfTheDocument_onAPhoneAndAnIPad() {
        let screens = SnapshotCatalog.cameraFlowScreens
        let devices = Dictionary(screens.map { ($0.id, Set($0.devices)) }, uniquingKeysWith: { first, _ in first })
        let required: [String: Set<SnapshotDevice>] = [
            "camera-denied": [.phonePortrait, .padLandscape], "placement-guide": [.phonePortrait],
            "calibration": [.phonePortrait, .padLandscape], "live-scan": [.phonePortrait, .padLandscape],
            "photo-mode": [.phonePortrait, .padLandscape], "photo-mode-no-camera": [.phonePortrait],
            "scan-thumbnail": [.padLandscape],
        ]
        for (id, expected) in required {
            #expect(expected.isSubset(of: devices[id] ?? []), "\(id): \(String(describing: devices[id]))")
        }
        // The camera flow closes the catalogue, and every file name is unique.
        let all = SnapshotCatalog.all.map(\.id)
        #expect(Set(all).count == all.count)
        #expect(Array(all.suffix(screens.count)) == screens.map(\.id))
    }

    @Test func everyScreen_rendersInBothLanguages() throws {
        for screen in SnapshotCatalog.cameraFlowScreens {
            for device in screen.devices {
                let french = try render(screen, device, .fr)
                let english = try render(screen, device, .en)
                #expect(french.drawn > 5_000 && english.drawn > 5_000, "\(screen.id)@\(device.rawValue) is empty")
                #expect(french.bytes != english.bytes, "\(screen.id)@\(device.rawValue): same picture in both languages")
            }
        }
    }

    @Test func fixtures_areThoseOfTheTable() throws {
        // calibration: a synthetic still, four handles, an advice; the proof of a "fair" calibration.
        let adjusting = CameraFlowFixtures.calibrationAdjusting(.phonePortrait)
        #expect(adjusting.stage == .adjusting && adjusting.picture != nil && adjusting.handles?.points.count == 4)
        #expect(CalibrationText.advice(for: adjusting.issues) != nil)
        let proof = CameraFlowFixtures.calibrationProof(.padLandscape)
        #expect(proof.quality?.grade == .fair && proof.rectified != nil && CalibrationText.advice(for: proof.quality?.issues ?? []) != nil)
        // live-scan: two tips, one "?", placed where the calibration of the synthetic camera puts the darts.
        let live = CameraFlowFixtures.liveScan(.phonePortrait)
        #expect(live.marks.map(\.label) == ["T20", "T19 ?"] && live.marks.map(\.needsReview) == [false, true])
        let calibration = CameraFlowFixtures.portraitCamera.calibration(grade: .good)
        #expect(calibration.hit(at: live.marks[0].point, board: .standard) == .treble(20))
        #expect(calibration.hit(at: live.marks[1].point, board: .standard) == .treble(19))
        // photo-mode: last photo T20, T19, S7; the variant without a camera.
        let photo = CameraFlowFixtures.photoMode(.phonePortrait)
        #expect(photo.lastHits == [.treble(20), .treble(19), .single(7)] && photo.canScan && photo.canImport)
        let blind = CameraFlowFixtures.photoModeWithoutCamera
        #expect(!blind.hasCamera && blind.canImport && !blind.canTakePhoto && !blind.canScan && !blind.canCaptureReference)
    }

    @Test func imageFit_placesImagePointsAsTheImageIsDrawn() {
        // A 1080 × 1920 image in a 393 × 600 view.
        let fit = CameraImageFit(imageSize: PixelSize(width: 1080, height: 1920), viewSize: CGSize(width: 393, height: 600), fills: false)
        #expect(abs(fit.scale - 600.0 / 1920.0) < 1e-9)
        // The corners of the image are the edges of the drawn image (pixel centres are half a pixel inside).
        let topLeft = fit.viewPoint(ImagePoint(x: -0.5, y: -0.5))
        let bottomRight = fit.viewPoint(ImagePoint(x: 1079.5, y: 1919.5))
        #expect(abs(topLeft.y) < 1e-9 && abs(bottomRight.y - 600) < 1e-9)
        #expect(abs(topLeft.x - (393 - 1080 * fit.scale) / 2) < 1e-9 && abs(bottomRight.x - (393 + 1080 * fit.scale) / 2) < 1e-9)
        let fill = CameraImageFit(imageSize: PixelSize(width: 1080, height: 1920), viewSize: CGSize(width: 393, height: 600), fills: true)
        #expect(abs(fill.scale - 393.0 / 1080.0) < 1e-9 && fill.origin.y < 0)
        // Round trip.
        for fitting in [fit, fill] {
            for point in [ImagePoint(x: 0, y: 0), ImagePoint(x: 540.25, y: 960.75), ImagePoint(x: 1079, y: 3)] {
                let back = fitting.imagePoint(fitting.viewPoint(point))
                #expect(abs(back.x - point.x) < 1e-9 && abs(back.y - point.y) < 1e-9)
            }
        }
        #expect(fit.shows(ImagePoint(x: 540, y: 960)) && !fill.shows(ImagePoint(x: 540, y: 10)))
    }

    @Test func captureInterruption_onMacOS_isAFailure() {
        let notification = Notification(name: Notification.Name("AVCaptureSessionWasInterruptedNotification"), object: nil,
                                        userInfo: ["AVCaptureSessionInterruptionReasonKey": 3])
        let issue = CaptureInterruptionObserver.issue(for: notification)
        if case .failed = issue {} else { Issue.record("expected .failed, got \(issue)") }
    }

    @Test func liveScanService_beforeStart_doesNothingAndTrapsNothing() async {
        let service = LiveScanService()
        #expect(service.frameInfo == nil && service.issue == nil && ["back-wide", "synthetic"].contains(service.cameraID))
        if case .none = service.preview {} else { Issue.record("a preview before start") }
        #expect(await service.currentState() == .needsCalibration)
        await #expect(throws: ScanServiceError(issue: .noCamera)) { try await service.captureStill(averaging: 8) }
        await service.send(.arm(boardConfirmedEmpty: true))
        #expect(await service.correct(CameraFlowSupport.id(1), tip: BoardPoint(x: 0, y: 0)) == nil)
        #expect(await service.evidenceCrop(for: CameraFlowSupport.id(1)) == nil)
        let events = service.events()
        await service.stop()
        var count = 0
        for await _ in events { count += 1 }
        #expect(count == 0)
        #expect(ScanServiceFactory.live() is LiveScanService)
    }

    @Test func cameraPermission_deniedRestrictedAndNotDetermined() {
        #expect(LiveScanService.access(for: .authorized) == .granted)
        #expect(LiveScanService.access(for: .notDetermined) == .ask)
        #expect(LiveScanService.access(for: .denied) == .refused && LiveScanService.access(for: .restricted) == .refused)
        // A refusal is the camera-denied screen, whose way out is manual input; the words say both cases.
        #expect(L10n.string("camera.denied.detail", .camera, language: .fr).contains("limité"))
        #expect(L10n.string("camera.denied.detail", .camera, language: .en).contains("restricted"))
    }

    @Test func thumbnail_saysWhatTheVisionSees() {
        func detail(_ state: ScanState, _ readiness: CameraModel.Readiness = .ready(grade: .good), issue: CameraIssue? = nil,
                    _ language: AppLanguage = .fr) -> String {
            ScanThumbnailContent.detail(state: state, readiness: readiness, issue: issue, language: language)
        }
        #expect(detail(.watching(dartsOnBoard: 2)) == "2 fléchettes vues, cible stable")
        #expect(detail(.watching(dartsOnBoard: 1), .ready(grade: .good), .en) == "1 dart seen, board still")
        #expect(detail(.watching(dartsOnBoard: 0)) == L10n.string("scan.thumbnail.empty", .camera, language: .fr))
        #expect(detail(.paused(.user)) == L10n.string("scan.thumbnail.paused", .camera, language: .fr))
        #expect(detail(.idle, .needsCalibration) == L10n.string("scan.thumbnail.needsCalibration", .camera, language: .fr))
        #expect(detail(.watching(dartsOnBoard: 0), issue: .notFullScreen) == "Passez l'application en plein écran")
        #expect(detail(.motion, .unavailable(.accessDenied), .en) == "Camera access denied")
    }
}
