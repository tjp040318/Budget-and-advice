import SwiftUI

/// The hub: a painted island with a tappable landmark for every part of the
/// game.
///
/// Summoners War's town is a painting with a fixed camera and hotspots, not a
/// scene the player walks around, and that is what this is. The painting is
/// `island_bg.png`, drawn to fill the screen; each landmark's anchor is a point
/// in the painting, so the plaques land on their buildings at any screen size.
/// A landmark glows when there is something to do there — energy to spend,
/// scrolls to open, arena attacks left — and its plaque carries a tier mark
/// that climbs with the player's level, which is where the painted upgrade
/// states will plug in.
struct IslandView: View {
    @EnvironmentObject private var store: GameStore
    /// False while another tab is up; the living layer stops rendering.
    var isActive: Bool = true
    let onOpen: (IslandDestination) -> Void

    @State private var pulse = false
    @State private var shaking: String?
    @State private var showShop = false
    @State private var showMissions = false
    /// The chapter whose story card is up, held here between the tap on the
    /// gate and the campaign opening behind it.
    @State private var pendingIntro: Chapter?

    /// The guided opening's pointer: a fixed box, so the plate can be placed
    /// against the thing it points at without measuring the text first. A
    /// wrapped second line would otherwise push the caret off the building.
    static let guideWidth: CGFloat = 240
    static let guidePlate: CGFloat = 48

    /// Where the team stands: open sand below the circle and the beach band
    /// in front of it, measured off the painting like the landmarks' anchors.
    /// Nothing goes below y 0.75. The painting is filled into the frame, so on
    /// a landscape phone y 0.80 puts a figure's feet on the surf line with its
    /// shadow behind the tab bar, and y 0.84 puts them in the sea.
    static let stands: [CGPoint] = [
        CGPoint(x: 0.43, y: 0.63), CGPoint(x: 0.50, y: 0.73),
        CGPoint(x: 0.36, y: 0.72), CGPoint(x: 0.63, y: 0.745),
    ]

    /// The campaign team, made up to four from the strongest of the rest,
    /// so the island is never empty and the team the player fights with is
    /// the one standing about.
    private var standingUnits: [ResolvedUnit] {
        var units = store.team(store.player.campaignTeam)
        for unit in store.resolvedUnits.sorted(by: { $0.power > $1.power }) where units.count < Self.stands.count {
            if !units.contains(where: { $0.id == unit.id }) { units.append(unit) }
        }
        return Array(units.prefix(Self.stands.count))
    }

