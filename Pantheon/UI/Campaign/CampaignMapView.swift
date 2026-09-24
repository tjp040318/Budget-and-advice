import SwiftUI
import UIKit
import CoreImage
import ImageIO

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
        // A row of the Realms sheet's scroll: the quiet press, and a shut
        // chapter at half strength as `.plain` drew it (2026-09-24).
        .buttonStyle(GamePressStyle(.quiet, dimsWhenDisabled: true))
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
        // Thirty-four points were moved on 2026-09-23 (run 216's frames at
        // the phone's real 262 points): marks stood on marks on eleven maps
        // — Jötunheim's fourth stage straight above its second, the Aegean
        // road chest over the fourth stage's stars, a boss's BOSS foot on
        // the disc below it on five maps. Each moved to the next landmark
        // along its road or to open ground, the mark and its foot clear of
        // every other on every phone (`ChapterMapTests.testNoMarkStandsOnAnother`).
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
                CGPoint(x: 0.88, y: 0.62), CGPoint(x: 0.62, y: 0.22), CGPoint(x: 0.80, y: 0.40),
                CGPoint(x: 0.92, y: 0.18),
            ],
            chests: [
                CGPoint(x: 0.40, y: 0.86), CGPoint(x: 0.70, y: 0.46), CGPoint(x: 0.97, y: 0.47),
            ]
        ),
        // The shrine, the stair's foot, the column terrace, the stair, the round temple, the spring, the stair up, the gate, the rock, the forge cellar.
        "olympus_1": ChapterMapArt(
            image: "map_olympus_1",
            nodes: [
                CGPoint(x: 0.11, y: 0.63), CGPoint(x: 0.30, y: 0.80), CGPoint(x: 0.27, y: 0.30),
                CGPoint(x: 0.45, y: 0.72), CGPoint(x: 0.50, y: 0.30), CGPoint(x: 0.57, y: 0.62),
                CGPoint(x: 0.66, y: 0.60), CGPoint(x: 0.67, y: 0.22), CGPoint(x: 0.79, y: 0.43),
                CGPoint(x: 0.89, y: 0.35),
            ],
            chests: [
                CGPoint(x: 0.20, y: 0.86), CGPoint(x: 0.85, y: 0.72), CGPoint(x: 0.95, y: 0.85),
            ]
        ),
        // The harbour, the beach road, the lighthouse, the cliff road, the sea cave, the cliff, the trident temple, the ruins path, the columns, the statue garden.
        "olympus_2": ChapterMapArt(
            image: "map_olympus_2",
            nodes: [
                CGPoint(x: 0.12, y: 0.78), CGPoint(x: 0.22, y: 0.60), CGPoint(x: 0.31, y: 0.32),
                CGPoint(x: 0.42, y: 0.28), CGPoint(x: 0.60, y: 0.42), CGPoint(x: 0.70, y: 0.50),
                CGPoint(x: 0.78, y: 0.58), CGPoint(x: 0.88, y: 0.49), CGPoint(x: 0.80, y: 0.28),
                CGPoint(x: 0.92, y: 0.18),
            ],
            chests: [
                CGPoint(x: 0.50, y: 0.35), CGPoint(x: 0.90, y: 0.75), CGPoint(x: 0.96, y: 0.58),
            ]
        ),
        // The stilt village, the boardwalk, the drowned shrine, the boardwalk, the dead trees, the boardwalk, the bone mound, its end, the reeds, the hydra's pool.
        "olympus_3": ChapterMapArt(
            image: "map_olympus_3",
            nodes: [
                CGPoint(x: 0.13, y: 0.50), CGPoint(x: 0.23, y: 0.71), CGPoint(x: 0.38, y: 0.60),
                CGPoint(x: 0.50, y: 0.57), CGPoint(x: 0.48, y: 0.30), CGPoint(x: 0.61, y: 0.60),
                CGPoint(x: 0.64, y: 0.34), CGPoint(x: 0.72, y: 0.47), CGPoint(x: 0.80, y: 0.32),
                CGPoint(x: 0.90, y: 0.14),
            ],
            chests: [
                CGPoint(x: 0.46, y: 0.86), CGPoint(x: 0.93, y: 0.50), CGPoint(x: 0.96, y: 0.70),
            ]
        ),
        // The longships, the pyre, the rune stone, the road, the stave church, the road, the burial mound, the road, the climb, the mead hall.
        "yggdrasil_1": ChapterMapArt(
            image: "map_yggdrasil_1",
            nodes: [
                CGPoint(x: 0.13, y: 0.70), CGPoint(x: 0.28, y: 0.80), CGPoint(x: 0.27, y: 0.30),
                CGPoint(x: 0.40, y: 0.45), CGPoint(x: 0.53, y: 0.35), CGPoint(x: 0.50, y: 0.68),
                CGPoint(x: 0.72, y: 0.58), CGPoint(x: 0.80, y: 0.80), CGPoint(x: 0.88, y: 0.55),
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
                CGPoint(x: 0.65, y: 0.48), CGPoint(x: 0.75, y: 0.46), CGPoint(x: 0.80, y: 0.18),
                CGPoint(x: 0.90, y: 0.44),
            ],
            chests: [
                CGPoint(x: 0.40, y: 0.86), CGPoint(x: 0.93, y: 0.74), CGPoint(x: 0.95, y: 0.15),
            ]
        ),
        // The ice pillars, the road, the giant's camp, the road, the frozen waterfall, the road's top, the icicles, the ice bridge, the road, the ice hall.
        "yggdrasil_3": ChapterMapArt(
            image: "map_yggdrasil_3",
            nodes: [
                CGPoint(x: 0.14, y: 0.62), CGPoint(x: 0.30, y: 0.48), CGPoint(x: 0.38, y: 0.72),
                CGPoint(x: 0.22, y: 0.31), CGPoint(x: 0.47, y: 0.48), CGPoint(x: 0.55, y: 0.22),
                CGPoint(x: 0.70, y: 0.35), CGPoint(x: 0.75, y: 0.62), CGPoint(x: 0.89, y: 0.58),
                CGPoint(x: 0.86, y: 0.28),
            ],
            chests: [
                CGPoint(x: 0.06, y: 0.87), CGPoint(x: 0.65, y: 0.85), CGPoint(x: 0.96, y: 0.86),
            ]
        ),
        // The arch, the road, the cold temple, the road, the basilica, the road, the rostra, the road, the camp gate, the Capitol.
        "rome_1": ChapterMapArt(
            image: "map_rome_1",
            nodes: [
                CGPoint(x: 0.16, y: 0.62), CGPoint(x: 0.30, y: 0.55), CGPoint(x: 0.29, y: 0.28),
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
                CGPoint(x: 0.14, y: 0.72), CGPoint(x: 0.25, y: 0.40), CGPoint(x: 0.36, y: 0.22),
                CGPoint(x: 0.40, y: 0.55), CGPoint(x: 0.50, y: 0.42), CGPoint(x: 0.55, y: 0.72),
                CGPoint(x: 0.66, y: 0.82), CGPoint(x: 0.68, y: 0.50), CGPoint(x: 0.77, y: 0.42),
                CGPoint(x: 0.87, y: 0.20),
            ],
            chests: [
                CGPoint(x: 0.46, y: 0.12), CGPoint(x: 0.93, y: 0.80), CGPoint(x: 0.80, y: 0.86),
            ]
        ),
        // The moon gate, the path, the pavilion, the path, the peach terraces, the path, the bridge, the path, the shrine stair, the fox shrine.
        "jade_1": ChapterMapArt(
            image: "map_jade_1",
            nodes: [
                CGPoint(x: 0.13, y: 0.72), CGPoint(x: 0.28, y: 0.66), CGPoint(x: 0.23, y: 0.30),
                CGPoint(x: 0.36, y: 0.48), CGPoint(x: 0.45, y: 0.62), CGPoint(x: 0.55, y: 0.45),
                CGPoint(x: 0.63, y: 0.47), CGPoint(x: 0.74, y: 0.33), CGPoint(x: 0.82, y: 0.48),
                CGPoint(x: 0.87, y: 0.18),
            ],
            chests: [
                CGPoint(x: 0.04, y: 0.80), CGPoint(x: 0.95, y: 0.60), CGPoint(x: 0.93, y: 0.85),
            ]
        ),
        // The falls, the bridge, the sunken temple, the sand, the wrecked junk, the path, the pearl grotto, the path, the climb, the dragon gate.
        "jade_2": ChapterMapArt(
            image: "map_jade_2",
            nodes: [
                CGPoint(x: 0.14, y: 0.45), CGPoint(x: 0.22, y: 0.70), CGPoint(x: 0.36, y: 0.30),
                CGPoint(x: 0.42, y: 0.58), CGPoint(x: 0.55, y: 0.50), CGPoint(x: 0.62, y: 0.80),
                CGPoint(x: 0.64, y: 0.22), CGPoint(x: 0.78, y: 0.65), CGPoint(x: 0.86, y: 0.54),
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
    // medallion, chest and arrow, in the wider of two forms that fits.
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

    /// The boss's face for its medallion: its own card, or the card of the
    /// mesh it fights in until its own lands (`ModelSpec.standInAsset` —
    /// the Colossus of the Sun as the Vault's Colossus, the Dragon of
    /// Longmen as the Dragon King in its element), or nil. Four of twelve
    /// bosses showed a bare pink lock in run 216 because only the first was
    /// looked for. The Hydra and the Jötunn had no card of any kind until
    /// round 6: theirs (`portrait_boss_hydra`, `portrait_boss_jotunn`) are
    /// renders of their shipped meshes, not paintings, so every chapter's
    /// boss now wears a face.
    static func bossPortrait(for chapter: Chapter) -> String? {
        guard let boss = UnitDatabase.blueprint(chapter.bossBlueprintID) else { return nil }
        var names = [boss.model.portraitName(awakened: false)]
        if let standIn = boss.model.standInAsset {
            names.append("portrait_\(standIn)")
            names.append("portrait_\(standIn)_\(boss.element.rawValue)")
        }
        return names.first(where: { BundleArt.exists($0) })
    }

    /// What each mark covers on the map, for the test that no mark stands
    /// on another: a medallion's disc with its foot under it (the stars, the
    /// energy or BOSS, 22 points under the disc; up to 50 points wide, 80
    /// for the boss's "⚡ 5 BOSS"), and a chest's painting (40 points, 44
    /// with its badge). The leader's face and the pulse are left out — one
    /// stage at a time wears them and they are drawn over the painting's
    /// air. Nodes first, in story order, then the three chests.
    static func markRects(nodes: [CGPoint], bosses: [Bool], chests: [CGPoint]) -> [CGRect] {
        var rects: [CGRect] = []
        for (index, point) in nodes.enumerated() {
            let isBoss = index < bosses.count && bosses[index]
            let radius = medallionRadius(isBoss: isBoss)
            let halfFoot: CGFloat = isBoss ? 40 : 25
            let half = max(radius, halfFoot)
            rects.append(CGRect(x: point.x - half, y: point.y - radius, width: half * 2, height: radius * 2 + 22))
        }
        for chest in chests {
            rects.append(CGRect(x: chest.x - 22, y: chest.y - 22, width: 44, height: 44))
        }
        return rects
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

    /// The chapter tab's two forms, widest first, each wide enough for its
    /// longest content in the shipped Manrope (measured with the font files):
    /// both sets with their names (Zephyr and Titanfall, 190 points with
    /// their stones and the chevron), and the two stones alone (88). The
    /// road's progress is the strip's line ("The Duat · Chapter 1 · 3/5"),
    /// not the tab's: it was printed in both (run 216), and the room it took
    /// is what lets the names stand on eight maps of twelve where they stood
    /// on four.
    enum TabForm: CaseIterable {
        case named, seal

        var width: CGFloat {
            switch self {
            case .named: return 194
            case .seal: return 92
            }
        }
    }

    static let tabHeight: CGFloat = 38

    /// Where the chapter's tab stands: for each form, widest first, along the
    /// top edge from the left and then along the bottom, the first place
    /// four points clear of every obstacle. On the five phones the test
    /// covers there is always one. A map that has none still gets its tab —
    /// never nothing (run 216 photographed four maps with no tab at all,
    /// laid out under the tab bar): the small form where it covers the least
    /// of the road, drawn UNDER the road so a medallion over it still draws
    /// and takes its tap.
    static func tabSlot(obstacles: [CGRect], in size: CGSize) -> (origin: CGPoint, form: TabForm) {
        let rows: [CGFloat] = [8, max(8, size.height - 8 - tabHeight)]
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
        return (leastCovered(obstacles: obstacles, rows: rows, in: size), .seal)
    }

    /// The small tab's place along either edge where the fewest points of
    /// it are under a mark, for a map with no clear ground at all; the top
    /// left when even that ties.
    private static func leastCovered(obstacles: [CGRect], rows: [CGFloat], in size: CGSize) -> CGPoint {
        let width = TabForm.seal.width
        var best = CGPoint(x: 8, y: 8)
        var bestCover = CGFloat.greatestFiniteMagnitude
        for y in rows {
            var x: CGFloat = 8
            while x + width <= size.width - 8 {
                let tab = CGRect(x: x, y: y, width: width, height: tabHeight)
                var cover: CGFloat = 0
                for obstacle in obstacles {
                    let overlap = obstacle.intersection(tab)
                    if !overlap.isNull {
                        cover += overlap.width * overlap.height
                    }
                }
                if cover < bestCover {
                    bestCover = cover
                    best = CGPoint(x: x, y: y)
                }
                x += 4
            }
        }
        return best
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
        // A locked tier sinks under the finger but says nothing: its
        // action does nothing either.
        .buttonStyle(GamePressStyle(.plate, sounds: open))
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

/// Which sides of a chapter map the painting's haze carries on past, into a
/// safe inset: both on a phone with an island or a notch, neither on an SE.
private struct MapHazeSides: Equatable {
    var leading: Bool
    var trailing: Bool
}

/// A chapter's painting as the haze its map melts into under the safe
/// insets: blurred with its edges CLAMPED — each edge column carried on
/// outward before the blur, so the soft copy keeps the painting's own colour
/// to its last column — and padded a fifth of its width on either side with
/// that carried-on edge, going softer the further it runs from the painting,
/// so an inset reads as the place's own air and not as streaks of its edge.
/// SwiftUI's `.blur(radius:opaque:)` takes in BLACK at a view's bounds: run
/// 224 blurred the whole map that way and every chapter's insets came out as
/// charcoal pillars with the painting's last points burnt black. Built once
/// per painting from a 512-pixel decode (a blur of seven points leaves
/// nothing a larger one would add), from any thread; `warm` builds a set off
/// the main thread before a map asks for one.
enum SoftMapPainting {
    struct Padded {
        let image: UIImage
        /// The thumbnail's size in pixels, and the pad on each side of it.
        let sourceWidth: CGFloat
        let sourceHeight: CGFloat
        let margin: CGFloat
        var paddedWidth: CGFloat { sourceWidth + margin * 2 }
    }

    /// The blur over the painting itself, as a share of its width: seven
    /// points of a map drawn 734 wide (a 16 Pro's), the blur run 223's haze
    /// had.
    static let sigmaShare: CGFloat = 0.0095
    /// The blur the pad goes to away from the painting: about 29 points, so
    /// the edge's rows melt into one another instead of standing as bands.
    static let mistSigmaShare: CGFloat = 0.04
    /// The pad on each side, as a share of the width: a phone's 59-point
    /// inset is 8% of its 734-point map, so a fifth covers any phone.
    static let marginShare: CGFloat = 0.2
    /// How far out into the pad the mist is whole, as a share of it: about
    /// 51 points, most of an inset.
    static let mistRampShare: CGFloat = 0.35

    private static var built: [String: Padded] = [:]
    private static let lock = NSLock()
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// The painting `name` soft and padded, or nil when the bundle has no
    /// such painting or Core Image refuses it.
    static func padded(_ name: String) -> Padded? {
        lock.lock()
        if let hit = built[name] { lock.unlock(); return hit }
        lock.unlock()
        // Decoded straight to 512 pixels and not kept: the soft copy is all
        // the map needs, and `BundleArt`'s thumbnail cache would hold a
        // second picture of every map for good.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
        ]
        guard let url = BundleArt.url(name),
              let file = CGImageSourceCreateWithURL(url as CFURL, nil),
              let source = CGImageSourceCreateThumbnailAtIndex(file, 0, options as CFDictionary)
        else { return nil }
        let painting = CIImage(cgImage: source)
        let width: CGFloat = painting.extent.width
        let height: CGFloat = painting.extent.height
        let margin: CGFloat = (width * marginShare).rounded()
        let canvas = CGRect(x: -margin, y: 0, width: width + margin * 2, height: height)
        let clamped = painting.clampedToExtent()
        let soft = clamped.applyingGaussianBlur(sigma: Double(width * sigmaShare))
        let mist = clamped.applyingGaussianBlur(sigma: Double(width * mistSigmaShare))
        // Black over the painting, easing to white `ramp` pixels out past
        // either edge: where it is white the pad is all mist.
        let ramp: CGFloat = max(1, margin * mistRampShare)
        let black = CIColor(red: 0, green: 0, blue: 0)
        let white = CIColor(red: 1, green: 1, blue: 1)
        guard let leftRamp = CIFilter(name: "CISmoothLinearGradient", parameters: [
                  "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: -ramp, y: 0),
                  "inputColor0": black, "inputColor1": white,
              ])?.outputImage,
              let rightRamp = CIFilter(name: "CISmoothLinearGradient", parameters: [
                  "inputPoint0": CIVector(x: width, y: 0), "inputPoint1": CIVector(x: width + ramp, y: 0),
                  "inputColor0": black, "inputColor1": white,
              ])?.outputImage
        else { return nil }
        let mask = leftRamp.applyingFilter("CIMaximumCompositing", parameters: ["inputBackgroundImage": rightRamp])
        let blended = mist
            .applyingFilter("CIBlendWithMask", parameters: ["inputBackgroundImage": soft, "inputMaskImage": mask])
            .cropped(to: canvas)
        guard let cg = context.createCGImage(blended, from: canvas) else { return nil }
        let made = Padded(image: UIImage(cgImage: cg), sourceWidth: width, sourceHeight: height, margin: margin)
        lock.lock()
        built[name] = made
        lock.unlock()
        return made
    }

    /// Builds the soft paintings of `names` on a utility thread, so the
    /// first map opened draws its haze in the first frame.
    static func warm(_ names: [String]) {
        DispatchQueue.global(qos: .utility).async {
            for name in Set(names) { _ = padded(name) }
        }
    }
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
    /// A modal card — the stage's popup, the sweep's receipt — stands over
    /// the map. The chapter's tab and the tier's line are the map's own
    /// chrome and go while it is up: the tab's "O" and its Oracle stone
    /// peeked out beside the popup, and the receipt's top edge cut through
    /// "Nemesis" (runs 220 and 221).
    let cardUp: Bool
    let onSelect: (Stage) -> Void
    /// The chapter before or after this one, from the arrows at the edges.
    let onChapter: (String) -> Void

    @State private var pulse = false
    /// The tribute chest tapped on the road; its card opens as a sheet.
    @State private var openTribute: Tribute?
    /// The chapter's scroll — the story, the progress, the yields and the
    /// tier's terms — open over the map from the tab.
    @State private var scrollOpen: Bool
    /// Hard's or Hell's terms in one line of glass, for a few seconds after
    /// the tier is chosen (or the map opens on it). Choosing a tier used to
    /// unroll the whole scroll over the left half of the road, every time
    /// (run 216's Hell frame was mostly a paragraph).
    @State private var tierToast: CampaignDifficulty?
    /// Which of the map's sides the painting's haze carries on past — a
    /// landscape phone's safe insets; an SE has none — so the painting
    /// feathers only an edge with haze beyond it. Measured by `bleed`;
    /// both until then, the case of every phone with an island or a notch.
    @State private var hazeSides = MapHazeSides(leading: true, trailing: true)

    /// Under the CI tour the toast stays up, so the frame shows it.
    private static let touring = ProcessInfo.processInfo.arguments.contains("-tour")

    init(
        chapterID: String,
        previewPlayer: Player? = nil,
        difficulty: Binding<CampaignDifficulty>,
        openingScroll: Bool = false,
        cardUp: Bool = false,
        onSelect: @escaping (Stage) -> Void,
        onChapter: @escaping (String) -> Void = { _ in }
    ) {
        self.chapterID = chapterID
        self.previewPlayer = previewPlayer
        _difficulty = difficulty
        _scrollOpen = State(initialValue: openingScroll)
        self.cardUp = cardUp
        self.onSelect = onSelect
        self.onChapter = onChapter
    }

    private var player: Player { previewPlayer ?? store.player }

    /// A card is over the map: the campaign's own (`cardUp`), or one laid
    /// over the campaign from outside — the tour's sweep receipt — which
    /// says so the way every card over a tab does, by dimming the tab bar
    /// (`dimsTabBar`, the store's `tabBarDimmed`).
    private var cardIsUp: Bool { cardUp || store.tabBarDimmed }

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
                    let soft = softPainting(chapter)
                    painting(chapter, size: size, feathered: featherSides(soft, width: size.width))
                    // UNDER the road: where a map ever leaves it no clear
                    // ground, a medallion over it still draws and still
                    // takes its tap. Hidden while the scroll is open — the
                    // scroll IS the tab unrolled, and the tab's line showed
                    // through the scroll's header (run 216) — and while a
                    // card is over the map, whose scrim it showed through.
                    let tabHidden = scrollOpen || cardIsUp
                    chapterTab(chapter, form: slot.form)
                        .offset(x: slot.origin.x, y: slot.origin.y)
                        .opacity(tabHidden ? 0 : 1)
                        .allowsHitTesting(!tabHidden)
                        .animation(.easeOut(duration: 0.2), value: tabHidden)
                    road(chapter, nodes: placed.nodes, chests: placed.chests, size: size)
                    arrows(size: size)
                    if let tierToast, !scrollOpen, !cardIsUp {
                        // Along the edge the tab is not on, centred.
                        let toastY: CGFloat = slot.origin.y < size.height / 2
                            ? slot.origin.y + ChapterMapArt.tabHeight + 8
                            : 8
                        tierLine(tierToast, base: base)
                            .frame(width: size.width)
                            .offset(y: toastY)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                    Color.clear
                        .frame(width: 1, height: 1)
                        .onAppear { Self.report(chapterID, size: size, origin: slot.origin, form: slot.form) }
                        .onChange(of: size) { _, now in
                            Self.report(chapterID, size: now, origin: slot.origin, form: slot.form)
                        }
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
            // The painting runs on under the side insets to the glass, as
            // every place's does since run 216 (the map stood in cream
            // pillars between a strip and a tab bar that reach both edges).
            .background(alignment: .topLeading) {
                if let chapter {
                    bleed(chapter, size: size, soft: softPainting(chapter))
                }
            }
        }
        .onAppear {
            settleTier()
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
            announce(difficulty)
            // The chapters an arrow leads to, soft before they are asked for.
            SoftMapPainting.warm(ChapterMapArt.byChapter.values.map(\.image))
        }
        .onChange(of: chapterID) { _, _ in
            settleTier()
            scrollOpen = false
        }
        // Switching to Hard or Hell says the tier's terms in one line for a
        // few seconds; the scroll stays the tab's to open.
        .onChange(of: difficulty) { _, tier in
            announce(tier)
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
    /// Hell — the tier is felt on the place before it is read. Normal is the
    /// painting as painted: its twelve flat motes photographed as specks of
    /// dirt on the glass (run 216). Decorative only: `.clipped()` does not
    /// clip hit testing, so it never takes a tap. A fixed
    /// `.frame(width:height:)` off the GeometryReader is the safe way to fill
    /// it. The last 14 points darken to meet the tab bar softly: the foot
    /// shade was laid out under the bar until run 216 and the map met the
    /// bar in a hard seam. At a side the haze carries on past (`feathered`),
    /// the painting's last `featherWidth` points fade out over the soft
    /// painting drawn behind it (`bleed`), so the place melts into its haze
    /// instead of stopping at a line.
    private func painting(_ chapter: Chapter, size: CGSize, feathered: MapHazeSides) -> some View {
        ZStack {
            ZStack {
                paintingImage(chapter, size: size)
                tierTint(size: size)
            }
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .bottom) { Self.footShade }
            .compositingGroup()
            .mask { Self.featherMask(width: size.width, sides: feathered) }
            tierAir
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .allowsHitTesting(false)
    }

    /// The painting itself and its top and foot shade, at `size`.
    private func paintingImage(_ chapter: Chapter, size: CGSize) -> some View {
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
            paintingShade
        }
        .frame(width: size.width, height: size.height)
    }

    /// The painting's top and foot shade, so the gold reads on any sky; the
    /// haze beyond the painting wears the same, row for row.
    private var paintingShade: some View {
        LinearGradient(
            stops: [
                .init(color: Theme.ink.opacity(art == nil ? 0.32 : 0.26), location: 0),
                .init(color: .clear, location: 0.22),
                .init(color: .clear, location: 0.78),
                .init(color: Theme.ink.opacity(art == nil ? 0.4 : 0.20), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// The map's last 14 points darkening to meet the tab bar.
    private static var footShade: some View {
        LinearGradient(colors: [Theme.ink.opacity(0), Theme.ink.opacity(0.42)],
                       startPoint: .top, endPoint: .bottom)
            .frame(height: 14)
    }

    /// The tier's colour over the painting. A dark violet MULTIPLY alone only
    /// darkened a warm painting — run 216's Hell was "Normal with the lights
    /// down", still orange-brown — so each tier also lays its hue over the
    /// painting's own light: a `.color` layer on Hell (the painting's
    /// luminance in violet), a crimson `.softLight` on Hard. The vignettes
    /// close the rim in the tier's dark. The haze beyond the painting takes
    /// the same tint about the painting's own centre (`centre`), so the two
    /// agree where they meet.
    @ViewBuilder
    private func tierTint(size: CGSize, centre: UnitPoint = .center) -> some View {
        switch difficulty {
        case .normal:
            Color.clear
        case .hard:
            ZStack {
                Color(hex: "#6E1022").opacity(0.20)
                    .blendMode(.multiply)
                Color(hex: "#C0243F").opacity(0.34)
                    .blendMode(.softLight)
                RadialGradient(
                    colors: [.clear, Color(hex: "#3A0810").opacity(0.45)],
                    center: centre, startRadius: size.width * 0.30, endRadius: size.width * 0.75
                )
            }
        case .hell:
            ZStack {
                Color(hex: "#24103D").opacity(0.30)
                    .blendMode(.multiply)
                Color(hex: "#5B2A86").opacity(0.36)
                    .blendMode(.color)
                RadialGradient(
                    colors: [.clear, Color(hex: "#12061F").opacity(0.60)],
                    center: centre, startRadius: size.width * 0.30, endRadius: size.width * 0.75
                )
            }
        }
    }

    /// Hell's embers, rising and glowing: the same thirty motes twice, one
    /// blurred into a halo and added as light, one sharp — eighteen flat
    /// four-point dots did not read in a still. The two share a seed and a
    /// clock, so every halo stays on its ember.
    @ViewBuilder
    private var tierAir: some View {
        if difficulty == .hell {
            ZStack {
                Motes(count: 30, color: Color(hex: "#FF9A4D"), seed: 1500)
                    .blur(radius: 3)
                    .blendMode(.plusLighter)
                Motes(count: 30, color: Color(hex: "#FFC27A"), seed: 1500)
            }
        }
    }

    /// The painting carried on under the side insets to the glass as HAZE:
    /// the chapter's soft painting (`SoftMapPainting`) drawn across the whole
    /// width behind the sharp one and lined up with it, so the painting's
    /// feathered rim melts into the same picture the insets show — its own
    /// edge colours, going to mist and darkening toward the glass, in the
    /// tier's colour — and no landmark stands in an inset. It was the
    /// painting MIRRORED about each edge until run 217, which doubled the
    /// Duat's dome and serpent and folded the Colosseum's stands and the Jade
    /// gate into kaleidoscope shapes about a visible line — "a Rorschach
    /// reflection"; a two-point column of the painting stretched and blurred
    /// in SwiftUI until run 223, which met the sharp painting in a seam; and
    /// in run 224 a SwiftUI blur of the whole painting, which took in black
    /// at its bounds and turned every inset into a charcoal pillar. It
    /// cannot simply be drawn wider: a 21:9 painting covering the whole
    /// 852-point width crops twice as much of its height, and thirty
    /// medallions would leave their landmarks. Read off a GeometryReader that
    /// ignores the horizontal safe area; it never takes a tap. It also tells
    /// the painting which sides it carries on past (`hazeSides`), so only
    /// those edges feather.
    private func bleed(_ chapter: Chapter, size: CGSize, soft: SoftMapPainting.Padded?) -> some View {
        GeometryReader { outer in
            // The insets as reported, or the extra width split evenly (a
            // landscape phone's two insets are equal) if they read zero.
            let extra: CGFloat = max(0, outer.size.width - size.width)
            let reported: CGFloat = outer.safeAreaInsets.leading
            let leading: CGFloat = reported > 0 && reported <= extra ? reported : extra / 2
            let trailing: CGFloat = extra - leading
            let sides = MapHazeSides(leading: leading > 0.5, trailing: trailing > 0.5)
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .onAppear { hazeSides = sides }
                    .onChange(of: sides) { _, now in hazeSides = now }
                if sides.leading || sides.trailing {
                    hazeBackdrop(chapter, size: size, soft: soft, width: outer.size.width, leading: leading)
                    if sides.leading {
                        insetShade(width: leading, height: size.height, towardLeading: true)
                    }
                    if sides.trailing {
                        insetShade(width: trailing, height: size.height, towardLeading: false)
                            .offset(x: leading + size.width)
                    }
                }
            }
        }
        .ignoresSafeArea(.container, edges: .horizontal)
        .allowsHitTesting(false)
    }

    /// How far in from a hazed edge the painting starts to go soft: 24
    /// points, judged on a render of the Duat's map at 20 and 28. Only the
    /// painting softens — a medallion, a chest or an arrow near the edge is
    /// drawn over it and stays sharp.
    private static let featherWidth: CGFloat = 24

    /// The painting the map draws, by name: its own map, or the first
    /// stage's backdrop; nil when the bundle has neither.
    private func paintingName(_ chapter: Chapter) -> String? {
        if let art { return art.image }
        let backdrop = chapter.stages.first?.environment.backdropName ?? ""
        return BundleImage.exists(backdrop) ? backdrop : nil
    }

    /// The soft painting the haze is cut from, when there is a painting.
    private func softPainting(_ chapter: Chapter) -> SoftMapPainting.Padded? {
        paintingName(chapter).flatMap { SoftMapPainting.padded($0) }
    }

    /// The sides whose rim melts into the haze: the ones the haze carries on
    /// past, once there is a soft painting behind the rim to melt into.
    private func featherSides(_ soft: SoftMapPainting.Padded?, width: CGFloat) -> MapHazeSides {
        guard soft != nil, width > Self.featherWidth * 4 else {
            return MapHazeSides(leading: false, trailing: false)
        }
        return hazeSides
    }

    /// Whole across the painting and clear at a hazed edge, over its last
    /// `featherWidth` points, eased (a smoothstep in five stops) so the fade
    /// has no line where it starts. An edge with no haze beyond it stays
    /// whole to the last point.
    private static func featherMask(width: CGFloat, sides: MapHazeSides) -> LinearGradient {
        let edge: CGFloat = min(0.25, featherWidth / max(1, width))
        let ease: [(at: CGFloat, alpha: Double)] = [(0, 0), (0.25, 0.16), (0.5, 0.5), (0.75, 0.84), (1, 1)]
        let lead: [Gradient.Stop] = sides.leading
            ? ease.map { Gradient.Stop(color: Color.black.opacity($0.alpha), location: $0.at * edge) }
            : [Gradient.Stop(color: Color.black, location: 0)]
        let trail: [Gradient.Stop] = sides.trailing
            ? ease.reversed().map { Gradient.Stop(color: Color.black.opacity($0.alpha), location: 1 - $0.at * edge) }
            : [Gradient.Stop(color: Color.black, location: 1)]
        return LinearGradient(stops: lead + trail, startPoint: .leading, endPoint: .trailing)
    }

    /// The soft painting across the whole `width`, lined up with the sharp
    /// one — the same fill, so every landmark's blur stands behind the
    /// landmark — and shaded and tinted as the painting is: the same top and
    /// foot shade, and the tier's tint about the painting's own centre, so a
    /// Hard or Hell map's haze carries its tier. With no soft painting (none
    /// in the bundle, or Core Image refused it) it is the chapter's colour,
    /// and the rim does not feather.
    private func hazeBackdrop(_ chapter: Chapter, size: CGSize, soft: SoftMapPainting.Padded?,
                              width: CGFloat, leading: CGFloat) -> some View {
        let centre = UnitPoint(x: (leading + size.width / 2) / max(1, width), y: 0.5)
        return ZStack(alignment: .topLeading) {
            Color.clear
                .overlay(alignment: .topLeading) {
                    if let soft {
                        // The painting's fill as `paintingImage` draws it:
                        // points per thumbnail pixel, and the pixels its
                        // left and top edges fall on.
                        let scale: CGFloat = max(size.width / soft.sourceWidth, size.height / soft.sourceHeight)
                        let left: CGFloat = (soft.sourceWidth - size.width / scale) / 2
                        let top: CGFloat = (soft.sourceHeight - size.height / scale) / 2
                        Image(uiImage: soft.image)
                            .resizable()
                            .frame(width: soft.paddedWidth * scale, height: soft.sourceHeight * scale)
                            .offset(x: leading - (soft.margin + left) * scale, y: -top * scale)
                    } else {
                        Rectangle().fill(chapter.pantheon.color.opacity(0.25))
                    }
                }
            paintingShade
            tierTint(size: size, centre: centre)
        }
        .frame(width: width, height: size.height)
        .overlay(alignment: .bottom) { Self.footShade }
        .clipped()
    }

    /// An inset's haze darkening from nothing at the painting's edge to deep
    /// at the glass.
    private func insetShade(width: CGFloat, height: CGFloat, towardLeading: Bool) -> some View {
        LinearGradient(
            stops: [
                .init(color: Theme.ink.opacity(0), location: 0),
                .init(color: Theme.ink.opacity(0.28), location: 0.4),
                .init(color: Theme.ink.opacity(0.74), location: 1),
            ],
            startPoint: towardLeading ? .trailing : .leading,
            endPoint: towardLeading ? .leading : .trailing
        )
        .frame(width: width, height: height)
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
        let bossPortrait = ChapterMapArt.bossPortrait(for: chapter)
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
        .buttonStyle(GamePressStyle(.medallion, sounds: unlocked))
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
            // A crown for a boss with no card, and the portrait's own small
            // lock on it while shut — a bare lock read as "locked, danger",
            // not as the thing the road walks toward.
            Image(systemName: "crown.fill")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(state == .cleared ? Theme.ink : Theme.onGlassDanger)
                .opacity(state == .locked ? 0.8 : 1)
                .frame(width: diameter - 8, height: diameter - 8)
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

    /// The chapter on the map as one line of glass: the two sets its road
    /// yields — with their names where the map has room, as stones alone
    /// where it does not — and a chevron that opens the scroll. The form and
    /// the place are solved by `ChapterMapArt`; the capsule hugs what it
    /// holds (the named form had a 60-point gap before its chevron). How far
    /// the road is walked is the strip's second line.
    private func chapterTab(_ chapter: Chapter, form: ChapterMapArt.TabForm) -> some View {
        Button {
            withAnimation(Motion.panel) { scrollOpen.toggle() }
        } label: {
            HStack(spacing: 8) {
                HStack(spacing: form == .seal ? 6 : 8) {
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
                Image(systemName: scrollOpen ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Theme.onGlassDim)
            }
            .padding(.horizontal, 12)
            .fixedSize(horizontal: true, vertical: false)
            .frame(height: ChapterMapArt.tabHeight)
            .background(GlassPlate(radius: ChapterMapArt.tabHeight / 2))
            .contentShape(Capsule())
        }
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel("\(chapter.name), the chapter's story and yields")
    }

    /// The chapter's scroll, open over the map from its tab: where it is
    /// (realm and chapter), its name carved, its story line, how far the
    /// road is walked and what comes next, what it yields, and the tier's
    /// terms — or, on Normal, what opens Hard. Deep glass (0.94) because it
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
                .buttonStyle(GamePressStyle(.medallion))
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
        // Deeper than any plate: a paragraph over a painting (0.86 let a
        // medallion show through the story, run 216).
        .background(GlassPlate(radius: 14, opacity: 0.94))
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
        let order = StageDatabase.chapterOrder(of: base.id)
        switch tier {
        case .normal:
            return Self.terms(.normal, chapterOrder: order)
        case .hard:
            return open ? Self.terms(.hard, chapterOrder: order) : "Hard opens when \(base.name)'s boss falls on Normal."
        case .hell:
            return open ? Self.terms(.hell, chapterOrder: order) : "Hell opens when \(base.name)'s boss falls on Hard."
        }
    }

    /// A tier's terms in the game's own numbers for this chapter — "Hell ·
    /// two grades up · enemies ×1.5 · relics 4★+ · ×2.6 drachma & EXP".
    /// Read off `CampaignDifficulty`, never written out: the line said
    /// "every stage drops a 6★ relic" on every chapter, which has not been
    /// the rule since the relic floor began to climb with the chapter
    /// (2026-09-16: Hell pays 4★ in chapter 1 and 6★ from chapter 7, at a
    /// 45% floor), and "×1.5" did not say what it multiplied.
    static func terms(_ tier: CampaignDifficulty, chapterOrder: Int) -> String {
        let grades: String
        switch tier.starBonus {
        case 0: return "Normal · the story · relics as each stage gives them"
        case 1: grades = "a grade up"
        case 2: grades = "two grades up"
        default: grades = "\(tier.starBonus) grades up"
        }
        let stats = String(format: "%.1f", tier.statScale)
        let pay = String(format: "%.1f", tier.rewardScale)
        let relicFloor = tier.relicGradeFloor(chapterOrder: chapterOrder)
        let name = tier.displayName
        return "\(name) · \(grades) · enemies ×\(stats) · relics \(relicFloor)★+ · ×\(pay) drachma & EXP"
    }

    /// The tier's terms as one line of glass along the top of the map.
    private func tierLine(_ tier: CampaignDifficulty, base: Chapter) -> some View {
        let words = Self.terms(tier, chapterOrder: StageDatabase.chapterOrder(of: base.id))
        let tint = Color(hex: tier.glowHex)
        return HStack(spacing: 6) {
            Image(systemName: tier.glyph)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(tint)
            Text(words)
                .font(Theme.body(11.5).weight(.bold))
                .foregroundStyle(Theme.onGlass)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(Capsule().fill(Color(hex: "#17120E").opacity(0.9)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.8), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
    }

    /// Says a tier's terms for about three seconds (for as long as the tour
    /// photographs); Normal says nothing.
    private func announce(_ tier: CampaignDifficulty) {
        guard tier != .normal else {
            withAnimation(.easeOut(duration: 0.2)) { tierToast = nil }
            return
        }
        withAnimation(.easeOut(duration: 0.25)) { tierToast = tier }
        guard !Self.touring else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            guard tierToast == tier else { return }
            withAnimation(.easeIn(duration: 0.35)) { tierToast = nil }
        }
    }

    /// The map's measured size and where its tab stood, on the console
    /// (DEBUG only): run 216's map was laid out 58 points taller than the
    /// phone showed and a green test described a size the view never got,
    /// so the size the view DOES get is printed for the CI job to read.
    private static func report(_ chapterID: String, size: CGSize, origin: CGPoint, form: ChapterMapArt.TabForm) {
        #if DEBUG
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())
        let x = Int(origin.x.rounded())
        let y = Int(origin.y.rounded())
        print("[ChapterMap] \(chapterID) size \(width)x\(height) tab \(form) at \(x),\(y)")
        #endif
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
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .black))
                .foregroundStyle(Theme.onGlassGold)
                .frame(width: 40, height: 40)
                .background(GlassPlate(radius: 20))
                .contentShape(Circle())
        }
        .buttonStyle(GamePressStyle(.medallion))
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
        .buttonStyle(GamePressStyle(.plate))
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
                    // Every chapter map's haze, built while the player picks
                    // a city, so the first map opened has it in its first
                    // frame (`SoftMapPainting`).
                    SoftMapPainting.warm(ChapterMapArt.byChapter.values.map(\.image))
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
        // The road pans, but its twelve cities stand apart on the painting,
        // so a drag rarely starts on one: the full press, silent when shut.
        .buttonStyle(GamePressStyle(.medallion, sounds: state != .locked))
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
///
/// ONE panel, sized to what it holds and centred in the screen (run 217):
/// the chest and Claim on the left, a gold hairline, and what the tribute
/// holds on the right as a centred group — the header between two rules,
/// the grants as 72-point tiles, the relic line, the footnote. It was two
/// cream panels: the right one stretched to the screen's foot with two
/// 52-point tiles in its top corner, 85% empty, the left one ending 110
/// pixels higher, and the header's and the footnote's first letters on the
/// painted panel's acanthus corners. The content now stands `cornerReach`
/// in from every side, clear of the scrolls.
struct TributeCard: View {
    let tribute: Tribute
    let chapterID: String
    let difficulty: CampaignDifficulty

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var opened = false
    @State private var receipt: TributeService.Receipt?

    private var chapter: Chapter? { StageDatabase.chapter(chapterID)?.at(difficulty) }

    /// How far the painted panel's acanthus corners reach in, and a margin:
    /// about 20 points measured on run 217's frame (SectionPanel's header
    /// was moved in for the same scrolls).
    private static let cornerReach: CGFloat = 24
    private static let cornerReachDown: CGFloat = 22
    /// The chest's column; Claim's label takes about 200 of it.
    private static let chestColumn: CGFloat = 240
    /// The gap either side of the hairline between the two columns.
    private static let columnGap: CGFloat = 28
    /// The holds' column: the grants as 72-point tiles, or 60 for the Hell
    /// judgment's four (4 × 81 + 3 × 6 = 342), and their names.
    private static let holdsColumn: CGFloat = 380
    private static let holdsColumnMin: CGFloat = 300

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
                    card(chapter)
                        .padding(.horizontal, ScreenChrome.contentPadding)
                        .padding(.vertical, 6)
                } else {
                    EmptyState(icon: "questionmark", title: "No such road", message: "This chapter is not in the campaign.")
                }
            }
        }
    }

    /// The one panel: both columns at the height of the taller, the holds
    /// centred against the chest, a hairline between them.
    private func card(_ chapter: Chapter) -> some View {
        HStack(alignment: .center, spacing: Self.columnGap) {
            chestPane(chapter)
                .frame(width: Self.chestColumn)
            contents(chapter)
                .frame(minWidth: Self.holdsColumnMin, maxWidth: Self.holdsColumn)
        }
        .overlay(alignment: .topLeading) {
            Rectangle()
                .fill(Theme.goldDim.opacity(0.35))
                .frame(width: 1)
                .padding(.vertical, 8)
                .offset(x: Self.chestColumn + Self.columnGap / 2)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, Self.cornerReach)
        .padding(.vertical, Self.cornerReachDown)
        .panelBackground(radius: Theme.tightCorner)
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
            .frame(width: Self.chestColumn - 10, height: 140)
            // A met requirement is said as done, in green — "Clear Scarab
            // Court" beside Claim read as "go clear it" and "claim it" at
            // once (run 217).
            if earned || claimed {
                Label(metLine(chapter), systemImage: "checkmark.circle.fill")
                    .font(Theme.body(11.5).weight(.semibold))
                    .foregroundStyle(Theme.success)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(TributeService.requirement(tribute, chapter: chapter))
                    .font(Theme.body(11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if claimed {
                Label("Claimed", systemImage: "checkmark.seal.fill")
                    .font(Theme.body(12).weight(.bold))
                    .foregroundStyle(Theme.success)
            } else if earned {
                PrimaryButton(title: "Claim the tribute", systemImage: "gift.fill") {
                    claim(chapter)
                }
            } else {
                Label("Not yet earned", systemImage: "lock.fill")
                    .font(Theme.body(12).weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// The requirement as done.
    private func metLine(_ chapter: Chapter) -> String {
        switch tribute.milestone {
        case .third:
            guard !chapter.stages.isEmpty else { return "Cleared" }
            let stage = chapter.stages[min(2, chapter.stages.count - 1)]
            return "\(stage.name) cleared"
        case .boss:
            return "The boss of \(chapter.name) has fallen"
        case .flawless:
            return "Three stars on every stage"
        }
    }

    /// The header between two rules, the grants as a centred row of tiles,
    /// the relic, and the footnote — a group centred in its column.
    private func contents(_ chapter: Chapter) -> some View {
        let grants = tribute.grants
        // Three tiles at 72 with their names (1.35 of the tile) are 304
        // points, four at 60 are 342: either fits the 380-point column, and
        // the Hell judgment's four still fit a phone without side insets.
        let tile: CGFloat = grants.count >= 4 ? 60 : 72
        return VStack(alignment: .center, spacing: 12) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Theme.stroke.opacity(0.8))
                    .frame(height: 1)
                Text(receipt == nil ? "THE TRIBUTE HOLDS" : "YOU RECEIVED")
                    .font(Theme.body(11).weight(.black))
                    .tracking(1.2)
                    .foregroundStyle(Theme.goldDim)
                    .lineLimit(1)
                    .fixedSize()
                Rectangle()
                    .fill(Theme.stroke.opacity(0.8))
                    .frame(height: 1)
            }
            // The grants as the genre's tiles, the count on each, the name
            // under it.
            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(grants.enumerated()), id: \.offset) { _, grant in
                    RewardTile(grant: grant, size: tile)
                }
            }
            .frame(maxWidth: .infinity)
            if let grade = tribute.relicGrade {
                HStack(spacing: 8) {
                    if let relic = receipt?.relic {
                        RelicIcon(relic: relic, size: 36, showsStars: true, showsLevel: false, showsSlot: true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(relic.displayName)
                                .font(Theme.body(12).weight(.semibold))
                                .foregroundStyle(relic.resolvedQuality.inkColor)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Slot \(relic.slot) · \(relic.effectiveMainStat.displayText)")
                                .font(Theme.body(11))
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
                                .font(Theme.body(11))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous).fill(Theme.surfaceHigh))
            }
            Text(footnote)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
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
