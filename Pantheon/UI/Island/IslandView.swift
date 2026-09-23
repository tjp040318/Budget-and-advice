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
    /// A guild war attack chosen on the Allies sheet: the sheet closes,
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
    /// The figure named for a breath: its plate's place is kept clear of
    /// chips and bubbles from the moment it is set (`IslandKeepOut`)…
    @State private var named: NamedFigure?
    /// …and the plate itself is drawn only while this is true: a beat after
    /// `named`, so what it lands on has stepped back first, and a beat before
    /// `named` clears, so nothing steps back in under a plate still fading.
    @State private var nameplateDrawn = false
    /// What of Athena is up — her plate, her caret's call-out — so the chips
    /// and bubbles under her stand back (`GuideStage`, run 224).
    @ObservedObject private var guide = GuideStage.shared
    @State private var offering: OfferingToast?
    @State private var burst = false
    @State private var burstOut = false
    /// Where the claimed bubble stood: the burst plays there, not where the
    /// bubble would stand now — the scroll the offering pays gives the
    /// circle a bubble of its own and moves the offering's spot.
    @State private var burstAt: CGPoint = .zero

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

    /// The daily offering's bubble: its words, and its size as drawn —
    /// Manrope-Bold at 12 sets "Daily Offering" in 79 points, and the painted
    /// gift, the gap and the padding are 36 more. Measured rather than
    /// reckoned at `IslandBubble.size`'s 7.6 a character, which is a
    /// figure's width and errs thirty points wide on words: too wide to
    /// stand the bubble six points from its neighbour (`offeringSpot`).
    private static let offeringWords = "Daily Offering"
    private static let offeringSize = CGSize(width: 116, height: 31)

    /// Where the team stands: open sand below the circle and the beach band
    /// in front of it, measured off the painting like the landmarks' anchors.
    /// Nothing goes below y 0.75. The painting is filled into the frame, so on
    /// a landscape phone y 0.80 puts a figure's feet on the surf line with its
    /// shadow behind the tab bar, and y 0.84 puts them in the sea.
    ///
    /// The leader's mark was (0.43, 0.63), right under the Summoning
    /// Circle's name chip: run 216 photographed the fourth figure's body
    /// behind the capsule at both zooms. (0.47, 0.67) is the open sand
    /// between the palms and the scrub, and a figure's head there clears the
    /// chip by two points at rest and at the tour's 1.5 (measured on a port
    /// of this layout, `restAnchorY` 0.4 and a 323-point frame).
    static let stands: [CGPoint] = [
        CGPoint(x: 0.47, y: 0.67), CGPoint(x: 0.50, y: 0.73),
        CGPoint(x: 0.36, y: 0.72), CGPoint(x: 0.63, y: 0.745)
    ]

    /// Where the painting's spare height goes at rest: 0.5 would centre it,
    /// 0.4 lets 40% of the overflow off the top and 60% off the bottom.
    ///
    /// Since run 216 the tab bar is LAID OUT under the island (RootView), so
    /// the island is a 323-point frame, not the 402-point window it filled
    /// with the bar drawn over its foot. Centred in 323 the header covered
    /// the Hall of Ka's roof and pushed its bubble under the header; at 0.4
    /// every building stands whole under the header, the Gate's and the
    /// Arena's name chips (which the old bar hid) sit three points over the
    /// band, and the figures keep twenty points of sand under them.
    static let restAnchorY: CGFloat = 0.4

    /// The header capsule's foot in the safe area: six over it, six inside
    /// it round a 44-point row. Chips and bubbles are held under it.
    private static let headerBottom: CGFloat = 62

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

    /// The safe width at which the header holds all of itself (a 16's 734
    /// and a 16 Pro's 750 do; `header(compact:)` says what gives below it).
    static let roomyHeaderWidth: CGFloat = 720

    /// The painting's pixel size; the anchors are normalised against it. A
    /// 16:9 painting for a landscape phone, which shows its full width at
    /// rest; in the island's 323-point frame over the tab bar a third of its
    /// height is cropped, 40% of that off the top (`restAnchorY`).
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
            // Where a chip or a bubble steps back this frame: under the named
            // figure's plate for the breath it is up (run 216: "Zeus · Lv.12"
            // over the start of "Summoning Circle"), under Athena's caret, and
            // everywhere while she speaks (run 224). Her call-outs come in
            // the window's coordinates; the island's are this reader's.
            let window = geometry.frame(in: .global).origin
            let keepOut = IslandKeepOut(
                plate: nameplateRect(frame: frame, full: full, shift: shift),
                callouts: guide.callouts.values.map { $0.offsetBy(dx: -window.x, dy: -window.y) },
                speaking: guide.isSpeaking
            )

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
                    building(landmark, frame: frame, shift: shift, bounds: geometry.size, keepOut: keepOut)
                }

                figureTargets(frame: frame, full: full, shift: shift)

                if ShopService.isDailyAvailable(player: store.player) {
                    offeringBubble(frame: frame, shift: shift, bounds: geometry.size, keepOut: keepOut)
                }
                if burst {
                    Circle()
                        .strokeBorder(Theme.gold, lineWidth: 3)
                        .frame(width: 44, height: 44)
                        .scaleEffect(burstOut ? 3.2 : 0.6)
                        .opacity(burstOut ? 0 : 0.9)
                        .position(burstAt)
                        .allowsHitTesting(false)
                }

                header(compact: geometry.size.width < Self.roomyHeaderWidth)

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

    /// Where an image of `image` size lands when drawn to fill `container`:
    /// scaled as SwiftUI's `.aspectRatio(contentMode: .fill)` scales it,
    /// centred across and held at `restAnchorY` down. The backdrop draws
    /// the painting at the camera's frame, which starts from this, so the
    /// anchors and the pixels agree.
    static func fill(_ image: CGSize, in container: CGSize) -> CGRect {
        let scale = max(container.width / image.width, container.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) * restAnchorY,
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
                // A little shade under the header and nothing else
                // (2026-09-23, run 216). The painting paled to cream top and
                // bottom while the header and the chips were cream plates;
                // the header is dark glass now and the bar under the island
                // is opaque, and the cream wash only turned the top fifth of
                // the sea milky. The sea keeps its blue.
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.black.opacity(0.25), Color.black.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .frame(height: 70)
                    Spacer(minLength: 0)
                }
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
    /// four painted doors (the missions, the allies, the events and the
    /// chisel for the decorations) and the wallet that opens the bazaar.
    ///
    /// On a phone narrower than `roomyHeaderWidth` inside its safe area (an
    /// SE's 667, a mini's 712) the header does not fit whole: the card at its
    /// least, the four doors and the purse with the energy's countdown come
    /// to about 700 points. There the purse leaves out the laurels — the
    /// arena's currency, on the arena's own strip — and the doors stand in
    /// 40-point targets instead of 44.
    private func header(compact: Bool) -> some View {
        let player = store.player
        let target: CGFloat = compact ? 40 : 44
        return HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                leaderPortrait
                VStack(alignment: .leading, spacing: 3) {
                    // 16 points, shrinking no further than the title floor
                    // (0.82 of 16 is 13.1) before a long name gives way.
                    // Carved gold on the glass, like every name over art.
                    Text(player.displayName)
                        .font(Theme.title(16))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .carved(glow: false)
                    // The level at its own width and the bar taking what is
                    // left, 44 to 120 points (2026-09-22, phase B). The row
                    // was "Lv.12", a fixed 120-point bar and "1240/2050"
                    // side by side, and in run 211's frame the header had
                    // squeezed both numbers to nothing and left the bar
                    // alone. The experience in numbers is the genre's
                    // detail, not its card: it is in the accessibility label.
                    // The level is the pale gold that reads on glass, and the
                    // bar the glass's own meter (run 216: goldDim on the
                    // cream capsule was faint).
                    HStack(spacing: 8) {
                        Text("Lv.\(player.level)")
                            .font(Theme.numeric(12))
                            .foregroundStyle(Theme.onGlassGold)
                            .lineLimit(1)
                            .fixedSize()
                        GlassMeter(
                            value: Double(player.experience),
                            maximum: Double(player.experienceToNextLevel),
                            tint: Theme.gold,
                            height: 5
                        )
                        .frame(minWidth: 44, maxWidth: 120)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(player.displayName), level \(player.level), \(player.experience) of \(player.experienceToNextLevel) experience")
            Spacer()
            // The four doors, painted (2026-09-22, phase B; PLAN.md, *The
            // painted doors*): each object from the tab bar's sheet in the
            // same dark socket, 36 points in a 44-point target. They stand
            // six points apart rather than the header's twelve: twenty
            // points between four 36-point medallions read as four loose
            // buttons, and in run 211's frame the player's card beside them
            // was squeezed until the level and the experience numbers either
            // side of its bar were gone. Six, not four, so the missions'
            // red count clears the allies' rim (run 216).
            HStack(spacing: 6) {
                // Missions: the scroll beside the wallet, with what is waiting.
                Button {
                    Juice.haptic(.light)
                    AudioLibrary.shared.play(.uiTap)
                    showMissions = true
                } label: {
                    door("scroll.fill", art: "missions", title: "Missions", waiting: store.claimableRewards, target: target)
                }
                .buttonStyle(PlateButtonStyle())
                // Allies: friends, mail, the guild and the ranks; requests
                // and unclaimed mail counted in red like the missions.
                Button {
                    Juice.haptic(.light)
                    AudioLibrary.shared.play(.uiTap)
                    showSocial = true
                } label: {
                    door("person.2.fill", art: "allies", title: "Allies", waiting: store.social.pendingCount, target: target)
                }
                .buttonStyle(PlateButtonStyle())
                // Events: the week's calendar beside the missions, with the
                // Festival's unclaimed gifts counted the same red way.
                Button {
                    Juice.haptic(.light)
                    AudioLibrary.shared.play(.uiTap)
                    showEvents = true
                } label: {
                    door("calendar", art: "events", title: "Events", waiting: EventCalendar.claimableCount(player: player), target: target)
                }
                .buttonStyle(PlateButtonStyle())
                // The chisel: the island's decorations.
                Button {
                    Juice.haptic(.light)
                    AudioLibrary.shared.play(.uiTap)
                    showDecor = true
                } label: {
                    door("hammer.fill", art: "decor", title: "Decorations", waiting: 0, target: target)
                }
                .buttonStyle(PlateButtonStyle())
            }
            // The wallet is the way into the bazaar, as the genre has it.
            Button {
                Juice.haptic(.light)
                AudioLibrary.shared.play(.uiTap)
                showShop = true
            } label: {
                IslandPurse(wallet: player.wallet, showsLaurels: !compact)
            }
            // The wallet keeps its full width on a notched landscape frame;
            // a long demigod's name gives way before a truncated number does.
            .layoutPriority(1)
            .buttonStyle(PlateButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        // Dark glass, the one material of the doors' sockets and the purse's
        // well (2026-09-23, run 216): the cream capsule at 0.62 was a third
        // material, milky over the sea, with the obelisk's flame and the
        // bubbles ghosting through it. Words over art go on glass.
        .background(GlassPlate(radius: 28, opacity: 0.8))
        .padding(.horizontal, 12)
        .padding(.top, 6)
    }

    /// One of the header's doors: its painted object in the dark socket
    /// (`MedallionIcon` at 36, the glyph in the same socket until the
    /// painting ships) with what is waiting behind it counted in red on its
    /// shoulder, in a 44-point target (40 on a narrow phone). `art` is the
    /// door's `ChromeArt` key; `title` is what VoiceOver reads, since the
    /// medallion is a picture and hides itself from it.
    private func door(_ glyph: String, art: String, title: String, waiting: Int, target: CGFloat) -> some View {
        MedallionIcon(key: art, glyph: glyph, size: 36)
            .overlay(alignment: .topTrailing) {
                if waiting > 0 {
                    // Rewards waiting are the one thing on this screen that
                    // must not be missed: red, not another gold pill beside
                    // a gold object in a gold ring next to the gold wallet.
                    // The white ring reads on the dark socket as it did on
                    // the cream disc.
                    Text("\(waiting)")
                        .font(Theme.numeric(11.5).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .frame(minWidth: 16)
                        .background(Capsule().fill(Theme.danger))
                        .overlay(Capsule().strokeBorder(Theme.surfaceHigh, lineWidth: 1))
                        .offset(x: 8, y: -4)
                }
            }
            .frame(width: target, height: 44)
            .contentShape(Circle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(waiting > 0 ? "\(title), \(waiting) waiting" : title)
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
    ///
    /// The chip and the bubble are held inside the island's frame
    /// (2026-09-23, run 216): at the tour's 1.5 the Hall of Ka's chip slid
    /// under the sensor housing ("all of Ka") and the temple's bubble under
    /// the header. Each is clamped across into the safe width and down under
    /// the header, and a building mostly off the frame across (under
    /// `inViewShare` of its footprint's width on it), or whose centre has
    /// gone under the header or off the foot, drops both rather than pinning
    /// them to an edge over somewhere else. It was the centre across as well
    /// until run 221, whose 1.5 had the Arena of Souls filling the lower
    /// right with neither its bubble nor its name, its centre just past the
    /// edge. `keepOut` is where a chip or a bubble steps back: the named
    /// figure's plate while it is up, Athena's caret, anywhere while she
    /// speaks.
    ///
    /// A chip or a bubble steps back AT ONCE and comes back over 0.2 s (run
    /// 224). Eased both ways, the zoomed island caught a chip fading out
    /// through the plate springing in over it — two half-drawn labels across
    /// the circle's front — and the same whenever Athena's plate rose over
    /// the chips at its edges.
    private func building(_ landmark: Landmark, frame: CGRect, shift: CGPoint, bounds: CGSize, keepOut: IslandKeepOut) -> some View {
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
        let across = min(centre.x + size.width / 2, bounds.width) - max(centre.x - size.width / 2, 0)
        let inView = across >= size.width * Self.inViewShare
            && centre.y >= Self.headerBottom && centre.y <= bounds.height
        // The chip on the building's front step, four points under its
        // footprint's foot (it hung eleven under, on the sand where the
        // leader stands), held in the frame.
        let chipSize = Self.chipSize(landmark, unlocked: unlocked, tier: tier)
        let chipAt = Self.held(CGPoint(x: centre.x, y: bottom + 4), size: chipSize, in: bounds)
        let chipRect = CGRect(x: chipAt.x - chipSize.width / 2, y: chipAt.y - chipSize.height / 2,
                              width: chipSize.width, height: chipSize.height)
        let chipShown = inView && keepOut.allows(chipRect)
        let wants = active ? badge(for: landmark) : nil

        return Group {
            if active {
                // Light on the sand under the building, not paint beside it
                // (run 216: a salmon smear 1.3 times the footprint ran down
                // to the band). A warm-white core and the accent, ADDED to
                // the painting, the building's width and a third its height.
                // A round fall-off squashed to that ellipse, so it reaches
                // nothing at the rim on both axes: a fall-off as wide as the
                // building clipped to an ellipse a third as tall was still
                // bright where the ellipse cut it top and bottom, and run
                // 221 read the lights as stains — a pink band on the arena's
                // wall, a mauve ellipse with hard edges on the Labyrinth's
                // scrub, a cyan edge across the circle's front columns. The
                // accent is held to 0.18 besides.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(hex: "#FFF3D0").opacity(0.22), accent.opacity(pulse ? 0.18 : 0.10), .clear],
                            center: .center, startRadius: 0, endRadius: size.width * 0.5
                        )
                    )
                    .frame(width: size.width, height: size.width)
                    .scaleEffect(x: 1, y: size.height * 0.32 / max(1, size.width))
                    .blendMode(.plusLighter)
                    .position(x: centre.x, y: bottom - size.height * 0.08)
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

            if inView {
                chip(landmark, unlocked: unlocked, tier: tier, accent: accent)
                    .scaleEffect(pop)
                    .offset(x: shake)
                    .opacity(chipShown ? 1 : 0)
                    .allowsHitTesting(chipShown)
                    .onTapGesture { tap(landmark, unlocked: unlocked) }
                    .position(chipAt)
                    .animation(.spring(response: 0.22, dampingFraction: 0.45), value: pressed)
                    .animation(.default.speed(3), value: shaking)
                    .animation(Self.stepBack(to: chipShown), value: chipShown)
            }

            if inView, let wants {
                let bubbleSize = IslandBubble.size(for: wants.text)
                let bubbleAt = Self.held(CGPoint(x: centre.x, y: top - 16), size: bubbleSize, in: bounds)
                let bubbleRect = CGRect(x: bubbleAt.x - bubbleSize.width / 2, y: bubbleAt.y - bubbleSize.height / 2,
                                        width: bubbleSize.width, height: bubbleSize.height)
                let bubbleShown = keepOut.allows(bubbleRect)
                IslandBubble(glyph: wants.glyph, text: wants.text, tint: accent, art: wants.art)
                    .scaleEffect(pop)
                    .offset(y: pulse ? -3 : 3)
                    .opacity(bubbleShown ? 1 : 0)
                    .allowsHitTesting(bubbleShown)
                    .onTapGesture { tap(landmark, unlocked: unlocked) }
                    .position(bubbleAt)
                    .animation(.spring(response: 0.22, dampingFraction: 0.45), value: pressed)
                    .animation(Self.stepBack(to: bubbleShown), value: bubbleShown)
            }
        }
    }

    /// How much of a building's footprint must be across the frame for its
    /// bubble and its name to show (`building`).
    private static let inViewShare: CGFloat = 0.35

    /// A chip's or a bubble's animation for a change in whether it shows:
    /// none on the way out, so whatever is drawn in its place never meets it
    /// half faded, and 0.2 s on the way back (run 224).
    private static func stepBack(to shown: Bool) -> Animation? {
        shown ? .easeOut(duration: 0.2) : nil
    }

    /// A point moved just far enough that a thing of `size` centred on it
    /// stands inside the island's safe frame, eight points from either side
    /// and four from the foot, and under the header.
    private static func held(_ point: CGPoint, size: CGSize, in bounds: CGSize) -> CGPoint {
        let halfWidth = size.width / 2 + 8
        let halfHeight = size.height / 2 + 4
        let x = min(max(point.x, halfWidth), max(halfWidth, bounds.width - halfWidth))
        let y = min(max(point.y, headerBottom + halfHeight), max(headerBottom + halfHeight, bounds.height - halfHeight))
        return CGPoint(x: x, y: y)
    }

    /// A name chip's size, reckoned rather than measured so the clamp and the
    /// plate's test need no layout pass: Manrope ExtraBold at 11 set
    /// "Summoning Circle" in 100 points (run 216's chip measured 114 with its
    /// padding) and "Hall of Ka" in 50, so 6.4 a character plus the padding,
    /// the lock and the tier diamonds errs wide: a clamped chip stops a few
    /// points early, never late.
    private static func chipSize(_ landmark: Landmark, unlocked: Bool, tier: Int) -> CGSize {
        let words = unlocked ? landmark.title : "\(landmark.title) · Lv.\(landmark.unlockLevel)"
        var width = CGFloat(words.count) * 6.4 + 18
        if !unlocked { width += 13 }
        if tier > 1 { width += CGFloat(tier) * 6 + 4 }
        return CGSize(width: width, height: 21)
    }

    /// The building's name on a chip of dark glass rimmed in the building's
    /// colour, with a lock and the level it wants while it is shut, and a
    /// diamond per tier past the first. Glass since run 216: cream chips on
    /// the painting were the one cream thing left between a glass header,
    /// glass bubbles and Athena's glass.
    private func chip(_ landmark: Landmark, unlocked: Bool, tier: Int, accent: Color) -> some View {
        HStack(spacing: 4) {
            if !unlocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .black))
            }
            Text(unlocked ? landmark.title : "\(landmark.title) · Lv.\(landmark.unlockLevel)")
                .font(Theme.body(11).weight(.heavy))
                .lineLimit(1)
                .fixedSize()
            if tier > 1 {
                HStack(spacing: 1) {
                    ForEach(0..<tier, id: \.self) { _ in
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 5, weight: .black))
                            .foregroundStyle(Theme.onGlassGold)
                    }
                }
            }
        }
        .foregroundStyle(unlocked ? Theme.onGlass : Theme.onGlassDim)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(IslandBubble.glassFill)
                .overlay(Capsule().strokeBorder(accent.opacity(unlocked ? 0.85 : 0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        )
    }

    /// What a building's bubble carries: the thing you have to spend there,
    /// with its painted item (`art`, a bundle painting — the energy's bolt,
    /// the summon door's scroll, the arena's shield, the collection's bust,
    /// the relic chest the Labyrinth pays) and the glyph that quantity wears
    /// elsewhere as the fallback. Run 216 had five SF glyphs on cream here,
    /// under a header and over a bar of painted objects.
    private func badge(for landmark: Landmark) -> (glyph: String, text: String, art: String?)? {
        let player = store.player
        let energy = ItemArt.imageName("energy")
        switch landmark.destination {
        case .campaign:
            return (glyph: "bolt.fill", text: "\(player.wallet.energy)", art: energy)
        case .summon:
            let scrolls = ScrollType.allCases.reduce(0) { $0 + player.wallet.count(of: $1) }
            guard scrolls > 0 else { return nil }
            return (glyph: "scroll.fill", text: "\(scrolls)", art: ChromeArt.imageName("summon"))
        case .arena:
            return (glyph: "flame.fill", text: "\(player.arena.attacksRemaining)", art: ChromeArt.imageName("arena"))
        case .collection, .training:
            return (glyph: "person.3.fill", text: "\(player.units.count)", art: ChromeArt.imageName("collection"))
        case .labyrinth:
            // The deepest level open across the relic dungeons.
            let deepest = DungeonDatabase.labyrinths.map { player.campaignProgress[$0.id] ?? 0 }.max() ?? 0
            guard deepest > 0 else { return (glyph: "bolt.fill", text: "\(player.wallet.energy)", art: energy) }
            return (glyph: "flag.checkered", text: "B\(deepest)", art: ItemArt.imageName("relic_cache"))
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
    /// stir, its name and level over its head — never while Athena speaks,
    /// when the island has stepped back behind her plate.
    private func figureTargets(frame: CGRect, full: CGSize, shift: CGPoint) -> some View {
        let height = full.height * IslandSceneView.figureHeight * camera.zoom
        let units = Array(standingUnits.prefix(Self.stands.count).enumerated())
        let plateShown = nameplateDrawn && !guide.isSpeaking
        return ForEach(units, id: \.element.id) { index, unit in
            let feet = point(Self.stands[index], frame: frame, shift: shift)
            Color.clear
                .frame(width: height * 0.6, height: height * 1.05)
                .contentShape(Rectangle())
                .onTapGesture { poke(index) }
                .position(x: feet.x, y: feet.y - height * 0.5)
            if plateShown, let named, named.index == index {
                nameplate(unit)
                    .position(x: feet.x, y: max(feet.y - height - 14, Self.headerBottom + 16))
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
    }

    /// What a figure's plate says: the name without its epithet, as every
    /// card and plate prints it (`nameWithoutEpithet`). The awakened title
    /// made "Anubis, Keeper of the Ash Road · Lv.12" about 240 points wide,
    /// a plate over the whole of the Summoning Circle's front (run 224);
    /// "Anubis · Lv.12" is 90.
    private static func nameplateWords(_ unit: ResolvedUnit) -> String {
        "\(unit.nameWithoutEpithet) · Lv.\(unit.unit.level)"
    }

    /// Where the named figure's plate stands, reckoned the way `chipSize`
    /// reckons a chip, or nil while nobody is named. A name and a level run
    /// narrower than a building's name (Manrope ExtraBold at 11 set "Zeus ·
    /// Lv.12" in 59 points and "Sekhmet · Lv.12" in 81), so 5.8 a
    /// character, and a chip steps back only when the plate is really on it.
    private func nameplateRect(frame: CGRect, full: CGSize, shift: CGPoint) -> CGRect? {
        guard let named else { return nil }
        let units = standingUnits
        guard named.index < units.count, named.index < Self.stands.count else { return nil }
        let height = full.height * IslandSceneView.figureHeight * camera.zoom
        let feet = point(Self.stands[named.index], frame: frame, shift: shift)
        let words = Self.nameplateWords(units[named.index])
        let width = CGFloat(words.count) * 5.8 + 20
        let centreY = max(feet.y - height - 14, Self.headerBottom + 16)
        return CGRect(x: feet.x - width / 2, y: centreY - 12, width: width, height: 24)
    }

    /// The figure's name and level on the same dark glass as the chips,
    /// rimmed in its element.
    private func nameplate(_ unit: ResolvedUnit) -> some View {
        Text(Self.nameplateWords(unit))
            .font(Theme.body(11).weight(.heavy))
            .foregroundStyle(Theme.onGlass)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(IslandBubble.glassFill)
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

    /// Names a figure for a breath, in three beats so the plate and what it
    /// lands on are never drawn together: its place is kept clear at once
    /// (the chip or bubble there steps back with no fade), the plate springs
    /// in `plateDelay` later, fades after `plateHold`, and only once it has
    /// gone does the place open again. Run 224's zoomed island caught the two
    /// crossing — the plate springing in through a "Summoning Circle" chip
    /// still fading — a flicker the phone showed at every stir under a chip,
    /// every nine to fifteen seconds.
    private func name(_ index: Int) {
        let plate = NamedFigure(index: index)
        let fade = Self.plateFade
        // A plate already up goes with no fade: another figure has the name.
        var instantly = Transaction()
        instantly.disablesAnimations = true
        withTransaction(instantly) {
            named = plate
            nameplateDrawn = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.plateDelay) {
            guard named == plate else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { nameplateDrawn = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.plateDelay + Self.plateHold) {
            guard named == plate else { return }
            withAnimation(.easeOut(duration: fade)) { nameplateDrawn = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + fade) {
                if named == plate { named = nil }
            }
        }
    }

    /// The name's three beats (`name`): the wait for what it lands on to
    /// step back, the time it is up, and its fade.
    private static let plateDelay: TimeInterval = 0.15
    private static let plateHold: TimeInterval = 1.6
    private static let plateFade: TimeInterval = 0.25

    // MARK: - The daily offering

    /// The bazaar's free daily offering, waiting by the pool as a bubble of
    /// the island's glass, rimmed gold, with the painted gift; a tap claims
    /// it where it stands — the same item through the same `GameStore.buy`,
    /// so the two doors cannot pay differently — with a burst of gold and
    /// the grants as tiles for a few seconds. Held in the frame and under the
    /// header like the buildings' bubbles, and gone while the pool itself is
    /// off the screen or under the header.
    ///
    /// It was a flat gold capsule floating over the water, between the
    /// circle's scroll count and its name: three call-outs down one column,
    /// the middle one in a material of its own (run 221). It is the same
    /// glass as every bubble now, and it stands beside the scroll count
    /// (`offeringSpot`), so the pool carries one row of bubbles over its name.
    /// It steps back where the buildings' bubbles do (`IslandKeepOut`).
    private func offeringBubble(frame: CGRect, shift: CGPoint, bounds: CGSize, keepOut: IslandKeepOut) -> some View {
        let spot = offeringSpot(frame: frame, shift: shift, bounds: bounds)
        let size = Self.offeringSize
        let rect = CGRect(x: spot.centre.x - size.width / 2, y: spot.centre.y - size.height / 2,
                          width: size.width, height: size.height)
        let shown = spot.inView && keepOut.allows(rect)
        return IslandBubble(glyph: "gift.fill", text: Self.offeringWords, tint: Theme.gold,
                            art: ItemArt.imageName("bundle"))
            .offset(y: pulse ? -3 : 3)
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(shown)
            .onTapGesture { claimOffering(at: spot.centre) }
            .position(spot.centre)
            .animation(Self.stepBack(to: shown), value: shown)
    }

    /// Where the offering's bubble stands: level with the Summoning Circle's
    /// own bubble and on its left, six points short of it, or in that
    /// bubble's place while the circle has none (no scroll to open); and
    /// whether the circle is on the screen at all. The circle's bubble is
    /// placed here as `building` places it.
    private func offeringSpot(frame: CGRect, shift: CGPoint, bounds: CGSize) -> (centre: CGPoint, inView: Bool) {
        guard let circle = IslandDatabase.landmarks.first(where: { $0.destination == .summon }) else {
            return (centre: .zero, inView: false)
        }
        let pool = point(circle.footprint.centre, frame: frame, shift: shift)
        let over = CGPoint(x: pool.x, y: pool.y - circle.footprint.size.height * frame.height / 2 - 16)
        let inView = pool.x >= 0 && pool.x <= bounds.width && pool.y >= Self.headerBottom && pool.y <= bounds.height
        let mine = Self.offeringSize
        guard circle.isUnlocked(atLevel: store.player.level), hasSomethingToDo(circle),
              let wants = badge(for: circle) else {
            return (centre: Self.held(over, size: mine, in: bounds), inView: inView)
        }
        let theirs = IslandBubble.size(for: wants.text)
        let beside = Self.held(over, size: theirs, in: bounds)
        let left = CGPoint(x: beside.x - theirs.width / 2 - 6 - mine.width / 2, y: beside.y)
        let heldLeft = Self.held(left, size: mine, in: bounds)
        guard heldLeft.x > left.x + 0.5 else { return (centre: heldLeft, inView: inView) }
        // Held off the screen's left edge it would stand on the circle's
        // own bubble, so it stands on that bubble's right instead.
        let right = CGPoint(x: beside.x + theirs.width / 2 + 6 + mine.width / 2, y: beside.y)
        return (centre: Self.held(right, size: mine, in: bounds), inView: inView)
    }

    private func claimOffering(at spot: CGPoint) {
        guard let item = ShopService.item("daily_offering"), let grants = store.buy(item) else { return }
        Juice.notify(.success)
        AudioLibrary.shared.play(.uiConfirm)
        burstAt = spot
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

// MARK: - Where the chips stand back

/// Where the island's name chips, its buildings' bubbles and the daily
/// offering may not stand this frame: under the named figure's plate while
/// it is up, under Athena's caret — its line, stem, arrow and ring, one
/// call-out (`GuideStage`) — and anywhere at all while she is speaking,
/// when the place recedes behind her plate and the genre's tutorial dim.
///
/// Run 224's guide frame had her plate slicing three chips at its edges
/// and the caret's frame "Arena of Souls" standing between the line and its
/// arrow; run 216's had "Zeus · Lv.12" over the start of "Summoning Circle".
/// One test for all three, so the buildings and the offering cannot answer
/// differently.
private struct IslandKeepOut {
    var plate: CGRect?
    var callouts: [CGRect] = []
    var speaking = false

    /// Whether a chip or a bubble standing in `rect` is drawn.
    func allows(_ rect: CGRect) -> Bool {
        if speaking { return false }
        if let plate, plate.intersects(rect) { return false }
        return !callouts.contains { $0.intersects(rect) }
    }
}

// MARK: - The purse

/// The island's wallet (2026-09-22, phase B): the four currencies as their
/// painted items in the strips' dark gold-rimmed well (`BarWell`), the next
/// point of energy's countdown beside the energy, and the bazaar's gold plus
/// inside the same well, so the way into the bazaar is one object.
///
/// It was `WalletBar`, a cream capsule of 11-point SF glyphs — a bolt, a
/// sparkle, a hexagon cluster, a laurel — on the most-seen screen, while
/// every other strip's `BarWallet` drew the painted energy, divinity, drachma
/// and laurels, and the painted doors now stand beside it. It draws what
/// `BarWallet` draws, item for item and at its sizes, because `BarWallet`
/// has no countdown and the island is where a player checks when the next
/// energy comes. Without the dividers and the twelve-point gaps it is about
/// twenty points narrower than the capsule it replaced, which goes to the
/// player's card.
private struct IslandPurse: View {
    let wallet: Wallet
    /// False on a narrow phone, where the header cannot hold all four.
    var showsLaurels: Bool = true

    /// One energy every five minutes: `GameStore.refreshTimedResources`
    /// keeps the same interval, and `lastEnergyTick` is where it counts from.
    private static let energyInterval: TimeInterval = 5 * 60

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 5) {
                currency("energy", tint: Theme.info, value: "\(wallet.energy)/\(wallet.maxEnergy)")
                if wallet.energy < wallet.maxEnergy {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(countdown(at: context.date))
                            .font(Theme.numeric(11.5))
                            .foregroundStyle(Theme.onGlassDim)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            // Every amount through `BarWallet.compact`, grouped under ten
            // thousand: run 221's purse printed "1240" laurels beside "200K".
            currency("divinity", tint: Theme.gold, value: BarWallet.compact(wallet.divinity))
            currency("drachma", tint: Theme.onGlass, value: BarWallet.compact(wallet.drachma))
            if showsLaurels {
                currency("laurels", tint: Theme.success, value: BarWallet.compact(wallet.laurels))
            }
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(Theme.ink)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.goldPlate))
                .overlay(Circle().strokeBorder(Color(hex: "#FFE9A8").opacity(0.6), lineWidth: 1))
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .frame(height: ScreenChrome.control)
        .background(BarWell())
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Energy \(wallet.energy) of \(wallet.maxEnergy), divinity \(wallet.divinity), drachma \(wallet.drachma), laurels \(wallet.laurels). Opens the bazaar.")
    }

    /// A currency as `BarWallet` draws it: the painted item at 18 (its glyph
    /// in `tint` until a painting ships) and the amount in cream, on one line
    /// at its own width — run 179 broke "80/80" into "80/8" over "0".
    private func currency(_ key: String, tint: Color, value: String) -> some View {
        HStack(spacing: 4) {
            ItemIcon(key: key, size: 18, tint: tint, glow: false)
                .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
            Text(value)
                .font(Theme.numeric(12.5))
                .foregroundStyle(Theme.onGlass)
                .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// Minutes and seconds to the next point of energy: the remainder of the
    /// current interval since `lastEnergyTick`.
    private func countdown(at now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(wallet.lastEnergyTick))
        let remaining = Self.energyInterval - elapsed.truncatingRemainder(dividingBy: Self.energyInterval)
        return String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60)
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

/// The genre's floating marker over a building: a small plate with the
/// painted item and a count and a tail pointing down, bobbing. The daily
/// offering wears the same glass, rimmed gold: it was a flat gold plate, a
/// material of its own among the bubbles, until run 221.
///
/// On dark glass rimmed in the building's colour since run 216, the wallet
/// well's material, with the item PAINTED (`art`, a bundle painting's name)
/// at 18 points; `glyph` is drawn only while that painting is missing. Five
/// SF glyphs on cream were the system kit in the middle of the painting.
struct IslandBubble: View {
    let glyph: String
    let text: String
    var tint: Color = Theme.gold
    var art: String? = nil

    /// The island's glass: the chips', the bubbles' and the plates' ground.
    static let glassFill = Color(hex: "#17120E").opacity(0.84)

    /// The painted item's size.
    static let artSize: CGFloat = 18

    /// A bubble's size with its tail, reckoned rather than measured so the
    /// island can keep it in the frame before it is drawn: Manrope-Bold's
    /// figures at 12 run about 7.6 points, the rest is the item and padding.
    static func size(for text: String) -> CGSize {
        CGSize(width: CGFloat(text.count) * 7.6 + artSize + 20, height: artSize + 8 + 5)
    }

    var body: some View {
        VStack(spacing: -1) {
            HStack(spacing: 4) {
                if let art, BundleImage.exists(art) {
                    BundleImage(name: art, renderedAt: Self.artSize)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: Self.artSize, height: Self.artSize)
                        .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
                } else {
                    Image(systemName: glyph)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(tint)
                }
                Text(text)
                    .font(Theme.numeric(12))
                    .foregroundStyle(Theme.onGlass)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .background(plate)
            BubbleTail()
                .fill(tint)
                .frame(width: 10, height: 6)
        }
        .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
    }

    /// The glass, its colour on the rim and a lit top edge, like the
    /// wallet's well.
    private var plate: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Self.glassFill)
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(tint, lineWidth: 1.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.white.opacity(0.18), Color.white.opacity(0)],
                                       startPoint: .top, endPoint: .center),
                        lineWidth: 1
                    )
                    .padding(1.5)
            )
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
