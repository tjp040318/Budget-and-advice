import SwiftUI

/// Athena on screen: her portrait, her plate, and the caret that points at
/// the one control she is talking about.
///
/// The caret is the reason this is a preference and not a table of
/// coordinates. `FirstHourStep`'s pointer was computed from the island
/// painting's own landmark anchors, which works exactly once — on the
/// island. A guide that has to point at a tab, a button in a sheet and a
/// slot on the unit sheet cannot know where any of them are, so instead
/// every control that can be pointed at says where it is:
///
///     Button("Summon") { … }.guideAnchor("summon_button")
///
/// and the overlay reads the rect back out of the preference. A lesson
/// naming an anchor no view has registered draws its line with no caret,
/// which is the safe way for this to fail.
struct GuideAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Lets Athena's caret find this control by name.
    func guideAnchor(_ id: String) -> some View {
        anchorPreference(key: GuideAnchorKey.self, value: .bounds) { [id: $0] }
    }

    /// Puts Athena over this container. Applied to the tab shell and to each
    /// sheet that is presented over it, because a sheet covers whatever is
    /// behind it and she has to be able to talk inside one.
    func guide(_ game: GameStore) -> some View {
        modifier(GuideOverlay(store: game))
    }
}

/// Her portrait and her words: a bust at the left, a plate of dark glass
/// beside it, the line typed out rather than dropped in. A tap anywhere goes
/// on.
///
/// Glass since phase B (2026-09-22, evening; PLAN.md, *Phase B of the premium
/// pass*): she speaks over PLACES — the island, the Hall of Ka — and the rule
/// is glass where words go over art. Run 211's guide frame had a cream slab
/// across the island painting with her name as a small gold caption. Now the
/// plate is `GlassPlate` at 0.86 (deep enough for a sentence over a bright
/// beach), the words cream at 13, her name carved at 15, and Skip a glass
/// bead rather than a word that could be missed.
struct GuidePlate: View {
    let beat: LessonBeat
    let title: String
    let isLast: Bool
    var onAdvance: () -> Void
    var onSkip: (() -> Void)?
    /// How much of the container's foot belongs to the game's tab bar: she
    /// and her plate stand ON its gold rule, never across it (run 216: the
    /// plate lay half over the band with the doors ghosting through the
    /// glass and her bust over the Island door). `GuideOverlay` passes what
    /// it measured off the bar's own doors — nothing inside a full-screen
    /// cover. Nil is the bar's own height, since the one place the plate is
    /// built directly (the tour's `guide` step) is over the shell.
    var bottomClearance: CGFloat? = nil

    /// How much of the line has been typed. Reset by `.id(beat.says)` at the
    /// call site, so a new beat starts empty.
    @State private var shown = 0
    @State private var finished = false

    private var portrait: CGFloat { 168 }

    /// Her foot: two points of air over the bar's rule when there is a bar,
    /// eight off the foot of a screen that has none.
    private var footing: CGFloat {
        let clearance = bottomClearance ?? GameTabBar.height
        return clearance > 0 ? clearance + 2 : 8
    }

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: -14) {
                BundleImage(name: beat.face.imageName, renderedAt: portrait)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: portrait, height: portrait)
                    .shadow(color: .black.opacity(0.45), radius: 10, y: 3)
                    .accessibilityLabel("Athena")

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("ATHENA")
                            .font(Theme.title(15))
                            .tracking(1.6)
                            .carved()
                            .lineLimit(1)
                            .fixedSize()
                        // The lesson's name, one line. It is the one thing
                        // on the plate that gives way to the Skip bead.
                        Text(title)
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.onGlassDim)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let onSkip {
                            GlassBead(text: "Skip", systemImage: "forward.fill", tint: Theme.onGlassDim,
                                      height: 24, action: onSkip)
                        }
                    }
                    Text(String(beat.says.prefix(shown)))
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.onGlass)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 4) {
                        Spacer(minLength: 0)
                        Text(finished ? (isLast ? "Tap to begin" : "Tap to go on") : " ")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.onGlassDim)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.onGlassEyebrow.opacity(finished ? 0.95 : 0))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(minHeight: 96, alignment: .top)
                // At most a reading width: across a whole landscape phone a
                // 13-point line ran past ninety characters.
                .frame(maxWidth: 560, alignment: .leading)
                .background(GlassPlate(radius: 14, opacity: 0.86))
                .padding(.bottom, 14)
            }
            // She stands at the left edge on a wide phone too, where the
            // capped plate would otherwise centre the pair.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            // On the bar's rule when there is a bar, with two points of air;
            // eight off the foot of a screen that has none.
            .padding(.bottom, footing)
        }
        // While she talks the place recedes, the bar with it — the genre's
        // tutorial dim, deeper at the foot where her words are. Run 216 had
        // nothing between her and a bright island and bar but a clear tap
        // catcher, so the plate read as pasted on.
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.18), Color.black.opacity(0.28), Color.black.opacity(0.48)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .task(id: beat.says) {
            shown = 0
            finished = false
            for index in beat.says.indices {
                try? await Task.sleep(nanoseconds: 16_000_000)
                if Task.isCancelled { return }
                shown = beat.says.distance(from: beat.says.startIndex, to: index) + 1
            }
            finished = true
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // A tap part way through the line finishes it rather than losing
            // it: the genre's rule, and the only one a reader ever wants.
            if finished {
                onAdvance()
            } else {
                shown = beat.says.count
                finished = true
            }
        }
    }
}

