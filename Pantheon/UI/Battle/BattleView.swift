import Foundation
import SceneKit
import SwiftUI
import UIKit

/// The battle screen: 3D stage underneath, HUD on top.
///
/// The HUD answers four questions, and every piece below exists to answer
/// exactly one of them without the player stopping to look:
///
///   *Whose turn is it?* — the gold dot on the attack gauge, the gold ring on
///   that unit's team plate, and the actor plate in the bottom-left corner,
///   which is filled during an enemy turn as well as the player's so the
///   corner never goes blank and never means two different things.
///   *Who is next?* — the gauge, read left to right.
///   *What just happened to whom?* — the combat feed on the right: one line
///   per health change and per status landing, named, on its own dark plate.
///   The 3D damage numbers land on a sunlit floor and were measured at 1.05:1
///   against it; these are 14:1 whatever the stage.
///   *What will this button do?* — every skill tile carries its own forecast
///   line (estimated damage, hit count, or HEAL/BUFF), and the plate spells
///   out the skill in hand before it is committed rather than after.
struct BattleView: View {

    @State private var ultimateFlash: Double = 0
    @StateObject var model: BattleViewModel
    @Environment(\.dismiss) private var dismiss

    /// The gear's menu: the log, forfeit.
    @State private var showMenu = false
    @State private var showLog = false
    @State private var summary: BattleSummary?
    /// The skill whose panel stands over the skill row: the square the
    /// player last touched this turn — tapped, held, or tapped while it is
    /// cooling down, just to read it. The genre's way (the owner, of the
    /// fight: "when I click on a skill during battle, I need to see what it
    /// does. Show me like Summoners War does"): a tap on a skill shows what
    /// it does above the skills while it is chosen, and goes when it is
    /// used or the turn passes. It was a card behind a HOLD in the middle of
    /// the field, which nobody found.
    @State private var inspectedSlot: Int?

    /// The skill under the player's finger, before the tap has committed to
    /// anything. A press on a tile sets it and a lift clears it, so the plate
    /// describes a skill *while it is being considered* — the old plate only
    /// ever described a skill that had already been chosen, and skills that
    /// pick their own targets fire on the tap, so those were never described
    /// at all.
    @State private var previewSlot: Int?

    /// The acting player unit's matchup against each living boss, told by
    /// the scene as each turn opens (`BattleSceneController.onBossMatchups`)
    /// and drawn as the arrow beside the boss's name in its bar — a boss's
    /// 3D arrow landed on its body (run 220).
    @State private var bossMatchups: [UUID: Element.Matchup] = [:]

    // MARK: The end of the fight (Docs/FEEL.md W1.7)

    /// Where the fight's end stands. The fight; then a beat ON THE FIELD —
    /// the survivors turned to the camera and posing under VICTORY while
    /// their plates fill with experience, or the colour draining out under
    /// DEFEAT — and only then the reckoning, over a scrim light enough that
    /// the team stays in sight behind it. The victory used to be played by
    /// survivors facing away from the camera, a second before a 0.84 scrim
    /// covered them: 115 families' victory clips that nobody had seen.
    private enum FieldBeat { case fighting, triumph, fallen, reckoning }
    @State private var beat: FieldBeat = .fighting
    /// The last fight's own result — what the field shows — which an
    /// auto-repeat's summary (every run's) can differ from.
    @State private var fieldOutcome: BattleOutcome = .victory
    /// Bumped as each beat begins, so a timer that outlived its beat steps
    /// aside rather than moving a later one on.
    @State private var beatSequence = 0
    @State private var beatBegan: Date?

    // MARK: The skill squares' answers (Docs/FEEL.md W1.9)

    /// Per slot, a count bumped each time the player arms that skill: the
    /// square's gold ring plays on it (`SkillButton.armPulse`).
    @State private var armPulses: [Int: Int] = [:]
    /// Per slot, a count bumped when the skill comes off cooldown: the
    /// square's gloss sweeps on it (`SkillButton.readyGlint`).
    @State private var readyGlints: [Int: Int] = [:]
    /// Each player unit's skills that were cooling when its last turn opened:
    /// the diff a skill ready again is found by (`noteCooldowns`).
    @State private var coolingSlots: [UUID: Set<Int>] = [:]

    /// The reckoning waits this long after the outcome lands, so the last
    /// blow and the scene's own end of the fight are seen first.
    private static let settleDelay: TimeInterval = 0.8
    /// A loss: the colour drains over this long, and DEFEAT sits over the
    /// grey field until `fallenHold` before the reckoning.
    private static let drainDuration: TimeInterval = 0.8
    private static let fallenHold: TimeInterval = 2.0
    /// The reckoning's scrim over the field (0.84 until 2026-09-24, which
    /// hid the team the beat had just posed).
    private static let reckoningScrim: Double = 0.55
    /// A tap hurries the beat to the reckoning, but not before the stamp and
    /// its stars have landed (the third star lands about 1.03 s in): the
    /// moment is shortened, never cut, and the taps that ended the fight
    /// are not read as a wish to skip it.
    private static let beatTapGrace: TimeInterval = 1.2
    /// `-tour-victory field|defeat` (TourView): the CI job photographs the
    /// beat, and a simulator screenshot of a live fight lands long after it
    /// is asked for — six to nine seconds in run 245, whose -0 caught the
    /// reckoning, -triumph the level-up and -levelup the chest, each a beat
    /// late under holds of 9, 7 and 6 s — so the triumph holds long enough
    /// for two frames and the fall for one, the reckoning plays itself on to
    /// the level-up and the chest (`BattleResultView.autoplay`), and
    /// `[TourCue] triumph` or `[TourCue] fallen` tells the job when the beat
    /// began. The job writes each of these frames' asked and landed times to
    /// shots/shot-times.txt.
    private static let touringVictory = ProcessInfo.processInfo.arguments.contains("-tour-victory")
    private static let tourTriumphHold: TimeInterval = 24
    private static let tourFallenHold: TimeInterval = 16

    /// A dark veil over the stage until the renderer has drawn the built
    /// stage (2026-09-24; `BattleSceneController.onStageShown`): run 243's
    /// first battle frame was white under the HUD while the stage built and
    /// its shaders compiled. It lifts on those first frames, or `veilLimit`
    /// after the build at the latest, and an auto-repeat's later runs never
    /// bring it back.
    @State private var stageShown = false
    private static let veilLimit: TimeInterval = 5
    private static let veilLift: Animation = .easeOut(duration: 0.35)

    /// Under the CI tour, `[TourCue] shown` when the veil lifts, and why:
    /// a step that photographs the first seconds of a fight waits on it
    /// (build.yml's aoe relaunches, whose frames at launch + 8 s were the
    /// veil in run 245 — the build settled at seven and the main thread
    /// was busy again after it).
    private static func cueStageShown(_ why: String) {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("-tour") else { return }
        print("[TourCue] shown (\(why))")
        #endif
    }

