import Foundation
import ImageIO
import SwiftUI
import UIKit

// MARK: - The way into a fight (Docs/FEEL.md W2.24)
//
// Fight or Begin used to slide a system cover up over the map, and the fight
// opened under a black veil while its stage built and its first frames
// compiled (run 243's first battle frame was white). Summoners War and Raid
// put a loading card between the map and the fight; Epic Seven a painting
// with the stage's name. Here:
//
// - The cover opens with no slide (`BattleCover.open`): the screen dips at
//   once to black with the carved card on it, and the realm's painting fades
//   up behind the card.
// - The card holds at least `StageCardTiming.minimumHold` and until the
//   battle has drawn its first complete frames — the stage, and everything
//   the fight can draw, drawn once under the card (`VFXLibrary.predraw`,
//   stepped by `BattleSceneController`) — then dissolves onto the field,
//   and only then does the fight's opening play: its horn call, a boss's
//   rise (`BattleSceneController.revealField`).
// - Leaving, the same card in reverse: it rises over the reckoning, holds a
//   breath, and the cover closes with no slide.
// - An auto-repeat's later runs build under no card.
//
// Its moving parts are Core Animation, not SwiftUI: the build holds the main
// thread for anything from a tenth of a second to four (run 245), a SwiftUI
// animation freezes with the main thread, and a Core Animation one runs on
// the render server. So the card's entrance, the painting's slow push, the
// glow's breath and the light across the plate all keep moving while the
// fight is built behind them. The words are drawn once into the plate's
// image in the game's own faces.

/// What the stage card says: the realm and the place over the stage's name
/// (or the rival's), the waves and the tier under it, and the stage's power
/// beside the team's when both are known.
struct StageCardInfo: Equatable {
    var eyebrow: String
    var title: String
    var detail: String
    var theirLabel: String
    var theirPower: Int?
    var ourPower: Int?
    /// The realm's painting (`BattleEnvironment.backdropName`).
    var painting: String
}

/// The card's clock.
enum StageCardTiming {
    /// The least the card stands, from the moment it is up (the spec's
    /// floor): long enough to read the stage's name and never longer than
    /// the build except by this.
    static let minimumHold: TimeInterval = 0.6
    /// A beat after the card is up before the fight is built, so the card's
    /// first frame is committed and its entrance is running on the render
    /// server before the build takes the main thread.
    static let buildDelay: TimeInterval = 0.06
    /// The longest the card waits, once the build is done, for the stage to
    /// be drawn: the veil's old limit. A renderer that draws nothing must not
    /// hold the fight for good.
    static let limit: TimeInterval = 5
    /// Under `-tour-card`, how long the card stands once the stage has been
    /// drawn, for its frame (a screenshot of a live fight lands six to nine
    /// seconds after it is asked for, run 245).
    static let tourHold: TimeInterval = 16
    /// Leaving the fight: the card's arrival and the breath it holds before
    /// the cover closes.
    static let leaveArrival: TimeInterval = 0.38
    static let leaveHold: TimeInterval = 0.3
    /// Under Reduce Motion the card arrives as a plain, quicker fade and
    /// holds a shorter breath. The plate's own fade (`plateCalmFade` after
    /// `plateDelay`) and the shade's (`shadeFade` after the same delay) end
    /// inside the wait, so the cover never closes on a card still arriving
    /// (review, 2026-09-24: it closed at 0.3 s with the card at nine tenths).
    static let calmLeaveArrival: TimeInterval = 0.2
    static let calmLeaveHold: TimeInterval = 0.25
    /// The card's parts as it comes up: the shade and the plate start a
    /// beat after the card, the plate springing in (a fade under Reduce
    /// Motion).
    static let plateDelay: TimeInterval = 0.05
    static let shadeFade: TimeInterval = 0.35
    static let plateCalmFade: TimeInterval = 0.25

    /// The dissolve onto the field: shorter at ×3 and under Reduce Motion.
    static func dissolve(speed: Double, calm: Bool) -> TimeInterval {
        if calm { return 0.3 }
        return Juice.isFast(speed) ? 0.32 : 0.5
    }

    /// How long the card takes to fade up over the reckoning on the way out.
    static func arrivalOut(calm: Bool) -> TimeInterval { calm ? calmLeaveArrival : leaveArrival }

    /// How long the way out waits before the cover closes: the card's
    /// arrival, then its breath.
    static func leaveWait(calm: Bool) -> TimeInterval {
        calm ? calmLeaveArrival + calmLeaveHold : leaveArrival + leaveHold
    }
}