/// The gold caret and the one line beside it, sitting on the control the
/// lesson named. Nothing here is tappable — the caret moves when the player
/// does the thing, which is read off the save. The line is on the same dark
/// glass as her plate (2026-09-22, phase B), so it is plainly her voice on a
/// painted place and on a cream screen alike.
///
/// The ARROW and the LINE are placed apart since run 216. The whole stack
/// was clamped to keep a 300-point box on the screen, and the clamp dragged
/// the arrow with it: aimed at the Collection door, the arrowhead stood 65
/// points to its left over the sand, 15 points short of the bar, and the
/// line broke with an orphan "→ Equip." Now the arrow stands on the
/// target's own centre with its tip over the control, the target wears a
/// breathing gold ring, and only the line's box is kept on the screen, one
/// line up to a 460-point reading width.
///
/// Over a control the line stands a label's height clear of the arrow
/// (`labelBand`), since run 217: aimed at the Collection door, the box lay
/// on the top of the island's "Arena of Souls" chip with the arrow beside
/// it — two call-outs colliding on the one frame that teaches where to tap.
/// The band just over a control at the foot is where the place above it
/// keeps its lowest names (the island holds its chips to its own foot, on
/// the bar's rule), so the line clears it and the arrow alone crosses it.
struct GuideCaret: View {
    let prompt: String
    let target: CGRect
    let bounds: CGSize
    /// How much of the container's foot is the game's tab bar, measured off
    /// its doors by `GuideOverlay`: the line never stands on it, so a target
    /// whose line would reach the bar has it over instead. Zero where there
    /// is no bar.
    var footing: CGFloat = 0

    /// The line's box as it measured, for the clamp and the stacking; the
    /// first frame guesses a one-line box.
    @State private var box = CGSize(width: 300, height: 32)
    @State private var breathe = false

    /// The arrowhead: 18 wide, 12 tall, a dark edge so it reads on sand.
    private static let arrow = CGSize(width: 18, height: 12)
    /// Air between the ring and the tip, and between the arrow and the box.
    private static let reach: CGFloat = 7
    private static let gap: CGFloat = 5
    /// The widest the line's box may be before it wraps.
    private static let reading: CGFloat = 460
    /// The extra air between the arrow and a line over its control: a chip's
    /// height and a little, so the line clears the names in the band over a
    /// control at the foot.
    private static let labelBand: CGFloat = 12

    /// Whether the target is a control rather than the no-anchor fallback,
    /// which is a point and wears no ring.
    private var hasTarget: Bool { target.width >= 1 && target.height >= 1 }

