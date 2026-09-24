import SwiftUI

// MARK: - The ten-pull as one ceremony (2026-09-24, Docs/FEEL.md W2.3)
//
// A ten-pull was ten reveals in a row — ten charges, ten taps — ending on a
// grid of 74-point tiles that scrolled and was never photographed.
// Summoners War made its 10× summon because single reveals were slow; the
// genre's answer is one moment for the ten. So: ONE charge on the W1.5
// ladder, climbing to the best grade in the ten (`SummonBoard.headline`); the
// flash opens onto a 5 × 2 board of face-down cards dealt from where the
// light was, turning left to right 90 ms apart; a 4★, a 5★ or a unit never
// owned lands with a rim flare, and the board steps aside while that card
// lifts off to the beam for its full reveal (`RevealLift`); then the summary,
// which always fits the phone (`SummonBoardLayout`): the ten cards with their
// names, a line like "1 ★★★★★ · 2 ★★★★ · 3 new", the new pity, and "Summon
// ×10 again" (`SummonAgainOffer`). A tap on a card there replays its reveal.
//
// The rules are pure and the looks are functions of a clock
// (`SummonBoardClock`), as the charge is: a main thread held up behind a
// stage can never leave a card half turned.

/// The board's rules and numbers.
enum SummonBoard {
    /// A card whose landing stops the board for its own reveal on the beam:
    /// a 4★ or better, or a unit the player never owned.
    static func isFeatured(_ result: SummonResult) -> Bool {
        result.stars >= 4 || result.isNew
    }

    /// The pull the ten's one charge climbs to: the best grade; among equals
    /// a Light or Dark one (its charge parts at the top of the ladder), then
    /// a new one, then the earliest. Nil for an empty pull.
    static func headline(of results: [SummonResult]) -> Int? {
        guard !results.isEmpty else { return nil }
        var best: Int = 0
        for candidate in results.indices.dropFirst() where outranks(results[candidate], results[best]) {
            best = candidate
        }
        return best
    }

    private static func outranks(_ one: SummonResult, _ other: SummonResult) -> Bool {
        if one.stars != other.stars { return one.stars > other.stars }
        let oneParts: Bool = one.blueprint.element.isLightOrDark
        let otherParts: Bool = other.blueprint.element.isLightOrDark
        if oneParts != otherParts { return oneParts }
        if one.isNew != other.isNew { return one.isNew }
        return false
    }

    /// The first featured card at or after `from`, or nil.
    static func nextFeatured(from: Int, in results: [SummonResult]) -> Int? {
        guard from < results.count else { return nil }
        return (max(0, from)..<results.count).first { isFeatured(results[$0]) }
    }

    /// The pull whose figure the summon room warms before the reveal is up:
    /// a single's own, a ten's first featured card — the first figure its
    /// board will stand on the beam — and nil for a ten with none, which
    /// mounts no stage at all.
    static func firstStage(in results: [SummonResult]) -> SummonResult? {
        if results.count == 1 { return results.first }
        return nextFeatured(from: 0, in: results).map { results[$0] }
    }

    /// A card's name under it: a form's name without its epithet
    /// (`RevealNameCard.names`) and without a leading "The ", so "The
    /// Unwrapped King" holds its 96 points.
    static func shortName(_ result: SummonResult) -> String {
        let main: String = RevealNameCard.names(for: result).main
        return main.hasPrefix("The ") ? String(main.dropFirst(4)) : main
    }

    // MARK: Timing

    /// The ten face-down cards fly out from the flash to their places, each
    /// this long, the next this much later.
    static let dealLength: TimeInterval = 0.42
    static let dealStagger: TimeInterval = 0.02
    /// From the flash to the first card's turn: the deal has landed.
    static let firstFlip: TimeInterval = 0.55
    /// Two cards turn this far apart — the genre's 90 ms — each turn this
    /// long.
    static let flipSpacing: TimeInterval = 0.09
    static let flipLength: TimeInterval = 0.32
    /// A featured card's rim flare, and the board's hold on it before it
    /// lifts off for its reveal.
    static let flareLength: TimeInterval = 0.6
    static let flareHold: TimeInterval = 0.55
    /// A skip's stop lifts a little sooner: the thumb asked for it.
    static let skipHold: TimeInterval = 0.3
    /// A featured reveal handed back: the board is back before the next turn.
    static let resume: TimeInterval = 0.35
    /// The last card up, the breath before the summary.
    static let lastBeat: TimeInterval = 0.4
    /// A skip's ripple: the cards still face down turn this far apart.
    static let rippleSpacing: TimeInterval = 0.04
    /// The summary's words and plate come up over this long.
    static let summaryIn: TimeInterval = 0.35

