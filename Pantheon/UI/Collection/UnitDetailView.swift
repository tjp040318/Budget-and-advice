import SwiftUI

/// What one fodder unit costs to feed. `GameStore.levelUp` charges the same
/// figure (`let cost = fodder.count * 500`, GameStore.swift); the two are kept
/// in step by hand, so change both together — the picker's footer reads this
/// one constant rather than a literal of its own. (The Power up row printed
/// it too until phase B made that row the gold `PrimaryButton`, 2026-09-22.)
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

/// What `UnitCard` draws under its square since the type floor of
/// 2026-09-22: the name at body 11 over the level and power at numeric
/// 11.5, with 3 and 4 of padding — 41 points, measured off run 211's unit
/// sheet (a 100-point card 141 tall). `Theme.cardCaptionHeight` still says
/// 36 at that size; the identity column sizes its card off this.
private let cardCaption: CGFloat = 41

/// The fade at the foot of a panel body that scrolls (`SheetPanelScroll`),
/// and the room its last line keeps under it so it can scroll clear.
private let panelFade: CGFloat = 14

/// A panel's body that scrolls INSIDE its panel and ends in a fade.
///
/// The unit sheet is one frame since phase B (2026-09-22): three columns,
/// each exactly the frame's height, the painted panels fixed and only what
/// cannot fit scrolling inside them. The whole sheet scrolled before, and
/// every column was taller than the phone — run 211's frame 2 cut the ring
/// panel's regalia row, the Evolve and Awaken rows and the skills' words at
/// the frame's foot with nothing to say there was more, the critic's
/// "clipped". Here the last line fades instead of being cut, the things a
/// player acts on (the buttons, the ring, the skill icons) are pinned
/// outside the scroll, and the regalia is the first thing in the ring's
/// scroll, whole at rest.
private struct SheetPanelScroll<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.bottom, panelFade)
        }
        .scrollBounceBehavior(.basedOnSize)
        .mask(
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: panelFade)
            }
        )
    }
}

