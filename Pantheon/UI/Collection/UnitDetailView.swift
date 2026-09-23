import SwiftUI
import UIKit

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

/// The largest face the identity column draws: its 158 less the panel's 12
/// a side is 134, and 120 leaves the rarity frame air inside it.
private let identityFaceMaximum: CGFloat = 120

/// The fade at the foot of a panel body that scrolls (`SheetPanelScroll`),
/// and the room its last line keeps under it so it can scroll clear.
private let panelFade: CGFloat = 14

/// The coordinate space a `SheetPanelScroll` measures its content in.
private let sheetPanelSpace = "sheetPanelScroll"

/// A panel's body that scrolls INSIDE its panel — and says so only when it
/// has to.
///
/// The unit sheet is one frame since phase B (2026-09-22): three columns,
/// each exactly the frame's height, the painted panels fixed and only what
/// cannot fit scrolling inside them. The things a player acts on (the
/// buttons, the ring, the skill icons) are pinned outside the scroll.
///
/// Run 216's judge: both panels ended in a GHOST ROW — set chips at a fifth
/// of their opacity, the skill's last line fading mid-sentence — which read
/// as clipped, with nothing to say it scrolled. So the body is measured:
/// content that fits is drawn whole, with no fade at all; content that does
/// not fades at the foot AND wears a small chevron there, which goes when
/// the last line has been scrolled into view. And the panels were cut so
/// that at rest they fit: the ring panel's footer and the skills' notes
/// moved to popovers and a tile of their own.
private struct SheetPanelScroll<Content: View>: View {
    let content: () -> Content
    /// The content's frame in the scroll's own space: its height against
    /// the viewport's says whether it overflows, its foot whether there is
    /// more below.
    @State private var contentFrame: CGRect = .zero
    @State private var viewportHeight: CGFloat = 0

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    private var overflows: Bool { contentFrame.height > viewportHeight + 1 }
    private var moreBelow: Bool { overflows && contentFrame.maxY > viewportHeight + 2 }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .named(sheetPanelSpace))
                        Color.clear
                            .onAppear { contentFrame = frame }
                            .onChange(of: frame) { _, now in contentFrame = now }
                    }
                )
                // Room for the last line to scroll clear of the fade — only
                // when there is a fade.
                .padding(.bottom, overflows ? panelFade : 0)
        }
        // The name-based pair (`coordinateSpace(name:)` with the proxy's
        // `.named`), which every SDK since iOS 13 resolves the same way.
        .coordinateSpace(name: sheetPanelSpace)
        .scrollBounceBehavior(.basedOnSize)
        .background(
            GeometryReader { proxy in
                let height = proxy.size.height
                Color.clear
                    .onAppear { viewportHeight = height }
                    .onChange(of: height) { _, now in viewportHeight = now }
            }
        )
        .mask(
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [Color.black, moreBelow ? Color.clear : Color.black], startPoint: .top, endPoint: .bottom)
                    .frame(height: panelFade)
            }
        )
        .overlay(alignment: .bottom) {
            if moreBelow {
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.goldDim)
                    .frame(width: 30, height: 12)
                    .background(Capsule().fill(Theme.surfaceHigh.opacity(0.92)))
                    .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.35), lineWidth: 0.8))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
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
    /// The popover off the ring's POWER: what the six slots and the boon
    /// are worth (the footer the ring panel scrolled to until run 216).
    @State private var showWorth = false
    /// The skill whose words are shown, by its place in the kit — or
    /// `leaderSlot` for the leader skill's own tile.
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
            // The short name and ONE epithet under it — the awakened name's
            // own when it has one — as every plate in the build prints a
            // unit; run 216 stacked "ANUBIS, KEEPER OF THE ASH ROAD" over
            // "of the Burning Sands".
            GameScreen(
                unit?.nameWithoutEpithet ?? "Unit",
                subtitle: unit?.epithetUnderName,
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
                // so another unit can wear them. Worded since run 216: a bare
                // ⊖ read as "remove", not as the relics coming off, and the
                // strip has the room now that its title is the short name.
                BarButton(title: "Unequip all", systemImage: "minus.circle", tint: Theme.textSecondary) {
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

    /// The face, its level, and the three things to do with a unit.
    ///
    /// Fitted to the frame rather than scrolled: the buttons are pinned at
    /// the panel's foot and the FACE takes what they leave, up to 120 points
    /// — 120 on an iPhone 16 Pro and on an iPhone 16 with all three rows.
    /// It is the face alone (`UnitPortraitTile`), no caption and no level
    /// badge: the card's caption printed the name the strip prints, the
    /// level the bar under it prints and the power the ring prints, all
    /// within 150 pixels (run 216), and its 41 points are the face's now,
    /// 93 → 120.
    private func identity(_ unit: ResolvedUnit, height: CGFloat) -> some View {
        // The fixed parts: the panel's 8 and 18, the level bar's 23, the 6
        // over it and the spacer's least 6 under it, and the rows — Power
        // up's 46 and 32 for each row under it with 4 between.
        let rows: CGFloat = unit.blueprint.awakening != nil ? 118 : 82
        let room = height - 61 - rows
        let card = max(64, min(identityFaceMaximum, room.rounded(.down)))
        // `grantExperience` zeroes the stored experience at the cap, so a
        // maxed unit's bar read "0 / 1400" under a full level — the same
        // lie the fodder footer was fixed for. Fill it and say MAX.
        let toNextLevel = Double(ProgressionService.experienceForNextLevel(
            level: unit.level, stars: unit.stars
        ))
        return VStack(spacing: 0) {
            UnitPortraitTile(unit: unit, size: card, showsLevel: false)
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
                    // Awakened is an ACHIEVEMENT, not a disabled row: it was
                    // drawn exactly like the unavailable Evolve above it and
                    // could not be pressed (run 216). It is the achieved
                    // plate now, and it opens the sheet with both forms.
                    actionButton(
                        unit.unit.isAwakened ? "Awakened" : "Awaken",
                        unit.unit.isAwakened
                            ? "Form unlocked ✓"
                            : (ready ? "Essences ready" : "Essences short"),
                        "sun.max.fill",
                        achieved: unit.unit.isAwakened
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

    /// Evolve and Awaken: a row with its word and why it is lit, dark or
    /// done. THREE states since run 216, so the three read apart at a glance:
    ///
    /// - lit: the drawn gold of the gold `PrimaryButton` above it — the same
    ///   four stops and gloss, so the column is ONE gold (run 216 had the
    ///   painted copper bar over `goldPlate`'s bronze), ink on it;
    /// - dark: the cream surface, secondary ink — not yet;
    /// - achieved: the dark bronze socket of a painted icon with a gold rim
    ///   and gold words — done, and still a door (the awakened unit's row
    ///   opens the sheet with both forms).
    private func actionButton(
        _ title: String, _ subtitle: String, _ symbol: String,
        enabled: Bool = true, achieved: Bool = false, action: @escaping () -> Void
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
        let ink: Color = achieved ? Theme.onGlassGold : (enabled ? Theme.ink : Theme.textSecondary)
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
                        .foregroundStyle(achieved ? Theme.onGlass : ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 7)
            .frame(height: 32)
            .background(
                // Gradient or colour: a Group, never a ternary.
                Group {
                    if achieved {
                        shape.fill(Theme.socketFill)
                            .overlay(shape.strokeBorder(Theme.gold, lineWidth: 1.2))
                            .overlay(shape.inset(by: 2).strokeBorder(Color(hex: "#FFE9A8").opacity(0.25), lineWidth: 0.6))
                    } else if enabled {
                        shape.fill(
                            LinearGradient(
                                colors: [Color(hex: "#FFE9A8"), Color(hex: "#E2BF62"), Theme.gold, Color(hex: "#7A5B1C")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
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
        .disabled(!enabled && !achieved)
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
        //
        // The five points are paid at the TOP only (run 216): the bottom
        // tile's badge hangs off its top-left corner, inside the ring, so
        // the frame ends at the bottom tile's edge and the centre sits 2.5
        // below the middle — five points handed to the words under it.
        let height = (radius + slotTileSize / 2) * 2 + 5
        let centre = CGPoint(x: width / 2, y: radius + slotTileSize / 2 + 5)
        let figures = relicFigures(unit)
        return VStack(spacing: 4) {
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
                //
                // The power is a door too (run 216): a tap opens what the
                // ring is worth — the boon's line, the slots filled, the
                // power the relics bought and their quality — the footer
                // that scrolled under the ring and ended the panel in a
                // ghost row.
                VStack(spacing: 2) {
                    boonSocket(unit)
                    Button {
                        Juice.haptic(.light)
                        showWorth = true
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(unit.power)")
                                .font(Theme.numeric(16))
                                .foregroundStyle(Theme.gold)
                                // The clear disc inside the ring is 74pt
                                // across; five monospaced digits at 16 are 43
                                // of them and six would touch the tiles at 2
                                // and 6 o'clock. It may shrink, but only to
                                // the numeric floor.
                                .lineLimit(1)
                                .minimumScaleFactor(Theme.numericFloor / 16)
                                .frame(maxWidth: 74)
                            HStack(spacing: 2) {
                                Text("POWER")
                                    .font(Theme.body(8).weight(.black))
                                    .tracking(1)
                                Image(systemName: "info.circle")
                                    .font(.system(size: 7, weight: .bold))
                            }
                            .foregroundStyle(Theme.textSecondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Power \(unit.power), what the relics are worth")
                    .popover(isPresented: $showWorth) {
                        ringWorth(unit, figures: figures)
                            .padding(14)
                            .frame(width: 272)
                            .background(Theme.surface)
                            .presentationCompactAdaptation(.popover)
                    }
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
            // Under the ring: the regalia and ONE line of set chips, which at
            // rest FIT (run 216). They sat in a scroll with the boon's line
            // and the relic arithmetic under them, and the panel ended in a
            // ghost row — the chips at a fifth of their opacity — with the
            // rest out of sight; the arithmetic and the boon are the
            // power's popover now. On an iPhone 16 Pro the panel has 287
            // points inside its paddings, the ring 199 and 4 of them, and
            // this 84: the regalia's two or three lines (40–55) and the chip
            // line (22). A regalia whose name AND line both wrap is taller,
            // and then the body scrolls with the chevron that says so.
            //
            // The regalia was a one-line row that could not hold the
            // longest names ("Potter's Wheel of Elephantine", 159 points)
            // beside its pips and its line without shrinking them under the
            // floor; it has two lines now. And the footer was offered to
            // `ViewThatFits` in three sizes, shedding its note, its
            // captions, then itself as the chips grew; it is a popover now,
            // always whole.
            SheetPanelScroll {
                VStack(spacing: 6) {
                    regaliaLine(unit)
                    setsRow(unit)
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
                .padding(.vertical, 3)
                .background(shape.fill(unlocked ? Theme.gold.opacity(0.12) : Theme.surface))
                .overlay(shape.strokeBorder(unlocked ? Theme.gold.opacity(0.6) : Theme.stroke.opacity(0.6), lineWidth: 0.5))
                .contentShape(shape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(regalia.name), level \(regalia.level)")
        }
    }

    /// Every set with a piece on the ring as ONE line of chips — the set's
    /// stone and a count, "×2" lit in gold where the set is complete (and
    /// how many times), "1/4" dim where it is not — and a book at the end
    /// that opens the set reference counting this unit's pieces, where the
    /// names are.
    ///
    /// One line since run 216: the named chips were a grid of two a row
    /// that the ring panel could not hold at rest, so they sat at a fifth of
    /// their opacity under the fade; and "Thunder 4/2" — two complete
    /// Thunder sets — read as a counting bug. The stone names the set (the
    /// chip's accessibility label says it), and more sets than the line
    /// holds scroll sideways.
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
        return HStack(spacing: 4) {
            if entries.isEmpty {
                Text("Nothing worn")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 0)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(entries) { relicSet in
                            setChip(relicSet, count: tally[relicSet, default: 0])
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
            Button {
                Juice.haptic(.light)
                showSets = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 10, weight: .bold))
                    // The word only when there are no chips to explain it.
                    if entries.isEmpty {
                        Text("Set effects")
                            .font(Theme.body(11).weight(.bold))
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .foregroundStyle(Theme.gold)
                .padding(.horizontal, entries.isEmpty ? 8 : 0)
                .frame(minWidth: 26)
                .frame(height: 22)
                .background(Capsule().fill(Theme.surface))
                .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Set effects")
        }
        .frame(height: 22)
    }

    /// One set on the chip line: its painted stone and its count. "Nemesis
    /// ×2" is 36 points at the floor beside a 14-point stone, so four stand
    /// in the column's 188 with the book.
    private func setChip(_ relicSet: RelicSet, count: Int) -> some View {
        let completions = count / relicSet.piecesRequired
        let complete = completions > 0
        let label: String = complete ? "×\(completions)" : "\(count)/\(relicSet.piecesRequired)"
        return HStack(spacing: 3) {
            RelicSetEmblem(set: relicSet, size: 14, tint: complete ? Theme.gold : Theme.textSecondary)
            Text(label)
                .font(Theme.numeric(11.5))
                .foregroundStyle(complete ? Theme.gold : Theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(Capsule().fill(complete ? Theme.surfaceHigh : Theme.surface))
        .overlay(Capsule().strokeBorder(complete ? Theme.gold.opacity(0.45) : Theme.stroke.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(relicSet.displayName), \(count) of \(relicSet.piecesRequired)")
    }

    /// What the ring is worth, in the popover off its POWER: the boon's
    /// line when one is socketed, then the three figures and the note of
    /// what is empty (`relicSummary`).
    private func ringWorth(_ unit: ResolvedUnit, figures: RelicFigures) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT THE RING IS WORTH")
                .font(Theme.body(11).weight(.black))
                .tracking(1.0)
                .foregroundStyle(Theme.goldDim)
            if let boon = unit.boon {
                boonLine(boon)
            }
            relicSummary(figures)
        }
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
    /// In the power's popover since run 216 (`ringWorth`), where it is
    /// always drawn whole and carries the note of what is empty under it.
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
    /// taller than the phone; the leader skill is the skill row's crown tile
    /// and the awakening the Awaken row's sheet (run 216).
    private func stats(_ unit: ResolvedUnit) -> some View {
        // Base is grade, level and awakening; the difference to the final
        // number is the relics, shown beside it the way the genre does, so
        // equipping a relic is visible on the sheet and not only in battle.
        let base = ProgressionService.baseStats(for: unit.unit, blueprint: unit.blueprint)
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                StarRow(stars: unit.stars, natural: unit.blueprint.naturalStars, size: 10)
                tag(unit.pantheon.displayName, color: unit.pantheon.color, ink: Self.inked(unit.pantheon.color))
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
    ///
    /// `ink` is the word's colour when it is not the tint's own: the
    /// pantheon colours were chosen for dark grounds, and "Greek" in its pale
    /// gold on its own pale gold tint on cream marble was all but invisible
    /// (run 216). The capsule keeps the tint; the word is the tint taken
    /// most of the way to ink (`inked`), 4.8:1 for the Greek gold.
    private func tag(_ text: String, color: Color, ink: Color? = nil) -> some View {
        Text(text)
            .font(Theme.body(11).weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(ink ?? color)
    }

    /// A colour taken 60% of the way to `Theme.ink`, so a word in it reads on
    /// cream and on the colour's own tint and still says which colour it is.
    private static func inked(_ color: Color) -> Color {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return Theme.textPrimary }
        var inkRed: CGFloat = 0, inkGreen: CGFloat = 0, inkBlue: CGFloat = 0, inkAlpha: CGFloat = 0
        _ = UIColor(Theme.ink).getRed(&inkRed, green: &inkGreen, blue: &inkBlue, alpha: &inkAlpha)
        let keep: CGFloat = 0.4
        let mixedRed: Double = Double(red * keep + inkRed * (1 - keep))
        let mixedGreen: Double = Double(green * keep + inkGreen * (1 - keep))
        let mixedBlue: Double = Double(blue * keep + inkBlue * (1 - keep))
        return Color(red: mixedRed, green: mixedGreen, blue: mixedBlue)
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

    /// The leader skill's place in `selectedSkill`: its tile stands after
    /// the kit's.
    private static let leaderSlot = -1

    /// The skills: the icons pinned along the top — the kit's, then the
    /// leader skill's crown — and under them, in a scroll that fades at the
    /// panel's foot only when the words do not fit (`SheetPanelScroll`), the
    /// chosen one's words.
    ///
    /// ICONS ALONE since run 216, the genre's way. Each tile held its name
    /// in 70 points and three of Anubis's four were cut ("Verdict of A…",
    /// "Rite of the…", "Scales of M…"); Summoners War's row is icons, and
    /// the chosen skill's name is in the words under it, which this panel
    /// already printed. The icons are painted, never greyed — the gold rim
    /// is the selection. The level is in the words beside the name, a door
    /// to the skill-up ladder (`SkillLevelButton`). The leader skill, which
    /// ended the scroll under the words with the awakening, is the crown's
    /// tile — the genre puts it in the skill row too — and the awakening is
    /// the Awaken row's sheet.
    private func skills(_ unit: ResolvedUnit) -> some View {
        let leader = unit.blueprint.leaderSkill
        let index: Int = (selectedSkill == Self.leaderSlot && leader != nil)
            ? Self.leaderSlot
            : min(max(0, selectedSkill), max(0, unit.skills.count - 1))
        let icons = SkillArt.keys(for: unit.skills, element: unit.element, ranged: !unit.blueprint.model.melee)
        let tileCount = unit.skills.count + (leader == nil ? 0 : 1)
        // 44 while four tiles share the row, 40 for five: a tile is the
        // icon and 4 a side, and five of them are 58 wide in the 316 of an
        // iPhone 16 Pro.
        let icon: CGFloat = tileCount > 4 ? 40 : 44
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                ForEach(unit.skills.indices, id: \.self) { slot in
                    Button {
                        Juice.haptic(.light)
                        selectedSkill = slot
                    } label: {
                        skillTile(
                            unit.skills[slot],
                            selected: slot == index,
                            element: unit.element,
                            ranged: !unit.blueprint.model.melee,
                            iconKey: slot < icons.count ? icons[slot] : nil,
                            icon: icon
                        )
                    }
                    .buttonStyle(PlateButtonStyle())
                    .accessibilityLabel(unit.skills[slot].name)
                }
                if leader != nil {
                    Button {
                        Juice.haptic(.light)
                        selectedSkill = Self.leaderSlot
                    } label: {
                        leaderTile(selected: index == Self.leaderSlot, icon: icon)
                    }
                    .buttonStyle(PlateButtonStyle())
                    .accessibilityLabel("Leader skill")
                }
            }
            // A new skill is a new page, met at its top.
            SheetPanelScroll {
                if index == Self.leaderSlot, let leader {
                    leaderWords(leader)
                } else if unit.skills.indices.contains(index) {
                    skillWords(unit.skills[index], index: index, unit: unit)
                }
            }
            .id(index)
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

    /// One skill's tile: its painted icon in the dark socket, in a plate
    /// rimmed gold when it is the one whose words are shown.
    private func skillTile(_ skill: Skill, selected: Bool, element: Element,
                           ranged: Bool, iconKey: String?, icon: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
        return SkillIcon(skill: skill, element: element, ranged: ranged, resolvedKey: iconKey,
                         size: icon, socket: true)
            .padding(4)
            // The tiles divide the row rather than sitting at a fixed width
            // with a Spacer holding the rest of it open — which also
            // overflowed on a narrower phone.
            .frame(maxWidth: .infinity)
            .background(shape.fill(selected ? Theme.surfaceHigh : Theme.surface))
            .overlay(shape.strokeBorder(selected ? Theme.gold : Theme.stroke, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
    }

    /// The leader skill's tile: a gold crown in the same socket as the
    /// skills' icons.
    private func leaderTile(selected: Bool, icon: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
        let socket = RoundedRectangle(cornerRadius: icon * 0.22, style: .continuous)
        return ZStack {
            socket.fill(Theme.socketFill)
            socket.strokeBorder(Theme.goldDeep.opacity(0.85), lineWidth: 1)
            Image(systemName: "crown.fill")
                .font(.system(size: icon * 0.44, weight: .black))
                .foregroundStyle(Theme.goldText)
                .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
        }
        .frame(width: icon, height: icon)
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(shape.fill(selected ? Theme.surfaceHigh : Theme.surface))
        .overlay(shape.strokeBorder(selected ? Theme.gold : Theme.stroke, lineWidth: selected ? 1.5 : 1))
        .contentShape(Rectangle())
    }

    /// The leader skill's words: what it gives, to whom, and where it
    /// counts. It works for the unit that LEADS — the first of a team
    /// (`BattleEngine.buildSide`).
    private func leaderWords(_ leader: LeaderSkill) -> some View {
        let reach: String
        if leader.appliesInArena && leader.appliesInCampaign {
            reach = "When this unit leads — the first of the team — in any fight."
        } else if leader.appliesInArena {
            reach = "When this unit leads — the first of the team — in the Arena only."
        } else if leader.appliesInCampaign {
            reach = "When this unit leads — the first of the team — anywhere but the Arena."
        } else {
            reach = "It applies nowhere yet."
        }
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.gold)
                Text("Leader skill")
                    .font(Theme.body(12).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            Text(leader.description)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(reach)
                .font(Theme.body(11))
                .foregroundStyle(Theme.goldDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The chosen skill: its name with its level (a door to the skill-up
    /// ladder), what it costs and hits for, and what it does. In the
    /// panel's scroll, so a long name takes a second line rather than
    /// shrinking under the floor; the "Next skill-up" line that ended it is
    /// the ladder's popover, so a skill of two lines of words fits at rest.
    private func skillWords(_ skill: Skill, index: Int, unit: ResolvedUnit) -> some View {
        let level = unit.unit.skillLevels.indices.contains(index) ? unit.unit.skillLevels[index] : 1
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: 6) {
                Text(skill.name)
                    .font(Theme.body(12).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                SkillLevelButton(skill: skill, level: level)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A skill's level beside its name, and the door to its ladder: every
/// skill-up with what it adds, the ones gained ticked, and where the next
/// one comes from. It replaced the five pips and the "Next skill-up: …"
/// line that ended the skill's words and ran them past the panel's foot
/// (run 216). A skill with no skill-ups prints its level and opens nothing.
private struct SkillLevelButton: View {
    let skill: Skill
    let level: Int
    @State private var isOpen = false

    private var isMax: Bool { level >= skill.maxSkillLevel }

    var body: some View {
        if skill.levelUpBonuses.isEmpty {
            badge
        } else {
            Button {
                Juice.haptic(.light)
                AudioLibrary.shared.play(.uiTap)
                isOpen = true
            } label: {
                badge
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skill level \(level) of \(skill.maxSkillLevel), skill-ups")
            .popover(isPresented: $isOpen) {
                ladder
                    .padding(14)
                    .frame(width: 272, alignment: .leading)
                    .background(Theme.surface)
                    .presentationCompactAdaptation(.popover)
            }
        }
    }

    private var badge: some View {
        let label: String = "Lv.\(level)/\(skill.maxSkillLevel)"
        return HStack(spacing: 3) {
            Text(label)
                .font(Theme.numeric(11.5))
                .lineLimit(1)
                .fixedSize()
            if !skill.levelUpBonuses.isEmpty {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .black))
            }
        }
        .foregroundStyle(isMax ? Theme.gold : Theme.textSecondary)
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(Capsule().fill(Theme.surfaceHigh))
        .overlay(Capsule().strokeBorder(isMax ? Theme.gold.opacity(0.5) : Theme.stroke, lineWidth: 1))
    }

    private var ladder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SKILL-UPS")
                .font(Theme.body(11).weight(.black))
                .tracking(1.0)
                .foregroundStyle(Theme.goldDim)
            ForEach(skill.levelUpBonuses.indices, id: \.self) { step in
                let gained = level > step + 1
                let rung: String = "Lv.\(step + 2)"
                HStack(spacing: 6) {
                    Image(systemName: gained ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(gained ? Theme.success : Theme.stroke)
                    Text(rung)
                        .font(Theme.numeric(11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 38, alignment: .leading)
                    Text(skill.levelUpBonuses[step].label)
                        .font(Theme.body(12))
                        .foregroundStyle(gained ? Theme.textPrimary : Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(isMax ? "Every skill-up is in." : "The next comes from a duplicate fed in the Hall of Ka.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.goldDim)
                .fixedSize(horizontal: false, vertical: true)
        }
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