    var body: some View {
        ZStack {
            BattleSceneView(controller: model.sceneController) { id in
                model.tapUnit(id)
            }
            .ignoresSafeArea()

            Color.black
                .ignoresSafeArea()
                .opacity(stageShown ? 0 : 1)
                .allowsHitTesting(false)

            // The genre's HUD and nothing else on the field (2026-09-15): a
            // boss's bar across the very top, the stage's name small under
            // it at the left, the three controls at the bottom left, the
            // skills at the bottom right. The bars stand over the heads
            // (`UnitPlate`). The actor plate, the side column, the turn
            // gauge and the combat feed of the earlier HUDs are gone — the
            // owner, with Summoners War's frame beside ours: "the UI of the
            // skills and the descriptions like the bottom left UI and more
            // I just don't like."
            let boss = model.displayedCombatants.first { $0.isBoss && $0.isAlive }
            // THE BOTTOM CORNERS ON THE SAFE AREA'S EDGES (2026-09-24). The
            // owner's Summoners War frame, measured on his phone (956 × 440
            // points, insets 62 at the sides and 21 at the foot): its skills'
            // right edge 61.5 points from the glass and its controls' left
            // edge 61, i.e. ON the safe area's sides, and both rows 15–18
            // points off the foot. Ours stood 8 points inside the safe area
            // all round. The corners now stand on the safe area itself where
            // the phone has an inset — never under the notch's side or the
            // home indicator's band — and `cornerFloor` points off the glass
            // where it has none (a Touch ID phone), so no button ever meets
            // the screen's edge. The top keeps its 8 and 4.
            GeometryReader { geometry in
                let insets = geometry.safeAreaInsets
                VStack(spacing: 6) {
                    VStack(spacing: 6) {
                        if let boss {
                            bossBar(boss)
                        }
                        topStrip
                    }
                    .padding(.horizontal, 8)
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom, spacing: 10) {
                        controls
                        Spacer(minLength: 0)
                        if let actor = model.awaitingActor {
                            VStack(alignment: .trailing, spacing: 8) {
                                if let option = inspectedOption {
                                    skillCard(option.skill, cooldown: option.cooldown, actor: actor)
                                        .transition(.opacity.combined(with: .offset(y: 6)))
                                }
                                skillRow(actor)
                            }
                            .animation(.easeOut(duration: 0.15), value: inspectedSlot)
                        } else if model.isPlayingBack {
                            skipButton
                        }
                    }
                    .padding(.leading, Self.cornerMargin(insets.leading))
                    .padding(.trailing, Self.cornerMargin(insets.trailing))
                    .padding(.bottom, Self.cornerMargin(insets.bottom))
                }
                .padding(.top, 4)
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
            // The fight's end takes the field: the chips, the controls and
            // the skills fade as its beat arrives (it is set inside an
            // animation) rather than showing through it, as they did in run
            // 220 behind the VICTORY wordmark and under its tiles.
            .opacity(beat == .fighting ? 1 : 0)
            .allowsHitTesting(beat == .fighting)

            // The frame goes white for a beat as an ultimate's cut-in lands —
            // never under Reduce Motion (`MotionComfort`, iOS's or the game's).
            Color.white
                .opacity(ultimateFlash)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .onChange(of: model.cutIn) { _, cutIn in
                    guard let cutIn, !cutIn.isSpeech, !MotionComfort.isReduced else { return }
                    ultimateFlash = 0.6
                    withAnimation(.easeOut(duration: 0.5)) { ultimateFlash = 0 }
                }

            if let cutIn = model.cutIn {
                cutInBanner(cutIn)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .onAppear {
                        // A skill's name is read at a glance; a sentence is
                        // not, so a boss's line is held nearly twice as long.
                        DispatchQueue.main.asyncAfter(deadline: .now() + (cutIn.isSpeech ? 2.4 : 1.15)) {
                            withAnimation(.easeIn(duration: 0.2)) {
                                if model.cutIn == cutIn { model.cutIn = nil }
                            }
                        }
                    }
            }

            if showLog, beat == .fighting { logOverlay }

            if let banner = model.repeatBanner {
                Text(banner)
                    .font(Theme.title(16))
                    .foregroundStyle(Theme.onGlassGold)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.glass))
                    .overlay(Capsule().strokeBorder(Theme.glassRim, lineWidth: 1))
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            withAnimation { model.repeatBanner = nil }
                        }
                    }
            }

            // The beat on the field, over the live scene (W1.7).
            fieldBeatLayer

            // The reckoning, over a scrim that keeps the team in sight; its
            // panels slide in on their own (`BattleResultView.arrived`). The
            // stars the stamp slammed in over the field stand lit in it
            // rather than ticking in a second time.
            if beat == .reckoning, let summary {
                BattleResultView(
                    summary: summary, onDismiss: { dismiss() }, autoplay: Self.touringVictory,
                    store: model.store, scrim: Self.reckoningScrim, starsLanded: fieldOutcome == .victory
                )
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // A binding, not the view: the controller is the model's, and a
            // closure holding the model would keep the whole fight alive.
            let matchups = $bossMatchups
            model.sceneController.onBossMatchups = { matchups.wrappedValue = $0 }
            let shown = $stageShown
            model.sceneController.onStageShown = {
                withAnimation(Self.veilLift) { shown.wrappedValue = true }
                Self.cueStageShown("drawn")
            }
            model.begin()
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.veilLimit) {
                guard !shown.wrappedValue else { return }
                withAnimation(Self.veilLift) { shown.wrappedValue = true }
                Self.cueStageShown("the \(Int(Self.veilLimit)) s limit")
            }
            // A chapter boss or a raid says its one line as the fight opens;
            // every other stage returns from this without doing anything.
            model.announceBoss(ifPresentIn: model.displayedCombatants)
            AudioLibrary.shared.playMusic(.battle)
        }
        .onDisappear {
            model.sceneController.onBossMatchups = nil
            model.sceneController.onStageShown = nil
            // A beat still counting when the screen goes steps aside.
            beatSequence += 1
            AudioLibrary.shared.playMusic(.island)
        }
        // A new actor means the old one's skill preview is meaningless; its
        // skills are diffed against its last turn for the ones ready again.
        .onChange(of: model.awaitingActor?.id) { _, _ in
            previewSlot = nil
            inspectedSlot = nil
            showTourSkillPanel()
            if let actor = model.awaitingActor { noteCooldowns(of: actor) }
        }
        .onChange(of: model.outcome?.outcome) { _, newValue in
            guard newValue != nil else { return }
            // Let the last blow land before the end of the fight begins.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) {
                // On a repeat run with runs still to go this banks the loot
                // and starts the next fight instead of returning a summary,
                // and no beat plays: the beat is the LAST run's (W1.7).
                if let concluded = model.conclude() {
                    endFight(concluded)
                }
            }
        }
        // The gear's menu: the genre keeps everything that is not a skill
        // behind one button.
        .confirmationDialog("Battle", isPresented: $showMenu, titleVisibility: .visible) {
            Button(showLog ? "Hide the battle log" : "Show the battle log") { withAnimation { showLog.toggle() } }
            Button("Forfeit", role: .destructive) { model.forfeit() }
            Button("Keep fighting", role: .cancel) {}
        } message: {
            Text("Forfeiting counts as a loss, and energy already spent is not refunded.")
        }
    }

    // MARK: - The end of the fight (Docs/FEEL.md W1.7)

    /// The beat over the live field: VICTORY stamped over the posing team,
    /// or DEFEAT in wine over the drained one, with a layer over the whole
    /// screen that takes a tap to hurry on to the reckoning.
    @ViewBuilder
    private var fieldBeatLayer: some View {
        switch beat {
        case .triumph:
            VictoryStamp(stars: stampStars)
                .transition(.opacity)
            beatTapCatcher
        case .fallen:
            DefeatStamp(outcome: fieldOutcome)
                .transition(.opacity)
            beatTapCatcher
        case .fighting, .reckoning:
            EmptyView()
        }
    }

    /// The stars the stamp slams in: the fight's own, or an auto-repeat's
    /// last run's (`BattleSummary.stampStars`).
    private var stampStars: Int {
        guard let summary else { return 0 }
        return summary.stampStars ?? summary.stars
    }

    /// A tap during the beat moves it on to the reckoning: the moment is
    /// shortened for a player who has seen it, never deleted (FEEL.md,
    /// principle 8).
    private var beatTapCatcher: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onTapGesture { hurryToReckoning() }
    }

    /// The fight is over and settled (`conclude()` has paid it): the beat on
    /// the field, then the reckoning. A win turns the survivors to the camera
    /// to pose in their own victory clips, the camera framing them, their
    /// plates' health swapped for the gold EXP bar filling from where it
    /// stood (`celebrate(experience:)`), and VICTORY slams down over them
    /// with the stars; the plates stay up through it. A loss drains the
    /// field's colour and DEFEAT settles over it in wine. The victory's
    /// fanfare stays the reckoning's, played once as its ribbon lands.
    private func endFight(_ concluded: BattleSummary) {
        beatSequence += 1
        let mine = beatSequence
        let field = model.outcome?.outcome ?? concluded.outcome
        fieldOutcome = field
        previewSlot = nil
        inspectedSlot = nil
        showLog = false
        summary = concluded
        beatBegan = Date()
        let hold: TimeInterval
        if field == .victory {
            model.sceneController.celebrate(experience: concluded.experience)
            withAnimation(.easeOut(duration: 0.35)) { beat = .triumph }
            hold = Self.touringVictory ? Self.tourTriumphHold : BattleSceneController.triumphDuration
            if Self.touringVictory { print("[TourCue] triumph") }
        } else {
            model.sceneController.drainColour(duration: Self.drainDuration)
            withAnimation(.easeOut(duration: 0.5)) { beat = .fallen }
            hold = Self.touringVictory ? Self.tourFallenHold : Self.fallenHold
            if Self.touringVictory { print("[TourCue] fallen") }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) {
            guard mine == beatSequence else { return }
            reckon()
        }
    }

    /// The reckoning takes over from the beat. The plates, which stood
    /// through the beat with their EXP bars, leave with it now.
    private func reckon() {
        guard beat == .triumph || beat == .fallen else { return }
        beatSequence += 1
        model.sceneController.setPlatesHidden(true)
        withAnimation(.easeOut(duration: 0.35)) { beat = .reckoning }
    }

    private func hurryToReckoning() {
        guard let began = beatBegan, Date().timeIntervalSince(began) >= Self.beatTapGrace else { return }
        reckon()
    }

    // MARK: - Top bar

    /// One height and one shape for every chip in the top row, and one way
    /// for a stateful one — a repeat run — to say it is on: a gold plate
    /// under a gold hairline.
    ///
    /// DARK GLASS over the fight (run 217): the chips were the cream plate at
    /// 0.6 over the 3D set — the premium pass's rule is dark glass over art,
    /// cream marble for data — and "Wave 1/3" in gold on pale cream was the
    /// lowest-contrast word on the screen. A chip takes its own width
    /// (`fixedSize`): the title chip was a fixed 190 points with "vs Phaidra"
    /// filling a third of it, like an empty search field.
    private func hudChip<C: View>(active: Bool = false, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(height: 30)
            .padding(.horizontal, 12)
            .background(Capsule().fill(active ? Theme.goldDeep.opacity(0.92) : Theme.glass))
            .overlay(Capsule().strokeBorder(active ? Theme.gold : Theme.glassRim, lineWidth: 1))
            .fixedSize()
    }

    // MARK: - The player's team

    /// Statuses at team-plate size: the glyph on a coloured disc, three of
    /// them and a count. The named chips are for the actor plate and the boss
    /// bar, where there is room for words.
    private func statusPips(_ statuses: [ActiveStatus]) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(statuses.prefix(3).enumerated()), id: \.offset) { _, status in
                Image(systemName: status.kind.glyph)
                    .font(.system(size: 6.5, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 11, height: 11)
                    .background(
                        Circle().fill(status.kind.isBuff ? Color(hex: "#2E8FBF") : Color(hex: "#B8403A"))
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5))
            }
            if statuses.count > 3 {
                Text("+\(statuses.count - 3)")
                    .font(Theme.numeric(7))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - The combat feed

    // MARK: - Command bar

    // MARK: - The strip and the controls

    /// The stage's name and the wave, small at the top left; a repeat run's
    /// count beside them. Nothing else at the top of a normal wave — the
    /// genre's frame is empty there.
    private var topStrip: some View {
        HStack(spacing: 6) {
            hudChip {
                Text(model.context.title)
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(Theme.onGlass)
                    .lineLimit(1)
            }
            if model.waveCount > 1 {
                hudChip {
                    Text("Wave \(model.waveIndex)/\(model.waveCount)")
                        .font(Theme.numeric(11))
                        .foregroundStyle(Theme.onGlassGold)
                        .lineLimit(1)
                }
            }
            if let session = model.repeatSession {
                // Runs done of runs asked for; a tap stops after this one.
                Button {
                    model.stopRepeating()
                } label: {
                    hudChip(active: true) {
                        HStack(spacing: 4) {
                            Image(systemName: "repeat")
                            Text("\(min(session.completed + 1, session.requested))/\(session.requested)")
                        }
                        .font(Theme.numeric(11).weight(.bold))
                        .foregroundStyle(Theme.onGlassGold)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// How far a bottom corner stands inside the safe area: nothing where
    /// the phone has an inset on that side (Summoners War's own place), and
    /// what it takes to stand `cornerFloor` points off the glass where it
    /// has none. `BattleSceneController.hudControls`/`hudSkills` mirror the
    /// corners for the floating numbers.
    private static func cornerMargin(_ inset: CGFloat) -> CGFloat {
        max(0, cornerFloor - inset)
    }
    /// His rows stand 15–18 points off the foot of the glass.
    private static let cornerFloor: CGFloat = 16

    /// The genre's three: a gear (the log, forfeit), the speed, and auto.
    /// Centres 58 points apart, his 0.0605 of the width (2026-09-24; 6
    /// apart on 36-point squares before).
    private var controls: some View {
        HStack(spacing: Self.controlGap) {
            squareControl {
                showMenu = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20, weight: .bold))
            }
            // ×1 → ×2 → ×3 → ×1, the genre's three, remembered between fights
            // (`BattleSpeed`, Docs/FEEL.md W1.1). ×3 keeps the fight's feel,
            // scaled; Skip is the one way to watch a turn without it.
            squareControl {
                model.speed = BattleSpeed.next(after: model.speed)
            } label: {
                Text("×\(Int(model.speed))")
                    .font(Theme.numeric(15).weight(.black))
            }
            .accessibilityLabel("Battle speed")
            .accessibilityValue("×\(Int(model.speed))")
            // His auto shows the pause glyph while it runs, and nothing else
            // changes: the glyph IS the state, as ×3 is the speed's.
            squareControl {
                model.autoBattle.toggle()
            } label: {
                Image(systemName: model.autoBattle ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .black))
            }
            .accessibilityAddTraits(model.autoBattle ? .isSelected : [])
        }
    }

    /// The controls' size and gap: his are 42 points with 15.7 between.
    private static let controlSide: CGFloat = 42
    private static let controlGap: CGFloat = 16

    /// One control, the genre's (2026-09-24; the owner's frames): a 42-point
    /// square of SEE-THROUGH dark — the set shows through it — in a 2-point
    /// white outline, the glyph in white. His outline is 1.7 points of pure
    /// white; his fill darkens the floor under it by a fifth to a third.
    /// Ours was a 36-point square of near-opaque dark glass with a gold
    /// hairline and a pale gold glyph, lit gold when on — a jewel, where his
    /// are a window. The dark is 0.45 (over his ~0.3) because our sets run
    /// paler than his and the glyph is white; a soft shadow under the glyph
    /// and the outline keeps both off a sunlit floor.
    ///
    /// The game's one press (`GamePressStyle`, Docs/FEEL.md W1.8) since
    /// 2026-09-24: the square sinks, ticks and taps under the thumb and
    /// springs back — the speed above all, stepped a fight at a time now
    /// that it is remembered (W1.1). The three were `.plain` and silent.
    private func squareControl<L: View>(action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.55), radius: 1.5, y: 0.5)
                .frame(width: Self.controlSide, height: Self.controlSide)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: 2)
                        .shadow(color: .black.opacity(0.45), radius: 1.5)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(GamePressStyle(.plate))
    }

    /// The skill squares' gap: his centres stand 78.3 points apart on
    /// 65.5-point squares (2026-09-24; 10 apart on 60 before).
    private static let skillGap: CGFloat = 13

    /// The skills as the genre's squares at the bottom right: no plate
    /// behind them, the caster's element lighting each.
    private func skillRow(_ actor: Combatant) -> some View {
        // Resolved together: three skills of one unit never wear the same
        // square (Zeus's bolt, clap and keraunos all named a bolt).
        let icons = SkillArt.keys(for: model.availableSkills.map(\.skill),
                                  element: actor.element, ranged: !actor.model.melee)
        return HStack(spacing: Self.skillGap) {
            ForEach(Array(model.availableSkills.enumerated()), id: \.element.id) { index, option in
                SkillButton(
                    skill: option.skill,
                    cooldown: option.cooldown,
                    isSelected: model.selectedSkillSlot == option.slot,
                    element: actor.element,
                    ranged: !actor.model.melee,
                    iconKey: index < icons.count ? icons[index] : nil,
                    armPulse: armPulses[option.slot] ?? 0,
                    readyGlint: readyGlints[option.slot] ?? 0,
                    onHold: { inspectedSlot = option.slot },
                    onPreview: { pressed in
                        previewSlot = pressed ? option.slot : nil
                        // A finger on a square shows its panel, even on a
                        // skill that is cooling down and cannot be chosen.
                        if pressed { inspectedSlot = option.slot }
                    }
                ) {
                    press(option.slot)
                }
            }
        }
    }

    /// A tap on a skill's square: the view model arms it, or — armed
    /// already — uses it. Arming answers in the hand, the ear and the eye at
    /// once (Docs/FEEL.md W1.9): a selection tick and a gold ring pulsing
    /// out of the square. A use answers with the cast itself; the basic
    /// armed for the player as a turn opens (`armBasicAttack`) makes no
    /// sound, because nobody chose it.
    private func press(_ slot: Int) {
        let wasArmed = model.selectedSkillSlot == slot
        model.selectSkill(slot)
        guard !wasArmed, model.selectedSkillSlot == slot else { return }
        armPulses[slot, default: 0] += 1
        Juice.haptic(.light)
        AudioLibrary.shared.play(.uiTap, volume: 0.8)
    }

    /// The skills ready again since this unit's last turn (Docs/FEEL.md
    /// W1.9): those cooling when its last turn opened and ready at this one
    /// gloss over and chime, a beat after the squares appear. The first turn
    /// a unit is seen only sets its record. Every skill with a cooldown of
    /// two or more passes through the record — the engine counts a cooldown
    /// down as the turn it was set in ENDS, so the skill is still cooling
    /// when its caster's next turn opens; a cooldown of one never takes the
    /// skill away, and there is nothing to announce. On auto the squares are
    /// not up and nothing plays, but the record is kept.
    private func noteCooldowns(of actor: Combatant) {
        let cooling = Set(actor.cooldowns.indices.filter { actor.cooldowns[$0] > 0 })
        let before = coolingSlots[actor.id]
        coolingSlots[actor.id] = cooling
        guard let before, !model.autoBattle else { return }
        let usable = Set(model.availableSkills.map(\.slot))
        let ready = before.subtracting(cooling).intersection(usable)
        guard !ready.isEmpty else { return }
        let actorID = actor.id
        // A beat after the row is made: a count bumped with the square's
        // making would be its first value, and nothing would play.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard model.awaitingActor?.id == actorID else { return }
            for slot in ready { readyGlints[slot, default: 0] += 1 }
            AudioLibrary.shared.play(.starTick, volume: 0.55)
        }
    }

    /// Skip, in the controls' own material and height (2026-09-24): the
    /// see-through dark in a 2-point white outline, white words and glyph.
    /// It was the old controls' dark glass in cream and pale gold (the
    /// caption grey before that read as a disabled button, run 217).
    private var skipButton: some View {
        Button {
            model.skipAnimation()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 13, weight: .black))
                Text("Skip")
                    .font(Theme.body(14).weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.white)
            .shadow(color: .black.opacity(0.55), radius: 1.5, y: 0.5)
            .padding(.horizontal, 16)
            .frame(height: Self.controlSide)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2)
                    .shadow(color: .black.opacity(0.45), radius: 1.5)
            )
            .contentShape(Rectangle())
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    /// The target the next tap would hit, if one is aimed.
    private var aimedTarget: Combatant? {
        model.displayedCombatants.first { $0.id == model.highlightedTarget }
    }

    // MARK: - Shared readouts

    /// One health colour ramp for the whole HUD. Green until 60%, amber to
    /// 30%, red under it — the old single break at 30% meant a unit on 35%
    /// looked exactly like one on 100%, which is the difference between
    /// healing it this turn and losing it next turn.
    private func healthTint(_ fraction: Double) -> Color {
        if fraction < 0.3 { return Theme.danger }
        if fraction < 0.6 { return Color(hex: "#F2A03C") }
        return Theme.success
    }

    /// How the element wheel reads for this particular attack, as a chip, so
    /// "will this hurt" is answered before the skill is spent rather than by
    /// the size of the number afterwards.
    private func matchupChip(attacker: Combatant, defender: Combatant) -> some View {
        let matchup = attacker.element.matchup(against: defender.element)
        let text: String
        let tint: Color
        let glyph: String
        switch matchup {
        case .advantage:
            text = "STRONG ×1.5"
            tint = Theme.success
            glyph = "arrow.up.right.circle.fill"
        case .neutral:
            text = "NEUTRAL"
            tint = Theme.textSecondary
            glyph = "equal.circle.fill"
        case .disadvantage:
            text = "WEAK ×0.7"
            tint = Theme.danger
            glyph = "arrow.down.right.circle.fill"
        }
        return Chip(text: text, systemImage: glyph, tint: tint, filled: matchup != .neutral)
    }

    /// What a skill will do, in one short string, for the face of its tile.
    private func forecast(_ skill: Skill, actor: Combatant) -> String? {
        if let damage = skill.damage {
            let value = Int(estimatedDamage(skill, actor: actor))
            return damage.hits > 1 ? "≈\(value) ×\(damage.hits)" : "≈\(value)"
        }
        if skill.utilities.contains(where: {
            if case .healTargetMaxHealth = $0 { return true }
            if case .healFromAttack = $0 { return true }
            return false
        }) { return "HEAL" }
        if skill.utilities.contains(where: {
            if case .revive = $0 { return true }
            return false
        }) { return "REVIVE" }
        if skill.utilities.contains(where: {
            if case .cleanse = $0 { return true }
            return false
        }) { return "CLEANSE" }
        if skill.utilities.contains(where: {
            if case .strip = $0 { return true }
            return false
        }) { return "STRIP" }
        if let status = skill.statuses.first {
            return status.kind.isBuff ? "BUFF" : "DEBUFF"
        }
        return nil
    }

    /// The damage the skill would do to the unit currently aimed at — its real
    /// defence and the real element matchup, not the collection screen's
    /// standing dummy. It is an estimate and it is labelled with a ≈: the crit
    /// roll and the damage variance are still ahead of it.
    private func estimatedDamage(_ skill: Skill, actor: Combatant) -> Double {
        guard let damage = skill.damage else { return 0 }
        let target = aimedTarget
            ?? model.displayedCombatants.first { $0.side == actor.side.opposing && $0.isAlive }
        var value = DamageCalculator.previewDamage(
            attackStat: actor.scalingValue(for: damage.scaling),
            spec: damage,
            againstDefense: target?.currentStats.def ?? 800
        )
        if let target, target.side != actor.side {
            value *= actor.element.matchup(against: target.element).damageMultiplier
        }
        return value.rounded()
    }

    /// Who a skill lands on, in one or two words.
    private func scopeWord(_ target: TargetSelector) -> String {
        switch target {
        case .singleEnemy: return "1 enemy"
        case .allEnemies: return "All enemies"
        case .randomEnemies(let count): return "\(count) random"
        case .lowestHealthEnemy: return "Weakest"
        case .caster: return "Self"
        case .singleAlly: return "1 ally"
        case .allAllies: return "All allies"
        case .lowestHealthAlly: return "Hurt ally"
        case .deadAlly: return "Fallen ally"
        case .otherAllies: return "Other allies"
        }
    }

    /// Buffs and debuffs as chips: blue for a buff, red for a debuff, the
    /// turns left last. `compact` drops the name and keeps the glyph; at most
    /// `limit` of them, the rest counted in a `+n`. They ride in the boss
    /// bar's glass capsule now (the actor plate they were cut for is gone),
    /// so the glyph is at the type floor and the count is cream on glass.
    private func statusChips(_ statuses: [ActiveStatus], compact: Bool = false, limit: Int = 4) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(statuses.prefix(limit).enumerated()), id: \.offset) { _, status in
                HStack(spacing: 2) {
                    Image(systemName: status.kind.glyph)
                        .font(.system(size: 11, weight: .bold))
                    if !compact {
                        Text(status.kind.displayName)
                            .font(Theme.body(11).weight(.semibold))
                            .lineLimit(1)
                    }
                    Text("\(status.turnsRemaining)")
                        .font(Theme.numeric(11))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Capsule().fill(status.kind.isBuff ? Color(hex: "#2E8FBF") : Color(hex: "#B8403A")))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
            }
            if statuses.count > limit {
                Text("+\(statuses.count - limit)")
                    .font(Theme.numeric(11))
                    .foregroundStyle(Theme.onGlassDim)
            }
        }
    }

    /// The boss's bar across the whole top of the frame, the genre's: its
    /// name and its numbers on a line, then a gold health bar with the blue
    /// attack bar under it in one dark track; a raid's barrier over the
    /// health in the weakness's colour; its chips beside its name.
    ///
    /// The name row stands on the HUD's own dark glass (`hudChip`, the
    /// capsule the stage and the wave wear under it) and the bars lie in a
    /// dark socket (`BossChannel`). Run 221's frame had the crown and the
    /// name bare on a torchlit painting, the 10-point crown lost in the
    /// flames, and the spent 43% of the Colossus's health in the cream UI's
    /// pale channel, where it read as a second, paler fill and not as health
    /// gone.
    private func bossBar(_ boss: Combatant) -> some View {
        let weakness = model.raidWeakness(boss.id)
        let enrage = model.raidEnrage(boss.id)
        // Only above 1: an enrage that has not started yet is not news.
        let enraged = enrage > 1.001
        let raidChips = (weakness == nil ? 0 : 1) + (enraged ? 1 : 0)
        // The capsule is its own width (`hudChip` fixes it, so nothing in
        // it is ever cut to an ellipsis), so it must never be wider than
        // the row. Two chips in all keep their names; past two, the statuses
        // shrink to their glyph and turns, and a raid's own chips take the
        // place of some of them. The widest case — a raid's weakness and
        // enrage beside "LERNAEAN HYDRA" with statuses on — is about 477
        // points, against the 501 an SE leaves beside the numbers.
        let compact = boss.statuses.count + raidChips > 2
        let statusLimit = compact ? 3 - raidChips : 4
        return VStack(spacing: 4) {
            HStack(spacing: 8) {
                hudChip {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Theme.onGlassGold)
                        Text(boss.name.uppercased())
                            .font(Theme.body(11).weight(.black))
                            .tracking(1.4)
                            .foregroundStyle(Theme.onGlass)
                            .lineLimit(1)
                        // The genre's arrow for the unit whose turn it is,
                        // beside the name: green up, yellow even, red down.
                        if let matchup = bossMatchups[boss.id] {
                            Image(uiImage: MatchupIconRenderer.image(for: matchup))
                                .resizable()
                                .frame(width: 18, height: 18)
                                .accessibilityLabel(matchupWord(matchup))
                        }
                        if let weakness {
                            Chip(text: "Open to \(weakness.displayName)", systemImage: weakness.glyph, tint: weakness.color)
                        }
                        if enraged {
                            Chip(
                                text: String(format: "Enraged ×%.1f", enrage),
                                systemImage: "flame.fill",
                                tint: Theme.danger,
                                filled: true
                            )
                        }
                        if !boss.statuses.isEmpty {
                            statusChips(boss.statuses, compact: compact, limit: statusLimit)
                        }
                    }
                }
                Spacer(minLength: 6)
                hudChip {
                    Text("\(Int(boss.currentHealth.rounded())) / \(Int(boss.maxHealth.rounded()))")
                        .font(Theme.numeric(11).weight(.bold))
                        .foregroundStyle(Theme.onGlassGold)
                        .lineLimit(1)
                }
            }
            VStack(spacing: 1.5) {
                // A raid boss's barrier sits ON the health bar, because it is
                // the bar the player is actually hitting: damage goes into it
                // first, and the health underneath does not move until it
                // breaks. Drawn in the boss's current weakness colour.
                if let barrier = model.raidBarrierFraction(boss.id) {
                    let tint = weakness?.color ?? Theme.gold
                    BossChannel(fraction: barrier, top: tint, bottom: tint.opacity(0.78), height: 4)
                }
                BossChannel(
                    fraction: boss.maxHealth > 0 ? boss.currentHealth / boss.maxHealth : 0,
                    top: Color(hex: "#F3D688"), bottom: Color(hex: "#B8872C"), height: 9
                )
                // The unit plates' own attack-bar blue (`PlateArt.attackStops`,
                // his (44, 187, 235) since 2026-09-24).
                BossChannel(fraction: boss.attackBar, top: Color(hex: "#6ECFE8"), bottom: Color(hex: "#1FA6D2"), height: 3)
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 2.5)
            // Dark from top to foot, as the unit plates' well is inside its
            // silver (`PlateArt.frame`), so the frame and the empty channels
            // read as one socket.
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "#2A211A"), Color(hex: "#120D09")],
                                         startPoint: .top, endPoint: .bottom))
                    .opacity(0.92)
            )
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.goldDeep.opacity(0.7), lineWidth: 1))
        }
        .padding(.horizontal, 2)
        // The one thing a player taps a boss for is to aim at it, and its
        // head reaches the band this bar lies across.
        .allowsHitTesting(false)
    }

    /// The boss bar's arrow in words, for VoiceOver.
    private func matchupWord(_ matchup: Element.Matchup) -> String {
        switch matchup {
        case .advantage: return "Strong against the boss"
        case .neutral: return "Even against the boss"
        case .disadvantage: return "Weak against the boss"
        }
    }

    /// An ultimate's announcement: a dark band across the field, the
    /// caster's card sliding in from the left and the skill's name from the
    /// right, gone in a second.
    private func cutInBanner(_ cutIn: BattleViewModel.CutIn) -> some View {
        let accent = Color(hex: cutIn.accentHex)
        // Annotated rather than inferred inside the modifier: nil is the
        // "leave it alone" value for both, and a bare ternary against nil is
        // the sort of thing that needs a compiler to settle.
        let speechLines: Int? = cutIn.isSpeech ? 3 : nil
        let speechWidth: CGFloat? = cutIn.isSpeech ? 420 : nil
        return VStack {
            Spacer().frame(height: 90)
            ZStack {
                LinearGradient(
                    colors: [.clear, Theme.ink.opacity(0.92), Theme.ink.opacity(0.92), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                Rectangle().fill(accent.opacity(0.9)).frame(height: 2).frame(maxHeight: .infinity, alignment: .top)
                Rectangle().fill(accent.opacity(0.9)).frame(height: 2).frame(maxHeight: .infinity, alignment: .bottom)
                HStack(spacing: 16) {
                    if BundleImage.exists(cutIn.portrait) {
                        BundleImage(name: cutIn.portrait, renderedAt: 64)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(accent, lineWidth: 2))
                            .shadow(color: accent.opacity(0.8), radius: 12)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cutIn.unitName.uppercased())
                            .font(Theme.body(11).weight(.bold))
                            .tracking(1.6)
                            .foregroundStyle(accent)
                        // A skill's name is two or three words and wears the
                        // display face; a boss's line is a sentence, and at 26pt
                        // an eighty-character one runs straight out of the 84pt
                        // band. It is set smaller, allowed three lines and given
                        // a width to wrap inside.
                        // Pale gold on the dark band (a line of speech cream):
                        // `textPrimary` is the cream UI's INK, and run 220's
                        // "BREATH OF PLAGUE" was near-black on near-black.
                        Text(cutIn.skillName)
                            .font(cutIn.isSpeech ? Theme.title(15) : Theme.display(26))
                            .foregroundStyle(cutIn.isSpeech ? Theme.onGlass : Theme.onGlassGold)
                            // Every one of these is written so that it is the
                            // no-op it used to be when this is not speech: the
                            // ultimate's announcement must look exactly as it did.
                            .lineLimit(speechLines)
                            .minimumScaleFactor(cutIn.isSpeech ? 0.8 : 1)
                            .fixedSize(horizontal: false, vertical: cutIn.isSpeech)
                            .frame(maxWidth: speechWidth, alignment: .leading)
                            .shadow(color: accent.opacity(0.9), radius: 10)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(height: 84)
            Spacer()
        }
    }

    /// The skill the panel describes: the one touched this turn, while it
    /// is the one chosen or it is cooling down (tapped only to read it).
    /// Choosing another square, using the skill or the turn passing takes
    /// the panel down.
    private var inspectedOption: SkillOption? {
        guard let slot = inspectedSlot,
              let option = model.availableSkills.first(where: { $0.slot == slot })
        else { return nil }
        if option.cooldown > 0 || model.selectedSkillSlot == slot || previewSlot == slot {
            return option
        }
        return nil
    }

    /// The genre's skill panel, over the skill squares at the bottom right:
    /// the skill's art and name, its cooldown and what it lands on, the
    /// estimate against the target aimed at, the words of what it does,
    /// and how to use it from here. Dark glass, so it reads over any set;
    /// it never takes a tap, so an enemy under it can still be chosen.
    private func skillCard(_ skill: Skill, cooldown: Int, actor: Combatant) -> some View {
        let ready = cooldown <= 0
        let chosen = model.selectedSkillSlot == skill.slot
        let hint: String
        if !ready {
            hint = cooldown == 1 ? "Ready next turn" : "Ready in \(cooldown) turns"
        } else if !chosen {
            hint = "Tap the skill to choose it"
        } else if BattleViewModel.needsTarget(skill) {
            hint = skill.target.hitsEnemies ? "Tap an enemy to use it" : "Tap an ally to use it"
        } else {
            hint = "Tap the skill again to use it"
        }
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 9) {
                SkillIcon(skill: skill, element: actor.element, ranged: !actor.model.melee,
                          size: 34, socket: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(skill.name.uppercased())
                        .font(Theme.title(14))
                        .foregroundStyle(Theme.onGlassGold)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(Self.skillFacts(skill))
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.onGlass.opacity(0.75))
                }
                Spacer(minLength: 6)
                // What it would do to the unit aimed at — the estimate the
                // squares used to print across their own art.
                if let forecast = forecast(skill, actor: actor) {
                    Text(forecast)
                        .font(Theme.numeric(13).weight(.bold))
                        .foregroundStyle(Theme.onGlassGold)
                        .fixedSize()
                }
            }
            Text(skill.description)
                .font(Theme.body(12.5))
                .foregroundStyle(Theme.onGlass)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                Image(systemName: ready ? "hand.tap.fill" : "hourglass")
                    .font(.system(size: 11, weight: .semibold))
                Text(hint)
                    .font(Theme.body(11).weight(.semibold))
            }
            .foregroundStyle(ready ? Theme.onGlassGold : Theme.onGlass.opacity(0.7))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(width: 330, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.glass))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.glassRim, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
        .allowsHitTesting(false)
    }

    /// Under the CI tour's `-tour-skill-info` the player's first turn opens
    /// with a skill chosen — the second when it is ready, the basic when
    /// not — and its panel up, as a tap would leave it, so a frame shows it.
    private static let touringSkillPanel = ProcessInfo.processInfo.arguments.contains("-tour-skill-info")

    private func showTourSkillPanel() {
        guard Self.touringSkillPanel, inspectedSlot == nil, model.awaitingActor != nil else { return }
        let slot = model.availableSkills.first(where: { $0.slot > 0 && $0.isReady })?.slot ?? 0
        // Choosing the square already chosen would USE it (the second tap
        // commits), so only a different one is chosen.
        if model.selectedSkillSlot != slot { model.selectSkill(slot) }
        inspectedSlot = slot
    }

    /// One line under the name: the cooldown and what the skill lands on.
    private static func skillFacts(_ skill: Skill) -> String {
        let cooldown = skill.cooldown > 0 ? "Cooldown \(skill.cooldown) turns" : "No cooldown"
        let lands: String
        switch skill.target {
        case .singleEnemy: lands = "One enemy"
        case .allEnemies: lands = "All enemies"
        case .randomEnemies(let count): lands = "\(count) random enemies"
        case .lowestHealthEnemy: lands = "The weakest enemy"
        case .caster: lands = "Self"
        case .singleAlly: lands = "One ally"
        case .allAllies: lands = "All allies"
        case .lowestHealthAlly: lands = "The weakest ally"
        case .deadAlly: lands = "A fallen ally"
        case .otherAllies: lands = "The other allies"
        }
        return cooldown + " · " + lands
    }

    // MARK: - Log

    private var logOverlay: some View {
        VStack {
            Spacer()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(model.log.indices, id: \.self) { index in
                            let line = model.log[index]
                            Text(line)
                                .font(Theme.body(11))
                                .foregroundStyle(
                                    line.hasPrefix("—") ? Theme.gold : Theme.textSecondary
                                )
                                .id(index)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 150)
                .background(Theme.panel())
                .onChange(of: model.log.count) { _, count in
                    withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 96)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// One channel of the boss bar: an EMPTY SOCKET in the unit plates' dark
/// (#130E0A) with the fill lying in it, lit along its top the way the
/// plates' fills are (`PlateArt.fill`), and eased to a new value as the
/// plates ease theirs. `StatBar` is the cream UI's recessed channel, a pale
/// sunken groove that belongs on marble; over the fight the Colossus's spent
/// health read in it as a second, paler fill (run 221).
private struct BossChannel: View {
    let fraction: Double
    let top: Color
    let bottom: Color
    let height: CGFloat

    private var filled: CGFloat { CGFloat(min(1, max(0, fraction))) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(hex: "#130E0A").opacity(0.85))
                Capsule().strokeBorder(Color.black.opacity(0.55), lineWidth: 0.75)
                Capsule()
                    .fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        Capsule()
                            .fill(Color.white.opacity(0.35))
                            .frame(height: max(0.8, height * 0.16))
                            .padding(.horizontal, height * 0.3)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .padding(.top, height * 0.12)
                    )
                    .frame(width: geometry.size.width * filled)
                    .shadow(color: bottom.opacity(0.6), radius: 2.5)
            }
        }
        .frame(height: height)
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}