/// The three figures at the foot of the relic ring, and the line under them.
///
/// A type rather than three loose values so the arithmetic — resolving the
/// unit bare and scoring its six relics — is done once per pass, outside the
/// builder. (It was offered to `ViewThatFits` in three sizes until phase B,
/// which built every candidate; the footer scrolls in its panel now.)
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
/// bottom with their words a tap away. The sheet is one landscape frame;
/// only a panel's overflow scrolls, inside the panel (`SheetPanelScroll`).
/// The lore sits behind the book, and the fodder pickers open as sheets. A
/// relic slot opens the picker for that slot.
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
    @State private var showBoons = false
    @State private var showRegalia = false
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
                    // Three columns: card and actions, the ring, then stats
                    // over skills — and the sheet is ONE frame, every column
                    // exactly its height (2026-09-22, phase B). The whole
                    // sheet scrolled from run 204, because a column taller
                    // than the frame overflowed the VStack it sits in, which
                    // centred it and pushed the strip's top half off the
                    // screen; but all three columns were taller than the
                    // phone, so the frame cut the regalia row, the Evolve and
                    // Awaken rows and the skills' words at its foot (run 211,
                    // frame 2). Now each panel is the frame's height and only
                    // what does not fit scrolls INSIDE it, ending in a fade
                    // (`SheetPanelScroll`); the buttons, the ring and the
                    // skill icons are pinned, and the regalia is the first
                    // thing in the ring's scroll, whole. The GeometryReader
                    // reports exactly the space it is given, so nothing here
                    // can push the strip again.
                    //
                    // The frame is a sheet's (no tab bar): 402 − 21 − 52 − 16
                    // = 313 points on an iPhone 16 Pro, 304 on an iPhone 16.
                    GeometryReader { geometry in
                        let height = geometry.size.height.isFinite ? max(0, geometry.size.height) : 0
                        HStack(alignment: .top, spacing: 8) {
                            identity(unit, height: height)
                                .frame(width: 158)
                            relicRing(unit)
                                .frame(width: ringColumnWidth)
                            VStack(spacing: 8) {
                                stats(unit)
                                    .fixedSize(horizontal: false, vertical: true)
                                skills(unit)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .frame(height: height, alignment: .top)
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
            .sheet(isPresented: $showBoons) {
                BoonPickerView(unitID: unitID)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showRegalia) {
                RegaliaSheet(unitID: unitID)
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

    /// The card, its level, and the three things to do with a unit.
    ///
    /// Fitted to the frame rather than scrolled: the buttons are pinned at
    /// the panel's foot and the CARD takes what they leave, up to 100 points
    /// — 93 on an iPhone 16 Pro with all three rows, 84 on an iPhone 16. The
    /// epithet row that stood under the card is gone: the strip's subtitle
    /// is the epithet, and the card wears the element, so it said both twice
    /// and cost the 21 points that put Evolve and Awaken under the frame's
    /// foot in run 211.
    private func identity(_ unit: ResolvedUnit, height: CGFloat) -> some View {
        // The fixed parts: the panel's 8 and 18, the level bar's 23, the 6
        // over it and the spacer's least 6 under it, and the rows — Power
        // up's 46 and 32 for each row under it with 4 between.
        let rows: CGFloat = unit.blueprint.awakening != nil ? 118 : 82
        let room = height - 61 - rows
        let card = max(64, min(100, (room - cardCaption).rounded(.down)))
        // `grantExperience` zeroes the stored experience at the cap, so a
        // maxed unit's bar read "0 / 1400" under a full level — the same
        // lie the fodder footer was fixed for. Fill it and say MAX.
        let toNextLevel = Double(ProgressionService.experienceForNextLevel(
            level: unit.level, stars: unit.stars
        ))
        return VStack(spacing: 0) {
            UnitCard(unit: unit, size: card)
                .padding(.bottom, 6)
            StatBar(
                value: unit.unit.isMaxLevel ? toNextLevel : Double(unit.unit.experience),
                maximum: toNextLevel,
                tint: unit.unit.isMaxLevel ? Theme.gold : Theme.info,
                height: 5,
                label: unit.unit.isMaxLevel
                    ? "Lv.\(unit.level) · MAX"
                    : "Lv.\(unit.level) / \(unit.unit.maxLevel)"
            )
            Spacer(minLength: 6)
            VStack(spacing: 4) {
                // The gold `PrimaryButton`, the screen's one main action
                // (2026-09-22, phase B): it was a teal plate, a third button
                // material beside gold and glass. Its name is the Hall of
                // Ka's for the same rite; the picker it opens says what a
                // maxed unit gains (skill-ups from duplicates). No glyph:
                // "POWER UP" is 97 points of Cinzel at 15, and with a glyph
                // it would not fit the column's 134 without shrinking its
                // title under the floor.
                PrimaryButton(title: "Power up") {
                    fodderPurpose = .levelUp
                    showFodderPicker = true
                }
                actionButton(
                    "Evolve", evolveSubtitle(unit),
                    "star.circle.fill", enabled: unit.unit.canEvolve
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
                        "sun.max.fill", enabled: !unit.unit.isAwakened
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
        // "5 × 5★ · 150K": the word "drachma" made the 5★ line 109 points
        // in a row of 100 at the type floor. The fodder picker's footer
        // spells the bill out in full before anything is spent.
        return "\(fodder) × \(unit.stars)★ · \(BarWallet.compact(cost))"
    }

    /// Evolve and Awaken: a row with its word and why it is lit or dark.
    /// Lit, it is the gold of `ClaimPlate`'s ready state — the metal plate
    /// with a gloss and a pale rim, ink on it — so the column's three rows
    /// are one gold under the Power up bar; dark, the cream surface. The
    /// tint parameter is gone with the teal it carried.
    private func actionButton(
        _ title: String, _ subtitle: String, _ symbol: String,
        enabled: Bool = true, action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
        return Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(Theme.body(11).weight(.bold))
                        .lineLimit(1)
                    // Every subtitle is written to fit the row's 100 points
                    // at the floor — the longest, "Fully evolved · 6★" and
                    // "Reach Lv.65 first", are 86 — so nothing shrinks: a
                    // scale factor would take body 11 under the floor.
                    Text(subtitle)
                        .font(Theme.body(11))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(enabled ? Theme.ink : Theme.textSecondary)
            .padding(.horizontal, 7)
            .frame(height: 32)
            .background(
                // Gradient or colour: a Group, never a ternary.
                Group {
                    if enabled {
                        shape.fill(Theme.goldPlate)
                            .overlay(
                                shape.fill(LinearGradient(colors: [Color.white.opacity(0.35), .clear],
                                                          startPoint: .top, endPoint: .center))
                            )
                            .overlay(shape.strokeBorder(Color(hex: "#FFE9A8").opacity(0.55), lineWidth: 1))
                    } else {
                        shape.fill(Theme.surface)
                            .overlay(shape.strokeBorder(Theme.stroke, lineWidth: 1))
                    }
                }
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
                // whole sheet exists to raise, and over it the BOON SOCKET —
                // the one earned line a unit carries (`BoonPickerView`) —
                // where a second copy of the element used to sit.
                VStack(spacing: 2) {
                    boonSocket(unit)
                    Text("\(unit.power)")
                        .font(Theme.numeric(16))
                        .foregroundStyle(Theme.gold)
                        // The clear disc inside the ring is 74pt across; five
                        // monospaced digits at 16 are 43 of them and six would
                        // touch the tiles at 2 and 6 o'clock. It may shrink,
                        // but only to the numeric floor.
                        .lineLimit(1)
                        .minimumScaleFactor(Theme.numericFloor / 16)
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
            // Under the ring, the column SCROLLS inside its panel and fades at
            // its foot (2026-09-22, phase B): the regalia first, whole — run
            // 211's frame cut it in half at the frame's foot, the critic's
            // "clipped" — then the sets as progress chips, the boon's line,
            // and the arithmetic of what the six slots are worth. On an
            // iPhone 16 Pro the ring panel has 287 points inside its
            // paddings; the ring takes 204 and this 77: the regalia's two
            // lines (37) and the first row of chips at rest, the rest a
            // scroll away.
            //
            // The regalia was a one-line row that could not hold the
            // longest names ("Potter's Wheel of Elephantine", 159 points)
            // beside its pips and its line without shrinking them under the
            // floor; it has two lines now. It is not pinned at the foot
            // because two lines pinned there would leave the chips 34
            // points. And the footer was offered to `ViewThatFits` in three
            // sizes, shedding its note, its captions, then itself as the
            // chips grew — the unit this screen exists to admire, six relics
            // in three sets, lost it altogether. In the scroll it is always
            // there, whole.
            SheetPanelScroll {
                VStack(spacing: 6) {
                    regaliaLine(unit)
                    setsRow(unit)
                    if let boon = unit.boon {
                        boonLine(boon)
                    }
                    relicSummary(figures)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, Theme.panelInset)
        .padding(.top, Theme.panelPadding)
        // The scroll's last line fades out over the corner ornament rather
        // than printing on it; the ornament's clearance keeps the fade's
        // foot off the painted band too.
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

    /// The socket at the ring's centre: the boon's glyph in its colour on
    /// the ring's own hexagon, or a ghost reading BOON. A tap opens the
    /// picker (`BoonPickerView`), where the caches open and the boons are
    /// pushed and socketed.
    private func boonSocket(_ unit: ResolvedUnit) -> some View {
        let boon = unit.boon
        let socket: CGFloat = 36
        return Button {
            Juice.haptic(.light)
            showBoons = true
        } label: {
            ZStack {
                BoonHexagon()
                    .fill(boon.map { $0.kind.tint.opacity(0.22) } ?? Theme.surface.opacity(0.9))
                    .frame(width: socket, height: socket)
                BoonHexagon()
                    .stroke(boon != nil ? Theme.gold : Theme.goldDim.opacity(0.5), lineWidth: 1)
                    .frame(width: socket, height: socket)
                if let boon {
                    Image(systemName: boon.kind.glyph)
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(boon.kind.tint)
                } else {
                    Text("BOON")
                        .font(Theme.body(8).weight(.black))
                        .tracking(0.5)
                        .foregroundStyle(Theme.goldDim.opacity(0.85))
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// The boon's line under the sets row: "Bane of Tide" over "+18.3% vs
    /// Tide". Two lines since phase B (2026-09-22): on one, "Bane of
    /// Radiance" and "+18.3% vs Radiance" are 210 points in a column of 188
    /// and fitted only by shrinking both under the type floor.
    private func boonLine(_ boon: Boon) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Image(systemName: boon.kind.glyph)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(boon.kind.tint)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(boon.displayName)
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(boon.shortLine)
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(Theme.gold)
            }
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    /// The family's regalia (`Regalia`, `RegaliaSheet`), the first thing
    /// under the ring: the item's glyph, its name, its level as five pips
    /// and its line at that level — or a lock and what unlocks it. A tap
    /// opens the sheet.
    ///
    /// Two lines, whole (2026-09-22, phase B). It was one 20-point row
    /// that shrank its name and its line to 0.7 — under the type floor —
    /// and still could not hold the longest ("Potter's Wheel of
    /// Elephantine", 159 points at the floor, beside five pips and "+12%
    /// ACC · debuffs +1 turn", 147); run 211's frame cut it in half at the
    /// foot of the sheet. Run 176 photographed the one-line form as
    /// "Thunderbolt of… Awaken to u…".
    @ViewBuilder
    private func regaliaLine(_ unit: ResolvedUnit) -> some View {
        if let regalia = RegaliaService.regalia(forBlueprint: unit.blueprint.id, level: RegaliaService.level(of: unit.unit)) {
            let unlocked = unit.regalia != nil
            let shape = RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
            Button {
                Juice.haptic(.light)
                showRegalia = true
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: regalia.template.glyph)
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(unlocked ? Theme.gold : Theme.textSecondary)
                        .frame(width: 14)
                        .padding(.top, 1)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(regalia.name)
                            .font(Theme.body(11).weight(.bold))
                            .foregroundStyle(unlocked ? Theme.textPrimary : Theme.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .center, spacing: 5) {
                            RegaliaPips(level: regalia.level, lit: unlocked, size: 5)
                            if unlocked {
                                Text(regalia.shortLine)
                                    .font(Theme.numeric(11.5))
                                    .foregroundStyle(Theme.gold)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text(RegaliaService.unlockLine(for: unit.blueprint))
                                    .font(Theme.body(11))
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(shape.fill(unlocked ? Theme.gold.opacity(0.12) : Theme.surface))
                .overlay(shape.strokeBorder(unlocked ? Theme.gold.opacity(0.6) : Theme.stroke.opacity(0.6), lineWidth: 0.5))
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(regalia.name), level \(regalia.level)")
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
                // Two chips a row, 92 points each: the widest, "Nemesis
                // 2/2", is 66 at the floor beside its 12-point stone, which
                // fits at 5 of padding and 3 of spacing with nothing shrunk
                // (it was 0.8, under the floor).
                HStack(spacing: 3) {
                    RelicSetEmblem(set: relicSet, size: 12, tint: complete ? Theme.gold : Theme.textSecondary)
                    Text("\(relicSet.displayName) \(count)/\(relicSet.piecesRequired)")
                        .font(Theme.body(11).weight(.bold))
                        .foregroundStyle(complete ? Theme.gold : Theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                .padding(.horizontal, 5)
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
                        .font(Theme.body(11).weight(.bold))
                        .lineLimit(1)
                        .fixedSize()
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

    /// The three figures the footer prints, worked out once per pass.
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
    ///
    /// In the ring's scroll since phase B, so it is always drawn whole and
    /// can carry the note of what is empty under it.
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
            if let note = figures.note {
                Text(note)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// One figure over its name. `Text` rather than `String` so the number
    /// keeps its thousands separator: SwiftUI groups an integer interpolated
    /// into a `Text`, and a pre-built `String` would read "1240" beside the
    /// ring's own "1,240".
    ///
    /// Nothing shrinks (both were at 0.6, under the floor): the figure is at
    /// most "+12,345", 50 points in a column of 60, and a caption too wide
    /// for its column ("FROM RELICS") takes a second line.
    private func summaryFigure(_ value: Text, _ caption: String, tint: Color) -> some View {
        VStack(spacing: 0) {
            value
                .font(Theme.numeric(12))
                .foregroundStyle(tint)
                .lineLimit(1)
                .fixedSize()
            Text(caption)
                .font(Theme.body(11).weight(.black))
                .tracking(0.6)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
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

    /// The grade and the tags, then the eight stats with what the relics
    /// add — and nothing else, so the panel is its natural height (132
    /// points) and the skills under it get the rest of the column. The
    /// leader skill and the awakening lines were here and made the column
    /// taller than the phone; they are the skills panel's scroll now, with
    /// the other words about what the unit can do (2026-09-22, phase B).
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
            HStack(alignment: .top, spacing: 6) {
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
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // The first row here is the star row and the three tags, drawn corner
        // to corner: at the old flat 8 the leading star was inside the top-left
        // ornament (18.6 x 16.9 points) and the Controller tag inside the
        // top-right one. The last row is "SPD" and "Resistance" at the
        // leading edge, so the bottom takes the ornament's clearance too.
        .padding(.horizontal, Theme.panelInset)
        .padding(.top, Theme.panelPadding)
        .padding(.bottom, panelBottomInset)
        .panelBackground(radius: Theme.tightCorner)
    }

    /// A pantheon, archetype or role, in a tinted capsule. At the type floor
    /// "Egyptian", "Primordial" and "Controller" beside a 6★ star row are
    /// 269 points against the panel's 316 on an iPhone 16 Pro and 300 on an
    /// iPhone 16, so nothing shrinks (it was 0.75, under the floor).
    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.body(11).weight(.semibold))
            .lineLimit(1)
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
    ///
    /// Nothing shrinks since phase B (2026-09-22): every column was scaled
    /// to 0.7–0.8, under the type floor. At the floor the widest figures are
    /// "12345" (37 of the 42) and "+10234" (40 of the 40), and "Resistance"
    /// is 58 of the 61 an iPhone 16's group leaves the label.
    private func statRow(
        _ label: String, _ base: Double, _ total: Double,
        percent: Bool = false, strong: Bool = false
    ) -> some View {
        let bonus = total - base
        let shown = abs(bonus) >= (percent ? 0.005 : 0.5)
        let sign = bonus > 0 ? "+" : "−"
        let bonusText: String = shown ? sign + Self.statText(abs(bonus), percent: percent) : ""
        return HStack(spacing: 3) {
            Text(label)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(Self.statText(total, percent: percent))
                .font(strong ? Theme.numeric(13) : Theme.numeric(11.5))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .frame(width: 42, alignment: .trailing)
            Text(bonusText)
                .font(Theme.numeric(11.5))
                .foregroundStyle(bonus > 0 ? Theme.success : Theme.danger)
                .lineLimit(1)
                .frame(width: 40, alignment: .trailing)
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

    /// The skills: the icons pinned along the top, and under them, in a
    /// scroll that fades at the panel's foot, the chosen skill's words, then
    /// the leader skill and the awakening — everything the sheet says about
    /// what the unit can do, in one place that is never cut (2026-09-22,
    /// phase B; run 211's frame cut this panel's words at the phone's foot).
    private func skills(_ unit: ResolvedUnit) -> some View {
        let index = min(selectedSkill, max(0, unit.skills.count - 1))
        let icons = SkillArt.keys(for: unit.skills, element: unit.element, ranged: !unit.blueprint.model.melee)
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
                            level: unit.unit.skillLevels.indices.contains(slot) ? unit.unit.skillLevels[slot] : 1,
                            element: unit.element,
                            ranged: !unit.blueprint.model.melee,
                            iconKey: slot < icons.count ? icons[slot] : nil
                        )
                    }
                    .buttonStyle(PlateButtonStyle())
                }
            }
            SheetPanelScroll {
                VStack(alignment: .leading, spacing: 6) {
                    if unit.skills.indices.contains(index) {
                        skillWords(unit.skills[index], index: index, unit: unit)
                    }
                    abilityNotes(unit)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, Theme.panelInset)
        .padding(.top, Theme.panelPadding)
        // The photographed overlap. The skill-up hint was this panel's last
        // row and started at its leading edge — the worst corner there is —
        // so at the old flat 8 its first word was drawn on the bottom-left
        // ornament (CI frame 2-detail.jpg). The scroll's fade ends above the
        // ornament now for the same reason.
        .padding(.bottom, panelBottomInset)
        .panelBackground(radius: Theme.tightCorner)
    }

    /// The leader skill and the awakening, under the chosen skill's words:
    /// they were the last two lines of the stats panel, and the reason the
    /// right column was 402 points on a 313-point frame.
    @ViewBuilder
    private func abilityNotes(_ unit: ResolvedUnit) -> some View {
        if unit.blueprint.leaderSkill != nil || unit.blueprint.awakening != nil {
            Divider().overlay(Theme.stroke)
        }
        if let leader = unit.blueprint.leaderSkill {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.gold)
                    .frame(width: 14)
                Text(leader.description)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if let awakening = unit.blueprint.awakening {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(unit.unit.isAwakened ? Theme.gold : Theme.textSecondary)
                    .frame(width: 14)
                Text(unit.unit.isAwakened
                     ? "Awakened: \(awakening.bonusDescription)"
                     : "Awakens into \(awakening.awakenedName): \(awakening.bonusDescription)")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func skillTile(_ skill: Skill, selected: Bool, level: Int,
                           element: Element, ranged: Bool, iconKey: String?) -> some View {
        VStack(spacing: 2) {
            SkillIcon(skill: skill, element: element, ranged: ranged, resolvedKey: iconKey,
                      size: 26, tint: selected ? Theme.gold : Theme.textSecondary,
                      dimmed: !selected, socket: true)
            // Two lines at the floor, never shrunk (it was 0.8, under it):
            // "Judgement of the" is 93 points, and a tile of four is 70.
            Text(skill.name)
                .font(Theme.body(11).weight(.semibold))
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text("Lv.\(level)/\(skill.maxSkillLevel)")
                .font(Theme.numeric(11.5))
                .foregroundStyle(level >= skill.maxSkillLevel ? Theme.gold : Theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 3)
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

    /// The chosen skill: its name with its skill-up pips, what it costs and
    /// hits for, what it does, and the next skill-up. In the panel's scroll
    /// since phase B, so the name and the hint take a second line rather
    /// than shrinking under the floor.
    private func skillWords(_ skill: Skill, index: Int, unit: ResolvedUnit) -> some View {
        let level = unit.unit.skillLevels.indices.contains(index) ? unit.unit.skillLevels[index] : 1
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(skill.name)
                    .font(Theme.body(12).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if !skill.levelUpBonuses.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(skill.levelUpBonuses.indices, id: \.self) { bonusIndex in
                            Circle()
                                .fill(level > bonusIndex + 1 ? Theme.success : Theme.stroke)
                                .frame(width: 6, height: 6)
                        }
                        Text("skill-ups")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            HStack(spacing: 8) {
                if skill.isPassive {
                    Text("PASSIVE")
                        .font(Theme.body(11).weight(.black))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Theme.gold.opacity(0.25)))
                        .foregroundStyle(Theme.gold)
                        .fixedSize()
                }
                if skill.cooldown > 0 {
                    Label("\(skill.cooldown) turns", systemImage: "clock.fill")
                        .font(Theme.numeric(11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                if let damage = skill.damage {
                    // previewDamage already multiplies by the hit count, so the
                    // old " × 3" read as an instruction to triple the figure.
                    let estimate = DamageCalculator.previewDamage(
                        attackStat: Self.scalingStat(damage.scaling, unit.stats), spec: damage
                    )
                    Text("≈ \(Int(estimate)) dmg" + (damage.hits > 1 ? " · \(damage.hits) hits" : ""))
                        .font(Theme.numeric(11.5))
                        .foregroundStyle(Theme.gold)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Text(skill.description)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let next = skill.levelUpBonuses.indices.first(where: { level <= $0 + 1 }) {
                Text("Next skill-up: \(skill.levelUpBonuses[next].label) — feed a duplicate in the Hall of Ka.")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.goldDim)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
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
                                    Text("The element's essence drops in its Hall of Essence, in the Labyrinth; Magic essence in the campaign.")
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
///
/// `onGlass` sinks the recess into the dark (2026-09-22, phase B): on the
/// collection Stage's glass plate the cream recess was six pale discs
/// glaring on a dark ground — the phase B mocks' "cream socket on glass" —
/// so there the socket is `Theme.socketFill`'s bronze-black with a glass rim
/// and the ghost in the on-glass gold.
struct RelicSlotTile: View {
    let slot: Int
    let relic: Relic?
    var size: CGFloat = 60
    var onGlass: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // The recess: darker towards the rim, no border.
                if onGlass {
                    Circle()
                        .fill(Theme.socketFill)
                    Circle()
                        .strokeBorder(Theme.glassRim.opacity(0.8), lineWidth: 0.8)
                } else {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Theme.surfaceRaised.opacity(0.9), Theme.stroke.opacity(0.45)],
                                center: .center, startRadius: size * 0.12, endRadius: size * 0.5
                            )
                        )
                    Circle()
                        .strokeBorder(Theme.stroke.opacity(0.5), lineWidth: 0.5)
                }
                if let relic {
                    RelicIcon(relic: relic, size: size * 0.74, showsStars: false, showsLevel: true)
                } else {
                    if let ghost = BundleArt.image(Relic.rimImageName) {
                        Image(uiImage: ghost)
                            .renderingMode(.template)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .foregroundStyle(onGlass ? Theme.onGlassEyebrow.opacity(0.35) : Theme.goldDim.opacity(0.35))
                            .frame(width: size * 0.64, height: size * 0.64)
                    }
                    Text("\(slot)")
                        .font(Theme.title(13))
                        .foregroundStyle(onGlass ? Theme.onGlassEyebrow.opacity(0.9) : Theme.goldDim.opacity(0.85))
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(PlateButtonStyle())
    }
}
