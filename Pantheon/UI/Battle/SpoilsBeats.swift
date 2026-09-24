import CoreImage
import Foundation
import SwiftUI
import UIKit

// MARK: - The reward box by rarity (Docs/FEEL.md W2.2)
//
// The chest rattles three times, each harder, before its lid creaks up and
// thuds against its hinge and the beam shimmers out of it; the shelf lands
// plain first and the best LAST, every tile a crystal clink one step higher
// up a pentatonic scale, so a big haul plays a melody; a rare glows blue
// under its socket, an epic is lit from behind in violet after a short
// pause, and a legend stops the row for a breath, stands in a column of
// gold with rays turning behind it and drops in from 1.4 with a jolt and a
// rising three notes. The panel stands over a soft still of the fight
// instead of black. Raid's shard colours and the Genshin and Star Rail tells
// are the model; ours landed a Hero relic on drachma's beat (run 245).

/// The chest's opening, in seconds from the tap: three rattles, each harder,
/// then the lid (its creak with it, its thud as it meets the hinge), the
/// beam a fifth of a second into its swing, and the flash that takes the
/// chest a second after the lid. Under Reduce Motion the chest does not
/// rattle and the lid goes at once. `RewardChestView` plays the motion and
/// `BattleResultView.openChest` the sounds on the same numbers.
enum ChestTiming {
    static let rattles: [TimeInterval] = [0, 0.26, 0.52]
    /// Each rattle's swing, in metres of a 1 m chest, and its length.
    static let rattleSwing: [CGFloat] = [0.03, 0.045, 0.065]
    static let rattleLength: TimeInterval = 0.16
    static let lid: TimeInterval = 0.8
    static let calmLid: TimeInterval = 0.2
    /// A chest that does not rattle (`RewardChestView.rattles` off: the
    /// tribute card's, whose grants are listed as it is claimed) jolts four
    /// times and lifts its lid here, as every chest did before W2.2.
    static let plainLid: TimeInterval = 0.32
    static let beamAfterLid: TimeInterval = 0.18
    static let flashAfterLid: TimeInterval = 1.1
    /// The first tile lands this long after the flash.
    static let firstTile: TimeInterval = 0.2

    /// When the lid goes.
    static func lidTime(calm: Bool) -> TimeInterval { calm ? calmLid : lid }
}

/// When each tile of the shelf lands, from the first (W2.2): every
/// `step` apart, an epic after a short pause and a legend after the row
/// has stopped for a breath, its own drop given time before the next.
enum SpoilsTimeline {
    static let step: TimeInterval = 0.14
    static let epicPause: TimeInterval = 0.2
    static let legendPause: TimeInterval = 0.35
    /// A legend's drop and jolt before the next tile.
    static let legendLanding: TimeInterval = 0.3

    /// Seconds from the first tile's landing to each tile's, for `tiers`
    /// in the order they land.
    static func delays(for tiers: [RewardTier]) -> [TimeInterval] {
        var at: TimeInterval = 0
        var landings: [TimeInterval] = []
        for (index, tier) in tiers.enumerated() {
            if index > 0 { at += step }
            if tier == .epic { at += epicPause }
            if tier == .legend { at += legendPause }
            landings.append(at)
            if tier == .legend { at += legendLanding }
        }
        return landings
    }

    /// Seconds from the first tile's landing to the last one settled.
    static func length(of tiers: [RewardTier]) -> TimeInterval {
        let last: TimeInterval = delays(for: tiers).last ?? 0
        return tiers.last == .legend ? last + legendLanding : last
    }
}

/// The shelf's own order and tiers (W2.2).
enum SpoilsShelf {
    /// A spoil's tier: its tile's (`RewardTier.of`), with a scroll known by
    /// its tint when the loot carries no key (an auto-repeat's summary).
    static func tier(of loot: BattleSummary.Loot) -> RewardTier {
        var key: String = loot.key ?? ""
        if key.isEmpty, case .scroll(let scroll) = loot.tint { key = ItemArt.key(scroll: scroll) }
        return RewardTier.of(key: key, relic: loot.relic, stars: loot.stars)
    }

    /// The spoils as they land: plain first and the best last, in the order
    /// they were won within a tier, and the `capacity` best when there are
    /// more (the rest are in the inventory, and the panel says so).
    static func ordered(_ loot: [BattleSummary.Loot], capacity: Int) -> [BattleSummary.Loot] {
        let ranked = loot.enumerated().sorted { first, second in
            let a = tier(of: first.element)
            let b = tier(of: second.element)
            return a == b ? first.offset < second.offset : a < b
        }.map { $0.element }
        return ranked.count > capacity ? Array(ranked.suffix(capacity)) : ranked
    }

    /// The tiers of the shelf as it lands.
    static func tiers(_ loot: [BattleSummary.Loot], capacity: Int) -> [RewardTier] {
        ordered(loot, capacity: capacity).map { tier(of: $0) }
    }
}