/// One skill, the genre's square: a dark socket lit from behind in the
/// caster's element, the painted art large, a gold frame that brightens
/// and grows on the skill in hand, a dark veil with the turns left while
/// it cools. 65 points (60 until 2026-09-24: his measure 65.3–66 on the
/// owner's phone), three abreast at the bottom right, no plate behind them.
struct SkillButton: View {
    let skill: Skill
    let cooldown: Int
    let isSelected: Bool
    /// The caster's element: the light behind the art, and which mark a
    /// plain elemental throw draws.
    var element: Element = .radiance
    /// A caster or an archer strikes from where it stands, and its skills
    /// read as thrown rather than swung.
    var ranged: Bool = false
    /// The icon chosen for this slot with the caster's other skills in mind.
    var iconKey: String? = nil
    /// Bumped each time the player arms this skill (Docs/FEEL.md W1.9): a
    /// gold ring pulses out of the square with the selection tick.
    var armPulse: Int = 0
    /// Bumped when the skill comes off cooldown: a gloss sweeps across the
    /// art with the chime.
    var readyGlint: Int = 0
    /// Held down: show what the skill does.
    var onHold: (() -> Void)? = nil
    /// True the moment a finger lands on the tile, false when it lifts.
    var onPreview: ((Bool) -> Void)? = nil
    let action: () -> Void