/// A battle's cover opens and closes with no slide (W2.24): the binding is
/// set, and the dismissal made, inside a transaction that disables
/// animations, which SwiftUI honours for a full-screen cover's presentation.
/// Every site that opens a `BattleView` goes through `open`.
enum BattleCover {
    static func open(_ change: () -> Void) {
        var instantly = Transaction()
        instantly.disablesAnimations = true
        withTransaction(instantly) { change() }
    }

    static func close(_ dismissal: () -> Void) {
        var instantly = Transaction()
        instantly.disablesAnimations = true
        withTransaction(instantly) { dismissal() }
    }
}

/// The card over the whole screen: black, the realm's painting fading up and
/// pushing in, and the carved plate rising in the middle with a glow behind
/// it and a light running across it. `reversed` is the way out: the whole
/// card fades up over the reckoning instead of standing at once over black.
/// `dissolving` sends it off onto the field.
struct StageCardView: UIViewRepresentable {
    let info: StageCardInfo
    var reversed: Bool = false
    var dissolving: Bool = false
    var dissolve: TimeInterval = 0.5

    final class Coordinator {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> StageCardCanvas {
        StageCardCanvas(info: info, reversed: reversed, calm: MotionComfort.isReduced)
    }

    func updateUIView(_ view: StageCardCanvas, context: Context) {
        if dissolving { view.playExit(over: dissolve) }
    }

    /// The painting and the plate let go as the card leaves: nothing of the
    /// card outlives it (the decoded painting is 9 MB at 2048 pixels).
    static func dismantleUIView(_ view: StageCardCanvas, coordinator: Coordinator) {
        view.releaseArt()
    }
}

/// The card's own view: every moving part a Core Animation layer's.
final class StageCardCanvas: UIView {
    private let info: StageCardInfo
    private let reversed: Bool
    private let calm: Bool
    private let painting = UIView()
    private let shade = UIView()
    private let card = UIView()
    private let glow = UIView()
    private let plate = UIView()
    private let sheen = UIView()
    private let sheenMask = UIView()
    private let band = UIView()
    private var plateSize: CGSize = .zero
    private var entered = false
    private var exited = false
    private var released = false

    init(info: StageCardInfo, reversed: Bool, calm: Bool) {
        self.info = info
        self.reversed = reversed
        self.calm = calm
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        // The card takes every touch while it stands: nothing under it is
        // there to be touched yet.
        isUserInteractionEnabled = true
        painting.alpha = 0
        painting.clipsToBounds = true
        painting.layer.contentsGravity = .resizeAspectFill
        shade.alpha = 0
        shade.layer.contentsGravity = .resize
        card.alpha = 0
        glow.layer.contentsGravity = .resize
        glow.alpha = 0.55
        band.layer.contentsGravity = .resize
        addSubview(painting)
        addSubview(shade)
        addSubview(card)
        card.addSubview(glow)
        card.addSubview(plate)
        card.addSubview(sheen)
        sheen.addSubview(band)
        sheen.mask = sheenMask

        let plateImage = StageCardArt.plate(for: info)
        plateSize = plateImage.size
        plate.layer.contents = plateImage.cgImage
        // The light runs over the plate's own pixels and nowhere else.
        sheenMask.layer.contents = plateImage.cgImage
        glow.layer.contents = StageCardArt.glow().cgImage
        band.layer.contents = StageCardArt.band().cgImage
        shade.layer.contents = StageCardArt.shade().cgImage
        if reversed { alpha = 0 }

        StageCardArt.decodePainting(info.painting) { [weak self] image in
            guard let self, let image, !self.released else { return }
            self.showPainting(image)
        }
    }

    required init?(coder: NSCoder) { nil }

    /// A layout that ran before the card was in a window started nothing
    /// (`playEntrance` waits for one): ask for another as it arrives, so the
    /// plate never stands invisible at alpha 0.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, !entered { setNeedsLayout() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.bounds
        // Bounds and centre, never frames, on the views a transform moves.
        painting.bounds = CGRect(origin: .zero, size: bounds.size)
        painting.center = CGPoint(x: bounds.midX, y: bounds.midY)
        shade.frame = bounds
        card.bounds = CGRect(origin: .zero, size: plateSize)
        card.center = CGPoint(x: bounds.midX, y: bounds.height * 0.52)
        glow.frame = CGRect(origin: .zero, size: plateSize).insetBy(dx: -110, dy: -80)
        plate.frame = CGRect(origin: .zero, size: plateSize)
        sheen.frame = CGRect(origin: .zero, size: plateSize)
        sheenMask.frame = sheen.bounds
        band.bounds = CGRect(x: 0, y: 0, width: 110, height: plateSize.height * 1.8)
        band.center = CGPoint(x: -140, y: plateSize.height / 2)
        band.transform = .init(rotationAngle: 0.32)
        if !entered, window != nil, bounds.width > 0 {
            entered = true
            playEntrance()
        }
    }

