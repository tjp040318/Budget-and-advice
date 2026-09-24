import SwiftUI

// MARK: - The Codex's parts (2026-09-23; Docs/CODEX.md)
//
// The book (`CodexView`) and a form's page (`CodexPageView`) are built from
// these and from the house's glass parts (Glass.swift): a pantheon's row on
// the rail, a family's row of five forms, a form's tile and its large card, a
// pantheon's milestone track, a road to a form. Every one takes plain values
// and no store, so it can be read — and judged — on its own.

/// A page to open: a family, one of its elements and one face. Pushed on the
/// book's navigation stack.
struct CodexPageRequest: Hashable {
    let familyKey: String
    let element: Element
    let kind: CodexFormKind
}

extension CodexPageRequest {
    /// The page of one blueprint's form — `anubis_ember` — for the tour and
    /// for any screen that wants to open the book on a unit it holds.
    init?(blueprintID: String, kind: CodexFormKind = .base) {
        guard let blueprint = UnitDatabase.blueprint(blueprintID) else { return nil }
        self.init(familyKey: RegaliaService.familyKey(of: blueprintID), element: blueprint.element, kind: kind)
    }
}

/// The paintings and marks the book draws, in one place.
enum CodexArt {

    /// The room each pantheon's pages stand in: its own realm, painted and
    /// already in the bundle. Egypt's is the Hall of Two Truths, where the
    /// dead are weighed and recorded — the one painting in the game that is
    /// a hall of records; the rest are their realms' gates and courts.
    static func painting(for pantheon: Pantheon) -> String {
        switch pantheon {
        case .egyptian: return "hall_of_two_truths_bg"
        case .greek: return "olympus_gate_bg"
        case .norse: return "yggdrasil_roots_bg"
        case .roman: return "forum_rome_bg"
        case .chinese: return "peach_garden_bg"
        default: return "summon_hall_bg"
        }
    }

    /// The point of each square painting kept in view on the landscape band
    /// (750 × 329 on an iPhone 16 Pro, 44% of the painting's height): the
    /// hall's receding columns, Olympus's arch over the cloud, the World
    /// Tree's trunk, the Forum's arch and temples (the bazaar's measured
    /// 0.26), the Peach Garden's pavilion and path.
    static func focus(for pantheon: Pantheon) -> UnitPoint {
        switch pantheon {
        case .egyptian: return UnitPoint(x: 0.5, y: 0.45)
        case .greek: return UnitPoint(x: 0.5, y: 0.30)
        case .norse: return UnitPoint(x: 0.5, y: 0.35)
        case .roman: return UnitPoint(x: 0.5, y: 0.26)
        case .chinese: return UnitPoint(x: 0.5, y: 0.40)
        default: return .center
        }
    }

    /// A dark wash pushing the painting back under a dense table of faces:
    /// deeper on the two pale paintings (Olympus's cloud and the Peach
    /// Garden's blossom), where cream words on glass are hardest to read.
    static func wash(for pantheon: Pantheon) -> Color {
        switch pantheon {
        case .greek, .chinese: return Color.black.opacity(0.45)
        default: return Color.black.opacity(0.28)
        }
    }

    static let moteColor = Color(hex: "#FFE29A")

    /// The face on a pantheon's rail row: its banner's featured family, in
    /// fire.
    static func emblem(for pantheon: Pantheon) -> String? {
        let name: String
        switch pantheon {
        case .egyptian: name = "portrait_anubis_ember"
        case .greek: name = "portrait_zeus_ember"
        case .norse: name = "portrait_odin_ember"
        case .roman: name = "portrait_mars_ember"
        case .chinese: name = "portrait_sun_wukong_ember"
        default: return nil
        }
        return BundleArt.exists(name) ? name : nil
    }

    /// The painted scroll a tier's marker carries: its prize's own.
    static func prizeKey(for tier: CodexTier) -> String {
        switch tier {
        case .quarter: return "scroll_pantheonic"
        case .half: return "scroll_divine"
        case .threeQuarters, .whole: return "scroll_light_dark"
        }
    }

    /// A page's card: the awakened card for an awakened face where it has
    /// shipped (`ModelSpec.portraitName(awakened:)` falls back to the base
    /// card), nil before a family has cards.
    static func portrait(for entry: CodexEntry) -> String? {
        guard let blueprint = entry.blueprint else { return nil }
        let name = blueprint.model.portraitName(awakened: entry.kind == .awakened)
        return BundleArt.exists(name) ? name : nil
    }