    /// When card `card` turns in a run that began with card `from`.
    static func flipDelay(of card: Int, from: Int, spacing: TimeInterval = flipSpacing) -> TimeInterval {
        Double(max(0, card - from)) * spacing
    }

    /// A move `elapsed` seconds into one of `length`: 0 → 1, a smoothstep.
    static func turn(elapsed: TimeInterval, length: TimeInterval) -> Double {
        let t: Double = min(1, max(0, elapsed / max(0.001, length)))
        return t * t * (3 - 2 * t)
    }

    // MARK: The tally

    /// The summary's line: how many of each grade from 4★ up — the best grade
    /// alone when nothing reached 4★ — best first, and how many are new.
    static func tally(_ results: [SummonResult]) -> SummonTally {
        var byGrade: [Int: Int] = [:]
        for result in results { byGrade[result.stars, default: 0] += 1 }
        let top: Int = results.map(\.stars).max() ?? 0
        let shown: [Int] = byGrade.keys.filter { $0 >= 4 || $0 == top }.sorted(by: >)
        let entries: [SummonTallyEntry] = shown.map { SummonTallyEntry(stars: $0, count: byGrade[$0] ?? 0) }
        let fresh: Int = results.filter(\.isNew).count
        return SummonTally(entries: entries, newCount: fresh, total: results.count)
    }

    /// The line in words — "1 ★★★★★ · 2 ★★★★ · 3 new" — for VoiceOver and
    /// the tests.
    static func tallyLine(_ tally: SummonTally) -> String {
        var parts: [String] = tally.entries.map { entry in
            "\(entry.count) " + String(repeating: "★", count: max(0, entry.stars))
        }
        if tally.newCount > 0 { parts.append("\(tally.newCount) new") }
        return parts.joined(separator: " · ")
    }
}

/// One grade on the summary's line.
struct SummonTallyEntry: Equatable {
    let stars: Int
    let count: Int
}

/// The summary's line as numbers (`SummonBoard.tally`).
struct SummonTally: Equatable {
    let entries: [SummonTallyEntry]
    let newCount: Int
    let total: Int
}

/// Where the board's cards stand on a frame of `size` with the phone's
/// `insets`, and its header and foot: the largest card up to 96 points that
/// fits two rows of five with their names between a top band clear of Skip
/// and a foot for the tally and "Summon ×10 again". On the CI's phone (852 ×
/// 393, 59-point sides) that is 96; on an SE (667 × 375) 96; on a 13 mini
/// (812 × 375, a 21-point home bar) 91 — never a scroll.
struct SummonBoardLayout: Equatable {
    let card: CGFloat
    /// Each card's square, its name under it (`nameHeight`).
    let slots: [CGRect]
    let header: CGRect
    let footer: CGRect
    /// Where the cards fly out from: the flash, at the charge's heart.
    let dealFrom: CGPoint

    static let largest: CGFloat = 96
    static let smallest: CGFloat = 56
    static let nameHeight: CGFloat = 20
    static let gapX: CGFloat = 12
    static let gapY: CGFloat = 8
    static let margin: CGFloat = 16
    static let footerHeight: CGFloat = 46
    /// The band at the top the cards keep clear of: Skip's capsule (12 + 34
    /// points) and "Hold to skip all" under it.
    static let top: CGFloat = 66
    static let columns: Int = 5

