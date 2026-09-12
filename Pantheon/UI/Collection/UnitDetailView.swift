import SwiftUI

/// What one fodder unit costs to feed. `GameStore.levelUp` charges the same
/// figure (`let cost = fodder.count * 500`, GameStore.swift); the two are kept
/// in step by hand, so change both together — the subtitle on the Power up
/// row and the picker's footer are one constant here rather than two literals.
private let fodderDrachmaPerUnit = 500

/// What a painted panel's LAST row has to clear at the bottom.
///
/// `Theme.panelInset` is the horizontal figure and `Theme.panelPadding` the
/// vertical one, but they are measured against `ui_panel`'s flat gold band,
/// which is 7.6 points thick. The bottom corner ornament is not flat: it
/// reaches 16.9 points up and 18.6 in (71 and 78 px of the 512 px @3x texture
/// at `Chrome.shrink`), so a panel whose last row is text or a full-width
/// plate at the leading edge — which is every panel on this sheet — prints on
/// the ornament at anything less. Photographed: the skill panel's "Next
/// skill-up ..." line drawn across the bottom border on CI frame 2-detail.jpg.
///
/// It belongs beside `panelInset` in Theme as `panelBottomInset`; it lives
/// here until the file that owns Theme takes it, so this sheet's four panels
/// at least agree with each other.
private let panelBottomInset: CGFloat = 18

/// The middle column. `relicRing` draws its ring to the panel's inner width
/// off this same figure, so the ring and the column cannot drift apart and
/// leave a tile sitting on the painted band.
private let ringColumnWidth: CGFloat = 212

/// One relic slot in the ring. Named because the ring's height is derived
/// from it: half a tile plus the radius plus the slot badge is what the
/// frame has to hold.
private let slotTileSize: CGFloat = 60

/// The three figures at the foot of the relic ring, and the line under them.
///
/// A type rather than three loose values because the footer is offered to
/// `ViewThatFits` in more than one size, and `ViewThatFits` builds every
/// candidate it is given: computed inside the footer's own body, this
/// arithmetic would resolve the unit and score its six relics once per
/// candidate on every redraw of the sheet.
private struct RelicFigures {
    /// How many of the six slots are filled.
    var worn: Int
    /// What the six slots are worth: the unit's power less the power it would
    /// have with them empty, so a completed set's bonus is counted.
    var gained: Int
    /// The mean of `RelicService.efficiency` over what is worn, 0...1.
    var quality: Double
    /// What to farm next, or nil when there is nothing left to say.
    var note: String?
}

/// One unit on one screen, the way the genre lays it out: the card and its
/// progress on the left, the six relic slots in a ring in the middle, the
/// stats with their relic bonuses on the right, and the skills along the
/// bottom with their words a tap away. Nothing to scroll for on a landscape
/// phone; the lore sits behind the book, and the fodder pickers open as
/// sheets. A relic slot opens the picker for that slot.
struct UnitDetailView: View {
    let unitID: UUID

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var pickingSlot: SlotPick?
    /// A worn relic opened from its slot: the power-up screen.
    @State private var openingRelic: RelicPick?
    @State private var showFodderPicker = false
    @State private var fodderPurpose: FodderPurpose = .levelUp
    @State private var showAwakening = false
    @State private var showLore = false
    @State private var showSets = false
    @State private var selectedSkill = 0

    /// A slot number that can drive a sheet.
    struct SlotPick: Identifiable {
        let id: Int
    }

    struct RelicPick: Identifiable {
        let id: UUID
    }

    enum FodderPurpose { case levelUp, evolve }

    private var unit: ResolvedUnit? { store.resolved(unitID) }
    private var isLocked: Bool { unit?.unit.isLocked == true }

