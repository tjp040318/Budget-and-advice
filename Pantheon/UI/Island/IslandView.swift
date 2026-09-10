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
    let onOpen: (IslandDestination) -> Void

    @State private var pulse = false
    @State private var shaking: String?
    @State private var showShop = false
    @State private var showMissions = false

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
                    lightHex: Self.daylight().lightHex
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
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(backdrop(full: full).ignoresSafeArea())
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
                .allowsHitTesting(false)
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
                    StatBar(
                        value: Double(player.experience),
                        maximum: Double(player.experienceToNextLevel),
                        tint: Theme.gold,
                        height: 5
                    )
                    .frame(width: 140)
                    Text("\(player.experience)/\(player.experienceToNextLevel)")
                        .font(Theme.numeric(10))
                        .foregroundStyle(Theme.textSecondary)
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
        onOpen(landmark.destination)
    }
}