    static func make(count: Int, size: CGSize, insets: EdgeInsets) -> SummonBoardLayout {
        let left: CGFloat = max(0, insets.leading) + margin
        let right: CGFloat = size.width - max(0, insets.trailing) - margin
        let bottom: CGFloat = size.height - max(insets.bottom, 6) - 4
        let footerTop: CGFloat = bottom - footerHeight
        let shown: Int = max(1, count)
        let rows: Int = (shown + columns - 1) / columns
        let across: Int = min(columns, shown)
        let rowCount: CGFloat = CGFloat(rows)
        let acrossCount: CGFloat = CGFloat(across)
        let roomHigh: CGFloat = footerTop - gapY - top
        let byHeight: CGFloat = (roomHigh - gapY * (rowCount - 1)) / rowCount - nameHeight
        let byWidth: CGFloat = (right - left - gapX * (acrossCount - 1)) / acrossCount
        let card: CGFloat = max(smallest, min(largest, byHeight, byWidth))
        let rowHeight: CGFloat = card + nameHeight
        let blockHeight: CGFloat = rowHeight * rowCount + gapY * (rowCount - 1)
        let blockTop: CGFloat = top + max(0, (roomHigh - blockHeight) / 2)
        let middle: CGFloat = (left + right) / 2
        var slots: [CGRect] = []
        for place in 0..<max(0, count) {
            let row: Int = place / columns
            let column: Int = place % columns
            let inRow: Int = min(columns, count - row * columns)
            let rowWidth: CGFloat = CGFloat(inRow) * card + gapX * CGFloat(inRow - 1)
            let x: CGFloat = middle - rowWidth / 2 + CGFloat(column) * (card + gapX)
            let y: CGFloat = blockTop + CGFloat(row) * (rowHeight + gapY)
            slots.append(CGRect(x: x, y: y, width: card, height: card))
        }
        let header = CGRect(x: left, y: 12, width: max(0, (right - left) / 2), height: 44)
        let footer = CGRect(x: left, y: footerTop, width: max(0, right - left), height: footerHeight)
        let dealFrom = CGPoint(x: size.width * RevealGeometry.boardLine, y: size.height * RevealGeometry.heart)
        return SummonBoardLayout(card: card, slots: slots, header: header, footer: footer, dealFrom: dealFrom)
    }
}

/// The board's clock: when it was dealt, when each card began to turn, when
/// each featured card flared, and when the summary began. Every look on the
/// board is a pure function of this and the wall clock (`SummonBoardView`).
struct SummonBoardClock: Equatable {
    var dealtAt: Date
    /// When each card began to turn, by its place.
    var flips: [Int: Date] = [:]
    /// When each featured card landed: its rim flare runs from there.
    var flares: [Int: Date] = [:]
    /// The card lifted off for its reveal, not drawn in its slot.
    var hidden: Int? = nil
    var summaryAt: Date? = nil

    /// How far card `card` has flown out from the flash, 0 → 1.
    func dealt(_ card: Int, at date: Date) -> Double {
        let start: Date = dealtAt.addingTimeInterval(Double(card) * SummonBoard.dealStagger)
        return SummonBoard.turn(elapsed: date.timeIntervalSince(start), length: SummonBoard.dealLength)
    }

    /// How far card `card` has turned, 0 face down → 1 face up.
    func turned(_ card: Int, at date: Date) -> Double {
        guard let start = flips[card] else { return 0 }
        return SummonBoard.turn(elapsed: date.timeIntervalSince(start), length: SummonBoard.flipLength)
    }

    func isLanded(_ card: Int, at date: Date) -> Bool {
        guard let start = flips[card] else { return false }
        return date.timeIntervalSince(start) >= SummonBoard.flipLength
    }

    /// A featured card's flare, 0 → 1 over its length; nil for a card with
    /// none (not featured, or not landed).
    func flare(_ card: Int, at date: Date) -> Double? {
        guard let start = flares[card] else { return nil }
        let elapsed: TimeInterval = date.timeIntervalSince(start)
        guard elapsed >= 0 else { return nil }
        return min(1, elapsed / SummonBoard.flareLength)
    }

    /// The summary's words and plate, 0 → 1.
    func summaryShown(at date: Date) -> Double {
        guard let summaryAt else { return 0 }
        return SummonBoard.turn(elapsed: date.timeIntervalSince(summaryAt), length: SummonBoard.summaryIn)
    }
}

/// "Summon ×10 again" on the summary (W2.3), handed in by the summon room:
/// what it spends, how many are held, the pity after this pull, and the
/// action that summons again in place. It spends scrolls in hand and nothing
/// else — short of them the plate says so, and offers no purchase
/// (Docs/STORE.md's review notes: nothing that hurries a spend of money).
struct SummonAgainOffer {
    let count: Int
    let scroll: ScrollType
    let held: Int
    /// The pity after this summon ("5★ in 78 · 4★+ in 17"); nil for a
    /// banner with none.
    let pity: String?
    let action: () -> Void

    var affordable: Bool { held >= count }
    var short: Int { max(0, count - held) }
}