    /// The form as the game would hand it over — level 1, nothing worn,
    /// awakened for an awakened page — so its skills read exactly as the
    /// unit sheet reads them (`ProgressionService.resolve`).
    static func preview(_ entry: CodexEntry) -> ResolvedUnit? {
        guard let blueprint = entry.blueprint else { return nil }
        let unit = Unit(blueprint: blueprint, awakened: entry.kind == .awakened)
        return ProgressionService.resolve(unit, blueprint: blueprint, equipped: [])
    }

    /// The shadow an unrecorded card is drawn in: drained of colour, warmed
    /// toward bronze, then darkened — the card still there, its shape and
    /// its pose, but not its colours. Judged against a bronze etching on real
    /// cards before it was chosen (Docs/CODEX.md, *The unseen card*).
    static let shadowTint = Color(hex: "#C9B48E")
    static let shadowDepth: Double = 0.62
}

/// A page's painting at a square size: the card itself once its form is
/// recorded; until then the same card in shadow under a carved "?".
struct CodexPortrait: View {
    let entry: CodexEntry
    let recorded: Bool
    let size: CGFloat

    var body: some View {
        ZStack {
            if let name = CodexArt.portrait(for: entry) {
                if recorded {
                    PortraitPainting(name: name, size: size)
                        .frame(width: size, height: size)
                } else {
                    PortraitPainting(name: name, size: size)
                        .frame(width: size, height: size)
                        .saturation(0)
                        .colorMultiply(CodexArt.shadowTint)
                        .overlay(Color.black.opacity(CodexArt.shadowDepth))
                }
            } else {
                // Before a family's cards ship: the element's glow, as every
                // card draws it pre-art.
                RadialGradient(
                    colors: [entry.element.color.opacity(recorded ? 0.75 : 0.3), Color(hex: "#17120E")],
                    center: .init(x: 0.5, y: 0.38),
                    startRadius: 0,
                    endRadius: size * 0.85
                )
            }
            if !recorded {
                Text("?")
                    .font(Theme.display(size * 0.42))
                    .carved(glow: false)
                    .shadow(color: .black.opacity(0.8), radius: 2)
            }
        }
        .frame(width: size, height: size)
        .clipped()
        .allowsHitTesting(false)
    }
}

/// The gold mark of a page whose reward waits: a small gold seal with a
/// spark, on the tile's shoulder.
struct CodexMark: View {
    var size: CGFloat = 13

    var body: some View {
        ZStack {
            Circle().fill(Theme.goldPlate)
            Circle().strokeBorder(Color(hex: "#FFF3C8").opacity(0.9), lineWidth: 1)
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.55, weight: .black))
                .foregroundStyle(Theme.ink)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.gold.opacity(0.85), radius: 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One form in the book's table: its card in its grade's metal once
/// recorded, in shadow with a "?" until then, the element's badge either
/// way so the columns read, and the gold mark while its reward waits.
struct CodexFormTile: View {
    let entry: CodexEntry
    let standing: CodexStanding
    var size: CGFloat = 50

    private var corner: CGFloat { max(6, min(Theme.tightCorner, size * 0.14)) }
    private var wear: CGFloat { max(0.6, min(1, size / 80)) }
    private var rarity: Rarity { Rarity(stars: entry.stars) }
    /// Marks stand inside the grade's metal, as `UnitPortraitTile`'s do.
    private var inset: CGFloat { rarity.frameWidth + 1 }