    var body: some View {
        // Under the control when the arrow and the box fit under it, over it
        // when they do not (a tab door, a button on the foot of a screen).
        let stack = Self.reach + Self.arrow.height + Self.gap + box.height
        let below = target.maxY + stack + 8 < bounds.height - footing
        let tip = below ? target.maxY + Self.reach : target.minY - Self.reach
        let arrowY = below ? tip + Self.arrow.height / 2 : tip - Self.arrow.height / 2
        let boxY = below
            ? tip + Self.arrow.height + Self.gap + box.height / 2
            : tip - Self.arrow.height - Self.gap - Self.labelBand - box.height / 2
        let arrowX = min(max(target.midX, 12), max(12, bounds.width - 12))
        let half = box.width / 2 + 12
        let boxX = min(max(target.midX, half), max(half, bounds.width - half))
        let lineWidth = min(Self.reading, max(0, bounds.width - 24))

        ZStack {
            if hasTarget {
                RoundedRectangle(cornerRadius: min(16, min(target.width, target.height) / 2 + 4), style: .continuous)
                    .strokeBorder(Theme.gold, lineWidth: 2.5)
                    .shadow(color: Color.black.opacity(0.55), radius: 1.5)
                    .shadow(color: Color(hex: "#FFD678").opacity(0.7), radius: 6)
                    .frame(width: target.width + 8, height: target.height + 8)
                    .scaleEffect(breathe ? 1.05 : 1)
                    .opacity(breathe ? 0.45 : 0.95)
                    .animation(Self.breath, value: breathe)
                    .position(x: target.midX, y: target.midY)
            }
            BubbleTail()
                .fill(Theme.gold)
                .overlay(BubbleTail().stroke(Color.black.opacity(0.6), lineWidth: 1))
                .frame(width: Self.arrow.width, height: Self.arrow.height)
                .rotationEffect(.degrees(below ? 180 : 0))
                .shadow(color: Color.black.opacity(0.35), radius: 2, y: 1)
                .offset(y: breathe ? (below ? 3 : -3) : 0)
                .animation(Self.breath, value: breathe)
                .position(x: arrowX, y: arrowY)
            line
                .frame(width: lineWidth)
                .position(x: boxX, y: boxY)
        }
        .frame(width: bounds.width, height: bounds.height)
        .allowsHitTesting(false)
        .transition(.opacity)
        // The breath is scoped to the ring and the arrow (`.animation(_:
        // value:)` on each), so the box and the arrow never glide when the
        // target moves or the line is measured.
        .onAppear { breathe = true }
    }

    /// The ring's and the arrow's breath.
    private static let breath = Animation.easeInOut(duration: 0.9).repeatForever(autoreverses: true)

    /// The prompt on its glass, as wide as its words up to the reading
    /// width (it is proposed the whole of it and hugs what it needs).
    private var line: some View {
        Text(prompt)
            .font(Theme.body(12).weight(.semibold))
            .foregroundStyle(Theme.onGlass)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(GlassPlate(radius: Theme.tightCorner, opacity: 0.86))
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { box = proxy.size }
                        .onChange(of: proxy.size) { _, size in box = size }
                }
            )
    }
}

/// Athena over a container: her words while she has any, then her caret
/// until the player has done the thing.
struct GuideOverlay: ViewModifier {
    @ObservedObject var store: GameStore

