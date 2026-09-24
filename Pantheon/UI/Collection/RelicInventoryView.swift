import SwiftUI

// What is left of the relic inventory's file (2026-09-24, the relic redesign;
// Docs/PLAN.md, *Relics the genre's way*): the parts the new screens and the
// cream screens still share. The inventory, the picker, the optimiser, the
// filter sheet, the relic card, the stone sheet, the wearer picker, the drop
// card and the set sheet went, replaced by `RelicsScreen` (Manage and the
// bag) and the card family in `RelicCard.swift`, built from the kit in
// `RelicKit.swift` and `RelicTile.swift`.

// MARK: - The relic as an object

extension RelicQuality {
    /// The app's rarity metal: the same five colours the cards wear, so the
    /// rim of a Legend and the frame of a 5★ card say "rare" the same way.
    var rarity: Rarity { Rarity(rawValue: rawValue + 1) ?? .common }

    /// The quality as ink on cream — the metal's dark stop, which reads
    /// where the glow would not.
    var inkColor: Color {
        switch self {
        case .normal: return Theme.textSecondary
        case .magic: return Color(hex: "#2F7A50")
        case .rare: return Color(hex: "#2A5FA8")
        case .hero: return Color(hex: "#6B34B8")
        case .legend: return Theme.goldDim
        }
    }
}

/// A relic drawn the way the genre draws a rune: the one hexagonal stone
/// in the set's colour with the set's seal engraved (`relic_<set>`, from
/// `tools/relic_art.py`), the quality's metal on the rim (a template tinted
/// here), the grade as stars under it, the level badged on one corner and,
/// where the stone stands alone in a grid or a list, the slot's number on
/// the other. The relic screens draw `RelicTile` (RelicTile.swift) since
/// 2026-09-24; this one stays where a relic stands among other spoils on
/// cream or glass — the reward tile (the chest's shelf, the sweep receipt),
/// the tribute card — and in the awakening rite.
struct RelicIcon: View {
    let relic: Relic
    var size: CGFloat = 44
    var showsStars: Bool = true
    var showsLevel: Bool = true
    /// The slot's number on the top-left corner. Off on the ring, where the
    /// socket's place says it.
    var showsSlot: Bool = false
    /// A gold flare, for the moment a power-up lands.
    var glow: Bool = false

    private var rarity: Rarity { relic.resolvedQuality.rarity }

    var body: some View {
        VStack(spacing: max(1, size * 0.05)) {
            ZStack(alignment: .topTrailing) {
                // The halo: an awakened relic wears a gold ring round the
                // stone with a second, fainter one outside it — the tier
                // above 6★ read at a glance in every grid, the way a card's
                // awakened sun is. Drawn a little wider than the frame, so
                // the hexagon's corners are not cut across.
                if relic.isAwakened {
                    Circle()
                        .strokeBorder(Theme.gold.opacity(0.45), lineWidth: max(0.5, size * 0.02))
                        .frame(width: size * 1.26, height: size * 1.26)
                        .frame(width: size, height: size)
                    Circle()
                        .strokeBorder(Theme.gold, lineWidth: max(1, size * 0.035))
                        .frame(width: size * 1.12, height: size * 1.12)
                        .shadow(color: Theme.gold.opacity(0.7), radius: size * 0.08)
                        .frame(width: size, height: size)
                }
                stone
                    .frame(width: size, height: size)
                    .shadow(color: rarity.glow.opacity(rarity >= .epic ? 0.45 : 0), radius: size * 0.1)
                    .shadow(color: Theme.gold.opacity(glow ? 0.9 : 0), radius: glow ? size * 0.25 : 0)
                if showsLevel, relic.level > 0 {
                    Text("+\(relic.level)")
                        .font(Theme.numeric(max(7, size * 0.2)).weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, max(2, size * 0.06))
                        .padding(.vertical, 1)
                        .background(Capsule().fill(relic.isMaxLevel ? Theme.gold : Theme.plate))
                        .overlay(Capsule().strokeBorder(Theme.goldDim, lineWidth: 0.5))
                        .offset(x: size * 0.1, y: -size * 0.06)
                }
            }
            .overlay(alignment: .topLeading) {
                if showsSlot {
                    Text("\(relic.slot)")
                        .font(Theme.numeric(max(7, size * 0.19)).weight(.bold))
                        .foregroundStyle(Theme.surfaceHigh)
                        .frame(width: max(11, size * 0.3), height: max(11, size * 0.3))
                        .background(Circle().fill(Theme.ink.opacity(0.85)))
                        .overlay(Circle().strokeBorder(Theme.goldDim, lineWidth: 0.5))
                        .offset(x: -size * 0.08, y: -size * 0.06)
                }
            }
            if showsStars {
                StarRow(stars: relic.grade, size: max(5, size * 0.13))
            }
        }
    }