    /// Packed stars sized to the room inside the rim.
    private var starSize: CGFloat {
        let count = CGFloat(max(1, entry.stars))
        let room = (size - 2 * (inset + 0.5)) / (count * StarRow.packedAdvance)
        return max(4, min(9, size * 0.15, room))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return Group {
            if standing == .unrecorded {
                face
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Theme.glassRim.opacity(0.55), lineWidth: 1))
            } else {
                face
                    .clipShape(shape)
                    .rarityFrame(rarity, radius: corner, painted: false)
            }
        }
        .overlay(alignment: .topTrailing) {
            if standing == .ready {
                CodexMark(size: 13)
                    .offset(x: 4, y: -4)
            }
        }
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    private var face: some View {
        ZStack(alignment: .topLeading) {
            CodexPortrait(entry: entry, recorded: standing != .unrecorded, size: size)
            if standing != .unrecorded {
                LinearGradient(colors: [.clear, .clear, Theme.ink.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
                StarRow(stars: entry.stars, size: starSize, packed: true)
                    .padding(.bottom, max(inset, 3 * wear))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            ElementBadge(element: entry.element, compact: true, scale: wear)
                .padding(max(inset, 4 * wear))
                .opacity(standing == .unrecorded ? 0.6 : 1)
        }
        .frame(width: size, height: size)
    }

    private var spokenLabel: String {
        let name = CodexService.formName(for: entry)
        switch standing {
        case .unrecorded: return "\(name), not yet recorded"
        case .ready: return "\(name), recorded, reward waiting"
        case .claimed: return "\(name), recorded"
        }
    }
}

/// A form's large card on its page: the painting in the grade's carved frame
/// once recorded, in shadow until then, with the element, the awakened sun
/// and the natural grade.
struct CodexCard: View {
    let entry: CodexEntry
    let standing: CodexStanding
    var size: CGFloat = 108

    private var rarity: Rarity { Rarity(stars: entry.stars) }
    private var recorded: Bool { standing != .unrecorded }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
        return Group {
            if recorded {
                face
                    .clipShape(shape)
                    .rarityFrame(rarity, radius: Theme.tightCorner, painted: rarity.hasPaintedFrame)
            } else {
                face
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Theme.glassRim.opacity(0.6), lineWidth: 1))
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CodexService.formName(for: entry))
    }

    private var face: some View {
        ZStack(alignment: .topLeading) {
            CodexPortrait(entry: entry, recorded: recorded, size: size)
            LinearGradient(colors: [.clear, .clear, Theme.ink.opacity(0.8)],
                           startPoint: .top, endPoint: .bottom)
            // The carved frame UNDER the marks, as `UnitCard` lays it: over
            // them it hid the star row.
            if recorded, let frame = Chrome.image(rarity.frameImageName) {
                Image(uiImage: frame)
                    .resizable()
                    .frame(width: size, height: size)
            }
            VStack(alignment: .leading, spacing: 4) {
                ElementBadge(element: entry.element, compact: true)
                if entry.kind == .awakened {
                    CardMark(systemName: "sun.max.fill", size: 17)
                }
            }
            .padding(8)
            StarRow(stars: entry.stars, size: 11)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.ink.opacity(0.74)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 7)
                .opacity(recorded ? 1 : 0.6)
        }
        .frame(width: size, height: size)
    }
}

/// A pantheon on the book's rail: its banner's god in a ring (with the gold
/// mark while anything of it waits), its name, and how much of it is
/// recorded as a meter and a count.
struct CodexPantheonRow: View {
    let pantheon: Pantheon
    let progress: CodexProgress
    let waiting: Bool
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            action()
        } label: {
            HStack(spacing: 8) {
                emblem
                VStack(alignment: .leading, spacing: 4) {
                    Text(pantheon.displayName.uppercased())
                        .font(Theme.title(13))
                        .tracking(1.0)
                        .foregroundStyle(isOn ? Color(hex: "#FFF1C2") : Theme.onGlass)
                        .lineLimit(1)
                        .fixedSize()
                    HStack(spacing: 5) {
                        GlassMeter(value: Double(progress.recorded), maximum: Double(max(1, progress.total)),
                                   tint: pantheon.color, height: 4)
                            .frame(width: 40)
                        Text("\(progress.recorded)/\(progress.total)")
                            .font(Theme.numeric(11.5))
                            .foregroundStyle(Theme.onGlassDim)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(7)
            .background(GlassRowPlate(isOn: isOn))
            .contentShape(Rectangle())
        }
        // A row of the pantheons' scrolling rail: quiet, its tap kept in
        // the action, on a finished tap (2026-09-24).
        .buttonStyle(GamePressStyle(.quiet))
        .accessibilityLabel("\(pantheon.displayName), \(progress.recorded) of \(progress.total) recorded")
    }

    private var emblem: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.35))
            if let name = CodexArt.emblem(for: pantheon) {
                PortraitPainting(name: name, size: 34)
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
            }
        }
        .frame(width: 36, height: 36)
        .overlay(Circle().strokeBorder(isOn ? Theme.gold : Theme.glassRim, lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if waiting {
                CodexMark(size: 12)
                    .offset(x: 3, y: -2)
            }
        }
    }
}

/// A family's row in the table: its name, grade and count, then its five
/// forms (or awakened faces) in the element order every column keeps.
struct CodexFamilyRow: View {
    let family: CodexFamily
    let kind: CodexFormKind
    let ledger: CodexLedger
    let cell: CGFloat
    let nameWidth: CGFloat
    let onOpen: (Element) -> Void

