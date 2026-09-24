import SwiftUI
import UIKit

// MARK: - The unit sheet as a PLACE (2026-09-24, Docs/PLAN.md *Relics the genre's way*)
//
// The owner, with Summoners War's monster sheet beside ours: "Look how easy it
// is to see everything, and to understand what's going on." Ours was three
// cream columns round a 120-point well: the figure a seventh of the width, the
// relics a ring of bare stones, the stats in 11-point figures on marble. The
// genre's sheet is a room with the monster standing in it and one dark panel
// of numbers beside it, and the builders' spec (§4.1) makes ours that room in
// our own materials: the Hall of Ka's sanctuary full-bleed with the unit's own
// figure on its painted dais (`AltarStageView`, the Hall's recipe exactly), a
// rail of faces down the left to page through the roster, five bronze tablets
// — INFO, SKILLS, RELICS, BOON, REGALIA — and one dark glass panel for the tab
// they name. The relics are a rosette of six sockets round the Boon
// (`RelicRosette`), the sets in two words each, and four plates with counts:
// MANAGE, BEST SIX, RELICS, STONES.
//
// Everything the old sheet did has a door here (spec §5): Power up, Evolve and
// Awaken open the Hall of Ka in that mode on this unit; the skills and their
// ladders are the SKILLS tab; a worn socket opens the relic's card and an
// empty one Manage on that slot; Auto-equip and Unequip all are Manage's (Best
// six ▾ → Fill empty slots, and All off), previewed before anything moves; the
// boon and the regalia have tabs of their own; the lore and the lock stay in
// the strip.

/// The fade at the foot of a panel body that scrolls (`SheetPanelScroll`),
/// and the room its last line keeps under it so it can scroll clear.
private let panelFade: CGFloat = 14

/// The coordinate space a `SheetPanelScroll` measures its content in.
private let sheetPanelSpace = "sheetPanelScroll"

/// A panel's body that scrolls INSIDE its panel — and says so only when it
/// has to.
///
/// The unit sheet is one frame: the panel is fixed and only what cannot fit
/// scrolls inside it; the things a player acts on (the skill icons) are
/// pinned outside the scroll. Run 216's judge: a panel that ended in a GHOST
/// ROW — the skill's last line fading mid-sentence — read as clipped, with
/// nothing to say it scrolled. So the body is measured: content that fits is
/// drawn whole, with no fade at all; content that does not fades at the foot
/// AND wears a small chevron there, which goes when the last line has been
/// scrolled into view. On the dark panel since 2026-09-24, so the chevron's
/// capsule is dark glass with the glass rim.
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
                    .foregroundStyle(Theme.onGlassEyebrow)
                    .frame(width: 30, height: 12)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .overlay(Capsule().strokeBorder(Theme.glassRim, lineWidth: 0.8))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - The tabs

/// The unit sheet's five tabs, in the order their tablets hang.
enum UnitSheetTab: String, CaseIterable {
    case info, skills, relics, boon, regalia

    /// The word carved on the tablet.
    var title: String {
        switch self {
        case .info: return "Info"
        case .skills: return "Skills"
        case .relics: return "Relics"
        case .boon: return "Boon"
        case .regalia: return "Regalia"
        }
    }
}

/// What the unit sheet presents over itself — one thing at a time, so the
/// altar knows when nothing covers it (`AltarStageView.playing`).
private enum UnitSheetCover: Identifiable, Equatable {
    /// The Hall of Ka in that mode, on this unit.
    case training(TrainingView.Mode)
    /// Manage, this unit's build.
    case manage
    /// Manage, filtered to one slot: an empty socket's door.
    case manageSlot(Int)
    /// Manage with THEN set to the optimiser's six for a goal.
    case bestSix(RelicService.OptimiserGoal)
    /// Manage with THEN set to what Auto-equip would put in the empty slots.
    case fillEmpty
    /// The bag: every relic, no unit.
    case bag
    /// One relic's card: a worn socket's door.
    case card(UUID)
    /// The set reference, counting this unit's pieces.
    case sets
    /// The boons, with this unit's socket.
    case boons
    /// The regalia's ladder.
    case regalia

    var id: String {
        switch self {
        case .training(let mode): return "training-\(mode.rawValue)"
        case .manage: return "manage"
        case .manageSlot(let slot): return "manage-slot-\(slot)"
        case .bestSix(let goal): return "best-six-\(goal.rawValue)"
        case .fillEmpty: return "fill-empty"
        case .bag: return "bag"
        case .card(let relicID): return "card-\(relicID.uuidString)"
        case .sets: return "sets"
        case .boons: return "boons"
        case .regalia: return "regalia"
        }
    }
}

/// A set with a piece on the unit, and how many pieces: one line of the
/// Relics tab's SET EFFECTS column.
private struct UnitSheetSetEntry: Identifiable {
    let relicSet: RelicSet
    let pieces: Int

    var id: String { relicSet.rawValue }
    /// Whole sets' worth of pieces worn.
    var completions: Int { pieces / max(1, relicSet.piecesRequired) }
}

// MARK: - The sheet

/// One unit in its own room, the genre's way (the builders' spec §4.1): the
/// Hall of Ka's painting full-bleed with the unit's figure on the painted dais,
/// a rail of faces down the left, the nameplate over the figure, five bronze
/// tablets, and the chosen tab on one dark glass panel.
///
/// `roster` is the order the rail pages through — the collection passes its
/// own filtered and sorted list; nil is every owned unit by power. The tab is
/// `openingTab` when one is given, else the last one the player chose
/// (`unitSheetTab`, never read or written under `-tour`), else INFO; the
/// tour, with no opening, shows RELICS.
struct UnitDetailView: View {
    let unitID: UUID
    let roster: [UUID]?
    let openingTab: UnitSheetTab?

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    /// The unit on the dais: `unitID` until a face on the rail is picked.
    @State private var shownID: UUID
    @State private var tab: UnitSheetTab
    /// What covers the sheet, one at a time; nil while the room is in view.
    @State private var presented: UnitSheetCover?
    @State private var showLore = false
    /// The card over the whole sheet, from the nameplate's thumbnail.
    @State private var showCard = false
    /// The six stones, as a popover off the STONES plate.
    @State private var showStones = false
    /// The skill whose words are shown, by its place in the kit — or
    /// `leaderSlot` for the leader skill's own tile.
    @State private var selectedSkill = 0
    /// The figure's turn, in points of drag: what earlier drags left it at,
    /// and the drag in progress (the collection Stage's pair).
    @State private var spinBase: CGFloat = 0
    @State private var spinDrag: CGFloat = 0
    /// Whether the figure stands on the dais yet: a beat after the sheet
    /// opens (`standFigure`).
    @State private var figureStands = false

    init(unitID: UUID, roster: [UUID]? = nil, openingTab: UnitSheetTab? = nil) {
        self.unitID = unitID
        self.roster = roster
        self.openingTab = openingTab
        _shownID = State(initialValue: unitID)
        _tab = State(initialValue: Self.startingTab(openingTab))
    }

    // MARK: Measures

