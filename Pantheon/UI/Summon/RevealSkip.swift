import SwiftUI

// MARK: - Skip that never swallows a 5★ (2026-09-24, Docs/FEEL.md W2.23)
//
// Skip went straight to the grid, and a 5★ still to come in a ten-pull went
// with everything else, unseen: the one pull the player paid for, skipped
// past by a thumb that only wanted the 3★s over with. Genshin keeps its 5★
// splash through a skip. Now:
//
// - a TAP on Skip goes to the next pull worth stopping for — a 5★, or a 4★
//   the player has never owned — and says so: "Skip to ★★★★★". The pull on
//   the beam counts too while its charge is still climbing: Skip then
//   jumps to its flash, never past it. The words never tell the grade of
//   the pull on the beam before its rung (W1.5): in a single they stay
//   "Skip", and in a pull of several they change only when a pull lands
//   (`RevealSkip.label`);
// - HOLDING Skip for 0.6 s, a ring filling round its glyph as the finger
//   stays, skips everything to the summary;
// - a tap anywhere during a 5★'s charge jumps to the flash, not past it
//   (`SummonRevealView.advance`);
// - Quick summons, a per-device setting on the summon room's header, plays
//   a 3★ as a half-second flash (`SummonRevealView.revealNext`).

/// Where a tap on Skip goes.
enum RevealSkipTarget: Equatable {
    /// The pull on the beam is worth seeing and has not landed: to its flash.
    case land
    /// A later pull worth seeing: to its charge.
    case pull(Int)
    /// Nothing left worth stopping for: the summary.
    case summary
}

/// What the Skip control says.
enum RevealSkipLabel: Equatable {
    case skip
    case to(stars: Int, new: Bool)
    case done
}

enum RevealSkip {
    /// A pull a skip never swallows: a 5★ or better, or a 4★ or better the
    /// player has never owned.
    static func isWorthSeeing(_ result: SummonResult) -> Bool {
        result.stars >= 5 || (result.isNew && result.stars >= 4)
    }

    /// Where a tap on Skip goes from pull `index`, `landed` once its flash
    /// has gone off: to that pull's own flash while it is worth seeing and
    /// still charging, else to the first later pull worth seeing, else to
    /// the summary. In ORDER, so a new 4★ before a 5★ is never swallowed on
    /// the way to it; the next tap goes on to the 5★.
    static func target(in results: [SummonResult], at index: Int, landed: Bool) -> RevealSkipTarget {
        guard results.indices.contains(index) else { return .summary }
        if !landed && isWorthSeeing(results[index]) { return .land }
        var next: Int = index + 1
        while next < results.count {
            if isWorthSeeing(results[next]) { return .pull(next) }
            next += 1
        }
        return .summary
    }

    /// What the control says for that target.
    ///
    /// The pull on the beam (`.land`) is named only where naming it tells
    /// nothing its charge has not (Docs/FEEL.md W1.5; review, 2026-09-24).
    /// In a SINGLE it is the one pull there is, so "Skip to ★★★★★" on the
    /// first frame of its charge would be its grade before any rung: the
    /// words stay plain Skip, and a tap still lands its flash. In a pull of
    /// several they are the words the last pull's landing left up — the
    /// first stop from here on, which the charge's first frame cannot move
    /// — and on the first pull the ten's own first stop, which could be any
    /// of the ten. Plain Skip there would be the tell: it would change the
    /// words at the one charge that is the stop, on its first frame.
    static func label(in results: [SummonResult], for target: RevealSkipTarget, at index: Int) -> RevealSkipLabel {
        switch target {
        case .land:
            guard results.count > 1, results.indices.contains(index) else { return .skip }
            let result = results[index]
            return .to(stars: result.stars, new: result.stars < 5 && result.isNew)
        case .pull(let next):
            guard results.indices.contains(next) else { return .skip }
            let result = results[next]
            return .to(stars: result.stars, new: result.stars < 5 && result.isNew)
        case .summary:
            return .skip
        }
    }

    // MARK: The board (W2.3)

    /// The first card at or after `from` worth stopping for — the stop a tap
    /// on Skip runs the board to — or nil, for the summary.
    static func boardStop(in results: [SummonResult], from: Int) -> Int? {
        guard from < results.count else { return nil }
        return (max(0, from)..<results.count).first { isWorthSeeing(results[$0]) }
    }