    /// Which beat of the current lesson is showing. Kept here rather than in
    /// the save: a lesson half read is not worth a write, and the lesson is
    /// resumed from its first beat if the app dies mid-sentence.
    @State private var beat = 0
    @State private var speaking: String?

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(GuideAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    if let lesson = store.currentLesson {
                        layer(lesson, anchors: anchors, proxy: proxy)
                    }
                }
                .ignoresSafeArea(.keyboard)
            }
    }

    @ViewBuilder
    private func layer(
        _ lesson: Lesson,
        anchors: [String: Anchor<CGRect>],
        proxy: GeometryProxy
    ) -> some View {
        let talking = speaking == lesson.id && beat < lesson.beats.count
        let clearance = Self.barClearance(anchors, proxy: proxy)
        ZStack {
            if talking {
                // While she is speaking she owns the taps, so a stray press
                // on the screen behind her cannot start something in the
                // middle of a sentence.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { advance(lesson) }
                GuidePlate(
                    beat: lesson.beats[beat],
                    title: lesson.title,
                    isLast: beat == lesson.beats.count - 1,
                    onAdvance: { advance(lesson) },
                    onSkip: lesson.topic == .opening ? { store.silenceOpening() } : nil,
                    bottomClearance: clearance
                )
                .id(lesson.id)
            } else if let prompt = lesson.prompt, lesson.isStep {
                if let name = lesson.anchor, let anchor = anchors[name] {
                    GuideCaret(prompt: prompt, target: proxy[anchor], bounds: proxy.size, footing: clearance)
                } else {
                    // No view on this screen registered that anchor: the line
                    // still tells the player where to go.
                    GuideCaret(
                        prompt: prompt,
                        target: CGRect(x: proxy.size.width / 2, y: proxy.size.height - clearance - 12, width: 0, height: 0),
                        bounds: proxy.size,
                        footing: clearance
                    )
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: talking)
        .onAppear { open(lesson) }
        .onChange(of: lesson.id) { _, _ in open(lesson) }
    }

    /// How far up the container's foot the game's tab bar reaches, read off
    /// the bar's own doors (`GameTabBar` registers `tab_<name>` anchors), so
    /// her plate stands on the bar over the shell and on the screen's foot
    /// inside a full-screen cover, with no argument threaded through
    /// `guide(_:)`. Zero when no door is in this container. The doors are
    /// 56.6 points tall in the bar's 58, so the rule is a point above them.
    private static func barClearance(_ anchors: [String: Anchor<CGRect>], proxy: GeometryProxy) -> CGFloat {
        var top: CGFloat?
        for (name, anchor) in anchors where name.hasPrefix("tab_") {
            let door = proxy[anchor].minY
            top = min(top ?? door, door)
        }
        guard let top else { return 0 }
        return max(0, proxy.size.height - top + 1)
    }

    /// A lesson whose words have not been read starts talking; one already
    /// read goes straight to its caret.
    private func open(_ lesson: Lesson) {
        guard speaking != lesson.id else { return }
        if store.hasReadLesson(lesson.id) {
            speaking = nil
        } else {
            speaking = lesson.id
            beat = 0
        }
    }

    private func advance(_ lesson: Lesson) {
        if beat + 1 < lesson.beats.count {
            beat += 1
        } else {
            store.markLessonRead(lesson.id)
            speaking = nil
            beat = 0
        }
    }
}

// MARK: - The library

/// Everything Athena has ever said, kept.
///
/// The owner, on the opening being skippable and replayable: "That would be
/// a good idea, let's expand on that." This is the expansion — the tutorial
/// stops being eight minutes that are spent once and becomes the manual. A
/// lesson she has given can be read again for ever; one she has not is
/// listed by name and dimmed, so a player can see what the game still holds.
///
/// A DATA screen on the Missions board's shape (2026-09-23; the Counsel tab,
/// run 220's frame 33): run 220 photographed it as seven 713-point cream bars
/// with a 12-point seal, a short title and "Read again" in grey — about 80%
/// of every row empty, no art, "a settings screen". So:
///
/// - a left column of CARDS: Athena herself in a dark socket with the count
///   carved ("4 · OF 14 GIVEN") and a track of fourteen, and a card that says
///   what the dimmed ones are;
/// - the lessons as a TWO-COLUMN grid of raised marble plates under their
///   topics, each with the painted door of the place it teaches in a bronze
///   socket (`MedallionIcon`: the campaign, the circle, the collection, a
///   relic cache …), its title at 14, one line of what it teaches, and a
///   round gold "read again" plate with a chevron; a lesson to come is the
///   same plate paler, its socket dimmed and locked, its words in the
///   secondary ink at full strength (never paler words: run 217 read them at
///   1.8:1) and no tap;
/// - the grid ends in a fade above the home indicator, with room under the
///   last plate to scroll it clear.
struct LessonsView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var replaying: Lesson?
    /// The replay card's words, measured, so its scroll is exactly as tall
    /// as they are up to its cap.
    @State private var replayHeight: CGFloat = 120

    /// The cards' column. 224 holds "ATHENA'S LESSONS" at 13 with its
    /// tracking (149 of the 200 inside), her 84-point bust beside "OF 14
    /// GIVEN" (94), and a track of fourteen 11-point segments; it leaves the
    /// grid 490 on an iPhone 16 Pro, two plates of 241.
    private static let cardColumn: CGFloat = 224
    /// A lesson's socket, the Missions rows' 38 and a little: the plate is
    /// 56 tall, and the socket fills it with eight points over and under.
    private static let socketSize: CGFloat = 40
    /// The round gold plate that reads a lesson again.
    private static let readPlate: CGFloat = 26

    var body: some View {
        // The strip, like every other menu in the game: the title and the
        // count on the left behind the Back medallion. Her face stood at the
        // strip's right as a cut-out on bare cream (run 220); it is on her
        // card now, in a socket, so the strip carries nothing else.
        // "Lessons", the name on its door in More: it was "Athena's Counsel"
        // until run 217, which is also the Missions screen's Counsel tab — a
        // mission ladder — so two features answered to one name.
        GameScreen(
            "Lessons",
            subtitle: "Athena's words, kept · \(read) of \(LessonBook.all.count) given",
            dismiss: { dismiss() }
        ) {
            EmptyView()
        } content: {
            HStack(alignment: .top, spacing: 12) {
                cards
                    .frame(width: Self.cardColumn)
                library
            }
            .padding(.horizontal, ScreenChrome.contentPadding)
            .padding(.top, 10)
            .overlay { if let replaying { card(replaying) } }
        }
    }

    private var read: Int {
        LessonBook.all.filter { store.hasReadLesson($0.id) }.count
    }

    // MARK: - The cards

    /// Her card and the card for the ones still to come. The column scrolls
    /// only if a short phone cannot hold it (about 290 of the 319 points an
    /// iPhone 16 Pro gives it).
    private var cards: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                athenaCard
                comingCard
            }
            .padding(.bottom, 12)
        }
    }

    /// Athena presents her own words: her bust in the dark socket with the
    /// gold rim the Counsel tab gives her, the count carved beside it, and one
    /// segment per lesson, gold when given. Pleased once every one is.
    private var athenaCard: some View {
        let total = LessonBook.all.count
        let given = read
        let face: GuideFace = given >= total ? .pleased : .calm
        return VStack(alignment: .leading, spacing: 8) {
            cardHeader("Athena's lessons", tally: nil)
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().fill(Theme.socketFill)
                    BundleImage(name: face.imageName, renderedAt: 84)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 84, height: 84)
                }
                .frame(width: 84, height: 84)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.goldPlate, lineWidth: 1.5))
                .shadow(color: Color.black.opacity(0.2), radius: 3, y: 2)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(given)")
                        .font(Theme.display(34))
                        .carved(glow: false)
                        .lineLimit(1)
                        .fixedSize()
                    Text("OF \(total) GIVEN")
                        .font(Theme.title(13))
                        .tracking(1.0)
                        .foregroundStyle(Theme.goldDim)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            segmentTrack(filled: given, total: total)
            Text(given == 0 ? "She has not spoken yet. Her first words come on the island."
                            : "Tap one she has given to hear it again.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MarbleRowPlate(radius: Theme.cornerRadius))
        .accessibilityElement(children: .combine)
    }

    /// What the dimmed plates are, so a locked lesson never reads as a
    /// broken button: she gives each one when its place first opens.
    private var comingCard: some View {
        let waiting = LessonBook.all.count - read
        return VStack(alignment: .leading, spacing: 6) {
            cardHeader(waiting > 0 ? "Still to come" : "Every lesson given",
                       tally: waiting > 0 ? "\(waiting)" : nil)
            HStack(alignment: .top, spacing: 10) {
                MedallionIcon(key: "", glyph: "book.fill", size: 38, glyphTint: Theme.onGlassGold,
                              itemKey: ItemArt.key(scroll: .unknown))
                Text(waiting > 0
                     ? "She gives each one the first time its place opens, and keeps it here after."
                     : "Nothing is left for her to teach. Read any of them again.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MarbleRowPlate(radius: Theme.cornerRadius))
        .accessibilityElement(children: .combine)
    }

    /// A card's name in carved-ink capitals and its tally at the right, both
    /// at their own width — the Missions cards' header.
    private func cardHeader(_ title: String, tally: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title.uppercased())
                .font(Theme.title(13))
                .tracking(1.2)
                .foregroundStyle(Theme.goldDim)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            if let tally {
                Text(tally)
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// One segment per lesson, gold when given.
    private func segmentTrack(filled: Int, total: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<max(1, total), id: \.self) { index in
                Capsule()
                    .fill(index < filled ? Theme.gold : Theme.stroke.opacity(0.7))
                    .frame(height: 6)
            }
        }
    }

    // MARK: - The grid

    private var library: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(LessonTopic.allCases) { topic in
                    let lessons = LessonBook.all.filter { $0.topic == topic }
                    if !lessons.isEmpty {
                        section(topic, lessons)
                    }
                }
            }
            // Room for a plate's shadow, which the scroll view would clip,
            // and under the last plate, so it scrolls clear of the fade and
            // of the home indicator below it.
            .padding(.horizontal, 3)
            .padding(.top, 3)
            .padding(.bottom, 22)
        }
        // The grid ends in a fade at its own foot, which is the top of the
        // home indicator's band: nothing draws under it (run 220: "The
        // wheel" ran to the frame's bottom under the indicator).
        .mask(
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [Color.black, Color.black.opacity(0)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 16)
            }
        )
    }

    /// A topic: its name and how many of its lessons are given over a rule,
    /// then its lessons two to a row. The two plates of a row are one height
    /// (`fixedSize` on the row, `maxHeight` on each plate), so a two-line
    /// title — "Two of a kind, four of a kind" — never leaves its neighbour
    /// short; a lone last plate keeps half the width.
    private func section(_ topic: LessonTopic, _ lessons: [Lesson]) -> some View {
        let given = lessons.filter { store.hasReadLesson($0.id) }.count
        let rows: [[Lesson]] = stride(from: 0, to: lessons.count, by: 2).map { start in
            Array(lessons[start..<min(start + 2, lessons.count)])
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                Text(topic.title.uppercased())
                    .font(Theme.title(13))
                    .tracking(1.2)
                    .foregroundStyle(Theme.goldDim)
                    .lineLimit(1)
                    .fixedSize()
                Rectangle()
                    .fill(Theme.goldDim.opacity(0.3))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                Text("\(given) / \(lessons.count)")
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 2)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(row) { lesson in
                        plate(lesson)
                    }
                    if row.count < 2 {
                        Color.clear
                            .frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// One lesson on its marble: the door it teaches in a bronze socket, its
    /// title and what it teaches, and — given — the gold read-again plate.
    /// The whole plate is the tap. A lesson to come is the same plate at a
    /// paler marble with its socket dimmed and locked; its words keep the
    /// secondary ink at full strength (about 4.6:1), and it takes no tap.
    private func plate(_ lesson: Lesson) -> some View {
        let given = store.hasReadLesson(lesson.id)
        let spoken: String = given ? lesson.title + ". Read again" : lesson.title + ". Still to come"
        return Button {
            guard given else { return }
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            withAnimation { replaying = lesson }
        } label: {
            HStack(spacing: 10) {
                socket(for: lesson, given: given)
                VStack(alignment: .leading, spacing: 2) {
                    Text(lesson.title)
                        .font(Theme.body(14).weight(.semibold))
                        .foregroundStyle(given ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Self.teaches(lesson))
                        .font(Theme.body(11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if given {
                    readAgainPlate
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(MarbleRowPlate(radius: Theme.tightCorner).opacity(given ? 1 : 0.55))
            .contentShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
        }
        .buttonStyle(PlateButtonStyle())
        .allowsHitTesting(given)
        .accessibilityLabel(spoken)
    }

    /// The door's painting in its socket; dimmed, with a lock on its
    /// shoulder, while the lesson is still to come.
    private func socket(for lesson: Lesson, given: Bool) -> some View {
        let art = Self.art(for: lesson)
        return MedallionIcon(key: art.door, glyph: art.glyph, size: Self.socketSize,
                             glyphTint: Theme.onGlassGold, itemKey: art.item)
            .saturation(given ? 1 : 0.3)
            .opacity(given ? 1 : 0.7)
            .overlay(alignment: .bottomTrailing) {
                if !given {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Theme.onGlass)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Theme.ink))
                        .overlay(Circle().strokeBorder(Theme.bronze, lineWidth: 1))
                        .offset(x: 4, y: 3)
                }
            }
    }

    /// Read again: the strip's Back medallion turned to face forward, small —
    /// the gold plate with a chevron in ink. It was the words "Read again"
    /// in grey at the far end of a bar (run 220).
    private var readAgainPlate: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(Theme.ink)
            .frame(width: Self.readPlate, height: Self.readPlate)
            .background(Circle().fill(Theme.goldPlate))
            .overlay(Circle().strokeBorder(Theme.goldDeep.opacity(0.75), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.25), radius: 2, y: 1)
    }

    /// The painting each lesson's socket wears: the DOOR of the place it
    /// teaches (`ChromeArt`) or the ITEM it is about (`ItemArt`), the same
    /// paintings the island, the tab bar and the bazaar use, so a lesson
    /// looks like the thing it is about. The glyph is the fallback while a
    /// painting is missing. The Night Market is the drachma that buys it,
    /// since the bazaar's chest is the Labyrinth's loot here.
    private static func art(for lesson: Lesson) -> (door: String, item: String?, glyph: String) {
        switch lesson.id {
        case "welcome": return ("island", nil, "sun.max.fill")
        case "first_fight": return ("campaign", nil, "map.fill")
        case "first_summon": return ("summon", nil, "sparkles")
        case "first_relic": return ("collection", nil, "person.fill")
        case "first_powerup": return ("", "unit_exp", "arrow.up.circle.fill")
        case "farewell": return ("", ItemArt.key(scroll: .unknown), "book.fill")
        case "relic_power": return ("", "gem_legend", "diamond.fill")
        case "sets": return ("", "relic_cache", "circle.hexagongrid.fill")
        case "elements": return ("", "essence_magic_high", "flame.fill")
        case "evolve": return ("", "level_up", "star.circle.fill")
        case "labyrinth": return ("", "chest_gold", "shippingbox.fill")
        case "arena": return ("arena", nil, "trophy.fill")
        case "tiers": return ("campaign", nil, "flame.circle.fill")
        case "night_market": return ("", "drachma", "moon.stars.fill")
        default: return ("", nil, "book.fill")
        }
    }

    /// One line of what a lesson teaches, written to fit the plate's 135
    /// points at 11.5 on one line (measured in Manrope, 2026-09-23; the
    /// longest, "Dungeons and the Halls", is 127). It wraps rather than
    /// truncates on a narrower phone. A lesson added to the book without a
    /// line here shows its topic.
    private static func teaches(_ lesson: Lesson) -> String {
        switch lesson.id {
        case "welcome": return "Who wakes the gods"
        case "first_fight": return "Your first fight"
        case "first_summon": return "Your first scroll"
        case "first_relic": return "Dressing a god in relics"
        case "first_powerup": return "Feeding gods to gods"
        case "farewell": return "The four things to do"
        case "relic_power": return "Powering a relic to +15"
        case "sets": return "Where each set drops"
        case "elements": return "Which element wins"
        case "evolve": return "Evolving for a star"
        case "labyrinth": return "Dungeons and the Halls"
        case "arena": return "Rank, laurels, the arena"
        case "tiers": return "Hard and Hell chapters"
        case "night_market": return "A shelf that rolls hourly"
        default: return lesson.topic.title
        }
    }

    /// A replay is a CARD, not a pointer: the player may be standing on the
    /// island reading the lesson about a relic slot, and a caret aimed at a
    /// control that is not on this screen would be a caret that lies.
    ///
    /// Her words on her glass (2026-09-22, phase B), the plate she speaks on
    /// over the island, so a lesson read again is the same object as the
    /// lesson given; the list under it stays cream, since it is a list. A
    /// long lesson scrolls inside the card: the card is an overlay on a
    /// sheet, 329 points under the strip, and the longest lesson (the Night
    /// Market's three beats and its prompt) all but fills that at 12 points.
    private func card(_ lesson: Lesson) -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { withAnimation { replaying = nil } }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    BundleImage(name: GuideFace.calm.imageName, renderedAt: 54)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 54, height: 54)
                    Text(lesson.title.uppercased())
                        .font(Theme.title(15))
                        .tracking(1.2)
                        .carved()
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                // As tall as the words, up to 190: a ScrollView takes all
                // the height it is offered, so the words are measured and
                // the scroll given exactly that, and a short lesson's card
                // does not stand half empty.
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(lesson.beats.enumerated()), id: \.offset) { _, said in
                            Text(said.says)
                                .font(Theme.body(12))
                                .foregroundStyle(Theme.onGlass)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let prompt = lesson.prompt {
                            Text(prompt)
                                .font(Theme.body(11).weight(.semibold))
                                .foregroundStyle(Theme.onGlassEyebrow)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .onAppear { replayHeight = proxy.size.height }
                                .onChange(of: proxy.size.height) { _, height in replayHeight = height }
                        }
                    )
                }
                .frame(height: min(max(replayHeight, 1), 190))
                Text("Tap to close")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.onGlassDim)
            }
            .padding(16)
            .frame(maxWidth: 440)
            .background(GlassPlate(radius: 14, opacity: 0.9))
            .onTapGesture { withAnimation { replaying = nil } }
            .padding(.vertical, 12)
        }
    }
}
