import SwiftUI

/// The world: one card per realm with its chapters. A shut chapter says which
/// boss shuts it. Tapping an open chapter opens its map.
struct WorldMapView: View {
    @EnvironmentObject private var store: GameStore
    let onOpen: (Chapter) -> Void

    private struct Realm: Identifiable {
        let pantheon: Pantheon
        let chapters: [Chapter]
        var id: String { pantheon.rawValue }
    }

    private var realms: [Realm] {
        Pantheon.live.map { pantheon in
            Realm(pantheon: pantheon, chapters: StageDatabase.chapters.filter { $0.pantheon == pantheon })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if BundleImage.exists("world_map") {
                BundleImage(name: "world_map")
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            }
            ForEach(realms) { realm in
                realmCard(realm)
            }
        }
    }

    private func realmCard(_ realm: Realm) -> some View {
        let backdrop = realm.chapters.first?.stages.first?.environment.backdropName ?? ""
        let cleared = realm.chapters.reduce(0) { $0 + (store.player.campaignProgress[$1.id] ?? 0) }
        let total = realm.chapters.reduce(0) { $0 + $1.stages.count }
        return VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                if BundleImage.exists(backdrop) {
                    BundleImage(name: backdrop)
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 88)
                        .frame(maxWidth: .infinity)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(realm.pantheon.color.opacity(0.3))
                        .frame(height: 88)
                }
                LinearGradient(colors: [.clear, Theme.plate.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text(realm.pantheon.displayName.uppercased())
                        .font(Theme.body(10).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(realm.pantheon.color)
                    Text(realm.pantheon.realmName)
                        .font(Theme.title(22))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(12)
            }
            .allowsHitTesting(false)
            .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Text("\(cleared)/\(total)")
                    .font(Theme.numeric(12))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(10)
            }

            ForEach(realm.chapters) { chapter in
                chapterRow(chapter)
            }
        }
        .padding(12)
        .panelBackground()
    }

    private func chapterRow(_ chapter: Chapter) -> some View {
        let player = store.player
        let cleared = player.campaignProgress[chapter.id] ?? 0
        let finished = cleared >= chapter.stages.count
        let unlocked = chapter.stages.first.map { CampaignService.isUnlocked($0, player: player) } ?? false
        return Button {
            if unlocked { onOpen(chapter) }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(finished ? Theme.gold.opacity(0.25) : Theme.surface)
                    Image(systemName: unlocked ? (finished ? "checkmark" : "map.fill") : "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(unlocked ? Theme.gold : Theme.textSecondary)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(chapter.name)
                        .font(Theme.body(14).weight(.semibold))
                        .foregroundStyle(unlocked ? Theme.textPrimary : Theme.textSecondary)
                    if unlocked {
                        StatBar(
                            value: Double(cleared),
                            maximum: Double(chapter.stages.count),
                            tint: chapter.pantheon.color,
                            height: 4
                        )
                        .frame(width: 150)
                    } else if let gate = gateText(for: chapter) {
                        Text(gate)
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                Text("\(cleared)/\(chapter.stages.count)")
                    .font(Theme.numeric(12))
                    .foregroundStyle(Theme.textSecondary)
                if unlocked {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(Theme.surface.opacity(unlocked ? 1 : 0.45))
            )
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }

    /// Why a chapter is shut: the chapter before it, whose boss must fall.
    private func gateText(for chapter: Chapter) -> String? {
        guard let index = StageDatabase.chapters.firstIndex(where: { $0.id == chapter.id }), index > 0 else { return nil }
        return "Clear \(StageDatabase.chapters[index - 1].name) first"
    }
}

/// A chapter as a place: the stage's painting fills the screen, the road
/// winds across it with a medallion per stage — gold once cleared, ringed
/// and pulsing where the player stands, shut with a lock beyond, the boss
/// last and largest — and the three tribute chests wait along the bottom
/// of the road. A tap on a medallion opens the stage's card over the map
/// (`StagePopup`); the chapter's name, story line, progress and yields sit
/// on one plate at the top left, the tiers at the top right, and the
/// chapters before and after are an arrow at either edge.
///
/// It was a 190-point strip of map over a header panel over a list of the
/// same stages, and the owner called it "so dumb ... not a map and a list
/// below, I want just a map" (2026-09-14). The genre's chapter screen is
/// the painting with the stages standing on it and the details in a popup.
/// A chapter's painted map — the region seen from above with its road and
/// its landmarks — and where on it the stages and the chests stand, in
/// 0...1 of the painting's width and height. Measured off the painting
/// with a grid, never guessed, the way the island's landmarks and the
/// world map's cities were; a repainted map is re-measured. A chapter
/// without one shows its stage's backdrop with a drawn road.
struct ChapterMapArt {
    let image: String
    /// One point per stage, in story order, on the painted landmark.
    let nodes: [CGPoint]
    /// The three tribute chests: the road's, the gate's, the judgment's.
    let chests: [CGPoint]

    static let byChapter: [String: ChapterMapArt] = [
        // Every chapter, its stages in story order along the painted road
        // (a ten-stage chapter stands on its five landmarks and the road
        // between them) and its three chests on open ground beside it; each
        // point read off the painting with tools/mapgrid.py and looked at.
        // Duat 1: the jackal gate at the lower left, the reed island, the
        // scarab court, the hall of sentinels, the serpent's hall of scales.
        "duat_1": ChapterMapArt(
            image: "map_duat_1",
            nodes: [CGPoint(x: 0.13, y: 0.70), CGPoint(x: 0.32, y: 0.47), CGPoint(x: 0.59, y: 0.63),
                    CGPoint(x: 0.70, y: 0.40), CGPoint(x: 0.86, y: 0.30)],
            chests: [CGPoint(x: 0.47, y: 0.83), CGPoint(x: 0.80, y: 0.58), CGPoint(x: 0.94, y: 0.80)]
        ),
        // The first gate, the road, the half-buried gate, the road, the gate of statues, the road, its loop, the hall of two truths, the road, the fourth gate.
        "duat_2": ChapterMapArt(
            image: "map_duat_2",
            nodes: [
                CGPoint(x: 0.12, y: 0.66), CGPoint(x: 0.30, y: 0.80), CGPoint(x: 0.34, y: 0.42),
                CGPoint(x: 0.50, y: 0.72), CGPoint(x: 0.59, y: 0.58), CGPoint(x: 0.72, y: 0.70),
                CGPoint(x: 0.90, y: 0.60), CGPoint(x: 0.62, y: 0.22), CGPoint(x: 0.80, y: 0.40),
                CGPoint(x: 0.92, y: 0.18),
            ],
            chests: [
                CGPoint(x: 0.40, y: 0.86), CGPoint(x: 0.70, y: 0.46), CGPoint(x: 0.96, y: 0.42),
            ]
        ),
        // The shrine, the stair's foot, the column terrace, the stair, the round temple, the spring, the stair up, the gate, the rock, the forge cellar.
        "olympus_1": ChapterMapArt(
            image: "map_olympus_1",
            nodes: [
                CGPoint(x: 0.11, y: 0.63), CGPoint(x: 0.30, y: 0.80), CGPoint(x: 0.27, y: 0.30),
                CGPoint(x: 0.45, y: 0.72), CGPoint(x: 0.50, y: 0.30), CGPoint(x: 0.57, y: 0.62),
                CGPoint(x: 0.66, y: 0.60), CGPoint(x: 0.67, y: 0.22), CGPoint(x: 0.80, y: 0.42),
                CGPoint(x: 0.89, y: 0.35),
            ],
            chests: [
                CGPoint(x: 0.12, y: 0.85), CGPoint(x: 0.85, y: 0.72), CGPoint(x: 0.95, y: 0.85),
            ]
        ),
        // The harbour, the beach road, the lighthouse, the cliff road, the sea cave, the cliff, the trident temple, the ruins path, the columns, the statue garden.
        "olympus_2": ChapterMapArt(
            image: "map_olympus_2",
            nodes: [
                CGPoint(x: 0.12, y: 0.78), CGPoint(x: 0.22, y: 0.60), CGPoint(x: 0.31, y: 0.32),
                CGPoint(x: 0.42, y: 0.28), CGPoint(x: 0.60, y: 0.42), CGPoint(x: 0.70, y: 0.50),
                CGPoint(x: 0.78, y: 0.58), CGPoint(x: 0.88, y: 0.47), CGPoint(x: 0.82, y: 0.30),
                CGPoint(x: 0.92, y: 0.18),
            ],
            chests: [
                CGPoint(x: 0.44, y: 0.40), CGPoint(x: 0.90, y: 0.75), CGPoint(x: 0.96, y: 0.58),
            ]
        ),
        // The stilt village, the boardwalk, the drowned shrine, the boardwalk, the dead trees, the boardwalk, the bone mound, its end, the reeds, the hydra's pool.
        "olympus_3": ChapterMapArt(
            image: "map_olympus_3",
            nodes: [
                CGPoint(x: 0.13, y: 0.52), CGPoint(x: 0.20, y: 0.72), CGPoint(x: 0.38, y: 0.60),
                CGPoint(x: 0.50, y: 0.57), CGPoint(x: 0.48, y: 0.30), CGPoint(x: 0.62, y: 0.57),
                CGPoint(x: 0.65, y: 0.37), CGPoint(x: 0.76, y: 0.42), CGPoint(x: 0.80, y: 0.30),
                CGPoint(x: 0.88, y: 0.16),
            ],
            chests: [
                CGPoint(x: 0.42, y: 0.85), CGPoint(x: 0.92, y: 0.45), CGPoint(x: 0.96, y: 0.70),
            ]
        ),
        // The longships, the pyre, the rune stone, the road, the stave church, the road, the burial mound, the road, the climb, the mead hall.
        "yggdrasil_1": ChapterMapArt(
            image: "map_yggdrasil_1",
            nodes: [
                CGPoint(x: 0.13, y: 0.70), CGPoint(x: 0.28, y: 0.80), CGPoint(x: 0.27, y: 0.30),
                CGPoint(x: 0.40, y: 0.45), CGPoint(x: 0.53, y: 0.35), CGPoint(x: 0.50, y: 0.68),
                CGPoint(x: 0.72, y: 0.58), CGPoint(x: 0.80, y: 0.80), CGPoint(x: 0.90, y: 0.48),
                CGPoint(x: 0.88, y: 0.27),
            ],
            chests: [
                CGPoint(x: 0.62, y: 0.48), CGPoint(x: 0.78, y: 0.38), CGPoint(x: 0.97, y: 0.75),
            ]
        ),
        // The cave stair, the path, the well, the path, the barrow field, the root bridge, the bridge, the ice, the frozen roots, the serpent.
        "yggdrasil_2": ChapterMapArt(
            image: "map_yggdrasil_2",
            nodes: [
                CGPoint(x: 0.14, y: 0.75), CGPoint(x: 0.30, y: 0.72), CGPoint(x: 0.32, y: 0.38),
                CGPoint(x: 0.42, y: 0.52), CGPoint(x: 0.55, y: 0.30), CGPoint(x: 0.50, y: 0.62),
                CGPoint(x: 0.65, y: 0.48), CGPoint(x: 0.76, y: 0.42), CGPoint(x: 0.80, y: 0.25),
                CGPoint(x: 0.88, y: 0.40),
            ],
            chests: [
                CGPoint(x: 0.45, y: 0.86), CGPoint(x: 0.92, y: 0.70), CGPoint(x: 0.95, y: 0.15),
            ]
        ),
        // The ice pillars, the road, the giant's camp, the road, the frozen waterfall, the road's top, the icicles, the ice bridge, the road, the ice hall.
        "yggdrasil_3": ChapterMapArt(
            image: "map_yggdrasil_3",
            nodes: [
                CGPoint(x: 0.14, y: 0.62), CGPoint(x: 0.30, y: 0.48), CGPoint(x: 0.38, y: 0.72),
                CGPoint(x: 0.30, y: 0.30), CGPoint(x: 0.47, y: 0.48), CGPoint(x: 0.55, y: 0.22),
                CGPoint(x: 0.70, y: 0.35), CGPoint(x: 0.75, y: 0.62), CGPoint(x: 0.88, y: 0.55),
                CGPoint(x: 0.86, y: 0.28),
            ],
            chests: [
                CGPoint(x: 0.10, y: 0.85), CGPoint(x: 0.65, y: 0.85), CGPoint(x: 0.96, y: 0.80),
            ]
        ),
        // The arch, the road, the cold temple, the road, the basilica, the road, the rostra, the road, the camp gate, the Capitol.
        "rome_1": ChapterMapArt(
            image: "map_rome_1",
            nodes: [
                CGPoint(x: 0.16, y: 0.62), CGPoint(x: 0.30, y: 0.55), CGPoint(x: 0.29, y: 0.30),
                CGPoint(x: 0.42, y: 0.48), CGPoint(x: 0.52, y: 0.28), CGPoint(x: 0.55, y: 0.70),
                CGPoint(x: 0.63, y: 0.58), CGPoint(x: 0.78, y: 0.80), CGPoint(x: 0.79, y: 0.45),
                CGPoint(x: 0.89, y: 0.22),
            ],
            chests: [
                CGPoint(x: 0.10, y: 0.35), CGPoint(x: 0.93, y: 0.64), CGPoint(x: 0.96, y: 0.86),
            ]
        ),
        // The gladiator school, the road, the beast pens, the road, the market, the weapon stall, the road, the arena gate, the sand, the bronze giant.
        "rome_2": ChapterMapArt(
            image: "map_rome_2",
            nodes: [
                CGPoint(x: 0.14, y: 0.72), CGPoint(x: 0.25, y: 0.40), CGPoint(x: 0.30, y: 0.20),
                CGPoint(x: 0.40, y: 0.55), CGPoint(x: 0.50, y: 0.42), CGPoint(x: 0.55, y: 0.72),
                CGPoint(x: 0.66, y: 0.82), CGPoint(x: 0.68, y: 0.55), CGPoint(x: 0.78, y: 0.40),
                CGPoint(x: 0.87, y: 0.20),
            ],
            chests: [
                CGPoint(x: 0.42, y: 0.12), CGPoint(x: 0.93, y: 0.80), CGPoint(x: 0.80, y: 0.86),
            ]
        ),
        // The moon gate, the path, the pavilion, the path, the peach terraces, the path, the bridge, the path, the shrine stair, the fox shrine.
        "jade_1": ChapterMapArt(
            image: "map_jade_1",
            nodes: [
                CGPoint(x: 0.13, y: 0.72), CGPoint(x: 0.28, y: 0.66), CGPoint(x: 0.23, y: 0.30),
                CGPoint(x: 0.36, y: 0.48), CGPoint(x: 0.45, y: 0.62), CGPoint(x: 0.55, y: 0.45),
                CGPoint(x: 0.63, y: 0.47), CGPoint(x: 0.74, y: 0.33), CGPoint(x: 0.83, y: 0.42),
                CGPoint(x: 0.87, y: 0.18),
            ],
            chests: [
                CGPoint(x: 0.08, y: 0.86), CGPoint(x: 0.95, y: 0.60), CGPoint(x: 0.93, y: 0.85),
            ]
        ),
        // The falls, the bridge, the sunken temple, the sand, the wrecked junk, the path, the pearl grotto, the path, the climb, the dragon gate.
        "jade_2": ChapterMapArt(
            image: "map_jade_2",
            nodes: [
                CGPoint(x: 0.14, y: 0.45), CGPoint(x: 0.22, y: 0.70), CGPoint(x: 0.36, y: 0.30),
                CGPoint(x: 0.42, y: 0.58), CGPoint(x: 0.55, y: 0.50), CGPoint(x: 0.62, y: 0.80),
                CGPoint(x: 0.64, y: 0.22), CGPoint(x: 0.78, y: 0.65), CGPoint(x: 0.85, y: 0.48),
                CGPoint(x: 0.86, y: 0.25),
            ],
            chests: [
                CGPoint(x: 0.45, y: 0.86), CGPoint(x: 0.96, y: 0.62), CGPoint(x: 0.93, y: 0.85),
            ]
        ),
    ]

    /// Where a point of the painting lands in a frame the painting fills
    /// (`.fill` crops the long side), so a measured landmark and its
    /// medallion stay together on every phone.
    static func place(_ point: CGPoint, imageSize: CGSize, in size: CGSize) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGPoint(x: point.x * size.width, y: point.y * size.height) }
        let scale = max(size.width / imageSize.width, size.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let offset = CGPoint(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2)
        return CGPoint(x: offset.x + point.x * drawn.width, y: offset.y + point.y * drawn.height)
    }
}

/// Normal, Hard, Hell as three chips in the strip's centre — the genre's
/// top-bar tabs. The tier being shown is filled in its own colour, a shut
/// tier wears a lock, and a tier cleared to its boss wears a check. What a
/// tier pays is a line in the chapter's plate on the map. They stood at the
/// top centre of the painted map first and collided with the plate on the
/// first frames; the strip has the room and the map keeps its sky.
struct TierChips: View {
    @EnvironmentObject private var store: GameStore
    let base: Chapter
    @Binding var difficulty: CampaignDifficulty

    var body: some View {
        let player = store.player
        HStack(spacing: 6) {
            ForEach(CampaignDifficulty.allCases) { tier in
                let open = CampaignService.isOpen(tier, of: base, player: player)
                let cleared = (player.campaignProgress[base.id + tier.suffix] ?? 0) >= base.stages.count
                let selected = tier == difficulty
                let tint = Color(hex: tier.accentHex)
                Button {
                    guard open else { return }
                    Juice.haptic(.light)
                    withAnimation(.easeOut(duration: 0.2)) { difficulty = tier }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: open ? (cleared ? "checkmark.seal.fill" : tier.glyph) : "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(tier.displayName.uppercased())
                            .font(Theme.body(10).weight(.black))
                            .tracking(1.1)
                    }
                    .foregroundStyle(selected ? Theme.ink : (open ? tint : Theme.textSecondary))
                    .padding(.horizontal, 9)
                    .frame(height: ScreenChrome.control)
                    .background(
                        ScreenChrome.controlShape.fill(selected ? tint : Theme.surfaceRaised)
                    )
                    .overlay(
                        ScreenChrome.controlShape.strokeBorder(open ? tint.opacity(selected ? 0 : 0.7) : Theme.stroke, lineWidth: 0.5)
                    )
                    .opacity(open ? 1 : 0.7)
                    .stripHitTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(open ? tier.displayName : "\(tier.displayName), locked")
            }
        }
    }
}

struct ChapterMapView: View {
    @EnvironmentObject private var store: GameStore
    let chapterID: String
    /// Which tier of the chapter the road shows. Owned by the campaign
    /// screen so it survives a change of chapter.
    @Binding var difficulty: CampaignDifficulty
    let onSelect: (Stage) -> Void
    /// The chapter before or after this one, from the arrows at the edges.
    var onChapter: (String) -> Void = { _ in }

    @State private var pulse = false
    /// The tribute chest tapped on the road; its card opens as a sheet.
    @State private var openTribute: Tribute?

    private var chapter: Chapter? { StageDatabase.chapter(chapterID)?.at(difficulty) }

    /// The chapter's painted map, when it has one in the bundle.
    private var art: ChapterMapArt? {
        guard let art = ChapterMapArt.byChapter[chapterID], BundleImage.exists(art.image) else { return nil }
        return art
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                if let base = StageDatabase.chapter(chapterID), let chapter {
                    painting(chapter, size: size)
                    road(chapter, size: size)
                    titlePlate(chapter, base: base)
                        .padding(10)
                    arrows(size: size)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .onAppear {
            settleTier()
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .onChange(of: chapterID) { _, _ in settleTier() }
        .sheet(item: $openTribute) { tribute in
            TributeCard(tribute: tribute, chapterID: chapterID, difficulty: difficulty)
                .environmentObject(store)
        }
    }

    // MARK: - The painting

    /// The stage's painting, full bleed, shaded a little at the top and the
    /// bottom so the plates and the gold read on any sky. Decorative only:
    /// `.clipped()` does not clip hit testing, so it must never take a tap.
    private func painting(_ chapter: Chapter, size: CGSize) -> some View {
        let backdrop = chapter.stages.first?.environment.backdropName ?? ""
        return ZStack {
            if let art {
                // The region itself, painted from above; the shading stays
                // light so the map is the map.
                BundleImage(name: art.image)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else if BundleImage.exists(backdrop) {
                BundleImage(name: backdrop)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
            } else {
                Rectangle()
                    .fill(chapter.pantheon.color.opacity(0.25))
                    .frame(width: size.width, height: size.height)
            }
            LinearGradient(
                stops: [
                    .init(color: Theme.ink.opacity(art == nil ? 0.32 : 0.22), location: 0),
                    .init(color: .clear, location: 0.3),
                    .init(color: .clear, location: 0.7),
                    .init(color: Theme.ink.opacity(art == nil ? 0.4 : 0.18), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
    }

    /// The medallions' points: on a painted map, the measured landmarks
    /// through the painting's fill; otherwise the drawn road's.
    private func nodePoints(_ chapter: Chapter, in size: CGSize) -> [CGPoint] {
        if let art, art.nodes.count >= chapter.stages.count, let image = BundleArt.image(art.image) {
            return chapter.stages.indices.map { ChapterMapArt.place(art.nodes[$0], imageSize: image.size, in: size) }
        }
        return Self.nodePoints(count: chapter.stages.count, in: size)
    }

    private func chestPoint(_ milestone: TributeMilestone, points: [CGPoint], in size: CGSize) -> CGPoint {
        if let art, art.chests.count == 3, let image = BundleArt.image(art.image) {
            let index: Int
            switch milestone {
            case .third: index = 0
            case .boss: index = 1
            case .flawless: index = 2
            }
            return ChapterMapArt.place(art.chests[index], imageSize: image.size, in: size)
        }
        return Self.chestPoint(for: milestone, points: points, in: size)
    }

    // MARK: - The road

    private func road(_ chapter: Chapter, size: CGSize) -> some View {
        let player = store.player
        let points = nodePoints(chapter, in: size)
        return ZStack(alignment: .topLeading) {
            // The road: a dotted curve through the medallions — drawn only
            // where the map is not painted, since a painted map has its own.
            if art == nil {
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                if points.count > 1 {
                    for index in 1..<points.count {
                        let previous = points[index - 1]
                        let next = points[index]
                        let middle = (previous.x + next.x) / 2
                        path.addCurve(
                            to: next,
                            control1: CGPoint(x: middle, y: previous.y),
                            control2: CGPoint(x: middle, y: next.y)
                        )
                    }
                }
            }
            .stroke(Theme.surfaceHigh.opacity(0.8), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 10]))
            .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
            .allowsHitTesting(false)
            }

            ForEach(Array(chapter.stages.enumerated()), id: \.element.id) { index, stage in
                let unlocked = CampaignService.isUnlocked(stage, player: player)
                let cleared = CampaignService.isCleared(stage, player: player)
                node(stage, unlocked: unlocked, cleared: cleared, current: unlocked && !cleared)
                    .position(points[index])
            }

            // The three tribute chests wait along the bottom of the road: the
            // road's below the third stage, the gate's and the judgment
            // either side of the boss.
            ForEach(TributeService.tributes(for: chapter)) { tribute in
                chest(tribute, chapter: chapter)
                    .position(chestPoint(tribute.milestone, points: points, in: size))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Where the medallions sit: spread across the width between the
    /// arrows, wandering up and down through the middle band of the frame
    /// so the plates above and the chests below have their own room.
    static func nodePoints(count: Int, in size: CGSize) -> [CGPoint] {
        guard count > 0 else { return [] }
        let inset: CGFloat = 84
        let usable = max(0, size.width - inset * 2)
        return (0..<count).map { index in
            let t = count == 1 ? 0.5 : CGFloat(index) / CGFloat(count - 1)
            let wave = sin(CGFloat(index) * 1.25 + 0.6)
            return CGPoint(x: inset + usable * t, y: size.height * 0.56 + wave * size.height * 0.15)
        }
    }

    private func node(_ stage: Stage, unlocked: Bool, cleared: Bool, current: Bool) -> some View {
        let diameter: CGFloat = stage.isBoss ? 64 : 52
        return Button {
            if unlocked { onSelect(stage) }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if current {
                        Circle()
                            .fill(Theme.gold.opacity(pulse ? 0.4 : 0.1))
                            .frame(width: diameter + 26, height: diameter + 26)
                    }
                    Circle()
                        .fill(
                            cleared
                                ? LinearGradient(colors: [Color(hex: "#F3D27A"), Color(hex: "#B08A2E")], startPoint: .top, endPoint: .bottom)
                                : LinearGradient(
                                    colors: unlocked ? [Theme.surfaceHigh, Theme.surfaceRaised] : [Theme.surface.opacity(0.75), Theme.surface.opacity(0.55)],
                                    startPoint: .top, endPoint: .bottom
                                )
                        )
                        .frame(width: diameter, height: diameter)
                        .overlay(
                            Circle().strokeBorder(
                                cleared ? Theme.goldDeep : (current ? Theme.gold : Theme.stroke),
                                lineWidth: current ? 2.5 : 1.5
                            )
                        )
                        .shadow(color: .black.opacity(0.55), radius: 5, y: 3)
                    if cleared {
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(Theme.ink)
                    } else if !unlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                    } else if stage.isBoss {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Theme.danger)
                    } else {
                        Text("\(stage.index)")
                            .font(Theme.title(19))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                starPips(stage, size: 8)
                HStack(spacing: 2) {
                    if stage.isBoss {
                        Text("BOSS")
                    } else {
                        Image(systemName: "bolt.fill")
                        Text("\(stage.energyCost)")
                    }
                }
                .font(Theme.body(9).weight(.black))
                .foregroundStyle(stage.isBoss ? Theme.danger : Theme.info)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.plate.opacity(0.9)))
            }
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }

    /// The stage's best rating as three pips, gold where earned, once it has
    /// been cleared at all. Saved by `TributeService.recordStars`; the
    /// judgment wants all three on every stage.
    @ViewBuilder private func starPips(_ stage: Stage, size: CGFloat) -> some View {
        if let pips = store.player.stageStars?[stage.id], pips > 0 {
            HStack(spacing: 1) {
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: "star.fill")
                        .font(.system(size: size, weight: .black))
                        .foregroundStyle(index < pips ? Theme.gold : Theme.stroke)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                }
            }
        }
    }

    // MARK: - The plates

    /// The chapter's name, its story line, its progress and what it yields,
    /// on one plate at the top left.
    private func titlePlate(_ chapter: Chapter, base: Chapter) -> some View {
        let player = store.player
        let cleared = player.campaignProgress[chapter.id] ?? 0
        let next = chapter.stages.first(where: { CampaignService.isUnlocked($0, player: player) && !CampaignService.isCleared($0, player: player) })
        return VStack(alignment: .leading, spacing: 5) {
            Text("\(chapter.realmName.uppercased()) · \(chapter.name.uppercased())")
                .font(Theme.body(9).weight(.black))
                .tracking(1.2)
                .foregroundStyle(chapter.pantheon.color)
            Text(chapter.summary)
                .font(Theme.body(10))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                StatBar(
                    value: Double(cleared),
                    maximum: Double(chapter.stages.count),
                    tint: chapter.pantheon.color,
                    height: 4
                )
                .frame(width: 70)
                Text("\(cleared)/\(chapter.stages.count)")
                    .font(Theme.numeric(10))
                    .foregroundStyle(Theme.textSecondary)
                if let next {
                    Text("· Next: \(next.name)")
                        .font(Theme.body(10).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Label("Cleared", systemImage: "checkmark.seal.fill")
                        .font(Theme.body(10).weight(.semibold))
                        .foregroundStyle(Theme.gold)
                }
            }
            // What the road yields: the chapter's two sets, so the farm is
            // read here and not looked up.
            if !chapter.relicSets.isEmpty {
                HStack(spacing: 5) {
                    Text("YIELDS")
                        .font(Theme.body(9).weight(.black))
                        .tracking(1.2)
                        .foregroundStyle(Theme.textSecondary)
                    ForEach(chapter.relicSets) { relicSet in
                        HStack(spacing: 3) {
                            RelicSetEmblem(set: relicSet, size: 14)
                            Text(relicSet.displayName)
                                .font(Theme.body(10).weight(.bold))
                                .foregroundStyle(Theme.gold)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                        .background(Capsule().fill(Theme.surfaceHigh))
                    }
                }
            }
            // What the tier changes, on Hard and Hell only: Normal is the
            // story and needs no terms.
            if difficulty != .normal {
                Text(tierNote(difficulty, open: CampaignService.isOpen(difficulty, of: base, player: player), base: base))
                    .font(Theme.body(10))
                    .foregroundStyle(Color(hex: difficulty.accentHex))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(9)
        .frame(width: 300, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous).fill(Theme.plate.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous).strokeBorder(Theme.gold.opacity(0.45), lineWidth: 1))
    }

    /// A tier carried over from another chapter may be shut on this one; the
    /// road then shows Normal rather than a locked tier's stages.
    private func settleTier() {
        guard let base = StageDatabase.chapter(chapterID) else { return }
        if !CampaignService.isOpen(difficulty, of: base, player: store.player) {
            difficulty = .normal
        }
    }

    private func tierNote(_ tier: CampaignDifficulty, open: Bool, base: Chapter) -> String {
        switch tier {
        case .normal:
            return "The story. Relics as the stage gives them."
        case .hard:
            return open
                ? "Hard: a grade up, ×1.2 · every stage drops a 5★+ relic · ×1.7 drachma and EXP"
                : "Hard opens when \(base.name)'s boss falls on Normal."
        case .hell:
            return open
                ? "Hell: two grades up, ×1.5 · every stage drops a 6★ relic · ×2.6 drachma and EXP"
                : "Hell opens when \(base.name)'s boss falls on Hard."
        }
    }

    /// The chapter before and the chapter after, an arrow at either edge of
    /// the map, where the story lets the player walk.
    private func arrows(size: CGSize) -> some View {
        let chapters = StageDatabase.chapters
        let index = chapters.firstIndex(where: { $0.id == chapterID }) ?? 0
        let player = store.player
        let previous = index > 0 ? chapters[index - 1] : nil
        let next = index + 1 < chapters.count ? chapters[index + 1] : nil
        func open(_ chapter: Chapter?) -> Chapter? {
            guard let chapter, let first = chapter.stages.first, CampaignService.isUnlocked(first, player: player) else { return nil }
            return chapter
        }
        return ZStack(alignment: .topLeading) {
            if let previous = open(previous) {
                arrow("chevron.left", previous.name) { onChapter(previous.id) }
                    .position(x: 24, y: size.height * 0.56)
            }
            if let next = open(next) {
                arrow("chevron.right", next.name) { onChapter(next.id) }
                    .position(x: size.width - 24, y: size.height * 0.56)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func arrow(_ symbol: String, _ name: String, action: @escaping () -> Void) -> some View {
        Button {
            Juice.haptic(.light)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(Theme.gold)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Theme.plate.opacity(0.9)))
                .overlay(Circle().strokeBorder(Theme.gold.opacity(0.6), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }

    // MARK: - The tributes

    /// A chest on the road in one of three states: shut with a lock until
    /// earned, gold and pulsing with a mark while it waits to be claimed,
    /// grey with a check once it has paid.
    private func chest(_ tribute: Tribute, chapter: Chapter) -> some View {
        let player = store.player
        let earned = TributeService.isEarned(tribute, chapter: chapter, player: player)
        let claimed = TributeService.isClaimed(tribute, player: player)
        let ready = earned && !claimed
        return Button {
            Juice.haptic(.light)
            openTribute = tribute
        } label: {
            ZStack(alignment: .topTrailing) {
                if ready {
                    Circle()
                        .fill(Theme.gold.opacity(pulse ? 0.5 : 0.18))
                        .frame(width: 54, height: 54)
                }
                TributeChestImage(size: 40)
                    .saturation(claimed ? 0 : (earned ? 1 : 0.4))
                    .opacity(claimed ? 0.6 : 1)
                    .scaleEffect(ready && pulse ? 1.08 : 1)
                    .frame(width: 54, height: 54)
                if claimed {
                    chestBadge("checkmark", Theme.success)
                } else if earned {
                    chestBadge("exclamationmark", Theme.gold)
                } else {
                    chestBadge("lock.fill", Theme.textSecondary)
                }
            }
            .frame(width: 54, height: 54)
        }
        .buttonStyle(.plain)
    }

    private func chestBadge(_ symbol: String, _ tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 8, weight: .black))
            .foregroundStyle(Theme.readableText(on: tint))
            .frame(width: 15, height: 15)
            .background(Circle().fill(tint))
            .overlay(Circle().strokeBorder(Theme.surfaceHigh, lineWidth: 1))
    }

    /// Where a chest stands: along the bottom of the road, below the band
    /// the medallions wander in. The road's chest under the gap between the
    /// third and fourth medallions, the gate's just before the boss, the
    /// judgment just past it.
    static func chestPoint(for milestone: TributeMilestone, points: [CGPoint], in size: CGSize) -> CGPoint {
        guard let last = points.last else { return .zero }
        let lane = size.height * 0.87
        switch milestone {
        case .third:
            let a = points[min(2, points.count - 1)]
            let b = points[min(3, points.count - 1)]
            return CGPoint(x: (a.x + b.x) / 2, y: lane)
        case .boss:
            return CGPoint(x: last.x - 44, y: lane)
        case .flawless:
            return CGPoint(x: min(size.width - 30, last.x + 44), y: lane)
        }
    }
}

// MARK: - The world road

/// The campaign as one painted world you travel across, the way the genre
/// does it: Egypt on the left, Greece in the middle, the Norse fjords and the
/// world tree on the right, a road running through all three, and a city on
/// the road for every chapter.
///
/// The owner asked for exactly this: "each country where the mythology took
/// place, you can have the campaigns there, like cities, and have a big
/// scrollable map that you have to progress through like Summoners War."
///
/// What was here before was a rail of eight chapter chips above one chapter's
/// stage path. That is a menu. This is a place — and the difference matters,
/// because the thing a player is meant to feel is that Yggdrasil is a long way
/// from the Duat and he walked it.
///
/// **The anchors are measured, not guessed.** `world_map.png` is 2048×1152 and
/// every city below sits on a landmark the painter actually drew: the pyramids,
/// the oasis town, the three temples, the longship harbour, the world tree, the
/// snowfield. They were checked by drawing rings at these coordinates over the
/// painting and looking at the result, the same way `Docs/ART_2D.md` §6 fixed
/// the island's landmarks. If the map is ever repainted, re-measure — do not
/// assume they carry over.
///
/// The map is taller than the frame at the zoom that makes a city tappable, so
/// it scrolls both ways, and it scrolls itself to the city the player is in
/// when it opens. `.allowsHitTesting(false)` on the painting is not optional:
/// a scaled image swallows taps far outside its visible frame, which has
/// broken three screens in this project already.
struct WorldRoadMapView: View {
    @EnvironmentObject private var store: GameStore
    /// Called with the chapter whose city was tapped.
    var onSelect: (Chapter) -> Void

    /// Where each chapter's city sits on the painting, in 0...1 of its width
    /// and height, in story order.
    static let cities: [(id: String, x: CGFloat, y: CGFloat)] = [
        ("duat_1",      0.085, 0.400),   // the pyramids
        ("duat_2",      0.205, 0.735),   // the oasis town on the delta
        ("olympus_1",   0.505, 0.430),   // the great temple
        ("olympus_2",   0.552, 0.475),   // the small temple above the olive groves
        ("olympus_3",   0.523, 0.315),   // the mountain temple
        ("yggdrasil_1", 0.733, 0.425),   // the longship harbour
        ("yggdrasil_2", 0.883, 0.120),   // the world tree
        ("yggdrasil_3", 0.845, 0.530),   // the snowfield below the peaks
    ]

    /// The painting's aspect, and how much bigger than the frame it is drawn.
    /// At 1.0 the whole world fits and a city is 20 points across, which is
    /// too small to hit; at 1.45 a city is a comfortable target and the map
    /// is worth scrolling.
    private static let aspect: CGFloat = 2048.0 / 1152.0
    private static let zoom: CGFloat = 1.45

    var body: some View {
        GeometryReader { frame in
            let mapHeight = frame.size.height * Self.zoom
            let mapWidth = mapHeight * Self.aspect
            ScrollViewReader { scroller in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        painting(width: mapWidth, height: mapHeight)
                        road(width: mapWidth, height: mapHeight)
                        ForEach(Array(Self.cities.enumerated()), id: \.offset) { index, city in
                            if let chapter = StageDatabase.chapter(city.id) {
                                CityMedallion(
                                    chapter: chapter,
                                    order: index + 1,
                                    state: state(of: chapter),
                                    action: { onSelect(chapter) }
                                )
                                .position(x: city.x * mapWidth, y: city.y * mapHeight)
                                .id(city.id)
                            }
                        }
                    }
                    .frame(width: mapWidth, height: mapHeight)
                }
                .onAppear {
                    // Open on the city the player is in, not on the top-left
                    // corner of a map three screens wide.
                    let here = CampaignView.currentChapter(for: store.player).id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.45)) {
                            scroller.scrollTo(here, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func painting(width: CGFloat, height: CGFloat) -> some View {
        Group {
            if BundleImage.exists("world_map") {
                BundleImage(name: "world_map")
                    .aspectRatio(contentMode: .fill)
            } else {
                // Until the painting ships: sea, so the cities still read.
                LinearGradient(
                    colors: [Color(hex: "#1B3A5C"), Color(hex: "#0E2036")],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .allowsHitTesting(false)
    }

    /// The road, drawn city to city in story order. Gold behind the player,
    /// faint ahead of him, so the map itself shows how far he has come.
    private func road(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, _ in
            let points = Self.cities.map { CGPoint(x: $0.x * width, y: $0.y * height) }
            for index in 0..<max(0, points.count - 1) {
                var path = Path()
                path.move(to: points[index])
                path.addLine(to: points[index + 1])
                let travelled = StageDatabase.chapter(Self.cities[index].id).map {
                    state(of: $0) == .cleared
                } ?? false
                context.stroke(
                    path,
                    with: .color(travelled ? Color(hex: "#F5D57A").opacity(0.85) : Color.white.opacity(0.25)),
                    style: StrokeStyle(lineWidth: travelled ? 3 : 2, lineCap: .round, dash: [7, 9])
                )
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    private func state(of chapter: Chapter) -> CityState {
        let player = store.player
        let unlocked = chapter.stages.first.map { CampaignService.isUnlocked($0, player: player) } ?? false
        if !unlocked { return .locked }
        let cleared = chapter.stages.allSatisfy { CampaignService.isCleared($0, player: player) }
        return cleared ? .cleared : .open
    }
}

enum CityState {
    case locked, open, cleared
}

/// One city on the road: a medallion big enough to hit, carrying the chapter's
/// number, its name, and how much of it is done.
struct CityMedallion: View {
    @EnvironmentObject private var store: GameStore
    let chapter: Chapter
    let order: Int
    let state: CityState
    let action: () -> Void

    private var cleared: Int {
        chapter.stages.filter { CampaignService.isCleared($0, player: store.player) }.count
    }

    var body: some View {
        Button {
            guard state != .locked else { return }
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiConfirm)
            action()
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: state == .locked
                                    ? [Color(hex: "#2A2A38"), Color(hex: "#14141C")]
                                    : [Color(hex: "#4A3A16"), Color(hex: "#1A1408")],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: 42, height: 42)
                    Circle()
                        .strokeBorder(
                            state == .locked ? LinearGradient(colors: [Theme.stroke, Theme.stroke],
                                                              startPoint: .top, endPoint: .bottom)
                                             : Theme.goldPlate,
                            lineWidth: 2
                        )
                        .frame(width: 42, height: 42)
                    switch state {
                    case .locked:
                        Image(systemName: "lock.fill")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(Theme.textSecondary)
                    case .cleared:
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .black))
                            .foregroundStyle(Theme.gold)
                    case .open:
                        Text("\(order)")
                            .font(Theme.numeric(16))
                            .foregroundStyle(Theme.gold)
                    }
                }
                .shadow(color: state == .open ? Theme.gold.opacity(0.55) : .black.opacity(0.6),
                        radius: state == .open ? 9 : 5)

                VStack(spacing: 0) {
                    Text(chapter.name)
                        .font(Theme.body(9).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if state != .locked {
                        Text("\(cleared)/\(chapter.stages.count)")
                            .font(Theme.numeric(8))
                            .foregroundStyle(state == .cleared ? Theme.gold : Theme.textSecondary)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.plate.opacity(0.85)))
                .fixedSize()
            }
        }
        .buttonStyle(.plain)
        .opacity(state == .locked ? 0.75 : 1)
    }
}

// MARK: - Tributes

/// The tribute chest as the map draws it: the reward chest's own painting,
/// keyed off its concept's grey ground (`ui_tribute_chest`, from
/// `Art/Concepts/prop_reward_chest_sw.png`), or a gift glyph in a bundle
/// without it.
struct TributeChestImage: View {
    var size: CGFloat = 36

    var body: some View {
        if BundleArt.exists("ui_tribute_chest") {
            BundleImage(name: "ui_tribute_chest", renderedAt: size)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
        } else {
            Image(systemName: "gift.fill")
                .font(.system(size: size * 0.7, weight: .bold))
                .foregroundStyle(Theme.gold)
                .frame(width: size, height: size)
        }
    }
}

/// A tribute chest opened: the chest itself (the victory's own model, its
/// lid hinged the same way), what earns it, what it holds, and Claim — then
/// what it paid, the relic drawn as a stone. All three chests of a road
/// open here.
struct TributeCard: View {
    let tribute: Tribute
    let chapterID: String
    let difficulty: CampaignDifficulty

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var opened = false
    @State private var receipt: TributeService.Receipt?

    private var chapter: Chapter? { StageDatabase.chapter(chapterID)?.at(difficulty) }

    var body: some View {
        NavigationStack {
            GameScreen(
                tribute.milestone.title,
                subtitle: chapter.map { "\($0.realmName) · \($0.name)" } ?? "",
                dismiss: { dismiss() }
            ) {
                BarWallet(wallet: store.player.wallet, shows: [.divinity])
            } content: {
                if let chapter {
                    HStack(alignment: .top, spacing: 8) {
                        chestPane(chapter)
                            .frame(width: 250)
                        contents(chapter)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, ScreenChrome.contentPadding)
                    .padding(.top, 6)
                } else {
                    EmptyState(icon: "questionmark", title: "No such road", message: "This chapter is not in the campaign.")
                }
            }
        }
    }

    private func chestPane(_ chapter: Chapter) -> some View {
        let earned = TributeService.isEarned(tribute, chapter: chapter, player: store.player)
        let claimed = TributeService.isClaimed(tribute, player: store.player)
        return VStack(spacing: 8) {
            ZStack {
                RadialGradient(
                    colors: [Theme.gold.opacity(opened ? 0.5 : (earned ? 0.22 : 0.08)), .clear],
                    center: .center, startRadius: 8, endRadius: 120
                )
                if claimed, !opened {
                    // Paid on an earlier visit: the painting, dimmed, rather
                    // than a chest that would swing open again.
                    TributeChestImage(size: 110)
                        .saturation(0)
                        .opacity(0.6)
                } else {
                    RewardChestView(open: opened, gone: false)
                }
            }
            .frame(width: 230, height: 150)
            Text(TributeService.requirement(tribute, chapter: chapter))
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if claimed {
                Label("Claimed", systemImage: "checkmark.seal.fill")
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(Theme.success)
            } else if earned {
                PrimaryButton(title: "Claim the tribute", systemImage: "gift.fill") {
                    claim(chapter)
                }
            } else {
                Label("Not yet earned", systemImage: "lock.fill")
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(10)
        .panelBackground(radius: Theme.tightCorner)
    }

    private func contents(_ chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(receipt == nil ? "THE TRIBUTE HOLDS" : "YOU RECEIVED")
                .font(Theme.body(9).weight(.black))
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
            // The grants as the genre's tiles, the count on each, the name
            // under it.
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(tribute.grants.enumerated()), id: \.offset) { _, grant in
                    RewardTile(grant: grant, size: 52)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            if let grade = tribute.relicGrade {
                HStack(spacing: 8) {
                    if let relic = receipt?.relic {
                        RelicIcon(relic: relic, size: 36, showsStars: true, showsLevel: false, showsSlot: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(relic.displayName)
                                .font(Theme.body(12).weight(.semibold))
                                .foregroundStyle(relic.resolvedQuality.inkColor)
                            Text("Slot \(relic.slot) · \(relic.effectiveMainStat.displayText)")
                                .font(Theme.body(10))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    } else {
                        HStack(spacing: 3) {
                            ForEach(chapter.relicSets) { relicSet in
                                RelicSetEmblem(set: relicSet, size: 15)
                            }
                        }
                        .frame(width: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(grade)★ \(tribute.relicQuality?.displayName ?? "") relic of \(chapter.relicSets.map(\.displayName).joined(separator: " or "))")
                                .font(Theme.body(12).weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Guaranteed, and the chapter's own set.")
                                .font(Theme.body(10))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous).fill(Theme.surfaceHigh))
            }
            Spacer(minLength: 0)
            Text(footnote)
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .panelBackground(radius: Theme.tightCorner)
    }

    private var footnote: String {
        switch tribute.milestone {
        case .third: return "The realm's first tribute: a scroll of its own pantheon."
        case .boss: return "The gate's tribute: the realm's essence and a relic of the road's set."
        case .flawless: return "The realm's judgment: three stars on every stage, and its finest relic."
        }
    }

    private func claim(_ chapter: Chapter) {
        guard let paid = store.claimTribute(tribute, chapter: chapter) else { return }
        Juice.notify(.success)
        AudioLibrary.shared.play(.uiConfirm)
        withAnimation(.easeOut(duration: 0.4)) {
            opened = true
            receipt = paid
        }
    }
}
