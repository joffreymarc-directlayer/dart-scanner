import Foundation
import Testing
import SwiftUI
import DartCore
@testable import DartUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)
/// What a board reported, in order.
@MainActor
private final class KernelGestureLog {
    var taps: [Hit] = []
    var presses: [Hit] = []
    var plainTaps = 0
}

/// Independent review of the gestures of `DartboardView` (ARCHITECTURE.md §8.4.3, §8.6; DESIGN.md §5): "un tap sur
/// la cible pose la fléchette ; un appui long ouvre la vue agrandie". SwiftUI gestures only run on real events: the
/// view is hosted in a borderless window placed far off every screen and driven with synthesised mouse events.
/// Other suites may run on the main actor while a button is held; a press is therefore timed, and only a press that
/// was really short counts as a tap.
@MainActor
@Suite(.serialized) struct KernelGestureReviewTests {
    /// The treble 20 of a 300 pt board, in window coordinates (origin bottom-left).
    private let treble20 = CGPoint(x: 150, y: 150 + 103 * 150 / 225.5)

    private func wait(_ seconds: Double) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
    }

    private func host(_ view: some View) -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 300, height: 300), styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view.frame(width: 300, height: 300))
        window.orderFrontRegardless()
        wait(0.2)
        return window
    }

    /// Mouse down at `point`, held for `seconds`, mouse up. Returns how long the button was really held.
    @discardableResult
    private func press(_ window: NSWindow, at point: CGPoint, for seconds: Double) -> TimeInterval {
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        }
        let start = ProcessInfo.processInfo.systemUptime
        if let down = event(.leftMouseDown) { window.sendEvent(down) }
        wait(seconds)
        if let up = event(.leftMouseUp) { window.sendEvent(up) }
        let held = ProcessInfo.processInfo.systemUptime - start
        wait(0.3)
        return held
    }

    /// Quick taps until two of them were held for less than 0.3 s; returns how many such taps were made.
    private func quickTaps(_ window: NSWindow) -> Int {
        var quick = 0
        for _ in 0..<6 where quick < 2 {
            if press(window, at: treble20, for: 0.03) < 0.3 { quick += 1 }
        }
        return quick
    }

    @Test func theHarness_deliversATapToAPlainView() {
        // Control: synthesised events reach a SwiftUI tap gesture.
        let log = KernelGestureLog()
        let window = host(Color.red.onTapGesture { log.plainTaps += 1 })
        let quick = quickTaps(window)
        #expect(quick == 2)
        #expect(log.plainTaps >= quick)
        window.orderOut(nil)
    }

    @Test func aTap_putsADart_withoutALongPressHandler() {
        let log = KernelGestureLog()
        let window = host(DartboardView(onTap: { log.taps.append($0.hit) }))
        let quick = quickTaps(window)
        #expect(quick == 2)
        #expect(log.taps.count >= quick && log.taps.allSatisfy { $0 == .treble(20) }, "\(log.taps)")
        window.orderOut(nil)
    }

    @Test func aTap_stillPutsADart_whenTheBoardAlsoOpensTheMagnifiedView() {
        // The play screen passes both handlers (§8.6): a quick tap must stay a dart.
        let log = KernelGestureLog()
        let window = host(DartboardView(onTap: { log.taps.append($0.hit) }, onLongPress: { log.presses.append($0.hit) }))
        let quick = quickTaps(window)
        #expect(quick == 2)
        #expect(log.taps.count >= quick && log.taps.allSatisfy { $0 == .treble(20) },
                "\(quick) quick taps gave \(log.taps.count) darts on a board that also has a long press")
        #expect(log.presses.isEmpty)
        // A press held past half a second opens the magnified view once, where it was held, and puts no dart.
        let darts = log.taps.count
        press(window, at: treble20, for: 0.9)
        #expect(log.presses == [.treble(20)])
        #expect(log.taps.count == darts)
        window.orderOut(nil)
    }
}
#endif