/// A featured card lifting off the board for its full reveal (W2.3): from
/// its slot to where the figure will stand, growing, while the board steps
/// aside; the flash that lands the figure covers it.
enum RevealLift {
    static let span: TimeInterval = 0.45
    static let growth: CGFloat = 1.45

    /// 0 → 1 over `span`, eased out; at once under Reduce Motion.
    static func progress(elapsed: TimeInterval, calm: Bool) -> CGFloat {
        guard !calm else { return 1 }
        let t: Double = min(1, max(0, elapsed / span))
        let rest: Double = 1 - t
        return CGFloat(1 - rest * rest * rest)
    }

    /// Where the card is at `progress` on its way from `slot` to `centre`:
    /// a straight line with a little lift, growing to `growth` of its size.
    static func pose(from slot: CGRect, to centre: CGPoint, progress: CGFloat) -> RevealLiftPose {
        let startX: CGFloat = slot.midX
        let startY: CGFloat = slot.midY
        let arc: CGFloat = CGFloat(sin(Double(progress) * Double.pi)) * slot.height * 0.3
        let x: CGFloat = startX + (centre.x - startX) * progress
        let y: CGFloat = startY + (centre.y - startY) * progress - arc
        let finalSide: CGFloat = slot.width * growth
        let side: CGFloat = slot.width + (finalSide - slot.width) * progress
        return RevealLiftPose(centre: CGPoint(x: x, y: y), side: side, finalSide: finalSide, progress: progress)
    }
}

/// A lifted card's place at one moment: its centre, its side now and the
/// side it arrives at (it is drawn at that and scaled, so its painting is
/// decoded once), and how far along it is.
struct RevealLiftPose: Equatable {
    let centre: CGPoint
    let side: CGFloat
    let finalSide: CGFloat
    let progress: CGFloat
}

// MARK: - The board, drawn