    /// The plate rises into place and the glow and the light start; the
    /// painting comes up by itself once it is decoded (`showPainting`). On
    /// the way out of a fight the whole card fades up first.
    private func playEntrance() {
        if reversed {
            UIView.animate(withDuration: StageCardTiming.arrivalOut(calm: calm), delay: 0,
                           options: [.curveEaseOut, .beginFromCurrentState]) {
                self.alpha = 1
            }
        }
        UIView.animate(withDuration: StageCardTiming.shadeFade, delay: StageCardTiming.plateDelay,
                       options: [.curveEaseOut]) {
            self.shade.alpha = 1
        }
        if calm {
            UIView.animate(withDuration: StageCardTiming.plateCalmFade, delay: StageCardTiming.plateDelay,
                           options: [.curveEaseOut]) {
                self.card.alpha = 1
            }
            return
        }
        card.transform = .init(translationX: 0, y: 14).scaledBy(x: 0.94, y: 0.94)
        UIView.animate(withDuration: 0.5, delay: StageCardTiming.plateDelay, usingSpringWithDamping: 0.84,
                       initialSpringVelocity: 0, options: [.beginFromCurrentState]) {
            self.card.alpha = 1
            self.card.transform = .identity
        }
        UIView.animate(withDuration: 2.2, delay: 0.4,
                       options: [.repeat, .autoreverse, .curveEaseInOut, .allowUserInteraction]) {
            self.glow.alpha = 1
        }
        // The light across the plate: once as it settles, then every
        // 2.6 seconds while the card stands.
        let sweep = CAKeyframeAnimation(keyPath: "position.x")
        let from = NSNumber(value: Double(-140))
        let to = NSNumber(value: Double(plateSize.width + 140))
        sweep.values = [from, to, to]
        sweep.keyTimes = [0, 0.3, 1] as [NSNumber]
        sweep.duration = 2.6
        sweep.beginTime = CACurrentMediaTime() + 0.42
        sweep.repeatCount = .infinity
        sweep.fillMode = .backwards
        band.layer.add(sweep, forKey: "sweep")
    }

    /// The realm's painting fades up behind the plate and pushes slowly in.
    private func showPainting(_ image: CGImage) {
        painting.layer.contents = image
        UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
            self.painting.alpha = 1
        }
        guard !calm else { return }
        UIView.animate(withDuration: 9, delay: 0, options: [.curveLinear, .beginFromCurrentState]) {
            self.painting.transform = .init(scaleX: 1.07, y: 1.07)
        }
    }

    /// The card dissolves onto the field: the plate lifts away, and the whole
    /// card — its black, its painting — fades to show the stage behind it.
    func playExit(over duration: TimeInterval) {
        guard !exited else { return }
        exited = true
        UIView.animate(withDuration: duration * 0.55, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            self.card.alpha = 0
            if !self.calm {
                self.card.transform = .init(translationX: 0, y: -10).scaledBy(x: 1.04, y: 1.04)
            }
        }
        UIView.animate(withDuration: duration, delay: duration * 0.15, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.alpha = 0
        }
    }

    /// Lets go of every picture the card drew with.
    func releaseArt() {
        released = true
        band.layer.removeAllAnimations()
        for view in [painting, shade, glow, plate, sheenMask, band] {
            view.layer.contents = nil
        }
    }
}

/// The card's pictures, drawn once each time a card is made.
enum StageCardArt {
    /// The plate's width, in points.
    static let width: CGFloat = 470

    // The faces: the game's own, with the system's in their place when a
    // bundle is missing them.
    private static func carved(_ size: CGFloat) -> UIFont {
        UIFont(name: Theme.carvedHeavyFace, size: size) ?? UIFont.systemFont(ofSize: size, weight: .black)
    }

    private static func label(_ size: CGFloat) -> UIFont {
        UIFont(name: "Manrope-ExtraBold", size: size) ?? UIFont.systemFont(ofSize: size, weight: .heavy)
    }

