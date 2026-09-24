import XCTest
import SwiftUI
import UIKit
@testable import Pantheon

/// The press and the motion curves (2026-09-24, `Docs/FEEL.md` W1.8). Every
/// kind of press but the quiet one sinks under the finger and springs past
/// its size on the way back; only the quiet one — a scrolling row's — never
/// answers touch-down, because a scroll view reports a press under a finger
/// that has only started to drag; the old `PlateButtonStyle()` spelling stays
/// silent for the call sites whose actions still play their own tap; and the
/// game's Reduce Motion switch turns every chrome curve into the calm ease.
final class PressTests: XCTestCase {
    @MainActor
    func testEveryPressSinksAndSpringsPastItsSize() {
        let kinds: [GamePressStyle.Kind] = [.primary, .plate, .medallion]
        for kind in kinds {
            let sink: Double = kind.sink
            let overshoot: Double = kind.overshoot
            XCTAssertLessThan(sink, 1, "\(kind) sinks under the finger")
            XCTAssertGreaterThan(overshoot, 1, "\(kind) springs past its size as it lets go")
            XCTAssertNotNil(kind.haptic, "\(kind) ticks on touch-down")
        }
        let quietSink: Double = GamePressStyle.Kind.quiet.sink
        XCTAssertEqual(quietSink, 1, "a scrolling row answers in brightness alone")
        XCTAssertNil(GamePressStyle.Kind.quiet.haptic, "a scrolling row never ticks on touch-down")
    }

    @MainActor
    func testOnlyTheFullPressAnswersTouchDown() {
        XCTAssertTrue(GamePressStyle(.primary).answersTouchDown)
        XCTAssertTrue(GamePressStyle(.plate).answersTouchDown)
        XCTAssertTrue(GamePressStyle(.medallion).answersTouchDown)
        XCTAssertFalse(GamePressStyle(.quiet).answersTouchDown, "a drag that starts on a row must not tick")
        XCTAssertFalse(GamePressStyle(.plate, sounds: false).answersTouchDown, "a shut door sinks in silence")
        XCTAssertFalse(PlateButtonStyle().answersTouchDown, "the old spelling's actions still play their own tap")
    }

    @MainActor
    func testReduceMotionMakesEveryChromeCurveCalm() {
        let saved = UserDefaults.standard.object(forKey: MotionComfort.key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: MotionComfort.key)
            } else {
                UserDefaults.standard.removeObject(forKey: MotionComfort.key)
            }
        }
        UserDefaults.standard.set(true, forKey: MotionComfort.key)
        let curves: [Animation] = [Motion.tap, Motion.select, Motion.pop, Motion.panel, Motion.exit, Motion.celebrate]
        for curve in curves {
            XCTAssertEqual(curve, Motion.calm, "no bounce under Reduce Motion")
        }
        let own: Animation = Motion.respecting(.linear(duration: 1))
        XCTAssertEqual(own, Motion.calm, "a screen's own curve is calmed the same way")
        UserDefaults.standard.set(false, forKey: MotionComfort.key)
        if !UIAccessibility.isReduceMotionEnabled {
            XCTAssertNotEqual(Motion.panel, Motion.calm, "the springs come back when the switch is off")
        }
    }
}