/// The board and its summary: the cards dealt, turning, flaring and named;
/// the scroll's line and SUMMONED at the top left; the tally, the pity and
/// "Summon ×10 again" along the foot. Stateless: the reveal owns the clock
/// and the phase and hands both in.
struct SummonBoardView: View {
    let results: [SummonResult]
    let units: [ResolvedUnit]
    let clock: SummonBoardClock
    let layout: SummonBoardLayout
    /// Whether the timeline draws: the reveal stops it once all is still.
    let ticking: Bool
    let summary: Bool
    let offer: SummonAgainOffer?
    let scroll: ScrollType?
    let calm: Bool
    let onTapCard: (Int) -> Void

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !ticking)) { timeline in
            board(at: timeline.date)
        }
    }

    private func board(at date: Date) -> some View {
        let shown: Double = clock.summaryShown(at: date)
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(results.indices, id: \.self) { place in
                if place < layout.slots.count {
                    slot(place, at: date)
                }
            }
            header(summaryShown: shown)
            footer(at: date, summaryShown: shown)
        }
    }

    // MARK: A card in its slot

    @ViewBuilder
    private func slot(_ place: Int, at date: Date) -> some View {
        let frame: CGRect = layout.slots[place]
        let dealt: Double = clock.dealt(place, at: date)
        let turned: Double = clock.turned(place, at: date)
        let named: Double = min(1, max(0, (turned - 0.6) / 0.4))
        // Under Reduce Motion the cards are dealt where they lie: a fade, no
        // flight from the flash.
        let flight: CGFloat = calm ? 0 : CGFloat(1 - dealt)
        let pullX: CGFloat = (layout.dealFrom.x - frame.midX) * flight
        let pullY: CGFloat = (layout.dealFrom.y - frame.midY) * flight
        let growth: CGFloat = calm ? 1 : CGFloat(0.35 + 0.65 * dealt)
        let result: SummonResult = results[place]
        let unit: ResolvedUnit? = units.indices.contains(place) ? units[place] : nil
        let hidden: Bool = clock.hidden == place
        let card = SummonBoardCard(
            result: result,
            unit: unit,
            size: layout.card,
            turned: turned,
            flare: clock.flare(place, at: date),
            calm: calm
        )
        VStack(spacing: 0) {
            Group {
                if summary {
                    Button {
                        onTapCard(place)
                    } label: {
                        card
                    }
                    .buttonStyle(GamePressStyle(.plate))
                    .accessibilityLabel(Text("\(SummonBoard.shortName(result)), \(result.stars) stars, replay"))
                } else {
                    card
                }
            }
            .frame(width: layout.card, height: layout.card)
            Text(SummonBoard.shortName(result))
                .font(Theme.body(11).weight(.semibold))
                .foregroundStyle(RevealDusk.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                .frame(width: layout.card + SummonBoardLayout.gapX - 2, height: SummonBoardLayout.nameHeight)
                .opacity(named)
        }
        .scaleEffect(growth)
        .offset(x: pullX, y: pullY)
        .opacity(hidden ? 0 : dealt)
        .position(x: frame.midX, y: frame.midY + SummonBoardLayout.nameHeight / 2)
    }

    // MARK: The header and the foot

    private var eyebrow: String {
        let count: Int = results.count
        guard let scroll else { return "×\(count)" }
        return scroll.displayName.uppercased() + "  ×\(count)"
    }

    private func header(summaryShown: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(eyebrow)
                .font(Theme.title(11))
                .tracking(2.2)
                .foregroundStyle(Theme.onGlassEyebrow)
                .lineLimit(1)
                .fixedSize()
                .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
            Text("SUMMONED")
                .font(Theme.display(24))
                .tracking(1.5)
                .carved()
                .lineLimit(1)
                .fixedSize()
                .opacity(summaryShown)
        }
        .frame(width: layout.header.width, height: layout.header.height, alignment: .topLeading)
        .position(x: layout.header.midX, y: layout.header.midY)
        .allowsHitTesting(false)
    }

    private func footer(at date: Date, summaryShown: Double) -> some View {
        let landed: [SummonResult] = results.indices.filter { clock.isLanded($0, at: date) }.map { results[$0] }
        let tally: SummonTally = SummonBoard.tally(landed)
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                SummonTallyLine(tally: tally)
                if summary, let words = footNote {
                    Text(words)
                        .font(Theme.body(11).weight(.semibold))
                        .foregroundStyle(Theme.onGlassDim)
                        .lineLimit(1)
                        .fixedSize()
                        .opacity(summaryShown)
                }
            }
            Spacer(minLength: 8)
            if summary, let offer {
                againButton(offer)
                    .opacity(summaryShown)
            }
        }
        .frame(width: layout.footer.width, height: layout.footer.height)
        .position(x: layout.footer.midX, y: layout.footer.midY)
    }

    /// Under the tally: the pity after this pull, and what "Summon again"
    /// still needs when the scrolls in hand are short.
    private var footNote: String? {
        var parts: [String] = []
        if let pity = offer?.pity { parts.append(pity) }
        if let offer, !offer.affordable {
            parts.append("×\(offer.count) needs \(offer.short) more")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func againButton(_ offer: SummonAgainOffer) -> some View {
        PrimaryButton(
            title: "Summon ×\(offer.count) again",
            systemImage: offer.scroll.glyph,
            isEnabled: offer.affordable,
            itemKey: ItemArt.key(scroll: offer.scroll)
        ) {
            if offer.affordable { offer.action() }
        }
        .frame(maxWidth: 300)
        .allowsHitTesting(summary)
    }
}

/// One card of the board: its back — the same for every card, so the board
/// tells nothing before a card turns — turning on its vertical axis to its
/// face, the unit's portrait tile with NEW or what a duplicate did; a
/// featured card's rim flares in its grade's colour as it lands and keeps a
/// glow after. Under Reduce Motion the back gives way to the face in place.
struct SummonBoardCard: View {
    let result: SummonResult
    let unit: ResolvedUnit?
    let size: CGFloat
    /// 0 face down → 1 face up.
    let turned: Double
    /// The flare's progress once a featured card has landed; nil otherwise.
    let flare: Double?
    let calm: Bool

    var body: some View {
        let faceUp: Bool = turned >= 0.5
        let angle: Double = faceUp ? (turned - 1) * 180 : turned * 180
        let rise: CGFloat = CGFloat(sin(Double.pi * turned)) * 0.08
        return ZStack {
            flareLayer
            if calm {
                SummonCardBack(size: size)
                    .opacity(1 - turned)
                face
                    .opacity(turned)
            } else if faceUp {
                face
                    .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            } else {
                SummonCardBack(size: size)
                    .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(calm ? 1 : 1 + rise)
    }

    @ViewBuilder
    private var face: some View {
        if let unit {
            UnitPortraitTile(unit: unit, size: size, showsLevel: false)
                .overlay(alignment: .topTrailing) {
                    chip
                        .padding(5)
                }
        } else {
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(Rarity(stars: result.stars).glow.opacity(0.45))
                .frame(width: size, height: size)
        }
    }

    /// NEW in gold, or what the copy did (`SummonDuplicateChip`).
    @ViewBuilder
    private var chip: some View {
        if result.isNew {
            Text("NEW")
                .font(Theme.body(11).weight(.black))
                .tracking(0.6)
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Capsule().fill(Theme.goldPlate))
                .fixedSize()
        } else if let skillUp = result.skillUp {
            SummonDuplicateChip(skillUp: skillUp)
        }
    }

    /// The rim flare: a ring of the grade's light swelling off the card and
    /// fading, the glow that stays behind it, and for a 5★ the rays.
    @ViewBuilder
    private var flareLayer: some View {
        if let flare {
            let glow: Color = Rarity(stars: result.stars).glow
            let fade: Double = 1 - flare
            let ring: CGFloat = size * (1 + 0.6 * CGFloat(flare))
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(glow.opacity(0.55))
                    .frame(width: size + 8, height: size + 8)
                    .blur(radius: 9)
                if !calm {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(glow.opacity(0.9 * fade), lineWidth: 3)
                        .frame(width: ring, height: ring)
                    if result.stars >= 5 {
                        AngularGradient(
                            colors: [glow.opacity(0), glow.opacity(0.7), glow.opacity(0), glow.opacity(0.7),
                                     glow.opacity(0), glow.opacity(0.7), glow.opacity(0), glow.opacity(0.7), glow.opacity(0)],
                            center: .center
                        )
                        .frame(width: size * 2.1, height: size * 2.1)
                        .mask {
                            RadialGradient(colors: [Color.white, Color.white.opacity(0)], center: .center,
                                           startRadius: size * 0.3, endRadius: size * 1.05)
                        }
                        .rotationEffect(.degrees(50 * flare))
                        .opacity(0.25 + 0.6 * fade)
                        .blendMode(.plusLighter)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// The back every card shows until it turns: dark bronze in a gold rim, the
/// ring of names — the rune ring's own lines — in gold, and a star at its
/// heart.
struct SummonCardBack: View {
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: max(6, size * 0.12), style: .continuous)
        return ZStack {
            shape
                .fill(LinearGradient(colors: [Color(hex: "#3A2A16"), Color(hex: "#1A120A")],
                                     startPoint: .top, endPoint: .bottom))
            ringOfNames
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.2, weight: .black))
                .foregroundStyle(Theme.goldText)
                .shadow(color: Theme.gold.opacity(0.6), radius: 4)
            shape
                .inset(by: 4)
                .strokeBorder(Theme.goldDim.opacity(0.6), lineWidth: 0.8)
            shape
                .strokeBorder(Theme.goldPlate, lineWidth: 2)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
    }

    @ViewBuilder
    private var ringOfNames: some View {
        if let lines = RuneLinesArt.image {
            Rectangle()
                .fill(Theme.goldTextFlat)
                .frame(width: size * 0.8, height: size * 0.8)
                .mask {
                    Image(uiImage: lines)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                }
                .opacity(0.7)
        } else {
            Circle()
                .strokeBorder(Theme.goldDim.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [3, 5]))
                .frame(width: size * 0.7, height: size * 0.7)
        }
    }
}

/// The tally along the board's foot: each grade's count and its stars, then
/// how many are new — "1 ★★★★★ · 2 ★★★★ · 3 new" — counting up as the
/// cards land.
struct SummonTallyLine: View {
    let tally: SummonTally

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(tally.entries.enumerated()), id: \.offset) { place, entry in
                if place > 0 {
                    Text("·")
                        .font(Theme.numeric(12))
                        .foregroundStyle(Theme.onGlassDim)
                }
                Text("\(entry.count)")
                    .font(Theme.numeric(13))
                    .foregroundStyle(Theme.onGlass)
                StarRow(stars: entry.stars, size: 10)
            }
            if tally.newCount > 0 {
                if !tally.entries.isEmpty {
                    Text("·")
                        .font(Theme.numeric(12))
                        .foregroundStyle(Theme.onGlassDim)
                }
                Text("\(tally.newCount) new")
                    .font(Theme.body(12).weight(.bold))
                    .foregroundStyle(Theme.onGlassGold)
            }
        }
        .lineLimit(1)
        .fixedSize()
        .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(SummonBoard.tallyLine(tally)))
    }
}
