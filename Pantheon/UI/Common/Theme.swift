import SwiftUI
import CoreText
import UIKit

/// The app's visual language, in one place.
///
/// The brief is a collection RPG, not a utility app, and the difference is
/// almost entirely depth and rarity. Two rules drive everything below:
///
/// 1. **Nothing is a flat fill.** Every surface is a gradient with a light top
///    edge and a dark bottom rim, so panels read as objects with a thickness
///    rather than as coloured rectangles. A single hairline stroke on a solid
///    fill is what makes an interface look like Settings.
/// 2. **Rarity is the loudest thing on screen.** A 5★ and a 1★ must be
///    distinguishable across the room, before a single word is read. The frame
///    carries that, not a text label — see `Rarity`.
///
/// Colours are still derived from the same hex strings the 3D layer uses, so a
/// Radiance unit is the same yellow on its card and in its aura.
enum Theme {

    // MARK: - Palette

    // MARBLE AND VERDIGRIS BRONZE, chosen by the owner on 2026-09-10 after
    // "I hate the UI of the game. It just doesn't feel premium, the menu
    // colours are awful looking."
    //
    // He was right, and the reason was measurable rather than a matter of
    // taste. EVERY surface was one hue: ground #07060F, panel #141328, raised
    // #1F1D3D, high #2A274F, the border #3B3766 and even the secondary text
    // #9E97C4 were all violet around 250°, five lightnesses of one muddy
    // colour. Three things followed from that and all three read as cheap.
    //
    // 1. NOTHING COULD BE A MATERIAL. Stone, metal, parchment and lacquer are
    //    what a collection RPG builds a menu out of; tints of one colour give
    //    you none of them. The palette below is deliberately TWO families in
    //    tension — warm bronze and marble against cool slate — because a
    //    single family is what made the old screens read as a dark theme
    //    rather than as objects.
    // 2. THE STEPS WERE TOO CLOSE. Six per cent of lightness apart, flat
    //    filled. A panel did not look raised, it looked like a slightly
    //    lighter rectangle. These are further apart and every panel now
    //    carries a gradient with a lit top edge and a dark rim.
    // 3. THE BORDER WAS A PURPLE LINE, not a metal. A hairline in a tint of
    //    the fill reads as a wireframe. It is aged bronze over a dark outer
    //    line now, which is what the genre actually does.

    /// Cold near-black with a blue cast: the back of the cabinet, behind
    /// everything. Never a panel.
    static let ink = Color(hex: "#1F1912")
    /// The screen's ground — dark slate, a shade up from ink.
    static let surface = Color(hex: "#EBE2CF")
    /// A panel. This is the marble the whole interface is built from.
    static let surfaceRaised = Color(hex: "#F6F0E3")
    /// A panel on a panel: an inset well, a selected row, a sub-card.
    static let surfaceHigh = Color(hex: "#FDF9F0")
    /// The cool line UNDER the metal. The bronze frame sits on it, and the
    /// dark line is what stops the frame glowing into the background.
    static let stroke = Color(hex: "#CDBB98")

    /// Bronze, not gold. `gold` keeps its name because two hundred call sites
    /// use it and the meaning — "the metal, the heading, the important
    /// number" — has not changed.
    static let gold = Color(hex: "#B08A2E")
    static let goldDim = Color(hex: "#8C6D22")
    static let goldDeep = Color(hex: "#5C4611")

    /// Warm off-white: marble, not paper. Against the cool slate panels this
    /// is what carries the second colour family.
    static let textPrimary = Color(hex: "#2A2116")
    /// Cool slate grey. Deliberately NOT a tint of the bronze — the contrast
    /// between a warm heading and a cool caption is half of what makes a
    /// screen look designed rather than themed.
    static let textSecondary = Color(hex: "#6D5F4B")

    /// Wine, laurel and verdigris: the three accents. Every one of them is a
    /// real pigment from the same world as the bronze, which is why they sit
    /// together instead of shouting.
    static let danger = Color(hex: "#B4364C")
    static let success = Color(hex: "#4E8A3E")
    static let info = Color(hex: "#2F7F6E")