    /// The card a tap on Skip lifts at once: the first of the cards up and
    /// waiting their turn on the beam (`queue`, in landing order) that is
    /// worth seeing — the ones before it are passed over — or nil when none
    /// is. The board's Skip (`SummonRevealView.boardSkip`) and its words
    /// both read it, so the two can never name different cards: a duplicate
    /// 4★ at the head of the queue once hid the 5★ waiting behind it, the
    /// words naming the next card still face down while a press lifted the
    /// 5★ (review, 2026-09-24).
    static func boardWaiting(in results: [SummonResult], queue: [Int]) -> Int? {
        queue.first { results.indices.contains($0) && isWorthSeeing(results[$0]) }
    }

    /// What Skip says on the board: the card it will go to — the first card
    /// up and waiting that is worth seeing (`boardWaiting`), else the first
    /// card worth seeing that has not LANDED (`landed` of them have) — or
    /// plain Skip when nothing is left but the summary. Read off landings
    /// alone (a card joins the queue as it lands), so the words change only
    /// when a card lands, never at a turn's start (W1.5).
    static func boardLabel(in results: [SummonResult], from landed: Int, queue: [Int]) -> RevealSkipLabel {
        if let waiting = boardWaiting(in: results, queue: queue) {
            let up: SummonResult = results[waiting]
            return .to(stars: up.stars, new: up.stars < 5 && up.isNew)
        }
        guard let stop = boardStop(in: results, from: landed) else { return .skip }
        let next: SummonResult = results[stop]
        return .to(stars: next.stars, new: next.stars < 5 && next.isNew)
    }

    /// How long Skip is held to skip everything.
    static let holdToSkipAll: Double = 0.6

    // MARK: Quick summons

    /// The `UserDefaults` key of Quick summons: a per-device setting, like
    /// the battle's speed, never a save field.
    static let quickKey = "summon.quick"

    static var quickSummons: Bool {
        get { UserDefaults.standard.bool(forKey: quickKey) }
        set { UserDefaults.standard.set(newValue, forKey: quickKey) }
    }

    /// Whether a pull plays as a quick flash: a 3★ or less, with Quick
    /// summons on. Never an awakening, whose reveal is the rite's ending.
    static func playsQuick(_ result: SummonResult, quick: Bool) -> Bool {
        quick && result.stars <= 3 && !result.isAwakening
    }

    /// A quick pull's flash, and its words' first star.
    static let quickFlash: TimeInterval = 0.5
}

/// The Skip control: one capsule of glass at the top right of the reveal.
/// A tap skips to what `RevealSkip.target` names; a hold of 0.6 s, its ring
/// filling, skips everything. ONE gesture reads the press from the finger's
/// touch to its lift, so a press is a tap or a hold and never both: with a
/// tap gesture beside a long press, whether the tap still fires on the lift
/// that ends a finished hold is SwiftUI's to decide, and after a hold the
/// control is Done — a tap there would close the summary the hold opened.
/// Not a `Button` for the same reason. The tick and the touch come on
/// touch-down, as every press in the game does (`GamePressStyle`). A press
/// the system takes from the finger is CANCELLED, which `onEnded` never
/// hears, so the finger is also followed through the gesture's own state
/// (`touching`): a cancelled press springs back with no tap and no hold.
struct RevealSkipControl: View {
    let label: RevealSkipLabel
    /// Whether a hold skips everything (a ten-pull before its summary).
    let offersHold: Bool
    let onTap: () -> Void
    let onHold: () -> Void

    @State private var pressed = false
    @State private var filling = false
    /// The press under the finger: whether one is down, its number (so a
    /// hold timed from an earlier press cannot fire on this one), and
    /// whether its hold has fired.
    @State private var down = false
    @State private var press = 0
    @State private var heldThisPress = false
    /// The press `letGo` sprang back without a lift, -1 for none: should
    /// SwiftUI ever deliver a lift after the reset it follows, `ended` still
    /// judges it as this press's lift rather than dropping the tap.
    @State private var releasedPress = -1
    /// Whether a finger is on the control, as the gesture keeps it: SwiftUI
    /// puts it back to false when the press ends AND when it is cancelled —
    /// an edge swipe iOS takes for its own centres (the control stands 12
    /// points under the top edge), a call, an alert — where `onEnded` never
    /// comes. Read from `down` alone, a cancelled press stayed down: its
    /// hold fired 0.6 s later and skipped a ten-pull past its 5★, and every
    /// later touch was refused as the same press (review, 2026-09-24).
    @GestureState private var touching = false