    /// The rail of faces: a 54-point face on its 4-point row plate, and
    /// `PlaceRail`'s 9 a side — 80. The spec's 76 would cut the row plates by
    /// two points a side (`PlaceRail` pads 9 both ways), so the rail keeps its
    /// faces whole and the figure's column gives up the four points.
    private static let railWidth: CGFloat = 80
    private static let railFace: CGFloat = 54
    private static let tabletWidth: CGFloat = 80
    private static let tabletHeight: CGFloat = 50
    private static let tabletGap: CGFloat = 8
    /// Between the figure's column and the tablets, and the tablets and the
    /// panel.
    private static let gutter: CGFloat = 6
    /// The panel: 360 where the safe frame is at least 720 wide, 336 on a
    /// narrower one (an iPhone SE), and 12 of glass before the screen's edge.
    private static let panelWide: CGFloat = 360
    private static let panelNarrow: CGFloat = 336
    private static let trailingEdge: CGFloat = 12
    /// The nameplate over the figure: at most 184 wide, and 5 points clear of
    /// the column's edges.
    private static let nameplateWidest: CGFloat = 184
    /// The Relics tab's middle row: the rosette (R 28 and a 3-point gap:
    /// 151.5 × 146.4) beside the set effects — an 18-point header over three
    /// 40-point rows, 4 apart.
    private static let relicRowHeight: CGFloat = 150
    private static let rosetteColumn: CGFloat = 152
    /// The experience bar's fill: the Hall of Ka's own verdigris.
    private static let experienceTint = Color(hex: "#4FB3A0")
    /// A chosen skill's rim, the tile's selection gold.
    private static let chosenRim = Color(hex: "#FFE08A")
    /// The leader skill's place in `selectedSkill`: its tile stands after
    /// the kit's.
    private static let leaderSlot = -1

    // MARK: The remembered tab

    private static let tabKey = "unitSheetTab"

    private static var touring: Bool {
        ProcessInfo.processInfo.arguments.contains("-tour")
    }

    /// `openingTab`, else the tab the player last chose (never under the
    /// tour, whose relaunches would otherwise bleed into each other), else
    /// INFO; the tour with no opening shows RELICS.
    private static func startingTab(_ opening: UnitSheetTab?) -> UnitSheetTab {
        if let opening { return opening }
        if touring { return .relics }
        guard let stored = UserDefaults.standard.string(forKey: tabKey),
              let remembered = UnitSheetTab(rawValue: stored) else { return .info }
        return remembered
    }

    // MARK: Body

    var body: some View {
        let shown = store.resolved(shownID)
        let locked = shown?.unit.isLocked == true
        NavigationStack {
            // The short name and ONE epithet under it — the awakened name's
            // own when it has one — as every plate in the build prints a
            // unit; run 216 stacked "ANUBIS, KEEPER OF THE ASH ROAD" over
            // "of the Burning Sands".
            GameScreen(
                shown?.nameWithoutEpithet ?? "Unit",
                subtitle: shown?.epithetUnderName,
                dismiss: { dismiss() }
            ) {
                BarButton(title: "Lore", systemImage: "book.fill", tint: Theme.textSecondary, showsTitle: false) {
                    showLore = true
                }
                BarButton(
                    title: locked ? "Locked" : "Unlocked",
                    systemImage: locked ? "lock.fill" : "lock.open",
                    tint: locked ? Theme.gold : Theme.textSecondary,
                    showsTitle: false
                ) {
                    store.toggleLock(shownID)
                }
            } content: {
                sheetContent(shown)
            }
            .overlay {
                cardOverlay(shown)
            }
            .sheet(item: $presented) { cover in
                coverView(cover)
                    .environmentObject(store)
            }
            .alert(shown?.blueprint.epithet ?? "", isPresented: $showLore) {
                Button("Close", role: .cancel) {}
            } message: {
                Text(shown?.blueprint.lore ?? "")
            }
            .task {
                await standFigure()
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ shown: ResolvedUnit?) -> some View {
        if let shown {
            // The rail, the figure's column, the tablets and the panel in the
            // safe frame; the stage under them out to the glass. The reader
            // is how the nameplate knows where the stage put the figure.
            GeometryReader { geometry in
                sheetLayout(shown, geometry: geometry)
            }
            .background { altarStage(shown) }
        } else {
            EmptyState(icon: "questionmark", title: "Gone", message: "This unit is no longer in your collection.")
        }
    }

    private func sheetLayout(_ shown: ResolvedUnit, geometry: GeometryProxy) -> some View {
        let faces = railUnits(including: shown)
        let panelWidth: CGFloat = geometry.size.width >= 720 ? Self.panelWide : Self.panelNarrow
        let figureX = figureInColumn(geometry)
        return HStack(spacing: 0) {
            faceRail(faces)
            figureColumn(shown, figureX: figureX)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            tabletColumn(shown)
                .padding(.horizontal, Self.gutter)
            tabPanel(shown)
                .frame(width: panelWidth)
                .frame(maxHeight: .infinity)
        }
        .padding(.trailing, Self.trailingEdge)
        .padding(.vertical, 8)
    }

    /// Where the figure's centre line stands in the figure's column, in
    /// points from the column's leading edge. The stage is the whole glass,
    /// so the dais is solved on that frame — the safe frame widened by its
    /// side insets and lengthened by the home indicator — and brought back
    /// into the column's coordinates: the Hall of Ka's `figureInColumn`.
    private func figureInColumn(_ geometry: GeometryProxy) -> CGFloat {
        let insets = geometry.safeAreaInsets
        let stage = CGSize(
            width: geometry.size.width + insets.leading + insets.trailing,
            height: geometry.size.height + insets.bottom
        )
        let across = AltarStageView.placement(in: stage).across
        return stage.width * across - insets.leading - Self.railWidth
    }

    // MARK: - The stage

    /// The sanctuary, the figure on its dais and the light falling on both,
    /// in ONE frame that runs under the side insets and the home indicator to
    /// the glass — the Hall of Ka's `hallStage`, layer for layer, so the feet
    /// stand on the painted stone on any phone. The figure turns with the
    /// drag across its column and stops drawing while anything covers the
    /// sheet (`playing`), so the Hall of Ka opened from here is the one stage
    /// running.
    private func altarStage(_ shown: ResolvedUnit) -> some View {
        ZStack {
            hallBackdrop
                .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
            AltarStageView(
                blueprint: figureStands ? shown.blueprint : nil,
                awakened: shown.unit.isAwakened,
                ceremony: nil,
                spin: spinRadians,
                playing: presented == nil
            )
            .allowsHitTesting(false)
            .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
            PlaceAmbience(shafts: LightShaft.sanctuary, motes: 0, seed: 944)
                .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
        }
        .ignoresSafeArea(.container, edges: [.horizontal, .bottom])
    }

    /// The Hall of Ka's painting with its scrims, darker toward the panel's
    /// side of the room.
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

    /// The figure's turn about its upright, at the collection Stage's rate.
    private var spinRadians: Float {
        Float((spinBase + spinDrag) * CollectionStageView.spinPerPoint)
    }

    /// Stands the figure on the dais a beat after the sheet opens.
    ///
    /// The unit's mesh is parsed off the main thread from the moment the
    /// sheet appears, with the next three faces' on the rail, and the figure
    /// is placed 0.35 s later, when the sheet has finished rising. Placed at
    /// once, in the stage's `makeUIView`, a family not yet in the cache would
    /// be parsed on the main thread inside the sheet's first layout, before
    /// the sheet could start to move. Meshes only, as the Hall of Ka and the
    /// collection warm: the sheet plays one clip, the idle, whose small file
    /// the altar reads as it places the figure — warming a family's twelve
    /// clips would hold the importer for eleven it never plays. The figure
    /// then goes into a scene that is already rendering, which is the order
    /// `SCNNode.startLoop` exists for.
    @MainActor
    private func standFigure() async {
        if let shown = store.resolved(shownID) {
            ModelLibrary.shared.warm(forms: [(spec: shown.blueprint.model, awakened: shown.unit.isAwakened)],
                                     crowded: false, clips: false)
            warmAhead(of: shown.id, in: railUnits(including: shown))
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        figureStands = true
    }

    /// The next three faces on the rail after `id`, parsed off the main
    /// thread (the Hall of Ka's rail warms its top six the same way), so a
    /// thumb running down the rail clones from the cache.
    private func warmAhead(of id: UUID, in faces: [ResolvedUnit]) {
        guard let index = faces.firstIndex(where: { $0.id == id }) else { return }
        let ahead = faces.dropFirst(index + 1).prefix(3)
        guard !ahead.isEmpty else { return }
        ModelLibrary.shared.warm(forms: ahead.map { (spec: $0.blueprint.model, awakened: $0.unit.isAwakened) },
                                 crowded: false, clips: false)
    }

    /// The awakened form's mesh and clips, parsed off the main thread before
    /// the Hall of Ka opens in Awaken: the altar there swaps its figure for
    /// the awakened one the moment `store.awaken` returns, and so does this
    /// one under it. The Hall's `warmAwakening`, a beat earlier.
    private func warmAwakenedForm(_ shown: ResolvedUnit) {
        guard !shown.unit.isAwakened, shown.blueprint.awakening != nil else { return }
        ModelLibrary.shared.warm(forms: [(spec: shown.blueprint.model, awakened: true)], crowded: false, clips: true)
    }

    // MARK: - The rail

    /// The faces the rail pages through: the roster given, in its order (any
    /// unit it names that is gone since is left out, and the unit on the dais
    /// is always there), or every owned unit by power.
    private func railUnits(including shown: ResolvedUnit) -> [ResolvedUnit] {
        guard let roster else {
            return store.resolvedUnits.sorted { $0.power > $1.power }
        }
        var faces = roster.compactMap { store.resolved($0) }
        if !faces.contains(where: { $0.id == shown.id }) {
            faces.insert(shown, at: 0)
        }
        return faces
    }

    /// The roster as a rail of faces down the left edge, opening on whole
    /// rows with the unit on the dais in them (`WholeRowRail`, the Hall of
    /// Ka's own), on the rail's dark glass.
    private func faceRail(_ faces: [ResolvedUnit]) -> some View {
        WholeRowRail(width: Self.railWidth, items: faces, focus: shownID) { unit in
            railRow(unit, faces: faces)
        }
    }

    private func railRow(_ unit: ResolvedUnit, faces: [ResolvedUnit]) -> some View {
        Button {
            // A face of a scrolling rail: the quiet press, its tick and tap
            // here, on a finished tap.
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            standOnDais(unit, from: faces)
        } label: {
            UnitPortraitTile(unit: unit, size: Self.railFace)
                .padding(4)
                .background(GlassRowPlate(isOn: unit.id == shownID))
                // The face and its plate's rim are the tap.
                .contentShape(Rectangle())
        }
        .buttonStyle(GamePressStyle(.quiet))
    }

    /// A face picked on the rail stands on the dais, met face on, on its
    /// first skill; the three faces after it are warmed.
    private func standOnDais(_ unit: ResolvedUnit, from faces: [ResolvedUnit]) {
        guard unit.id != shownID else { return }
        shownID = unit.id
        spinBase = 0
        spinDrag = 0
        selectedSkill = 0
        figureStands = true
        warmAhead(of: unit.id, in: faces)
    }

    // MARK: - The figure's column

    /// Over the figure: the nameplate at the top, centred on the figure and
    /// kept inside the column; under it the whole column is the turntable a
    /// drag turns the figure on; the turn's hint at the foot.
    private func figureColumn(_ shown: ResolvedUnit, figureX: CGFloat) -> some View {
        GeometryReader { column in
            let width = column.size.width
            let plateWidth = max(0, min(Self.nameplateWidest, width - 10))
            let lowest = plateWidth / 2 + 5
            let highest = max(lowest, width - plateWidth / 2 - 5)
            let centre = min(max(figureX, lowest), highest)
            VStack(spacing: 0) {
                nameplate(shown)
                    .frame(width: plateWidth)
                    .offset(x: centre - width / 2)
                    .frame(width: width)
                turntable
            }
        }
        .overlay(alignment: .bottom) {
            turnHint
        }
    }

    /// The drag that turns the figure about its own axis, left for left; it
    /// stays where the finger left it until the next drag or the next unit.
    private var turntable: some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        spinDrag = value.translation.width
                    }
                    .onEnded { value in
                        spinBase += value.translation.width
                        spinDrag = 0
                    }
            )
            .accessibilityHidden(true)
    }

