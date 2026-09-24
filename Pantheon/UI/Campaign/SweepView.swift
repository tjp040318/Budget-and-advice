import SwiftUI
import UIKit

/// The sweep control, and the receipt it leaves.
///
/// The genre puts sweep where the fight is launched from, not in a menu of
/// its own — Blue Archive's is a second button beside Start, Summoners War's
/// Scout Battle is a tab of the dungeon's own entry screen — because the
/// decision a player is making is "this stage, now, how many times", and a
/// sweep is one of the answers to it, not a different question.

/// A Sweep button that says why it is dark.
///
/// A disabled control with no reason is the single most annoying thing in a
/// menu, and this one is disabled most of the time by design: a stage is not
/// sweepable until it has been three-starred. So the refusal is a sentence
/// the player can act on, drawn beside the button rather than behind a tap.
struct SweepButton: View {
    let stage: Stage
    let runs: Int
    let onSweep: (Int) -> Void
    /// The sweep over art (2026-09-22, phase B): dark glass as tall as a
    /// `PrimaryButton`, the words in pale gold, and NO footnote. The
    /// footnote is brown on cream — invisible on glass — and 30 points of
    /// height the stage popup and the briefing's deck do not have. A sweep
    /// not yet earned says why ON the button, in a few words under a lock
    /// (`shutLine`); the whole sentence is its accessibility hint. The
    /// Labyrinth's deck can take the same button.
    var onGlass: Bool = false

    @EnvironmentObject private var store: GameStore

    private var refusal: String? { SweepService.refusal(stage, player: store.player) }
    private var affordable: Int { SweepService.affordableRuns(stage, player: store.player) }
    /// What a tap will actually do: what was asked for, or what the energy pays for.
    private var effectiveRuns: Int { max(1, min(runs, affordable)) }

    /// How strongly a shut sweep's plate and title are drawn: a ghost of the
    /// open button, so the two cannot be mistaken — the shut one was dimmer
    /// glass with dimmer words and read as the same button (runs 220 and 221).
    private static let shutOpacity: Double = 0.45

    var body: some View {
        if onGlass {
            glassButton
        } else {
            creamButton
        }
    }

    /// The refusal in the words the button's second line holds: the stars
    /// the stage has of the three it needs, the power it asks, or the energy
    /// a run costs. Nil when the sweep is open.
    private var shutLine: String? {
        let player = store.player
        guard refusal != nil else { return nil }
        if !SweepService.isMastered(stage, player: player) {
            let pips = min(3, player.stageStars?[stage.id] ?? 0)
            return "\(pips)/3 ★"
        }
        if !SweepService.isPowered(stage, player: player) {
            return "Needs \(stage.recommendedPower.formatted()) power"
        }
        return "\(EventCalendar.energyCost(for: stage)) energy a run"
    }