    /// Set by a hold so the release that follows it is not read as a tap:
    /// reading a skill must never cast it.
    @State private var wasHeld = false

    private var isReady: Bool { cooldown <= 0 }
    private var tint: Color { element.color }
    /// The square's side; the art, the light and the corner scale with it.
    private static let side: CGFloat = 65
    private static let corner: CGFloat = 11

    var body: some View {
        Button {
            if wasHeld { wasHeld = false; return }
            if isReady { action() }
        } label: {
            // The genre's square: the art, and nothing else. The estimate
            // that used to be printed across the bottom ("≈847") is on the
            // held card now, and the damage a skill really does is the
            // number that flies off the victim when the blow lands — the
            // owner: "I hate having the NUMBER show on top of the skill …
            // only show the damage when the character attacks."
            ZStack {
                RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                    .fill(LinearGradient(colors: [Color(hex: "#3B2F22"), Color(hex: "#160F09")], startPoint: .top, endPoint: .bottom))
                RadialGradient(colors: [tint.opacity(isReady ? 0.55 : 0.18), .clear], center: .center, startRadius: 2, endRadius: 41)
                SkillIcon(skill: skill, element: element, ranged: ranged, resolvedKey: iconKey,
                          size: 54, tint: .white, dimmed: !isReady)
                    .shadow(color: tint.opacity(isReady ? 0.8 : 0), radius: 7)
                if !isReady {
                    RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                    OutlinedText(text: "\(cooldown)", font: Theme.display(28), fill: .white, width: 1.2)
                }
                // Ready again: a pale band sweeps across the art, inside the
                // square's clip.
                SkillGloss(trigger: readyGlint)
            }
            .frame(width: Self.side, height: Self.side)
            .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                    .strokeBorder(
                        isReady ? Rarity.legendary.frame : Rarity.common.frame,
                        lineWidth: isSelected ? 3 : 2
                    )
            )
            .overlay(alignment: .topTrailing) {
                // Who it lands on — but only when that is worth saying. A
                // plain single-enemy skill is the common case and wears
                // nothing, so the art is what the eye meets. Inside the
                // frame's corner on a 16-point disc of dark glass, the glyph
                // in cream: it hung over the gold corner as a small grey
                // disc with a 7-point glyph nobody could read (run 217).
                if let badge = Self.targetGlyph(for: skill) {
                    Image(systemName: badge)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.onGlass)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Theme.glass))
                        .overlay(Circle().strokeBorder(Theme.glassRim, lineWidth: 0.8))
                        .padding(4)
                }
            }
            // Armed: a gold ring goes out of the square, outside its clip.
            .overlay {
                SkillArmRing(trigger: armPulse, corner: Self.corner)
            }
            .shadow(color: isSelected ? Theme.gold.opacity(0.9) : Color.black.opacity(0.5), radius: isSelected ? 10 : 4, y: isSelected ? 0 : 2)
            .scaleEffect(isSelected ? 1.06 : 1)
            .animation(.easeOut(duration: 0.15), value: isSelected)
        }
        // A ButtonStyle rather than a gesture: `isPressed` is the one way to
        // watch a finger land that cannot swallow the tap it is watching.
        .buttonStyle(PressStyle(onPress: { pressed in onPreview?(pressed) }))
        // A hold shows the card even on a skill that is cooling down.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                wasHeld = true
                onHold?()
                // The button may or may not fire on the release after a hold
                // (it varies by iOS); either way the flag is spent shortly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { wasHeld = false }
            }
        )
        .disabled(!isReady && onHold == nil)
    }

    /// Reports the press to the caller and shrinks the tile while it is held.
    struct PressStyle: ButtonStyle {
        var onPress: (Bool) -> Void

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.93 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onChange(of: configuration.isPressed) { _, pressed in onPress(pressed) }
        }
    }

    /// A glyph per target shape: how many, and which side. Nil for the one
    /// enemy in front of you, which needs no telling.
    static func targetGlyph(for skill: Skill) -> String? {
        switch skill.target {
        case .allEnemies: return "person.3.fill"
        case .randomEnemies: return "die.face.5.fill"
        case .allAllies, .otherAllies: return "heart.circle.fill"
        case .singleAlly, .lowestHealthAlly: return "heart.fill"
        case .deadAlly: return "arrow.uturn.up.circle.fill"
        case .caster: return "person.crop.circle.fill"
        default: return nil
        }
    }
}

// MARK: - The skill squares' answers (Docs/FEEL.md W1.9)

/// The animated values of a ring that goes out and fades: the arm ring on a
/// skill square and the ring the VICTORY stamp sends out as it lands.
/// Hidden at rest; a keyframe animation ends where it stands, so it rests
/// hidden again after every play.
private struct PulseRingFrame {
    var scale: Double = 1
    var opacity: Double = 0
}

/// The gold ring that pulses out of a skill's square as the player arms it
/// (`SkillButton.armPulse`): the rim of the square, gone out a third past
/// it and faded in under half a second. Under Reduce Motion it brightens
/// and fades where it stands.
private struct SkillArmRing: View {
    let trigger: Int
    let corner: CGFloat

    var body: some View {
        let reach: Double = Motion.isCalm ? 1.0 : 1.32
        RoundedRectangle(cornerRadius: corner + 2, style: .continuous)
            .strokeBorder(Theme.goldText, lineWidth: 3)
            .shadow(color: Color(hex: "#FFD678").opacity(0.9), radius: 6)
            .keyframeAnimator(initialValue: PulseRingFrame(), trigger: trigger) { content, frame in
                content
                    .scaleEffect(frame.scale)
                    .opacity(frame.opacity)
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    MoveKeyframe(1.0)
                    CubicKeyframe(reach, duration: 0.45)
                }
                KeyframeTrack(\.opacity) {
                    MoveKeyframe(0)
                    LinearKeyframe(1, duration: 0.05)
                    CubicKeyframe(0, duration: 0.42)
                }
            }
            .allowsHitTesting(false)
    }
}

/// Where the ready gloss's band stands across the square, in squares from
/// its centre: off the left edge at rest, off the right once it has swept.
private struct GlossSweepFrame {
    var travel: Double = -1.3
}

/// The level-up numerals' animated values (`BattleResultView.levelUpAct`):
/// small, low and clear before the fanfare's chord; up to full on it.
private struct LevelNumeralFrame {
    var scale: Double = 0.35
    var opacity: Double = 0
    var rise: Double = 22
}

/// A skill ready again (`SkillButton.readyGlint`): a pale band sweeps
/// across the art corner to corner, the genre's glint on a thing that has
/// come back. Drawn inside the square's clip, added to the art. Under
/// Reduce Motion it still passes — a light crossing a button, not the
/// field moving — but slower.
private struct SkillGloss: View {
    let trigger: Int

