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

    // MARK: - Where things stand, solved (2026-09-22, phase B)
    //
    // The chapter's plate stood on the road: a 300-point cream plate at the
    // top left that hid one to three medallions on every one of the twelve
    // maps in run 211's frames, and took their taps, because it was drawn
    // above them. And those frames were taken WITHOUT the tab bar: the
    // campaign is a tab, so on the phone the map is about 734 × 262 points
    // (the CI phone, 852 × 393, less its insets, the strip and the 58-point
    // `GameTabBar`), not the 734 × 320 the tour photographed. At 262 no fixed
    // corner is clear on every map. So the plate became a one-line glass tab
    // whose place is SOLVED from the same measured points the medallions
    // stand on, the way `CameraDirector` solves the camera from the figures:
    // the first spot along the top edge, then the bottom, clear of every
    // medallion, chest and arrow, in the widest of three forms that fits.
    // The solve takes every medallion at its LARGEST (the leader's face over
    // it, a foot under it), so the tab stands still while the player walks
    // the road; it moves only from one map to the next. `ChapterMapTests`
    // runs it on all twelve maps on five phones.

    /// Every chapter map is painted at 21:9, 2520 × 1080 (the chapter-map
    /// batch of 2026-09-14). The view reads the bundle's own size and falls
    /// back to this; the tests use this.
    static let paintingSize = CGSize(width: 2520, height: 1080)

    /// A medallion's radius: 52 points across, 64 for the boss.
    static func medallionRadius(isBoss: Bool) -> CGFloat { isBoss ? 32 : 26 }

    /// Where the chapter's arrows stand, as a fraction of the map's height.
    static let arrowLine: CGFloat = 0.56

    /// A medallion held inside the frame: its disc whole at the top, its
    /// foot (stars, energy or BOSS, 22 points under the disc) whole at the
    /// bottom. Under the tab bar the painting's fill crops about 26 points
    /// off each end of a 21:9 map, and a landmark at 0.16 or 0.82 of the
    /// painting put its medallion half under the strip or its foot under
    /// the tab bar; held, it moves at most about 20 points off its landmark
    /// (Rome II's seventh stage on the CI phone), less than its own radius.
    static func holdNode(_ point: CGPoint, isBoss: Bool, in size: CGSize) -> CGPoint {
        let radius = medallionRadius(isBoss: isBoss)
        return CGPoint(
            x: max(radius + 8, min(size.width - radius - 8, point.x)),
            y: max(radius + 8, min(size.height - radius - 26, point.y))
        )
    }

    /// A chest held inside the frame, its 54-point frame and its pulse whole.
    static func holdChest(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: max(30, min(size.width - 30, point.x)), y: max(30, min(size.height - 30, point.y)))
    }

    /// The medallions and the chests of a painted map in a frame of `size`:
    /// each measured point through the painting's fill (`place`), then held
    /// inside the frame. The one function the map and its test both call.
    static func marks(_ art: ChapterMapArt, bosses: [Bool], imageSize: CGSize,
                      in size: CGSize) -> (nodes: [CGPoint], chests: [CGPoint]) {
        let nodes = bosses.indices.map { index -> CGPoint in
            let point = index < art.nodes.count ? art.nodes[index] : CGPoint(x: 0.5, y: 0.5)
            return holdNode(place(point, imageSize: imageSize, in: size), isBoss: bosses[index], in: size)
        }
        let chests = art.chests.map { holdChest(place($0, imageSize: imageSize, in: size), in: size) }
        return (nodes, chests)
    }

    /// Whether the leader's face can ride above the current medallion; when
    /// the medallion stands too near the top of the frame it rides at the
    /// medallion's right instead, so the face is never cut by the strip.
    static func leaderSitsAbove(_ point: CGPoint, isBoss: Bool) -> Bool {
        point.y - medallionRadius(isBoss: isBoss) - 40 >= 0
    }

    /// Everything on the map the chapter's tab must not stand on: each
    /// medallion at its largest — the pulsing ring, the leader's face above
    /// it (or beside it), the foot under it — each chest, and the two arrows
    /// whether or not the chapters beside this one are open, so the tab's
    /// place never depends on the player's progress.
    static func obstacles(nodes: [CGPoint], bosses: [Bool], chests: [CGPoint], in size: CGSize) -> [CGRect] {
        var rects: [CGRect] = []
        for (index, point) in nodes.enumerated() {
            let isBoss = index < bosses.count && bosses[index]
            let radius = medallionRadius(isBoss: isBoss)
            let above = leaderSitsAbove(point, isBoss: isBoss)
            let top: CGFloat = above ? radius + 40 : radius + 8
            let beside: CGFloat = above ? 0 : 38
            rects.append(CGRect(x: point.x - radius - 8, y: point.y - top,
                                width: (radius + 8) * 2 + beside, height: top + radius + 26))
        }
        for chest in chests {
            rects.append(CGRect(x: chest.x - 30, y: chest.y - 30, width: 60, height: 60))
        }
        let arrowY = size.height * arrowLine
        rects.append(CGRect(x: 6, y: arrowY - 20, width: 40, height: 40))
        rects.append(CGRect(x: size.width - 46, y: arrowY - 20, width: 40, height: 40))
        return rects
    }

    /// The chapter tab's three forms, widest first, each wide enough for its
    /// longest content in the shipped Manrope (measured with the font files):
    /// the progress and both sets with their names (Zephyr and Titanfall are
    /// 258 points), the progress and the two stones (158), the two stones
    /// alone (88).
    enum TabForm: CaseIterable {
        case named, stones, seal

        var width: CGFloat {
            switch self {
            case .named: return 264
            case .stones: return 162
            case .seal: return 92
            }
        }
    }

    static let tabHeight: CGFloat = 38

    /// Where the chapter's tab stands: for each form, widest first, along the
    /// top edge from the left and then along the bottom, the first place
    /// four points clear of every obstacle. On the five phones the test
    /// covers there is always one; a map painted later that has none gets
    /// the smallest tab at the top left, drawn UNDER the road so a medallion
    /// over it still draws and takes its tap.
    static func tabSlot(obstacles: [CGRect], in size: CGSize) -> (origin: CGPoint, form: TabForm) {
        let rows: [CGFloat] = [8, size.height - 8 - tabHeight]
        for form in TabForm.allCases {
            for y in rows {
                var x: CGFloat = 8
                while x + form.width <= size.width - 8 {
                    let room = CGRect(x: x - 4, y: y - 4, width: form.width + 8, height: tabHeight + 8)
                    if !obstacles.contains(where: { $0.intersects(room) }) {
                        return (CGPoint(x: x, y: y), form)
                    }
                    x += 4
                }
            }
        }
        return (CGPoint(x: 8, y: 8), .seal)
    }
}

