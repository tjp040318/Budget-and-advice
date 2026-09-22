import XCTest
@testable import Pantheon

/// The painted doors (2026-09-22, phase B; PLAN.md, *The painted doors*):
/// the five tabs and the island header's four doors are painted objects,
/// `tab_<key>.png`, cut from one sheet by `tools/tab_icons.py`. A door whose
/// file is missing still draws — its SF glyph in the same socket — so a lost
/// file would never show as a crash, only as one system symbol back in the
/// tab bar beside four paintings. This is the check that fails instead.
final class ChromeArtTests: XCTestCase {

    /// Every key the tab bar, the island header and More ask for is in the
    /// bundle. The test target is hosted in the app, so `Bundle.main` holds
    /// the Portraits.
    func testEveryChromeIconIsPainted() {
        let missing = ChromeArt.allKeys.filter { !ChromeArt.hasPainting($0) }
        XCTAssertEqual(missing, [], "tab_<key>.png missing from the bundle: python3 tools/tab_icons.py --split")
    }

    /// The nine are the doors that exist, once each: the five tabs and the
    /// header's missions, allies, events and decorations. A tenth key with
    /// no door, or a door listed twice, is a sheet cell painted for nothing.
    func testTheKeysAreTheNineDoors() {
        let keys = ChromeArt.allKeys
        let unique = Set(keys)
        XCTAssertEqual(unique.count, keys.count, "a chrome key is listed twice")
        let doors: Set<String> = ["island", "campaign", "arena", "summon", "collection",
                                  "missions", "allies", "events", "decor"]
        XCTAssertEqual(unique, doors)
    }

    /// An empty key — More's bazaar and lessons, which have no painting yet —
    /// is never a painting, so those doors draw their glyph rather than
    /// asking the bundle for "tab_".
    func testAnEmptyKeyIsTheGlyph() {
        XCTAssertFalse(ChromeArt.hasPainting(""))
        XCTAssertEqual(ChromeArt.imageName("arena"), "tab_arena")
    }
}
