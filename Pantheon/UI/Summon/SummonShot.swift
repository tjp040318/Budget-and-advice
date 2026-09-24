import SwiftUI
import UIKit

// MARK: - One continuous shot into the summon (2026-09-24, Docs/FEEL.md W2.14)
//
// A summon was three beats that did not meet: the room's scroll dipped over
// its ring, a system sheet slid up from the foot of the screen, and a SECOND
// scroll stood in the reveal's charge. Summoners War's scroll is one object:
// it lifts off the circle and burns in the light on the same screen. So the
// room's scroll lifts off its ring and flies, growing, to the exact square
// where the reveal's charge will hold it, while the room fades to the
// reveal's own dusk (`SummonShot`, drawn by `SummonView`); the reveal then
// comes up with no slide — the room sets its results inside a transaction
// that disables animations — and its charge comes up round the scroll it was
// handed (`SummonRevealView.openingScrollFrame`, `RevealGeometry.handoff`).
// The numbers both sides draw with live here, off the main actor, so the
// room, the reveal and the tests read one set.

/// Where the reveal draws what the summon room hands it: the figure's line,
/// the charge's heart and the scroll's first pose.
enum RevealGeometry {
    /// The figure's centre line on a single reveal and on a card lifted off
    /// the board, as a share of the width (`SummonStageView.figureLine` reads
    /// it; the stage's camera is solved for it).
    static let figureLine: CGFloat = 0.26
    /// The ten's charge and its board stand in the middle of the frame:
    /// nothing stands on the beam until a featured card lifts off.
    static let boardLine: CGFloat = 0.5
    /// The charge's heart — where the scroll hangs and the rings turn — as a
    /// share of the height.
    static let heart: CGFloat = 0.42
    /// The scroll's side at the charge's first frame, as a share of the
    /// height: `chargeLook`'s `0.24 + 0.07 × grand` on the ground rung.
    static let scrollSide: CGFloat = 0.24
    /// The scroll's tilt at the charge's first frame (`-12 × rest`).
    static let scrollTilt: Double = -12
    /// How long the reveal's own charge takes to come up round a scroll the
    /// room handed it, and the scroll to settle into its own place.
    static let handoffSpan: TimeInterval = 0.3

    /// The beam's line for a reveal of `count` pulls.
    static func line(forPulls count: Int) -> CGFloat {
        count > 1 ? boardLine : figureLine
    }

    /// The scroll's square at the reveal's first frame, in the reveal's
    /// full-screen points for a screen of `size`: the square the room's
    /// flight ends on.
    static func openingScroll(pulls: Int, in size: CGSize) -> CGRect {
        let side: CGFloat = size.height * scrollSide
        let x: CGFloat = size.width * line(forPulls: pulls)
        let y: CGFloat = size.height * heart
        return CGRect(x: x - side / 2, y: y - side / 2, width: side, height: side)
    }

    /// How far the reveal's charge has come up round a handed-over scroll,
    /// `ambient` seconds into it: 0 → 1 over `handoffSpan`, a smoothstep.
    static func handoff(ambient: TimeInterval) -> CGFloat {
        let t: Double = min(1, max(0, ambient / handoffSpan))
        let eased: Double = t * t * (3 - 2 * t)
        return CGFloat(eased)
    }
}

/// The dusk every reveal stands in (2026-09-18) and the colours of its
/// words: the room fades to it under the scroll's flight and the reveal is
/// drawn on it, so the two are one picture.
enum RevealDusk {
    static let zenith = Color(hex: "#12162B")
    static let violet = Color(hex: "#3A2C4E")
    static let ember = Color(hex: "#9C5F33")
    static let ground = Color(hex: "#15110F")
    /// The cream the dusk's quiet words are set in.
    static let ink = Color(hex: "#D9CDB3")

    /// Where the corners fall to ink from: the figure's line, a little
    /// right of it and just under the middle; the middle for the board.
    static func vignetteCentre(line: CGFloat) -> UnitPoint {
        line > 0.4 ? UnitPoint(x: 0.5, y: 0.5) : UnitPoint(x: line + 0.04, y: 0.52)
    }
}