/// Normal, Hard, Hell as ONE dark well in the strip — the genre's top-bar
/// tabs, and the strip's one control material since phase A (a chosen
/// segment is a gold plate with ink, as `BarSegments` draws it). Each tier's
/// own colour is its glyph, lifted to read on the dark well (`glowHex`); a
/// shut tier wears a lock and is dimmed, a tier cleared to its boss wears a
/// check. It was three separate capsules, the chosen one filled teal, which
/// broke the strip's rule on run 211 (2026-09-22). What a tier pays is the
/// last line of the chapter's scroll on the map.
struct TierChips: View {
    let base: Chapter
    /// Whose progress opens the tiers: the store's player, or the tour's
    /// walked copy of it (`CampaignView.previewPlayer`).
    let player: Player
    @Binding var difficulty: CampaignDifficulty

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CampaignDifficulty.allCases) { tier in
                segment(tier)
            }
        }
        .padding(3)
        .frame(height: ScreenChrome.control)
        .background(ScreenChrome.well)
    }

    private func segment(_ tier: CampaignDifficulty) -> some View {
        let open = CampaignService.isOpen(tier, of: base, player: player)
        let cleared = (player.campaignProgress[base.id + tier.suffix] ?? 0) >= base.stages.count
        let selected = tier == difficulty
        let glyphTint: Color = selected ? Theme.ink : (open ? Color(hex: tier.glowHex) : Theme.onGlassDim)
        let labelTint: Color = selected ? Theme.ink : (open ? Theme.onGlass : Theme.onGlassDim)
        return Button {
            guard open else { return }
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            withAnimation(.easeOut(duration: 0.2)) { difficulty = tier }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: open ? (cleared ? "checkmark.seal.fill" : tier.glyph) : "lock.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(glyphTint)
                // One line at its own width: the type floor lifted the chips
                // to 11 and run 204 photographed "NO / RM".
                Text(tier.displayName.uppercased())
                    .font(Theme.body(11).weight(.black))
                    .tracking(0.5)
                    .foregroundStyle(labelTint)
                    .lineLimit(1)
                    .fixedSize()
            }
            .opacity(open || selected ? 1 : 0.7)
            .padding(.horizontal, 9)
            .frame(height: ScreenChrome.control - 6)
            .background(
                Capsule().fill(selected ? AnyShapeStyle(Theme.goldPlate) : AnyShapeStyle(Color.clear))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(open ? tier.displayName : "\(tier.displayName), locked")
    }
}