    var body: some View {
        let sweep: TimeInterval = Motion.isCalm ? 0.9 : 0.6
        GeometryReader { geometry in
            let side: CGFloat = geometry.size.width
            let bandWidth: CGFloat = side * 0.42
            let bandHeight: CGFloat = side * 1.9
            LinearGradient(
                colors: [Color.white.opacity(0), Color.white.opacity(0.65), Color.white.opacity(0)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: bandWidth, height: bandHeight)
            .rotationEffect(.degrees(22))
            .keyframeAnimator(initialValue: GlossSweepFrame(), trigger: trigger) { content, frame in
                content.offset(x: side * CGFloat(frame.travel))
            } keyframes: { _ in
                KeyframeTrack(\.travel) {
                    MoveKeyframe(-1.3)
                    CubicKeyframe(1.3, duration: sweep)
                }
            }
            .frame(width: side, height: side)
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

// MARK: - The beat on the field (Docs/FEEL.md W1.7)

/// VICTORY stamped over the live field, the genre's: the word slams down
/// out of the air onto a dark band ruled in gold, a ring of gold light goes
/// out from it, and the stars the fight earned slam in over it one by one in
/// a shallow arc, each with its tick and its knock in the hand; the stars
/// not earned stand as empty sockets. It keeps to the top of the frame —
/// the stars first, the band under them — so the team the camera is framing
/// and the gold EXP bars over their heads stay clear, and it never takes a
/// tap. Under Reduce Motion nothing travels: the word and the stars fade in
/// where they stand, and no ring goes out.
struct VictoryStamp: View {
    let stars: Int

    @State private var landed = false
    @State private var shownStars = 0

    private var earned: Int { min(3, max(0, stars)) }

    /// The band's gold rules, bright in the middle and gone at the ends.
    private static let rule = LinearGradient(
        colors: [Color(hex: "#EDCB6C").opacity(0), Color(hex: "#FFF3C8"), Color(hex: "#EDCB6C").opacity(0)],
        startPoint: .leading, endPoint: .trailing
    )

    var body: some View {
        let calm: Bool = Motion.isCalm
        let ringFrom: Double = calm ? 0 : 0.95
        let wordScale: CGFloat = landed || calm ? 1 : 2.1
        VStack(spacing: 2) {
            // The arc: the middle star larger and a little higher.
            HStack(alignment: .bottom, spacing: 12) {
                star(1, size: 30)
                star(2, size: 38)
                    .offset(y: -6)
                star(3, size: 30)
            }
            .opacity(landed ? 1 : 0)
            ZStack {
                StampBand(rule: VictoryStamp.rule, shade: 0.8)
                    .scaleEffect(x: landed ? 1 : 0.25, y: 1)
                    .opacity(landed ? 1 : 0)
                Ellipse()
                    .strokeBorder(Theme.goldText, lineWidth: 3)
                    .frame(width: 320, height: 84)
                    .shadow(color: Color(hex: "#FFD678").opacity(0.8), radius: 10)
                    .keyframeAnimator(initialValue: PulseRingFrame(), trigger: landed) { content, frame in
                        content
                            .scaleEffect(frame.scale)
                            .opacity(frame.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.scale) {
                            MoveKeyframe(0.7)
                            CubicKeyframe(1.9, duration: 0.6)
                        }
                        KeyframeTrack(\.opacity) {
                            MoveKeyframe(ringFrom)
                            CubicKeyframe(0, duration: 0.6)
                        }
                    }
                Text("VICTORY")
                    .font(Theme.display(62))
                    .tracking(8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .carved()
                    .scaleEffect(wordScale)
                    .opacity(landed ? 1 : 0)
            }
            .frame(height: 84)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Victory, \(earned) of 3 stars")
        .onAppear(perform: play)
    }

    /// A star's socket, and over it the gold star once it has slammed in.
    private func star(_ index: Int, size: CGFloat) -> some View {
        let lit = index <= shownStars
        let slam: CGFloat = lit || Motion.isCalm ? 1 : 2.6
        return ZStack {
            Image(systemName: "star.fill")
                .font(.system(size: size, weight: .black))
                .foregroundStyle(Color.black.opacity(0.55))
            Image(systemName: "star")
                .font(.system(size: size, weight: .black))
                .foregroundStyle(Theme.goldDim)
            if index <= earned {
                Image(systemName: "star.fill")
                    .font(.system(size: size, weight: .black))
                    .foregroundStyle(Theme.goldText)
                    .shadow(color: Color(hex: "#FFD678").opacity(0.85), radius: 10)
                    .scaleEffect(slam)
                    .opacity(lit ? 1 : 0)
            }
        }
    }

    /// The word lands a breath after the HUD has gone, then the stars, a
    /// quarter second apart — the reckoning's own cadence, heavier.
    private func play() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(Motion.pop) { landed = true }
            Juice.haptic(.heavy)
            AudioLibrary.shared.play(.hitHeavy, volume: 0.55)
        }
        let count = earned
        for index in 0..<count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55 + Double(index) * 0.24) {
                withAnimation(Motion.pop) { shownStars = index + 1 }
                AudioLibrary.shared.play(.starTick, volume: 0.85)
                Juice.haptic(index == count - 1 ? .medium : .light)
            }
        }
    }
}

/// DEFEAT over the grey field (Docs/FEEL.md W1.7): the scene's colour
/// drains (`BattleSceneController.drainColour`) while the word settles onto
/// its band in wine — sinking a little, never slamming, and with no ring: a
/// loss is not an event to ring. A draw says DRAW in marble.
struct DefeatStamp: View {
    let outcome: BattleOutcome

    @State private var shown = false

    private var word: String { outcome == .draw ? "DRAW" : "DEFEAT" }

    var body: some View {
        let settled: Bool = shown || Motion.isCalm
        let glow: Double = outcome == .draw ? 0 : 0.7
        ZStack {
            StampBand(rule: DefeatStamp.ruleFill(for: outcome), shade: 0.72)
            Text(word)
                .font(Theme.display(62))
                .tracking(8)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(DefeatStamp.wordFill(for: outcome))
                .shadow(color: Color.black.opacity(0.8), radius: 1, y: 1)
                .shadow(color: Theme.wine.opacity(glow), radius: 14)
                .scaleEffect(settled ? 1 : 1.12)
                .offset(y: settled ? 0 : -10)
        }
        .frame(height: 84)
        .opacity(shown ? 1 : 0)
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .frame(maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(word.capitalized)
        .onAppear {
            withAnimation(Motion.respecting(.easeOut(duration: 0.7))) { shown = true }
        }
    }

    /// The word: wine for a defeat, from a lit rose at its crown to the
    /// deep wine at its foot; marble for a draw.
    private static func wordFill(for outcome: BattleOutcome) -> LinearGradient {
        if outcome == .draw {
            return LinearGradient(colors: [Color(hex: "#F4F1EA"), Theme.marble, Color(hex: "#A9A396")],
                                  startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(colors: [Color(hex: "#E58A9C"), Color(hex: "#B8405A"), Theme.wine],
                              startPoint: .top, endPoint: .bottom)
    }

    private static func ruleFill(for outcome: BattleOutcome) -> LinearGradient {
        if outcome == .draw {
            return LinearGradient(colors: [Theme.marble.opacity(0), Theme.marble, Theme.marble.opacity(0)],
                                  startPoint: .leading, endPoint: .trailing)
        }
        return LinearGradient(colors: [Theme.wine.opacity(0), Color(hex: "#B8405A"), Theme.wine.opacity(0)],
                              startPoint: .leading, endPoint: .trailing)
    }
}

/// The band a stamp's word lies on: dark across the middle and clear at
/// both ends, the way the ultimate's cut-in band is, with a rule of `rule`
/// along each edge. As tall as the stamp makes it.
private struct StampBand: View {
    let rule: LinearGradient
    let shade: Double

    var body: some View {
        LinearGradient(
            colors: [Color.black.opacity(0), Theme.ink.opacity(shade), Theme.ink.opacity(shade), Color.black.opacity(0)],
            startPoint: .leading, endPoint: .trailing
        )
        .overlay(alignment: .top) {
            Rectangle().fill(rule).frame(height: 2)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(rule).frame(height: 2)
        }
    }
}

/// The end of a battle, in two acts.
///
/// The owner: "when we win a battle, it should first show the stats of the
/// battle, then you tap to show a chest that opens or like a greek chest, as
/// it opens it shows your prize. Again, I want this to feel PREMIUM."
///
/// ACT ONE, THE RECKONING. The word, the stars ticking in one at a time, the
/// three numbers of the fight, and a row per unit saying what each one did —
/// damage dealt as a bar against the best, damage taken, healing, kills — with
/// a laurel on the one that did the most. A defeat gets the same reckoning in
/// wine instead of gold, and a Continue button, because there is no chest to
/// open after losing.
///
/// BETWEEN THEM, THE LEVEL (2026-09-24, Docs/FEEL.md W1.6). When the fight
/// raised the demigod's level, the tap on the reckoning brings the level-up
/// on its own: LEVEL 8 in carved gold springing in over light shafts on the
/// fanfare's downbeat, then what it paid — the energy refilled, the bar's
/// new length, the divinity — and what it opened, one chip at a time. The
/// refill used to happen with no word at all.
///
/// ACT TWO, THE CHEST. One tap and the reckoning gives way to a marble
/// strongbox bound in bronze, shut, waiting. A second tap lifts the lid: a
/// flash, rays, the inside lit gold, and the spoils rise out of it one by one
/// onto a shelf above, each with a tick and a pulse in the hand. Only then does
/// Continue appear. Every timed step checks it still belongs to the current
/// sequence, so a tap that skips ahead cannot be followed by a stale step.
///
/// Nothing here is a flat fill. The chest is stone plate and bronze plate over
/// a bevel; the tiles are panels; the light is additive over the scrim. That
/// is the whole difference between a receipt and a reward.
struct BattleResultView: View {
    let summary: BattleSummary
    let onDismiss: () -> Void
    /// The CI tour sets this so a five-second photograph catches the chest
    /// open with the spoils out, rather than the reckoning waiting for a tap.
    var autoplay: Bool = false
    /// The store, for the relic drop card a spoil tile opens; without one
    /// the tiles are not tappable.
    var store: GameStore? = nil
    /// The reckoning's scrim. The battle lays it over the live field at 0.55
    /// (Docs/FEEL.md W1.7) so the team the victory beat posed stays in sight
    /// behind the panels; the level-up and the chest deepen it to
    /// `stageScrim`, because their light is additive and a lit field under
    /// it washes it out. 0.84 alone, over black, for the tour's demo.
    var scrim: Double = 0.84
    /// The stars have already slammed in over the field (`VictoryStamp`):
    /// the verdict shows them lit rather than ticking them in a second time.
    var starsLanded: Bool = false

    private enum Phase { case reckoning, levelUp, chest, opened }

    @State private var phase: Phase = .reckoning
    /// The reckoning's panels have slid in over the scrim.
    @State private var arrived = false
    /// The level-up's numerals have landed (they spring in on it) and how
    /// many of its chips are in.
    @State private var levelLanded = false
    @State private var levelChipsShown = 0
    /// When the level-up began: a tap in its first second is the one that
    /// opened it, still under the thumb, not a wish to leave it.
    @State private var levelBegan: Date?
    @State private var shownStars = 0
    @State private var rowsShown = 0
    @State private var lidOpen = false
    /// The chest has lifted and faded under the flash; the spoils remain.
    @State private var chestGone = false
    @State private var flash: Double = 0
    @State private var raysShown = false
    @State private var rays: Double = 0
    @State private var lootShown = 0
    @State private var continueShown = false
    @State private var pulse = false
    @State private var sequence = 0
    /// The relic whose drop card is up.
    @State private var openedRelic: Relic?

    private var won: Bool { summary.outcome == .victory }
    /// A loss can have spoils now: a raid's grade pays its aether on a wipe
    /// as well as a kill, and the model puts nothing else on a lost raid's
    /// shelf. Every other defeat has an empty shelf, as it always did.
    private var hasSpoils: Bool { !summary.loot.isEmpty }
    /// The fight raised the demigod's level: the level-up comes between the
    /// reckoning and the chest.
    private var hasLevelUp: Bool { summary.levelUp != nil }
    /// The stars the verdict shows lit.
    private var litStars: Int { starsLanded && won ? summary.stars : shownStars }

    /// The scrim under the level-up and the chest, whatever the reckoning's.
    private static let stageScrim: Double = 0.84
    /// How long the tour holds the level-up before the chest, so the CI
    /// job's frame lands on it (`[TourCue] levelup`).
    private static let tourLevelUpHold: TimeInterval = 16

    var body: some View {
        ZStack {
            // The scrim. It stays dark on a cream interface on purpose: the
            // chest's beam, the flash and the rays are additive light and
            // vanish on cream, and everything written straight on it is gold
            // or marble, never ink — the panels carry the ink. Over the live
            // field the reckoning's is lighter (`scrim`), and it deepens as
            // the reckoning gives way.
            Color.black
                .opacity(phase == .reckoning ? scrim : max(scrim, Self.stageScrim))
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.45), value: phase)
            // Over the live field the verdict's gold and marble words stand
            // on the set, not on black: a little more dark under the left
            // column, gone by the middle, where the team the beat posed is.
            if phase == .reckoning, scrim < Self.stageScrim {
                LinearGradient(colors: [Color.black.opacity(0.4), Color.black.opacity(0)],
                               startPoint: .leading, endPoint: .center)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            switch phase {
            case .reckoning:
                reckoning
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            case .levelUp:
                if let levelUp = summary.levelUp {
                    levelUpAct(levelUp)
                        .transition(.opacity)
                }
            case .chest, .opened:
                chestAct
                    .transition(.opacity)
            }
        }
        .onAppear { beginReckoning() }
    }

    // MARK: - Act one

    /// The panels slide in from below over the scrim (Docs/FEEL.md W1.7):
    /// the reckoning arrives on the field rather than replacing it.
    private var reckoning: some View {
        reckoningBody
            .offset(y: arrived ? 0 : 44)
            .opacity(arrived ? 1 : 0)
    }

    private var reckoningBody: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                verdict
                    .frame(width: 292)
                unitRows
                    .frame(maxWidth: .infinity)
            }
            // Its own height, always. When the unit rows stood taller than
            // the verdict (four rows, no raid grade), this row had no give
            // at all, tied with the spoils line below it, and the stack
            // offered it half the screen: the verdict got 171 points of its
            // 186 and shrank what could shrink — VICTORY to 0.8 and the
            // three numbers to 0.7 (run 221's 20-a, against 38-a, 18-d and
            // 6-a, whose verdicts were the taller column and never shrank).
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 26)
            .padding(.top, 12)

            Spacer(minLength: 6)

            if hasSpoils || hasLevelUp {
                // A level-up comes first, and it is not the spoils yet.
                Text(hasLevelUp ? "TAP TO CONTINUE" : "TAP TO CLAIM YOUR SPOILS")
                    .font(Theme.body(11).weight(.black))
                    .tracking(2.2)
                    .foregroundStyle(Theme.gold)
                    .opacity(pulse ? 1 : 0.45)
                    .padding(.bottom, 14)
            } else {
                PrimaryButton(title: "Continue", action: onDismiss)
                    .frame(width: 220)
                    .padding(.bottom, 12)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard hasSpoils || hasLevelUp else { return }
            leaveReckoning()
        }
    }

    /// The word, the stars and the three numbers.
    private var verdict: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headline)
                .font(Theme.display(46))
                .foregroundStyle(won ? Theme.gold : (summary.outcome == .draw ? Theme.marble : Theme.wine))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(color: (won ? Theme.gold : Theme.wine).opacity(0.45), radius: 18)
            if !summary.title.isEmpty {
                // Marble, not the caption ink: this line stands straight on
                // the dark scrim, with no panel under it.
                Text(summary.title)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.marble)
                    .lineLimit(1)
            }
            if won, summary.stars > 0 {
                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { index in
                        Image(systemName: "star.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(index <= litStars ? Theme.gold : Theme.stroke)
                            .scaleEffect(index <= litStars ? 1 : 0.7)
                            .shadow(color: Theme.gold.opacity(index <= litStars ? 0.7 : 0), radius: 8)
                            .animation(Motion.pop, value: litStars)
                    }
                    if summary.isFirstClear {
                        Chip(text: "First clear", systemImage: "seal.fill", tint: Theme.verdigris, filled: true)
                            .padding(.leading, 6)
                    }
                }
                .padding(.top, 2)
            }
            // A raid's grade: the stamp and the one line that earned it. It
            // stands on a loss as well, because a D is a thing to improve on
            // and a bare DEFEAT is not.
            if let grade = summary.raidGrade {
                HStack(spacing: 10) {
                    RaidGradeStamp(grade: grade, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("RAID GRADE")
                            .font(Theme.body(8).weight(.black))
                            .tracking(1.4)
                            .foregroundStyle(Theme.goldDim)
                        Text(summary.raidGradeLine)
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.marble)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 4)
            }
            HStack(spacing: 8) {
                statTile("TURNS", value: "\(summary.turns)")
                statTile("DEALT", value: Int(summary.damageDealt).formatted())
                statTile("TAKEN", value: Int(summary.damageTaken).formatted())
            }
            .padding(.top, 8)
        }
    }

    private func statTile(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(Theme.body(8).weight(.black))
                .tracking(1.4)
                .foregroundStyle(Theme.goldDim)
            // One size on every result screen: the reckoning's top row keeps
            // its own height, so this shrinks only for a figure wider than
            // the tile's 92 points — never a real one (eight digits and their
            // commas are about 80; run 221's "32,810" measured 49).
            Text(value)
                .font(Theme.numeric(15))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Theme.panel(Theme.tightCorner))
    }

    /// One row per unit, damage as a bar against the best in the team, and the
    /// laurel on whoever earned it.
    private var unitRows: some View {
        let best = max(1, summary.unitStats.map { $0.dealt + $0.healed }.max() ?? 1)
        return VStack(spacing: 6) {
            ForEach(Array(summary.unitStats.enumerated()), id: \.element.id) { index, unit in
                unitRow(unit, share: (unit.dealt + unit.healed) / best)
                    .opacity(index < rowsShown ? 1 : 0)
                    .offset(x: index < rowsShown ? 0 : 28)
                    .animation(.spring(response: 0.42, dampingFraction: 0.8), value: rowsShown)
            }
            if summary.unitStats.isEmpty {
                Text("No reckoning for this one.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.marble)
            }
        }
    }

    private func unitRow(_ unit: BattleSummary.UnitStat, share: Double) -> some View {
        let isMVP = unit.id == summary.mvpID
        return HStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if BundleImage.exists(unit.portraitName) {
                        BundleImage(name: unit.portraitName, renderedAt: 44)
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(unit.element.color.opacity(0.5))
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .rarityFrame(Rarity(stars: unit.stars), radius: 6)
                .saturation(unit.survived ? 1 : 0.15)
                .opacity(unit.survived ? 1 : 0.6)
                if isMVP {
                    Image(systemName: "laurel.leading")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Theme.ink)
                        .padding(3)
                        .background(Circle().fill(Theme.gold))
                        .offset(x: 6, y: -6)
                }
            }
            // The fallen mark is on the greyed portrait, the laurel's twin at
            // the other corner, and no longer a chip on the name's line: a
            // defeat puts it on every row, where it took 66 points from each
            // name and would wrap every awakened title in a five-unit team
            // (17 points a line), which is a reckoning taller than the phone.
            .overlay(alignment: .bottomTrailing) {
                if !unit.survived {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Theme.onGlass)
                        .padding(3)
                        .background(Circle().fill(Theme.wine))
                        .offset(x: 6, y: 6)
                        .accessibilityLabel("Fallen")
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                // The name has its line to itself but for the kills, and it
                // WRAPS: an awakened title runs to 36 characters ("Sekhmet,
                // Bringer of the Seven Arrows", about 257 points against the
                // 238 the CI phone's column leaves it), and with the MVP
                // capsule on this line run 221 printed "ANUBIS, KEEPER OF THE
                // ASH R…". The kills chip keeps its own width, so the name is
                // what gives: two lines hold every name in the roster on every
                // phone down to an SE, and a third is allowed rather than an
                // ellipsis. The chip sits on its first line.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(unit.name)
                        .font(Theme.title(12))
                        .foregroundStyle(isMVP ? Theme.gold : Theme.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    Spacer(minLength: 0)
                    if unit.kills > 0 {
                        Chip(text: "\(unit.kills) \(unit.kills == 1 ? "kill" : "kills")", systemImage: "bolt.fill", tint: Theme.gold)
                            .fixedSize()
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.plate.opacity(0.6))
                        // Nothing dealt or healed draws no fill: the 4-point
                        // floor drew a gold dot under every name of run 245's
                        // DEFEAT, where the team had done nothing yet.
                        if share > 0 {
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.goldDim, Theme.gold], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(4, geo.size.width * share))
                        }
                    }
                }
                .frame(height: 5)
                // The MVP capsule ends the numbers, which leave it room: a
                // healer's three at five digits are about 248 of the CI
                // phone's 305-point column, and the capsule with its gap 46.
                // Nested, so the gap is the spacer's 8 and not the numbers'
                // own spacing twice over.
                HStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Text("Dealt \(Int(unit.dealt).formatted())")
                        if unit.healed > 0 { Text("Healed \(Int(unit.healed).formatted())") }
                        Text("Taken \(Int(unit.taken).formatted())")
                    }
                    if isMVP {
                        Spacer(minLength: 8)
                        Text("MVP")
                            .font(Theme.body(11).weight(.black))
                            .tracking(1)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.gold))
                            .fixedSize()
                    }
                }
                .font(Theme.numeric(9))
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.panel(Theme.tightCorner))
    }

    // MARK: - Between the acts: the level (Docs/FEEL.md W1.6)

    /// One chip of the level-up: what the level paid or opened.
    private struct LevelUpChip: Identifiable {
        let id: Int
        let label: String
        let value: String
        /// A painted item (`ItemArt`: the energy's bolt, divinity).
        let itemKey: String?
        /// A bundle painting — a decoration's thumbnail.
        let art: String?
        let glyph: String
    }

    /// What the level paid, then what it opened: at most three of those,
    /// the rest counted on the last chip, so the act keeps to two rows on
    /// the smallest phone.
    private func levelChips(_ levelUp: PlayerLevelUp) -> [LevelUpChip] {
        var chips: [LevelUpChip] = [
            LevelUpChip(id: 0, label: "Energy refilled", value: "\(levelUp.maxEnergy)/\(levelUp.maxEnergy)",
                        itemKey: "energy", art: nil, glyph: "bolt.fill"),
            LevelUpChip(id: 1, label: "Max energy", value: "+\(levelUp.maxEnergyGained)",
                        itemKey: "energy", art: nil, glyph: "bolt.fill"),
            LevelUpChip(id: 2, label: "Divinity", value: "+\(levelUp.divinity)",
                        itemKey: "divinity", art: nil, glyph: "sparkles"),
        ]
        let shown = Array(levelUp.unlocks.prefix(3))
        for (index, unlock) in shown.enumerated() {
            let more = index == shown.count - 1 ? levelUp.unlocks.count - shown.count : 0
            chips.append(LevelUpChip(
                id: 3 + index,
                label: more > 0 ? "\(unlock.label) · +\(more) more" : unlock.label,
                value: unlock.value, itemKey: nil, art: unlock.art, glyph: unlock.glyph
            ))
        }
        return chips
    }

    /// The level-up, on the deepened scrim: shafts of light standing over
    /// the middle, a gold bloom behind the word, LEVEL UP small and spaced,
    /// then LEVEL 8 in carved gold springing up out of itself on the
    /// fanfare's chord; under it what the level paid, and a row of what it
    /// opened. A tap goes on to the chest.
    private func levelUpAct(_ levelUp: PlayerLevelUp) -> some View {
        let chips = levelChips(levelUp)
        let paid = chips.filter { $0.id < 3 }
        let opened = chips.filter { $0.id >= 3 }
        // Under Reduce Motion the numerals fade in where they stand.
        let calm: Bool = Motion.isCalm
        let fromScale: Double = calm ? 1 : 0.35
        let fromRise: Double = calm ? 0 : 22
        return ZStack {
            LightShafts(shafts: Self.levelShafts)
                .ignoresSafeArea()
                .opacity(levelLanded ? 1 : 0)
                .animation(.easeOut(duration: 0.9), value: levelLanded)
            RadialGradient(
                colors: [Theme.gold.opacity(0.34), Theme.gold.opacity(0.1), Color.clear],
                center: .init(x: 0.5, y: 0.34), startRadius: 0, endRadius: 320
            )
            .blendMode(.plusLighter)
            .ignoresSafeArea()
            .opacity(levelLanded ? 1 : 0)
            .animation(.easeOut(duration: 0.6), value: levelLanded)
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer(minLength: 8)
                Text("LEVEL UP")
                    .font(Theme.body(13).weight(.black))
                    .tracking(5)
                    .foregroundStyle(Theme.onGlassEyebrow)
                    .opacity(levelLanded ? 1 : 0)
                    .animation(.easeOut(duration: 0.3), value: levelLanded)
                Text("LEVEL \(levelUp.level)")
                    .font(Theme.display(64))
                    .tracking(3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .carved()
                    .keyframeAnimator(initialValue: LevelNumeralFrame(), trigger: levelLanded) { content, frame in
                        content
                            .scaleEffect(frame.scale)
                            .opacity(frame.opacity)
                            .offset(y: frame.rise)
                    } keyframes: { _ in
                        KeyframeTrack(\.scale) {
                            MoveKeyframe(fromScale)
                            SpringKeyframe(1.0, duration: 0.6, spring: Motion.celebrateSpring.spring)
                        }
                        KeyframeTrack(\.opacity) {
                            MoveKeyframe(0)
                            LinearKeyframe(1, duration: 0.14)
                        }
                        KeyframeTrack(\.rise) {
                            MoveKeyframe(fromRise)
                            SpringKeyframe(0, duration: 0.5, spring: Motion.popSpring.spring)
                        }
                    }
                    .padding(.top, 2)
                if levelUp.levelsGained > 1 {
                    Text("\(levelUp.levelsGained) levels at once")
                        .font(Theme.body(12).weight(.bold))
                        .foregroundStyle(Theme.onGlassGold)
                        .opacity(levelLanded ? 1 : 0)
                        .animation(.easeOut(duration: 0.3).delay(0.3), value: levelLanded)
                }
                VStack(spacing: 8) {
                    levelChipRow(paid, from: 0)
                    if !opened.isEmpty {
                        levelChipRow(opened, from: paid.count)
                    }
                }
                .padding(.top, 16)
                Spacer(minLength: 6)
                Group {
                    if hasSpoils {
                        Text("TAP TO CLAIM YOUR SPOILS")
                            .font(Theme.body(11).weight(.black))
                            .tracking(2.2)
                            .foregroundStyle(Theme.gold)
                            .opacity(pulse ? 1 : 0.45)
                            .padding(.bottom, 14)
                    } else {
                        PrimaryButton(title: "Continue", action: onDismiss)
                            .frame(width: 220)
                            .padding(.bottom, 12)
                    }
                }
                .opacity(levelChipsShown >= chips.count ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: levelChipsShown)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { leaveLevelUp() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Level up: level \(levelUp.level)")
    }

    private func levelChipRow(_ chips: [LevelUpChip], from start: Int) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(chips.enumerated()), id: \.element.id) { offset, chip in
                levelChip(chip, shown: start + offset < levelChipsShown)
            }
        }
    }

    /// One chip on dark glass: the item, then its words over its number.
    private func levelChip(_ chip: LevelUpChip, shown: Bool) -> some View {
        let settled: Bool = shown || Motion.isCalm
        return HStack(spacing: 8) {
            Group {
                if let key = chip.itemKey {
                    ItemIcon(key: key, size: 26)
                } else if let art = chip.art, BundleImage.exists(art) {
                    BundleImage(name: art, renderedAt: 26)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 26, height: 26)
                } else {
                    Image(systemName: chip.glyph)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.onGlassGold)
                        .frame(width: 26, height: 26)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(chip.label)
                    .font(Theme.body(11).weight(.semibold))
                    .foregroundStyle(Theme.onGlassDim)
                    .lineLimit(1)
                Text(chip.value)
                    .font(Theme.numeric(15))
                    .foregroundStyle(Theme.onGlassGold)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 9)
        .padding(.trailing, 14)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.glass))
        .overlay(Capsule().strokeBorder(Theme.glassRim, lineWidth: 1))
        .fixedSize()
        .scaleEffect(settled ? 1 : 0.6)
        .offset(y: settled ? 0 : 10)
        .opacity(shown ? 1 : 0)
    }

    /// The level-up's light: three shafts standing over the middle of the
    /// frame, brighter than a hall's, where the word is.
    private static let levelShafts: [LightShaft] = [
        LightShaft(x: 0.36, width: 0.07, alpha: 0.2),
        LightShaft(x: 0.48, width: 0.11, alpha: 0.26),
        LightShaft(x: 0.62, width: 0.06, alpha: 0.18),
    ]

    // MARK: - Act two

    private var chestAct: some View {
        ZStack {
            // Rays behind the chest, additive, only once it is open. Half
            // the reveal's strength: there is a shelf of tiles to read here.
            AngularGradient(
                colors: [Theme.gold.opacity(0), Theme.gold.opacity(0.16), Theme.gold.opacity(0),
                         Theme.gold.opacity(0.16), Theme.gold.opacity(0), Theme.gold.opacity(0.16),
                         Theme.gold.opacity(0), Theme.gold.opacity(0.16), Theme.gold.opacity(0)],
                center: .center
            )
            .scaleEffect(2.2)
            .opacity(raysShown ? 1 : 0)
            .animation(.easeOut(duration: 0.8), value: raysShown)
            .rotationEffect(.degrees(rays))
            .blendMode(.plusLighter)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            RadialGradient(
                colors: [Theme.gold.opacity(lidOpen ? 0.34 : 0.08), Theme.gold.opacity(lidOpen ? 0.12 : 0.03), .clear],
                center: .init(x: 0.5, y: 0.62),
                startRadius: 0,
                endRadius: lidOpen ? 330 : 160
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.6), value: lidOpen)

            // The chest, centred, until the flash takes it; then the
            // spoils panel stands where it stood — the genre's reward box,
            // with the tiles popping in one by one and the way out inside
            // it. The shelf this replaces floated six pale tiles in the
            // empty middle of the screen once the chest had gone.
            if chestGone {
                SpoilsPanel(
                    title: summary.title,
                    stars: summary.stars,
                    isFirstClear: summary.isFirstClear,
                    grade: summary.raidGrade,
                    ribbonTitle: won ? "SPOILS OF VICTORY" : "SPOILS OF THE RAID",
                    loot: summary.loot,
                    shown: lootShown,
                    continueShown: continueShown,
                    tapAction: tapAction(for:),
                    onContinue: onDismiss
                )
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                VStack(spacing: 14) {
                    Spacer(minLength: 0)

                    RewardChestView(open: lidOpen, gone: chestGone)
                        .frame(width: 300, height: 170)
                        .contentShape(Rectangle())
                        .onTapGesture { openChest() }

                    Group {
                        if phase == .chest {
                            Text("TAP TO OPEN")
                                .font(Theme.body(11).weight(.black))
                                .tracking(2.2)
                                .foregroundStyle(Theme.gold)
                                .opacity(pulse ? 1 : 0.45)
                        } else {
                            Color.clear.frame(height: 1)
                        }
                    }
                    .frame(height: 44)

                    Spacer(minLength: 0)
                }
            }

            // The flash on the lid coming up. White over gold, gone in under
            // half a second.
            Color(hex: "#FFF3D0")
                .opacity(flash * 0.85)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .blendMode(.plusLighter)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if phase == .chest { openChest() } else if phase == .opened, !continueShown { finishOpeningNow() }
        }
        // The genre's rune-obtained card: a tap on a relic's tile shows it
        // large with Sell, Keep or Lock and keep, before the inventory.
        .sheet(item: $openedRelic) { relic in
            if let store {
                RelicDropCard(relicID: relic.id)
                    .environmentObject(store)
            }
        }
    }

    /// A relic's tile opens its card when there is a store to sell through;
    /// every other spoil is just shown.
    private func tapAction(for item: BattleSummary.Loot) -> (() -> Void)? {
        guard store != nil, let relic = item.relic else { return nil }
        return { openedRelic = relic }
    }

    // MARK: - Sequencing

    private func after(_ seconds: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func beginReckoning() {
        sequence += 1
        let mine = sequence
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        withAnimation(Motion.panel) { arrived = true }
        // A forfeit never reaches `.battleEnded`, so the music stops here too.
        AudioLibrary.shared.stopMusic(fade: 0.4)
        AudioLibrary.shared.play(won ? .victory : .defeat, volume: 0.9)
        Juice.haptic(won ? .heavy : .medium)

        // Stars that slammed in over the field stand lit (`litStars`); only
        // a reckoning with no beat before it ticks them in.
        let stars = won && !starsLanded ? summary.stars : 0
        for i in 0..<stars {
            after(0.45 + Double(i) * 0.18) {
                guard mine == sequence else { return }
                shownStars = i + 1
                AudioLibrary.shared.play(.starTick, volume: 0.8)
                Juice.haptic(i == stars - 1 ? .medium : .light)
            }
        }
        let rowStart = 0.45 + Double(stars) * 0.18 + 0.1
        for i in 0..<summary.unitStats.count {
            after(rowStart + Double(i) * 0.09) {
                guard mine == sequence else { return }
                rowsShown = i + 1
            }
        }
        if autoplay, hasSpoils || hasLevelUp {
            after(rowStart + Double(summary.unitStats.count) * 0.09 + 3.2) {
                guard mine == sequence else { return }
                if hasLevelUp {
                    // The tour's level-up (`-tour-victory field`): held for
                    // its frame, then the chest as below.
                    beginLevelUp()
                    let levelSequence = sequence
                    after(Self.tourLevelUpHold) {
                        guard levelSequence == sequence, hasSpoils else { return }
                        advanceToChest()
                        let chestSequence = sequence
                        after(2.2) {
                            guard chestSequence == sequence else { return }
                            openChest()
                        }
                    }
                    return
                }
                advanceToChest()
                // `advanceToChest()` has just bumped the sequence, so the
                // second step must guard on the NEW number: guarding on
                // `mine` here is what left the tour's chest shut.
                // Two seconds closed, so the tour photographs the chest
                // on its beat before the lid goes.
                let chestSequence = sequence
                after(2.2) {
                    guard chestSequence == sequence else { return }
                    openChest()
                }
            }
        }
    }

    /// The tap on the reckoning: the level-up when the fight raised one,
    /// the chest otherwise.
    private func leaveReckoning() {
        guard phase == .reckoning else { return }
        if hasLevelUp {
            beginLevelUp()
        } else {
            advanceToChest()
        }
    }

    /// The level-up (Docs/FEEL.md W1.6). The fanfare (`level_up.wav`) opens
    /// on a three-note pickup and lands its chord at 0.3 s; the numerals land
    /// WITH the chord, the shafts rise under them, and the chips follow a
    /// sixth of a second apart, each with its tick.
    private func beginLevelUp() {
        guard phase == .reckoning, let levelUp = summary.levelUp else { return }
        sequence += 1
        let mine = sequence
        levelBegan = Date()
        AudioLibrary.shared.play(.levelUp, volume: 0.95)
        withAnimation(.easeInOut(duration: 0.35)) { phase = .levelUp }
        if autoplay { print("[TourCue] levelup") }
        after(0.3) {
            guard mine == sequence else { return }
            levelLanded = true
            Juice.haptic(.heavy)
        }
        let chips = levelChips(levelUp).count
        for index in 0..<chips {
            after(1.0 + Double(index) * 0.16) {
                guard mine == sequence else { return }
                withAnimation(Motion.pop) { levelChipsShown = index + 1 }
                AudioLibrary.shared.play(.starTick, volume: 0.6)
                Juice.haptic(.light)
            }
        }
    }

    /// The tap on the level-up: on to the chest, once the level has had its
    /// second (`levelBegan`). Without spoils its own Continue is the way
    /// out, and a tap elsewhere does nothing.
    private func leaveLevelUp() {
        guard phase == .levelUp, hasSpoils,
              let began = levelBegan, Date().timeIntervalSince(began) >= 1.0 else { return }
        advanceToChest()
    }

    private func advanceToChest() {
        guard phase == .reckoning || phase == .levelUp else { return }
        sequence += 1
        AudioLibrary.shared.play(.uiConfirm, volume: 0.6)
        Juice.haptic(.light)
        withAnimation(.easeInOut(duration: 0.4)) { phase = .chest }
        withAnimation(.linear(duration: 22).repeatForever(autoreverses: false)) { rays = 360 }
    }

    private func openChest() {
        guard phase == .chest else { return }
        sequence += 1
        let mine = sequence
        phase = .opened
        Juice.haptic(.medium)
        // The chest shakes, the lid swings back and the light stands up out
        // of it (`RewardChestView`, about a second); then the flash, under
        // which the chest lifts away, and the spoils rise onto the shelf.
        lidOpen = true
        after(0.3) {
            guard mine == sequence else { return }
            AudioLibrary.shared.play(.summonBurst, volume: 0.9)
        }
        after(1.4) {
            guard mine == sequence else { return }
            Juice.haptic(.heavy)
            flash = 1
            withAnimation(.easeOut(duration: 0.5)) { flash = 0 }
            raysShown = true
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { chestGone = true }
        }

        let count = min(SpoilsPanel.capacity, summary.loot.count)
        for i in 0..<count {
            after(1.6 + Double(i) * 0.14) {
                guard mine == sequence else { return }
                lootShown = i + 1
                AudioLibrary.shared.play(.starTick, volume: 0.7)
                Juice.haptic(.light)
            }
        }
        after(1.6 + Double(count) * 0.14 + 0.35) {
            guard mine == sequence else { return }
            withAnimation(.easeOut(duration: 0.3)) { continueShown = true }
        }
    }

    /// A tap during the opening lands everything at once.
    private func finishOpeningNow() {
        sequence += 1
        lidOpen = true
        withAnimation(.easeOut(duration: 0.25)) { chestGone = true }
        raysShown = true
        flash = 0
        lootShown = min(SpoilsPanel.capacity, summary.loot.count)
        withAnimation(.easeOut(duration: 0.2)) { continueShown = true }
    }

    private var headline: String {
        switch summary.outcome {
        case .victory: return "VICTORY"
        case .defeat: return "DEFEAT"
        case .draw: return "DRAW"
        }
    }
}