    /// The turn's hint, centred at the column's foot 12 points above the
    /// safe bottom (the column ends 8 above it).
    private var turnHint: some View {
        Image(systemName: "arrow.left.and.right")
            .font(.system(size: 11, weight: .black))
            .foregroundStyle(Theme.onGlassDim.opacity(0.75))
            .shadow(color: .black.opacity(0.6), radius: 1, y: 0.5)
            .frame(height: 8)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// Who stands on the dais, on a small glass plate over the figure's
    /// head: the card's thumbnail (the door to the card), the element and
    /// the stars, the level, and the power.
    private func nameplate(_ shown: ResolvedUnit) -> some View {
        HStack(spacing: 8) {
            cardThumbnail(shown)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    ElementBadge(element: shown.element, compact: true)
                    // Bright on the glass: the natural stars' dim bronze
                    // could not be counted (run 217).
                    StarRow(stars: shown.stars, size: 11)
                }
                // Measured in the bundled faces: "Lv.40/55" is 53 points and
                // "11,423" 55, so the row is 114 of the 120 an iPhone 16's
                // plate leaves them; MAX stands over the level as POWER
                // stands over its figure, since beside it (63) the row
                // would be 123 and spill out of the plate.
                HStack(alignment: .lastTextBaseline, spacing: 0) {
                    nameplateLevel(shown)
                    Spacer(minLength: 6)
                    nameplatePower(shown)
                }
            }
        }
        .padding(6)
        .background(GlassPlate(radius: 10, opacity: 0.72))
    }

    private func cardThumbnail(_ shown: ResolvedUnit) -> some View {
        Button {
            withAnimation(Motion.pop) {
                showCard = true
            }
        } label: {
            UnitPortraitTile(unit: shown, size: 40, showsLevel: false)
        }
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel("Show the card")
    }

    /// "Lv.40/55", or at the cap "Lv.60" under a green MAX — the level's
    /// own eyebrow, level with POWER's.
    @ViewBuilder
    private func nameplateLevel(_ shown: ResolvedUnit) -> some View {
        if shown.unit.isMaxLevel {
            VStack(alignment: .leading, spacing: 0) {
                Text("MAX")
                    .font(Theme.body(11).weight(.black))
                    .tracking(0.8)
                    .foregroundStyle(RelicPalette.gain)
                Text("Lv.\(shown.level)")
                    .font(Theme.numeric(13))
                    .foregroundStyle(RelicPalette.value)
            }
            .lineLimit(1)
            .fixedSize()
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("Lv.\(shown.level)")
                    .font(Theme.numeric(13))
                    .foregroundStyle(RelicPalette.value)
                Text("/\(shown.unit.maxLevel)")
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(RelicPalette.dim)
            }
            .lineLimit(1)
            .fixedSize()
        }
    }

    /// POWER over the figure. It rolls to its new value when the unit's
    /// power moves (a relic worn from Manage); a new unit on the dais is a
    /// new figure (`id`), not a roll from the last one's.
    private func nameplatePower(_ shown: ResolvedUnit) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("POWER")
                .font(Theme.body(11).weight(.black))
                .tracking(0.8)
                .foregroundStyle(RelicPalette.eyebrow)
                .lineLimit(1)
                .fixedSize()
            Text(shown.power.formatted())
                .font(Theme.numeric(16))
                .foregroundStyle(RelicPalette.star)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText(value: Double(shown.power)))
                .animation(Motion.select, value: shown.power)
                .id(shown.id)
        }
    }

    // MARK: - The card

    /// The unit's card over the whole sheet, from the nameplate's
    /// thumbnail: the painting in its grade's metal and the name under it; a
    /// tap anywhere puts it away. It replaces the old well's flip.
    @ViewBuilder
    private func cardOverlay(_ shown: ResolvedUnit?) -> some View {
        if showCard, let shown {
            ZStack {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                VStack(spacing: 10) {
                    cardPainting(shown)
                    Text(shown.nameWithoutEpithet.uppercased())
                        .font(Theme.display(19))
                        .tracking(1.4)
                        .carved()
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(Motion.exit) {
                    showCard = false
                }
            }
            .transition(.asymmetric(insertion: .scale(scale: 0.94).combined(with: .opacity), removal: .opacity))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("The card of \(shown.nameWithoutEpithet)")
            .accessibilityHint("Tap to close")
            .accessibilityAddTraits(.isButton)
        }
    }

    @ViewBuilder
    private func cardPainting(_ shown: ResolvedUnit) -> some View {
        let name = shown.blueprint.model.portraitName(awakened: shown.unit.isAwakened)
        let rarity = Rarity(stars: shown.stars)
        if BundleImage.exists(name) {
            PortraitPainting(name: name, size: 220)
                .frame(width: 220, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    // The carved frame for the grade, as a large card wears
                    // it; `rarityFrame` strokes the metal when it has not
                    // shipped.
                    if let frame = Chrome.image(rarity.frameImageName) {
                        Image(uiImage: frame)
                            .resizable()
                    }
                }
                .rarityFrame(rarity, radius: 12)
                .allowsHitTesting(false)
        } else {
            UnitPortraitTile(unit: shown, size: 220, showsLevel: false)
                .allowsHitTesting(false)
        }
    }

    // MARK: - The tablets

    /// Five bronze tablets on their fluted rod, top-aligned with the panel;
    /// the chosen one gold leaf, and a red dot on any whose tab has
    /// something to do.
    private func tabletColumn(_ shown: ResolvedUnit) -> some View {
        let tabs = UnitSheetTab.allCases
        let stackHeight = CGFloat(tabs.count) * Self.tabletHeight + CGFloat(max(0, tabs.count - 1)) * Self.tabletGap
        return ZStack(alignment: .top) {
            TabletRod(height: stackHeight)
            VStack(spacing: Self.tabletGap) {
                ForEach(tabs, id: \.self) { each in
                    UnitSheetTablet(title: each.title, isOn: each == tab, waiting: isWaiting(each, shown)) {
                        choose(each)
                    }
                }
            }
        }
        .frame(width: Self.tabletWidth)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// A new tab, cross-faded; remembered for the next sheet, except under
    /// the tour.
    private func choose(_ next: UnitSheetTab) {
        guard next != tab else { return }
        withAnimation(Motion.select) {
            tab = next
        }
        if !Self.touring {
            UserDefaults.standard.set(next.rawValue, forKey: Self.tabKey)
        }
    }

    /// Whether a tab has something to do: INFO a rite the unit is ready for,
    /// RELICS an empty slot with a free relic of that slot, BOON a cache to
    /// open or, with the socket empty, a free boon.
    private func isWaiting(_ which: UnitSheetTab, _ shown: ResolvedUnit) -> Bool {
        switch which {
        case .info:
            return riteWaits(shown)
        case .relics:
            return relicWaits(shown)
        case .boon:
            return boonWaits(shown)
        case .skills, .regalia:
            return false
        }
    }

    private func riteWaits(_ shown: ResolvedUnit) -> Bool {
        if shown.unit.canEvolve { return true }
        return shown.blueprint.awakening != nil && !shown.unit.isAwakened && essencesMet(shown)
    }

    private func relicWaits(_ shown: ResolvedUnit) -> Bool {
        let relics = store.player.relics
        for slot in 1...6 where shown.unit.equippedRelics[slot] == nil {
            if relics.contains(where: { $0.slot == slot && $0.equippedBy == nil }) {
                return true
            }
        }
        return false
    }

    private func boonWaits(_ shown: ResolvedUnit) -> Bool {
        if !(store.player.boonCaches ?? []).isEmpty { return true }
        guard shown.boon == nil else { return false }
        return (store.player.boons ?? []).contains { $0.equippedBy == nil }
    }

    // MARK: - The panel

    /// The chosen tab on one dark glass plate, 12 points in; a new tab
    /// cross-fades in over the old, no slide.
    private func tabPanel(_ shown: ResolvedUnit) -> some View {
        ZStack(alignment: .topLeading) {
            tabContent(shown)
                .id(tab)
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(GlassPlate(radius: 12, opacity: 0.78))
    }

    @ViewBuilder
    private func tabContent(_ shown: ResolvedUnit) -> some View {
        switch tab {
        case .info:
            infoTab(shown)
        case .skills:
            skillsTab(shown)
        case .relics:
            relicsTab(shown)
        case .boon:
            boonTab(shown)
        case .regalia:
            regaliaTab(shown)
        }
    }

    private func present(_ cover: UnitSheetCover) {
        presented = cover
    }

    /// Everything the sheet opens, as sheets over it, on the unit on the
    /// dais.
    @ViewBuilder
    private func coverView(_ cover: UnitSheetCover) -> some View {
        switch cover {
        case .training(let mode):
            TrainingView(initialMode: mode, selectedUnitID: shownID)
        case .manage:
            RelicsScreen(unitID: shownID)
        case .manageSlot(let slot):
            RelicsScreen(unitID: shownID, opening: .slot(slot))
        case .bestSix(let goal):
            RelicsScreen(unitID: shownID, opening: .bestSix(goal))
        case .fillEmpty:
            RelicsScreen(unitID: shownID, opening: .fillEmpty)
        case .bag:
            RelicsScreen()
        case .card(let relicID):
            RelicCard(relicID: relicID)
        case .sets:
            RelicSetsReference(unitID: shownID)
        case .boons:
            BoonPickerView(unitID: shownID)
        case .regalia:
            RegaliaSheet(unitID: shownID)
        }
    }

    // MARK: - INFO

    /// The level with its bar and the power-up medallion, the eight stats
    /// with what the relics add, the unit's tags, and the two rites.
    private func infoTab(_ shown: ResolvedUnit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            levelRow(shown)
            Color.clear
                .frame(height: 8)
            HStack(alignment: .top, spacing: 8) {
                StatLedger(rows: statRows(shown), style: .info)
                Spacer(minLength: 0)
                tagColumn(shown)
            }
            Spacer(minLength: 10)
            riteRow(shown)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// "Lv.40 / 55", the experience bar, "0 / 8,232" and the gold (+) that
    /// opens the Hall of Ka to power the unit up. `grantExperience` zeroes
    /// the stored experience at the cap, so a maxed unit's bar is drawn full
    /// with the level's own figure, and says MAX.
    private func levelRow(_ shown: ResolvedUnit) -> some View {
        let toNext = ProgressionService.experienceForNextLevel(level: shown.level, stars: shown.stars)
        let isMax = shown.unit.isMaxLevel
        let experience = isMax ? toNext : shown.unit.experience
        return HStack(spacing: 8) {
            infoLevel(shown)
            GlassMeter(
                value: Double(experience),
                maximum: Double(toNext),
                tint: isMax ? Theme.gold : Self.experienceTint,
                height: 6
            )
            Text("\(experience.formatted()) / \(toNext.formatted())")
                .font(Theme.numeric(11.5))
                .foregroundStyle(RelicPalette.dim)
                .lineLimit(1)
                .fixedSize()
            powerUpMedallion
        }
        .frame(height: 34)
    }

    @ViewBuilder
    private func infoLevel(_ shown: ResolvedUnit) -> some View {
        if shown.unit.isMaxLevel {
            HStack(spacing: 0) {
                Text("Lv.\(shown.level) · ")
                    .foregroundStyle(RelicPalette.value)
                Text("MAX")
                    .foregroundStyle(RelicPalette.gain)
            }
            .font(Theme.numeric(13))
            .lineLimit(1)
            .fixedSize()
        } else {
            Text("Lv.\(shown.level) / \(shown.unit.maxLevel)")
                .font(Theme.numeric(13))
                .foregroundStyle(RelicPalette.value)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// The gold (+): the Hall of Ka in Power up, on this unit.
    private var powerUpMedallion: some View {
        Button {
            present(.training(.powerUp))
        } label: {
            ZStack {
                Circle()
                    .fill(RelicPalette.goldLeaf)
                Circle()
                    .strokeBorder(Color(hex: "#5C4611"), lineWidth: 1)
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(RelicPalette.goldInk)
            }
            .frame(width: 34, height: 34)
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.4), radius: 2, y: 1.5)
            .contentShape(Circle())
        }
        .buttonStyle(GamePressStyle(.medallion))
        .accessibilityLabel("Power up")
    }

    /// HP, ATK, DEF, SPD, then the four percentages: each the total, and
    /// the total less the base — grade, level and awakening — which is what
    /// the relics add.
    private func statRows(_ shown: ResolvedUnit) -> [StatLedgerRow] {
        let base = ProgressionService.baseStats(for: shown.unit, blueprint: shown.blueprint)
        let total = shown.stats
        return [
            Self.ledgerRow("HP", base.hp, total.hp, percent: false),
            Self.ledgerRow("ATK", base.atk, total.atk, percent: false),
            Self.ledgerRow("DEF", base.def, total.def, percent: false),
            Self.ledgerRow("SPD", base.spd, total.spd, percent: false),
            Self.ledgerRow("CRIT Rate", base.critRate, total.critRate, percent: true),
            Self.ledgerRow("CRIT DMG", base.critDamage, total.critDamage, percent: true),
            Self.ledgerRow("Accuracy", base.accuracy, total.accuracy, percent: true),
            Self.ledgerRow("Resistance", base.resistance, total.resistance, percent: true),
        ]
    }

    /// One ledger line: the change is shown from half a point (half a
    /// percent), green for a gain and rose for a loss.
    private static func ledgerRow(_ label: String, _ base: Double, _ total: Double, percent: Bool) -> StatLedgerRow {
        let bonus = total - base
        let threshold: Double = percent ? 0.005 : 0.5
        let value = statText(total, percent: percent)
        guard abs(bonus) >= threshold else {
            return StatLedgerRow(label: label, value: value, change: nil, tone: .none)
        }
        let sign = bonus > 0 ? "+" : "−"
        let tone: LedgerTone = bonus > 0 ? .gain : .loss
        return StatLedgerRow(label: label, value: value, change: sign + statText(abs(bonus), percent: percent), tone: tone)
    }

    /// The role in quiet capitals, the pantheon in its colour, the
    /// archetype in a well — SW's quiet "Support" under the name.
    private func tagColumn(_ shown: ResolvedUnit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(shown.role.displayName.uppercased())
                .font(Theme.body(11).weight(.black))
                .tracking(0.8)
                .foregroundStyle(RelicPalette.dim)
                .lineLimit(1)
                .fixedSize()
            tagCapsule(shown.pantheon.displayName, ink: shown.pantheon.color, ground: shown.pantheon.color.opacity(0.22))
            tagCapsule(shown.archetype.displayName, ink: RelicPalette.dim, ground: RelicPalette.well)
        }
        .frame(width: 100, alignment: .topLeading)
    }

    private func tagCapsule(_ word: String, ink: Color, ground: Color) -> some View {
        Text(word)
            .font(Theme.body(11).weight(.semibold))
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(ground))
    }

    /// EVOLVE and, for a family that has one, AWAKEN: each opens the Hall
    /// of Ka in that mode on this unit, where the rite is chosen and paid.
    private func riteRow(_ shown: ResolvedUnit) -> some View {
        HStack(spacing: 8) {
            RelicPlateButton(
                title: "Evolve",
                count: evolveSubtitle(shown),
                systemImage: "star.circle.fill",
                height: 44,
                isEnabled: shown.unit.canEvolve
            ) {
                present(.training(.evolve))
            }
            if shown.blueprint.awakening != nil {
                awakenPlate(shown)
            }
        }
    }

    /// AWAKEN is always a door: before the rite it says whether the
    /// essences are in; after it, the awakened unit still sees both forms
    /// in the Hall.
    private func awakenPlate(_ shown: ResolvedUnit) -> some View {
        let reading = awakeningReading(shown)
        return RelicPlateButton(
            title: shown.unit.isAwakened ? "Awakened" : "Awaken",
            count: reading.words,
            countTint: reading.tint,
            systemImage: "sun.max.fill",
            height: 44
        ) {
            warmAwakenedForm(shown)
            present(.training(.awaken))
        }
    }

    private func awakeningReading(_ shown: ResolvedUnit) -> (words: String, tint: Color) {
        if shown.unit.isAwakened {
            return (words: "Form unlocked", tint: RelicPalette.gain)
        }
        if essencesMet(shown) {
            return (words: "Essences ready ✓", tint: RelicPalette.gain)
        }
        return (words: "Essences short", tint: RelicPalette.partial)
    }

    private func essencesMet(_ shown: ResolvedUnit) -> Bool {
        guard let awakening = shown.blueprint.awakening else { return false }
        return awakening.essenceCost.allSatisfy { (store.player.essences[$0.key] ?? 0) >= $0.value }
    }

    /// Why EVOLVE is lit or dark. `canEvolve` is false for two different
    /// reasons — short of the level cap, and already 6★ — and one line of
    /// copy once told a maxed 6★ to "Reach Lv.65 first" while it stood at
    /// Lv.65.
    private func evolveSubtitle(_ shown: ResolvedUnit) -> String {
        if shown.stars >= 6 { return "Fully evolved · 6★" }
        guard shown.unit.canEvolve else { return "Reach Lv.\(shown.unit.maxLevel) first" }
        let fodder = ProgressionService.evolutionFodderRequired(currentStars: shown.stars)
        let cost = ProgressionService.drachmaCostToEvolve(currentStars: shown.stars)
        // "5 × 5★ · 150K": the Hall of Ka's ledger spells the bill out in
        // full before anything is spent.
        return "\(fodder) × \(shown.stars)★ · \(BarWallet.compact(cost))"
    }

    // MARK: - SKILLS

    /// The icons pinned along the top — the kit's, then the leader skill's
    /// crown — and under them, in a scroll that fades only when the words do
    /// not fit, the chosen one's words.
    private func skillsTab(_ shown: ResolvedUnit) -> some View {
        let index = shownSkillIndex(shown)
        return VStack(alignment: .leading, spacing: 8) {
            skillRow(shown, index: index)
            // A new skill is a new page, met at its top.
            SheetPanelScroll {
                skillPage(shown, index: index)
            }
            .id(index)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func shownSkillIndex(_ shown: ResolvedUnit) -> Int {
        if selectedSkill == Self.leaderSlot, shown.blueprint.leaderSkill != nil {
            return Self.leaderSlot
        }
        return min(max(0, selectedSkill), max(0, shown.skills.count - 1))
    }

    /// The painted icons in wells, the chosen one rimmed in gold. 44 while
    /// four tiles share the row, 40 for five.
    private func skillRow(_ shown: ResolvedUnit, index: Int) -> some View {
        let ranged = !shown.blueprint.model.melee
        let icons = SkillArt.keys(for: shown.skills, element: shown.element, ranged: ranged)
        let hasLeader = shown.blueprint.leaderSkill != nil
        let tiles = shown.skills.count + (hasLeader ? 1 : 0)
        let icon: CGFloat = tiles > 4 ? 40 : 44
        return HStack(spacing: 6) {
            ForEach(shown.skills.indices, id: \.self) { slot in
                skillButton(
                    shown.skills[slot],
                    slot: slot,
                    selected: slot == index,
                    element: shown.element,
                    ranged: ranged,
                    iconKey: slot < icons.count ? icons[slot] : nil,
                    icon: icon
                )
            }
            if hasLeader {
                leaderButton(selected: index == Self.leaderSlot, icon: icon)
            }
        }
        .frame(height: 52)
    }

    private func skillButton(
        _ skill: Skill, slot: Int, selected: Bool, element: Element,
        ranged: Bool, iconKey: String?, icon: CGFloat
    ) -> some View {
        Button {
            selectedSkill = slot
        } label: {
            SkillIcon(skill: skill, element: element, ranged: ranged, resolvedKey: iconKey, size: icon, socket: true)
                .padding(4)
                .frame(maxWidth: .infinity)
                .background(skillWell(selected: selected))
                .contentShape(Rectangle())
        }
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel(skill.name)
    }

    private func leaderButton(selected: Bool, icon: CGFloat) -> some View {
        Button {
            selectedSkill = Self.leaderSlot
        } label: {
            leaderGlyph(icon: icon)
                .padding(4)
                .frame(maxWidth: .infinity)
                .background(skillWell(selected: selected))
                .contentShape(Rectangle())
        }
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel("Leader skill")
    }

    private func skillWell(selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return shape
            .fill(RelicPalette.well)
            .overlay(shape.strokeBorder(selected ? Self.chosenRim : RelicPalette.bronze, lineWidth: selected ? 1.5 : 1))
    }

    /// The leader skill's tile: a gold crown in the same socket as the
    /// skills' icons.
    private func leaderGlyph(icon: CGFloat) -> some View {
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
    }

    @ViewBuilder
    private func skillPage(_ shown: ResolvedUnit, index: Int) -> some View {
        if index == Self.leaderSlot, let leader = shown.blueprint.leaderSkill {
            leaderWords(leader)
        } else if shown.skills.indices.contains(index) {
            skillWords(shown.skills[index], index: index, shown: shown)
        }
    }

    /// The chosen skill: its name with its level (a door to the skill-up
    /// ladder), what it costs and hits for, and what it does.
    private func skillWords(_ skill: Skill, index: Int, shown: ResolvedUnit) -> some View {
        let level = shown.unit.skillLevels.indices.contains(index) ? shown.unit.skillLevels[index] : 1
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(skill.name)
                    .font(Theme.body(15).weight(.bold))
                    .foregroundStyle(RelicPalette.value)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                SkillLevelButton(skill: skill, level: level)
            }
            skillFacts(skill, stats: shown.stats)
            Text(skill.description)
                .font(Theme.body(13))
                .foregroundStyle(RelicPalette.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// PASSIVE, the cooldown, and the damage estimate, on one line.
    @ViewBuilder
    private func skillFacts(_ skill: Skill, stats: Stats) -> some View {
        let estimate = damageLine(skill, stats: stats)
        if skill.isPassive || skill.cooldown > 0 || estimate != nil {
            HStack(spacing: 10) {
                if skill.isPassive {
                    passiveChip
                }
                if skill.cooldown > 0 {
                    cooldownLabel(skill.cooldown)
                }
                if let estimate {
                    Text(estimate)
                        .font(Theme.numeric(13))
                        .foregroundStyle(RelicPalette.star)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
    }

    /// "≈ 243 dmg · 2 hits". `previewDamage` already multiplies by the hit
    /// count, so the hits are said, never multiplied again.
    private func damageLine(_ skill: Skill, stats: Stats) -> String? {
        guard let damage = skill.damage else { return nil }
        let estimate = DamageCalculator.previewDamage(attackStat: Self.scalingStat(damage.scaling, stats), spec: damage)
        let hits = damage.hits > 1 ? " · \(damage.hits) hits" : ""
        return "≈ \(Int(estimate).formatted()) dmg" + hits
    }

    private var passiveChip: some View {
        Text("PASSIVE")
            .font(Theme.body(11).weight(.black))
            .tracking(0.6)
            .foregroundStyle(RelicPalette.partial)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Capsule().fill(RelicPalette.partial.opacity(0.16)))
    }

    private func cooldownLabel(_ turns: Int) -> some View {
        let words: String = turns == 1 ? "1 turn" : "\(turns) turns"
        return HStack(spacing: 3) {
            Image(systemName: "clock.fill")
                .font(.system(size: 11, weight: .bold))
            Text(words)
                .font(Theme.numeric(12))
        }
        .foregroundStyle(RelicPalette.dim)
        .lineLimit(1)
        .fixedSize()
    }

    /// The leader skill's words: what it gives, to whom, and where it
    /// counts. It works for the unit that LEADS — the first of a team
    /// (`BattleEngine.buildSide`).
    private func leaderWords(_ leader: LeaderSkill) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(RelicPalette.star)
                Text("Leader skill")
                    .font(Theme.body(15).weight(.bold))
                    .foregroundStyle(RelicPalette.value)
                    .lineLimit(1)
            }
            Text(leader.description)
                .font(Theme.body(13))
                .foregroundStyle(RelicPalette.dim)
                .fixedSize(horizontal: false, vertical: true)
            Text(Self.leaderReach(leader))
                .font(Theme.body(12))
                .foregroundStyle(RelicPalette.eyebrow)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func leaderReach(_ leader: LeaderSkill) -> String {
        if leader.appliesInArena && leader.appliesInCampaign {
            return "When this unit leads — the first of the team — in any fight."
        }
        if leader.appliesInArena {
            return "When this unit leads — the first of the team — in the Arena only."
        }
        if leader.appliesInCampaign {
            return "When this unit leads — the first of the team — anywhere but the Arena."
        }
        return "It applies nowhere yet."
    }

    // MARK: - RELICS

    /// The owner's screen: the six relics as ONE object round the Boon, the
    /// sets they make in two words each, and four plates — MANAGE (the
    /// tab's one gold), BEST SIX ▾, RELICS with the bag's count and STONES
    /// with the stones'.
    private func relicsTab(_ shown: ResolvedUnit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassSectionHeader(title: "Relics", accessory: relicsAccessory(shown))
            Color.clear
                .frame(height: 8)
            HStack(alignment: .top, spacing: 12) {
                relicRosette(shown)
                    .frame(width: Self.rosetteColumn, height: Self.relicRowHeight)
                setEffectsColumn(shown)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: Self.relicRowHeight, alignment: .top)
            }
            Spacer(minLength: 4)
            relicPlates
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// "5/6 worn · +1,240 power": what the six slots are worth is the unit's
    /// power less the power it would have with them empty, so a completed
    /// set's bonus is counted.
    private func relicsAccessory(_ shown: ResolvedUnit) -> String {
        let worn = shown.relics.count
        guard worn > 0 else { return "0/6 worn" }
        let bare = ProgressionService.resolve(shown.unit, blueprint: shown.blueprint, equipped: [])
        let gained = shown.power - bare.power
        let sign = gained < 0 ? "−" : "+"
        return "\(worn)/6 worn · \(sign)\(abs(gained).formatted()) power"
    }

    /// The worn relics by the slot they are worn in.
    private func relicsBySlot(_ shown: ResolvedUnit) -> [Int: Relic] {
        var slots: [Int: Relic] = [:]
        for (slot, relicID) in shown.unit.equippedRelics {
            if let relic = store.player.relic(relicID) {
                slots[slot] = relic
            }
        }
        return slots
    }

    private func relicRosette(_ shown: ResolvedUnit) -> some View {
        RelicRosette(
            slots: relicsBySlot(shown),
            activeSets: Set(shown.activeRelicSets.map { $0.set }),
            boon: shown.boon,
            radius: 28,
            gap: 3,
            onSlot: { slot in
                openSlot(slot, of: shown)
            },
            onCentre: {
                present(.boons)
            }
        )
    }

    /// A worn socket opens the relic's card; an empty one opens Manage on
    /// that slot — the same rule as the collection's plates.
    private func openSlot(_ slot: Int, of shown: ResolvedUnit) {
        if let relicID = shown.unit.equippedRelics[slot], store.player.relic(relicID) != nil {
            present(.card(relicID))
        } else {
            present(.manageSlot(slot))
        }
    }

    /// SET EFFECTS: every set with a piece on the unit, complete first, then
    /// by pieces worn, then by name — up to three whole lines, or two and a
    /// line of chips for the rest. The (i) and the lines open the set
    /// reference counting this unit's pieces.
    private func setEffectsColumn(_ shown: ResolvedUnit) -> some View {
        let entries = Self.setEntries(shown)
        return VStack(alignment: .leading, spacing: 4) {
            setEffectsHeader
            if entries.isEmpty {
                Text("No relics worn")
                    .font(Theme.body(12))
                    .foregroundStyle(RelicPalette.dim)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                setEffectsList(entries)
            }
        }
    }

    private var setEffectsHeader: some View {
        HStack(spacing: 6) {
            Text("SET EFFECTS")
                .font(Theme.body(11).weight(.black))
                .tracking(0.8)
                .foregroundStyle(RelicPalette.eyebrow)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            setsInfoButton
        }
        // The 22-point (i) stands two points past the row above and below:
        // the column's three lines keep their 40.
        .frame(height: 18)
    }

    private var setsInfoButton: some View {
        Button {
            present(.sets)
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(RelicPalette.eyebrow, lineWidth: 1.2)
                Text("i")
                    .font(Theme.body(11).weight(.black))
                    .foregroundStyle(RelicPalette.eyebrow)
            }
            .frame(width: 22, height: 22)
            .contentShape(Circle())
        }
        .buttonStyle(GamePressStyle(.medallion))
        .accessibilityLabel("Set effects")
    }

    private func setEffectsList(_ entries: [UnitSheetSetEntry]) -> some View {
        let full: [UnitSheetSetEntry] = entries.count > 3 ? Array(entries.prefix(2)) : entries
        let rest: [UnitSheetSetEntry] = entries.count > 3 ? Array(entries.dropFirst(2)) : []
        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            present(.sets)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(full) { entry in
                    SetEffectRow(set: entry.relicSet, piecesOnUnit: entry.pieces, style: .full)
                }
                if !rest.isEmpty {
                    setChipLine(rest)
                }
            }
            .contentShape(Rectangle())
        }
        // Lines of words, not a plate: the quiet press, its tick and tap in
        // the action.
        .buttonStyle(GamePressStyle(.quiet))
        .accessibilityHint("Opens the set effects")
    }

    /// The third line when more than three sets have a piece on: the rest
    /// as chips, each set's stone and its count. Three fit the column; past
    /// that, two and a count of the others, which the set reference lists.
    private func setChipLine(_ rest: [UnitSheetSetEntry]) -> some View {
        let chips: [UnitSheetSetEntry] = rest.count > 3 ? Array(rest.prefix(2)) : rest
        let others = rest.count - chips.count
        return HStack(spacing: 4) {
            ForEach(chips) { entry in
                setChip(entry)
            }
            if others > 0 {
                moreSetsChip(others)
            }
        }
        .frame(height: 40, alignment: .leading)
    }

    private func setChip(_ entry: UnitSheetSetEntry) -> some View {
        let required = entry.relicSet.piecesRequired
        let complete = entry.completions > 0
        return HStack(spacing: 3) {
            RelicSetEmblem(set: entry.relicSet, size: 20)
            Text("\(entry.pieces)/\(required)")
                .font(Theme.numeric(11.5))
                .foregroundStyle(complete ? RelicPalette.gain : RelicPalette.partial)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 5)
        .frame(height: 22)
        .background(Capsule().fill(RelicPalette.well))
        .overlay(Capsule().strokeBorder(RelicPalette.bronze, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.relicSet.displayName), \(entry.pieces) of \(required)")
    }

    private func moreSetsChip(_ others: Int) -> some View {
        Text("+\(others)")
            .font(Theme.numeric(11.5))
            .foregroundStyle(RelicPalette.dim)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Capsule().fill(RelicPalette.well))
            .overlay(Capsule().strokeBorder(RelicPalette.bronze, lineWidth: 1))
            .accessibilityLabel("\(others) more sets")
    }

    /// Complete sets first (twice over before once), then the most pieces
    /// worn, then by name, so the order is the same on every launch.
    private static func setEntries(_ shown: ResolvedUnit) -> [UnitSheetSetEntry] {
        var tally: [RelicSet: Int] = [:]
        for relic in shown.relics {
            tally[relic.set, default: 0] += 1
        }
        let entries = tally.map { UnitSheetSetEntry(relicSet: $0.key, pieces: $0.value) }
        return entries.sorted(by: setOrder)
    }

    private static func setOrder(_ first: UnitSheetSetEntry, _ second: UnitSheetSetEntry) -> Bool {
        if first.completions != second.completions { return first.completions > second.completions }
        if first.pieces != second.pieces { return first.pieces > second.pieces }
        return first.relicSet.displayName < second.relicSet.displayName
    }

    /// MANAGE and BEST SIX ▾ over RELICS and STONES, two halves a row.
    private var relicPlates: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                PrimaryButton(title: "Manage", systemImage: "square.grid.3x3.fill") {
                    present(.manage)
                }
                bestSixMenu
            }
            HStack(spacing: 8) {
                RelicPlateButton(
                    title: "Relics",
                    count: store.player.relics.count.formatted(),
                    itemKey: "relic_cache",
                    height: 44
                ) {
                    present(.bag)
                }
                stonesPlate
            }
        }
    }

    /// The optimiser's goals and Auto-equip's fill, each opening Manage with
    /// THEN set to that build — previewed, and applied there.
    private var bestSixMenu: some View {
        Menu {
            ForEach(RelicService.OptimiserGoal.allCases) { goal in
                Button {
                    present(.bestSix(goal))
                } label: {
                    Label("Best for \(goal.displayName)", systemImage: goal.glyph)
                }
            }
            Divider()
            Button {
                present(.fillEmpty)
            } label: {
                Label("Fill empty slots", systemImage: "square.dashed")
            }
        } label: {
            RelicPlateLabel(
                title: "Best six",
                systemImage: "wand.and.stars",
                height: PrimaryButton.height,
                trailingSystemImage: "chevron.down"
            )
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Best six")
    }

    /// Every whetstone and gem held, and the six of them in a popover.
    private var stonesPlate: some View {
        RelicPlateButton(
            title: "Stones",
            count: stoneTotal.formatted(),
            itemKey: "whetstone_legend",
            height: 44
        ) {
            showStones = true
        }
        .popover(isPresented: $showStones) {
            RelicStonesPopover()
                .environmentObject(store)
        }
    }

    private var stoneTotal: Int {
        (store.player.relicStones ?? [:]).values.reduce(0, +)
    }

    // MARK: - BOON

    /// The socket's boon — its glyph in a hexagon of the rosette's own
    /// metal, its name, its line and its pushes — or the socket empty with
    /// the caches to open and the boons owned; BOONS opens the list, and
    /// REMOVE takes a socketed one out.
    private func boonTab(_ shown: ResolvedUnit) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            GlassSectionHeader(title: "Boon", accessory: boonAccessory(shown.boon))
            Color.clear
                .frame(height: 14)
            boonBody(shown)
            Spacer(minLength: 10)
            boonFoot(shown)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func boonAccessory(_ boon: Boon?) -> String? {
        guard let boon else { return nil }
        return "\(boon.grade)★ · pushed \(boon.pushes)/\(BoonService.maxPushes)"
    }

    @ViewBuilder
    private func boonBody(_ shown: ResolvedUnit) -> some View {
        if let boon = shown.boon {
            socketedBoon(boon)
        } else {
            emptyBoon
        }
    }

    private func socketedBoon(_ boon: Boon) -> some View {
        HStack(spacing: 14) {
            hexWell(radius: 36)
                .overlay {
                    Image(systemName: boon.kind.glyph)
                        .font(.system(size: 30, weight: .black))
                        .foregroundStyle(boon.kind.tint)
                        .shadow(color: boon.kind.tint.opacity(0.8), radius: 6)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(boon.displayName.uppercased())
                    .font(Theme.title(17))
                    .carved(glow: false, multiline: true)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(boon.shortLine)
                    .font(Theme.numeric(16))
                    .foregroundStyle(RelicPalette.star)
                    .lineLimit(1)
                    .fixedSize()
                RollMarks(count: boon.pushes)
                Text("PUSHES")
                    .font(Theme.body(11).weight(.black))
                    .tracking(0.8)
                    .foregroundStyle(RelicPalette.eyebrow)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private var emptyBoon: some View {
        let caches = (store.player.boonCaches ?? []).count
        let loose = (store.player.boons ?? []).filter { $0.equippedBy == nil }.count
        return HStack(spacing: 14) {
            hexWell(radius: 36)
                .overlay {
                    Text("EMPTY")
                        .font(Theme.title(13))
                        .foregroundStyle(RelicPalette.quiet)
                        .lineLimit(1)
                        .fixedSize()
                }
                .accessibilityLabel("Boon socket, empty")
            VStack(alignment: .leading, spacing: 6) {
                countLine(caches, words: "to open")
                countLine(loose, words: "owned")
            }
        }
    }

    private func countLine(_ count: Int, words: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(count.formatted())
                .font(Theme.numeric(13))
                .foregroundStyle(RelicPalette.value)
            Text(words)
                .font(Theme.body(12))
                .foregroundStyle(RelicPalette.dim)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private func boonFoot(_ shown: ResolvedUnit) -> some View {
        let caches = (store.player.boonCaches ?? []).count
        return HStack(spacing: 8) {
            RelicPlateButton(
                title: "Boons",
                count: caches > 0 ? "\(caches) to open" : nil,
                systemImage: "seal.fill",
                height: 44
            ) {
                present(.boons)
            }
            if shown.boon != nil {
                RelicPlateButton(title: "Remove", systemImage: "minus.circle", height: 44) {
                    store.unequipBoon(from: shown.id)
                }
            }
        }
    }

    /// A pointy-top hexagon of `RelicSocket`'s rings — dark bronze, bronze
    /// light, bronze — round a basalt floor, framed as the square
    /// `BoonHexagon` reads its radius from.
    private func hexWell(radius: CGFloat) -> some View {
        ZStack {
            hexagon(radius, RelicPalette.bronzeDark)
            hexagon(radius - 0.8, RelicPalette.bronzeMid)
            hexagon(radius - 2.2, RelicPalette.bronze)
            hexagon(radius - 3.2, RelicPalette.basaltFoot)
        }
        .frame(width: radius * 2, height: radius * 2)
    }

    private func hexagon(_ radius: CGFloat, _ colour: Color) -> some View {
        BoonHexagon()
            .fill(colour)
            .frame(width: radius * 2, height: radius * 2)
    }

    // MARK: - REGALIA

    /// The family's own item: its glyph on a gold-rimmed medallion, its
    /// name, its template, its level as five pips and its line at that level
    /// — or the lock and what unlocks it. LADDER opens the five levels.
    private func regaliaTab(_ shown: ResolvedUnit) -> some View {
        let regalia = RegaliaService.regalia(forBlueprint: shown.blueprint.id, level: RegaliaService.level(of: shown.unit))
        let unlocked = shown.regalia != nil
        return VStack(alignment: .leading, spacing: 0) {
            GlassSectionHeader(title: "Regalia", accessory: regaliaAccessory(regalia, unlocked: unlocked))
            Color.clear
                .frame(height: 14)
            regaliaBody(regalia, unlocked: unlocked, blueprint: shown.blueprint)
            Spacer(minLength: 10)
            RelicPlateButton(title: "Ladder", systemImage: "list.number", height: 44) {
                present(.regalia)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func regaliaAccessory(_ regalia: Regalia?, unlocked: Bool) -> String? {
        guard let regalia else { return nil }
        return unlocked ? "Level \(regalia.levelLabel) of V" : "Locked"
    }

    @ViewBuilder
    private func regaliaBody(_ regalia: Regalia?, unlocked: Bool, blueprint: UnitBlueprint) -> some View {
        if let regalia {
            HStack(alignment: .top, spacing: 14) {
                regaliaMedallion(regalia.template.glyph)
                VStack(alignment: .leading, spacing: 5) {
                    Text(regalia.name.uppercased())
                        .font(Theme.title(17))
                        .carved(glow: false, multiline: true)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    templateChip(regalia.template.displayName)
                    RegaliaPips(level: regalia.level, lit: unlocked, size: 10)
                    regaliaLine(regalia, unlocked: unlocked, blueprint: blueprint)
                }
            }
        } else {
            Text("This family has no regalia.")
                .font(Theme.body(12))
                .foregroundStyle(RelicPalette.dim)
        }
    }

    private func regaliaMedallion(_ glyph: String) -> some View {
        ZStack {
            Circle()
                .fill(Theme.socketFill)
            Circle()
                .strokeBorder(RelicPalette.goldLeaf, lineWidth: 3)
            Image(systemName: glyph)
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(RelicPalette.star)
        }
        .frame(width: 72, height: 72)
        .accessibilityHidden(true)
    }

    private func templateChip(_ name: String) -> some View {
        Text(name)
            .font(Theme.body(12))
            .foregroundStyle(RelicPalette.dim)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(RelicPalette.well))
    }

    @ViewBuilder
    private func regaliaLine(_ regalia: Regalia, unlocked: Bool, blueprint: UnitBlueprint) -> some View {
        if unlocked {
            Text(regalia.line)
                .font(Theme.body(13))
                .foregroundStyle(RelicPalette.value)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(RegaliaService.unlockLine(for: blueprint))
                    .font(Theme.body(13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(RelicPalette.partial)
        }
    }

    // MARK: - Shared figures

    /// A stat as every screen prints it: grouped ("5,270", "+2,573"), or a
    /// whole percentage. It printed the bare figure — "HP 7301" beside
    /// "2,983" on the same plate (runs 220–221) — because a `String` handed
    /// to `Text` is not grouped the way an integer interpolated into one is.
    /// The collection's plates and the relic screens read it too.
    static func statText(_ value: Double, percent: Bool) -> String {
        percent ? "\(Int((value * 100).rounded()))%" : Int(value.rounded()).formatted()
    }

    /// The stat a skill's damage is multiplied by, so a max-health or defence
    /// skill never advertises the figure it would hit for off ATK.
    static func scalingStat(_ scaling: DamageScaling, _ stats: Stats) -> Double {
        switch scaling {
        case .attack: return stats.atk
        case .maxHealth: return stats.hp
        case .defense: return stats.def
        case .speed: return stats.spd
        }
    }
}

/// A skill's level beside its name, and the door to its ladder: every
/// skill-up with what it adds, the ones gained ticked, and where the next
/// one comes from. A skill with no skill-ups prints its level and opens
/// nothing. The badge is a dark well on the panel since 2026-09-24, its
/// figures in star gold once every skill-up is in.
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
            // In the skill's words, which scroll (`SheetPanelScroll`): the
            // quiet press, its tick and tap kept in the action (2026-09-24).
            .buttonStyle(GamePressStyle(.quiet))
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
                .font(Theme.body(11).weight(.bold))
                .foregroundStyle(isMax ? RelicPalette.star : RelicPalette.value)
                .lineLimit(1)
                .fixedSize()
            if !skill.levelUpBonuses.isEmpty {
                // The kit's wells' chevron: 10 points, never the 8 that read
                // as a speck (the audit's #9).
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(RelicPalette.eyebrow)
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(Capsule().fill(RelicPalette.well))
        .overlay(Capsule().strokeBorder(RelicPalette.bronze, lineWidth: 1))
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