    /// Dark glass when it can sweep, the label the count the energy actually
    /// pays for; shut, a ghost of it with a lock and the reason under the
    /// word.
    private var glassButton: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
        let open = refusal == nil
        return Button {
            onSweep(effectiveRuns)
        } label: {
            Group {
                if open {
                    HStack(spacing: 6) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13, weight: .black))
                        Text(runs > 1 ? "SWEEP ×\(effectiveRuns)" : "SWEEP")
                            .font(Theme.title(14))
                            .tracking(1.2)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .foregroundStyle(Color(hex: "#FFE9A8"))
                } else {
                    shutLabel
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: PrimaryButton.height)
            .background(
                shape.fill(LinearGradient(
                    colors: [Color(hex: "#3A2C1A").opacity(0.92), Color(hex: "#150F0A").opacity(0.92)],
                    startPoint: .top, endPoint: .bottom
                ))
                .opacity(open ? 1 : Self.shutOpacity)
            )
            .overlay(
                shape.strokeBorder(Theme.glassRim, lineWidth: 1)
                    .opacity(open ? 1 : Self.shutOpacity)
            )
            .contentShape(shape)
        }
        .buttonStyle(GamePressStyle(.plate))
        .disabled(!open)
        .accessibilityHint(refusal ?? "")
    }

    /// A shut sweep's words: the lock and SWEEP as faint as the plate, and
    /// the reason under them in gold at full strength — "0/3 ★" — because
    /// it is the one thing on the button the player can act on.
    private var shutLabel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .black))
                Text("SWEEP")
                    .font(Theme.title(14))
                    .tracking(1.2)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(Theme.onGlass)
            .opacity(Self.shutOpacity + 0.15)
            if let shutLine {
                Text(shutLine)
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(Theme.onGlassEyebrow)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
    }

    private var creamButton: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Button {
                onSweep(effectiveRuns)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 11, weight: .black))
                    Text(runs > 1 ? "Sweep ×\(effectiveRuns)" : "Sweep")
                        .font(Theme.body(12).weight(.black))
                        .tracking(0.6)
                }
                .foregroundStyle(refusal == nil ? Theme.ink : Theme.textSecondary)
                .padding(.horizontal, 14)
                .frame(height: Theme.buttonHeight)
                .background(
                    // A gradient and a colour will not unify in a ternary;
                    // every plate in the game that switches between them uses
                    // a Group, and one that did not cost a CI run.
                    Group {
                        if refusal == nil {
                            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                                .fill(Theme.goldPlate)
                        } else {
                            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                                .fill(Theme.surface)
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                        .strokeBorder(refusal == nil ? Color.clear : Theme.stroke, lineWidth: 0.5)
                )
            }
            // A gold plate: the primary press, at half strength when shut
            // as `.plain` drew it (2026-09-24).
            .buttonStyle(GamePressStyle(.primary, dimsWhenDisabled: true))
            .disabled(refusal != nil)

            if let refusal {
                Text(refusal)
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 240, alignment: .trailing)
            } else if runs > effectiveRuns {
                Text("Energy pays for \(effectiveRuns) of \(runs).")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.danger)
            } else {
                Text("No battle — \(EventCalendar.energyCost(for: stage) * effectiveRuns) energy")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// The receipt, over whatever screen asked for the sweep.
///
/// Deep glass over the dimmed map (2026-09-23): a card over a place is glass
/// on the rule every place screen keeps since phase A. It was the win's
/// cream `SpoilsPanel`, centred in the whole screen — so its ribbon rose into
/// the strip and covered the chapter's name, its caption floated on the map
/// and the tab bar under it stayed bright (run 216). Now it stands in the
/// map under the strip, with what it paid as the popup's tiles on glass (the
/// same `RewardTile`, the stars inside the socket so every name sits on one
/// line) and what it cost as its eyebrow. A sweep pays exactly what the
/// fights would have paid; the tiles are all shown at once — the victory
/// deals them one by one for the drama of a fight it just watched, and a
/// sweep has no drama to pace. Its screen dims the tab bar
/// (`dimsTabBar`) while it is up.
struct SweepReceiptCard: View {
    let receipt: SweepReceipt
    let loot: [BattleSummary.Loot]
    let onClose: () -> Void
    var onRelic: (Relic) -> Void = { _ in }

    /// The card is as wide as what it holds — the title row with its
    /// stars, or the row of spoils, whichever is wider — with 56 points of
    /// air across (the padding's 28 and 14 more a side), never under
    /// `minimumWidth` and never wider than the map less 16 a side. It was
    /// 580 whatever it held, so four or five spoils sat in a band of empty
    /// glass 110 to 150 points wide on either side (runs 220 and 221).
    private static let minimumWidth: CGFloat = 460
    private static let air: CGFloat = 56
    private static let tile: CGFloat = 52
    /// A tile's name frame: 1.3 of the tile, and "Whetstone" (60 at 11).
    private static let footprint: CGFloat = 68
    private static let gap: CGFloat = 8
    private static let chevron: CGFloat = 18
    /// The header's fixed parts: the chest (44), the stars (three at 14,
    /// about 57), and the HStack's three gaps of 12 with the spacer's 8.
    private static let chestWidth: CGFloat = 44
    private static let starsWidth: CGFloat = 57
    private static let headerGaps: CGFloat = 12 * 3 + 8

    var body: some View {
        GeometryReader { frame in
            let width = min(max(0, frame.size.width - 32), max(Self.minimumWidth, contentWidth + Self.air))
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onClose)
                // Centred in the map under the strip, clear of the strip.
                card(width: width)
                    .padding(.top, ScreenChrome.height)
            }
            .frame(width: frame.size.width, height: frame.size.height)
        }
    }

    /// The wider of the header — its eyebrow or the stage's name, whichever
    /// is longer, in the faces they are set in, with the chest and the stars
    /// — and the row of spoils.
    private var contentWidth: CGFloat {
        let count = CGFloat(loot.count)
        let tiles = count * Self.footprint + max(0, count - 1) * Self.gap
        let eyebrow = Self.measured(eyebrowText, face: "Manrope-ExtraBold", size: 11, tracking: 1.4)
        let name = Self.measured(receipt.stage.name.uppercased(), face: Theme.carvedHeavyFace, size: 20, tracking: 0.8)
        let header = Self.chestWidth + Self.headerGaps + max(eyebrow, name) + Self.starsWidth
        return max(header, tiles)
    }

    /// A line's width as CoreText sets it in a bundled face with its
    /// tracking, so the card is sized before it is laid out; a face that did
    /// not register measures in the system's heavy. A long name that makes
    /// the card wider than the map still shrinks to fit (its scale floor).
    private static func measured(_ text: String, face: String, size: CGFloat, tracking: CGFloat) -> CGFloat {
        let font = UIFont(name: face, size: size) ?? UIFont.systemFont(ofSize: size, weight: .heavy)
        let width = (text as NSString).size(withAttributes: [.font: font, .kern: tracking]).width
        return ceil(width)
    }

    /// About 44 + 10 + 88 + 10 + 46 and the padding — 226 points, or 246
    /// with the line that says the energy ran out, inside the CI phone's
    /// 262-point map.
    private func card(width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(spacing: 10) {
            header
            spoils(inner: width - 28)
            if receipt.cameUpShort {
                // A sweep that silently did eleven of twenty would be read
                // as a bug.
                let done = receipt.runs
                let asked = receipt.requested
                Text("The energy ran out after \(done) of \(asked) runs.")
                    .font(Theme.body(11.5).weight(.bold))
                    .foregroundStyle(Theme.onGlassWarning)
                    .lineLimit(1)
                    .fixedSize()
            }
            PrimaryButton(title: "Continue", action: onClose)
                .frame(width: 220)
        }
        .padding(14)
        .frame(width: width)
        .background(GlassPlate(radius: 16, opacity: 0.9))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.glassRim, lineWidth: 1))
        .shadow(color: .black.opacity(0.6), radius: 22, y: 10)
    }

    /// What the sweep cost, as the header's gold eyebrow.
    private var eyebrowText: String {
        let runs = receipt.runs
        let runWord = runs == 1 ? "RUN" : "RUNS"
        return "SWEPT · \(runs) \(runWord) · \(receipt.energySpent) ENERGY"
    }

    /// The chest, what the sweep cost as a gold eyebrow, the stage's name
    /// carved, and its three stars — a swept stage is three-starred.
    private var header: some View {
        HStack(spacing: 12) {
            TributeChestImage(size: Self.chestWidth)
            VStack(alignment: .leading, spacing: 1) {
                Text(eyebrowText)
                    .font(Theme.body(11).weight(.black))
                    .tracking(1.4)
                    .foregroundStyle(Theme.onGlassEyebrow)
                    .lineLimit(1)
                    .fixedSize()
                Text(receipt.stage.name.uppercased())
                    .font(Theme.display(20))
                    .tracking(0.8)
                    .carved()
                    .lineLimit(1)
                    .minimumScaleFactor(0.66)
            }
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Image(systemName: "star.fill")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(Theme.gold)
                        .shadow(color: Theme.gold.opacity(0.6), radius: 3)
                }
            }
        }
    }

    /// Every spoil as a tile: all of them when they fit, else as many WHOLE
    /// tiles as the card holds, scrolling for the rest, with a chevron to
    /// say so — never a fade across a name.
    private func spoils(inner: CGFloat) -> some View {
        let count = loot.count
        let needed = CGFloat(count) * Self.footprint + CGFloat(max(0, count - 1)) * Self.gap
        let fits = needed <= inner + 0.5
        let whole = max(1, Int((inner - Self.chevron + Self.gap) / (Self.footprint + Self.gap)))
        let window = CGFloat(whole) * Self.footprint + CGFloat(max(0, whole - 1)) * Self.gap
        return Group {
            if fits {
                spoilsRow
                    .frame(maxWidth: .infinity)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        spoilsRow
                    }
                    .frame(width: window)
                    .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Theme.onGlassEyebrow)
                        .frame(width: Self.chevron, height: Self.tile)
                }
            }
        }
    }

    private var spoilsRow: some View {
        HStack(alignment: .top, spacing: Self.gap) {
            ForEach(loot) { item in
                spoilTile(item)
            }
        }
    }

    /// One spoil. A relic is the stone every relic screen draws
    /// (`RelicIcon`, through `RewardTile`'s `relic`): its quality on the
    /// stone's rim and the socket's, its slot on the stone's corner, and its
    /// grade's stars on a band at the socket's foot — inside the socket, so
    /// every name sits on one line — and it opens its card on a tap. It was
    /// the set's painting alone, and the receipt could not say which of the
    /// six slots had dropped (run 224, 34-sweep). Any other graded spoil (a
    /// boon cache) keeps its stars along the socket's top, clear of the
    /// count on its corner.
    private func spoilTile(_ item: BattleSummary.Loot) -> some View {
        let relic = item.relic
        let tap: (() -> Void)?
        if let relic {
            tap = { onRelic(relic) }
        } else {
            tap = nil
        }
        return VStack(spacing: 3) {
            RewardTile(
                key: relic == nil ? (item.key ?? "") : "relic_cache",
                amount: item.amount,
                relic: relic,
                size: Self.tile,
                showsTitle: false,
                showsGrade: false,
                onGlass: true,
                onTap: tap
            )
            .overlay(alignment: .bottom) {
                if let relic {
                    Self.gradeBand(relic.grade)
                }
            }
            .overlay(alignment: .top) {
                if relic == nil, let stars = item.stars {
                    StarRow(stars: stars, size: RewardTile.starSize(stars: stars, width: Self.tile * 0.8))
                        .shadow(color: .black.opacity(0.8), radius: 1)
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }
            }
            Text(Self.caption(item))
                .font(Theme.body(11).weight(.semibold))
                .foregroundStyle(Theme.onGlass)
                // Three lines before an ellipsis: a levelled unit's name
                // ("Terracotta Soldier levelled") takes three in 68 points,
                // and the card has the height for it.
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .frame(width: Self.footprint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: Self.footprint)
    }

    /// A relic's grade at its socket's foot: the stars packed to fit the
    /// stone's width, on the dark band a unit card's stars stand on, so they
    /// read over the stone's lower point and never meet the slot's number on
    /// its top corner, which a row along the top did from 4★ up.
    private static func gradeBand(_ grade: Int) -> some View {
        let room = Self.tile * 0.8 - 6
        let size = max(4, min(Self.tile * 0.1, room / (CGFloat(max(1, grade)) * StarRow.packedAdvance)))
        return StarRow(stars: grade, size: size, packed: true)
            .padding(.horizontal, 3)
            .padding(.vertical, 1.5)
            .background(Capsule().fill(Theme.ink.opacity(0.74)))
            .padding(.bottom, 3)
            .allowsHitTesting(false)
    }

    /// A spoil's name under its tile. A relic is named by its set alone —
    /// "Nemesis Relic" — because the rim already says its quality and the
    /// corner its slot: the loot's full "Normal Nemesis Relic" ran to three
    /// lines in 68 points and printed "Normal / Nemesis R…" (run 217).
    private static func caption(_ item: BattleSummary.Loot) -> String {
        if let relic = item.relic {
            return "\(relic.set.displayName) Relic"
        }
        return item.title
    }
}