/// The third act of a win, the genre's reward box: a framed panel with a
/// ribbon, the chest and the stars at its head, the spoils as a grid of
/// tiles with their counts printed on them, and the way out under them. The
/// owner, with Summoners War's box beside our shelf of six pale glyph tiles
/// on a gradient: "You see how nice this looks? Why does ours look so basic
/// and ugly?" The tiles are `RewardTile`, the same one every screen that
/// pays out now draws, so the painted icons land here the day they ship.
struct SpoilsPanel: View {
    let title: String
    let stars: Int
    let isFirstClear: Bool
    /// A raid's grade, stamped beside the stars. Nil everywhere else.
    var grade: RaidGrade? = nil
    /// The ribbon's words: a lost raid that still paid its aether is not a
    /// victory, and the ribbon must not say it was.
    var ribbonTitle: String = "SPOILS OF VICTORY"
    let loot: [BattleSummary.Loot]
    /// How many tiles have popped in so far.
    let shown: Int
    let continueShown: Bool
    var tapAction: (BattleSummary.Loot) -> (() -> Void)? = { _ in nil }
    let onContinue: () -> Void

    /// Two rows of six; a longer haul says how many more.
    static let capacity = 12

    private var items: [BattleSummary.Loot] { Array(loot.prefix(Self.capacity)) }
    /// Up to six in one row; more than six splits into two rows as even as
    /// they come.
    private var columns: Int { items.count <= 6 ? max(1, items.count) : min(6, (items.count + 1) / 2) }
    private var tileSize: CGFloat { columns >= 6 ? 58 : 64 }

