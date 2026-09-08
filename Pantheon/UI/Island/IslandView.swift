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

    /// The painting's pixel size; the anchors are normalised against it.
    static let paintingSize = CGSize(width: 1536, height: 2048)

    var body: some View {
        GeometryReader { geometry in
            let insets = geometry.safeAreaInsets
            let full = CGSize(
                width: geometry.size.width + insets.leading + insets.trailing,
                height: geometry.size.height + insets.top + insets.bottom
            )
            let frame = Self.fill(Self.paintingSize, in: full)

            ZStack(alignment: .top) {
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
                    .frame(width: 110)
                }
            }
            Spacer()
            WalletBar(wallet: player.wallet)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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
                        Text(badge)
                            .font(Theme.numeric(10))
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
                    .font(Theme.body(11).weight(.heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.ink.opacity(0.7)))

                if !unlocked {
                    Text("Level \(landmark.unlockLevel)")
                        .font(Theme.body(9).weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(unlocked ? 1 : 0.72)
        .offset(x: shaking == landmark.id ? 5 : 0)
        .animation(.default.speed(3), value: shaking)
    }

    /// The number a landmark shows on its plaque: what you have to spend there.
    private func badge(for landmark: Landmark) -> String? {
        let player = store.player
        switch landmark.destination {
        case .campaign:
            return "\(player.wallet.energy)"
        case .summon:
            let scrolls = ScrollType.allCases.reduce(0) { $0 + player.wallet.count(of: $1) }
            return scrolls > 0 ? "\(scrolls)" : nil
        case .arena:
            return "\(player.arena.attacksRemaining)"
        case .collection, .training:
            return "\(player.units.count)"
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