    /// Named for what they are, for the places that want the pigment rather
    /// than the meaning: a laurel wreath, a wine seal, a verdigris edge, a
    /// marble reading surface.
    static let wine = Color(hex: "#8E2740")
    static let laurel = Color(hex: "#6B8F4E")
    static let verdigris = Color(hex: "#4E8A72")
    static let marble = Color(hex: "#D9D4C8")
    static let bronze = Color(hex: "#A8894F")
    /// The translucent plate over a scene or a painting — the battle HUD,
    /// the Hall of Ka's rail, the island's labels: cream, so its ink reads,
    /// the way the panels do. It was `ink` at half opacity when the
    /// interface was slate; a dark plate under dark text is unreadable.
    static let plate = Color(hex: "#F4EDDD")

    /// Ink or cream, whichever reads on the colour given. The drawn button
    /// plates are the tint itself, and a tint can be anything from gold to
    /// ink.
    static func readableText(on color: Color) -> Color {
        isLight(color) ? ink : surfaceHigh
    }

    /// Whether a colour is pale enough to carry ink: luma over 0.55. A colour
    /// that cannot be read back (a pattern) counts as light, so its text is
    /// ink like everything else on the cream interface.
    static func isLight(_ color: Color) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return true }
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.55
    }

    // MARK: - Metal

    /// Polished bronze. Four stops, because the pale band across the upper
    /// third is what reads as METAL rather than as an orange rectangle, and
    /// the dark foot is what gives it a thickness.
    static let goldPlate = LinearGradient(
        colors: [Color(hex: "#6B5528"), Color(hex: "#E4CE93"),
                 Color(hex: "#B0904F"), Color(hex: "#4A3A1C")],
        startPoint: .top,
        endPoint: .bottom
    )

    /// A bronze frame that has gone green where it has been handled. The
    /// verdigris stop is the whole difference between "gold border" and
    /// "an old bronze frame", and it costs one colour.
    static let bronzeFrame = LinearGradient(
        colors: [Color(hex: "#D6BE86"), Color(hex: "#A8894F"),
                 Color(hex: "#4E8A72").opacity(0.55), Color(hex: "#3E3218")],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// The reading surface: aged marble for anything that carries a lot of
    /// words — lore, a rate table, a briefing.
    static let marblePlate = LinearGradient(
        colors: [Color(hex: "#E4E0D5"), Color(hex: "#CFC9BA")],
        startPoint: .top,
        endPoint: .bottom
    )

    /// The indigo wash for a raised plate that is not a panel — the island's
    /// landmark discs are the one caller left. Kept as it was;
    /// `drawnPanelPlate` is what a panel uses now.
    static let panelPlate = LinearGradient(
        colors: [surfaceHigh, surfaceRaised, surface],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Dark polished marble, with the cool blue cast that stone has in
    /// shadow. Three stops so the top catches the light.
    static let stonePlate = LinearGradient(
        colors: [Color(hex: "#F7F2E7"), Color(hex: "#EBE3D0"), Color(hex: "#DED4BE")],
        startPoint: .top,
        endPoint: .bottom
    )

    /// The body of a code-drawn panel: the painted panel's own centre, which
    /// samples at (22, 23, 28), with just enough gradient that it does not
    /// read as a flat fill. See `drawnPanel` for why it is not `panelPlate`.
    static let drawnPanelPlate = LinearGradient(
        colors: [Color(hex: "#FBF6EA"), Color(hex: "#F2EBDA"), Color(hex: "#E7DEC8")],
        startPoint: .top,
        endPoint: .bottom
    )

    /// A one-pixel highlight along the top edge and a dark rim along the
    /// bottom. Cheap, and it does most of the work of making a panel solid.
    /// A lit top edge and a dark rim along the bottom. Warmed slightly and
    /// deepened from the first pass: a colder, fainter bevel is exactly what
    /// made the old panels read as rectangles instead of as objects with a
    /// thickness. It is still only two colours and it does most of the work.
    static let bevel = LinearGradient(
        colors: [Color.white.opacity(0.85), Color.white.opacity(0.25),
                 Color.clear, Color(hex: "#5A4A2E").opacity(0.22)],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Type

    /// Headline voice. Heavy and wide-tracked; the previous serif fought with
    /// the rounded titles and neither won.
    /// One knob for the whole app's type. The genre runs small — a landscape
    /// phone is 430 points tall and Summoners War fits a team, a grid and a
    /// bar into it — and the first playtest asked for exactly that density.
    static let fontScale: CGFloat = 0.9

    /// A ROMAN SERIF for the two headline roles, against the system sans for
    /// everything else.
    ///
    /// A serif was tried once before and removed, with the note that it "fought
    /// with the rounded titles and neither won". That was true against the old
    /// indigo palette, where the interface had no material of its own for a
    /// serif to belong to. Against marble and bronze it is the opposite: a
    /// heavy Roman capital is what carved lettering looks like, and it is the
    /// single largest thing separating a premium collection RPG from an app
    /// that happens to be dark. It costs nothing — no font file, no bundle
    /// weight — because the system ships a serif design.
    ///
    /// Only `display` and `title` take it, thirty-three call sites between
    /// them. Body text stays sans, because a serif at eleven points on a phone
    /// is worse to read and this game asks people to read a lot of skill
    /// descriptions; numbers stay monospaced so stat columns line up. Two
    /// voices, each doing the job it is good at, which is the whole of
    /// typography.
    /// The two bundled faces (`Pantheon/Resources/Fonts`, OFL, registered
    /// at launch by `FontLibrary`): **Cinzel** — Roman inscriptional
    /// capitals, the lettering a temple actually wears — for the carved
    /// roles, and **Manrope** — a clean geometric sans with true tabular
    /// figures — for every word and every number. The system serif and the
    /// monospaced digits it replaces were two of the three things the owner
    /// read as "not premium" (2026-09-12). A missing file falls back to the
    /// system face, so a broken bundle is a plainer game, never a blank one.
    static let carvedFace = "Cinzel-Bold"
    static let carvedHeavyFace = "Cinzel-Black"
    static let textFace = "Manrope-Medium"
    static let numberFace = "Manrope-Bold"

    private static let hasCarved: Bool = UIFont(name: carvedFace, size: 12) != nil
    private static let hasText: Bool = UIFont(name: textFace, size: 12) != nil

    /// Nothing on the phone under ten points. The density pass left ninety
    /// call sites at 7–9, which after `fontScale` was 6.3–8.1 on the
    /// screen; Apple's floor for legible text is 11 and the genre's smallest
    /// label about that. The floor lifts them all at once.
    static let bodyFloor: CGFloat = 10
    static let numericFloor: CGFloat = 10.5
    static let titleFloor: CGFloat = 12

    static func display(_ size: CGFloat) -> Font {
        let points = max(titleFloor, size * fontScale)
        return hasCarved ? .custom(carvedHeavyFace, size: points) : .system(size: points, weight: .black, design: .serif)
    }

    static func title(_ size: CGFloat = 20) -> Font {
        let points = max(titleFloor, size * fontScale)
        return hasCarved ? .custom(carvedFace, size: points) : .system(size: points, weight: .heavy, design: .serif)
    }

    static func body(_ size: CGFloat = 15) -> Font {
        let points = max(bodyFloor, size * fontScale)
        return hasText ? .custom(textFace, size: points) : .system(size: points, weight: .medium, design: .default)
    }

    /// Numbers keep tabular figures so columns of stats line up, which
    /// matters more here than in most apps — the whole game is comparing
    /// two stat blocks. Manrope's `tnum` does it without a monospaced face.
    static func numeric(_ size: CGFloat = 15) -> Font {
        let points = max(numericFloor, size * fontScale)
        return hasText
            ? Font.custom(numberFace, size: points).monospacedDigit()
            : .system(size: points, weight: .bold, design: .monospaced)
    }

    // MARK: - Shapes
    //
    // One scale for each of the three things a screen keeps re-deciding:
    // how round a thing is, how tall a control is, and how far content sits
    // from a panel's edge. Before this the screens carried `cornerRadius: 6`
    // in five places, 8 in four, 10 in two and 14 in two; control heights of
    // 22, 24, 26, 28, 30, 32 and 34 for the same class of object; and chip
    // padding of 3, 4, 5, 6, 7 and 9. Read the object, not the number.

    /// A panel or a sheet.
    static let cornerRadius: CGFloat = 12
    /// A card, a plate, a primary button.
    static let tightCorner: CGFloat = 8
    /// Anything control-sized. It *is* the strip's radius
    /// (`ScreenChrome.corner`), so a filter tile in the strip and a tile in
    /// the grid below it are the same shape rather than nearly the same.
    static let tileCorner: CGFloat = ScreenChrome.corner

    /// A read-only tag: a set name, a role, PASSIVE. Deliberately not the
    /// strip's 26 — the unit sheet's tag row cannot afford ten more points.
    static let chipHeight: CGFloat = 16
    /// Horizontal padding inside a chip.
    static let chipPadding: CGFloat = 6

    /// Anything tappable that sits inline in a screen's content. The same
    /// height as a control in the strip (`ScreenChrome.control`), so the two
    /// rails line up.
    static let controlHeight: CGFloat = ScreenChrome.control

    /// A screen's primary action. `PrimaryButton` measures this today — a
    /// 13pt title at `fontScale` plus its 10pt of vertical padding — so
    /// anything that calls itself a button and stands beside one should ask
    /// for this rather than guess.
    static let buttonHeight: CGFloat = 34

    /// What a panel's content has to clear horizontally.
    ///
    /// `ui_panel`'s flat gold band measures 7.4pt thick at the shipped
    /// `Chrome.shrink` scale (31 px of a 512 px @3x texture) and its corner
    /// ornament reaches further, so the bare `.padding(8)` that sits under
    /// every `Theme.panel(...)` puts the first row of content 0.6pt off the
    /// metal: a section header's title or its accessory prints on the band.
    ///
    /// Horizontal only, on purpose. A landscape frame is 430 points tall and
    /// cannot pay four more points of height per panel, so `panelPadding`
    /// stays the vertical figure. `panelContentInset()` applies both.
    static let panelInset: CGFloat = 12
    /// The vertical padding inside a panel, unchanged from what the screens
    /// already used.
    static let panelPadding: CGFloat = 8

    /// The caption block under a unit card's square portrait — name, then
    /// level and power.
    ///
    /// One expression so `UnitCard` and `EmptyTeamSlot` cannot drift apart
    /// again: the slot is `size * 1.35` today and the card is `size` plus a
    /// fixed ~27pt caption, so they agree only near size 76 and every real
    /// team row is ragged (38 gives 65 against 51 in the arena, 46 gives 73
    /// against 62 on the campaign screen, and the row's height jumps as a
    /// unit is added or removed).
    ///
    /// `EmptyTeamSlot` can adopt `cardHeight(for:)` on its own — at every size
    /// the two are drawn together the figure is the card's real height, so the
    /// row stops jumping without `UnitCard` changing at all.
    ///
    /// The 27pt floor is the caption `UnitCard` actually draws today, measured
    /// rather than guessed: `Theme.body(10).weight(.heavy)` is 9pt after
    /// `fontScale` and lays out at ~10.7, the `Theme.numeric(9)` level/power
    /// row is 8.1pt and lays out at ~9.7, and the block carries 3pt of top and
    /// 4pt of bottom padding — 27.4 in total, whatever `size` is, because
    /// those two fonts are fixed. It is the figure the field measurements
    /// above confirm: 38 → 65 and 46 → 73 are both `size + 27`.
    ///
    /// 0.36 is the same caption expressed as a fraction of the shipped 76pt
    /// card, and it takes over above 75 so the helper keeps working the day
    /// `UnitCard`'s caption fonts start scaling with `size`. Until then the
    /// floor is what every real pairing hits: `EmptyTeamSlot` is only ever
    /// drawn beside a card at 30, 36, 38, 40, 46 or 58.
    ///
    /// The floor is deliberately never *below* the drawn caption. Under-
    /// reporting is the bug — a slot shorter than the card beside it is the
    /// ragged row this replaces, and a card frame shorter than its own caption
    /// would push text out of the plate. Over-reporting only adds air.
    static func cardCaptionHeight(for size: CGFloat) -> CGFloat {
        max(27, size * 0.36)
    }

    /// The full height of a unit card of this size, caption included.
    static func cardHeight(for size: CGFloat) -> CGFloat {
        size + cardCaptionHeight(for: size)
    }

    /// The standard panel: gradient body, bevelled edge, and a drop shadow so
    /// it floats off the backdrop instead of being painted onto it.
    ///
    /// `radius` applies to the drawn branch only — the painted texture brings
    /// its own corners, and a small panel is the only one that gets the drawn
    /// one, so a radius passed here is honoured exactly when the panel is
    /// under `Chrome.paintedPanelMinimum`.
    static func panel(_ radius: CGFloat = cornerRadius) -> some View {
        // The painted panel's corner ornament is 31pt on each side. Below
        // roughly twice that the four corners meet and the ornament becomes the
        // whole panel, swamping whatever it is framing — which is exactly what
        // happened to the 86pt actor plate in battle. Small panels get the
        // drawn one, which scales down cleanly.
        GeometryReader { geometry in
            let fitsPainted = geometry.size.width >= Chrome.paintedPanelMinimum
                && geometry.size.height >= Chrome.paintedPanelMinimum
            if fitsPainted, let painted = Chrome.slice("ui_panel", Chrome.panelInsets) {
                painted
                    .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 4)
            } else {
                drawnPanel(radius)
            }
        }
    }

    /// The code-drawn panel: near-black body, bevelled edge, gold rim, drop
    /// shadow — a smaller sibling of the painted one rather than a different
    /// object.
    ///
    /// It used to be `panelPlate`, an indigo #2A274F → #141328 with a #3B3766
    /// hairline, against the painted panel's near-black centre inside a gold
    /// frame. Nothing was shared: no fill, no border. A screen that shows both
    /// at once shows two materials — the Team Picker's Lineup panel is ~100pt
    /// and painted, the Leader skill panel under it is ~60pt and drawn, in the
    /// same 300pt rail. Matching the plate to the texture's centre also raises
    /// contrast: `textSecondary` goes from ~5.1:1 on `surfaceHigh` to ~6.1:1
    /// here.
    private static func drawnPanel(_ radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(drawnPanelPlate)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(bevel, lineWidth: 1)
            )
            .overlay(
                // A DARK LINE OUTSIDE THE METAL. This is the half of a frame
                // that is easy to leave out and impossible to unsee once it is
                // there: without it the bronze bleeds into the background and
                // the panel has no edge, which is most of why the old screens
                // looked flat.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color(hex: "#6B5636").opacity(0.5), lineWidth: 2)
            )
            .overlay(
                // The metal itself, inside that line: aged bronze with a
                // verdigris turn where it catches. A gradient rather than a
                // flat colour, because a border of one colour is a wireframe.
                RoundedRectangle(cornerRadius: radius - 1, style: .continuous)
                    .strokeBorder(bronzeFrame, lineWidth: 1.5)
                    .padding(1)
            )
            .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
    }

    /// The screen background. A radial lift behind the centre keeps the middle
    /// of the screen from going dead flat under a stack of panels.
    static var backdrop: some View {
        ZStack {
            // Cold slate, top to bottom. The old ground was #100D22 into
            // #0B0918 with a violet lift — the single largest patch of the
            // colour the owner called awful, since it is behind every screen
            // in the game.
            LinearGradient(
                colors: [Color(hex: "#F1E9D8"), Color(hex: "#E6DCC6"), Color(hex: "#D9CDB3")],
                startPoint: .top,
                endPoint: .bottom
            )
            // A WARM lift, against a cold ground. The old one was violet on
            // violet, which is a brightness change and not a colour: the eye
            // reads it as a smudge. Warm on cold is the cheapest depth there
            // is, and it is the same trick the stage lighting uses.
            RadialGradient(
                colors: [Color(hex: "#FFF8E6").opacity(0.7), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 560
            )
            // A verdigris pool at the foot, so the bottom of a long screen is
            // not simply darker but somewhere else.
            RadialGradient(
                colors: [Color(hex: "#B99C5A").opacity(0.22), .clear],
                center: .bottom,
                startRadius: 0,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }
}

// MARK: - Painted chrome

/// The painted UI kit — panels, buttons, frames — as 9-slice textures.
///
/// This is the half of the genre's look that code-drawn shapes cannot reach:
/// a carved gold frame is a painting, not a stroke. Every consumer asks here
/// first and draws its gradient fallback if the file is missing, so the kit
/// can ship one texture at a time.
///
/// Files are `@3x` so a 512px source is ~171pt logical; the cap insets below
/// are in those logical points and were measured off the art, not guessed.
/// Sum of opposite insets is the smallest size a texture can be drawn at
/// without its corners overlapping.
enum Chrome {
    private static var cache: [String: UIImage?] = [:]

    /// The kit is drawn at 1/1.4 of its painted size: the corner ornaments
    /// and the button ends were sized for a portrait phone, and on a
    /// landscape one they ate the screen (a 31-point ornament on every side
    /// of every panel). The insets below are divided by the same number.
    static let shrink: CGFloat = 1.4

    static func image(_ name: String) -> UIImage? {
        if let hit = cache[name] { return hit }
        var loaded = UIImage(named: name)
        if let source = loaded, let cg = source.cgImage {
            loaded = UIImage(cgImage: cg, scale: source.scale * shrink, orientation: source.imageOrientation)
        }
        cache[name] = loaded
        return loaded
    }

    /// Smallest side a painted panel may be drawn at. Below this the corner
    /// ornament from opposite sides overlaps and the panel reads as a frame
    /// with no middle.
    static let paintedPanelMinimum: CGFloat = 165 / shrink

    private static func scaled(_ top: CGFloat, _ leading: CGFloat, _ bottom: CGFloat, _ trailing: CGFloat) -> EdgeInsets {
        EdgeInsets(top: top / shrink, leading: leading / shrink, bottom: bottom / shrink, trailing: trailing / shrink)
    }

    /// ui_panel: 512² → 171pt at full size. The cream kit's scrolled gold
    /// acanthus corners reach 95 px in along each edge (measured on the
    /// night-3 painting, 2026-09-12; the slate kit's reached 76), so the
    /// caps are 98: everything an ornament touches stays fixed and only
    /// flat marble is stretched.
    static let panelInsets = scaled(98, 98, 98, 98)
    /// ui_button_gold: 640×192 → 213×64pt at full size. The bronze bar's
    /// scroll bands reach 68 px in (measured); the caps are 70.
    static let goldButtonInsets = scaled(8, 70, 8, 70)
    /// ui_button_dark: same size, a cream plate with a thin gold border and
    /// a 19 px gold band at each plain end (measured); the caps are 22.
    static let darkButtonInsets = scaled(10, 22, 10, 22)
    /// ui_ribbon: 640×128 → 213×43pt at full size.
    static let ribbonInsets = scaled(9, 17, 9, 17)

    /// How far in a label has to start so it does not print on the gold
    /// plate's ornate ends — the same 47/1.4 = 33.6pt the 9-slice reserves.
    /// `PrimaryButton` applies no horizontal padding at all today, so a long
    /// title (the campaign briefing's "BEGIN ×20 — 3 ENERGY EACH" in a 260pt
    /// button, against 193pt of flat middle) is centred over the scarabs.
    static var goldButtonLabelInset: CGFloat { goldButtonInsets.leading }

    /// The dark plate's ends are plain, so this is air rather than clearance.
    static let darkButtonLabelInset: CGFloat = 18

    /// The marble-and-verdigris kit landed on 2026-09-11 (`tools/batch/
    /// ui_marble.sh`: three rolls for the buttons, which Gemini kept painting
    /// as objects on a marble ground until the prompt said the bar IS the
    /// image). The indigo kit it replaces was held back here for a day so the
    /// game spoke one language while it waited.

    /// The slate panel and the slate button of the marble kit were held back
    /// here for a day until the night-3 routine repainted them in cream
    /// marble with a gold frame (2026-09-12, first roll each): the owner
    /// asked for "a cream color with gold accents (like a greek temple)" on
    /// 2026-09-11, and a dark slate panel on a cream ground was the one
    /// thing that would have read as the old interface. Empty now; kept so
    /// a future repaint can hold a texture back the same way.
    static let awaitingCreamRepaint: Set<String> = []

    static func slice(_ name: String, _ insets: EdgeInsets) -> Image? {
        if awaitingCreamRepaint.contains(name) { return nil }
        guard let ui = image(name) else { return nil }
        return Image(uiImage: ui).resizable(capInsets: insets, resizingMode: .stretch)
    }
}

// MARK: - Rarity

/// What a star grade looks like.
///
/// In this genre the frame *is* the rarity readout — a player identifies a
/// pull before reading a single word. Everything that draws a unit routes its
/// colours through here so the language is identical on a card, in a team slot
/// and on the summon reveal.
enum Rarity: Int, CaseIterable {
    case common = 1, uncommon, rare, epic, legendary, mythic

    init(stars: Int) {
        self = Rarity(rawValue: min(6, max(1, stars))) ?? .common
    }

    /// Frame metal. Two stops minimum, and the top stop is always the lighter
    /// one so the frame catches light from above like everything else.
    var frame: LinearGradient {
        LinearGradient(colors: frameStops, startPoint: .top, endPoint: .bottom)
    }

    private var frameStops: [Color] {
        switch self {
        case .common:    return [Color(hex: "#6E7590"), Color(hex: "#3B4157")]
        case .uncommon:  return [Color(hex: "#7FD6A0"), Color(hex: "#2F7A50")]
        case .rare:      return [Color(hex: "#7FC4FF"), Color(hex: "#2A5FA8")]
        case .epic:      return [Color(hex: "#C89BFF"), Color(hex: "#6B34B8")]
        case .legendary: return [Color(hex: "#FFE49B"), Color(hex: "#C08A23")]
        case .mythic:    return [Color(hex: "#FFB4C8"), Color(hex: "#FF6A3D"),
                                 Color(hex: "#C0308A")]
        }
    }

    /// The colour that bleeds out past the frame. Rarer means further.
    var glow: Color {
        switch self {
        case .common:    return Color(hex: "#6E7590")
        case .uncommon:  return Color(hex: "#4BE38F")
        case .rare:      return Color(hex: "#5FC8FF")
        case .epic:      return Color(hex: "#B478FF")
        case .legendary: return Color(hex: "#FFCB57")
        case .mythic:    return Color(hex: "#FF7BA8")
        }
    }

    var glowRadius: CGFloat {
        switch self {
        case .common, .uncommon: return 0
        case .rare: return 5
        case .epic: return 9
        case .legendary: return 13
        case .mythic: return 18
        }
    }

    var frameWidth: CGFloat { self >= .epic ? 2.5 : 1.5 }

    /// Only the top grades earn an animated sheen. If everything shimmers,
    /// nothing reads as special.
    var hasSheen: Bool { self >= .legendary }

    /// The painted frame for this grade, if it shipped. Square, with a
    /// transparent centre, designed to sit over the portrait.
    var frameImageName: String {
        switch self {
        case .common: return "ui_frame_common"
        case .uncommon: return "ui_frame_uncommon"
        case .rare: return "ui_frame_rare"
        case .epic: return "ui_frame_epic"
        case .legendary: return "ui_frame_legendary"
        case .mythic: return "ui_frame_mythic"
        }
    }

    var hasPaintedFrame: Bool { Chrome.image(frameImageName) != nil }
}

extension Rarity: Comparable {
    static func < (a: Rarity, b: Rarity) -> Bool { a.rawValue < b.rawValue }
}

// MARK: - Colour parsing

extension Color {
    /// Parses `#RRGGBB`. Falls back to magenta so a typo is visible rather than
    /// silently transparent.
    init(hex: String) {
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = .pink
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

extension Element {
    var color: Color { Color(hex: accentHex) }
}

extension Pantheon {
    var color: Color { Color(hex: accentHex) }
}

extension ArenaTier {
    var color: Color { Color(hex: accentHex) }
}

// MARK: - Reusable modifiers

struct PanelBackground: ViewModifier {
    var radius: CGFloat = Theme.cornerRadius
    func body(content: Content) -> some View {
        content.background(Theme.panel(radius))
    }
}

/// A tag: a set name, a role, an archetype, PASSIVE, a count.
///
/// One shape for what was ten. The unit sheet alone drew three of them — set
/// names at 7/3 in `body(9).bold` on `surfaceHigh`, the pantheon, archetype
/// and role tags at 6/2 on a 0.18-opacity tint, and PASSIVE at 4/1 in
/// `body(7).black` on gold at 0.25 — with 6/3, 8/3, 5/1 and 9/3 variants on
/// the Labyrinth and relic screens. Three shapes for one object on one screen.
///
/// The convention: **filled for a count or a state, unfilled for a label.**
/// The height is `Theme.chipHeight`, not the strip's `ScreenChrome.control` —
/// a chip is read, not tapped, and the tag rows it lives in have no room.
struct Chip: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = Theme.gold
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .black))
            }
            Text(text)
                .font(Theme.body(9).weight(.bold))
                .lineLimit(1)
        }
        .foregroundStyle(filled ? Theme.ink : tint)
        .padding(.horizontal, Theme.chipPadding)
        .frame(height: Theme.chipHeight)
        .background(Capsule().fill(filled ? tint : Theme.surfaceHigh))
        .overlay(
            Capsule().strokeBorder(tint.opacity(filled ? 0 : 0.35), lineWidth: 0.5)
        )
    }
}