/// The light a tile stands in on the shelf (W2.2), drawn behind its socket
/// and added to the dark tray under it: nothing for a plain spoil, a blue
/// pool under a rare one, a violet light behind an epic, and for a legend a
/// column of gold with rays turning behind it. It takes no room of its own.
struct RewardTierAura: View {
    let tier: RewardTier
    let size: CGFloat
    @State private var turn: Double = 0

    private static let blue = Color(hex: "#5FC8FF")
    private static let violet = Color(hex: "#B478FF")
    private static let gold = Color(hex: "#FFCB57")

    var body: some View {
        ZStack {
            switch tier {
            case .plain:
                EmptyView()
            case .rare:
                Ellipse()
                    .fill(RadialGradient(colors: [Self.blue.opacity(0.7), Self.blue.opacity(0.22), Self.blue.opacity(0)],
                                         center: .center, startRadius: 0, endRadius: size * 0.72))
                    .frame(width: size * 1.6, height: size * 0.62)
                    .offset(y: size * 0.4)
            case .epic:
                Circle()
                    .fill(RadialGradient(colors: [Self.violet.opacity(0.62), Self.violet.opacity(0.2), Self.violet.opacity(0)],
                                         center: .center, startRadius: size * 0.12, endRadius: size * 0.95))
                    .frame(width: size * 1.9, height: size * 1.9)
            case .legend:
                AngularGradient(colors: [Self.gold.opacity(0), Self.gold.opacity(0.42), Self.gold.opacity(0),
                                         Self.gold.opacity(0.42), Self.gold.opacity(0), Self.gold.opacity(0.42),
                                         Self.gold.opacity(0), Self.gold.opacity(0.42), Self.gold.opacity(0)],
                                center: .center)
                    .mask {
                        Circle().fill(RadialGradient(colors: [Color.white, Color.white.opacity(0)], center: .center,
                                                     startRadius: size * 0.25, endRadius: size * 1.2))
                    }
                    .frame(width: size * 2.5, height: size * 2.5)
                    .rotationEffect(.degrees(turn))
                LinearGradient(colors: [Self.gold.opacity(0), Self.gold.opacity(0.55), Self.gold.opacity(0.9),
                                        Self.gold.opacity(0.55), Self.gold.opacity(0)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(width: size * 0.6, height: size * 2.7)
                    .blur(radius: size * 0.09)
                Circle()
                    .fill(RadialGradient(colors: [Self.gold.opacity(0.55), Self.gold.opacity(0)], center: .center,
                                         startRadius: 0, endRadius: size * 0.8))
                    .frame(width: size * 1.6, height: size * 1.6)
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
        .onAppear {
            guard tier == .legend, !MotionComfort.isReduced else { return }
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) { turn = 360 }
        }
    }
}

/// The jolt the panel takes as a legend lands (W2.2): down and back, a
/// little side to side, gone in under half a second.
struct LandingJolt {
    var x: CGFloat = 0
    var y: CGFloat = 0
}

/// The still of the fight the reward box stands over (W2.2): the field as
/// the reckoning began, taken from the battle's view (`SCNView.snapshot`)
/// and softened off the main thread — a quarter of its size, blurred and
/// darkened — so the panel stands in the place the fight was won rather
/// than over black.
enum BattleStill {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    /// The long side the still is softened at, in pixels: it is blurred
    /// past any detail a larger one would keep.
    static let pixels: CGFloat = 720
    /// The blur's sigma, a share of the long side, and how far it is darkened.
    static let blurShare: CGFloat = 0.012
    static let darkening: CGFloat = 0.12

    /// `image` softened, handed back on the main thread; nil when Core Image
    /// refuses it.
    static func soften(_ image: UIImage, completion: @escaping (UIImage?) -> Void) {
        let long: CGFloat = max(image.size.width, image.size.height)
        guard long > 0 else {
            completion(nil)
            return
        }
        let scale: CGFloat = min(1, pixels / (long * image.scale))
        let size = CGSize(width: image.size.width * image.scale * scale, height: image.size.height * image.scale * scale)
        DispatchQueue.global(qos: .userInitiated).async {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = true
            let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            var softened: UIImage?
            if let cg = small.cgImage {
                let source = CIImage(cgImage: cg)
                let extent = source.extent
                let sigma = Double(max(extent.width, extent.height) * blurShare)
                let blurred = source.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
                let dimmed = blurred.applyingFilter("CIColorControls", parameters: [
                    kCIInputBrightnessKey: -darkening, kCIInputSaturationKey: 0.85,
                ])
                if let out = context.createCGImage(dimmed, from: extent) {
                    softened = UIImage(cgImage: out)
                }
            }
            DispatchQueue.main.async { completion(softened) }
        }
    }

    /// The realm's painting softened the same way, for a reckoning with no
    /// fight behind it (the tour's demo victory).
    static func painting(_ name: String, completion: @escaping (UIImage?) -> Void) {
        guard let image = BundleArt.uncachedImage(name) else {
            completion(nil)
            return
        }
        soften(image, completion: completion)
    }
}