    var body: some View {
        VStack(spacing: 10) {
            header
            grid
            Group {
                if continueShown {
                    PrimaryButton(title: "Continue", action: onContinue)
                        .frame(width: 220)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    Color.clear
                }
            }
            .frame(height: Theme.buttonHeight)
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 14)
        .frame(width: 600)
        .panelBackground()
        .overlay(alignment: .top) {
            ribbon.offset(y: -14)
        }
    }

    private var ribbon: some View {
        Text(ribbonTitle)
            .font(Theme.title(13))
            .tracking(2)
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 28)
            .padding(.vertical, 7)
            .background {
                if let ribbon = Chrome.slice("ui_ribbon", Chrome.ribbonInsets) {
                    ribbon
                } else {
                    Capsule().fill(Theme.gold)
                }
            }
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }

    /// The chest, the stage and its stars: what was won, and how well.
    private var header: some View {
        HStack(spacing: 12) {
            TributeChestImage(size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title.isEmpty ? "The spoils" : title)
                    .font(Theme.title(13))
                    .tracking(1)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(1...3, id: \.self) { index in
                        Image(systemName: "star.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(index <= stars ? Theme.gold : Theme.stroke)
                            .shadow(color: Theme.gold.opacity(index <= stars ? 0.6 : 0), radius: 4)
                    }
                    if isFirstClear {
                        Chip(text: "First clear", systemImage: "seal.fill", tint: Theme.verdigris, filled: true)
                            .padding(.leading, 6)
                    }
                }
            }
            if let grade {
                RaidGradeStamp(grade: grade, size: 36)
                    .padding(.leading, 4)
            }
            Spacer(minLength: 0)
            Text("\(loot.count) \(loot.count == 1 ? "spoil" : "spoils")")
                .font(Theme.body(10).weight(.bold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var grid: some View {
        let rows = stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
        return VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(row.enumerated()), id: \.element.id) { column, item in
                        let index = rowIndex * columns + column
                        RewardTile(
                            key: item.key ?? "",
                            title: item.title,
                            // A relic's tile prints no amount whatever the
                            // loot carries: its slot is the badge on the
                            // stone, never a count across its seal.
                            amount: item.relic == nil ? item.amount : nil,
                            stars: item.relic == nil ? item.stars : nil,
                            relic: item.relic,
                            size: tileSize,
                            onTap: tapAction(item)
                        )
                        .opacity(index < shown ? 1 : 0)
                        .scaleEffect(index < shown ? 1 : 0.4)
                        .animation(.spring(response: 0.4, dampingFraction: 0.62), value: shown)
                    }
                }
            }
            if loot.count > items.count {
                Text("+\(loot.count - items.count) more in the inventory")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// The reward chest: the Meshy-made box and lid — `prop_reward_chest` and
/// `prop_reward_chest_lid`, one 30-credit image-to-3D mesh from a Gemini
/// concept, cut in two by `tools/prop.py --split-lid` — on a small stage of
/// its own, transparent over the act's rays and glow.
///
/// Closed, it sits on its shadow, turns a few degrees either way so the gold
/// catches the light, and gives a hop every second or so: the tap prompt's
/// beat. Opened, it shakes, the lid swings back past open and settles on the
/// hinge the split left at its back edge, a pillar of gold light stands up
/// out of the box with sparks rising in it, and at the flash the chest lifts
/// and fades and the spoils are what is left. The owner, with the drawn
/// marble strongbox on his phone: "That chest SUCKS. Maybe get a 3D model?
/// Where it opens and then flashes and goes away and shows the reward (like
/// summoners war)."
struct RewardChestView: UIViewRepresentable {
    var open: Bool
    var gone: Bool

    /// Where the split put the lid's origin: the middle of its back-bottom
    /// edge, in metres of a 1 m chest. `prop.py` prints it as it ships; a
    /// lid hinged anywhere else swings through the box or floats.
    private static let hinge = SCNVector3(0, 0.617, -0.433)

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var scene: SCNScene?
        let chest = SCNNode()
        var lid: SCNNode?
        var opened = false
        var vanished = false
        /// The view, held at alpha 0 until SceneKit has drawn it once.
        weak var view: SCNView?
        /// The render thread's: the first frame has been drawn.
        private var drewFirstFrame = false
        /// The main thread's: the view has been faded in.
        private var revealed = false

        /// The first frame is on the screen: fade the view in over it. A
        /// transparent HDR view shows nothing of its own until then, and a
        /// view that is visible before its first frame is whatever the
        /// compositor had — never a white slab in front of the chest.
        func renderer(_ renderer: SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
            guard !drewFirstFrame else { return }
            drewFirstFrame = true
            DispatchQueue.main.async { [weak self] in self?.reveal() }
        }

        /// Fades the view in, once — on its first frame, or from a half-second
        /// fallback so a callback that never comes cannot hide the chest.
        func reveal() {
            guard !revealed else { return }
            revealed = true
            DispatchQueue.main.async { [weak self] in
                guard let view = self?.view else { return }
                UIView.animate(withDuration: 0.22) { view.alpha = 1 }
            }
        }

        /// The opening's light, sized for THIS frame — half a second into the
        /// opening, built on the main thread. The chest used to borrow the
        /// reveal's beam and the light element's hit: the beam is a 14 m
        /// column for a stage seen from eight metres, which ran out of the
        /// top of this 300-point view and was cut flat by its edge, and the
        /// hit throws the painted ring, whose sprite is an opaque WHITE
        /// square (`vfx_ring.png` was painted on white), grown to 3.5 m —
        /// wider than this whole frame at the chest, which is about 3.1 m by
        /// 1.8. Run 217 photographed the chest standing in a pure white
        /// rectangle over the dark victory ground. Everything here stays
        /// inside the frame, fades before it reaches an edge and ADDS light
        /// without writing alpha (the transparent view's rule, written down
        /// in `SummonRevealView`).
        func burst() {
            let gold = UIColor(hex: "#FFD36A") ?? .yellow
            let warm = gold.mixed(with: .white, amount: 0.45)

            // The pillar: a sheet facing the lens, brightest at the chest's
            // mouth and gone by 1.35 m — the frame's top edge is 1.45 m up
            // at the chest.
            let pillar = SCNPlane(width: 0.95, height: 0.95)
            pillar.firstMaterial = lightMaterial(ChestLight.pillar, tint: warm)
            let pillarNode = SCNNode(geometry: pillar)
            pillarNode.position = SCNVector3(0, 0.875, 0.02)
            pillarNode.opacity = 0
            pillarNode.scale = SCNVector3(0.15, 1, 1)
            chest.addChildNode(pillarNode)
            let rise = SCNAction.group([
                .fadeIn(duration: 0.28),
                .customAction(duration: 0.28) { node, elapsed in
                    let t = Float(min(1, elapsed / 0.28))
                    node.scale = SCNVector3(0.15 + 0.85 * t, 1, 1)
                },
            ])
            pillarNode.runAction(.sequence([rise, .wait(duration: 0.5), .fadeOut(duration: 0.6), .removeFromParentNode()]))

            // The flare at the mouth: the painted four-point star (a real
            // alpha channel), 0.8 m growing to 1.2 m and gone in half a
            // second.
            if let flareImage = VFXLibrary.sprite("flare") {
                let flare = SCNPlane(width: 0.8, height: 0.8)
                flare.firstMaterial = lightMaterial(flareImage, tint: warm)
                let flareNode = SCNNode(geometry: flare)
                flareNode.position = SCNVector3(0, 0.72, 0.18)
                chest.addChildNode(flareNode)
                let bloom = SCNAction.scale(to: 1.5, duration: 0.5)
                bloom.timingMode = .easeOut
                flareNode.runAction(.sequence([
                    .group([bloom, .sequence([.wait(duration: 0.15), .fadeOut(duration: 0.35)])]),
                    .removeFromParentNode(),
                ]))
            }

            // Sparks rising out of the box, gone before the frame's top.
            let sparks = SCNParticleSystem()
            sparks.loops = false
            sparks.birthRate = 110
            sparks.emissionDuration = 0.5
            sparks.birthLocation = .volume
            sparks.emitterShape = SCNBox(width: 0.7, height: 0.02, length: 0.35, chamferRadius: 0)
            sparks.particleImage = VFXLibrary.sprite("flare") ?? UIImage(named: "spark")
            sparks.particleColor = warm
            sparks.particleSize = 0.05
            sparks.particleSizeVariation = 0.025
            sparks.particleLifeSpan = 0.75
            sparks.particleLifeSpanVariation = 0.15
            sparks.particleVelocity = 0.6
            sparks.particleVelocityVariation = 0.2
            sparks.emittingDirection = SCNVector3(0, 1, 0)
            sparks.spreadingAngle = 18
            sparks.acceleration = SCNVector3(0, 0.2, 0)
            sparks.isAffectedByGravity = false
            sparks.blendMode = .additive
            sparks.isLightingEnabled = false
            sparks.orientationMode = .billboardScreenAligned
            let fade = CAKeyframeAnimation()
            fade.values = [0, 1, 1, 0] as [NSNumber]
            fade.keyTimes = [0, 0.15, 0.6, 1] as [NSNumber]
            sparks.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
            let sparkHost = SCNNode()
            sparkHost.position = SCNVector3(0, 0.55, 0)
            sparkHost.addParticleSystem(sparks)
            chest.addChildNode(sparkHost)
            // Through `VFXLibrary.retire`, as every node that carries a
            // particle system leaves a scene: on the main thread, never a
            // removal action on the render thread.
            sparkHost.name = "vfx_chest_sparks"
            VFXLibrary.retire(sparkHost, after: 2.5)

            // And the gold the box throws on its own lid and rim: a small
            // lamp in its mouth, reaching a metre and a half.
            let lamp = SCNLight()
            lamp.type = .omni
            lamp.color = gold
            lamp.intensity = 0
            lamp.attenuationStartDistance = 0.3
            lamp.attenuationEndDistance = 1.5
            let lampNode = SCNNode()
            lampNode.light = lamp
            lampNode.position = SCNVector3(0, 0.75, 0.1)
            chest.addChildNode(lampNode)
            lampNode.runAction(.sequence([
                .customAction(duration: 1.1) { node, elapsed in
                    let t = CGFloat(min(1, elapsed / 1.1))
                    node.light?.intensity = 1_300 * (t < 0.2 ? t / 0.2 : (1 - t) / 0.8)
                },
                .removeFromParentNode(),
            ]))
        }

        /// A sheet of light: constant, added to what is behind it, never
        /// written to depth or to the alpha channel.
        private func lightMaterial(_ image: UIImage, tint: UIColor) -> SCNMaterial {
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = image
            material.multiply.contents = tint
            material.blendMode = .add
            material.writesToDepthBuffer = false
            material.colorBufferWriteMask = [.red, .green, .blue]
            material.isDoubleSided = true
            return material
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        // Transparent, like the reveal's stage: the rays and the gold glow
        // behind this view are the light the chest sits in. Said three
        // times over — the scene's own background, the view's colour and
        // its opacity — because a transparent HDR view that falls back to
        // any one default is a slab in front of the act (run 217).
        scene.background.contents = UIColor.clear
        view.scene = scene
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = false
        view.rendersContinuously = true
        // The tap belongs to SwiftUI.
        view.isUserInteractionEnabled = false

        let coordinator = context.coordinator
        coordinator.scene = scene
        // Held invisible until SceneKit has drawn it once, then faded in by
        // the coordinator's `didRenderScene`, with a fallback in case that
        // callback never comes.
        view.alpha = 0
        coordinator.view = view
        view.delegate = coordinator
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak coordinator] in
            coordinator?.reveal()
        }
        let chest = coordinator.chest
        chest.addChildNode(StageBuilder.loadProp("prop_reward_chest") ?? Self.standInBox())
        let lid = SCNNode()
        lid.position = Self.hinge
        lid.addChildNode(StageBuilder.loadProp("prop_reward_chest_lid") ?? Self.standInLid())
        chest.addChildNode(lid)
        // The split leaves both halves open shells, and an open lid shows the
        // camera its inside — back faces, culled, a ghost outline in the
        // first frames. Both sides drawn: the lid has an inside, the box has
        // a floor and walls to look into.
        chest.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] { material.isDoubleSided = true }
        }
        coordinator.lid = lid
        scene.rootNode.addChildNode(chest)

        // The shadow under it, the reveal's own image.
        let shadow = SCNPlane(width: 2.1, height: 1.4)
        let shadowMaterial = SCNMaterial()
        shadowMaterial.lightingModel = .constant
        shadowMaterial.diffuse.contents = SummonStageView.contactShadowImage
        shadowMaterial.writesToDepthBuffer = false
        shadow.firstMaterial = shadowMaterial
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        shadowNode.position = SCNVector3(0, 0.004, 0)
        shadowNode.opacity = 0.7
        scene.rootNode.addChildNode(shadowNode)

        // A 28° lens from in front and a little above, aimed at the lock:
        // the closed chest stands about two thirds of the frame's height,
        // and the lid has room to swing up.
        let camera = SCNCamera()
        camera.fieldOfView = 28
        camera.projectionDirection = .vertical
        camera.zNear = 0.2
        camera.zFar = 60
        camera.wantsHDR = true
        // THE SHOULDER (2026-09-17, evening): `whitePoint` at SceneKit's
        // default 1.0 clips every lit surface at or over 1.0 flat to paper —
        // the battle learned it on 2026-09-15 (BattleSceneController) and
        // this camera never got it, which is half of why the owner's awakened
        // Ares photographed as a pale smear on the reveal. Same number as the
        // battle's so the figure looks the same on every stage.
        camera.whitePoint = 1.85
        camera.wantsExposureAdaptation = false
        camera.bloomIntensity = 0.42
        camera.bloomThreshold = 0.9
        camera.bloomBlurRadius = 14
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 1.45, 3.4)
        cameraNode.look(at: SCNVector3(0, 0.6, 0))
        scene.rootNode.addChildNode(cameraNode)

        // Key from the front-left, warm; a cool fill from the right; a gold
        // rim from behind for the edge of the lid; an ambient floor.
        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        key.color = UIColor(hex: "#FFF1D6") ?? .white
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.75, -0.55, 0)
        scene.rootNode.addChildNode(keyNode)
        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 320
        fill.color = UIColor(hex: "#8FA3D9") ?? .white
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-0.4, 0.8, 0)
        scene.rootNode.addChildNode(fillNode)
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 560
        rim.color = UIColor(hex: "#FFD36A") ?? .yellow
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(-0.5, 2.7, 0)
        scene.rootNode.addChildNode(rimNode)
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 210
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // The idle: a hop on the prompt's beat, and a slow turn either way.
        let hop = SCNAction.sequence([
            .wait(duration: 1.1),
            .moveBy(x: 0, y: 0.05, z: 0, duration: 0.09),
            .moveBy(x: 0, y: -0.05, z: 0, duration: 0.14),
        ])
        chest.runAction(.repeatForever(hop), forKey: "hop")
        let swayRight = SCNAction.rotateTo(x: 0, y: 0.2, z: 0, duration: 2.8, usesShortestUnitArc: true)
        swayRight.timingMode = .easeInEaseOut
        let swayLeft = SCNAction.rotateTo(x: 0, y: -0.2, z: 0, duration: 2.8, usesShortestUnitArc: true)
        swayLeft.timingMode = .easeInEaseOut
        chest.eulerAngles.y = -0.2
        chest.runAction(.repeatForever(.sequence([swayRight, swayLeft])), forKey: "sway")

        if open { openSequence(coordinator) }
        if gone { vanish(coordinator) }
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        if open, !coordinator.opened { openSequence(coordinator) }
        if gone, !coordinator.vanished { vanish(coordinator) }
    }

    /// The shake, the lid, the light. About a second; the flash follows.
    private func openSequence(_ coordinator: Coordinator) {
        guard !coordinator.opened, let lid = coordinator.lid else { return }
        coordinator.opened = true
        let chest = coordinator.chest
        chest.removeAction(forKey: "hop")
        chest.removeAction(forKey: "sway")
        let square = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.15, usesShortestUnitArc: true)
        square.timingMode = .easeOut
        chest.runAction(square)

        // Four quick jolts, a third of a second.
        var jolts: [SCNAction] = []
        for index in 0..<4 {
            let dx: CGFloat = index % 2 == 0 ? 0.06 : -0.06
            jolts.append(.moveBy(x: dx, y: 0.02, z: 0, duration: 0.04))
            jolts.append(.moveBy(x: -dx, y: -0.02, z: 0, duration: 0.04))
        }
        chest.runAction(.sequence(jolts), forKey: "shake")

        // The lid swings back past open and settles. Its origin is its back
        // edge, so a negative turn about X is what lifts the front.
        let swing = SCNAction.rotateTo(x: -2.05, y: 0, z: 0, duration: 0.32, usesShortestUnitArc: false)
        swing.timingMode = .easeOut
        let settle = SCNAction.rotateTo(x: -1.85, y: 0, z: 0, duration: 0.2, usesShortestUnitArc: false)
        settle.timingMode = .easeInEaseOut
        lid.runAction(.sequence([.wait(duration: 0.32), swing, settle]))

        // The light standing up out of the box, and a flare at its mouth —
        // this frame's own (the coordinator's `burst()`), built on the main
        // thread half a second in, not in an action's block on the render
        // thread.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak coordinator] in
            coordinator?.burst()
        }
    }

    /// Lifts and fades under the flash; the spoils on the shelf are what stay.
    private func vanish(_ coordinator: Coordinator) {
        guard !coordinator.vanished else { return }
        coordinator.vanished = true
        let chest = coordinator.chest
        let away = SCNAction.group([
            .fadeOut(duration: 0.32),
            .moveBy(x: 0, y: 0.5, z: 0, duration: 0.32),
            .scale(to: 1.12, duration: 0.32),
        ])
        away.timingMode = .easeIn
        chest.runAction(away)
    }

    /// A box of wood banded in gold for a bundle without the mesh, at the
    /// mesh's own size, so the sequence plays either way.
    private static func standInBox() -> SCNNode {
        let node = SCNNode()
        let box = SCNBox(width: 1.35, height: 0.62, length: 0.86, chamferRadius: 0.03)
        box.firstMaterial?.diffuse.contents = UIColor(hex: "#5A3A22") ?? .brown
        let boxNode = SCNNode(geometry: box)
        boxNode.position = SCNVector3(0, 0.31, 0)
        node.addChildNode(boxNode)
        for x in [-0.42, 0.42] as [CGFloat] {
            let band = SCNBox(width: 0.14, height: 0.64, length: 0.88, chamferRadius: 0.01)
            band.firstMaterial?.diffuse.contents = UIColor(hex: "#D9A93C") ?? .yellow
            let bandNode = SCNNode(geometry: band)
            bandNode.position = SCNVector3(Float(x), 0.31, 0)
            node.addChildNode(bandNode)
        }
        return node
    }

    /// The chest's scene goes when the view leaves, in the order the summon
    /// reveal's does (`SummonStageView.dismantleUIView`): the renderer
    /// stopped first, the particle hosts dismissed the way an effect leaves
    /// the stage, every action stopped, and only half a second later the
    /// nodes removed and the scene let go. A representable with no teardown
    /// keeps its scene for as long as SwiftUI keeps the view: the reveal's
    /// did, and CI run 242's summon stress climbed 30 MB a reveal to 1.4 GB
    /// (2026-09-24).
    static func dismantleUIView(_ uiView: SCNView, coordinator: Coordinator) {
        uiView.isPlaying = false
        uiView.rendersContinuously = false
        uiView.delegate = nil
        guard let root = uiView.scene?.rootNode else {
            coordinator.scene = nil
            coordinator.lid = nil
            return
        }
        for child in root.childNodes {
            var carries = false
            child.enumerateHierarchy { node, stop in
                if let systems = node.particleSystems, !systems.isEmpty {
                    carries = true
                    stop.pointee = true
                }
            }
            if carries { VFXLibrary.dismiss(child, reportsLive: false) }
        }
        root.enumerateHierarchy { node, _ in
            node.removeAllActions()
            node.removeAllAnimations()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            for child in root.childNodes {
                child.removeFromParentNode()
            }
            uiView.scene = nil
            coordinator.scene = nil
            coordinator.lid = nil
        }
    }

    private static func standInLid() -> SCNNode {
        let lid = SCNBox(width: 1.35, height: 0.36, length: 0.86, chamferRadius: 0.1)
        lid.firstMaterial?.diffuse.contents = UIColor(hex: "#D9A93C") ?? .yellow
        let node = SCNNode(geometry: lid)
        // Relative to the hinge at the back-bottom edge.
        node.position = SCNVector3(0, 0.18, 0.43)
        return node
    }
}

