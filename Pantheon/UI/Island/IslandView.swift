import SwiftUI

/// The hub: the island as Summoners War's Isle — a painted diorama the
/// player pans and pinches, whose BUILDINGS are the buttons, with a bubble
/// over any that has something to do, the team standing about and reacting
/// to a tap, the daily offering waiting over the pool, and the player's own
/// decorations on the sand (`Docs/PLAN.md`, *The home island as Summoners
/// War's*, 2026-09-17).
///
/// The painting is `island_bg`, filled to the screen at rest and zoomed up
/// to 1.6× within its pixels (`IslandCamera`); every anchor, footprint,
/// stand and slot is a point of the painting, so the whole island moves as
/// one. The plaques it replaced — a 56-pt disc with an SF symbol over each
/// building — read as a map screen.
struct IslandView: View {
    @EnvironmentObject private var store: GameStore
    /// False while another tab is up; the living layer stops rendering.
    var isActive: Bool = true
    /// The tour's zoom (`-tour-island-zoom`): the camera opens on the circle
    /// at it, so one frame shows the island close.
    var pinnedZoom: CGFloat? = nil
    let onOpen: (IslandDestination) -> Void

    @State private var pulse = false
    @State private var shaking: String?
    /// The building just pressed, for its pop.
    @State private var pressed: String?
    @State private var showShop = false
    @State private var showMissions = false
    @State private var showEvents = false
    @State private var showSocial = false
    /// A guild war attack chosen on the Summoners sheet: the sheet closes,
    /// then the fight opens over the island the way the arena's does.
    @State private var warBattle: BattleContext?
    @State private var showDecor = false
    /// The chapter whose story card is up, held here between the tap on the
    /// gate and the campaign opening behind it.
    @State private var pendingIntro: Chapter?
    @State private var camera = IslandCamera()
    @State private var dragStart: IslandCamera?
    @State private var pinchStart: IslandCamera?
    @State private var magnifying = false
    @State private var reaction: IslandReaction?
    @State private var named: NamedFigure?
    @State private var offering: OfferingToast?
    @State private var burst = false
    @State private var burstOut = false

    /// The figure named for a breath after a tap or a stir.
    private struct NamedFigure: Equatable {
        let id = UUID()
        let index: Int
    }

    /// The daily offering's receipt, up for a few seconds.
    private struct OfferingToast: Equatable {
        let id = UUID()
        let grants: [ShopService.Grant]
    }

    /// Where the daily offering's bubble floats: over the pool's water.
    static let offeringPoint = CGPoint(x: 0.44, y: 0.455)