    @ViewBuilder private var stone: some View {
        if BundleArt.exists(relic.stoneImageName) {
            ZStack {
                BundleImage(name: relic.stoneImageName, renderedAt: size)
                    .aspectRatio(contentMode: .fit)
                if let rim = BundleArt.image(Relic.rimImageName) {
                    Image(uiImage: rim)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(rarity.frame)
                }
            }
        } else {
            // A bundle without the art: the set's glyph in the quality's frame.
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .fill(Theme.surfaceHigh)
                Image(systemName: relic.set.glyph)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(Theme.gold)
            }
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .strokeBorder(rarity.frame, lineWidth: max(1, size * 0.04))
            )
        }
    }
}

/// A set's mark for chips and lists: the painted stone itself, small — the
/// gem in the set's colour with its device — the way the genre's set
/// filters show the rune. The line seal, tinted, only where a coloured gem
/// would be wrong (`lineSeal`: the loading screen's gold rule) or in a
/// bundle without the paintings. A device cut down to thirteen pixels was
/// tried and is a blob; the line seal stays a glyph, and the gem's colour
/// with the set's name beside it reads better than either (2026-09-14).
struct RelicSetEmblem: View {
    let set: RelicSet
    var size: CGFloat = 12
    var tint: Color = Theme.gold
    var lineSeal: Bool = false