    private static let ink = Color(hex: "#FFE9A8")

    /// A finger that slides further than this before lifting was not
    /// pressing the control.
    private static let slop: CGFloat = 40

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 7) {
                if offersHold {
                    holdRing
                }
                words
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(GlassPlate(radius: 17))
            .scaleEffect(pressed ? 0.96 : 1)
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, state, _ in state = true }
                    .onChanged { _ in began() }
                    .onEnded { value in ended(travel: value.translation) }
            )
            .onChange(of: touching) { _, isTouching in
                if !isTouching { letGo() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(accessibilityWords))
            .accessibilityAction { onTap() }
            .accessibilityAction(named: Text("Skip all")) { onHold() }

            if offersHold {
                Text("Hold to skip all")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.onGlassDim)
                    .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                    .padding(.trailing, 8)
                    .allowsHitTesting(false)
            }
        }
    }

    /// The ring that fills while the finger holds, round the skip glyph.
    private var holdRing: some View {
        ZStack {
            Circle()
                .strokeBorder(Theme.onGlassDim.opacity(0.35), lineWidth: 2)
            Circle()
                .trim(from: 0, to: filling ? 1 : 0)
                .stroke(Theme.onGlassGold, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(1)
            Image(systemName: "forward.end.fill")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(Self.ink)
        }
        .frame(width: 20, height: 20)
    }

    @ViewBuilder
    private var words: some View {
        switch label {
        case .skip:
            Text("Skip")
                .font(Theme.title(13))
                .tracking(1.2)
                .foregroundStyle(Self.ink)
        case .done:
            Text("Done")
                .font(Theme.title(13))
                .tracking(1.2)
                .foregroundStyle(Self.ink)
        case .to(let stars, let new):
            HStack(spacing: 5) {
                Text(new ? "Skip to NEW" : "Skip to")
                    .font(Theme.title(13))
                    .tracking(1.2)
                    .foregroundStyle(Self.ink)
                    .fixedSize()
                StarRow(stars: stars, size: 10)
            }
        }
    }

    private var accessibilityWords: String {
        switch label {
        case .skip: return "Skip"
        case .done: return "Done"
        case .to(let stars, let new): return new ? "Skip to the new \(stars)-star" : "Skip to the \(stars)-star"
        }
    }

    /// The finger comes down: the press sinks with its tick and touch, and
    /// the hold is timed from here while one is offered. The hold fires only
    /// on a press still down — lifted (`ended`) or cancelled (`letGo`), it
    /// is not.
    private func began() {
        guard !down else { return }
        down = true
        heldThisPress = false
        press += 1
        let mine: Int = press
        AudioLibrary.shared.play(.uiTap)
        Juice.haptic(.light)
        withAnimation(Motion.tap) { pressed = true }
        guard offersHold else { return }
        withAnimation(.linear(duration: RevealSkip.holdToSkipAll)) { filling = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + RevealSkip.holdToSkipAll) {
            guard down, press == mine, !heldThisPress else { return }
            held()
        }
    }

    /// The finger lifts: a tap, unless this press's hold has fired or the
    /// finger slid well away. The lift of a press `letGo` has already sprung
    /// back is still this press's lift (see `releasedPress`).
    private func ended(travel: CGSize) {
        guard down || releasedPress == press else { return }
        down = false
        releasedPress = -1
        let fired: Bool = heldThisPress
        heldThisPress = false
        withAnimation(Motion.tap) { pressed = false }
        withAnimation(.easeOut(duration: 0.15)) { filling = false }
        let slid: CGFloat = max(abs(travel.width), abs(travel.height))
        if !fired && slid < Self.slop {
            onTap()
        }
    }

    /// The finger is off the control, lifted or taken. A LIFT is judged by
    /// `ended`, which SwiftUI delivers with the reset that brought us here,
    /// so nothing is decided on this turn: a press still down on the main
    /// queue's NEXT turn never reached `ended` — it was cancelled — and it
    /// springs back with no tap, its hold (still waiting on the clock)
    /// finding it up. Its `heldThisPress` stays as it was, so a lift that
    /// did come late (`releasedPress`) cannot turn a finished hold into a
    /// tap on Done.
    private func letGo() {
        let mine: Int = press
        DispatchQueue.main.async {
            guard down, press == mine else { return }
            down = false
            releasedPress = mine
            withAnimation(Motion.tap) { pressed = false }
            withAnimation(.easeOut(duration: 0.15)) { filling = false }
        }
    }

    private func held() {
        heldThisPress = true
        Juice.haptic(.medium)
        AudioLibrary.shared.play(.whoosh, volume: 0.6)
        withAnimation(Motion.exit) { filling = false }
        onHold()
    }
}