    /// The hour's light. The painting is a sunset, so the day is the painting
    /// as it is; dawn is pale, dusk warmer, night blue and dark.
    static func daylight(at date: Date = Date()) -> (overlay: Color, opacity: Double, lightHex: String) {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<8: return (Color(hex: "#FFD9C0"), 0.12, "#FFE6D0")
        case 8..<17: return (Color.clear, 0, "#FFF4E0")
        case 17..<20: return (Color(hex: "#FF9A4A"), 0.14, "#FFC890")
        default: return (Color(hex: "#24336A"), 0.45, "#9AB4FF")
        }
    }

    /// The painting's pixel size; the anchors are normalised against it. A
    /// 16:9 painting for a landscape phone, which shows its full width and
    /// crops 9% off the top and the bottom.
    static let paintingSize = CGSize(width: 2048, height: 1152)

    var body: some View {
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            let full = CGSize(
                width: geometry.size.width + insets.leading + insets.trailing,
                height: geometry.size.height + insets.top + insets.bottom
            )
            let frame = Self.fill(Self.paintingSize, in: full)

            ZStack(alignment: .top) {
                // The living layer sits over the painting and under the
                // plaques, covering the whole screen like the painting does.
                IslandSceneView(
                    units: standingUnits,
                    stands: Self.stands,
                    paintingFrame: frame,
                    viewSize: full,
                    lightHex: Self.daylight().lightHex,
                    isActive: isActive
                )
                .frame(width: full.width, height: full.height)
                .position(x: full.width / 2 - insets.leading, y: full.height / 2 - insets.top)
                .allowsHitTesting(false)

                ForEach(IslandDatabase.landmarks) { landmark in
                    plaque(landmark)
                        .position(
                            // Painting coordinates are in the full screen; the
                            // ZStack lives inside the safe area, hence the shift.
                            // Plaques float a little above their footprint so the
                            // painted building shows beneath the pin.
                            x: frame.minX + landmark.anchor.x * frame.width - insets.leading,
                            y: frame.minY + (landmark.anchor.y - 0.055) * frame.height - insets.top
                        )
                }
                header

                // The guided opening: one pointer at whatever the player has
                // not done yet. It is drawn last so it sits over the plaques,
                // and it is inert, so tapping "through" it opens the building.
                if let step = store.firstHourStep, pendingIntro == nil {
                    guide(step, frame: frame, full: full, insets: insets, size: geometry.size)
                }

                if let chapter = pendingIntro {
                    ChapterIntroCard(chapter: chapter) {
                        store.markChapterIntroSeen(chapter.id)
                        pendingIntro = nil
                        onOpen(.campaign)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(backdrop(full: full).ignoresSafeArea())
            .animation(.easeInOut(duration: 0.25), value: pendingIntro)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
            // The save carries the step so a relaunch opens on the same
            // pointer; a player who is past all four writes the sentinel here
            // and is never asked again.
            store.recordFirstHourStep(store.firstHourStep)
        }
        .onChange(of: store.firstHourStep) { _, step in
            store.recordFirstHourStep(step)
        }
        .sheet(isPresented: $showShop) {
            ShopView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showMissions) {
            MissionsView()
                .environmentObject(store)
        }
    }

    /// Where an image of `image` size lands when drawn to fill `container`,
    /// centred — the same placement SwiftUI's `.aspectRatio(contentMode: .fill)`
    /// produces, so the anchors and the pixels agree.
    static func fill(_ image: CGSize, in container: CGSize) -> CGRect {
        let scale = max(container.width / image.width, container.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Backdrop

    @ViewBuilder
    private func backdrop(full: CGSize) -> some View {
        if BundleImage.exists("island_bg") {
            BundleImage(name: "island_bg")
                .aspectRatio(contentMode: .fill)
                .frame(width: full.width, height: full.height)
                .clipped()
                .overlay(
                    // The hour's colour over the painting: nothing by day,
                    // warm at dusk, blue at night.
                    Rectangle()
                        .fill(Self.daylight().overlay)
                        .opacity(Self.daylight().opacity)
                        .blendMode(.multiply)
                )
                .overlay(
                    // Dusk falls a little harder at the edges so the plaques
                    // and the header read against the painting.
                    LinearGradient(
                        colors: [Theme.ink.opacity(0.55), .clear, .clear, Theme.ink.opacity(0.7)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                // Last in the chain, so the two washes over the painting are as
                // inert as the painting: a filled Rectangle in an overlay is
                // hit-testable even when it is clear, and `.clipped()` does not
                // clip hit-testing.
                .allowsHitTesting(false)
        } else {
            ZStack {
                Theme.backdrop
                RadialGradient(
                    colors: [Color(hex: "#3A2C1E"), Color(hex: "#15121F")],
                    center: .init(x: 0.5, y: 0.7), startRadius: 40, endRadius: 520
                )
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        let player = store.player
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(player.displayName)
                    .font(Theme.title(18))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.8), radius: 3, y: 1)
                HStack(spacing: 8) {
                    Text("Lv.\(player.level)")
                        .font(Theme.numeric(12))
                        .foregroundStyle(Theme.gold)
                        .lineLimit(1)
                    StatBar(
                        value: Double(player.experience),
                        maximum: Double(player.experienceToNextLevel),
                        tint: Theme.gold,
                        height: 5
                    )
                    .frame(width: 140)
                    // One line, always: "1240/2050" offers a break after the
                    // slash, and a wrap here would add a second line to the
                    // header on a narrow frame rather than truncate.
                    Text("\(player.experience)/\(player.experienceToNextLevel)")
                        .font(Theme.numeric(10))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            // Missions: the scroll beside the wallet, with what is waiting.
            Button {
                Juice.haptic(.light)
                AudioLibrary.shared.play(.uiTap)
                showMissions = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "scroll.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.gold)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.surface))
                        .overlay(Circle().strokeBorder(Theme.goldPlate, lineWidth: 1))
                    let waiting = store.claimableRewards
                    if waiting > 0 {
                        // Rewards waiting are the one thing on this screen that
                        // must not be missed: red, not another gold pill beside
                        // a gold glyph in a gold ring next to the gold wallet.
                        Text("\(waiting)")
                            .font(Theme.numeric(10).weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .frame(minWidth: 16)
                            .background(Capsule().fill(Theme.danger))
                            .overlay(Capsule().strokeBorder(Theme.ink, lineWidth: 1))
                            .offset(x: 6, y: -4)
                    }
                }
                // The 36pt disc is the look; the target is 44.
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(PlateButtonStyle())
            // The wallet is the way into the bazaar, as the genre has it.
            Button {
                Juice.haptic(.light)
                AudioLibrary.shared.play(.uiTap)
                showShop = true
            } label: {
                HStack(spacing: 6) {
                    WalletBar(wallet: player.wallet)
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Theme.gold))
                        .overlay(Circle().strokeBorder(Theme.goldPlate, lineWidth: 1))
                }
            }
            // The wallet keeps its full width on a notched landscape frame;
            // a long summoner name gives way before a truncated number does.
            .layoutPriority(1)
            .buttonStyle(PlateButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(Theme.ink.opacity(0.62))
                .overlay(Capsule().strokeBorder(Theme.stroke.opacity(0.7), lineWidth: 1))
        )
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    // MARK: - Landmarks

    private func plaque(_ landmark: Landmark) -> some View {
        let level = store.player.level
        let unlocked = landmark.isUnlocked(atLevel: level)
        let tier = landmark.tier(atLevel: level)
        let accent = Color(hex: landmark.accentHex)
        let active = unlocked && hasSomethingToDo(landmark)

        return Button {
            tap(landmark, unlocked: unlocked)
        } label: {
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [accent.opacity(active ? (pulse ? 0.6 : 0.3) : 0.12), .clear],
                                center: .center, startRadius: 2, endRadius: 48
                            )
                        )
                        .frame(width: 96, height: 96)

                    Circle()
                        .fill(Theme.panelPlate)
                        .frame(width: 56, height: 56)
                        .overlay(Circle().strokeBorder(accent.opacity(unlocked ? 0.95 : 0.35), lineWidth: 2))
                        .overlay(Circle().strokeBorder(Theme.bevel, lineWidth: 1).padding(2))
                        .shadow(color: accent.opacity(active ? (pulse ? 0.8 : 0.35) : 0.15), radius: active ? 14 : 5)

                    Image(systemName: unlocked ? landmark.systemImage : "lock.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(unlocked ? accent : Theme.textSecondary)
                        .shadow(color: .black.opacity(0.6), radius: 2, y: 1)

                    if unlocked, let badge = badge(for: landmark) {
                        HStack(spacing: 2) {
                            Image(systemName: badge.glyph)
                                .font(.system(size: 8, weight: .black))
                            Text(badge.text)
                                .font(Theme.numeric(10))
                        }
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(active ? Theme.gold : Theme.textSecondary))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .frame(width: 74, height: 64)
                    }

                    if tier > 1 {
                        HStack(spacing: 2) {
                            ForEach(0..<tier, id: \.self) { _ in
                                Image(systemName: "diamond.fill")
                                    .font(.system(size: 6, weight: .black))
                                    .foregroundStyle(Theme.gold)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .frame(width: 56, height: 68)
                    }
                }

                Text(landmark.title)
                    .font(Theme.body(12).weight(.heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(
                        // A plate, like every other chip in the app: a hairline
                        // in the building's own accent and a shadow, so the
                        // name reads off a sunset painting.
                        Capsule().fill(Theme.ink.opacity(0.8))
                            .overlay(Capsule().strokeBorder(accent.opacity(0.6), lineWidth: 1))
                            .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    )

                if !unlocked {
                    Text("Level \(landmark.unlockLevel)")
                        .font(Theme.body(9).weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .buttonStyle(PlateButtonStyle())
        .opacity(unlocked ? 1 : 0.72)
        .offset(x: shaking == landmark.id ? 5 : 0)
        .animation(.default.speed(3), value: shaking)
    }

    /// What a landmark shows on its plaque: the thing you have to spend there,
    /// with the glyph that quantity wears everywhere else in the game, because
    /// a bare gold pill of "5" on every plaque says nothing.
    private func badge(for landmark: Landmark) -> (glyph: String, text: String)? {
        let player = store.player
        switch landmark.destination {
        case .campaign:
            return (glyph: "bolt.fill", text: "\(player.wallet.energy)")
        case .summon:
            let scrolls = ScrollType.allCases.reduce(0) { $0 + player.wallet.count(of: $1) }
            guard scrolls > 0 else { return nil }
            return (glyph: "scroll.fill", text: "\(scrolls)")
        case .arena:
            return (glyph: "flame.fill", text: "\(player.arena.attacksRemaining)")
        case .collection, .training:
            return (glyph: "person.3.fill", text: "\(player.units.count)")
        case .labyrinth:
            // The deepest level open across the relic dungeons.
            let deepest = DungeonDatabase.labyrinths.map { player.campaignProgress[$0.id] ?? 0 }.max() ?? 0
            guard deepest > 0 else { return nil }
            return (glyph: "flag.checkered", text: "B\(deepest)")
        case .settings:
            return nil
        }
    }

    /// Whether the landmark should glow: only when a tap there leads somewhere.
    private func hasSomethingToDo(_ landmark: Landmark) -> Bool {
        let player = store.player
        switch landmark.destination {
        case .campaign: return player.wallet.energy >= 5
        case .summon: return ScrollType.allCases.contains { player.wallet.count(of: $0) > 0 }
        case .arena: return player.arena.attacksRemaining > 0
        // Training glows when there is someone to feed and someone to feed to.
        case .training: return player.units.count > 1 && player.units.contains { !$0.isMaxLevel }
        case .labyrinth: return player.wallet.energy >= 6
        case .collection, .settings: return false
        }
    }

    private func tap(_ landmark: Landmark, unlocked: Bool) {
        guard unlocked else {
            Juice.notify(.warning)
            shaking = landmark.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if shaking == landmark.id { shaking = nil }
            }
            return
        }
        Juice.haptic(.light)
        AudioLibrary.shared.play(.uiTap)
        // The chapter's story, once, on the way through the gate rather than
        // on top of the map: the map is a screen the player is trying to use,
        // and a card that lands after it has drawn reads as an interruption.
        if landmark.destination == .campaign, let chapter = unseenIntroChapter {
            pendingIntro = chapter
            return
        }
        onOpen(landmark.destination)
    }

    // MARK: - The guided opening

    /// The chapter whose intro card has not been shown yet, or nil.
    private var unseenIntroChapter: Chapter? {
        let chapter = CampaignView.currentChapter(for: store.player)
        guard !chapter.intro.isEmpty, !store.hasSeenChapterIntro(chapter.id) else { return nil }
        return chapter
    }

    /// One step of the opening: a caret on the thing to press and a line under
    /// it, plus the way out. There is no "next" — the caret moves when the
    /// player does the thing, and nothing here is tappable except Skip.
    @ViewBuilder
    private func guide(
        _ step: FirstHourStep,
        frame: CGRect,
        full: CGSize,
        insets: EdgeInsets,
        size: CGSize
    ) -> some View {
        let landmark = IslandDatabase.landmarks.first { $0.id == step.landmarkID }
        // What the caret has to touch. A plaque is drawn from its anchor less
        // 0.055 of the painting's height and stands 56pt of disc plus a name
        // chip tall, so its edge is about 60pt from that centre.
        let target: CGPoint = landmark.map { mark in
            CGPoint(
                x: frame.minX + mark.anchor.x * frame.width - insets.leading,
                y: frame.minY + (mark.anchor.y - 0.055) * frame.height - insets.top
            )
        } ?? CGPoint(
            // No building for this one: it is the Collection tab. An iPhone
            // lays a landscape tab bar out as one centred row rather than five
            // equal columns, so the fifth item sits a little right of centre
            // instead of at 0.9 of the width. The caret is aimed at 0.78 and
            // the line names the tab, which is what actually finds it.
            x: 0.78 * full.width - insets.leading,
            y: size.height
        )
        let reach: CGFloat = landmark == nil ? 0 : 60
        let gap: CGFloat = 6
        let caret: CGFloat = 13
        // Under the plaque when the whole box fits under it, over it when it
        // does not: the Gate sits low enough on the painting that its pointer
        // would otherwise hang behind the tab bar.
        let below = landmark != nil
            && target.y + reach + gap + caret + 2 + Self.guidePlate <= size.height - 6
        let caretY = below
            ? target.y + reach + gap + caret / 2
            : target.y - reach - gap - caret / 2
        let plateY = below
            ? target.y + reach + gap + caret + 2 + Self.guidePlate / 2
            : target.y - reach - gap - caret - 2 - Self.guidePlate / 2
        // The plate is 240 wide and the Hall of Ka stands close to the left
        // edge, so the plate is kept on screen while the caret stays on the
        // building.
        let plateX = min(
            max(target.x, Self.guideWidth / 2 + 8),
            max(size.width - Self.guideWidth / 2 - 8, Self.guideWidth / 2 + 8)
        )

        Image(systemName: below ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
            .font(.system(size: caret, weight: .black))
            .foregroundStyle(Theme.gold)
            .shadow(color: .black.opacity(0.7), radius: 2, y: 1)
            // Bobs toward what it points at, on the same repeating animation
            // the active plaques glow with.
            .offset(y: pulse ? (below ? 3 : -3) : 0)
            .position(x: target.x, y: caretY)
            .allowsHitTesting(false)

        guideLine(step)
            .frame(width: Self.guideWidth, height: Self.guidePlate)
            .position(x: plateX, y: plateY)
            // Inert, like every other painted thing on this screen: the plate
            // floats over a plaque and neither `.clipShape` nor a capsule
            // clips hit-testing, so a tap on it has to reach the building.
            .allowsHitTesting(false)

        skipChip
            // Clear of the header: that plate is 60pt tall under a 6pt top
            // padding, and a chip centred at 72 put its top edge inside the
            // wallet button. This one is drawn after the header, so an overlap
            // is the header losing its taps, not a cosmetic one.
            .position(x: size.width - 52, y: 84)
    }

    private func guideLine(_ step: FirstHourStep) -> some View {
        Text(step.line)
            .font(Theme.body(11).weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(Theme.ink.opacity(0.88))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                            .strokeBorder(Theme.gold.opacity(0.7), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
            )
    }

    /// Skip, under the header rather than on the pointer, because the pointer
    /// has to stay inert for the building underneath it.
    private var skipChip: some View {
        Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            store.skipFirstHour()
        } label: {
            Text("Skip guide")
                .font(Theme.body(10).weight(.bold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(Theme.ink.opacity(0.7))
                        .overlay(Capsule().strokeBorder(Theme.stroke.opacity(0.8), lineWidth: 1))
                )
        }
        .buttonStyle(PlateButtonStyle())
    }
}

// MARK: - The guided opening

/// The first hour, as four things to do in order: summon somebody, take them
/// through the gate, put a relic on them, feed them.
///
/// There is no state machine and nothing to advance. `current(for:)` reads the
/// save and answers what the player has not done yet, because a counter that
/// has to be stepped from every screen in the game goes wrong the first time a
/// call site forgets — and because a save made before any of this existed then
/// lands on the right step instead of starting a veteran at the beginning.
/// What `Player.firstHourStep` is for is the record and the ending: the island
/// writes the step it is showing, and once the field holds `finished` the guide
/// is over for good. That is what Skip writes.
enum FirstHourStep: String, CaseIterable, Sendable {
    case summon
    case fight
    case equip
    case powerUp

    /// Written into `Player.firstHourStep` when the guide is skipped or has
    /// been seen out. A sentinel rather than a fifth case, because it is not a
    /// step and nothing should be able to point at it.
    static let finished = "done"

    /// The line under the caret. Each one names the building and the verb: the
    /// test of the opening is whether somebody who has never seen the game
    /// knows what to press, not whether the prose is nice.
    var line: String {
        switch self {
        case .summon:
            return "Start here. Open a scroll at the Summoning Circle and meet your first god."
        case .fight:
            return "Now the Gate of the Duat. The first stage is two shabti — your team can take them."
        case .equip:
            return "Your new god is wearing nothing. Open Collection, tap them, tap a relic slot."
        case .powerUp:
            return "Hall of Ka: feed the units you don't want to the one you do."
        }
    }

    /// The landmark the caret sits on, or nil when the step's destination is a
    /// tab rather than a building on the island.
    var landmarkID: String? {
        switch self {
        case .summon: return "circle"
        case .fight: return "gate"
        // Relics go on from the unit sheet, and the collection is a tab: there
        // is no building on the painting to point at.
        case .equip: return nil
        case .powerUp: return "hall"
        }
    }

    /// Whether the save says this has been done. Read off what the player
    /// actually owns and has cleared, never off a flag written by the screen
    /// that did it.
    func isDone(for player: Player) -> Bool {
        switch self {
        case .summon:
            return player.totalSummons > 0
        case .fight:
            return (player.campaignProgress["duat_1"] ?? 0) >= 1
        case .equip:
            // A new save already wears the starter loadout — `NewGame.create`
            // auto-equips six relics on the starter — so "is anybody wearing a
            // relic" is true before the player has done anything. What the step
            // teaches is that the god they just summoned is bare, so it counts
            // a SECOND unit in relics. It stands down when there is nobody to
            // dress or nothing spare to dress them in: a pointer at a relic the
            // player does not own is a pointer that lies.
            let dressed = player.units.filter { !$0.equippedRelics.isEmpty }.count
            let spare = player.relics.contains { $0.equippedBy == nil }
            return player.units.count < 2 || dressed >= 2 || !spare
        case .powerUp:
            // `QuestService` counts every power-up for the feats, so the answer
            // is already in the save. The level check is for the saves that
            // predate the counters — nothing else raises a unit's level.
            return (player.lifetimeCounters?["power_ups"] ?? 0) > 0
                || player.units.contains { $0.level > 1 }
        }
    }

    /// The step the player is on, or nil when there is nothing left to point
    /// at. The first one not done, so a relic that drops after the guide has
    /// moved on brings the equip step back rather than losing it.
    static func current(for player: Player) -> FirstHourStep? {
        allCases.first { !$0.isDone(for: player) }
    }
}

// MARK: - Chapter intro card

/// The few lines of story a chapter gets, once, on the way into it.
///
/// `Chapter.summary` is the line the map carries every time; `Chapter.intro` is
/// the longer one, and this is the only screen it appears on. It is shown over
/// the chapter's own painting on the way through the gate rather than on top of
/// the campaign map, because the map is a screen the player is trying to use.
/// One tap anywhere goes on, and `Player.seenChapterIntros` means it does not
/// come back.
struct ChapterIntroCard: View {
    let chapter: Chapter
    let onContinue: () -> Void

    /// The chapter's own painting: the first stage's backdrop, which is the
    /// picture the campaign map already shows for it.
    private var painting: String {
        chapter.stages.first?.environment.backdropName ?? ""
    }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Theme.ink.opacity(0.82))
            card
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
        }
        // Tap anywhere: the Enter button says what happens, and everything
        // behind this card is a place the player was already going.
        .contentShape(Rectangle())
        .onTapGesture { onContinue() }
    }

    private var card: some View {
        ZStack(alignment: .bottomLeading) {
            painted
            words
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.goldDim.opacity(0.8), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.7), radius: 12, y: 6)
    }

    @ViewBuilder
    private var painted: some View {
        if BundleImage.exists(painting) {
            BundleImage(name: painting)
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(
                    // The words sit on the left, so the dark runs that way and
                    // the painting keeps its right-hand side.
                    LinearGradient(
                        colors: [Theme.ink.opacity(0.94), Theme.ink.opacity(0.55), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .overlay(
                    LinearGradient(
                        colors: [.clear, Theme.ink.opacity(0.8)],
                        startPoint: .center, endPoint: .bottom
                    )
                )
                // `.clipped()` does not clip hit-testing, and this is scaled to
                // fill: without this it would swallow taps outside the card.
                .allowsHitTesting(false)
        } else {
            Theme.backdrop
                .allowsHitTesting(false)
        }
    }

    private var words: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(chapter.realmName.uppercased())
                .font(Theme.body(10).weight(.black))
                .tracking(1.6)
                .foregroundStyle(Theme.gold)
            Text(chapter.name)
                .font(Theme.title(20))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text(chapter.intro)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                // Forty words on one landscape frame: past about 430pt the
                // line is too long to come back from at this size.
                .frame(maxWidth: 430, alignment: .leading)
            // No Spacer: the block hugs the bottom-left corner, which is where
            // both washes over the painting are darkest. A Spacer here stretched
            // the stack to the card's full height and stood the story up in the
            // one corner the gradients leave bright.
            HStack(spacing: 10) {
                PrimaryButton(title: "Enter", systemImage: "arrow.right") { onContinue() }
                    .frame(width: 170)
                Text("\(chapter.stages.count) stages")
                    .font(Theme.numeric(10))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
