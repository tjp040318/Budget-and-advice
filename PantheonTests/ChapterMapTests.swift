import XCTest
@testable import Pantheon

/// The chapter map's placements (2026-09-22, phase B): the chapter's tab
/// never stands on the road, and every medallion is whole in the frame.
///
/// Run 211 photographed the chapter's 300-point cream plate over one to
/// three medallions on every one of the twelve maps — and those frames were
/// taken without the tab bar, 58 points taller than the phone. So the sizes
/// here are the map's content UNDER the strip and the `GameTabBar`: the
/// screen less its side insets across, less the home indicator, the 58-point
/// bar and the 52-point strip down. The SE is asserted too: the solve's
/// smallest form clears every map on it.
final class ChapterMapTests: XCTestCase {

    /// The map's content on the phones the game runs on.
    private let frames: [(name: String, size: CGSize)] = [
        ("CI phone 852 × 393", CGSize(width: 734, height: 262)),
        ("iPhone 16 Pro 874 × 402", CGSize(width: 750, height: 271)),
        ("6.1-inch 844 × 390", CGSize(width: 750, height: 259)),
        ("iPhone 16 Pro Max 956 × 440", CGSize(width: 832, height: 309)),
        ("iPhone SE 667 × 375", CGSize(width: 667, height: 265)),
    ]

    /// The tab's place is solved once per map from every medallion at its
    /// largest, so it is the same whatever the progress; the intent is that
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

    /// The tab's widths hold their longest content, measured in the shipped
    /// Manrope: the named form's longest pair (Zephyr and Titanfall) is 258
    /// points, the stones form 158, the seal 88. A smaller constant would
    /// clip the content inside a tab the solve placed; the intent is that
    /// each form stays at least that wide.
    func testTabFormsHoldTheirContent() {
        let named: CGFloat = ChapterMapArt.TabForm.named.width
        let stones: CGFloat = ChapterMapArt.TabForm.stones.width
        let seal: CGFloat = ChapterMapArt.TabForm.seal.width
        XCTAssertGreaterThanOrEqual(named, 258)
        XCTAssertGreaterThanOrEqual(stones, 158)
        XCTAssertGreaterThanOrEqual(seal, 88)
    }
}