extension CampaignDifficulty {
    /// A tier's colour on DARK glass: `accentHex` (teal, crimson, violet) is
    /// drawn for a cream ground and sank into the tier well and the popup's
    /// band, so each is lifted to read on #17120E (2026-09-22, phase B).
    var glowHex: String {
        switch self {
        case .normal: return "#8FD1B4"
        case .hard: return "#FF8C9E"
        case .hell: return "#C9A8FF"
        }
    }
}

/// What a medallion on the road is: cleared (gold, its stars under it), the
/// one the player stands at (dark glass, a pulsing gold ring, his leader's
/// face over it), or shut (dark glass with a lock).
private enum StageMarkState {
    case cleared, current, locked
}

/// A chapter as a place: the chapter's own painted map fills the content,
/// the stages stand on it as medallions — gold once cleared, dark glass and
/// ringed where the player stands with his leader's face over it, shut with
/// a lock beyond, the boss last and largest with its own face — and the
/// three tribute chests wait beside the road. A tap on a medallion opens
/// the stage's card over the map (`StagePopup`); the chapter's name is the
/// strip's carved title, and what the road yields is a one-line glass tab
/// that opens the chapter's scroll (its story, progress, yields and the
/// tier's terms); the chapters before and after are an arrow at either edge.
///
/// It was a 190-point strip of map over a header panel over a list of the
/// same stages, and the owner called it "so dumb ... not a map and a list
/// below, I want just a map" (2026-09-14). The genre's chapter screen is
/// the painting with the stages standing on it and the details in a popup.
/// Phase B (2026-09-22) took the last cream off it: the 300-point plate that
/// covered one to three medallions on every map, the ghost-white locked
/// medallions (eleven of twelve frames of step 28 showed nothing else), the
/// cream pills and arrows, and "0/10 ✓ Cleared" on a chapter not yet open.
struct ChapterMapView: View {
    @EnvironmentObject private var store: GameStore
    let chapterID: String
    /// The tour's walked copy of the player (`CampaignView.previewPlayer`);
    /// nil, always, outside the tour — the map then reads the store's.
    let previewPlayer: Player?
    /// Which tier of the chapter the road shows. Owned by the campaign
    /// screen so it survives a change of chapter.
    @Binding var difficulty: CampaignDifficulty
    let onSelect: (Stage) -> Void
    /// The chapter before or after this one, from the arrows at the edges.
    let onChapter: (String) -> Void

    @State private var pulse = false
    /// The tribute chest tapped on the road; its card opens as a sheet.
    @State private var openTribute: Tribute?
    /// The chapter's scroll — the story, the progress, the yields and the
    /// tier's terms — open over the map from the tab.
    @State private var scrollOpen: Bool

    init(
        chapterID: String,
        previewPlayer: Player? = nil,
        difficulty: Binding<CampaignDifficulty>,
        openingScroll: Bool = false,
        onSelect: @escaping (Stage) -> Void,
        onChapter: @escaping (String) -> Void = { _ in }
    ) {
        self.chapterID = chapterID
        self.previewPlayer = previewPlayer
        _difficulty = difficulty
        _scrollOpen = State(initialValue: openingScroll)
        self.onSelect = onSelect
        self.onChapter = onChapter
    }

    private var player: Player { previewPlayer ?? store.player }

    private var chapter: Chapter? { StageDatabase.chapter(chapterID)?.at(difficulty) }

    /// The chapter's painted map, when it has one in the bundle.
    private var art: ChapterMapArt? {
        guard let art = ChapterMapArt.byChapter[chapterID], BundleImage.exists(art.image) else { return nil }
        return art
    }

