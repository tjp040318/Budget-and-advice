import XCTest
@testable import Pantheon

/// The chapter map's placements (2026-09-22, phase B): every one of the
/// twelve maps shows its tab, the tab never stands on the road, every
/// medallion is whole in the frame, and no mark stands on another.
///
/// Run 211 photographed the chapter's 300-point cream plate over one to
/// three medallions on every one of the twelve maps — and those frames were
/// taken without the tab bar, 58 points taller than the phone. So the sizes
/// here are the map's content UNDER the strip and the `GameTabBar`: the
/// screen less its side insets across, less the home indicator, the 58-point
/// bar and the 52-point strip down. The SE is asserted too: the solve's
/// smallest form clears every map on it.
///
/// Run 216 showed what these tests could not: the map was still LAID OUT at
/// 734 × 320 on the CI phone (the bar was an inset the map never saw), the
/// tab was solved into the bottom row under the bar, and four maps showed no
/// tab at all while these passed at 262. The bar is laid out under the tab
/// since then, the map prints the size it gets (`[ChapterMap] … size WxH`),
/// and 320 — the same map with nothing under it — is a frame here too, so
/// the tab has clear ground whichever the view is given.
final class ChapterMapTests: XCTestCase {

    /// The map's content on the phones the game runs on, and the CI phone's
    /// map with no bar under it.
    private let frames: [(name: String, size: CGSize)] = [
        ("CI phone 852 × 393", CGSize(width: 734, height: 262)),
        ("iPhone 16 Pro 874 × 402", CGSize(width: 750, height: 271)),
        ("6.1-inch 844 × 390", CGSize(width: 750, height: 259)),
        ("iPhone 16 Pro Max 956 × 440", CGSize(width: 832, height: 309)),
        ("iPhone SE 667 × 375", CGSize(width: 667, height: 265)),
        ("6.7-inch map of 814 × 303", CGSize(width: 814, height: 303)),
        ("CI phone with no bar under the map", CGSize(width: 734, height: 320)),
    ]

    /// The tab's place is solved once per map from every medallion at its
    /// largest, so it is the same whatever the progress; the intent is that
    /// every one of the twelve maps has its tab, inside the frame, and that
    /// no medallion, chest or arrow is ever under it, four points clear.
    func testChapterTabFindsClearGroundOnEveryMap() {
        XCTAssertEqual(ChapterMapArt.byChapter.count, 12)
        for (id, art) in ChapterMapArt.byChapter.sorted(by: { $0.key < $1.key }) {
            guard let chapter = StageDatabase.chapter(id) else {
                XCTFail("\(id) is not a campaign chapter")
                continue
            }
            let bosses: [Bool] = chapter.stages.map(\.isBoss)
            XCTAssertGreaterThanOrEqual(art.nodes.count, bosses.count, id)
            for frame in frames {
                let marks = ChapterMapArt.marks(art, bosses: bosses, imageSize: ChapterMapArt.paintingSize, in: frame.size)
                let obstacles = ChapterMapArt.obstacles(nodes: marks.nodes, bosses: bosses, chests: marks.chests, in: frame.size)
                let slot = ChapterMapArt.tabSlot(obstacles: obstacles, in: frame.size)
                let rect = CGRect(origin: slot.origin, size: CGSize(width: slot.form.width, height: ChapterMapArt.tabHeight))
                let clear: Bool = !obstacles.contains { $0.intersects(rect) }
                XCTAssertTrue(clear, "\(id) on the \(frame.name): the tab stands on the road at \(rect)")
                let inside: Bool = CGRect(origin: .zero, size: frame.size).contains(rect)
                XCTAssertTrue(inside, "\(id) on the \(frame.name): the tab leaves the frame at \(rect)")
            }
        }
    }

    /// Every medallion's disc and its foot (the stars, the energy, BOSS, 22
    /// points under the disc) are whole inside the frame: under the tab bar
    /// the painting's fill crops about 26 points off each end of a 21:9 map,
    /// and a landmark at 0.16 or 0.82 of the painting put its medallion
    /// half under the strip or its foot under the bar until it was held.
    func testEveryMedallionIsWholeInTheFrame() {
        for (id, art) in ChapterMapArt.byChapter.sorted(by: { $0.key < $1.key }) {
            guard let chapter = StageDatabase.chapter(id) else { continue }
            let bosses: [Bool] = chapter.stages.map(\.isBoss)
            for frame in frames {
                let marks = ChapterMapArt.marks(art, bosses: bosses, imageSize: ChapterMapArt.paintingSize, in: frame.size)
                for (index, point) in marks.nodes.enumerated() {
                    let radius = ChapterMapArt.medallionRadius(isBoss: bosses[index])
                    let footBottom: CGFloat = point.y + radius + 22
                    let discTop: CGFloat = point.y - radius
                    let left: CGFloat = point.x - radius
                    let right: CGFloat = point.x + radius
                    let whole: Bool = discTop >= 0 && footBottom <= frame.size.height
                        && left >= 0 && right <= frame.size.width
                    XCTAssertTrue(whole, "\(id) stage \(index + 1) on the \(frame.name) at \(point)")
                }
            }
        }
    }