    var body: some View {
        if !lineSeal, BundleArt.exists(set.stoneImageName) {
            BundleImage(name: set.stoneImageName, renderedAt: size)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else if let image = BundleArt.image(set.emblemImageName) {
            Image(uiImage: image)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        } else {
            Image(systemName: set.glyph)
                .font(.system(size: size * 0.85, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: size, height: size)
        }
    }
}

/// A unit's face in a small gold-rimmed disc: the genre's mark on a worn
/// relic in the grid, which says "equipped, and by whom" without a word.
struct WearerBadge: View {
    let unit: ResolvedUnit
    var size: CGFloat = 16

    var body: some View {
        let art = unit.blueprint.model.portraitName(awakened: unit.unit.isAwakened)
        ZStack {
            Circle().fill(Theme.surfaceHigh)
            if BundleArt.exists(art) {
                BundleImage(name: art, renderedAt: size)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(Theme.gold)
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Theme.gold, lineWidth: 1))
    }
}

/// The quality as a word in its ink, for cream: LEGEND. Nothing draws it
/// since the relic screens went dark (2026-09-24), where a quality is worded
/// in its `tone` (RelicKit.swift); kept for the next cream screen that needs
/// one.
struct RelicQualityTag: View {
    let quality: RelicQuality
    var size: CGFloat = 8

    var body: some View {
        Text(quality.displayName.uppercased())
            .font(Theme.body(size).weight(.black))
            .tracking(0.5)
            .foregroundStyle(quality.inkColor)
            .padding(.horizontal, size * 0.6)
            .padding(.vertical, 1)
            .background(Capsule().fill(quality.inkColor.opacity(0.12)))
    }
}

/// Every axis the genre's Manage Runes narrows by: slot, grade, quality,
/// main stat, sub stats, set, worn state, lock. A set of each so a chip
/// toggles; every sub stat ticked must be on the relic, which is what a
/// hunt for "SPD and CRIT Rate" needs. `RelicsScreen` drives it: the slot
/// rosette, the SET, MAIN and SUB wells and the MORE popover.
struct RelicFilter: Equatable {
    enum Worn: String, CaseIterable {
        case any, unequipped, equipped

        var title: String {
            switch self {
            case .any: return "Any"
            case .unequipped: return "Unequipped"
            case .equipped: return "Equipped"
            }
        }
    }

    var slots: Set<Int> = []
    var grades: Set<Int> = []
    var qualities: Set<RelicQuality> = []
    var mainKinds: Set<StatKind> = []
    var subKinds: Set<StatKind> = []
    var sets: Set<RelicSet> = []
    var worn: Worn = .any
    var lockedOnly = false
    var awakenedOnly = false

    /// How many axes are narrowing the list.
    var activeCount: Int {
        [!slots.isEmpty, !grades.isEmpty, !qualities.isEmpty, !mainKinds.isEmpty, !subKinds.isEmpty,
         !sets.isEmpty, worn != .any, lockedOnly, awakenedOnly].filter { $0 }.count
    }

    var isEmpty: Bool { activeCount == 0 }

    func matches(_ relic: Relic) -> Bool {
        if !slots.isEmpty, !slots.contains(relic.slot) { return false }
        if !grades.isEmpty, !grades.contains(relic.grade) { return false }
        if !qualities.isEmpty, !qualities.contains(relic.resolvedQuality) { return false }
        if !mainKinds.isEmpty, !mainKinds.contains(relic.mainStat.kind) { return false }
        if !subKinds.isEmpty, !subKinds.isSubset(of: Set(relic.subStats.map(\.kind))) { return false }
        if !sets.isEmpty, !sets.contains(relic.set) { return false }
        switch worn {
        case .any: break
        case .unequipped: if relic.equippedBy != nil { return false }
        case .equipped: if relic.equippedBy == nil { return false }
        }
        if lockedOnly, !relic.isLocked { return false }
        if awakenedOnly, !relic.isAwakened { return false }
        return true
    }
}

/// The rite: the stone stands up out of the screen in a pillar of gold
/// light, the halo draws itself round it, and AWAKENED springs in over it —
/// the Hall of Ka's awakening, done for a relic. In SwiftUI rather than on
/// the altar's SceneKit stage, because a relic is a stone and not a figure:
/// there is no model to stand on the dais, and the rays, the glow and the
/// ring are the whole of what the moment needs. A tap ends it early. The
/// relic card (`RelicCard`, RelicCard.swift) plays it over its blurred
/// columns, unchanged from the card before it.
struct RelicAwakeningRite: View {
    let relic: Relic
    let onDone: () -> Void

    @State private var lit = false
    @State private var risen = false
    @State private var haloed = false
    @State private var stamped = false
    @State private var rays: Double = 0

    var body: some View {
        ZStack {
            // 0.85 over the whole screen, strip and all, with the columns
            // blurred under it: at 0.74 over the content alone AWAKENED lay
            // across "Hone & gem" and the strip stayed bright (run 221).
            Color.black.opacity(lit ? 0.85 : 0)
                .ignoresSafeArea()
            AngularGradient(
                colors: [Theme.gold.opacity(0), Theme.gold.opacity(0.22), Theme.gold.opacity(0),
                         Theme.gold.opacity(0.22), Theme.gold.opacity(0), Theme.gold.opacity(0.22),
                         Theme.gold.opacity(0), Theme.gold.opacity(0.22), Theme.gold.opacity(0)],
                center: .center
            )
            .scaleEffect(2.4)
            .rotationEffect(.degrees(rays))
            .opacity(lit ? 1 : 0)
            .blendMode(.plusLighter)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            RadialGradient(
                colors: [Theme.gold.opacity(lit ? 0.38 : 0), Theme.gold.opacity(lit ? 0.12 : 0), .clear],
                center: .center, startRadius: 0, endRadius: lit ? 320 : 120
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .trim(from: 0, to: haloed ? 1 : 0)
                        .stroke(Theme.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 176, height: 176)
                        .shadow(color: Theme.gold.opacity(0.8), radius: 10)
                    RelicIcon(relic: relic, size: 120, showsStars: false, showsLevel: false, glow: lit)
                        .scaleEffect(risen ? 1 : 0.55)
                        .opacity(risen ? 1 : 0)
                }
                Text("AWAKENED")
                    .font(Theme.display(34))
                    .tracking(4)
                    .foregroundStyle(Theme.gold)
                    .shadow(color: Theme.gold.opacity(0.6), radius: 14)
                    .scaleEffect(stamped ? 1 : 1.7)
                    .opacity(stamped ? 1 : 0)
                Text("A fifth sub stat opens. Take either one.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.marble)
                    .opacity(stamped ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDone() }
        .onAppear { play() }
    }

    private func play() {
        withAnimation(.easeOut(duration: 0.35)) { lit = true }
        withAnimation(.linear(duration: 18).repeatForever(autoreverses: false)) { rays = 360 }
        withAnimation(Motion.celebrate.delay(0.1)) { risen = true }
        withAnimation(.easeInOut(duration: 0.7).delay(0.5)) { haloed = true }
        withAnimation(Motion.celebrate.delay(1.05)) { stamped = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            AudioLibrary.shared.play(.starTick, volume: 0.8)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            Juice.haptic(.medium)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closesAfter) { onDone() }
    }

    /// How long the rite stands before it closes itself: 2.8 s, and 6 under
    /// the CI tour, which photographs it. AWAKENED and its caption have
    /// settled by about 1.4 s and nothing moves after but the rays, so the
    /// tour's rite is the same peak held longer. A screenshot on CI's
    /// runner lands two to three seconds after it is asked for, and the
    /// 2.8-s rite was gone by then: run 234's 40-a, asked for 1.3 s after
    /// the cue, came out byte for byte the 40-b.
    private static let closesAfter: TimeInterval =
        ProcessInfo.processInfo.arguments.contains("-tour") ? 6.0 : 2.8
}