/// Quick summons on the summon room's header: a chip of glass that says it
/// and lights gold when on. Remembered on the device (`RevealSkip.quickKey`).
struct SummonQuickToggle: View {
    @State private var on: Bool = RevealSkip.quickSummons

    var body: some View {
        Button {
            on.toggle()
            RevealSkip.quickSummons = on
        } label: {
            HStack(spacing: 5) {
                Image(systemName: on ? "bolt.fill" : "bolt")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(on ? Theme.gold : Theme.onGlassDim)
                Text("Quick 3★")
                    .font(Theme.body(11).weight(.semibold))
                    .foregroundStyle(on ? Theme.onGlassGold : Theme.onGlassDim)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(on ? Theme.onGlassSuccess : Theme.onGlassDim)
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(Theme.glass)
                    .overlay(Capsule().strokeBorder(on ? Theme.gold.opacity(0.9) : Theme.glassRim, lineWidth: 0.8))
            )
        }
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel(Text("Quick summons for three-star pulls"))
        .accessibilityValue(Text(on ? "On" : "Off"))
    }
}

#if DEBUG
extension SummonRevealView {
    /// `-tour-reveal ten` (DEBUG, the CI's frames of the board and its
    /// Skip): a ten-pull whose fifth pull is the fire Sekhmet, a 5★, with a
    /// NEW 4★ behind it and 3★s and duplicates round them, so the board's
    /// Skip reads "Skip to ★★★★★" and, pressed (`-tour-reveal-skip`), runs
    /// past the duplicate 4★ to the 5★'s reveal rather than to the summary.
    /// `-tour-reveal board` is the same ten, turned without lifting a card
    /// (`tourBoardHold`). Nil without either.
    static func tourTenPull() -> [SummonResult]? {
        guard tourTenFlag else { return nil }
        let pool: [UnitBlueprint] = UnitDatabase.summonPool.compactMap { UnitDatabase.blueprint($0) }
        func pick(_ stars: Int, _ nth: Int) -> UnitBlueprint? {
            let grade: [UnitBlueprint] = pool.filter { $0.naturalStars == stars && !$0.element.isLightOrDark }
            guard !grade.isEmpty else { return nil }
            return grade[nth % grade.count]
        }
        let plan: [(stars: Int, nth: Int, new: Bool)] = [
            (3, 0, false), (3, 1, false), (4, 0, false), (3, 2, false), (5, 0, true),
            (3, 3, false), (4, 1, true), (3, 4, false), (3, 5, false), (4, 2, false),
        ]
        var results: [SummonResult] = []
        for step in plan {
            let chosen: UnitBlueprint? = step.stars == 5 ? (UnitDatabase.blueprint("sekhmet_ember") ?? pick(5, 0)) : pick(step.stars, step.nth)
            guard let blueprint = chosen else { continue }
            results.append(SummonResult(
                unit: Unit(blueprint: blueprint),
                blueprint: blueprint,
                stars: blueprint.naturalStars,
                isNew: step.new,
                isFeatured: step.stars == 5,
                fromPity: false
            ))
        }
        return results.count == plan.count ? results : nil
    }

    /// Whether the tour asked for its ten (`-tour-reveal ten` or `board`).
    private static var tourTenFlag: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-tour-reveal"), at + 1 < args.count else { return false }
        return args[at + 1] == "ten" || args[at + 1] == "board"
    }

    /// The summary's plate under the CI's ten (W2.3): the summon room is not
    /// there to hand one in, so a stand-in says what the plate says — ten of
    /// twenty-three Mystical Scrolls held, the pity after the pull — and
    /// summons nothing when pressed. Nil outside the tour's ten.
    static func tourAgainOffer() -> SummonAgainOffer? {
        guard tourTenFlag else { return nil }
        return SummonAgainOffer(count: 10, scroll: .mystical, held: 23, pity: "4★+ in 17", action: {})
    }
}
#endif