/// A moving band of light across a surface. Used only on the rarest frames and
/// on the summon reveal, where the whole point is spectacle.
struct Sheen: View {
    var cornerRadius: CGFloat = Theme.tightCorner
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geometry in
            let span = geometry.size.width + geometry.size.height
            LinearGradient(
                colors: [.clear, .white.opacity(0.42), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: span * 0.35)
            .rotationEffect(.degrees(28))
            .offset(x: phase * span)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .onAppear {
            withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
                phase = 1.4
            }
        }
    }
}

extension View {
    func panelBackground(radius: CGFloat = Theme.cornerRadius) -> some View {
        modifier(PanelBackground(radius: radius))
    }

    /// The inset a panel's content needs so it does not sit on the painted
    /// frame's gold band: `Theme.panelInset` across, `Theme.panelPadding`
    /// down. Replaces the bare `.padding(8)` written under every
    /// `Theme.panel(...)` / `panelBackground()`.
    func panelContentInset() -> some View {
        self
            .padding(.horizontal, Theme.panelInset)
            .padding(.vertical, Theme.panelPadding)
    }

    /// Frames a view in its rarity's metal, with the matching outer glow.
    /// `painted` says whether the caller draws the carved frame texture over
    /// the card, in which case the metal stroke stays out of its way; nil
    /// reads it off the bundle, the way every caller did before the small
    /// cards gave the texture up (2026-09-12).
    func rarityFrame(_ rarity: Rarity, radius: CGFloat = Theme.tightCorner, painted: Bool? = nil) -> some View {
        let carved = painted ?? rarity.hasPaintedFrame
        return self
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(rarity.frame, lineWidth: carved ? 0 : rarity.frameWidth)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(carved ? 0 : 0.22), lineWidth: 0.5)
            )
            .shadow(color: rarity.glow.opacity(rarity.glowRadius > 0 ? 0.7 : 0),
                    radius: rarity.glowRadius, x: 0, y: 0)
    }

    // `screen(_ title:)` used to live here: backdrop, a UIKit navigation bar
    // and its title style. `GameScreen` replaced it on every menu and it had
    // no call sites left, so it is gone rather than waiting to be picked up
    // again — a second chrome language is exactly what this pass is for.
}


// MARK: - The bundled faces

/// Registers the `.ttf` files in the bundle with CoreText at launch — the
/// generated Info.plist has no font list, and registration needs none.
/// Called first thing in `PantheonApp.init`, before any view asks `Theme`
/// for a font. The console line is for the CI tour: a run whose frames
/// show the system faces will say why here.
enum FontLibrary {
    @discardableResult
    static func registerBundledFonts() -> Int {
        var urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        urls += Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        var registered = 0
        for url in urls {
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
                registered += 1
            }
        }
        let carved = UIFont(name: Theme.carvedFace, size: 12) != nil
        let text = UIFont(name: Theme.textFace, size: 12) != nil
        print("[Fonts] registered \(registered) of \(urls.count) bundled faces; Cinzel \(carved), Manrope \(text)")
        return registered
    }
}