    var body: some View {
        let pages = Element.allCases.compactMap { family.entry($0, kind) }
        let lit = pages.filter { ledger.isRecorded($0) }.count
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(family.name.uppercased())
                    .font(Theme.title(13))
                    .tracking(0.8)
                    .foregroundStyle(lit > 0 ? Theme.onGlass : Theme.onGlassDim)
                    .lineLimit(1)
                    .fixedSize()
                HStack(spacing: 6) {
                    StarRow(stars: family.stars, size: 8)
                    Text("\(lit)/\(pages.count)")
                        .font(Theme.numeric(11.5))
                        .foregroundStyle(lit == pages.count ? Theme.onGlassGold : Theme.onGlassDim)
                        .lineLimit(1)
                        .fixedSize()
                    Text(family.role.displayName)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.onGlassDim)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(width: nameWidth, alignment: .leading)
            HStack(spacing: 8) {
                ForEach(Element.allCases) { element in
                    if let page = family.entry(element, kind) {
                        Button {
                            Juice.haptic(.light)
                            AudioLibrary.shared.play(.uiTap)
                            onOpen(element)
                        } label: {
                            CodexFormTile(entry: page, standing: ledger.standing(page), size: cell)
                        }
                        // A face of the table's scrolling list: quiet, its
                        // tap kept in the action.
                        .buttonStyle(GamePressStyle(.quiet))
                    } else {
                        Color.clear
                            .frame(width: cell, height: cell)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}

/// A pantheon's completion track: the recorded share as a gold meter, and a
/// marker at 25, 50, 75 and 100% carrying its prize's painted scroll — the
/// genre's milestone chests along a progress bar. A reached marker glows and
/// pulses until it is claimed; a claimed one wears a tick.
struct CodexTierTrack: View {
    let progress: CodexProgress
    let standings: [CodexTier: CodexStanding]
    let onTap: (CodexTier) -> Void

    static let marker: CGFloat = 30
    /// The disc, 2, and the percent's line of Manrope at 11.5.
    static let height: CGFloat = marker + 18

    var body: some View {
        GeometryReader { box in
            let span = max(1, box.size.width - Self.marker)
            ZStack(alignment: .topLeading) {
                GlassMeter(value: Double(progress.recorded), maximum: Double(max(1, progress.total)),
                           tint: Theme.gold, height: 6)
                    .frame(width: span)
                    .offset(x: Self.marker / 2, y: Self.marker / 2 - 3)
                ForEach(CodexTier.allCases) { tier in
                    medal(tier)
                        .offset(x: span * CGFloat(tier.rawValue) / 100, y: 0)
                }
            }
        }
        .frame(height: Self.height)
    }

    private func medal(_ tier: CodexTier) -> some View {
        let standing = standings[tier] ?? .unrecorded
        return Button {
            onTap(tier)
        } label: {
            VStack(spacing: 2) {
                disc(tier, standing: standing)
                Text("\(tier.rawValue)%")
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(standing == .ready ? Theme.onGlassGold : Theme.onGlassDim)
                    .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(width: Self.marker)
            .contentShape(Rectangle())
        }
        .buttonStyle(GamePressStyle(.medallion))
        .accessibilityLabel("\(tier.rawValue)% of the pantheon: \(CodexService.prizeWords(for: tier))")
    }

    @ViewBuilder
    private func disc(_ tier: CodexTier, standing: CodexStanding) -> some View {
        if standing == .ready {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                let pulse: Double = 0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 3.2)
                socket(tier, standing: standing)
                    .shadow(color: Theme.gold.opacity(0.45 + 0.4 * pulse), radius: CGFloat(4 + 4 * pulse))
            }
        } else {
            socket(tier, standing: standing)
        }
    }

    private func socket(_ tier: CodexTier, standing: CodexStanding) -> some View {
        ZStack {
            Circle().fill(Theme.socketFill)
            ItemIcon(key: CodexArt.prizeKey(for: tier), size: 21, glow: false)
                .opacity(standing == .unrecorded ? 0.45 : 1)
            if standing == .claimed {
                Circle().fill(Color.black.opacity(0.45))
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(Theme.onGlassSuccess)
            }
        }
        .frame(width: Self.marker, height: Self.marker)
        .overlay(Circle().strokeBorder(rim(standing), lineWidth: standing == .ready ? 1.6 : 1))
    }

    private func rim(_ standing: CodexStanding) -> Color {
        switch standing {
        case .ready: return Theme.gold
        case .claimed: return Theme.onGlassSuccess.opacity(0.7)
        case .unrecorded: return Theme.glassRim.opacity(0.6)
        }
    }
}

/// One road to a form on its page: the scroll's painting (or the road's
/// glyph) in a dark disc, the road's name and what it asks.
struct CodexSourceRow: View {
    let source: CodexSource

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                Circle().fill(Color.black.opacity(0.35))
                if let key = source.itemKey, ItemArt.hasPainting(key) {
                    ItemIcon(key: key, size: 26, glow: false)
                } else {
                    Image(systemName: source.glyph)
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Theme.onGlassGold)
                }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                    .font(Theme.title(13))
                    .foregroundStyle(Theme.onGlass)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(source.detail)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.onGlassDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(7)
        .background(GlassRowPlate(isOn: false))
    }
}