    /// Where the team stands: open sand below the circle and the beach band
    /// in front of it, measured off the painting like the landmarks' anchors.
    /// Nothing goes below y 0.75. The painting is filled into the frame, so on
    /// a landscape phone y 0.80 puts a figure's feet on the surf line with its
    /// shadow behind the tab bar, and y 0.84 puts them in the sea.
    static let stands: [CGPoint] = [
        CGPoint(x: 0.43, y: 0.63), CGPoint(x: 0.50, y: 0.73),
        CGPoint(x: 0.36, y: 0.72), CGPoint(x: 0.63, y: 0.745)
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

    /// What stands in the sand patches.
    private var placements: [IslandDecorPlacement] {
        IslandDecorService.placements(for: store.player).map { IslandDecorPlacement(slot: $0.slot, decoration: $0.decoration) }
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

    /// The hours the fireflies are out and the braziers matter: the same
    /// hours `daylight` paints blue.
    static func isNight(at date: Date = Date()) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour < 5 || hour >= 20
    }

    /// The painting's pixel size; the anchors are normalised against it. A
    /// 16:9 painting for a landscape phone, which shows its full width and
    /// crops 9% off the top and the bottom at rest.
    static let paintingSize = CGSize(width: 2048, height: 1152)

    var body: some View {
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            let full = CGSize(
                width: geometry.size.width + insets.leading + insets.trailing,
                height: geometry.size.height + insets.top + insets.bottom
            )
            // Painting coordinates are in the full screen; the ZStack lives
            // inside the safe area, hence the shift on everything placed.
            let frame = camera.frame(painting: Self.paintingSize, in: full)
            let shift = CGPoint(x: insets.leading, y: insets.top)
            let hour = Self.daylight()
            let night = Self.isNight()

            ZStack(alignment: .top) {
                // Open sand: a double tap brings the camera home.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { camera = IslandCamera() }
                    }

                // The living layer sits over the painting and under the
                // buildings' bubbles, covering the whole screen like the
                // painting does, and follows the camera through `frame`.
                IslandSceneView(
                    units: standingUnits,
                    stands: Self.stands,
                    decorations: placements,
                    paintingFrame: frame,
                    viewSize: full,
                    lightHex: hour.lightHex,
                    isNight: night,
                    zoom: camera.zoom,
                    reaction: reaction,
                    isActive: isActive,
                    onStir: { index in name(index) }
                )
                .frame(width: full.width, height: full.height)
                .position(x: full.width / 2 - shift.x, y: full.height / 2 - shift.y)
                .allowsHitTesting(false)

                ForEach(IslandDatabase.landmarks) { landmark in
                    building(landmark, frame: frame, shift: shift)
                }

                figureTargets(frame: frame, full: full, shift: shift)

                if ShopService.isDailyAvailable(player: store.player) {
                    offeringBubble(frame: frame, shift: shift)
                }
                if burst {
                    Circle()
                        .strokeBorder(Theme.gold, lineWidth: 3)
                        .frame(width: 44, height: 44)
                        .scaleEffect(burstOut ? 3.2 : 0.6)
                        .opacity(burstOut ? 0 : 0.9)
                        .position(point(Self.offeringPoint, frame: frame, shift: shift))
                        .allowsHitTesting(false)
                }

                header

                if let offering {
                    offeringToast(offering)
                }

                // The guided opening is Athena's now (`GuideOverlay`, put on
                // the whole shell in RootView): she says the line, and her
                // caret finds this island's buildings through the anchors the
                // buildings register.

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
            .background(backdrop(frame: frame, full: full, hour: hour).ignoresSafeArea())
            .simultaneousGesture(panGesture(full: full))
            .simultaneousGesture(pinchGesture(full: full, shift: shift))
            .animation(.easeInOut(duration: 0.25), value: pendingIntro)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: offering)
            .onAppear {
                if let pinnedZoom, let circle = IslandDatabase.landmarks.first(where: { $0.id == "circle" }) {
                    camera = IslandCamera.aimed(at: circle.footprint.centre, zoom: pinnedZoom, painting: Self.paintingSize, in: full)
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .sheet(isPresented: $showShop) {
            ShopView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showMissions) {
            MissionsView()
                .environmentObject(store)
        }
        .sheet(isPresented: $showEvents) {
            EventsView(onClaim: { _ in store.claimEventGift() })
                .environmentObject(store)
        }
        .sheet(isPresented: $showSocial) {
            SocialView(
                social: store.social,
                onAttack: { target in
                    showSocial = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { warBattle = .guildWar(target) }
                },
                onClaim: { grants in _ = store.receive(grants) }
            )
            .environmentObject(store)
        }
        .fullScreenCover(item: $warBattle) { context in
            if case .guildWar(let target) = context, let engine = store.startWarAttack(target) {
                BattleView(model: BattleViewModel(engine: engine, context: context, store: store))
                    .environmentObject(store)
            } else {
                EmptyState(icon: "person.3", title: "No team", message: "Set an offence team in the Arena first.")
                    .onTapGesture { warBattle = nil }
            }
        }
        .sheet(isPresented: $showDecor) {
            IslandDecorView()
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

    /// A point of the painting in the safe-area ZStack's coordinates.
    private func point(_ anchor: CGPoint, frame: CGRect, shift: CGPoint) -> CGPoint {
        CGPoint(x: frame.minX + anchor.x * frame.width - shift.x, y: frame.minY + anchor.y * frame.height - shift.y)
    }

    // MARK: - The camera's gestures

    /// One finger pans. A tap never moves six points, so the buildings and
    /// the figures keep their taps; a pinch in progress owns the camera.
    private func panGesture(full: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !magnifying else { return }
                let start = dragStart ?? camera
                if dragStart == nil { dragStart = start }
                var next = start
                next.pan.width += value.translation.width
                next.pan.height += value.translation.height
                camera = next
            }
            .onEnded { _ in
                dragStart = nil
                camera.settle(painting: Self.paintingSize, in: full)
            }
    }

    /// Two fingers zoom about the point they landed on.
    private func pinchGesture(full: CGSize, shift: CGPoint) -> some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.01)
            .onChanged { value in
                magnifying = true
                let start = pinchStart ?? camera
                if pinchStart == nil { pinchStart = start }
                let anchor = CGPoint(x: value.startLocation.x + shift.x, y: value.startLocation.y + shift.y)
                camera = start.zoomed(by: value.magnification, about: anchor, painting: Self.paintingSize, in: full)
            }
            .onEnded { _ in
                pinchStart = nil
                dragStart = nil
                magnifying = false
                camera.settle(painting: Self.paintingSize, in: full)
            }
    }

    // MARK: - Backdrop

    @ViewBuilder
    private func backdrop(frame: CGRect, full: CGSize, hour: (overlay: Color, opacity: Double, lightHex: String)) -> some View {
        if BundleImage.exists("island_bg") {
            ZStack {
                // The painting at the camera's frame — an explicit size, so
                // nothing here is a fill image measuring larger than the
                // screen (the gotcha in CLAUDE.md).
                BundleImage(name: "island_bg")
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                // The hour's colour over the painting: nothing by day, warm
                // at dusk, blue at night.
                Rectangle()
                    .fill(hour.overlay)
                    .opacity(hour.opacity)
                    .blendMode(.multiply)
                // The painting pales toward its top and bottom edges so the
                // header and the chips read against it: cream, like the
                // plates they sit on, never a dark wash under ink.
                LinearGradient(
                    colors: [Theme.plate.opacity(0.55), .clear, .clear, Theme.plate.opacity(0.7)],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .frame(width: full.width, height: full.height)
            .clipped()
            // `.clipped()` does not clip hit-testing, and a filled Rectangle
            // is hit-testable even when it is clear: the whole backdrop is
            // inert, and the empty-sand double tap is a layer of its own.
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

    /// The player's card — the leader's face in a ring, the name, the level
    /// and the experience bar, as the genre's top-left card has it — then
    /// the missions scroll, the chisel for the decorations, and the wallet
    /// that opens the bazaar.
    private var header: some View {
        let player = store.player
        return HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                leaderPortrait
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.displayName)
                        .font(Theme.title(16))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
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
                        .frame(width: 120)
                        // One line, always: "1240/2050" offers a break after
                        // the slash, and a wrap here would add a second line
                        // to the header on a narrow frame rather than truncate.
                        Text("\(player.experience)/\(player.experienceToNextLevel)")
                            .font(Theme.numeric(10))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
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
                    roundGlyph("scroll.fill")
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
                            .overlay(Capsule().strokeBorder(Theme.surfaceHigh, lineWidth: 1))
                            .offset(x: 6, y: -4)
                    }
                }
                // The 36pt disc is the look; the target is 44.
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(PlateButtonStyle())
            // Summoners: friends, mail, the guild and the ranks; requests
            // and unclaimed mail counted in red like the missions.
            Button {
                Juice.haptic(.light)
                AudioLibrary.shared.play(.uiTap)
                showSocial = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    roundGlyph("person.2.fill")
                    let pending = store.social.pendingCount
                    if pending > 0 {
                        Text("\(pending)")
                            .font(Theme.numeric(10).weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .frame(minWidth: 16)
                            .background(Capsule().fill(Theme.danger))
                            .overlay(Capsule().strokeBorder(Theme.surfaceHigh, lineWidth: 1))
                            .offset(x: 6, y: -4)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(PlateButtonStyle())
            // Events: the week's calendar beside the missions, with the
            // Festival's unclaimed gifts counted the same red way.
            Button {
                Juice.haptic(.light)
                AudioLibrary.shared.play(.uiTap)
                showEvents = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    roundGlyph("calendar")
                    let gifts = EventCalendar.claimableCount(player: player)
                    if gifts > 0 {
                        Text("\(gifts)")
                            .font(Theme.numeric(10).weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .frame(minWidth: 16)
                            .background(Capsule().fill(Theme.danger))
                            .overlay(Capsule().strokeBorder(Theme.surfaceHigh, lineWidth: 1))
                            .offset(x: 6, y: -4)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(PlateButtonStyle())
            // The chisel: the island's decorations.
            Button {
                Juice.haptic(.light)
                AudioLibrary.shared.play(.uiTap)
                showDecor = true
            } label: {
                roundGlyph("hammer.fill")
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
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Theme.plate.opacity(0.62))
                .overlay(Capsule().strokeBorder(Theme.stroke.opacity(0.7), lineWidth: 1))
        )
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    private func roundGlyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Theme.gold)
            .frame(width: 36, height: 36)
            .background(Circle().fill(Theme.surface))
            .overlay(Circle().strokeBorder(Theme.goldPlate, lineWidth: 1))
    }

    /// The campaign leader's face in a gold ring: the Isle's avatar, in our
    /// own art. The card is cropped to its top, where the face is.
    private var leaderPortrait: some View {
        let leader = standingUnits.first
        return ZStack {
            Circle().fill(Theme.surface)
            if let leader {
                BundleImage(name: leader.blueprint.model.portraitName(awakened: leader.unit.isAwakened), renderedAt: 44)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 40, height: 40, alignment: .top)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.goldDim)
            }
        }
        .frame(width: 40, height: 40)
        .overlay(Circle().strokeBorder(Theme.goldPlate, lineWidth: 2))
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    }

    // MARK: - The buildings

    /// A painted building as the button it is in the genre: its footprint is
    /// the tap target, a light pulses on the sand under it when there is
    /// something to do there, a bubble bobs over it with the glyph and count
    /// of what it wants, and a small chip under it names it — the owner's
    /// players are new to the island and the painting names nothing. A tap
    /// pops the chip and the bubble before the screen opens.
    private func building(_ landmark: Landmark, frame: CGRect, shift: CGPoint) -> some View {
        let level = store.player.level
        let unlocked = landmark.isUnlocked(atLevel: level)
        let tier = landmark.tier(atLevel: level)
        let accent = Color(hex: landmark.accentHex)
        let active = unlocked && hasSomethingToDo(landmark)
        let footprint = landmark.footprint
        let centre = point(footprint.centre, frame: frame, shift: shift)
        let size = CGSize(width: footprint.size.width * frame.width, height: footprint.size.height * frame.height)
        let top = centre.y - size.height / 2
        let bottom = centre.y + size.height / 2
        let pop: CGFloat = pressed == landmark.id ? 1.12 : 1
        let shake: CGFloat = shaking == landmark.id ? 5 : 0

        return Group {
            if active {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [accent.opacity(pulse ? 0.62 : 0.34), accent.opacity(pulse ? 0.22 : 0.1), .clear],
                            center: .center, startRadius: 0, endRadius: size.width * 0.62
                        )
                    )
                    .frame(width: size.width * 1.3, height: size.height * 0.5)
                    .position(x: centre.x, y: bottom - size.height * 0.06)
                    .allowsHitTesting(false)
            }

            // The building itself is the target. So Athena's caret can find
            // it by name from anywhere (`GuideAnchorKey`).
            Color.clear
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .onTapGesture { tap(landmark, unlocked: unlocked) }
                .guideAnchor("island_\(landmark.id)")
                .position(centre)

            chip(landmark, unlocked: unlocked, tier: tier, accent: accent)
                .scaleEffect(pop)
                .offset(x: shake)
                .onTapGesture { tap(landmark, unlocked: unlocked) }
                .position(x: centre.x, y: bottom + 11)
                .animation(.spring(response: 0.22, dampingFraction: 0.45), value: pressed)
                .animation(.default.speed(3), value: shaking)

            if active, let badge = badge(for: landmark) {
                IslandBubble(glyph: badge.glyph, text: badge.text, tint: accent)
                    .scaleEffect(pop)
                    .offset(y: pulse ? -3 : 3)
                    .onTapGesture { tap(landmark, unlocked: unlocked) }
                    .position(x: centre.x, y: top - 16)
                    .animation(.spring(response: 0.22, dampingFraction: 0.45), value: pressed)
            }
        }
    }

    /// The building's name on a cream chip, with a lock and the level it
    /// wants while it is shut, and a diamond per tier past the first.
    private func chip(_ landmark: Landmark, unlocked: Bool, tier: Int, accent: Color) -> some View {
        HStack(spacing: 4) {
            if !unlocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .black))
            }
            Text(unlocked ? landmark.title : "\(landmark.title) · Lv.\(landmark.unlockLevel)")
                .font(Theme.body(10).weight(.heavy))
                .lineLimit(1)
            if tier > 1 {
                HStack(spacing: 1) {
                    ForEach(0..<tier, id: \.self) { _ in
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 5, weight: .black))
                            .foregroundStyle(Theme.gold)
                    }
                }
            }
        }
        .foregroundStyle(unlocked ? Theme.textPrimary : Theme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Theme.plate.opacity(0.88))
                .overlay(Capsule().strokeBorder(accent.opacity(unlocked ? 0.8 : 0.3), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        )
    }

    /// What a building's bubble carries: the thing you have to spend there,
    /// with the glyph that quantity wears everywhere else in the game.
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
            guard deepest > 0 else { return (glyph: "bolt.fill", text: "\(player.wallet.energy)") }
            return (glyph: "flag.checkered", text: "B\(deepest)")
        case .settings:
            return nil
        }
    }

    /// Whether the building lights and carries a bubble: only when a tap
    /// there leads somewhere.
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

    /// The press: a pop on the chip and the bubble, the tap sound, and the
    /// screen a beat later, so the pop is seen — the genre's order.
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
        pressed = landmark.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            if pressed == landmark.id { pressed = nil }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            // The chapter's story, once, on the way through the gate rather
            // than on top of the map: the map is a screen the player is
            // trying to use, and a card that lands after it has drawn reads
            // as an interruption.
            if landmark.destination == .campaign, let chapter = unseenIntroChapter {
                pendingIntro = chapter
                return
            }
            onOpen(landmark.destination)
        }
    }

    /// The chapter whose intro card has not been shown yet, or nil.
    private var unseenIntroChapter: Chapter? {
        let chapter = CampaignView.currentChapter(for: store.player)
        guard !chapter.intro.isEmpty, !store.hasSeenChapterIntro(chapter.id) else { return nil }
        return chapter
    }

    // MARK: - The figures

    /// A tap target over each figure and, for a breath after a tap or a
    /// stir, its name and level over its head.
    private func figureTargets(frame: CGRect, full: CGSize, shift: CGPoint) -> some View {
        let height = full.height * IslandSceneView.figureHeight * camera.zoom
        let units = Array(standingUnits.prefix(Self.stands.count).enumerated())
        return ForEach(units, id: \.element.id) { index, unit in
            let feet = point(Self.stands[index], frame: frame, shift: shift)
            Color.clear
                .frame(width: height * 0.6, height: height * 1.05)
                .contentShape(Rectangle())
                .onTapGesture { poke(index) }
                .position(x: feet.x, y: feet.y - height * 0.5)
            if let named, named.index == index {
                nameplate(unit)
                    .position(x: feet.x, y: feet.y - height - 14)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
    }

    private func nameplate(_ unit: ResolvedUnit) -> some View {
        Text("\(unit.name) · Lv.\(unit.unit.level)")
            .font(Theme.body(11).weight(.heavy))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Theme.plate.opacity(0.92))
                    .overlay(Capsule().strokeBorder(Color(hex: unit.element.accentHex).opacity(0.9), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            )
    }

    private func poke(_ index: Int) {
        Juice.haptic(.light)
        AudioLibrary.shared.play(.uiTap)
        reaction = IslandReaction(index: index)
        name(index)
    }

    private func name(_ index: Int) {
        let plate = NamedFigure(index: index)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { named = plate }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if named == plate {
                withAnimation(.easeOut(duration: 0.3)) { named = nil }
            }
        }
    }

    // MARK: - The daily offering

    /// The bazaar's free daily offering, waiting over the pool as a gold
    /// bubble; a tap claims it where it stands — the same item through the
    /// same `GameStore.buy`, so the two doors cannot pay differently — with
    /// a burst of gold and the grants as tiles for a few seconds.
    private func offeringBubble(frame: CGRect, shift: CGPoint) -> some View {
        IslandBubble(glyph: "gift.fill", text: "Daily offering", tint: Theme.gold, filled: true)
            .offset(y: pulse ? -3 : 3)
            .onTapGesture { claimOffering() }
            .position(point(Self.offeringPoint, frame: frame, shift: shift))
    }

    private func claimOffering() {
        guard let item = ShopService.item("daily_offering"), let grants = store.buy(item) else { return }
        Juice.notify(.success)
        AudioLibrary.shared.play(.uiConfirm)
        burstOut = false
        burst = true
        withAnimation(.easeOut(duration: 0.7)) { burstOut = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { burst = false }
        let toast = OfferingToast(grants: grants)
        offering = toast
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
            if offering == toast { offering = nil }
        }
    }

    private func offeringToast(_ toast: OfferingToast) -> some View {
        VStack(spacing: 6) {
            Text("THE POOL'S OFFERING")
                .font(Theme.title(12))
                .tracking(1.4)
                .foregroundStyle(Theme.gold)
            HStack(spacing: 10) {
                ForEach(Array(toast.grants.enumerated()), id: \.offset) { _, grant in
                    RewardTile(grant: grant, size: 52)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).fill(Theme.plate.opacity(0.94)))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.goldPlate, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .padding(.top, 64)
        .transition(.move(edge: .top).combined(with: .opacity))
        .allowsHitTesting(false)
    }
}

// MARK: - The camera

/// Where the island's painting lies on the screen: a zoom (1 at rest, the
/// painting filling the screen; up to 1.6, the most its pixels allow) and a
/// pan in points, clamped so the painting always covers the screen.
struct IslandCamera: Equatable {
    var zoom: CGFloat = 1
    var pan: CGSize = .zero

    static let minZoom: CGFloat = 1
    static let maxZoom: CGFloat = 1.6

    /// The painting's frame for this camera, in the full screen's coordinates.
    func frame(painting: CGSize, in full: CGSize) -> CGRect {
        Self.clamp(unclampedFrame(painting: painting, in: full), to: full)
    }

    /// The fill frame scaled about the screen's centre and shifted by the pan.
    private func unclampedFrame(painting: CGSize, in full: CGSize) -> CGRect {
        let base = IslandView.fill(painting, in: full)
        let centre = CGPoint(x: full.width / 2, y: full.height / 2)
        return CGRect(
            x: centre.x - (centre.x - base.minX) * zoom + pan.width,
            y: centre.y - (centre.y - base.minY) * zoom + pan.height,
            width: base.width * zoom,
            height: base.height * zoom
        )
    }

    private static func clamp(_ frame: CGRect, to full: CGSize) -> CGRect {
        var clamped = frame
        clamped.origin.x = min(0, max(full.width - frame.width, frame.minX))
        clamped.origin.y = min(0, max(full.height - frame.height, frame.minY))
        return clamped
    }

    /// The pan brought back inside the clamp, so the next drag moves the
    /// painting at once instead of spending its first points on slack.
    mutating func settle(painting: CGSize, in full: CGSize) {
        let free = unclampedFrame(painting: painting, in: full)
        let held = Self.clamp(free, to: full)
        pan.width += held.minX - free.minX
        pan.height += held.minY - free.minY
    }

    /// This camera zoomed by `factor` about a screen point, the painting
    /// under the finger staying under it.
    func zoomed(by factor: CGFloat, about anchor: CGPoint, painting: CGSize, in full: CGSize) -> IslandCamera {
        let newZoom = min(Self.maxZoom, max(Self.minZoom, zoom * factor))
        let before = frame(painting: painting, in: full)
        let under = CGPoint(x: (anchor.x - before.minX) / before.width, y: (anchor.y - before.minY) / before.height)
        var next = IslandCamera(zoom: newZoom, pan: .zero)
        let centred = next.unclampedFrame(painting: painting, in: full)
        next.pan = CGSize(
            width: anchor.x - under.x * centred.width - centred.minX,
            height: anchor.y - under.y * centred.height - centred.minY
        )
        return next
    }

    /// The camera that puts a point of the painting at the screen's centre,
    /// as near as the clamp allows.
    static func aimed(at point: CGPoint, zoom: CGFloat, painting: CGSize, in full: CGSize) -> IslandCamera {
        var camera = IslandCamera(zoom: min(maxZoom, max(minZoom, zoom)), pan: .zero)
        let centred = camera.unclampedFrame(painting: painting, in: full)
        camera.pan = CGSize(
            width: full.width / 2 - point.x * centred.width - centred.minX,
            height: full.height / 2 - point.y * centred.height - centred.minY
        )
        camera.settle(painting: painting, in: full)
        return camera
    }
}

// MARK: - Bubbles

/// The genre's floating marker over a building: a small plate with a glyph
/// and a count and a tail pointing down, bobbing. Gold and filled for the
/// daily offering.
struct IslandBubble: View {
    let glyph: String
    let text: String
    var tint: Color = Theme.gold
    var filled: Bool = false

    var body: some View {
        VStack(spacing: -1) {
            HStack(spacing: 4) {
                Image(systemName: glyph)
                    .font(.system(size: 11, weight: .black))
                Text(text)
                    .font(Theme.numeric(12))
                    .lineLimit(1)
            }
            .foregroundStyle(filled ? Theme.ink : Theme.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(filled ? Theme.gold : Theme.plate.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(filled ? Theme.goldDeep.opacity(0.7) : tint, lineWidth: 1.5)
            )
            BubbleTail()
                .fill(filled ? Theme.gold : tint)
                .frame(width: 10, height: 6)
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
    }
}

/// The bubble's tail: a small triangle pointing down.
struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - The first hour, as four tests

/// The four things the opening asks for — summon somebody, take them through
/// the gate, put a relic on them, feed them — each as a question the SAVE can
/// answer.
///
/// This used to be the guide itself, with a pointer of its own drawn over the
/// island. Athena took the pointing over (`LessonBook`, `GuideOverlay`), and
/// what was worth keeping is these four tests: `LessonBook.opening`'s steps
/// call `isDone(for:)` and nothing else. The reason they are read off what the
/// player owns and has cleared, rather than a flag written by the screen that
/// did it, is that a counter stepped from every screen in the game goes wrong
/// the first time a call site forgets — and that a save made before any of
/// this existed lands on the right step instead of restarting a veteran at
/// the beginning.
enum FirstHourStep: String, CaseIterable, Sendable {
    case summon
    case fight
    case equip
    case powerUp

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

    /// The step the player is on, or nil when all four are done. The first one
    /// not done, so a relic that drops later brings the equip step back rather
    /// than losing it.
    ///
    /// Athena drives her own carets from `LessonBook` now, so nothing in the
    /// app calls this; `SaveGameTests` does, and it is the one place the four
    /// tests are asserted in order against a real save. That is worth keeping.
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
            // A cream veil over the island, not a blackout: the card is the
            // one thing left in focus, in the palette the rest of it wears.
            Rectangle()
                .fill(Theme.plate.opacity(0.82))
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
            // `PaintingFill` reports exactly the card's size; a fill image
            // under a flexible frame reports the painting's own.
            PaintingFill(name: painting)
                .overlay(
                    // The words sit on the left, so the cream runs that way
                    // and the painting keeps its right-hand side. The words
                    // are ink, so the wash under them LIGHTENS; the dark one
                    // it replaces put ink on ink.
                    LinearGradient(
                        colors: [Theme.plate.opacity(0.94), Theme.plate.opacity(0.55), .clear],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .overlay(
                    LinearGradient(
                        colors: [.clear, Theme.plate.opacity(0.8)],
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
            // both washes over the painting are palest. A Spacer here stretched
            // the stack to the card's full height and stood the story up in the
            // one corner the gradients leave unwashed.
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