/// The reveal's sky: indigo over a violet dusk and an ember horizon, the
/// ground at the foot.
struct RevealDuskSky: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: RevealDusk.zenith, location: 0.0),
                .init(color: RevealDusk.violet, location: 0.45),
                .init(color: RevealDusk.ember, location: 0.72),
                .init(color: RevealDusk.ground, location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// The corners going back to the ground, centred on what the frame is
/// about rather than on the screen.
struct RevealDuskVignette: View {
    let centre: UnitPoint

    var body: some View {
        RadialGradient(
            colors: [.clear, RevealDusk.ground.opacity(0.10), RevealDusk.ground.opacity(0.42), RevealDusk.ground.opacity(0.82)],
            center: centre,
            startRadius: 0,
            endRadius: 560
        )
    }
}

/// The dusk whole, as the reveal's first frame draws it before any light is
/// in it: the sky and the vignette round the beam's line.
struct RevealDuskScreen: View {
    let line: CGFloat

    var body: some View {
        ZStack {
            RevealDuskSky()
            RevealDuskVignette(centre: RevealDusk.vignetteCentre(line: line))
        }
    }
}

/// The room's scroll on its way to the reveal (W2.14): the square it lifts
/// off, the square it lands on, its tilt at each end, the light round it at
/// each end, and when it left. Its pose is a pure function of the clock
/// (`pose(at:)`), so a main thread held up for a frame never leaves it
/// behind where it should be.
struct SummonShot {
    let serial: Int
    let scroll: ScrollType
    /// How many pulls the reveal it hands over to holds.
    let pulls: Int
    /// The scroll's square over the ring as it lifts, and the reveal's
    /// opening square, in window points.
    let from: CGRect
    let to: CGRect
    /// Its tilt over the ring — the room straightens it as it charges — and
    /// at the reveal's first frame.
    let fromTilt: Double
    let toTilt: Double
    /// The light round it: the scroll's own colour over the ring, the
    /// charge's ground-rung blue-white at the reveal's first frame.
    let fromLight: ChargeRGB
    let toLight: ChargeRGB
    let began: Date

    /// The flight: long enough to follow one object from the altar into the
    /// charge, and together with the room's 0.35 s wind-up shorter than the
    /// wind-up and the sheet's slide it replaces.
    static let length: TimeInterval = 0.55
    /// How high over the straight line the arc lifts, as a share of the
    /// distance flown: it LIFTS off the ring before it travels.
    static let lift: CGFloat = 0.22

    /// Where the scroll is, how big, how turned, and how far along.
    struct Pose: Equatable {
        let centre: CGPoint
        let side: CGFloat
        let tilt: Double
        let progress: CGFloat
    }

    /// 0 → 1 over `length`: eased in and out, so it leaves the ring gently
    /// and settles into the charge.
    static func progress(elapsed: TimeInterval) -> CGFloat {
        let t: Double = min(1, max(0, elapsed / length))
        let back: Double = -2 * t + 2
        let eased: Double = t < 0.5 ? 4 * t * t * t : 1 - back * back * back / 2
        return CGFloat(eased)
    }

    func pose(at date: Date) -> Pose {
        let elapsed: TimeInterval = date.timeIntervalSince(began)
        return pose(progress: Self.progress(elapsed: elapsed))
    }

    /// The pose at `p` along the flight: a quadratic arc from the ring to
    /// the charge through a point above both.
    func pose(progress p: CGFloat) -> Pose {
        let startX: CGFloat = from.midX
        let startY: CGFloat = from.midY
        let endX: CGFloat = to.midX
        let endY: CGFloat = to.midY
        let dx: CGFloat = endX - startX
        let dy: CGFloat = endY - startY
        let distance: CGFloat = (dx * dx + dy * dy).squareRoot()
        let controlX: CGFloat = (startX + endX) / 2
        let controlY: CGFloat = min(startY, endY) - distance * Self.lift
        let q: CGFloat = 1 - p
        let x: CGFloat = q * q * startX + 2 * q * p * controlX + p * p * endX
        let y: CGFloat = q * q * startY + 2 * q * p * controlY + p * p * endY
        let side: CGFloat = from.width + (to.width - from.width) * p
        let tilt: Double = fromTilt + (toTilt - fromTilt) * Double(p)
        return Pose(centre: CGPoint(x: x, y: y), side: side, tilt: tilt, progress: p)
    }

    /// The key window's bounds: where the reveal's full-screen cover will be
    /// laid out, so the flight ends on the square the reveal draws. `.zero`
    /// when no window can be found, and the room then cuts to the reveal.
    @MainActor
    static func windowBounds() -> CGRect {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            if let key = windowScene.windows.first(where: { $0.isKeyWindow }) {
                return key.bounds
            }
        }
        return .zero
    }
}

/// The painted scroll as the room hangs it and the charge holds it: the
/// painting, its sheet's ragged dark ground feathered away along the roll's
/// diagonal (every roll lies corner to corner, lower left to upper right),
/// or the scroll's glyph where no painting shipped. Drawn at one size and
/// scaled by the caller, so its painting is decoded once.
struct SummonScrollArt: View {
    let scroll: ScrollType
    let side: CGFloat

    var body: some View {
        let key: String = ItemArt.key(scroll: scroll)
        if ItemArt.hasPainting(key) {
            ItemIcon(key: key, size: side, glow: false)
                .mask {
                    Capsule()
                        .frame(width: side * 1.34, height: side * 0.44)
                        .rotationEffect(.degrees(-45))
                        .blur(radius: side * 0.025)
                }
        } else {
            Image(systemName: scroll.glyph)
                .font(.system(size: side * 0.4, weight: .black))
                .foregroundStyle(scroll.tint)
                .frame(width: side, height: side)
        }
    }
}