    /// The chapter's scroll is this wide: its three-line story at 12.5 in
    /// 352 points, the longest chapter name at display 18 without a squeeze.
    private static let scrollWidth: CGFloat = 380

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: .topLeading) {
                if let base = StageDatabase.chapter(chapterID), let chapter {
                    // Measured once, and the same points serve the
                    // medallions, the chests and the tab's solve.
                    let bosses: [Bool] = chapter.stages.map(\.isBoss)
                    let placed = marks(chapter, bosses: bosses, in: size)
                    let slot = ChapterMapArt.tabSlot(
                        obstacles: ChapterMapArt.obstacles(nodes: placed.nodes, bosses: bosses, chests: placed.chests, in: size),
                        in: size
                    )
                    painting(chapter, size: size)
                    // UNDER the road: where a map ever leaves it no clear
                    // ground, a medallion over it still draws and still
                    // takes its tap.
                    chapterTab(chapter, form: slot.form)
                        .offset(x: slot.origin.x, y: slot.origin.y)
                    road(chapter, nodes: placed.nodes, chests: placed.chests, size: size)
                    arrows(size: size)
                    if scrollOpen {
                        Color.black.opacity(0.001)
                            .frame(width: size.width, height: size.height)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeOut(duration: 0.2)) { scrollOpen = false }
                            }
                        let onTop = slot.origin.y < size.height / 2
                        chapterScroll(chapter, base: base)
                            .padding(.leading, max(8, min(slot.origin.x, size.width - 8 - Self.scrollWidth)))
                            .padding(.vertical, 8)
                            .frame(width: size.width, height: size.height, alignment: onTop ? .topLeading : .bottomLeading)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: onTop ? .top : .bottom)))
                    }
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
        .onChange(of: chapterID) { _, _ in
            settleTier()
            scrollOpen = false
        }
        // Switching to Hard or Hell opens the scroll on the tier's terms:
        // what the tier changes is the thing to read at that moment.
        .onChange(of: difficulty) { _, tier in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { scrollOpen = tier != .normal }
        }
        .sheet(item: $openTribute) { tribute in
            TributeCard(tribute: tribute, chapterID: chapterID, difficulty: difficulty)
                .environmentObject(store)
        }
    }

    // MARK: - The painting

    /// The chapter's painting, full bleed, shaded at the top and the bottom
    /// so the gold reads on any sky, and graded by the tier: a crimson cast
    /// and a darkened rim on Hard, a violet night with embers rising on
    /// Hell, a few motes of dust on Normal — the tier is felt on the place
    /// before it is read. Decorative only: `.clipped()` does not clip hit
    /// testing, so it never takes a tap. A fixed `.frame(width:height:)`
    /// off the GeometryReader is the safe way to fill it.
    private func painting(_ chapter: Chapter, size: CGSize) -> some View {
        let backdrop = chapter.stages.first?.environment.backdropName ?? ""
        return ZStack {
            if let art {
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
                    .init(color: Theme.ink.opacity(art == nil ? 0.32 : 0.26), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.78),
                    .init(color: Theme.ink.opacity(art == nil ? 0.4 : 0.20), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            tierGrade(size: size)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .allowsHitTesting(false)
    }

    /// The tier's grade over the painting. The multiply strengths and the
    /// vignettes are first values, to be judged on the Hell frame.
    @ViewBuilder
    private func tierGrade(size: CGSize) -> some View {
        switch difficulty {
        case .normal:
            Motes(count: 12, color: Color(hex: "#FFE29A"), seed: 1400)
                .opacity(0.7)
        case .hard:
            ZStack {
                Color(hex: "#6E1022").opacity(0.20)
                    .blendMode(.multiply)
                RadialGradient(
                    colors: [.clear, Color(hex: "#3A0810").opacity(0.45)],
                    center: .center, startRadius: size.width * 0.30, endRadius: size.width * 0.75
                )
            }
        case .hell:
            ZStack {
                Color(hex: "#24103D").opacity(0.34)
                    .blendMode(.multiply)
                RadialGradient(
                    colors: [.clear, Color(hex: "#12061F").opacity(0.60)],
                    center: .center, startRadius: size.width * 0.30, endRadius: size.width * 0.75
                )
                Motes(count: 18, color: Color(hex: "#FF7A4D"), seed: 1500)
            }
        }
    }

    /// The medallions' and the chests' points: on a painted map the
    /// measured landmarks through the painting's fill; otherwise the drawn
    /// road's. Held inside the frame either way (`ChapterMapArt.holdNode`).
    private func marks(_ chapter: Chapter, bosses: [Bool], in size: CGSize) -> (nodes: [CGPoint], chests: [CGPoint]) {
        if let art, art.nodes.count >= chapter.stages.count, art.chests.count == 3 {
            let imageSize = BundleArt.image(art.image)?.size ?? ChapterMapArt.paintingSize
            return ChapterMapArt.marks(art, bosses: bosses, imageSize: imageSize, in: size)
        }
        let drawn = Self.nodePoints(count: chapter.stages.count, in: size)
        let nodes = drawn.indices.map { index in
            ChapterMapArt.holdNode(drawn[index], isBoss: index < bosses.count && bosses[index], in: size)
        }
        let chests = [TributeMilestone.third, .boss, .flawless].map {
            ChapterMapArt.holdChest(Self.chestPoint(for: $0, points: nodes, in: size), in: size)
        }
        return (nodes, chests)
    }

    // MARK: - The road

    private func road(_ chapter: Chapter, nodes: [CGPoint], chests: [CGPoint], size: CGSize) -> some View {
        let player = self.player
        // The first open, uncleared stage is where the player stands; his
        // campaign leader's face rides over it.
        let current = chapter.stages.firstIndex {
            CampaignService.isUnlocked($0, player: player) && !CampaignService.isCleared($0, player: player)
        }
        let leader = store.team(store.player.campaignTeam).first
        let bossPortrait = UnitDatabase.blueprint(chapter.bossBlueprintID)
            .map { $0.model.portraitName(awakened: false) }
            .flatMap { BundleArt.exists($0) ? $0 : nil }
        return ZStack(alignment: .topLeading) {
            // The road: a dotted curve through the medallions — drawn only
            // where the map is not painted, since a painted map has its own.
            if art == nil {
                Path { path in
                    guard let first = nodes.first else { return }
                    path.move(to: first)
                    if nodes.count > 1 {
                        for index in 1..<nodes.count {
                            let previous = nodes[index - 1]
                            let next = nodes[index]
                            let middle = (previous.x + next.x) / 2
                            path.addCurve(
                                to: next,
                                control1: CGPoint(x: middle, y: previous.y),
                                control2: CGPoint(x: middle, y: next.y)
                            )
                        }
                    }
                }
                .stroke(Theme.onGlass.opacity(0.7), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [2, 10]))
                .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                .allowsHitTesting(false)
            }

            ForEach(Array(chapter.stages.enumerated()), id: \.element.id) { index, stage in
                let state: StageMarkState = CampaignService.isCleared(stage, player: player)
                    ? .cleared
                    : (index == current ? .current : .locked)
                if index < nodes.count {
                    node(stage, state: state, at: nodes[index], leader: leader, bossPortrait: bossPortrait)
                        .position(nodes[index])
                }
            }

            // The three tribute chests: the road's, the gate's by the boss,
            // the judgment beyond it.
            ForEach(TributeService.tributes(for: chapter)) { tribute in
                chest(tribute, chapter: chapter)
                    .position(chestPoint(tribute.milestone, chests: chests))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func chestPoint(_ milestone: TributeMilestone, chests: [CGPoint]) -> CGPoint {
        let index: Int
        switch milestone {
        case .third: index = 0
        case .boss: index = 1
        case .flawless: index = 2
        }
        return index < chests.count ? chests[index] : .zero
    }

    /// Where the medallions sit on a chapter with no painted map: spread
    /// across the width between the arrows, wandering up and down through
    /// the middle band of the frame so the tab and the chests have room.
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

    /// One stage on the road. The DISC is the view's frame, so `.position`
    /// puts the disc's centre on the landmark whatever it wears; the halo,
    /// the leader's face and the foot are drawn round it without moving it.
    /// Every surface is opaque dark glass or gold — the old locked medallion
    /// was translucent cream and photographed as a white bubble.
    private func node(_ stage: Stage, state: StageMarkState, at point: CGPoint,
                      leader: ResolvedUnit?, bossPortrait: String?) -> some View {
        let diameter: CGFloat = stage.isBoss ? 64 : 52
        let unlocked = state != .locked
        let leaderAbove = ChapterMapArt.leaderSitsAbove(point, isBoss: stage.isBoss)
        return Button {
            if unlocked { onSelect(stage) }
        } label: {
            ZStack {
                Circle()
                    .fill(discFill(state))
                Circle()
                    .strokeBorder(discRim(state, isBoss: stage.isBoss), lineWidth: rimWidth(state, isBoss: stage.isBoss))
                face(stage, state: state, diameter: diameter, bossPortrait: bossPortrait)
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: .black.opacity(0.6), radius: 6, y: 3)
            .background {
                if state == .current {
                    ZStack {
                        Circle()
                            .fill(Theme.gold.opacity(pulse ? 0.42 : 0.12))
                            .frame(width: diameter + 26, height: diameter + 26)
                        Circle()
                            .strokeBorder(Theme.gold.opacity(pulse ? 0.9 : 0.4), lineWidth: 1.5)
                            .frame(width: diameter + 12, height: diameter + 12)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                foot(stage, state: state)
                    .fixedSize()
                    .offset(y: 22)
            }
            .overlay(alignment: leaderAbove ? .top : .trailing) {
                if state == .current, let leader {
                    WearerBadge(unit: leader, size: 28)
                        .overlay(Circle().strokeBorder(Theme.goldText, lineWidth: 1.5))
                        .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
                        .offset(x: leaderAbove ? 0 : 34, y: leaderAbove ? -34 + (pulse ? -3 : 0) : 0)
                        .allowsHitTesting(false)
                }
            }
        }
        .buttonStyle(PlateButtonStyle())
        .disabled(!unlocked)
        .accessibilityLabel(spokenName(stage, state: state))
    }

    private func discFill(_ state: StageMarkState) -> AnyShapeStyle {
        switch state {
        case .cleared:
            return AnyShapeStyle(Theme.goldPlate)
        case .current:
            return AnyShapeStyle(LinearGradient(colors: [Color(hex: "#3A2C1A"), Color(hex: "#150F0A")],
                                                startPoint: .top, endPoint: .bottom))
        case .locked:
            return AnyShapeStyle(Color(hex: "#17120E").opacity(0.82))
        }
    }

    private func discRim(_ state: StageMarkState, isBoss: Bool) -> AnyShapeStyle {
        if isBoss {
            return AnyShapeStyle(LinearGradient(colors: [Color(hex: "#FF9AA8"), Color(hex: "#8E2740")],
                                                startPoint: .top, endPoint: .bottom))
        }
        switch state {
        case .cleared: return AnyShapeStyle(Theme.goldDeep)
        case .current: return AnyShapeStyle(Theme.goldText)
        case .locked: return AnyShapeStyle(Theme.glassRim)
        }
    }

    private func rimWidth(_ state: StageMarkState, isBoss: Bool) -> CGFloat {
        if isBoss { return 2 }
        switch state {
        case .cleared: return 1.5
        case .current: return 2.5
        case .locked: return 1.2
        }
    }

    /// What the disc shows: the boss's own face on the boss medallion (the
    /// thing the road is walking toward), the stage's number carved on the
    /// current one, in ink on gold once cleared, a lock while shut.
    @ViewBuilder
    private func face(_ stage: Stage, state: StageMarkState, diameter: CGFloat, bossPortrait: String?) -> some View {
        if stage.isBoss, let bossPortrait {
            BundleImage(name: bossPortrait, renderedAt: diameter - 8)
                .aspectRatio(contentMode: .fill)
                .frame(width: diameter - 8, height: diameter - 8)
                .clipShape(Circle())
                .saturation(state == .locked ? 0.35 : 1)
                .opacity(state == .locked ? 0.8 : 1)
                .overlay(alignment: .bottomTrailing) {
                    if state == .locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(Theme.onGlass)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(Color(hex: "#17120E")))
                            .overlay(Circle().strokeBorder(Theme.glassRim, lineWidth: 1))
                    }
                }
        } else if stage.isBoss {
            Image(systemName: state == .locked ? "lock.fill" : "crown.fill")
                .font(.system(size: state == .locked ? 16 : 22, weight: .black))
                .foregroundStyle(state == .cleared ? Theme.ink : Theme.onGlassDanger)
        } else {
            switch state {
            case .cleared:
                Text("\(stage.index)")
                    .font(Theme.display(20))
                    .foregroundStyle(Theme.ink)
            case .current:
                Text("\(stage.index)")
                    .font(Theme.display(22))
                    .carved()
            case .locked:
                Image(systemName: "lock.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.onGlassDim)
            }
        }
    }

    /// Under the disc, on a dark capsule: the stars once cleared (gold on
    /// dark, where 8-point gold stars under gold medallions vanished), the
    /// energy where the player stands, BOSS under the boss while it waits.
    /// A shut stage that is not the boss has no foot.
    @ViewBuilder
    private func foot(_ stage: Stage, state: StageMarkState) -> some View {
        let pips = player.stageStars?[stage.id] ?? 0
        let content = HStack(spacing: 4) {
            switch state {
            case .cleared:
                if pips > 0 {
                    starPips(pips)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Theme.onGlassGold)
                }
            case .current:
                ItemIcon(key: "energy", size: 14, glow: false)
                Text("\(EventCalendar.energyCost(for: stage))")
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(Theme.onGlass)
                if stage.isBoss {
                    bossWord
                }
            case .locked:
                if stage.isBoss {
                    bossWord
                }
            }
        }
        if state != .locked || stage.isBoss {
            content
                .padding(.horizontal, 7)
                .frame(height: 18)
                .background(Capsule().fill(Color(hex: "#17120E").opacity(0.82)))
                .overlay(Capsule().strokeBorder(Theme.glassRim.opacity(0.7), lineWidth: 0.8))
                .allowsHitTesting(false)
        }
    }

    private var bossWord: some View {
        Text("BOSS")
            .font(Theme.body(11).weight(.black))
            .tracking(1.2)
            .foregroundStyle(Theme.onGlassDanger)
            .lineLimit(1)
            .fixedSize()
    }

    /// The stage's best rating as three stars, gold where earned. Saved by
    /// `TributeService.recordStars`; the judgment wants all three on every
    /// stage.
    private func starPips(_ pips: Int) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(index < pips ? Theme.gold : Color.white.opacity(0.28))
                    .shadow(color: .black.opacity(0.5), radius: 1)
            }
        }
    }

    private func spokenName(_ stage: Stage, state: StageMarkState) -> String {
        switch state {
        case .cleared: return "\(stage.name), cleared"
        case .current: return "\(stage.name), \(EventCalendar.energyCost(for: stage)) energy"
        case .locked: return "\(stage.name), locked"
        }
    }

    // MARK: - The chapter's tab and scroll

    /// The chapter on the map as one line of glass: how far the road is
    /// walked, the two sets it yields (with their names where the map has
    /// room, as stones alone where it does not), and a chevron that opens
    /// the scroll. The form and the place are solved by `ChapterMapArt`.
    private func chapterTab(_ chapter: Chapter, form: ChapterMapArt.TabForm) -> some View {
        Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { scrollOpen.toggle() }
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: form == .seal ? 6 : 8) {
                    if form != .seal {
                        progressMark(chapter)
                        Rectangle()
                            .fill(Theme.glassRim.opacity(0.7))
                            .frame(width: 1, height: 18)
                    }
                    ForEach(chapter.relicSets) { relicSet in
                        HStack(spacing: 5) {
                            RelicSetEmblem(set: relicSet, size: 20)
                            if form == .named {
                                Text(relicSet.displayName)
                                    .font(Theme.body(12).weight(.bold))
                                    .foregroundStyle(Theme.onGlassGold)
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: scrollOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Theme.onGlassDim)
            }
            .padding(.horizontal, 12)
            .frame(width: form.width, height: ChapterMapArt.tabHeight)
            .background(GlassPlate(radius: ChapterMapArt.tabHeight / 2))
            .contentShape(Capsule())
        }
        .buttonStyle(PlateButtonStyle())
        .accessibilityLabel("\(chapter.name), the chapter's story and yields")
    }

    /// The road's progress with a glyph that says which of three things it
    /// is: walking (a map), done (a seal, in gold), or not yet open (a lock,
    /// dim) — the plate printed "0/10 ✓ Cleared" on a sealed chapter, since
    /// "no stage left open" was read as "every stage cleared".
    private func progressMark(_ chapter: Chapter) -> some View {
        let count = chapter.stages.count
        let cleared = min(count, player.campaignProgress[chapter.id] ?? 0)
        let sealed = !(chapter.stages.first.map { CampaignService.isUnlocked($0, player: player) } ?? false)
        let done = cleared >= count && count > 0
        let tint: Color = done ? Theme.onGlassGold : (sealed ? Theme.onGlassDim : Theme.onGlass)
        return HStack(spacing: 4) {
            Image(systemName: done ? "checkmark.seal.fill" : (sealed ? "lock.fill" : "map.fill"))
                .font(.system(size: 11, weight: .black))
                .frame(width: 14)
            Text("\(cleared)/\(count)")
                .font(Theme.numeric(12.5))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(tint)
    }

    /// The chapter's scroll, open over the map from its tab: where it is
    /// (realm and chapter), its name carved, its story line, how far the
    /// road is walked and what comes next, what it yields, and the tier's
    /// terms — or, on Normal, what opens Hard. Deep glass (0.86) because it
    /// is a paragraph. Its budget is the CI phone's 262-point map less 16:
    /// 22 + 23 + three lines of story + a two-line next + 24 + two lines of
    /// terms + the spacing is about 238.
    private func chapterScroll(_ chapter: Chapter, base: Chapter) -> some View {
        let count = chapter.stages.count
        let cleared = min(count, player.campaignProgress[chapter.id] ?? 0)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("\(chapter.realmName.uppercased()) · CHAPTER \(StageDatabase.chapterOrder(of: chapter.id))")
                    .font(Theme.body(11).weight(.black))
                    .tracking(1.6)
                    .foregroundStyle(Theme.onGlassEyebrow)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 8)
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { scrollOpen = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Theme.onGlass)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.black.opacity(0.45)))
                        .overlay(Circle().strokeBorder(Theme.glassRim, lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            Text(chapter.name.uppercased())
                .font(Theme.display(18))
                .tracking(1)
                .carved()
                .lineLimit(1)
                .minimumScaleFactor(0.73)
            Text(chapter.summary)
                .font(Theme.body(12.5))
                .foregroundStyle(Theme.onGlass)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .center, spacing: 8) {
                GlassMeter(value: Double(cleared), maximum: Double(max(1, count)), height: 5)
                    .frame(width: 96)
                Text("\(cleared) of \(count)")
                    .font(Theme.numeric(12))
                    .foregroundStyle(Theme.onGlass)
                    .lineLimit(1)
                    .fixedSize()
                Text(nextLine(chapter))
                    .font(Theme.body(11.5))
                    .foregroundStyle(Theme.onGlassDim)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !chapter.relicSets.isEmpty {
                HStack(spacing: 8) {
                    Text("YIELDS")
                        .font(Theme.body(11).weight(.black))
                        .tracking(1.4)
                        .foregroundStyle(Theme.onGlassEyebrow)
                        .fixedSize()
                    ForEach(chapter.relicSets) { relicSet in
                        HStack(spacing: 5) {
                            RelicSetEmblem(set: relicSet, size: 24)
                            Text(relicSet.displayName)
                                .font(Theme.body(12.5).weight(.bold))
                                .foregroundStyle(Theme.onGlassGold)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                }
            }
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: termsTier(base).glyph)
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Color(hex: termsTier(base).glowHex))
                Text(tierNote(termsTier(base), open: CampaignService.isOpen(termsTier(base), of: base, player: player), base: base))
                    .font(Theme.body(11.5))
                    .foregroundStyle(Theme.onGlass)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: Self.scrollWidth, alignment: .leading)
        .background(GlassPlate(radius: 14, opacity: 0.86))
    }

    /// Whose terms the scroll's last line gives: the tier shown, or on
    /// Normal the first tier still shut (what the story opens next), or
    /// Normal's own line once every tier is open.
    private func termsTier(_ base: Chapter) -> CampaignDifficulty {
        guard difficulty == .normal else { return difficulty }
        if !CampaignService.isOpen(.hard, of: base, player: player) { return .hard }
        if !CampaignService.isOpen(.hell, of: base, player: player) { return .hell }
        return .normal
    }

    /// The line after the progress: the next stage, the road done, or what
    /// the chapter waits on.
    private func nextLine(_ chapter: Chapter) -> String {
        let player = self.player
        if let next = chapter.stages.first(where: {
            CampaignService.isUnlocked($0, player: player) && !CampaignService.isCleared($0, player: player)
        }) {
            return "Next: \(next.name)"
        }
        if let last = chapter.stages.last, CampaignService.isCleared(last, player: player) {
            return "Every stage cleared."
        }
        let (baseID, tier) = CampaignDifficulty.split(chapter.id)
        if let easier = tier.easier, let base = StageDatabase.chapter(baseID) {
            return "Sealed until \(base.name) falls on \(easier.displayName)."
        }
        let chapters = StageDatabase.chapters
        if let index = chapters.firstIndex(where: { $0.id == baseID }), index > 0 {
            return "Sealed until \(chapters[index - 1].name) falls."
        }
        return "Sealed."
    }

    /// A tier carried over from another chapter may be shut on this one; the
    /// road then shows Normal rather than a locked tier's stages.
    private func settleTier() {
        guard let base = StageDatabase.chapter(chapterID) else { return }
        if !CampaignService.isOpen(difficulty, of: base, player: player) {
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

    // MARK: - The arrows

    /// The chapter before and the chapter after, an arrow at either edge of
    /// the map, where the story lets the player walk. Glass discs of 40, on
    /// the line `ChapterMapArt.obstacles` keeps the tab off.
    private func arrows(size: CGSize) -> some View {
        let chapters = StageDatabase.chapters
        let index = chapters.firstIndex(where: { $0.id == chapterID }) ?? 0
        let player = self.player
        let previous = index > 0 ? chapters[index - 1] : nil
        let next = index + 1 < chapters.count ? chapters[index + 1] : nil
        func open(_ chapter: Chapter?) -> Chapter? {
            guard let chapter, let first = chapter.stages.first, CampaignService.isUnlocked(first, player: player) else { return nil }
            return chapter
        }
        return ZStack(alignment: .topLeading) {
            if let previous = open(previous) {
                arrow("chevron.left", previous.name) { onChapter(previous.id) }
                    .position(x: 26, y: size.height * ChapterMapArt.arrowLine)
            }
            if let next = open(next) {
                arrow("chevron.right", next.name) { onChapter(next.id) }
                    .position(x: size.width - 26, y: size.height * ChapterMapArt.arrowLine)
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
                .foregroundStyle(Theme.onGlassGold)
                .frame(width: 40, height: 40)
                .background(GlassPlate(radius: 20))
                .contentShape(Circle())
        }
        .buttonStyle(PlateButtonStyle())
        .accessibilityLabel(name)
    }

    // MARK: - The tributes

    /// A chest on the road in one of three states: shut with a lock until
    /// earned, gold and pulsing with a mark while it waits to be claimed,
    /// grey with a check once it has paid.
    private func chest(_ tribute: Tribute, chapter: Chapter) -> some View {
        let player = self.player
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
                    // A dark lock, where a cream disc read as a ghost.
                    chestBadge("lock.fill", Color(hex: "#2C2218"))
                }
            }
            .frame(width: 54, height: 54)
        }
        .buttonStyle(.plain)
    }

    private func chestBadge(_ symbol: String, _ tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .black))
            .foregroundStyle(Theme.readableText(on: tint))
            .frame(width: 15, height: 15)
            .background(Circle().fill(tint))
            .overlay(Circle().strokeBorder(Theme.glassRim, lineWidth: 1))
    }

    /// Where a chest stands on a chapter with no painted map: along the
    /// bottom of the road, below the band the medallions wander in. The
    /// road's chest under the gap between the third and fourth medallions,
    /// the gate's just before the boss, the judgment just past it.
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