/// The reward chest's pillar of light, drawn once: white at the core and
/// soft at the sides, full at the bottom and nothing at the top, so the
/// sheet the chest's `burst()` stands up out of the box never shows an
/// edge. Tinted gold by the material.
private enum ChestLight {
    static let pillar: UIImage = {
        let size = CGSize(width: 64, height: 256)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            let space = CGColorSpaceCreateDeviceRGB()
            let across = [
                UIColor(white: 1, alpha: 0).cgColor,
                UIColor(white: 1, alpha: 0.35).cgColor,
                UIColor(white: 1, alpha: 1).cgColor,
                UIColor(white: 1, alpha: 0.35).cgColor,
                UIColor(white: 1, alpha: 0).cgColor,
            ]
            let acrossStops: [CGFloat] = [0, 0.28, 0.5, 0.72, 1]
            if let gradient = CGGradient(colorsSpace: space, colors: across as CFArray, locations: acrossStops) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: 0), options: [])
            }
            // Keep what is drawn, faded from the foot (y = height in UIKit's
            // flipped context) to nothing at the top.
            cg.setBlendMode(.destinationIn)
            let up = [
                UIColor(white: 1, alpha: 1).cgColor,
                UIColor(white: 1, alpha: 0.5).cgColor,
                UIColor(white: 1, alpha: 0).cgColor,
            ]
            let upStops: [CGFloat] = [0, 0.5, 1]
            if let fade = CGGradient(colorsSpace: space, colors: up as CFArray, locations: upStops) {
                cg.drawLinearGradient(fade, start: CGPoint(x: 0, y: size.height), end: .zero, options: [])
            }
        }
    }()
}