    /// No mark stands on another: each medallion's disc with its foot (the
    /// stars, the energy, BOSS) and each chest are clear of every other on
    /// every map and phone. Run 216 photographed Jötunheim's fourth stage
    /// directly above its second, the Aegean road chest over the fourth
    /// stage's stars and a boss's BOSS foot on the disc below it; nothing
    /// tested mark against mark, only marks against the tab. A hairline of
    /// touch is not a collision (each rect is inset half a point).
    func testNoMarkStandsOnAnother() {
        for (id, art) in ChapterMapArt.byChapter.sorted(by: { $0.key < $1.key }) {
            guard let chapter = StageDatabase.chapter(id) else { continue }
            let bosses: [Bool] = chapter.stages.map(\.isBoss)
            for frame in frames {
                let marks = ChapterMapArt.marks(art, bosses: bosses, imageSize: ChapterMapArt.paintingSize, in: frame.size)
                let rects: [CGRect] = ChapterMapArt.markRects(nodes: marks.nodes, bosses: bosses, chests: marks.chests)
                    .map { $0.insetBy(dx: 0.5, dy: 0.5) }
                let stageNames: [String] = bosses.indices.map { index in "stage \(index + 1)" }
                let chestNames: [String] = ["the road's chest", "the gate's chest", "the judgment's chest"]
                let names: [String] = stageNames + chestNames
                for first in rects.indices {
                    for second in rects.indices where second > first {
                        let apart: Bool = !rects[first].intersects(rects[second])
                        XCTAssertTrue(apart, "\(id) on the \(frame.name): \(names[first]) stands on \(names[second])")
                    }
                }
            }
        }
    }

    /// A map with no clear ground anywhere still gets its tab: the small
    /// form, inside the frame. The intent is "never nothing" — run 216 had
    /// four maps with no tab at all.
    func testTabIsPlacedEvenWithNoClearGround() {
        for frame in frames {
            let everywhere = [CGRect(origin: .zero, size: frame.size)]
            let slot = ChapterMapArt.tabSlot(obstacles: everywhere, in: frame.size)
            let rect = CGRect(origin: slot.origin, size: CGSize(width: slot.form.width, height: ChapterMapArt.tabHeight))
            let inside: Bool = CGRect(origin: .zero, size: frame.size).contains(rect)
            XCTAssertTrue(inside, "on the \(frame.name) the fallback tab leaves the frame at \(rect)")
            XCTAssertEqual(slot.form, .seal)
        }
    }

    /// The boss medallion of every chapter shows a face or the crown, and
    /// the faces that exist are found through the mesh a boss fights in:
    /// the Colossus of the Sun wears the Vault's Colossus's card and the
    /// Dragon of Longmen the Dragon King's (run 216 drew a bare lock on
    /// four of twelve maps). The intent: a boss with ANY card in the bundle
    /// is never drawn without it.
    func testBossPortraitFallsBackThroughTheStandIn() {
        let rome = StageDatabase.chapter("rome_2")
        let jade = StageDatabase.chapter("jade_2")
        XCTAssertNotNil(rome)
        XCTAssertNotNil(jade)
        if let rome, BundleArt.exists("portrait_boss_colossus") {
            let face: String? = ChapterMapArt.bossPortrait(for: rome)
            XCTAssertEqual(face, "portrait_boss_colossus")
        }
        if let jade, BundleArt.exists("portrait_dragon_king_tide") {
            let face: String? = ChapterMapArt.bossPortrait(for: jade)
            XCTAssertEqual(face, "portrait_dragon_king_tide")
        }
    }

    /// The tab's widths hold their longest content, measured in the shipped
    /// Manrope: the named form's longest pair (Zephyr and Titanfall, their
    /// stones and the chevron) is 190 points, the seal 88. A smaller
    /// constant would let the solve place a tab the content overruns onto
    /// the road; the intent is that each form stays at least that wide.
    func testTabFormsHoldTheirContent() {
        let named: CGFloat = ChapterMapArt.TabForm.named.width
        let seal: CGFloat = ChapterMapArt.TabForm.seal.width
        XCTAssertGreaterThanOrEqual(named, 190)
        XCTAssertGreaterThanOrEqual(seal, 88)
    }
}