    var body: some View {
        NavigationStack {
            GameScreen(
                unit?.name ?? "Unit",
                subtitle: unit?.blueprint.epithet,
                dismiss: { dismiss() }
            ) {
                BarButton(
                    title: "Lore",
                    systemImage: "book.fill",
                    tint: Theme.textSecondary,
                    showsTitle: false
                ) {
                    showLore = true
                }
                BarButton(title: "Auto-equip", systemImage: "wand.and.stars", tint: Theme.info) {
                    store.autoEquip(unitID)
                }
                // The genre's "remove all", free: the six come off in one tap
                // so another unit can wear them.
                BarButton(title: "Unequip all", systemImage: "minus.circle", tint: Theme.textSecondary, showsTitle: false) {
                    store.unequipAll(unitID)
                    AudioLibrary.shared.play(.uiTap)
                }
                BarButton(
                    title: isLocked ? "Locked" : "Unlocked",
                    systemImage: isLocked ? "lock.fill" : "lock.open",
                    tint: isLocked ? Theme.gold : Theme.textSecondary,
                    showsTitle: false
                ) {
                    store.toggleLock(unitID)
                }
            } content: {
                if let unit {
                    // Three columns, sized so a landscape phone holds the lot
                    // without a scroll: card and actions, the ring, then stats
                    // over skills. No ScrollView — the sheet is one frame, and
                    // each panel stretches to a common bottom rail so no band
                    // of bare backdrop is left under a short column.
                    HStack(alignment: .top, spacing: 8) {
                        identity(unit)
                            .frame(width: 158)
                        relicRing(unit)
                            .frame(width: ringColumnWidth)
                        VStack(spacing: 8) {
                            stats(unit)
                            skills(unit)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, ScreenChrome.contentPadding)
                    .padding(.vertical, 8)
                } else {
                    EmptyState(icon: "questionmark", title: "Gone", message: "This unit is no longer in your collection.")
                }
            }
            .sheet(isPresented: $showFodderPicker) {
                if let unit {
                    FodderPickerView(target: unit, purpose: fodderPurpose)
                        .environmentObject(store)
                }
            }
            .sheet(item: $pickingSlot) { pick in
                RelicPickerView(unitID: unitID, slot: pick.id)
                    .environmentObject(store)
            }
            .sheet(item: $openingRelic) { pick in
                RelicDetailView(relicID: pick.id, role: unit?.role ?? .attacker)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showAwakening) {
                if let unit {
                    AwakeningSheet(unit: unit)
                        .environmentObject(store)
                }
            }
            .sheet(isPresented: $showSets) {
                RelicSetsSheet(unitID: unitID)
                    .environmentObject(store)
            }
            .alert(unit?.blueprint.epithet ?? "", isPresented: $showLore) {
                Button("Close", role: .cancel) {}
            } message: {
                Text(unit?.blueprint.lore ?? "")
            }
        }
    }

    // MARK: - Left: the card and what to do with it

    private func identity(_ unit: ResolvedUnit) -> some View {
        VStack(spacing: 6) {
            UnitCard(unit: unit, size: 100)
            HStack(spacing: 4) {
                ElementBadge(element: unit.element, compact: true)
                Text(unit.blueprint.epithet)
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            // `grantExperience` zeroes the stored experience at the cap, so a
            // maxed unit's bar read "0 / 1400" under a full level — the same
            // lie the fodder footer was fixed for. Fill it and say MAX.
            let toNextLevel = Double(ProgressionService.experienceForNextLevel(
                level: unit.level, stars: unit.stars
            ))
            StatBar(
                value: unit.unit.isMaxLevel ? toNextLevel : Double(unit.unit.experience),
                maximum: toNextLevel,
                tint: unit.unit.isMaxLevel ? Theme.gold : Theme.info,
                height: 5,
                label: unit.unit.isMaxLevel
                    ? "Lv.\(unit.level) · MAX"
                    : "Lv.\(unit.level) / \(unit.unit.maxLevel)"
            )
            Spacer(minLength: 0)
            // The three things to do with a unit, one wide row each: a 4pt
            // label in a square tile was the least legible thing on the most
            // important control, so each row now says what it costs and
            // whether it is ready.
            VStack(spacing: 4) {
                actionButton(
                    "Power up",
                    unit.unit.isMaxLevel
                        ? "Max level · feed duplicates to skill up"
                        : "\(fodderDrachmaPerUnit) drachma per unit",
                    "arrow.up.circle.fill", tint: Theme.info
                ) {
                    fodderPurpose = .levelUp
                    showFodderPicker = true
                }
                actionButton(
                    "Evolve", evolveSubtitle(unit),
                    "star.circle.fill", tint: Theme.gold, enabled: unit.unit.canEvolve
                ) {
                    fodderPurpose = .evolve
                    showFodderPicker = true
                }
                if let awakening = unit.blueprint.awakening {
                    let ready = awakening.essenceCost.allSatisfy { (store.player.essences[$0.key] ?? 0) >= $0.value }
                    actionButton(
                        unit.unit.isAwakened ? "Awakened" : "Awaken",
                        unit.unit.isAwakened
                            ? "Form unlocked"
                            : (ready ? "Essences ready" : "Essences short"),
                        "sun.max.fill", tint: Theme.gold, enabled: !unit.unit.isAwakened
                    ) {
                        showAwakening = true
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, Theme.panelInset)
        .padding(.top, Theme.panelPadding)
        // The last row is the Awaken plate, full width and at the leading
        // edge, so it needs the ornament's 17 points rather than the band's 8.
        // It costs nothing: the `Spacer` above the action rows measures 46
        // points on CI frame 2-detail.jpg and simply gives ten of them back.
        .padding(.bottom, panelBottomInset)
        .panelBackground(radius: Theme.tightCorner)
    }

    /// Why the Evolve row is lit or dark. `canEvolve` is false for two
    /// different reasons — short of the level cap, and already 6★ — and the
    /// one line of copy told a maxed 6★ to "Reach Lv.65 first" while it stood
    /// at Lv.65.
    private func evolveSubtitle(_ unit: ResolvedUnit) -> String {
        if unit.stars >= 6 { return "Fully evolved · 6★" }
        guard unit.unit.canEvolve else { return "Reach Lv.\(unit.unit.maxLevel) first" }
        let fodder = ProgressionService.evolutionFodderRequired(currentStars: unit.stars)
        let cost = ProgressionService.drachmaCostToEvolve(currentStars: unit.stars)
        return "\(fodder) × \(unit.stars)★ · \(cost) drachma"
    }

    private func actionButton(
        _ title: String, _ subtitle: String, _ symbol: String, tint: Color,
        enabled: Bool = true, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(Theme.body(10).weight(.bold))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(Theme.body(8))
                        .lineLimit(1)
                        // "Max level · feed duplicates to skill up" is the
                        // longest of these and lays out at ~137 points against
                        // the 100 the row has inside the panel's proper inset,
                        // so at 0.8 it ellipsised. A subtitle shrinks rather
                        // than truncating: the figure it names is the point.
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(enabled ? Theme.ink : Theme.textSecondary)
            .padding(.horizontal, 7)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(enabled ? tint : Theme.surface)
            )
        }
        .buttonStyle(PlateButtonStyle())
        .disabled(!enabled)
    }

    // MARK: - Middle: the relic ring

    /// Six slots around the element's emblem, slot 1 at the top and the
    /// rest clockwise — the arrangement every player of the genre knows.
    private func relicRing(_ unit: ResolvedUnit) -> some View {
        let radius: CGFloat = 67
        // The ring is drawn to the panel's inner width rather than to a flat
        // 196, so it and the sets row under it share a centre line and neither
        // can reach the painted band: a tile's far corner is 88 points from
        // the centre and its slot badge 92, against the 94 the box allows.
        let width = ringColumnWidth - Theme.panelInset * 2
        // Tall enough to hold a slot badge, which is drawn four points up and
        // left of its tile's corner. The old square 196 held the tiles with a
        // point to spare but not their badges, so the top slot's badge was
        // drawn three points into the panel's painted top band — measured on
        // CI frame 2-detail.jpg, badge top at 69 px against the band's inner
        // edge at 74.
        let height = (radius + slotTileSize / 2 + 5) * 2
        let centre = CGPoint(x: width / 2, y: height / 2)
        let figures = relicFigures(unit)
        return VStack(spacing: 6) {
            ZStack {
                // The rune hexagon: one thin line through the six sockets.
                Path { path in
                    for slot in 0..<6 {
                        let angle = (Double(slot) * 60 - 90) * Double.pi / 180
                        let point = CGPoint(x: centre.x + CGFloat(cos(angle)) * radius, y: centre.y + CGFloat(sin(angle)) * radius)
                        if slot == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    path.closeSubpath()
                }
                .stroke(Theme.goldDim.opacity(0.35), lineWidth: 1)
                // The largest clear space on the sheet carries the number the
                // whole sheet exists to raise, not a second copy of the element.
                VStack(spacing: 2) {
                    ZStack {
                        Circle()
                            .fill(unit.element.color.opacity(0.18))
                            .frame(width: 34, height: 34)
                        Image(systemName: unit.element.glyph)
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(unit.element.color)
                    }
                    Text("\(unit.power)")
                        .font(Theme.numeric(16))
                        .foregroundStyle(Theme.gold)
                        // The clear disc inside the ring is 74pt across; five
                        // monospaced digits at 16 are 43 of them and six would
                        // touch the tiles at 2 and 6 o'clock.
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: 74)
                    Text("POWER")
                        .font(Theme.body(8).weight(.black))
                        .tracking(1)
                        .foregroundStyle(Theme.textSecondary)
                }
                .position(centre)
                ForEach(1...6, id: \.self) { slot in
                    let angle = (Double(slot - 1) * 60 - 90) * Double.pi / 180
                    slotTile(slot: slot, unit: unit)
                        .position(
                            x: centre.x + CGFloat(cos(angle)) * radius,
                            y: centre.y + CGFloat(sin(angle)) * radius
                        )
                }
            }
            .frame(width: width, height: height)
            setsRow(unit)
            // The footer takes what the ring and the sets row leave, and the
            // frame around it pins it to the panel's bottom rail rather than
            // letting it hang under the sets row with ninety-odd points of
            // bare metal below.
            //
            // It is offered in three sizes because the room under the sets
            // row swings by forty points and the panel cannot grow to cover
            // the difference. Measured against the panel on CI frame
            // 2-detail.jpg (322.4pt tall, so 296.4 inside the paddings, less
            // the ring's 204 and the stack's 18 of spacing): a unit with no
            // relics leaves 55 points, one completed set 58, two 38 — and six
            // relics in three completed sets, which is the build this screen
            // exists to admire, leaves 18.3. On a 375-point-tall phone in
            // landscape that last case leaves 1.4. The full footer wants 25.5
            // without its note and 38.1 with it, so a fixed block would have
            // printed over the bottom ornament on exactly the unit most worth
            // looking at — the fault the rest of this pass is fixing.
            // `ViewThatFits` measures each candidate's ideal height against
            // what is left and takes the first that fits, so the footer sheds
            // its note, then its captions, then itself.
            //
            // No `Spacer` here and none inside a candidate: a greedy view has
            // no ideal height and `ViewThatFits` chooses on the ideal, which
            // is the same reason `ArenaView.teamCards` has none.
            ViewThatFits(in: .vertical) {
                relicSummary(figures)
                compactRelicSummary(figures)
                Color.clear.frame(height: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, Theme.panelInset)
        .padding(.top, Theme.panelPadding)
        // The footer's captions are this panel's last row and sit at the
        // leading edge, so they need the corner ornament's clearance.
        .padding(.bottom, panelBottomInset)
        .panelBackground(radius: Theme.tightCorner)
    }

    private func slotTile(slot: Int, unit: ResolvedUnit) -> some View {
        let relic = unit.unit.equippedRelics[slot].flatMap { store.player.relic($0) }
        return RelicSlotTile(slot: slot, relic: relic, size: slotTileSize) {
            Juice.haptic(.light)
            // A worn relic opens its power-up screen (Change is on it);
            // an empty slot opens the picker.
            if let relic {
                openingRelic = RelicPick(id: relic.id)
            } else {
                pickingSlot = SlotPick(id: slot)
            }
        }
    }

    /// Every set with a piece on the ring as a progress chip — "Fury 2/2"
    /// lit in gold where the set is complete, "Fates 1/4" dim where it is
    /// not — and a book that opens the set reference counting this unit's
    /// pieces. The genre shows a set's count against its need beside the
    /// rune hexagon; the completed-only chips before this left a player to
    /// work out from six stones which set was one piece short.
    private func setsRow(_ unit: ResolvedUnit) -> some View {
        let tally = Dictionary(grouping: unit.relics, by: { $0.set }).mapValues(\.count)
        // Complete sets first, then the nearest to complete, then by name,
        // so the order is the same on every launch.
        let entries = tally.keys.sorted { a, b in
            let ca = tally[a, default: 0] / a.piecesRequired, cb = tally[b, default: 0] / b.piecesRequired
            if ca != cb { return ca > cb }
            let ra = tally[a, default: 0] % a.piecesRequired, rb = tally[b, default: 0] % b.piecesRequired
            if ra != rb { return ra > rb }
            return a.displayName < b.displayName
        }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 72, maximum: 120), spacing: 4)], spacing: 4) {
            ForEach(entries) { relicSet in
                let count = tally[relicSet, default: 0]
                let complete = count >= relicSet.piecesRequired
                HStack(spacing: 4) {
                    RelicSetEmblem(set: relicSet, size: 12, tint: complete ? Theme.gold : Theme.textSecondary)
                    Text("\(relicSet.displayName) \(count)/\(relicSet.piecesRequired)")
                        .font(Theme.body(10).weight(.bold))
                        .foregroundStyle(complete ? Theme.gold : Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, 6)
                .frame(height: 22)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(complete ? Theme.surfaceHigh : Theme.surface))
                .overlay(Capsule().strokeBorder(complete ? Theme.gold.opacity(0.35) : Theme.stroke.opacity(0.6), lineWidth: 1))
            }
            Button {
                Juice.haptic(.light)
                showSets = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(entries.isEmpty ? "Set effects" : "Sets")
                        .font(Theme.body(10).weight(.bold))
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.gold)
                .padding(.horizontal, 6)
                .frame(height: 22)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(Theme.surface))
                .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    /// The three figures the footer prints, worked out once for every
    /// candidate `ViewThatFits` builds.
    private func relicFigures(_ unit: ResolvedUnit) -> RelicFigures {
        // The same unit with nothing equipped. `power` is a function of the
        // stats alone, so resolving with an empty relic list gives the bare
        // figure and the difference is what the six slots are worth — set
        // bonuses included, which is why this resolves rather than adding up
        // the relics' own modifiers.
        let bare = ProgressionService.resolve(unit.unit, blueprint: unit.blueprint, equipped: [])
        // The inventory's efficiency, averaged over what is worn: the same
        // 0...1 score the dials there show, so a player who has learned to
        // read one number has not been given a second.
        let scored = unit.relics.reduce(0.0) { $0 + RelicService.efficiency($1, for: unit.role) }
        return RelicFigures(
            worn: unit.relics.count,
            gained: unit.power - bare.power,
            quality: unit.relics.isEmpty ? 0 : scored / Double(unit.relics.count),
            note: setProgressNote(unit)
        )
    }

    /// The bottom of the ring panel: what the six slots are actually worth.
    ///
    /// The ring is a fixed frame and the sets row is at most three lines, so
    /// under them sat the largest dead area on the sheet — 97 points of bare
    /// metal on CI frame 2-detail.jpg, more than a quarter of the panel. What
    /// belongs there is the arithmetic the ring cannot show: how much of the
    /// power in its centre the relics bought, how good the pieces on it are
    /// for this unit's role, and which set is a piece short. None of the three
    /// is anywhere else in the app — the inventory scores one relic at a time,
    /// and the stats panel shows the bonus per stat but never the total.
    private func relicSummary(_ figures: RelicFigures) -> some View {
        VStack(spacing: 4) {
            Divider().overlay(Theme.stroke)
            HStack(alignment: .top, spacing: 4) {
                summaryFigure(
                    Text("\(figures.worn)/6"), "SLOTS",
                    tint: figures.worn == 6 ? Theme.gold : Theme.textPrimary
                )
                summaryFigure(
                    figures.gained > 0 ? Text("+\(figures.gained)") : Text("—"), "FROM RELICS",
                    tint: figures.gained > 0 ? Theme.success : Theme.textSecondary
                )
                summaryFigure(
                    figures.worn == 0 ? Text("—") : Text("\(Int((figures.quality * 100).rounded()))%"),
                    "QUALITY",
                    tint: figures.worn == 0 ? Theme.textSecondary : qualityTint(figures.quality)
                )
            }
        }
    }

    /// The same three figures on one line, for the unit that leaves the footer
    /// eighteen points instead of forty: six relics in three completed sets.
    ///
    /// The captions go, because in the panel that draws the ring "5/6", a
    /// green "+1,240" and a percentage cannot be read as anything else, and
    /// the note goes with them — which costs nothing, since a unit whose sets
    /// are all complete and whose slots are all full has no note to print.
    private func compactRelicSummary(_ figures: RelicFigures) -> some View {
        // Bound to locals rather than written as parenthesised ternaries in
        // the builder: a line that opens with a left parenthesis is parsed as
        // an argument list for the expression on the line above it, so the
        // separator before it would be asked to call itself.
        let gained = figures.gained > 0 ? Text("+\(figures.gained)") : Text("—")
        let quality = figures.worn == 0
            ? Text("—")
            : Text("\(Int((figures.quality * 100).rounded()))%")
        return VStack(spacing: 3) {
            Divider().overlay(Theme.stroke)
            HStack(spacing: 5) {
                Text("\(figures.worn)/6")
                    .foregroundStyle(figures.worn == 6 ? Theme.gold : Theme.textPrimary)
                Text("·").foregroundStyle(Theme.textSecondary)
                gained
                    .foregroundStyle(figures.gained > 0 ? Theme.success : Theme.textSecondary)
                Text("·").foregroundStyle(Theme.textSecondary)
                quality
                    .foregroundStyle(figures.worn == 0 ? Theme.textSecondary : qualityTint(figures.quality))
            }
            .font(Theme.numeric(9))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
        }
    }

    /// One figure over its name. `Text` rather than `String` so the number
    /// keeps its thousands separator: SwiftUI groups an integer interpolated
    /// into a `Text`, and a pre-built `String` would read "1240" beside the
    /// ring's own "1,240".
    private func summaryFigure(_ value: Text, _ caption: String, tint: Color) -> some View {
        VStack(spacing: 0) {
            value
                .font(Theme.numeric(12))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(caption)
                .font(Theme.body(7).weight(.black))
                .tracking(0.6)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    /// The efficiency dial's own thresholds (`EfficiencyDial.tint`), so a
    /// relic that reads green in the inventory reads green here too.
    private func qualityTint(_ value: Double) -> Color {
        value >= 0.7 ? Theme.success : (value >= 0.45 ? Theme.gold : Theme.textSecondary)
    }

    /// The slots that are simply empty, in one line. The sets in progress
    /// used to be here too; the sets row's chips count them now, against
    /// each set's need, so the footer says only what the chips cannot.
    ///
    /// Nil when the ring is full: there is nothing left to say.
    private func setProgressNote(_ unit: ResolvedUnit) -> String? {
        let empty = 6 - unit.relics.count
        guard empty > 0 else { return nil }
        return "\(empty) slot\(empty == 1 ? "" : "s") empty · Auto-equip fills them"
    }

    // MARK: - Right: the stats

    private func stats(_ unit: ResolvedUnit) -> some View {
        // Base is grade, level and awakening; the difference to the final
        // number is the relics, shown beside it the way the genre does, so
        // equipping a relic is visible on the sheet and not only in battle.
        let base = ProgressionService.baseStats(for: unit.unit, blueprint: unit.blueprint)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                StarRow(stars: unit.stars, natural: unit.blueprint.naturalStars, size: 10)
                tag(unit.pantheon.displayName, color: unit.pantheon.color)
                tag(unit.archetype.displayName, color: Theme.textSecondary)
                tag(unit.role.displayName, color: Theme.textSecondary)
            }
            .padding(.bottom, 3)
            HStack(alignment: .top, spacing: 8) {
                VStack(spacing: 3) {
                    statRow("HP", base.hp, unit.stats.hp, strong: true)
                    statRow("ATK", base.atk, unit.stats.atk, strong: true)
                    statRow("DEF", base.def, unit.stats.def, strong: true)
                    statRow("SPD", base.spd, unit.stats.spd, strong: true)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: 3) {
                    statRow("CRIT Rate", base.critRate, unit.stats.critRate, percent: true)
                    statRow("CRIT DMG", base.critDamage, unit.stats.critDamage, percent: true)
                    statRow("Accuracy", base.accuracy, unit.stats.accuracy, percent: true)
                    statRow("Resistance", base.resistance, unit.stats.resistance, percent: true)
                }
                .frame(maxWidth: .infinity)
            }
            if let leader = unit.blueprint.leaderSkill {
                Divider().overlay(Theme.stroke).padding(.vertical, 2)
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.gold)
                    Text(leader.description)
                        .font(Theme.body(9))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let awakening = unit.blueprint.awakening {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(unit.unit.isAwakened ? Theme.gold : Theme.textSecondary)
                    Text(unit.unit.isAwakened
                         ? "Awakened: \(awakening.bonusDescription)"
                         : "Awakens into \(awakening.awakenedName): \(awakening.bonusDescription)")
                        .font(Theme.body(9))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The first row here is the star row and the three tags, drawn corner
        // to corner: at the old flat 8 the leading star was inside the top-left
        // ornament (18.6 x 16.9 points) and the Controller tag inside the
        // top-right one. The panel has ~77 points of unused height under the
        // awakening line, so the ornament's clearance at the bottom is free.
        .padding(.horizontal, Theme.panelInset)
        .padding(.top, Theme.panelPadding)
        .padding(.bottom, panelBottomInset)
        .panelBackground(radius: Theme.tightCorner)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.body(9).weight(.semibold))
            .lineLimit(1)
            // "Mesopotamian" + "Primordial" + "Controller" beside a 6★ star row
            // is 256 points against the 245 the panel has on a 667-point
            // landscape phone; without this the row runs off the panel.
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    /// Three columns — label, total, relic bonus — so the numbers line up down
    /// the group instead of landing on a ragged edge that moves per row.
    /// `strong` weights the four combat stats over the four percentages.
    ///
    /// The two number columns are fixed and the label takes what is left. All
    /// three were fixed at 54/44/36, which is 142 a group and 292 for the pair:
    /// the stats panel is 245 points wide inside its padding on a 667-point
    /// landscape phone, and a fixed frame does not shrink — the relic-bonus
    /// column was drawn 47 points past the panel and off the screen. A flexible
    /// label costs nothing on a wide phone, where it simply gets more room.
    private func statRow(
        _ label: String, _ base: Double, _ total: Double,
        percent: Bool = false, strong: Bool = false
    ) -> some View {
        let bonus = total - base
        let shown = abs(bonus) >= (percent ? 0.005 : 0.5)
        return HStack(spacing: 4) {
            Text(label)
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(Self.statText(total, percent: percent))
                .font(strong ? Theme.numeric(13) : Theme.numeric(11))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 44, alignment: .trailing)
            Text(shown ? ((bonus > 0 ? "+" : "−") + Self.statText(abs(bonus), percent: percent)) : "")
                .font(Theme.numeric(9))
                .foregroundStyle(bonus > 0 ? Theme.success : Theme.danger)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 32, alignment: .trailing)
        }
    }

    static func statText(_ value: Double, percent: Bool) -> String {
        percent ? "\(Int((value * 100).rounded()))%" : "\(Int(value.rounded()))"
    }

    /// The stat a skill's damage is multiplied by, so a max-health or defence
    /// skill no longer advertises the figure it would hit for off ATK.
    static func scalingStat(_ scaling: DamageScaling, _ stats: Stats) -> Double {
        switch scaling {
        case .attack: return stats.atk
        case .maxHealth: return stats.hp
        case .defense: return stats.def
        case .speed: return stats.spd
        }
    }

    // MARK: - Bottom: the skills

    private func skills(_ unit: ResolvedUnit) -> some View {
        let index = min(selectedSkill, max(0, unit.skills.count - 1))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(unit.skills.indices, id: \.self) { slot in
                    Button {
                        Juice.haptic(.light)
                        selectedSkill = slot
                    } label: {
                        skillTile(
                            unit.skills[slot],
                            selected: slot == index,
                            level: unit.unit.skillLevels.indices.contains(slot) ? unit.unit.skillLevels[slot] : 1
                        )
                    }
                    .buttonStyle(PlateButtonStyle())
                }
            }
            if unit.skills.indices.contains(index) {
                skillWords(unit.skills[index], index: index, unit: unit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.panelInset)
        .padding(.top, Theme.panelPadding)
        // The photographed overlap. The skill-up hint is this panel's last row
        // and starts at its leading edge — the worst corner there is — so at
        // the old flat 8 its first word was drawn on the bottom-left ornament
        // and its baseline sat on the flat band: on CI frame 2-detail.jpg the
        // panel's outer bottom edge is at 360.8pt, the text's bottom at 353.7,
        // and the ornament's mass begins at 344.6. The stats panel above is in
        // the same column with ~77 points spare and pays for the ten.
        .padding(.bottom, panelBottomInset)
        .panelBackground(radius: Theme.tightCorner)
    }

    private func skillTile(_ skill: Skill, selected: Bool, level: Int) -> some View {
        VStack(spacing: 2) {
            Image(systemName: SkillButton.glyph(for: skill))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(selected ? Theme.gold : Theme.textSecondary)
            Text(skill.name)
                .font(Theme.body(9).weight(.semibold))
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.8)
            Text("Lv.\(level)/\(skill.maxSkillLevel)")
                .font(Theme.numeric(7))
                .foregroundStyle(level >= skill.maxSkillLevel ? Theme.gold : Theme.textSecondary)
        }
        .padding(.horizontal, 3)
        // The tiles divide the row rather than sitting at a fixed 58 with a
        // Spacer holding the rest of it open — which also overflowed on a
        // narrower phone.
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(selected ? Theme.surfaceHigh : Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .strokeBorder(selected ? Theme.gold : Theme.stroke, lineWidth: selected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
    }

    private func skillWords(_ skill: Skill, index: Int, unit: ResolvedUnit) -> some View {
        let level = unit.unit.skillLevels.indices.contains(index) ? unit.unit.skillLevels[index] : 1
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(skill.name)
                    .font(Theme.body(12).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    // Unbounded, a long name ("Judgement of the Nine Bows")
                    // wrapped to two lines and took the whole panel a line
                    // taller, which is the one direction this sheet cannot
                    // afford to grow.
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if skill.isPassive {
                    Text("PASSIVE")
                        .font(Theme.body(7).weight(.black))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.gold.opacity(0.25)))
                        .foregroundStyle(Theme.gold)
                }
                if skill.cooldown > 0 {
                    Label("\(skill.cooldown) turns", systemImage: "clock.fill")
                        .font(Theme.numeric(9))
                        .foregroundStyle(Theme.textSecondary)
                }
                if let damage = skill.damage {
                    // previewDamage already multiplies by the hit count, so the
                    // old " × 3" read as an instruction to triple the figure.
                    let estimate = DamageCalculator.previewDamage(
                        attackStat: Self.scalingStat(damage.scaling, unit.stats), spec: damage
                    )
                    Text("≈ \(Int(estimate)) dmg" + (damage.hits > 1 ? " · \(damage.hits) hits" : ""))
                        .font(Theme.numeric(9))
                        .foregroundStyle(Theme.gold)
                }
                Spacer()
                if !skill.levelUpBonuses.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(skill.levelUpBonuses.indices, id: \.self) { bonusIndex in
                            Circle()
                                .fill(level > bonusIndex + 1 ? Theme.success : Theme.stroke)
                                .frame(width: 6, height: 6)
                        }
                        Text("skill-ups")
                            .font(Theme.body(8))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            Text(skill.description)
                .font(Theme.body(9))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let next = skill.levelUpBonuses.indices.first(where: { level <= $0 + 1 }) {
                Text("Next skill-up: \(skill.levelUpBonuses[next].label) — feed a duplicate in the Hall of Ka.")
                    .font(Theme.body(8))
                    .foregroundStyle(Theme.goldDim)
                    .lineLimit(1)
                    // A long bonus label ("Cooldown −1 turn", "Harm +10%")
                    // pushed this past the panel on a 667-point phone and it
                    // ellipsised mid-sentence. It shrinks a step instead.
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Awakening in one sheet: the form it has and the form it becomes, what the
/// change is worth, and the essences it costs.
struct AwakeningSheet: View {
    let unit: ResolvedUnit

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GameScreen("Awakening", subtitle: unit.name, dismiss: { dismiss() }) {
                EmptyView()
            } content: {
                ScrollView {
                    if let awakening = unit.blueprint.awakening {
                        let costs = awakening.essenceCost.sorted { $0.key < $1.key }
                        let affordable = awakening.essenceCost.allSatisfy { (store.player.essences[$0.key] ?? 0) >= $0.value }
                        HStack(alignment: .top, spacing: 14) {
                            formTile(unit.blueprint.model.portraitName(awakened: false), caption: unit.blueprint.name)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(Theme.gold)
                                .frame(height: 136)
                            formTile(unit.blueprint.model.portraitName(awakened: true), caption: awakening.awakenedName)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(awakening.awakenedName)
                                    .font(Theme.title(16))
                                    .foregroundStyle(Theme.gold)
                                Text(awakening.bonusDescription)
                                    .font(Theme.body(12))
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                ForEach(costs.indices, id: \.self) { costIndex in
                                    let id = costs[costIndex].key
                                    let needed = costs[costIndex].value
                                    let have = store.player.essences[id] ?? 0
                                    HStack {
                                        Text(EssenceCatalog.name(for: id))
                                            .font(Theme.body(12))
                                            .foregroundStyle(Theme.textSecondary)
                                        Spacer()
                                        Text("\(have) / \(needed)")
                                            .font(Theme.numeric(12))
                                            .foregroundStyle(have >= needed ? Theme.success : Theme.danger)
                                    }
                                }
                                if unit.unit.isAwakened {
                                    Text("Already awakened.")
                                        .font(Theme.body(12))
                                        .foregroundStyle(Theme.gold)
                                } else {
                                    PrimaryButton(title: "Awaken", systemImage: "sun.max.fill", isEnabled: affordable) {
                                        store.awaken(unit.id)
                                        dismiss()
                                    }
                                    Text("Essences drop in the Halls of Essence, in the Labyrinth on the island.")
                                        .font(Theme.body(10))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, ScreenChrome.contentPadding)
                        .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    private func formTile(_ portrait: String, caption: String) -> some View {
        VStack(spacing: 4) {
            if BundleImage.exists(portrait) {
                BundleImage(name: portrait)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 104, height: 136)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
                    // A near-square portrait filled into a 104x136 frame hangs
                    // ~30 points past each side, and clipShape does not clip
                    // hit-testing: without this the art swallows taps meant for
                    // the Awaken button beside it.
                    .allowsHitTesting(false)
            } else {
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(Theme.surface)
                    .frame(width: 104, height: 136)
            }
            Text(caption)
                .font(Theme.body(11).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
        }
    }
}

/// Picks units to consume for levelling or evolution.
struct FodderPickerView: View {
    let target: ResolvedUnit
    let purpose: UnitDetailView.FodderPurpose

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID> = []

    private var candidates: [ResolvedUnit] {
        store.resolvedUnits.filter { candidate in
            guard candidate.id != target.id, !candidate.unit.isLocked else { return false }
            if purpose == .evolve { return candidate.stars == target.stars }
            return true
        }
        .sorted { $0.power < $1.power }
    }

    private var required: Int {
        purpose == .evolve
            ? ProgressionService.evolutionFodderRequired(currentStars: target.stars)
            : 0
    }

    var body: some View {
        NavigationStack {
            GameScreen(
                purpose == .evolve ? "Evolve" : "Power up",
                subtitle: target.name,
                dismiss: { dismiss() }
            ) {
                EmptyView()
            } content: {
                ScrollView {
                    if candidates.isEmpty {
                        EmptyState(
                            icon: "tray",
                            title: "No fodder available",
                            message: purpose == .evolve
                                ? "Evolution needs \(required) unlocked units at exactly \(target.stars)★."
                                : "Every other unit you own is locked."
                        )
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 96), spacing: 8)], spacing: 10) {
                            ForEach(candidates) { candidate in
                                Button {
                                    toggle(candidate.id)
                                } label: {
                                    UnitCard(unit: candidate, isSelected: selection.contains(candidate.id), size: 76)
                                }
                            }
                        }
                        .padding(.horizontal, ScreenChrome.contentPadding)
                        .padding(.vertical, 8)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 6) {
                        let cost = purpose == .evolve
                            ? ProgressionService.drachmaCostToEvolve(currentStars: target.stars)
                            : selection.count * fodderDrachmaPerUnit
                        if purpose == .evolve {
                            Text("\(selection.count) / \(required) selected · \(cost) drachma")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        } else {
                            let xp = candidates
                                .filter { selection.contains($0.id) }
                                .reduce(0) { $0 + ProgressionService.feedValue(of: $1.unit) }
                            let duplicates = candidates.filter {
                                selection.contains($0.id) && $0.unit.blueprintID == target.unit.blueprintID
                            }.count
                            // A unit at its cap gains no experience — the old
                            // "+18,400 EXP" was a lie and the fodder vanished
                            // for nothing unless it was a duplicate.
                            Text(target.unit.isMaxLevel
                                 ? "Max level · no EXP · \(duplicates) duplicate\(duplicates == 1 ? "" : "s") will skill up"
                                 : "+\(xp) EXP · \(cost) drachma")
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        // GameStore bails silently when the drachma is short,
                        // so the button says so rather than closing on nothing.
                        Text("You have \(store.player.wallet.drachma) drachma")
                            .font(Theme.numeric(10))
                            .foregroundStyle(store.player.wallet.drachma >= cost ? Theme.textSecondary : Theme.danger)
                        PrimaryButton(
                            title: purpose == .evolve ? "Evolve" : "Consume",
                            isEnabled: (purpose == .evolve ? selection.count == required : !selection.isEmpty)
                                && store.player.wallet.drachma >= cost
                        ) {
                            commit()
                        }
                    }
                    .padding(10)
                    .background(Theme.surfaceRaised)
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else if purpose != .evolve || selection.count < required {
            selection.insert(id)
        }
    }

    private func commit() {
        let ids = Array(selection)
        switch purpose {
        case .levelUp: store.levelUp(target.id, feeding: ids)
        case .evolve: store.evolve(target.id, fodderIDs: ids)
        }
        dismiss()
    }
}

/// One relic socket: the stone alone in a soft recess, its level on its
/// corner — or, empty, the slot's silhouette as a ghost with the slot's
/// number on it. The genre's rune hexagon is bare stones; the numbers are
/// read on a tap.
///
/// It was a bordered tile with two badges (the slot's number, the level),
/// a stone a third its size and three lines of seven-point text under it,
/// and the owner sent a crop of the ring with "look how ugly this is"
/// (2026-09-12). Shared by the unit sheet's ring, the collection's plate
/// and its stage layout; what a tap does is the caller's.
struct RelicSlotTile: View {
    let slot: Int
    let relic: Relic?
    var size: CGFloat = 60
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // The recess: darker towards the rim, no border.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Theme.surfaceRaised.opacity(0.9), Theme.stroke.opacity(0.45)],
                            center: .center, startRadius: size * 0.12, endRadius: size * 0.5
                        )
                    )
                Circle()
                    .strokeBorder(Theme.stroke.opacity(0.5), lineWidth: 0.5)
                if let relic {
                    RelicIcon(relic: relic, size: size * 0.74, showsStars: false, showsLevel: true)
                } else {
                    if let ghost = BundleArt.image(Relic.rimImageName) {
                        Image(uiImage: ghost)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(Theme.goldDim.opacity(0.35))
                            .frame(width: size * 0.64, height: size * 0.64)
                    }
                    Text("\(slot)")
                        .font(Theme.title(13))
                        .foregroundStyle(Theme.goldDim.opacity(0.85))
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(PlateButtonStyle())
    }
}
