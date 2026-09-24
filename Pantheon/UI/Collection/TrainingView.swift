import SceneKit
import SwiftUI

/// The Hall of Ka: where a unit is made stronger, and a place.
///
/// Summoners War's power-up circle, evolution and awakening under one roof.
/// Pick a unit, then feed it: every fed unit is consumed for experience, a fed
/// duplicate of the same character is a skill-up on top, evolution takes
/// same-grade fodder at max level, awakening takes essences. The rules all
/// live in `ProgressionService` and `GameStore`; this screen only shows their
/// consequences before the player commits, and what changed after.
///
/// It was three plain panels. The owner, with the power-up grid on his phone:
/// "can we do something for the consuming like with the summoning temple? A
/// place with a full UI for powering up, awakening, evolve etc?" So it is a
/// place: the painting is a temple sanctuary with an empty altar dais in its
/// left third (`hall_of_ka_bg`), and the chosen unit stands on that dais in
/// the flesh, its real model on a rune ring over the painted stone
/// (`AltarStageView`, a transparent SceneKit view the size of the frame, the
/// island's trick). A rite is played on the altar: the fed units fly into the
/// figure as orbs of their element and it flares, an evolution stands it in a
/// pillar of light, an awakening does the same and then the reveal plays the
/// new form.
///
/// **Phase B of the premium pass (2026-09-22): the altar and one ledger.**
/// Run 211's frames showed the place hidden: two cream panels covered 56% of
/// the frame and the whole dark colonnade, a cream veil lightened the rest,
/// the Result panel was three rows of words over 150 points of empty cream,
/// the disabled button read "PICK UNITS T…", the essences were words, and on
/// frame 43 the Awaken panel's fixed content outgrew its column and pushed
/// the strip half off the top of the phone. Four options were weighed
/// (PLAN.md, *Phase B of the premium pass*): glass the old panels, the altar
/// and ONE ledger, the genre's bottom tray, and the ledger without a rail. It
/// is the second, the genre's own composition (Summoners War's circle, Epic
/// Seven's Enhance) in the summon screen's materials:
///
/// - the painting full-bleed with dark scrims, never a cream veil
///   (`PlaceBackdrop`), out to the glass under the side insets and the home
///   indicator with the 3D figure in the same frame (`hallStage`), one light
///   shaft laid along the painted one and a few motes over the altar
///   (`PlaceAmbience`);
/// - the roster a dark glass rail of faces down the left (`PlaceRail`,
///   `UnitPortraitTile` — a face has no name to cut), with the rite's glyph
///   in a gold-ringed disc on the units ready for it; in Fuse the rail is
///   the six prizes;
/// - the figure clean on the dais under a small glass nameplate, the
///   awakened card floating beside it in Awaken ("BECOMES"), the moment's
///   words over it and the last commit's line at its feet;
/// - ONE glass ledger per mode on the room's dark side: a header, a body that
///   scrolls and fades, and a fixed foot with the price and the button.
///   Only the body is flexible, so no ledger can outgrow its frame again.
///
/// Sentences went behind the little ?s (`InfoDot`); the essences are their
/// paintings with have/need (`RequirementTile`); the experience is the
/// genre's gauge with the gain as a pulsing ghost (`GlassMeter`) and the
/// experience past the level cap called out; Auto offers the cheap units the
/// way Summoners War's Auto Select does; and at the level cap the Power up
/// button becomes Evolve, the next rite, rather than a dead plate (Epic
/// Seven's Promotion). No `GameStore` call and no rite changed.
struct TrainingView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    @State private var targetID: UUID?
    @State private var mode: Mode = .powerUp
    @State private var fodder: Set<UUID> = []
    @State private var outcome: String?
    /// Set when an awakening or a fusion succeeds: the summon reveal plays the
    /// new form in on the beam under its name. Both events are rarer than a
    /// summon, so both get the beam.
    @State private var reveal: SummonResult?
    /// The rite the altar is playing, stamped so the stage plays each once.
    @State private var ceremony: AltarCeremony?
    /// The words of the moment over the altar — "LEVEL UP!" — for a breath.
    @State private var stamp: AltarStamp?
    @State private var stampSequence = 0
    /// The hexagram picked on the Fuse rail. Nil is the first one ready, or
    /// the first of the six (`selectedPlan`).
    @State private var fusionID: String?
    /// The question asked before an offering that eats a unit worth keeping
    /// — one on a team, wearing relics or a boon, awakened, or a 4★ and up
    /// fed for experience — the genre's "a 4★+ monster is included" prompt.
    /// Nil when nothing is being asked.
    @State private var warning: OfferingWarning?

    /// Whether the Power up ledger opens with Auto's offering already chosen
    /// (and the Evolve ledger with its sockets filled by the cheapest units
    /// of the grade nothing keeps, `evolutionOffering`). No player path asks
    /// for it; the CI tour's `-tour-training feed` frame does, because the
    /// ghost gauge, the cost and the chosen veils had never been photographed
    /// (2026-09-22), and the evolve frame may, for a lit EVOLVE.
    private let offersOnOpen: Bool

    /// Which tab the screen opens on, and on whom. Every caller wants the
    /// default mode; the CI tour wants a way to photograph the fusion board
    /// without a tap, and `@State` cannot read another property without an
    /// initialiser. The collection's Train button names the unit it was
    /// pressed beside, so the hall opens on that unit rather than on the
    /// strongest; nil keeps the old behaviour, the top of the rail.
    init(initialMode: Mode = .powerUp, selectedUnitID: UUID? = nil, offersOnOpen: Bool = false) {
        _mode = State(initialValue: initialMode)
        _targetID = State(initialValue: selectedUnitID)
        self.offersOnOpen = offersOnOpen
    }

    enum Mode: String, CaseIterable {
        case powerUp = "Power up"
        case evolve = "Evolve"
        case awaken = "Awaken"
        case fuse = "Fuse"
    }

    /// The mode switch as the strip's segments, in the order it always had.
    private var modes: [(value: Mode, title: String)] {
        Mode.allCases.map { (value: $0, title: $0.rawValue) }
    }

    /// Everything owned, strongest first, so the unit worth training is near
    /// the top of the rail.
    private var units: [ResolvedUnit] {
        store.resolvedUnits.sorted { $0.power > $1.power }
    }

    /// The unit on the dais: the one picked, or the top of the rail until
    /// one is. The fallback is HERE and not only in `.onAppear`, so the hall
    /// opened from the island builds its figure in the stage's `makeUIView`,
    /// before the view's first frame, like every other stage — with the
    /// pick landing a beat later, the figure went into a live scene, which
    /// is where its idle never started (2026-09-17).
    private var target: ResolvedUnit? {
        guard let targetID else { return units.first }
        return units.first { $0.id == targetID }
    }

    /// The strip's second line. The nameplate over the altar names the unit
    /// now, so the strip no longer repeats "Zeus · Lv.12"; it keeps a line in
    /// every mode so the carved title does not jump when the mode changes.
    private var subtitle: String {
        if mode == .fuse {
            let ready = plans.filter { $0.canFuse }.count
            return "\(FusionService.recipes.count) hexagrams · \(ready) ready"
        }
        return "\(units.count) units"
    }

    /// Every recipe measured against the save. Six recipes of four corners
    /// against a roster of a hundred is a few hundred comparisons, which is
    /// cheaper than a cache that goes stale the moment a fusion eats something.
    private var plans: [FusionService.Plan] {
        FusionService.recipes.map { FusionService.plan(for: $0, player: store.player) }
    }

    /// The hexagram on the altar: the one picked on the rail, else the first
    /// that can be fused now, else the first of the six.
    private var selectedPlan: FusionService.Plan? {
        let all = plans
        return all.first { $0.id == fusionID } ?? all.first { $0.canFuse } ?? all.first
    }

    /// What stands on the dais: the unit in training, or in Fuse the prize —
    /// a unit the player may not own yet, which is why the altar takes a
    /// blueprint and not an owned unit.
    private var altarBlueprint: UnitBlueprint? {
        mode == .fuse ? selectedPlan?.recipe.result : target?.blueprint
    }

    private var altarAwakened: Bool {
        mode == .fuse ? false : (target?.unit.isAwakened ?? false)
    }

    /// Units standing on a saved team. Auto never offers one of them: the
    /// genre's auto-select skips a monster wearing runes, and a team member
    /// eaten by a button is worse than one wearing a relic.
    private var keptIDs: Set<UUID> {
        let player = store.player
        var kept = Set(player.campaignTeam.unitIDs)
        kept.formUnion(player.arenaOffenseTeam.unitIDs)
        kept.formUnion(player.arenaDefenseTeam.unitIDs)
        for team in player.savedTeams { kept.formUnion(team.unitIDs) }
        return kept
    }

    // MARK: - The budget
    //
    // Written down, because a guess is what pushed frame 43's strip off the
    // phone. An iPhone 16 Pro in landscape is 874 × 402 points; the hall is a
    // full-screen cover or a sheet, so no tab bar sits under it. Take the side
    // insets (62 each), the home indicator (21) and the strip (52) and the
    // content is **750 × 329**. The STAGE — the painting, the figure and the
    // light — is not: it bleeds under both side insets and the home indicator
    // to the glass, **874 × 350** (run 216: the sanctuary sat in a cream box
    // on three sides), and the figure is solved on that frame
    // (`AltarStageView.placement`), so the painted dais and the 3D figure
    // share one frame and cannot slide apart.
    //
    // Across: the rail is 84, the ledger 320 plus the 12-point edge, and the
    // altar column keeps the 334 between them — the painted dais is 29% of the
    // way across the WHOLE stage (253 points, 191 into the safe frame), 107
    // into that column, under the figure.
    //
    // Down, inside the ledger (329, less 8 above and below, less its own 10
    // and 10): **293**. Power up spends 26 on the header, 58 on the gauge (the
    // level line, the bar, the experience line), 46 on the foot and 24 on the
    // three gaps, which leaves 139 for the offering: two rows of 52-point faces
    // and the top of a third, so the grid visibly goes on. Evolve spends 26 on
    // its title, 24 on the grade line, 60 on the sockets the price fills, 46
    // on the foot and 32 on the gaps, and leaves about 105: the "YOUR 3★"
    // label and a row of faces with the next one under the fade. The body is
    // inset 12 inside the plate's own edge, so a face's rarity glow is never
    // cut on the scroll view's line. Awaken has no header and scrolls its whole
    // body (the name, the bonus, four essence tiles: about 240) over a 46-point
    // foot. Fuse spends 26 and 46 and scrolls about 200. On a mini (375 tall)
    // the offering keeps its two rows; every body scrolls, nothing else moves.

    private let railWidth: CGFloat = 84
    private let ledgerWidth: CGFloat = 320
    /// Five faces across the ledger's 296 inner points: 5 × 52 + 4 × 7 = 288.
    /// The glow round each face has the plate's own 12 points on either side
    /// (`HallLedger` insets the body inside the scroll view, not round it).
    private let offeringColumns = Array(repeating: GridItem(.fixed(52), spacing: 7), count: 5)
    /// Four essences across: a `RequirementTile` of 56 is 68 wide with its
    /// caption, so 4 × 68 + 3 × 6 = 290.
    private let essenceColumns = Array(repeating: GridItem(.fixed(68), spacing: 6), count: 4)
    /// Four fusion corners across, the same 68-point columns, TOP-aligned: a
    /// name that wraps ("Jackal / Warrior") centred its whole tile 12 points
    /// higher than its neighbours' and the row zig-zagged (run 216).
    private let cornerColumns = Array(repeating: GridItem(.fixed(68), spacing: 6, alignment: .top), count: 4)
    /// What one offered unit costs to feed, in drachma — `GameStore.levelUp`'s
    /// price, written once here for the well and the rate beside the button.
    private static let drachmaPerOffering = 500
    /// The experience bar's fill: the unit plate's old verdigris lifted to
    /// read on dark glass, so the pale-gold ghost of the gain ahead of it is a
    /// different colour from the bar it extends.
    private static let experienceTint = Color(hex: "#4FB3A0")

    var body: some View {
        NavigationStack {
            GameScreen("Hall of Ka", subtitle: subtitle, dismiss: { dismiss() }) {
                // Always shown: fusion needs no unit picked, so hiding the
                // switch with an empty roster would hide the one mode that
                // still works.
                BarSegments(options: modes, selection: $mode)
                BarWallet(wallet: store.player.wallet, shows: [.drachma])
            } content: {
                // The rail, the altar's words and the ledger in the safe
                // frame; the stage under them out to the glass. The reader
                // is how the words know where the stage put the figure.
                GeometryReader { geometry in
                    hall(figureX: figureInColumn(geometry))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background { hallStage }
            }
            .onAppear {
                if targetID == nil { targetID = units.first?.id }
                // The altar loads a unit's model the moment it is picked; the
                // top of the rail is warmed off the main thread so the first
                // few taps do not stall on parsing.
                ModelLibrary.shared.warm(forms: units.prefix(6).map { (spec: $0.blueprint.model, awakened: $0.unit.isAwakened) }, crowded: false, clips: false)
                warmAwakening()
                if mode == .fuse { warmPrizes() }
                if offersOnOpen, mode == .powerUp, let target {
                    fodder = Set(OfferingRule.pick(for: target.unit, from: store.player.units, keep: keptIDs))
                }
                // The same for Evolve: the cheapest units of the grade that
                // nothing keeps, as many as the rite eats, so the tour can
                // photograph the sockets filled and EVOLVE lit.
                if offersOnOpen, mode == .evolve, let target {
                    fodder = Set(evolutionOffering(for: target).map(\.id))
                }
            }
            .onChange(of: mode) { _, now in
                fodder = []
                // The label belongs to the mode that wrote it: "Ares fused"
                // beside Zeus in the Power up column is a lie the next tap
                // would have to explain.
                outcome = nil
                // The prizes stand on the altar in Fuse: parse them before
                // the first tap on the rail asks for one.
                if now == .fuse { warmPrizes() }
                warmAwakening()
            }
            .onChange(of: targetID) { previous, _ in
                warmAwakening()
                // The first pick is the fallback landing in `.onAppear`, not
                // the player's: it must not clear an offering the tour's
                // `offersOnOpen` has just chosen for that same unit.
                guard previous != nil else { return }
                fodder = []
                outcome = nil
            }
            .fullScreenCover(item: $reveal) { result in
                SummonRevealView(results: [result]) { reveal = nil }
            }
            .alert(
                warning?.title ?? "",
                isPresented: warningShown,
                presenting: warning
            ) { asked in
                Button("Offer", role: .destructive) { asked.commit() }
                Button("Keep them", role: .cancel) {}
            } message: { asked in
                Text(asked.message)
            }
        }
    }

    /// Whether the keep-it question is up; dismissing it forgets it.
    private var warningShown: Binding<Bool> {
        Binding(get: { warning != nil }, set: { if !$0 { warning = nil } })
    }

    // MARK: - The hall

    /// The stage: the painting, the figure on its dais and the light falling
    /// on both, in ONE frame that runs under the side insets and the home
    /// indicator to the glass. Run 216 had the painting as a background of
    /// the safe frame, so the dark sanctuary sat in flat cream on three sides
    /// — the most "app, not game" thing on every Hall frame. The figure's
    /// view is in the same frame as the painting, never beside it: the
    /// camera is solved against the painting's crop in that frame
    /// (`AltarStageView.placement`), so the feet stay on the painted stone
    /// on any phone. Every layer ignores the safe area itself as well as
    /// through the stack, so each one is laid out in the stage's frame.
    private var hallStage: some View {
        ZStack {
            hallBackdrop
                .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
            AltarStageView(blueprint: altarBlueprint, awakened: altarAwakened, ceremony: ceremony)
                .allowsHitTesting(false)
                .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
            // The shaft alone out here; the motes rise in the altar column
            // (`altarColumn`), because through the ledger's glass they read
            // as specks of dust — one as a missing sixth star (run 216).
            PlaceAmbience(shafts: LightShaft.sanctuary, motes: 0, seed: 944)
                .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
        }
        .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
    }

    /// Where the figure's centre line stands in the altar column, in points
    /// from the column's leading edge. The stage is the whole glass, so the
    /// dais is solved on that frame — the safe frame widened by its side
    /// insets and lengthened by the home indicator — and brought back into
    /// the column's coordinates (the island reads its insets the same way).
    private func figureInColumn(_ geometry: GeometryProxy) -> CGFloat {
        let insets = geometry.safeAreaInsets
        let stage = CGSize(
            width: geometry.size.width + insets.leading + insets.trailing,
            height: geometry.size.height + insets.bottom
        )
        let across = AltarStageView.placement(in: stage).across
        return stage.width * across - insets.leading - railWidth
    }

    /// The sanctuary under everything (`PlaceBackdrop` is a `PaintingFill`,
    /// which reports only the space it is given — the dungeon screen's
    /// lesson). Its scrims are lighter than the summon hall's, 0.45 at the
    /// top and the foot, because the painted dais is in the bottom fifth and
    /// the figure stands on it; the right half, where the ledger's glass sits
    /// on the dark colonnade, goes a little darker still. The cream veil it
    /// replaces lightened exactly the half that should be dark.
    private var hallBackdrop: some View {
        PlaceBackdrop(painting: "hall_of_ka_bg", topScrim: 0.45, footScrim: 0.45)
            .overlay(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.5),
                        .init(color: Color.black.opacity(0.35), location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .allowsHitTesting(false)
    }

    /// The rail, the altar's words and the ledger across the stage, in the
    /// safe frame. The ledger is exactly `ledgerWidth` in every mode:
    /// `HallLedger` takes the width it is given and no child can widen it
    /// (run 216's Evolve plate grew 35 points and hung off the painting).
    private func hall(figureX: CGFloat) -> some View {
        HStack(spacing: 0) {
            rail
            altarColumn(figureX: figureX)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            ledger
                .frame(width: ledgerWidth)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 8)
                .padding(.trailing, ScreenChrome.contentPadding)
        }
    }

    // MARK: - The rail

    /// The roster as a rail of faces down the left edge, on the summon rail's
    /// dark glass with its fade at the foot: in landscape the height is the
    /// scarce dimension, and one column keeps four units in reach and the
    /// painting's columns in view. The "WHO TRAINS" label, gold at the floor
    /// on a pale plate, could not be read in either of run 211's frames, and
    /// a card's name strip cut "Anubis, Keep…"; a face has neither. In Fuse
    /// the rail is the six prizes instead, because fusion trains nobody.
    ///
    /// The roster opens on the unit on the dais, with whole faces at its top
    /// (`WholeRowRail`, the Labyrinth's rail): run 221's Awaken frame had
    /// Sekhmet on the altar and the rail showing Thoth to Perseus, so no face
    /// on it said who was being trained. A unit picked on the rail leaves the
    /// rail where it is, under the finger.
    @ViewBuilder
    private var rail: some View {
        if mode == .fuse {
            let chosenPlan = selectedPlan?.id
            PlaceRail(width: railWidth) {
                ForEach(plans) { plan in
                    prizeRow(plan, isOn: plan.id == chosenPlan)
                }
            }
        } else {
            let onAltar = target?.id
            WholeRowRail(width: railWidth, items: units, focus: onAltar) { unit in
                rosterRow(unit, isOn: unit.id == onAltar)
            }
        }
    }

    private func rosterRow(_ unit: ResolvedUnit, isOn: Bool) -> some View {
        Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            targetID = unit.id
        } label: {
            UnitPortraitTile(unit: unit, size: 58)
                // The rite's own mark on a unit ready for it: on the face's
                // right edge, hanging just off it, in the top corner UNDER
                // the level capsule (which ends 17 points down) and well
                // above the star row (which starts about 48 down). On the
                // bottom corner it hid the last star of every ready tile
                // (run 217: Thoth, Ares and Zeus read as 4★). Not on the
                // unit already on the altar: the ledger beside it says so
                // in words.
                .overlay(alignment: .topTrailing) {
                    if !isOn, let glyph = readyGlyph(unit) {
                        readyMark(glyph)
                            .offset(x: 6, y: 20)
                    }
                }
                .padding(4)
                .background(GlassRowPlate(isOn: isOn))
                // The face's own shape is the tap, plus the plate's padding:
                // a thumb on the plate's rim picks the unit too.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Whether the unit can take this mode's rite now: at its level cap for
    /// Evolve (the genre marks the ones ready to promote), unawakened with
    /// the whole bill of essences held for Awaken. Power up has no pip —
    /// every unit can be fed.
    private func isReady(_ unit: ResolvedUnit) -> Bool {
        switch mode {
        case .evolve:
            return unit.unit.canEvolve
        case .awaken:
            guard !unit.unit.isAwakened, let awakening = unit.blueprint.awakening else { return false }
            return awakening.essenceCost.allSatisfy { (store.player.essences[$0.key] ?? 0) >= $0.value }
        case .powerUp, .fuse:
            return false
        }
    }

    /// The glyph of the rite a unit is ready for in this mode — the star of
    /// Evolve, the sun of Awaken — or nil.
    private func readyGlyph(_ unit: ResolvedUnit) -> String? {
        guard isReady(unit) else { return nil }
        return mode == .awaken ? "sun.max.fill" : "star.fill"
    }

    /// "Ready for the rite": a 16-point dark disc with the rite's glyph in
    /// gold and a gold ring that breathes. The 10-point cream dot it replaces
    /// hung off the corner and read as a stray page dot (run 216).
    private func readyMark(_ glyph: String) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            let pulse = 0.55 + 0.45 * (0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 3))
            ZStack {
                Circle().fill(Color(hex: "#17120E").opacity(0.94))
                Circle().strokeBorder(Theme.gold.opacity(pulse), lineWidth: 1.5)
                Image(systemName: glyph)
                    .font(.system(size: 8.5, weight: .black))
                    .foregroundStyle(Theme.gold)
            }
            .frame(width: 16, height: 16)
            .shadow(color: Theme.gold.opacity(0.55 * pulse), radius: 4)
        }
        .allowsHitTesting(false)
    }

    /// One hexagram on the Fuse rail: the prize's card in its grade's metal,
    /// its element, and READY in green or how many corners are filled. A
    /// prize that cannot be fused yet is drawn half-grey, so the ready ones
    /// read before a word is.
    private func prizeRow(_ plan: FusionService.Plan, isOn: Bool) -> some View {
        let filled = plan.slots.count - plan.missing.count
        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            fusionID = plan.id
        } label: {
            VStack(spacing: 3) {
                prizePortrait(plan.recipe.result, size: 58)
                    .saturation(plan.canFuse ? 1 : 0.55)
                Text(plan.canFuse ? "READY" : "\(filled)/\(plan.slots.count)")
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(plan.canFuse ? Theme.onGlassSuccess : Theme.onGlassDim)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(4)
            .background(GlassRowPlate(isOn: isOn))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(plan.recipe.name)
    }

    /// A prize's card: the painting in a dark socket, the element on it, the
    /// grade's metal round it. Every portrait is square, so the fill does not
    /// overhang the frame it is given.
    private func prizePortrait(_ blueprint: UnitBlueprint?, size: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let zoom: CGFloat = Self.fullFigurePrizes.contains(blueprint?.id ?? "") ? 1.9 : 1
        return ZStack(alignment: .topLeading) {
            shape.fill(Theme.socketFill)
            if let blueprint, BundleImage.exists(blueprint.model.portraitName) {
                BundleImage(name: blueprint.model.portraitName, renderedAt: size * zoom)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .scaleEffect(zoom, anchor: .top)
            }
            if let blueprint {
                ElementBadge(element: blueprint.element, compact: true, scale: 0.72)
                    .padding(3)
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .rarityFrame(Rarity(stars: blueprint?.naturalStars ?? 5), radius: 7, painted: false)
    }

    /// Prizes whose card was painted as a whole small figure on black rather
    /// than a bust (the fire Horus): drawn at 1.9× from the top, so the head
    /// and chest fill the face like the other five until the card is
    /// re-rolled as a bust.
    private static let fullFigurePrizes: Set<String> = ["horus_ember"]

    // MARK: - The altar

    /// Over the altar, all as overlays on a clear column (an overlay is never
    /// measured, so nothing here can grow the column): the nameplate at the
    /// top left, clear of the figure's head; the awakened card floating
    /// beside the figure in Awaken; the moment's words over it; the last
    /// commit's line at its feet.
    private func altarColumn(figureX: CGFloat) -> some View {
        Color.clear
            // The motes rise here and nowhere else: over the figure and the
            // dais, never through the rail's or the ledger's glass.
            .background {
                // Clear of the column's foot by the motes' own 40, not a
                // place's 80: the column has no deck under it, and 80 would
                // lift them off the painted dais they rise from.
                PlaceAmbience(shafts: [], motes: 18, seed: 944, bleeds: false, moteClearance: 40)
                    .clipped()
            }
            .overlay(alignment: .topLeading) {
                nameplate
                    .padding(.top, 8)
                    .padding(.leading, 8)
            }
            .overlay {
                // Measured, because the card must stand clear of the figure
                // and the figure's place depends on the whole stage's width.
                GeometryReader { column in
                    becomesCard(size: becomesSize(columnWidth: column.size.width, figureX: figureX))
                        .padding(.trailing, 10)
                        .offset(y: -12)
                        .frame(width: column.size.width, height: column.size.height, alignment: .trailing)
                }
            }
            .overlay(alignment: .bottom) {
                if let stamp {
                    stampView(stamp)
                        .padding(.bottom, 88)
                }
            }
            .overlay(alignment: .bottom) {
                outcomeLine
                    .padding(.bottom, 10)
            }
            .overlay {
                if mode != .fuse, target == nil {
                    EmptyState(
                        icon: "person.crop.circle.badge.questionmark",
                        title: "Choose a unit",
                        message: "Tap a unit in the rail to train it.",
                        onGlass: true
                    )
                }
            }
    }

    @ViewBuilder
    private var nameplate: some View {
        if mode == .fuse {
            if let plan = selectedPlan, let result = plan.recipe.result {
                prizeNameplate(plan, result: result)
            }
        } else if let target {
            unitNameplate(target)
        }
    }

    /// Who stands on the altar, on a small glass plate: the name carved (the
    /// name before its epithet — the epithet cut it to "SEK…" on frame 43),
    /// the stars, the element, the level (gold at the cap) and the power.
    /// Two rows and at most 280 wide, so it stays above the figure's head.
    private func unitNameplate(_ unit: ResolvedUnit) -> some View {
        nameplateGlass {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(personalName(unit.name).uppercased())
                        .font(Theme.display(22))
                        .tracking(1.0)
                        .carved(glow: false)
                        .lineLimit(1)
                        // 22 × 0.62 is 13.6, over the title floor: the longest
                        // name the roster holds, "Heracles Alexikakos", fits
                        // at about two thirds.
                        .minimumScaleFactor(0.62)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    Text("POWER")
                        .font(Theme.body(11).weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(Theme.onGlassDim)
                        .lineLimit(1)
                        .fixedSize()
                }
                HStack(spacing: 8) {
                    // Bright on the glass, as the faces' stars are since run
                    // 216: the natural stars' dim bronze could not be counted.
                    StarRow(stars: unit.stars, size: 11)
                    ElementBadge(element: unit.element, compact: true)
                    Text("Lv.\(unit.level)")
                        .font(Theme.numeric(13))
                        .foregroundStyle(unit.unit.isMaxLevel ? Theme.onGlassGold : Theme.onGlass)
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 8)
                    Text(unit.power.formatted())
                        .font(Theme.numeric(15))
                        .foregroundStyle(Theme.onGlassGold)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
    }

    /// The prize on the altar in Fuse: its name, grade and element, and the
    /// whole reason to fuse rather than pull — EXCLUSIVE, or a rose IN THE
    /// POOL if the pool filter ever comes off and the gacha starts handing the
    /// prize out again.
    private func prizeNameplate(_ plan: FusionService.Plan, result: UnitBlueprint) -> some View {
        nameplateGlass {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    Text(personalName(result.name).uppercased())
                        .font(Theme.display(22))
                        .tracking(1.0)
                        .carved(glow: false)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    Group {
                        if plan.recipe.isExclusive {
                            Text("EXCLUSIVE")
                                .font(Theme.body(11).weight(.black))
                                .tracking(0.8)
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 8)
                                .frame(height: 20)
                                .background(Capsule().fill(Theme.goldPlate))
                        } else {
                            Text("IN THE POOL")
                                .font(Theme.body(11).weight(.black))
                                .tracking(0.8)
                                .foregroundStyle(Theme.onGlassDanger)
                                .padding(.horizontal, 8)
                                .frame(height: 20)
                                .background(Capsule().fill(Theme.glass))
                                .overlay(Capsule().strokeBorder(Theme.onGlassDanger.opacity(0.7), lineWidth: 0.8))
                        }
                    }
                    .lineLimit(1)
                    .fixedSize()
                }
                HStack(spacing: 8) {
                    StarRow(stars: result.naturalStars, size: 11)
                    ElementBadge(element: result.element, compact: true)
                    Spacer(minLength: 8)
                    Text("\(plan.slots.count - plan.missing.count) / \(plan.slots.count) corners")
                        .font(Theme.numeric(12))
                        .foregroundStyle(plan.missing.isEmpty ? Theme.onGlassSuccess : Theme.onGlassDim)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
    }

    /// The nameplate's glass: 12 and 8 of padding inside a plate no wider than
    /// 280, 66 points tall with its two rows — its foot at 74 from the top of
    /// the frame, over the figure's head at about 85 (`AltarStageView.fill`).
    private func nameplateGlass<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 280, alignment: .leading)
            .background(GlassPlate(radius: 12))
    }

    /// The name before its epithet: "Sekhmet", not "Sekhmet, Bringer of the
    /// Seven Arrows" — the whole name is the Awaken ledger's title.
    private func personalName(_ name: String) -> String {
        name.split(separator: ",", maxSplits: 1).first.map { String($0) } ?? name
    }

    /// The epithet after the comma — "Bringer of the Seven Arrows" — or nil
    /// for a name that has none ("Ares Stormlance").
    private func epithetPart(_ name: String) -> String? {
        let parts = name.split(separator: ",", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let rest = parts[1].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : rest
    }

    /// In Awaken, the card the unit becomes, floating beside the figure on the
    /// altar with a gold chevron from the figure to it — the genre sells an
    /// awakening as two forms side by side. It replaces the Awaken panel's two
    /// 84-point cards and their cut captions ("Sekhmet, Brin…").
    @ViewBuilder
    private func becomesCard(size: CGFloat) -> some View {
        if let art = becomesArt, let target, size >= 56 {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(Theme.onGlassGold)
                    .shadow(color: Theme.gold.opacity(0.7), radius: 6)
                VStack(spacing: 4) {
                    Text("BECOMES")
                        .font(Theme.title(13))
                        .tracking(2)
                        .carved(glow: false)
                        .lineLimit(1)
                        .fixedSize()
                    ZStack(alignment: .topLeading) {
                        BundleImage(name: art, renderedAt: size)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: size, height: size)
                        // The awakened sun in its socket, as every card
                        // wears it since round 4 (`CardMark`): a bare
                        // cream glyph with a shadow floated on the purple
                        // art (run 224, 43-awaken). At 20 its glyph is the
                        // 11 points the bare one was.
                        CardMark(systemName: "sun.max.fill", size: 20)
                            .padding(5)
                    }
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
                    .rarityFrame(Rarity(stars: target.stars), painted: false)
                    .shadow(color: target.element.color.opacity(0.6), radius: 12)
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// The awakened card's side: 96 points where the altar has the room, and
    /// whatever stands clear of the figure where it has not. The figure's
    /// centre line is `figureX` into this column (`figureInColumn`, solved on
    /// the whole stage), and it is taken as 48 points wide either side of
    /// that line; the card also gives up its 10-point margin and the
    /// chevron's 24. On an iPhone 16 Pro that is the full 96 (about 140 to
    /// spare); on an SE, whose frame is 667 wide with no side insets, the
    /// column is 251 and the card about 59 — at 96 it stood over the figure.
    /// A card under 56 is not drawn at all.
    private func becomesSize(columnWidth: CGFloat, figureX: CGFloat) -> CGFloat {
        let figureRight = figureX + 48
        return min(96, columnWidth - figureRight - 10 - 24)
    }

    /// The awakened card's painting, when this is the moment to show it: in
    /// Awaken, on a unit with an awakened form it has not taken, whose card
    /// ships.
    private var becomesArt: String? {
        guard mode == .awaken, let target, !target.unit.isAwakened, target.blueprint.awakening != nil else { return nil }
        let art = target.blueprint.model.portraitName(awakened: true)
        return BundleImage.exists(art) ? art : nil
    }

    /// "LEVEL UP!" and the line under it, sprung in and gone in a breath —
    /// carved gold now, the summon room's display type.
    private func stampView(_ stamp: AltarStamp) -> some View {
        VStack(spacing: 2) {
            Text(stamp.title)
                .font(Theme.display(34))
                .carved()
            if !stamp.detail.isEmpty {
                Text(stamp.detail)
                    .font(Theme.numeric(14))
                    .foregroundStyle(Theme.onGlass)
                    .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
            }
        }
        .multilineTextAlignment(.center)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
        .id(stamp.id)
    }

    /// What the last commit did, at the feet of the unit it was done to. It
    /// wraps rather than truncates: "Powered up: Lv.12 → Lv.19, skill-up ×2,
    /// regalia → III" is two lines in the altar's 334 points.
    @ViewBuilder
    private var outcomeLine: some View {
        if let outcome {
            Text(outcome)
                .font(Theme.body(12).weight(.semibold))
                .foregroundStyle(Theme.onGlassGold)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.glass))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.glassRim, lineWidth: 0.8))
                .padding(.horizontal, 12)
                .allowsHitTesting(false)
        }
    }

    /// Shows the moment's words over the altar for a breath and a half.
    private func show(_ title: String, _ detail: String) {
        stampSequence += 1
        let mine = stampSequence
        withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
            stamp = AltarStamp(id: mine, title: title, detail: detail)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard mine == stampSequence else { return }
            withAnimation(.easeOut(duration: 0.4)) { stamp = nil }
        }
    }

    private func play(_ kind: AltarCeremony.Kind, tint: String) {
        ceremony = AltarCeremony(stamp: (ceremony?.stamp ?? 0) + 1, kind: kind, tintHex: tint)
    }

    /// The six prizes' meshes, parsed off the main thread when Fuse opens.
    private func warmPrizes() {
        ModelLibrary.shared.warm(plans.compactMap { $0.recipe.result?.model }, crowded: false, clips: false)
    }

    /// The awakened form of the unit on the dais, parsed off the main thread
    /// while the Awaken ledger is up, so the rite's figure swap
    /// (`altarAwakened` flips the moment `store.awaken` returns) clones from
    /// the cache. `warm(forms:)` warms only the form a unit has today, and the
    /// LRU keeps an unused entry safe for `recentGrace` only, so this runs
    /// again on every change of mode or target. `clips: true` also warms the
    /// awakened rig's idle, which `place()` asks for on the main thread.
    private func warmAwakening() {
        guard mode == .awaken, let target, !target.unit.isAwakened,
              target.blueprint.awakening != nil else { return }
        ModelLibrary.shared.warm(forms: [(spec: target.blueprint.model, awakened: true)], crowded: false, clips: true)
    }

    // MARK: - The ledger

    /// The mode's one glass ledger. Every mode names its case, so a fifth
    /// mode cannot fall through to an empty column.
    @ViewBuilder
    private var ledger: some View {
        switch mode {
        case .powerUp:
            if let target { powerUpLedger(target) }
        case .evolve:
            if let target { evolveLedger(target) }
        case .awaken:
            if let target { awakenLedger(target) }
        case .fuse:
            if let plan = selectedPlan { fusionLedger(plan) }
        }
    }

    /// A ledger with nothing to do: the empty state on the same glass, so the
    /// column keeps its plate and the room keeps its shape.
    private func quietLedger(icon: String, title: String, message: String) -> some View {
        EmptyState(icon: icon, title: title, message: message, onGlass: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(GlassPlate(radius: 14))
    }

    /// The ledger's button: the painted gold plate when it can be pressed,
    /// dimmed glass when it cannot. A disabled painted button is still the
    /// cream plate (the greyed plate for every screen is a separate change,
    /// PLAN.md), and a cream slab on this glass is the fault this pass
    /// removes. The title is the rite and nothing else — never a sentence,
    /// which is what truncated to "PICK UNITS T…".
    private func ledgerButton(
        _ title: String,
        systemImage: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        PrimaryButton(
            title: title,
            systemImage: systemImage,
            isEnabled: isEnabled,
            style: isEnabled ? .painted : .glass,
            action: action
        )
    }

    private func infoText(_ text: String) -> some View {
        Text(text)
            .font(Theme.body(12))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Power up

    private func powerUpLedger(_ target: ResolvedUnit) -> some View {
        let kept = keptIDs
        let candidates = cheapestFirst(units.filter { $0.id != target.id && !$0.unit.isLocked }, kept: kept)
        let chosen = candidates.filter { fodder.contains($0.id) }
        let experience = chosen.reduce(0) { $0 + ProgressionService.feedValue(of: $1.unit) }
        let duplicates = chosen.filter { $0.blueprint.id == target.blueprint.id }.count
        let kin = chosen.filter { RegaliaService.isSameFamily($0.unit, as: target.unit) }.count
        let cost = chosen.count * Self.drachmaPerOffering
        var preview = target.unit
        let gained = ProgressionService.grantExperience(experience, to: &preview)
        let reached = preview
        let affordable = store.player.wallet.drachma >= cost
        // At the level cap with nothing of the family offered, feeding buys
        // nothing: the button is the next rite instead (Epic Seven puts
        // Promotion where Enhance was). A 6★ has no next rite and keeps the
        // button; a copy of the family still raises its skills or regalia.
        let promotes = target.unit.isMaxLevel && kin == 0 && target.stars < 6

        return HallLedger {
            VStack(alignment: .leading, spacing: 8) {
                offeringHeader(target, chosen: chosen.count)
                experienceGauge(target, experience: experience, gained: gained, reached: reached, duplicates: duplicates)
            }
        } content: {
            if candidates.isEmpty {
                EmptyState(
                    icon: "tray",
                    title: "Nothing to offer",
                    message: "Locked units are never consumed.",
                    onGlass: true
                )
            } else {
                offeringGrid(candidates, target: target, limit: 12, marksKin: true, kept: kept)
            }
        } foot: {
            HStack(spacing: 8) {
                if promotes {
                    ledgerButton("Evolve", systemImage: "star.circle.fill", isEnabled: true) {
                        mode = .evolve
                    }
                } else {
                    // Nothing chosen is the RATE, not a zero: "0" beside a
                    // dead button read as a broken price (run 216).
                    if chosen.isEmpty {
                        rateWell
                    } else {
                        CostWell(key: "drachma", amount: cost, affordable: affordable, height: PrimaryButton.height)
                    }
                    ledgerButton("Power up", systemImage: "arrow.up.circle.fill", isEnabled: !chosen.isEmpty && affordable) {
                        askBeforeOffering(chosen, gradeCounts: true, kept: kept) {
                            commitPowerUp(target, feeding: chosen)
                        }
                    }
                }
            }
        }
    }

    /// The price before anything is chosen: the drachma and "500 each" in
    /// the cost well's own dark socket, dim, so the foot reads as the rule
    /// and not as a price of nothing.
    private var rateWell: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
        let rate = "\(Self.drachmaPerOffering) each"
        return HStack(spacing: 6) {
            ItemIcon(key: "drachma", size: 20, glow: false)
            Text(rate)
                .font(Theme.numeric(13))
                .foregroundStyle(Theme.onGlassDim)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: PrimaryButton.height)
        .background(shape.fill(Color(hex: "#1C1610").opacity(0.9)))
        .overlay(shape.strokeBorder(Theme.goldDim.opacity(0.8), lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .combine)
    }

    /// The Offering's name and count, the rule behind the ?, and Auto — or
    /// Clear once anything is chosen.
    private func offeringHeader(_ target: ResolvedUnit, chosen: Int) -> some View {
        HStack(spacing: 6) {
            GlassSectionHeader(title: "Offering", accessory: "\(chosen) / 12")
            InfoDot(title: "Offering") {
                infoText("Every unit offered is consumed for experience, at 500 drachma each. A copy of \(personalName(target.name)) (marked ↑) is a skill-up as well; once its skills are capped, or for another element of the family, it raises the regalia. Auto offers unlocked 1–3★ units that wear no relic or boon and stand on no team, and stops at the level cap. A unit on a team (shield), wearing relics (diamond) or awakened (sun) is marked and listed last, and the hall asks before it is offered.")
            }
            if fodder.isEmpty {
                GlassBead(text: "Auto", systemImage: "wand.and.stars", tint: Theme.onGlassGold) {
                    offerAutomatically(to: target)
                }
            } else {
                GlassBead(text: "Clear", systemImage: "xmark", tint: Theme.onGlass) {
                    fodder = []
                }
            }
        }
    }

    /// The genre's power-up read: the level now and the level the offering
    /// reaches (and a "+1 LV" seal), the skill-ups it carries, the bar with
    /// the gain as pulsing gold light ahead of the fill (the reached level's
    /// bar, filled from its start, when a level is crossed), and the
    /// experience it brings — or, when the offering runs past the level cap,
    /// how much of it would be wasted (Summoners War's over-cap warning).
    ///
    /// It is fixed in the ledger's header, not in the scrolling body: a face
    /// chosen from the third row of the offering has to move the gauge in
    /// view, or the player scrolls to choose and back to read.
    private func experienceGauge(
        _ target: ResolvedUnit,
        experience: Int,
        gained: Int,
        reached: Unit,
        duplicates: Int
    ) -> some View {
        let unit = target.unit
        let needed = ProgressionService.experienceForNextLevel(level: unit.level, stars: unit.stars)
        // The bar of the level the offering REACHES once it crosses one: the
        // genre's wrapping bar, the gain as gold light from its start (full
        // at the cap). A ghost run to the end of the old level's bar said
        // "a level" and nothing about how far into the next.
        let reachedNeeded = max(1, ProgressionService.experienceForNextLevel(level: reached.level, stars: reached.stars))
        let reachedInto = reached.isMaxLevel ? reachedNeeded : max(1, reached.experience)
        let levelsGained = "+\(gained) LV"
        let wasted = unit.isMaxLevel ? 0 : max(0, experience - experienceToCap(unit))
        let line: String
        if unit.isMaxLevel {
            line = unit.stars < 6 ? "Level cap for \(unit.stars)★" : "The top of the ladder"
        } else if experience > 0 {
            line = "+\(experience.formatted()) EXP"
        } else {
            line = "\(unit.experience.formatted()) / \(needed.formatted()) EXP"
        }

        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Lv.\(unit.level)")
                    .font(Theme.numeric(15))
                    .foregroundStyle(unit.isMaxLevel ? Theme.onGlassGold : Theme.onGlass)
                    .lineLimit(1)
                    .fixedSize()
                if unit.isMaxLevel {
                    Text("MAX")
                        .font(Theme.numeric(15))
                        .foregroundStyle(Theme.onGlassGold)
                        .lineLimit(1)
                        .fixedSize()
                } else if gained > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Theme.onGlassDim)
                    Text(reached.isMaxLevel ? "Lv.\(reached.level) MAX" : "Lv.\(reached.level)")
                        .font(Theme.numeric(18))
                        .foregroundStyle(Theme.onGlassGold)
                        .lineLimit(1)
                        .fixedSize()
                    // Not beside MAX, which says it already (and the line
                    // must hold "Lv.12 › Lv.50 MAX" and SKILL ×n in 296).
                    if !reached.isMaxLevel {
                        sealChip(levelsGained)
                    }
                }
                Spacer(minLength: 6)
                if duplicates > 0 {
                    sealChip("SKILL ×\(duplicates)")
                }
            }
            if unit.isMaxLevel {
                GlassMeter(value: 1, maximum: 1, tint: Theme.gold, height: 10)
            } else if gained > 0 {
                GlassMeter(
                    value: 0,
                    maximum: Double(reachedNeeded),
                    projected: Double(reachedInto),
                    reachesNext: reached.isMaxLevel,
                    tint: Self.experienceTint,
                    height: 10
                )
            } else {
                GlassMeter(
                    value: Double(unit.experience),
                    maximum: Double(needed),
                    projected: Double(unit.experience + experience),
                    tint: Self.experienceTint,
                    height: 10
                )
            }
            HStack(spacing: 6) {
                Text(line)
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(Theme.onGlassDim)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 6)
                if wasted > 0 {
                    Text("\(wasted.formatted()) wasted")
                        .font(Theme.numeric(11.5))
                        .foregroundStyle(Theme.onGlassDanger)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
    }

    /// A small gold seal on the gauge's line: "+1 LV", the levels the
    /// offering reaches, and "SKILL ×2", the skill-ups it carries.
    private func sealChip(_ text: String) -> some View {
        Text(text)
            .font(Theme.body(11).weight(.black))
            .tracking(0.6)
            .foregroundStyle(Color(hex: "#FFF1C2"))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(Capsule().fill(Theme.goldDeep))
            .overlay(Capsule().strokeBorder(Theme.onGlassGold, lineWidth: 1))
    }

    /// The experience from where the unit stands to its level cap: what an
    /// offering can use before the rest is wasted.
    private func experienceToCap(_ unit: Unit) -> Int {
        let cap = ProgressionService.maxLevel(stars: unit.stars)
        guard unit.level < cap else { return 0 }
        var total = 0
        for level in unit.level..<cap {
            total += ProgressionService.experienceForNextLevel(level: level, stars: unit.stars)
        }
        return max(0, total - unit.experience)
    }

    /// Auto, the genre's auto-select: the cheap units offered for the unit on
    /// the altar, stopping at its level cap. Nothing to offer is a warning
    /// tap, not a silent button.
    private func offerAutomatically(to target: ResolvedUnit) {
        let picked = OfferingRule.pick(for: target.unit, from: store.player.units, keep: keptIDs)
        if picked.isEmpty {
            Juice.notify(.warning)
        } else {
            fodder = Set(picked)
        }
    }

    private func commitPowerUp(_ target: ResolvedUnit, feeding chosen: [ResolvedUnit]) {
        let before = target.unit
        store.levelUp(target.id, feeding: chosen.map(\.id))
        fodder = []
        guard let after = store.resolved(target.id)?.unit else { return }
        var parts: [String] = []
        if after.level > before.level { parts.append("Lv.\(before.level) → Lv.\(after.level)") }
        let skillUps = zip(after.skillLevels, before.skillLevels).filter { $0 > $1 }.count
        if skillUps > 0 { parts.append("skill-up ×\(skillUps)") }
        // A duplicate fed past the skill cap raises the family's regalia.
        let regaliaBefore = before.regaliaLevel ?? 1
        let regaliaAfter = after.regaliaLevel ?? 1
        let regaliaRose = regaliaAfter > regaliaBefore
        if regaliaRose { parts.append("regalia → \(Regalia.numeral(regaliaAfter))") }
        if parts.isEmpty {
            outcome = after.level == before.level ? "Experience banked" : "Powered up"
        } else {
            outcome = "Powered up: " + parts.joined(separator: ", ")
        }
        Juice.notify(.success)
        AudioLibrary.shared.play(.uiConfirm)
        // The rite: the fed units fly into the figure and it flares; the
        // words land as the orbs do.
        play(.feed(count: chosen.count), tint: target.blueprint.element.accentHex)
        let regaliaName = RegaliaService.regalia(forBlueprint: target.blueprint.id, level: regaliaAfter)?.name ?? "Regalia"
        // The words, one plain branch at a time: as two nested ternaries
        // of interpolated strings, with the delay's sum inside the call,
        // this took the type checker most of a second on CI (run 229).
        let levelled = after.level > before.level
        let title: String
        let detail: String
        if levelled {
            title = "LEVEL UP!"
            let skills: String = skillUps > 0 ? "  ·  skill-up ×\(skillUps)" : ""
            detail = "Lv.\(before.level) → Lv.\(after.level)" + skills
        } else if skillUps > 0 {
            title = "SKILL UP!"
            detail = "skill-up ×\(skillUps)"
        } else if regaliaRose {
            title = "REGALIA \(Regalia.numeral(regaliaAfter))"
            detail = "\(regaliaName) → \(Regalia.numeral(regaliaAfter))"
        } else {
            title = "POWERED UP"
            let gained: Int = after.experience - before.experience
            detail = "+\(gained) experience"
        }
        let offered: Double = Double(min(12, chosen.count))
        let delay: Double = 0.55 + 0.06 * offered
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            show(title, detail)
        }
    }

    /// The units that can be offered, as faces five across. A tap toggles
    /// one, up to `limit`; a chosen face is veiled with a gold check and
    /// ringed, a copy of the family wears ↑ in Power up (a skill-up or the
    /// regalia), and a unit worth keeping wears its reason on the face's
    /// left edge before a tap can eat it (`Keepsake`).
    ///
    /// Each face rests like a row of the cream lists (`restingRow()`): one
    /// showing a third of itself or less is not drawn. The ledger's third
    /// row stood under the second as a six-pixel sliver of a card's rim
    /// over the cost well (run 224, 3-training-feed), the fault this round
    /// took off Missions, Lessons and the decor catalogue; the ledger's
    /// chevron says the offering goes on.
    private func offeringGrid(
        _ candidates: [ResolvedUnit],
        target: ResolvedUnit,
        limit: Int,
        marksKin: Bool,
        kept: Set<UUID>
    ) -> some View {
        LazyVGrid(columns: offeringColumns, alignment: .leading, spacing: 8) {
            ForEach(candidates) { candidate in
                offeringTile(
                    candidate,
                    target: target,
                    limit: limit,
                    marksKin: marksKin,
                    worth: keepsake(candidate, kept: kept)
                )
                .restingRow()
            }
        }
    }

    private func offeringTile(
        _ candidate: ResolvedUnit,
        target: ResolvedUnit,
        limit: Int,
        marksKin: Bool,
        worth: Keepsake?
    ) -> some View {
        let chosen = fodder.contains(candidate.id)
        let kin = marksKin && RegaliaService.isSameFamily(candidate.unit, as: target.unit)
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return Button {
            if fodder.contains(candidate.id) {
                fodder.remove(candidate.id)
            } else if fodder.count < limit {
                fodder.insert(candidate.id)
                Juice.haptic(.light)
            } else {
                Juice.notify(.warning)
            }
        } label: {
            UnitPortraitTile(unit: candidate, size: 52)
                .overlay {
                    if chosen {
                        ZStack {
                            shape.fill(Color.black.opacity(0.45))
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20, weight: .black))
                                .foregroundStyle(Theme.onGlassGold)
                                .shadow(color: .black.opacity(0.8), radius: 2)
                            shape.strokeBorder(Theme.onGlassGold, lineWidth: 2)
                        }
                    }
                }
                // Both marks sit on the face's side edges at mid-height,
                // hanging 3 points off (the grid's 7-point gap holds the two
                // of neighbouring tiles without a touch): clear of the
                // element and the level along the top, which end 17 points
                // down on this 52-point face, and of the star row along the
                // foot, which starts about 42 down. On the bottom corners
                // the keepsake hid the FIRST star of every marked tile and
                // the kin arrow the last (run 217: Perseus 4★ read as 3★).
                .overlay(alignment: .trailing) {
                    if kin {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(Theme.onGlassGold)
                            .background(Circle().fill(Color.black.opacity(0.75)))
                            .offset(x: 3)
                    }
                }
                .overlay(alignment: .leading) {
                    if let worth {
                        keepsakeMark(worth)
                            .offset(x: -3)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(worth?.phrase ?? "")
    }

    /// Why an offered unit is worth keeping: on a saved team, wearing relics
    /// or a boon, or awakened. Run 216's grid led with the player's best 5★
    /// and marked nothing, so one mis-tap ate a team's unit.
    private enum Keepsake {
        case team, relics, awakened

        var glyph: String {
            switch self {
            case .team: return "shield.fill"
            case .relics: return "diamond.fill"
            case .awakened: return "sun.max.fill"
            }
        }

        var phrase: String {
            switch self {
            case .team: return "on a team"
            case .relics: return "wears relics"
            case .awakened: return "awakened"
            }
        }
    }

    private func keepsake(_ unit: ResolvedUnit, kept: Set<UUID>) -> Keepsake? {
        if kept.contains(unit.id) { return .team }
        if !unit.unit.equippedRelics.isEmpty || unit.unit.boonID != nil { return .relics }
        if unit.unit.isAwakened { return .awakened }
        return nil
    }

    /// A kept unit's mark: a 16-point dark disc on the face's lower left with
    /// the reason's glyph in the eyebrow gold.
    private func keepsakeMark(_ worth: Keepsake) -> some View {
        ZStack {
            Circle().fill(Color(hex: "#17120E").opacity(0.92))
            Circle().strokeBorder(Theme.onGlassEyebrow.opacity(0.85), lineWidth: 1)
            Image(systemName: worth.glyph)
                .font(.system(size: 8.5, weight: .black))
                .foregroundStyle(Theme.onGlassEyebrow)
        }
        .frame(width: 16, height: 16)
        .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
        .allowsHitTesting(false)
    }

    /// The genre's material order, cheapest first, so the thumb lands on
    /// fodder: the units worth keeping last, then the grade, the level and
    /// the power, lowest first. The grid was the rail's order, strongest
    /// first, which put the player's best 5★ under the first tap (run 216).
    private func cheapestFirst(_ candidates: [ResolvedUnit], kept: Set<UUID>) -> [ResolvedUnit] {
        candidates.sorted { lhs, rhs in
            let lhsKept = keepsake(lhs, kept: kept) != nil
            let rhsKept = keepsake(rhs, kept: kept) != nil
            if lhsKept != rhsKept { return rhsKept }
            if lhs.stars != rhs.stars { return lhs.stars < rhs.stars }
            if lhs.level != rhs.level { return lhs.level < rhs.level }
            return lhs.power < rhs.power
        }
    }

    /// Commits at once when the offering eats nothing worth keeping, and
    /// otherwise asks first, naming what would go and why — Summoners War's
    /// "a 4★+ monster is included" prompt. `gradeCounts` is Power up's: a 4★
    /// or better fed for experience is worth the question; Evolve takes its
    /// own grade by rule, so there only a kept unit asks.
    private func askBeforeOffering(
        _ chosen: [ResolvedUnit],
        gradeCounts: Bool,
        kept: Set<UUID>,
        commit: @escaping () -> Void
    ) {
        var lines: [String] = []
        for unit in chosen {
            var reasons: [String] = []
            if let worth = keepsake(unit, kept: kept) { reasons.append(worth.phrase) }
            let precious = gradeCounts && unit.stars >= 4
            if reasons.isEmpty && !precious { continue }
            reasons.insert("\(unit.stars)★", at: 0)
            let name = personalName(unit.name)
            let why = reasons.joined(separator: ", ")
            lines.append("\(name) (\(why))")
        }
        guard !lines.isEmpty else {
            commit()
            return
        }
        let shown = lines.prefix(3).joined(separator: "\n")
        let more = lines.count > 3 ? "\nand \(lines.count - 3) more" : ""
        let title = lines.count == 1 ? "Offer a unit worth keeping?" : "Offer \(lines.count) units worth keeping?"
        warning = OfferingWarning(
            title: title,
            message: shown + more + "\n\nOffered units are consumed; their relics come back to the inventory.",
            commit: commit
        )
        Juice.notify(.warning)
    }

    // MARK: - Evolve

    @ViewBuilder
    private func evolveLedger(_ target: ResolvedUnit) -> some View {
        let required = ProgressionService.evolutionFodderRequired(currentStars: target.stars)
        let cost = ProgressionService.drachmaCostToEvolve(currentStars: target.stars)
        let kept = keptIDs
        let candidates = cheapestFirst(
            units.filter { $0.id != target.id && !$0.unit.isLocked && $0.stars == target.stars },
            kept: kept
        )
        let chosen = candidates.filter { fodder.contains($0.id) }
        let affordable = store.player.wallet.drachma >= cost
        let ready = target.unit.canEvolve && chosen.count == required && affordable
        let filled = "\(chosen.count) / \(required)"
        let yours = "Your \(target.stars)★"

        if target.stars >= 6 {
            quietLedger(
                icon: "star.circle.fill",
                title: "Fully evolved",
                message: "\(personalName(target.name)) is 6★, the top of the ladder."
            )
        } else {
            HallLedger {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        GlassSectionHeader(
                            title: "Evolution",
                            accessory: filled,
                            accessoryTint: chosen.count == required ? Theme.onGlassSuccess : Theme.onGlassDim
                        )
                        InfoDot(title: "Evolution") {
                            infoText("Evolving resets the level to 1 and raises every stat. It takes the unit at its level cap and \(required) unlocked units at exactly \(target.stars)★, which are consumed.")
                        }
                    }
                    evolutionLadder(target)
                    evolveSockets(chosen, required: required, stars: target.stars)
                }
            } content: {
                if candidates.isEmpty {
                    EmptyState(
                        icon: "tray",
                        title: "No \(target.stars)★ to offer",
                        message: "Evolution takes unlocked units at exactly \(target.stars)★.",
                        onGlass: true
                    )
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        GlassSectionHeader(title: yours)
                        offeringGrid(candidates, target: target, limit: required, marksKin: false, kept: kept)
                    }
                }
            } foot: {
                HStack(spacing: 8) {
                    CostWell(key: "drachma", amount: cost, affordable: affordable, height: PrimaryButton.height)
                    ledgerButton("Evolve", systemImage: "star.circle.fill", isEnabled: ready) {
                        askBeforeOffering(chosen, gradeCounts: false, kept: kept) {
                            commitEvolution(target, feeding: chosen)
                        }
                    }
                }
            }
        }
    }

    /// The cheapest units of the target's grade that nothing keeps, exactly
    /// as many as its evolution eats — or none when there are not enough.
    private func evolutionOffering(for target: ResolvedUnit) -> [ResolvedUnit] {
        let kept = keptIDs
        let required = ProgressionService.evolutionFodderRequired(currentStars: target.stars)
        let pool = cheapestFirst(
            units.filter { $0.id != target.id && !$0.unit.isLocked && $0.stars == target.stars },
            kept: kept
        )
        .filter { keepsake($0, kept: kept) == nil }
        return pool.count >= required ? Array(pool.prefix(required)) : []
    }

    private func commitEvolution(_ target: ResolvedUnit, feeding chosen: [ResolvedUnit]) {
        store.evolve(target.id, fodderIDs: chosen.map(\.id))
        fodder = []
        if let after = store.resolved(target.id), after.stars > target.stars {
            outcome = "\(after.name) evolved to \(after.stars)★"
            Juice.notify(.success)
            AudioLibrary.shared.play(.summonBurst, volume: 0.8)
            play(.evolve, tint: target.blueprint.element.accentHex)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                show("EVOLVED", String(repeating: "★", count: after.stars))
            }
        }
    }

    /// The grade now, the grade next (lit), and the level requirement with a
    /// tick or a cross — in one line that fits the ledger's 296 points. Two
    /// star rows at 13 made it about 330, and the plate grew with it and hung
    /// off the painting (run 216); the grades are numerals with one star.
    private func evolutionLadder(_ target: ResolvedUnit) -> some View {
        let atCap = target.unit.isMaxLevel
        let level = atCap ? "Lv.\(target.level) MAX" : "Lv.\(target.level) / \(target.unit.maxLevel)"
        return HStack(spacing: 8) {
            gradeMark(target.stars, lit: false)
            Image(systemName: "chevron.right.2")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(Theme.onGlassDim)
            gradeMark(target.stars + 1, lit: true)
            Spacer(minLength: 6)
            Image(systemName: atCap ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(atCap ? Theme.onGlassSuccess : Theme.onGlassDanger)
            Text(level)
                .font(Theme.numeric(12))
                .foregroundStyle(atCap ? Theme.onGlassSuccess : Theme.onGlassDanger)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// A grade as a numeral and one star: "5★", the next one larger and lit.
    private func gradeMark(_ stars: Int, lit: Bool) -> some View {
        let count = "\(stars)"
        return HStack(spacing: 2) {
            Text(count)
                .font(Theme.numeric(lit ? 18 : 16))
                .foregroundStyle(lit ? Theme.onGlassGold : Theme.onGlass)
                .lineLimit(1)
                .fixedSize()
            StarRow(stars: 1, size: lit ? 14 : 12)
        }
        .shadow(color: lit ? Theme.gold.opacity(0.6) : .clear, radius: 5)
    }

    /// The evolution's price in faces: `required` sockets, the chosen units
    /// filling them from the left — a tap on one gives it back — and the rest
    /// empty wells marked with the grade they want. The genre's evolve
    /// layout; run 216's ledger had one face over 190 points of empty glass
    /// and the count as a small grey "0 / 5".
    private func evolveSockets(_ chosen: [ResolvedUnit], required: Int, stars: Int) -> some View {
        let want = "\(stars)★"
        return HStack(spacing: 7) {
            ForEach(Array(0..<max(1, required)), id: \.self) { index in
                socket(index < chosen.count ? chosen[index] : nil, want: want)
            }
        }
    }

    @ViewBuilder
    private func socket(_ unit: ResolvedUnit?, want: String) -> some View {
        if let unit {
            Button {
                Juice.haptic(.light)
                AudioLibrary.shared.play(.uiTap)
                fodder.remove(unit.id)
            } label: {
                UnitPortraitTile(unit: unit, size: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Theme.onGlassGold, lineWidth: 1.5)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            EmptyUnitSlot(size: 52)
                .overlay(alignment: .bottom) {
                    Text(want)
                        .font(Theme.numeric(11.5))
                        .foregroundStyle(Theme.onGlassDim)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.bottom, 2)
                }
                .allowsHitTesting(false)
        }
    }

    // MARK: - Awaken

    @ViewBuilder
    private func awakenLedger(_ target: ResolvedUnit) -> some View {
        if let awakening = target.blueprint.awakening {
            // The element's own essences first, then Magic; low to high
            // inside each — the order the Halls pay them in.
            let costs = awakening.essenceCost.sorted { essenceOrder($0.key) < essenceOrder($1.key) }
            let ready = costs.allSatisfy { (store.player.essences[$0.key] ?? 0) >= $0.value }
            let awakenedTitle = personalName(awakening.awakenedName).uppercased()
            let awakenedEpithet = epithetPart(awakening.awakenedName)?.uppercased()
            HallLedger {
                EmptyView()
            } content: {
                VStack(alignment: .leading, spacing: 8) {
                    // The whole awakened name, carved, never cut: the name
                    // and its epithet as two titles, each light gold on
                    // every line. One carved block over two lines ran one
                    // gradient down both and left the second in dark bronze
                    // (run 216: "SEKHMET, BRINGER OF THE" over "SEVEN ARROWS").
                    VStack(alignment: .leading, spacing: 2) {
                        Text(awakenedTitle)
                            .font(Theme.title(18))
                            .tracking(1.0)
                            .carved(glow: false, multiline: true)
                            .fixedSize(horizontal: false, vertical: true)
                        if let awakenedEpithet {
                            Text(awakenedEpithet)
                                .font(Theme.title(13))
                                .tracking(1.2)
                                .carved(glow: false, multiline: true)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if target.unit.isAwakened {
                        Text("AWAKENED")
                            .font(Theme.body(11).weight(.black))
                            .tracking(0.8)
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .frame(height: 20)
                            .background(Capsule().fill(Theme.goldPlate))
                    }
                    Text(awakening.bonusDescription)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.onGlassDim)
                        .fixedSize(horizontal: false, vertical: true)
                    if !target.unit.isAwakened {
                        HStack(spacing: 6) {
                            GlassSectionHeader(title: "Essences")
                            InfoDot(title: "Essences") {
                                // Where each line of the bill comes from, read
                                // the way the tables actually pay: the
                                // element's essence from its Hall in the
                                // Labyrinth (and its Titan), Magic from the
                                // campaign's stages.
                                infoText("The element's essence drops in its Hall of Essence, in the Labyrinth; Magic essence in the campaign.")
                            }
                        }
                        LazyVGrid(columns: essenceColumns, alignment: .leading, spacing: 8) {
                            ForEach(costs.indices, id: \.self) { index in
                                RequirementTile(
                                    key: costs[index].key,
                                    have: store.player.essences[costs[index].key] ?? 0,
                                    need: costs[index].value,
                                    caption: EssenceCatalog.name(for: costs[index].key)
                                        .replacingOccurrences(of: " Essence", with: ""),
                                    size: 56
                                )
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            } foot: {
                if !target.unit.isAwakened {
                    ledgerButton("Awaken", systemImage: "sun.max.fill", isEnabled: ready) {
                        store.awaken(target.id)
                        if let after = store.resolved(target.id), after.unit.isAwakened {
                            outcome = "\(after.name) awakened"
                            Juice.notify(.success)
                            AudioLibrary.shared.play(.summonBurst, volume: 0.9)
                            // The altar's pillar first; the reveal of the
                            // new form follows it up.
                            play(.awaken, tint: target.blueprint.element.accentHex)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                                reveal = SummonResult(
                                    unit: after.unit,
                                    blueprint: after.blueprint,
                                    stars: after.stars,
                                    isNew: false,
                                    isFeatured: false,
                                    fromPity: false,
                                    isAwakening: true
                                )
                            }
                        }
                    }
                }
            }
        } else {
            quietLedger(
                icon: "sun.max",
                title: "No awakened form",
                message: "\(personalName(target.name)) has no awakening; power up and evolve instead."
            )
        }
    }

    /// An essence's place in the bill: the element's before Magic, then low,
    /// mid, high.
    private func essenceOrder(_ key: String) -> Int {
        let tier = key.hasSuffix("_low") ? 0 : (key.hasSuffix("_mid") ? 1 : 2)
        return key.contains("_magic_") ? 10 + tier : tier
    }

    // MARK: - Fusion

    /// One hexagram as a ledger: its name with the lore behind the ? (the
    /// panel cut the lore at two lines with an ellipsis), the prize's epithet,
    /// the four corners as faces with their grade, level and state, the one
    /// thing that is short, and the price beside the Fuse button. The six
    /// were a sideways row of 268-point cream panels that hid the painting;
    /// the prize now stands on the altar and the six are the rail.
    private func fusionLedger(_ plan: FusionService.Plan) -> some View {
        let recipe = plan.recipe
        // "Prize · Sekhmet of the Red Nile": a blueprint's epithet is written
        // to follow its name, and alone under the title it read as a broken
        // string ("of the Red Nile", run 216).
        let prize: String? = recipe.result.map { "Prize · \(personalName($0.name)) \($0.epithet)" }
        let blocker = fusionBlocker(plan)
        return HallLedger {
            HStack(spacing: 6) {
                GlassSectionHeader(title: recipe.name)
                InfoDot(title: recipe.name) {
                    VStack(alignment: .leading, spacing: 8) {
                        infoText(recipe.lore)
                        infoText("Four corners at the grade and level shown, and \(recipe.drachmaCost.formatted()) drachma. Locked units and units on a team are never eaten.")
                    }
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                if let prize {
                    Text(prize)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.onGlassDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LazyVGrid(columns: cornerColumns, alignment: .leading, spacing: 8) {
                    ForEach(plan.slots) { slot in
                        cornerTile(slot)
                    }
                }
                Text(blocker ?? "Every corner is ready.")
                    .font(Theme.body(12))
                    .foregroundStyle(plan.canFuse ? Theme.onGlassSuccess : Theme.onGlassDanger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } foot: {
            HStack(spacing: 8) {
                CostWell(key: "drachma", amount: recipe.drachmaCost, affordable: plan.costMet, height: PrimaryButton.height)
                // `store.fuse(_:)` is the wiring: it calls
                // `FusionService.fuse(_:player:)` and hands back the new unit.
                ledgerButton("Fuse", systemImage: "hexagon.fill", isEnabled: plan.canFuse) {
                    commitFusion(plan)
                }
            }
        }
    }

    /// One corner: the character wanted in a dark socket in its grade's metal,
    /// then its name, the grade and level it must be at, and either Ready or
    /// the one thing that is short — every line at the type floor with no
    /// shrinking (the panel's were 9 points shrunk to 7.7).
    ///
    /// A corner the player cannot fill is drawn grey and half faded, so the
    /// ledger reads at a glance — colour means owned — before any of the words
    /// under it are read.
    private func cornerTile(_ slot: FusionService.Slot) -> some View {
        let blueprint = slot.ingredient.blueprint
        let met = slot.isMet
        let shape = RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)

        return VStack(spacing: 3) {
            ZStack {
                shape.fill(Theme.socketFill)
                if let blueprint, BundleImage.exists(blueprint.model.portraitName) {
                    BundleImage(name: blueprint.model.portraitName, renderedAt: 56)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 56, height: 56)
                        .saturation(met ? 1 : 0.15)
                        .opacity(met ? 1 : 0.6)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(shape)
            .rarityFrame(Rarity(stars: slot.ingredient.stars), painted: false)
            .overlay(alignment: .topTrailing) {
                Image(systemName: met ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(met ? Theme.onGlassSuccess : Theme.onGlassDanger)
                    .background(Circle().fill(Color.black).padding(1))
                    .offset(x: 4, y: -4)
            }
            .overlay(alignment: .bottomLeading) {
                if let blueprint {
                    // Which of the five is wanted. Two Shabti of different
                    // elements are two different corners and one of them will
                    // not do for the other.
                    ElementBadge(element: blueprint.element, compact: true, scale: 0.72)
                        .padding(3)
                }
            }

            // Two lines' room for every name, filled or not, so the grade
            // and the state lines of the four corners share one baseline.
            // The name is laid out at its own height first and the box is
            // 32: two lines of Manrope 11 are 30.05 points, and the 30-point
            // box of run 217 laid out one line and cut "Jackal Warr…".
            Text(personalName(blueprint?.name ?? slot.ingredient.blueprintID))
                .font(Theme.body(11).weight(.semibold))
                .foregroundStyle(Theme.onGlass)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 68, height: 32, alignment: .top)
            Text(slot.ingredient.requirement)
                .font(Theme.numeric(11.5))
                .foregroundStyle(Theme.onGlassDim)
                .lineLimit(1)
                .fixedSize()
            Text(met ? "Ready" : shortfallWords(slot))
                .font(Theme.body(11))
                .foregroundStyle(met ? Theme.onGlassSuccess : Theme.onGlassDanger)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: 68)
        .accessibilityElement(children: .combine)
    }

    /// What a corner is short of, in words a player reads at once under the
    /// "4★ Lv.30" it asks for: "Not owned", "Only 3★", "Only Lv.12",
    /// "Locked" or "On a team". `Shortfall.short` is "none" and "reserved",
    /// which read as debug strings (run 216). A reserved corner says which
    /// of the two holds it back: locked if any copy is locked, else a team.
    private func shortfallWords(_ slot: FusionService.Slot) -> String {
        guard let shortfall = slot.shortfall else { return "Not ready" }
        switch shortfall {
        case .notOwned:
            return "Not owned"
        case .grade(let have, _):
            return "Only \(have)★"
        case .level(let have, _):
            return "Only Lv.\(have)"
        case .reserved:
            let copies = store.player.units.filter { $0.blueprintID == slot.ingredient.blueprintID }
            return copies.contains { $0.isLocked } ? "Locked" : "On a team"
        }
    }

    /// The line under the corners when the hexagram cannot be fused: the
    /// plan's own, with the price grouped ("Needs 40,000 drachma").
    private func fusionBlocker(_ plan: FusionService.Plan) -> String? {
        if plan.missing.isEmpty && !plan.costMet {
            let price = plan.recipe.drachmaCost.formatted()
            return "Needs \(price) drachma"
        }
        return plan.blocker
    }

    private func commitFusion(_ plan: FusionService.Plan) {
        // Read before the fusion runs: the codex has the id in it the moment
        // the unit exists, and the reveal wants to know it was the first.
        let isNew = !store.player.codex.contains(plan.recipe.resultID)
        guard let created = store.fuse(plan.recipe) else { return }
        Juice.notify(.success)
        AudioLibrary.shared.play(.uiConfirm)
        reveal = SummonResult(
            unit: created.unit,
            blueprint: created.blueprint,
            stars: created.stars,
            isNew: isNew,
            isFeatured: false,
            fromPity: false
        )
    }
}

// MARK: - The ledger's shape

/// The coordinate space a `HallLedger` measures its body in.
private let hallLedgerSpace = "hallLedger"

/// One glass ledger of the Hall of Ka: a fixed header, a body that scrolls
/// and fades at its foot, and a fixed foot for the price and the button, on
/// one `GlassPlate` the height of its column.
///
/// Only the body is flexible. That is the whole point (2026-09-22): frame 43's
/// Awaken panel stacked about 330 points of fixed content in a 311-point
/// column, and an oversized child pushed `GameScreen`'s stack up until the
/// strip's title was cut in half at the top of the phone. Here the header and
/// the foot keep their size, the body takes what is left and scrolls, and the
/// button is always on the plate's bottom edge.
private struct HallLedger<Header: View, Content: View, Foot: View>: View {
    let header: () -> Header
    let content: () -> Content
    let foot: () -> Foot

    /// The body's frame in its scroll's own space and the scroll's height:
    /// whether a row stands below the fold.
    @State private var bodyFrame: CGRect = .zero
    @State private var viewportHeight: CGFloat = 0

    /// The room under the body's last row, which scrolls it clear of the
    /// fade: not a row, so it never calls the chevron up by itself.
    private static var footRoom: CGFloat { 16 }

    init(
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder foot: @escaping () -> Foot
    ) {
        self.header = header
        self.content = content
        self.foot = foot
    }

    /// A row of the body is below the fold. The offering's faces rest on
    /// whole rows (`restingRow()`), so a row cut at the foot is not drawn
    /// and nothing else would say the offering goes on.
    private var moreBelow: Bool {
        bodyFrame.height > viewportHeight + 1 && bodyFrame.maxY - Self.footRoom > viewportHeight + 2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header()
            ScrollView(showsIndicators: false) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The plate's 12 points INSIDE the scroll view, which
                    // spans the plate's full width (the -12 below): a face's
                    // rarity glow reaches about 8 points past the face, and
                    // with the body inset round the scroll view its clip cut
                    // every halo of the first row and the left column on a
                    // ruled line (run 216). 8 over the first row for the same.
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    // Room under the last row to scroll it clear of the fade.
                    .padding(.bottom, Self.footRoom)
                    .background(
                        GeometryReader { proxy in
                            let frame = proxy.frame(in: .named(hallLedgerSpace))
                            Color.clear
                                .onAppear { bodyFrame = frame }
                                .onChange(of: frame) { _, now in bodyFrame = now }
                        }
                    )
            }
            .coordinateSpace(name: hallLedgerSpace)
            .background(
                GeometryReader { proxy in
                    let height = proxy.size.height
                    Color.clear
                        .onAppear { viewportHeight = height }
                        .onChange(of: height) { _, now in viewportHeight = now }
                }
            )
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.04),
                        .init(color: .black, location: 0.9),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // The cream lists' cue (`RestingList`) in the glass's own
            // colours, over the fade rather than under its mask: while a
            // row is below the fold, a small chevron at the body's foot.
            .overlay(alignment: .bottom) {
                if moreBelow {
                    Image(systemName: "chevron.compact.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.onGlassGold)
                        .frame(width: 30, height: 12)
                        .background(Capsule().fill(Color.black.opacity(0.6)))
                        .overlay(Capsule().strokeBorder(Theme.glassRim, lineWidth: 0.8))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, -12)
            .frame(maxHeight: .infinity)
            foot()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        // The width it is GIVEN, whatever a child asks for: with no minimum
        // a flexible frame takes the larger of the offer and its child, so
        // run 216's 330-point Evolve ladder grew the plate 35 points past
        // the Power up plate's and off the painting. A child too wide now
        // overflows its own line, where a frame shows it, and the plate —
        // the thing the eye measures between tabs — never moves.
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .top)
        .background(GlassPlate(radius: 14))
    }
}

// MARK: - Auto

/// The Hall's Auto, the rule Summoners War's Auto Select follows: offer the
/// cheap units — 1★ to 3★, unlocked, unawakened, wearing no relic and no boon,
/// on no saved team — weakest first, and stop the moment the unit on the altar
/// would reach its level cap, so no unit is eaten for experience that would
/// be thrown away (the genre's over-cap warning, as a rule). At most `limit`,
/// the offering's twelve.
///
/// It only fills the selection; the player sees the faces veiled and presses
/// Power up as before, and `GameStore.levelUp` is the same call. A pure
/// function of the save, so it can move to `ProgressionService` with a test
/// when that file is next open (2026-09-22: this pass owned only this file).
private enum OfferingRule {
    static func pick(for target: Unit, from units: [Unit], keep: Set<UUID>, limit: Int = 12) -> [UUID] {
        let pool = units
            .filter { unit in
                unit.id != target.id
                    && !unit.isLocked
                    && !unit.isAwakened
                    && unit.equippedRelics.isEmpty
                    && unit.boonID == nil
                    && !keep.contains(unit.id)
                    && unit.stars <= 3
            }
            .sorted { lhs, rhs in
                lhs.stars != rhs.stars ? lhs.stars < rhs.stars : lhs.level < rhs.level
            }
        var trial = target
        var picked: [UUID] = []
        for unit in pool {
            guard picked.count < limit, !trial.isMaxLevel else { break }
            ProgressionService.grantExperience(ProgressionService.feedValue(of: unit), to: &trial)
            picked.append(unit.id)
        }
        return picked
    }
}

/// The question asked before an offering eats a unit worth keeping: its
/// title, the units and why each is worth keeping, and the commit it holds
/// back until the player says Offer.
private struct OfferingWarning {
    let title: String
    let message: String
    let commit: () -> Void
}

// MARK: - The altar

/// One rite on the altar, stamped so the stage plays each exactly once.
struct AltarCeremony {
    enum Kind {
        case feed(count: Int)
        case evolve
        case awaken
    }

    var stamp: Int
    var kind: Kind
    var tintHex: String
}

/// Where the altar's figure stands in a frame, in 0…1 of it: its centre
/// line `across`, its feet `down`, and its height `fill` of the frame's
/// height (`AltarStageView.placement(in:)`).
struct AltarPlacement {
    var across: CGFloat
    var down: CGFloat
    var fill: CGFloat
}

/// The words of a moment over the altar.
struct AltarStamp {
    var id: Int
    var title: String
    var detail: String
}

/// The chosen unit standing on the painted dais.
///
/// A transparent SceneKit view the size of the frame: the figure's real model
/// on a rune ring with a contact shadow, framed so its feet land on the
/// painting's altar — the island's trick of figures over a painting, done for
/// one, at the summon reveal's lens. The rites play here: the fed units fly
/// into the figure as orbs of its element and it flares; an evolution or an
/// awakening stands it in a pillar of its element's light.
///
/// It takes a BLUEPRINT and the form to show, not an owned unit, since
/// 2026-09-22: in Fuse the prize stands on the dais before the player owns
/// it, the way the summon reveal draws a figure that is not yet in the
/// roster.
struct AltarStageView: UIViewRepresentable {
    let blueprint: UnitBlueprint?
    /// The awakened form: its own mesh, its own clips, the aura. Part of the
    /// figure's key, so an awakening on the altar rebuilds the figure.
    let awakened: Bool
    let ceremony: AltarCeremony?

    /// Where the figure's feet stand on the painting, in 0…1 of the PAINTING
    /// (`hall_of_ka_bg`, 2048 × 1152): 29% across, 73.4% down — the front of
    /// the dais's top, where they have stood since the Hall became a place.
    /// It was written as 29% and 80% of a 750 × 329 FRAME until run 216; the
    /// stage bleeds to the glass now (874 × 350 on a 16 Pro), the cover crop
    /// changes with the frame's shape, and a number of the frame would have
    /// stood the figure 12 points off the painted stone. So the dais is
    /// measured on the painting and solved on whatever frame the stage gets
    /// (`placement(in:)`), the island's way (`tools/mapgrid.py` on the
    /// painting with a dot at 0.29, 0.734 is the check).
    static let daisInPainting = CGPoint(x: 0.29, y: 0.734)
    static let paintingSize = CGSize(width: 2048, height: 1152)
    /// The figure's height as a share of the painting's DRAWN height, so it
    /// keeps its size against the painted dais on any frame: 0.41 is the 54%
    /// of the old 329-point frame (a 422-point drawn painting) a breath
    /// smaller. On a 16 Pro the drawn painting is 492 tall, the figure about
    /// 202 and its head about 88 points down, under the nameplate's foot at 74.
    static let fillOfPainting: CGFloat = 0.41
    private static let lens: Float = 30

    /// Where the dais lands in a frame of `size` that draws the painting the
    /// way `PaintingFill` does — a centred cover crop — as fractions of that
    /// frame: the figure's centre line across, its feet down, and its height
    /// against the frame's height. Only the frame's SHAPE matters. Internal:
    /// the Awaken card beside the figure reads it to stand clear of it
    /// (`TrainingView.figureInColumn`).
    static func placement(in size: CGSize) -> AltarPlacement {
        guard size.width > 0, size.height > 0 else {
            return placement(in: CGSize(width: 874, height: 350))
        }
        let scale = max(size.width / paintingSize.width, size.height / paintingSize.height)
        let drawnWidth = paintingSize.width * scale
        let drawnHeight = paintingSize.height * scale
        let left = (drawnWidth - size.width) / 2
        let top = (drawnHeight - size.height) / 2
        return AltarPlacement(
            across: (daisInPainting.x * drawnWidth - left) / size.width,
            down: (daisInPainting.y * drawnHeight - top) / size.height,
            fill: fillOfPainting * drawnHeight / size.height
        )
    }

    final class Coordinator {
        var scene: SCNScene?
        var figure: SCNNode?
        var figureKey = ""
        var figureHeight: Float = 1.9
        var ring: SCNNode?
        var shadow: SCNNode?
        var cameraNode: SCNNode?
        var framedFor: Float = 0
        var playedStamp = 0
        let doctor = StageDoctor(label: "altar")
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        view.scene = scene
        // Transparent: the painting behind this view is the hall. Everything
        // added here either blends with a real alpha channel or adds light
        // and writes no alpha (the summon stage's rule).
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = false
        view.rendersContinuously = true
        // Playing from the first frame, whatever the scene holds at that
        // moment: the figure arrives a beat later when no unit was picked.
        view.isPlaying = true
        view.isUserInteractionEnabled = false
        let coordinator = context.coordinator
        coordinator.scene = scene
        view.delegate = coordinator.doctor
        coordinator.doctor.view = view

        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(Self.lens)
        camera.projectionDirection = .vertical
        camera.zNear = 0.5
        camera.zFar = 100
        camera.wantsHDR = true
        // THE SHOULDER (2026-09-17, evening): `whitePoint` at SceneKit's
        // default 1.0 clips every lit surface at or over 1.0 flat to paper —
        // the battle learned it on 2026-09-15 (BattleSceneController) and
        // this camera never got it, which is half of why the owner's awakened
        // Ares photographed as a pale smear on the reveal. Same number as the
        // battle's so the figure looks the same on every stage.
        camera.whitePoint = 1.85
        camera.wantsExposureAdaptation = false
        camera.bloomIntensity = 0.3
        camera.bloomThreshold = 0.93
        camera.bloomBlurRadius = 12
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        coordinator.cameraNode = cameraNode

        // Lit as the painting is: a warm key from the shaft of light above and
        // in front, a cool fill from the hall, a gold rim from behind, and an
        // ambient floor so the shadow side keeps its costume.
        // The rig's numbers, the studio environment and the figure's shadow are
        // `FigureStageLighting`, shared with the reveal (2026-09-18).
        let key = SCNLight()
        key.type = .directional
        key.intensity = FigureStageLighting.keyIntensity
        key.color = UIColor(hex: "#FFE8C2") ?? .white
        FigureStageLighting.castShadows(from: key)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-1.0, -0.3, 0)
        scene.rootNode.addChildNode(keyNode)
        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = FigureStageLighting.fillIntensity
        fill.color = UIColor(hex: "#7C93D6") ?? .white
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-0.4, 0.9, 0)
        scene.rootNode.addChildNode(fillNode)
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = FigureStageLighting.rimIntensity
        rim.color = UIColor(hex: "#FFD36A") ?? .yellow
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(-0.5, 2.7, 0)
        scene.rootNode.addChildNode(rimNode)
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = FigureStageLighting.ambientIntensity
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
        FigureStageLighting.applyEnvironment(to: scene)

        place(blueprint, awakened: awakened, in: coordinator)
        frameCamera(view, coordinator)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        place(blueprint, awakened: awakened, in: coordinator)
        frameCamera(view, coordinator)
        if let ceremony, ceremony.stamp != coordinator.playedStamp {
            coordinator.playedStamp = ceremony.stamp
            play(ceremony, coordinator)
        }
    }

    /// The figure for the blueprint, rebuilt only when the blueprint or its
    /// form changes.
    private func place(_ blueprint: UnitBlueprint?, awakened: Bool, in coordinator: Coordinator) {
        guard let scene = coordinator.scene else { return }
        let key = blueprint.map { "\($0.id)|\(awakened)" } ?? ""
        guard key != coordinator.figureKey else { return }
        coordinator.figureKey = key
        // An awakened figure carries a live aura: it leaves the way every
        // particle carrier does (`VFXLibrary.dismiss`: systems off, hidden
        // now, removed half a second of frames later), never freed with its
        // motes alive (2026-09-24).
        if let old = coordinator.figure { VFXLibrary.dismiss(old, reportsLive: false) }
        coordinator.ring?.removeFromParentNode()
        coordinator.shadow?.removeFromParentNode()
        coordinator.figure = nil
        guard let blueprint else { return }
        let height = blueprint.model.height
        let tint = UIColor(hex: blueprint.element.accentHex) ?? .white

        let node = ModelLibrary.shared.node(
            for: blueprint.model,
            archetype: blueprint.archetype,
            element: blueprint.element,
            awakened: awakened
        )
        if awakened {
            node.addParticleSystem(VFXLibrary.aura(tint: tint, scale: height / 1.9))
        }
        // A three-quarter stance, turned a little toward the panel.
        node.eulerAngles.y = -0.3
        node.opacity = 0
        scene.rootNode.addChildNode(node)
        // The idle AFTER the figure is in the scene, through a player told
        // to play (`SCNNode.startLoop`): added before, to a detached node
        // carried into this already-rendering scene, it never started and
        // the figure stood in its bind pose (2026-09-17).
        // The clips of the mesh on the stage (`ModelLibrary.clipAsset`): an
        // awakened figure plays its own rig's idle, never the base rig's.
        let assetName = ModelLibrary.shared.clipAsset(for: blueprint.model, awakened: awakened)
        if let idle = ModelLibrary.shared.animation(.idle, for: assetName)
            ?? ModelLibrary.shared.animation(.idleCombat, for: assetName) {
            node.startLoop(idle, key: "idle")
        }
        node.runAction(.fadeIn(duration: 0.35))
        // The figure is the scene's one shadow caster; the ring, the shadow
        // patch and the set never cast (2026-09-18).
        FigureStageLighting.restrictShadows(in: scene, to: node)
        coordinator.figure = node
        coordinator.doctor.figure = node
        coordinator.figureHeight = height

        let ring = StageBuilder.runeRing(radius: CGFloat(max(1.2, height * 0.7)), tint: tint)
        scene.rootNode.addChildNode(ring)
        coordinator.ring = ring

        let size = CGFloat(height) * 0.75
        let plane = SCNPlane(width: size, height: size)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = SummonStageView.contactShadowImage
        material.writesToDepthBuffer = false
        plane.firstMaterial = material
        let shadow = SCNNode(geometry: plane)
        shadow.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        shadow.position = SCNVector3(0, 0.012, 0)
        shadow.renderingOrder = 5
        shadow.opacity = 0.75
        scene.rootNode.addChildNode(shadow)
        coordinator.shadow = shadow
        // A new height is a new framing.
        coordinator.framedFor = 0
    }

    /// Places the camera so the figure's feet land on the painted dais.
    ///
    /// The vertical lens makes the frame's height a known quantity: the
    /// figure is `fill` of it, the feet sit `down` of the way down, and the
    /// camera is shifted — not turned — so the figure's centre line stands
    /// `across` of the way across, the reveal's rising front; all three are
    /// the painting's dais solved on this view's frame (`placement(in:)`),
    /// which is the painting's own frame. Solved again only when the
    /// viewport's shape or the figure changes.
    private func frameCamera(_ view: SCNView, _ coordinator: Coordinator) {
        guard let cameraNode = coordinator.cameraNode else { return }
        // The stage of a 16 Pro in landscape, bled to the glass, stands in
        // until the first real layout.
        let bounds = view.bounds.height > 0 ? view.bounds.size : CGSize(width: 874, height: 350)
        let aspect = Float(bounds.width / bounds.height)
        let framedFor = aspect * 1000 + coordinator.figureHeight
        guard abs(framedFor - coordinator.framedFor) > 0.01 else { return }
        coordinator.framedFor = framedFor

        let dais = Self.placement(in: bounds)
        let visible = coordinator.figureHeight / Float(dais.fill)
        let distance = visible / (2 * tan(Self.lens * .pi / 360))
        // The frame's centre is `down - 0.5` of a frame above the feet.
        let aimY = visible * (Float(dais.down) - 0.5)
        let halfWidth = visible * aspect / 2
        let x = halfWidth * (1 - 2 * Float(dais.across))
        // A little above the aim and looking down at it, the way the painting
        // looks down at its dais.
        cameraNode.position = SCNVector3(x, aimY + visible * 0.08, distance)
        cameraNode.look(at: SCNVector3(x, aimY, 0))
    }

    /// The rite.
    private func play(_ ceremony: AltarCeremony, _ coordinator: Coordinator) {
        guard let scene = coordinator.scene, let figure = coordinator.figure else { return }
        let tint = UIColor(hex: ceremony.tintHex) ?? .white
        let height = coordinator.figureHeight
        switch ceremony.kind {
        case .feed(let count):
            // The fed units, as orbs from the panel's side, into the chest
            // one after another; then the flare and the light from below.
            let orbs = min(12, max(1, count))
            let chest = SCNVector3(0, height * 0.55, 0)
            for index in 0..<orbs {
                let orb = SCNNode(geometry: SCNSphere(radius: 0.1))
                let material = SCNMaterial()
                material.lightingModel = .constant
                material.diffuse.contents = tint
                material.emission.contents = tint
                material.blendMode = .add
                material.writesToDepthBuffer = false
                // Adds light, so it writes no alpha: the transparent view's rule.
                material.colorBufferWriteMask = [.red, .green, .blue]
                orb.geometry?.firstMaterial = material
                let column = Float(index % 3)
                let row = Float(index / 3)
                orb.position = SCNVector3(2.6 + column * 0.55, 0.5 + row * 0.4, 0.3 - column * 0.3)
                orb.opacity = 0
                scene.rootNode.addChildNode(orb)
                let fly = SCNAction.move(to: chest, duration: 0.45)
                fly.timingMode = .easeIn
                orb.runAction(.sequence([
                    .wait(duration: 0.06 * Double(index)),
                    .fadeIn(duration: 0.12),
                    fly,
                    // Action blocks run on SceneKit's render thread: the
                    // burst is added from the main thread (run 239's rule
                    // for anything that carries particles).
                    .run { _ in
                        DispatchQueue.main.async { VFXLibrary.spawn("buff", at: chest, in: scene, tint: tint, scale: 0.5) }
                    },
                    .removeFromParentNode(),
                ]))
            }
            figure.runAction(.sequence([
                .wait(duration: 0.06 * Double(orbs) + 0.55),
                .run { node in
                    DispatchQueue.main.async {
                        Self.flare(node)
                        VFXLibrary.summonBeam(at: SCNVector3(0, 0, 0), in: scene, tint: tint)
                    }
                },
            ]))
        case .evolve, .awaken:
            let swell = SCNAction.sequence([.scale(by: 1.08, duration: 0.25), .scale(by: 1 / 1.08, duration: 0.4)])
            swell.timingMode = .easeInEaseOut
            figure.runAction(swell)
            Self.flare(figure)
            VFXLibrary.summonBeam(at: SCNVector3(0, 0, 0), in: scene, tint: tint)
            let effect: String
            if case .awaken = ceremony.kind { effect = "duat_rite" } else { effect = "olympian_decree" }
            VFXLibrary.spawn(effect, at: SCNVector3(0, height * 0.5, 0), in: scene, tint: tint, scale: 1.2)
        }
    }

    /// A flash of light through the figure: the battle's hit flash.
    private static func flare(_ node: SCNNode) {
        node.enumerateHierarchy { child, _ in
            for material in child.geometry?.materials ?? [] {
                let previous = material.emission.contents
                material.emission.contents = UIColor(white: 0.85, alpha: 1)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    material.emission.contents = previous
                }
            }
        }
    }
}