    private static func figures(_ size: CGFloat) -> UIFont {
        UIFont(name: Theme.numberFace, size: size) ?? UIFont.monospacedDigitSystemFont(ofSize: size, weight: .bold)
    }

    private static let eyebrowInk = UIColor(hex: "#E0C275") ?? .yellow
    private static let dimInk = UIColor(hex: "#C9BB9E") ?? .lightGray
    private static let cream = UIColor(hex: "#F5EBD2") ?? .white
    private static let metSuccess = UIColor(hex: "#A6D98A") ?? .green
    private static let shortDanger = UIColor(hex: "#F2939F") ?? .red
    private static let rimGold = UIColor(hex: "#D2B26A") ?? .yellow
    private static let edgeInk = UIColor(red: 0.07, green: 0.05, blue: 0.03, alpha: 0.95)

    /// The carved plate with every word on it: dark glass in a gold rim,
    /// the eyebrow between two rules, the title in carved gold, the detail,
    /// and the two powers under a hairline with a diamond on it.
    static func plate(for info: StageCardInfo) -> UIImage {
        let margin: CGFloat = 28
        let inner: CGFloat = width - 2 * margin
        let eyebrow = NSAttributedString(string: info.eyebrow, attributes: [
            .font: label(11), .foregroundColor: eyebrowInk, .kern: CGFloat(2.6),
        ])
        let detail = NSAttributedString(string: info.detail, attributes: [
            .font: label(12), .foregroundColor: dimInk, .kern: CGFloat(1.8),
        ])
        // The title at 30 points, smaller only as far as it must be to fit.
        var titleSize: CGFloat = 30
        var titleWidth: CGFloat = NSAttributedString(string: info.title, attributes: [
            .font: carved(titleSize), .kern: CGFloat(1.2),
        ]).size().width
        if titleWidth > inner {
            titleSize = max(18, titleSize * inner / titleWidth)
            titleWidth = NSAttributedString(string: info.title, attributes: [
                .font: carved(titleSize), .kern: CGFloat(1.2),
            ]).size().width
        }
        let titleFont = carved(titleSize)
        let titleFill = NSAttributedString(string: info.title, attributes: [
            .font: titleFont, .foregroundColor: UIColor.white, .kern: CGFloat(1.2),
        ])
        let titleEdge = NSAttributedString(string: info.title, attributes: [
            .font: titleFont, .kern: CGFloat(1.2),
            .strokeColor: edgeInk,
            .strokeWidth: CGFloat(2 * 2.2 / titleSize * 100),
        ])
        let titleHeight: CGFloat = titleFill.size().height
        let powers: Bool = info.theirPower != nil || info.ourPower != nil

        let top: CGFloat = 22
        let eyebrowHeight: CGFloat = eyebrow.size().height
        let titleTop: CGFloat = top + eyebrowHeight + 8
        let detailTop: CGFloat = titleTop + titleHeight + 4
        let detailHeight: CGFloat = info.detail.isEmpty ? 0 : detail.size().height
        let dividerY: CGFloat = detailTop + detailHeight + 14
        let rowTop: CGFloat = dividerY + 13
        let rowHeight: CGFloat = 46
        let height: CGFloat = ceil(powers ? rowTop + rowHeight + 18 : detailTop + detailHeight + 22)
        let size = CGSize(width: width, height: height)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = max(2, UIScreen.main.scale)
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let bounds = CGRect(origin: .zero, size: size)
            // The glass: a dark plate, a little deeper at the foot.
            let outline = UIBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), cornerRadius: 16)
            cg.saveGState()
            outline.addClip()
            drawVertical(in: cg, rect: bounds, colours: [
                (UIColor(hex: "#241B14") ?? .black).withAlphaComponent(0.9),
                (UIColor(hex: "#120D0A") ?? .black).withAlphaComponent(0.94),
            ])
            cg.restoreGState()
            // The rim in gold, bright at the crown and bronze at the foot,
            // and a hairline inside it.
            cg.saveGState()
            cg.addPath(outline.cgPath)
            cg.setLineWidth(1.6)
            cg.replacePathWithStrokedPath()
            cg.clip()
            drawVertical(in: cg, rect: bounds, colours: [
                UIColor(hex: "#F3DFA6") ?? .yellow, UIColor(hex: "#B08A2E") ?? .brown, UIColor(hex: "#6E5319") ?? .brown,
            ])
            cg.restoreGState()
            let hairline = UIBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 6), cornerRadius: 12)
            rimGold.withAlphaComponent(0.26).setStroke()
            hairline.lineWidth = 0.75
            hairline.stroke()
            // A small diamond on each side of the rim: the carving's studs.
            for x in [CGFloat(1.5), width - 1.5] {
                diamond(at: CGPoint(x: x, y: height / 2), radius: 4.5, in: cg)
            }

            // The eyebrow between its two rules.
            let eyebrowSize = eyebrow.size()
            let eyebrowX: CGFloat = (width - eyebrowSize.width) / 2
            eyebrow.draw(at: CGPoint(x: eyebrowX, y: top))
            let ruleY: CGFloat = top + eyebrowSize.height / 2
            rule(from: margin, to: eyebrowX - 12, y: ruleY, fadingLeft: true, in: cg)
            rule(from: eyebrowX + eyebrowSize.width + 12, to: width - margin, y: ruleY, fadingLeft: false, in: cg)

            // The title, carved: its dark edge with a shadow under it, then
            // the fill in gold through a transparency layer.
            let titleOrigin = CGPoint(x: (width - titleWidth) / 2, y: titleTop)
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 5, color: UIColor.black.withAlphaComponent(0.85).cgColor)
            titleEdge.draw(at: titleOrigin)
            cg.restoreGState()
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            titleFill.draw(at: titleOrigin)
            cg.setBlendMode(.sourceIn)
            drawVertical(in: cg, rect: CGRect(origin: titleOrigin, size: CGSize(width: titleWidth, height: titleHeight)),
                         colours: [
                            UIColor(hex: "#FFF3C8") ?? .white, UIColor(hex: "#EDCB6C") ?? .yellow,
                            UIColor(hex: "#B8902F") ?? .brown, UIColor(hex: "#7E5C1B") ?? .brown,
                         ])
            cg.setBlendMode(.normal)
            cg.endTransparencyLayer()

            if !info.detail.isEmpty {
                let detailSize = detail.size()
                detail.draw(at: CGPoint(x: (width - detailSize.width) / 2, y: detailTop))
            }

            guard powers else { return }
            // The hairline and its diamond.
            rule(from: margin + 40, to: width / 2 - 10, y: dividerY, fadingLeft: true, in: cg)
            rule(from: width / 2 + 10, to: width - margin - 40, y: dividerY, fadingLeft: false, in: cg)
            diamond(at: CGPoint(x: width / 2, y: dividerY), radius: 3.5, in: cg)

            // The powers: the field's on the left, the team's on the right in
            // green when it meets it and rose when it falls short; VS between.
            let met: Bool = (info.ourPower ?? 0) >= (info.theirPower ?? 0)
            column(label: info.theirLabel, value: info.theirPower, ink: cream, centre: width * 0.28, top: rowTop, in: cg)
            column(label: "YOUR TEAM", value: info.ourPower, ink: met ? metSuccess : shortDanger,
                   centre: width * 0.72, top: rowTop, in: cg)
            let versus = NSAttributedString(string: "VS", attributes: [
                .font: carved(15), .foregroundColor: eyebrowInk, .kern: CGFloat(1.5),
            ])
            let versusSize = versus.size()
            versus.draw(at: CGPoint(x: (width - versusSize.width) / 2, y: rowTop + 16))
        }
    }

    /// A label over a figure, centred on `centre`.
    private static func column(label text: String, value: Int?, ink: UIColor, centre: CGFloat, top: CGFloat, in cg: CGContext) {
        let caption = NSAttributedString(string: text, attributes: [
            .font: label(11), .foregroundColor: dimInk, .kern: CGFloat(1.8),
        ])
        let captionSize = caption.size()
        caption.draw(at: CGPoint(x: centre - captionSize.width / 2, y: top))
        let figure = NSAttributedString(string: value.map { $0.formatted() } ?? "—", attributes: [
            .font: figures(22), .foregroundColor: ink,
        ])
        let figureSize = figure.size()
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 1), blur: 3, color: UIColor.black.withAlphaComponent(0.7).cgColor)
        figure.draw(at: CGPoint(x: centre - figureSize.width / 2, y: top + captionSize.height + 2))
        cg.restoreGState()
    }

    /// A gold rule, one point high, fading to nothing at its outer end.
    private static func rule(from start: CGFloat, to end: CGFloat, y: CGFloat, fadingLeft: Bool, in cg: CGContext) {
        guard end - start > 4 else { return }
        let rect = CGRect(x: start, y: y - 0.5, width: end - start, height: 1)
        let gold = rimGold.withAlphaComponent(0.85)
        let clear = rimGold.withAlphaComponent(0)
        let colours = (fadingLeft ? [clear, gold] : [gold, clear]).map { $0.cgColor } as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1]) else { return }
        cg.saveGState()
        cg.clip(to: rect)
        cg.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: y), end: CGPoint(x: rect.maxX, y: y), options: [])
        cg.restoreGState()
    }

    /// A small gold diamond with a dark edge.
    private static func diamond(at centre: CGPoint, radius: CGFloat, in cg: CGContext) {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: centre.x, y: centre.y - radius))
        path.addLine(to: CGPoint(x: centre.x + radius, y: centre.y))
        path.addLine(to: CGPoint(x: centre.x, y: centre.y + radius))
        path.addLine(to: CGPoint(x: centre.x - radius, y: centre.y))
        path.close()
        (UIColor(hex: "#EDCB6C") ?? .yellow).setFill()
        path.fill()
        edgeInk.setStroke()
        path.lineWidth = 0.8
        path.stroke()
    }

    /// A vertical gradient through `colours`, evenly spaced, over `rect`.
    private static func drawVertical(in cg: CGContext, rect: CGRect, colours: [UIColor]) {
        guard colours.count > 1 else { return }
        let stops: [CGFloat] = (0..<colours.count).map { CGFloat($0) / CGFloat(colours.count - 1) }
        let cgColours = colours.map { $0.cgColor } as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColours, locations: stops) else { return }
        cg.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY),
                              end: CGPoint(x: rect.midX, y: rect.maxY),
                              options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// The warm glow behind the plate: gold at the heart, gone by the edge.
    static func glow() -> UIImage {
        let size = CGSize(width: 256, height: 160)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let gold = UIColor(hex: "#D9AE4C") ?? .yellow
            let colours = [gold.withAlphaComponent(0.42).cgColor, gold.withAlphaComponent(0.12).cgColor,
                           gold.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours,
                                            locations: [0, 0.5, 1]) else { return }
            cg.translateBy(x: size.width / 2, y: size.height / 2)
            cg.scaleBy(x: 1, y: size.height / size.width)
            cg.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero,
                                  endRadius: size.width / 2, options: [])
        }
    }

    /// The light that runs across the plate: a soft upright band.
    static func band() -> UIImage {
        let size = CGSize(width: 64, height: 16)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let warm = UIColor(hex: "#FFF3C8") ?? .white
            let colours = [warm.withAlphaComponent(0).cgColor, warm.withAlphaComponent(0.2).cgColor,
                           warm.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours,
                                            locations: [0, 0.5, 1]) else { return }
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
        }
    }

    /// The shade over the painting: darker at the top and the foot, and a
    /// pool of shadow behind the plate so the words stand on it.
    static func shade() -> UIImage {
        let size = CGSize(width: 160, height: 90)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let black = UIColor.black
            let vertical = [black.withAlphaComponent(0.62).cgColor, black.withAlphaComponent(0.22).cgColor,
                            black.withAlphaComponent(0.3).cgColor, black.withAlphaComponent(0.72).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: vertical,
                                         locations: [0, 0.35, 0.65, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
            let pool = [black.withAlphaComponent(0.38).cgColor, black.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: pool, locations: [0, 1]) {
                cg.saveGState()
                cg.translateBy(x: size.width / 2, y: size.height * 0.52)
                cg.scaleBy(x: 1, y: 0.55)
                cg.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0, endCenter: .zero,
                                      endRadius: size.width * 0.42, options: [])
                cg.restoreGState()
            }
        }
    }

    /// The realm's painting decoded off the main thread at about the
    /// screen's own pixels (2048 at most, the size the paintings ship at)
    /// and kept by nothing but the card, handed back on the main thread.
    static func decodePainting(_ name: String, completion: @escaping (CGImage?) -> Void) {
        guard let url = BundleArt.url(name) else {
            completion(nil)
            return
        }
        let screen = UIScreen.main.bounds.size
        let longest = Int(max(screen.width, screen.height) * UIScreen.main.scale)
        let pixels: Int = min(2048, max(1024, longest))
        DispatchQueue.global(qos: .userInitiated).async {
            var image: CGImage?
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixels,
                ]
                image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            }
            DispatchQueue.main.async { completion(image) }
        }
    }
}
