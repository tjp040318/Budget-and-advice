#if DEBUG
import Combine
import SceneKit
import SwiftUI

/// A self-driving pass through the app's screens, for a machine with no
/// fingers.
///
/// The CI job builds the app on a macOS runner, launches it in a simulator
/// with `-tour`, and takes a screenshot every few seconds. This view is what
/// it launches into: each screen in turn, held for a few ticks, with a caption
/// in the corner so a sheet of frames reads without a key. The battle runs on
/// auto for a while so the models are caught fighting, not standing. Nothing
/// here ships: the whole file is debug-only and the switch is one launch
/// argument in `PantheonApp`.
struct TourView: View {
    @EnvironmentObject private var store: GameStore

    @State private var index = TourView.pinnedStep ?? 0
    @State private var ticksOnStep = 0
    @State private var battleModel: BattleViewModel?
    @State private var realmModel: BattleViewModel?
    @State private var arenaModel: BattleViewModel?
    @State private var dungeonModel: BattleViewModel?
    /// The victory step's real fight (`-tour-victory field`).
    @State private var victoryModel: BattleViewModel?
    @State private var seeded = false
    /// Ticks since the step appeared, for its `[Mem]` curve. Not `@State`:
    /// a state change re-renders the tour every tick, and several steps
    /// build their screen's data in `body` (the victory's summary, the launch
    /// screen's progress), which a pinned step never re-rendered before.
    private static var memoryTicks = 0

    /// `-tour-step N` pins the tour to one screen for the whole run. The CI
    /// job launches the app once per step and photographs it, because a
    /// timer-driven tour raced the simulator's first, slow screenshot and
    /// every frame came out of the last screen.
    static var pinnedStep: Int? {
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-tour-step"), at + 1 < args.count,
              let step = Int(args[at + 1]) else { return nil }
        return min(max(0, step), schedule.count - 1)
    }

    /// One entry per screen: what to show and how many ticks to hold it.
    private static let schedule: [(name: String, ticks: Int)] = [
        ("island", 2), ("collection", 2), ("detail", 2), ("training", 2),
        ("summon", 2), ("reveal", 3), ("battle", 8), ("arena", 2), ("arena_battle", 6), ("more", 2),
        ("halls", 2), ("relics", 2), ("shop", 2), ("chapter_map", 2), ("missions", 2),
        ("labyrinth", 2), ("dungeon", 2), ("relic_picker", 2), ("dungeon_battle", 6), ("relic_powerup", 2),
        ("victory", 4), ("collection_stage", 2), ("relic_drop", 2), ("relic_filter", 2), ("launch", 2),
        ("relic_sets", 2), ("tribute", 2), ("stage_popup", 2), ("chapter_maps", 2), ("realm_battle", 6),
        ("guide", 2), ("lessons", 2), ("night_market", 2), ("counsel", 2),
        ("sweep", 3), ("mileage", 2), ("selector", 2), ("relic_roll", 2),
        ("raid_grade", 4), ("raids", 2), ("relic_awaken", 3), ("boons", 2), ("resonance", 2),
        ("awaken", 2), ("island_decor", 2), ("events", 2), ("regalia", 2), ("demigods", 2),
        ("sign_in", 2), ("codex", 2), ("draft", 3), ("shrines", 2),
        ("treasury", 2), ("stress", 2),
    ]

    /// `-tour-chapter K` picks which chapter the `chapter_maps` step opens;
    /// the CI job relaunches that step once per chapter so every painted
    /// map is photographed.
    static var pinnedChapter: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-tour-chapter"), at + 1 < args.count,
              let chapter = Int(args[at + 1]) else { return 0 }
        return min(max(0, chapter), StageDatabase.chapters.count - 1)
    }

    /// `-tour-environment <rawValue>` picks the set the `realm_battle` step
    /// fights on; the CI job relaunches that step once per realm so every
    /// dressed set is photographed, not only Egypt's three the other battle
    /// steps happen to use.
    static var pinnedEnvironment: BattleEnvironment? {
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-tour-environment"), at + 1 < args.count else { return nil }
        return BattleEnvironment(rawValue: args[at + 1])
    }

    /// `-tour-island-zoom Z` opens the island's camera zoomed onto the
    /// summoning circle; the CI job relaunches step 0 with it so the
    /// diorama is photographed close as well as at rest.
    static var pinnedIslandZoom: CGFloat? {
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-tour-island-zoom"), at + 1 < args.count,
              let zoom = Double(args[at + 1]) else { return nil }
        return CGFloat(zoom)
    }

    /// The word after `flag` on the launch line, or nil when the flag is
    /// absent or last. Every relaunch argument below that takes a word is
    /// read through it: phase B (2026-09-22) added sixteen, and sixteen
    /// copies of the same four lines were sixteen places to get the bounds
    /// check wrong.
    private static func argument(after flag: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: flag), at + 1 < args.count else { return nil }
        return args[at + 1]
    }

    /// `-tour-dungeon <chapterID>` opens the `halls` or `dungeon` step on
    /// another room: the CI job relaunches the Halls on Radiance (Olympus,
    /// the brightest painting, where glass is hardest to read) and Umbra
    /// (the Serpent Deep, the darkest), and the dungeon on the Necropolis.
    static var pinnedDungeon: String? { argument(after: "-tour-dungeon") }

    /// `-tour-dungeon-floor N` opens that room on floor N rather than the
    /// player's current one: B1 for the mastered floor's Sweep deck, B10
    /// for the locked floor with the tallest drops plate — the height test.
    static var pinnedDungeonFloor: Int? { argument(after: "-tour-dungeon-floor").flatMap { Int($0) } }

    /// `-tour-dungeon-sweep` opens the focused floor's sweep choices (the
    /// run count, the energy it costs), over a mastered floor.
    static var pinnedDungeonSweep: Bool { ProcessInfo.processInfo.arguments.contains("-tour-dungeon-sweep") }
    /// The battle step's skill panel (`BattleView.showTourSkillPanel`): the
    /// fight waits on its first turn instead of taking a command a tick.
    static var pinnedSkillInfo: Bool { ProcessInfo.processInfo.arguments.contains("-tour-skill-info") }

    /// `-tour-victory field` fights the victory step's win for real
    /// (Docs/FEEL.md W1.6, W1.7): the Duat's first gate on auto at the top
    /// speed, the demigod seeded one experience short of his next level and
    /// the team's leader one short of hers, so the CI job photographs
    /// VICTORY stamped over the live field (`20-victory-0`), the survivors
    /// posing to the camera with their EXP bars filled and LEVEL UP over the
    /// leader (`20-victory-triumph`), and the level-up between the reckoning
    /// and the chest (`20-victory-levelup`). The battle screen holds the beat
    /// and prints `[TourCue] triumph` and `[TourCue] levelup` for the job's
    /// clock. `-tour-victory defeat` is the same gate fought by nobody and
    /// forfeited seven seconds in — the one loss a tour can play for certain —
    /// for DEFEAT in wine over the drained field (`20-victory-defeat`,
    /// `[TourCue] fallen`). The plain step keeps the demo's reckoning, chest
    /// and spoils.
    static var pinnedVictory: String? { argument(after: "-tour-victory") }
    static var pinnedVictoryField: Bool { pinnedVictory == "field" || pinnedVictory == "defeat" }

    /// `-tour-labyrinth-wing halls|tower|raids` opens the building on that
    /// wing. Neither the Halls wing nor the Tower had ever been photographed
    /// before phase B; the Tower is newly on glass.
    static var pinnedLabyrinthWing: LabyrinthView.Wing {
        switch argument(after: "-tour-labyrinth-wing") ?? "" {
        case "halls": return .halls
        case "tower": return .tower
        case "raids": return .raids
        default: return .dungeons
        }
    }

    /// `-tour-raid <raid id>` opens the Titans on that Titan: the Unwrapped
    /// King has the longest name, the one the rail's third line is for, and
    /// sits low enough that the rail must scroll to him.
    static var pinnedRaid: String? { argument(after: "-tour-raid") }

    /// `-tour-training feed|evolve|fuse` opens the Hall of Ka on that ledger:
    /// the offering Auto chose (the ghost gauge, the cost, the veils), the
    /// evolution, and the fusion board with its prize on the altar. Only
    /// Power up with nothing offered and Awaken had been photographed.
    static var pinnedTraining: String? { argument(after: "-tour-training") }

    /// `-tour-popup-stage <stageID>` opens the stage card on another stage
    /// of the Duat: the fifth, for the BOSS eyebrow and the boss's face.
    static var pinnedPopupStage: String? { argument(after: "-tour-popup-stage") }

    /// `-tour-chapter-scroll` (no value) opens the chapter map with its
    /// scroll unrolled: the story, the yields and the terms.
    static var pinnedChapterScroll: Bool { ProcessInfo.processInfo.arguments.contains("-tour-chapter-scroll") }

    /// `-tour-tier hard|hell` opens the Duat's map on that tier, on the
    /// walked copy (`CampaignView.tourWalk`), which has the easier tiers
    /// cleared so the tier is open: the tier well's gold plate and seals,
    /// Hell's grade and motes, and the scroll opening on its terms.
    static var pinnedTier: CampaignDifficulty? {
        argument(after: "-tour-tier").flatMap { CampaignDifficulty(rawValue: $0.lowercased()) }
    }

    /// `-tour-briefing <stageID>` shows that stage's briefing ALONE, as the
    /// sheet it is: nothing photographed the briefing except under the
    /// sweep's receipt, a screen the game never draws (2026-09-22).
    static var pinnedBriefing: String? { argument(after: "-tour-briefing") }

    /// `-tour-shop-stall scrolls|laurel|night…` opens the bazaar on the stall
    /// whose name begins with the word: the Scrolls stall is the densest
    /// shelf, and the Laurel exchange sits below the rail's fold, so the
    /// frame proves the rail opens scrolled to it.
    static var pinnedShopStall: ShopService.Section? {
        guard let word = argument(after: "-tour-shop-stall")?.lowercased() else { return nil }
        return ShopService.visibleSections.first { $0.rawValue.lowercased().hasPrefix(word) }
    }

    /// `-tour-missions-tab daily|counsel|feats` opens the Missions on that
    /// list; the Feats are twenty-eight rows with the claimable ones first.
    static var pinnedMissionsTab: MissionsView.Tab? {
        switch argument(after: "-tour-missions-tab")?.lowercased() ?? "" {
        case "daily": return .missions
        case "counsel": return .counsel
        case "feats": return .feats
        default: return nil
        }
    }

    /// `-tour-events-week plain` moves the events step a week on from the
    /// Festival Monday, so the ordinary week's band is photographed as well:
    /// every frame till now was the Festival's.
    static var pinnedPlainWeek: Bool { argument(after: "-tour-events-week") == "plain" }

    /// `-tour-guide caret` shows Athena's caret on the Collection tab instead
    /// of her plate — the proof that a door in the tab bar, laid out under
    /// the screen, reaches an overlay drawn above both.
    static var pinnedGuideCaret: Bool { argument(after: "-tour-guide") == "caret" }

    /// `-tour-root summon` shows the app's own shell (`RootView`) on the
    /// Summon tab instead of the tour's `tabbed` copy: the phone lays the
    /// tab bar out under a TabView of NavigationStacks, and no frame had
    /// ever photographed that path (run 216's judges inferred it).
    static var pinnedRoot: RootView.Tab? {
        switch argument(after: "-tour-root") ?? "" {
        case "island": return .island
        case "campaign": return .campaign
        case "arena": return .arena
        case "summon": return .summon
        case "collection": return .collection
        default: return nil
        }
    }

    /// `-tour-more diagnostics` shows the debug build's Diagnostics desk, the
    /// place the model board and the console went when they left More's
    /// front page (2026-09-22, phase B).
    static var pinnedMoreDiagnostics: Bool { argument(after: "-tour-more") == "diagnostics" }

    /// `-tour-more notifications|graphics|delete` opens More on one of its
    /// pages or on the account-deletion sheet (2026-09-23, Docs/SETTINGS.md),
    /// so the CI job photographs what the settings build added.
    static var pinnedMoreOpening: SettingsOpening {
        switch argument(after: "-tour-more") ?? "" {
        case "notifications": return .notifications
        case "graphics": return .graphics
        case "delete": return .deleteAccount
        default: return .boards
        }
    }

    /// `-tour-codex-page <blueprint id>` opens the Codex on that form's page;
    /// `-tour-codex-awakened` on the awakened faces (Docs/CODEX.md).
    static var pinnedCodexPage: String? { argument(after: "-tour-codex-page") }
    static var pinnedCodexAwakened: Bool { ProcessInfo.processInfo.arguments.contains("-tour-codex-awakened") }

    /// `-tour-selector-pick first` puts the first candidate on the opening
    /// gift's counter, so the gold TAKE and the lit tile are in one frame.
    static var pinnedSelectorPick: Bool { argument(after: "-tour-selector-pick") == "first" }

    /// `-tour-mileage-pick dearest` puts the head of the Duat's catalogue —
    /// the dearest 5★, 153 points against the save's 118 — on the counter:
    /// the rose price and the dim "35 MORE".
    static var pinnedMileagePick: Bool { argument(after: "-tour-mileage-pick") == "dearest" }

    /// `-tour-detail awakened` opens the unit sheet on the seed's awakened
    /// unit, whose regalia is at III: the unlocked regalia plate and the
    /// awakening line, where the Zeus frame shows the regalia locked.
    static var pinnedDetailAwakened: Bool { argument(after: "-tour-detail") == "awakened" }

    /// `-tour-relic legend` opens the relic inventory with a worn four-sub
    /// Legend of a four-piece set picked: the fullest panel an ordinary 6★
    /// relic asks for, where run 221's set line was cut above OPEN. The
    /// plain frame keeps whichever relic the tour's rolls happen to pick.
    static var pinnedRelicPick: String? { argument(after: "-tour-relic") }

    /// Seconds per tick. The runner screenshots on the same period, so every
    /// step is caught at least once.
    static let tickSeconds: TimeInterval = 4

    private let timer = Timer.publish(every: TourView.tickSeconds, on: .main, in: .common).autoconnect()

    private var current: String { Self.schedule[min(index, Self.schedule.count - 1)].name }

    var body: some View {
        // The chip stands on its side in the LEFT safe-area inset — the
        // 59 points beside the Dynamic Island where no screen draws — at
        // the bottom, below the cutout. Everywhere else it has stood it
        // covered something being judged: the ISLAND tab (run 207), the
        // island's header card (209), More's first tile and the summon
        // rail's label (210). `offset` moves the drawing only, so the
        // screen's own layout is untouched.
        GeometryReader { geometry in
            let inset = geometry.safeAreaInsets.leading
            ZStack(alignment: .bottomLeading) {
                content
                    .id(index)
                Text("\(index + 1)/\(Self.schedule.count) \(current)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.7), in: Capsule())
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
                    .frame(width: 20, height: 120)
                    .offset(x: inset > 24 ? -inset + 8 : 4, y: -8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .preferredColorScheme(.light)
        .onAppear {
            seedIfNeeded()
            // The memory curve of every step (2026-09-24): as it appears, and
            // every twelve seconds after (the timer below), so a step that
            // climbs — a battle's waves, a reveal's figures — shows it in its
            // console. `-tour-step` launches the app per step, so each line is
            // one launch's own.
            let label = "step \(index) \(current)"
            MemoryProbe.log("\(label) appeared")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { MemoryProbe.log("\(label) settled") }
            if current == "battle" { startBattle() }
            if current == "arena_battle" { startArenaBattle() }
            if current == "dungeon_battle" { startDungeonBattle() }
            if current == "realm_battle" { startRealmBattle() }
            if current == "victory", Self.pinnedVictoryField { startVictoryField() }
        }
        .onReceive(timer) { _ in
            if Self.pinnedStep == nil { tick() }
            Self.memoryTicks += 1
            if Self.memoryTicks % 3 == 0 {
                MemoryProbe.log("step \(index) \(current) +\(Int(Double(Self.memoryTicks) * Self.tickSeconds)) s")
            }
            // The battles play themselves a command at a time, so the frames
            // catch a dash, a hit and a flash rather than a line of units
            // waiting for a thumb. Auto-battle would win before the first
            // frame; one basic attack every four seconds is a fight in
            // progress for the whole step.
            //
            // Not while the skill panel is pinned (`-tour-skill-info`): the
            // fight holds on its first turn with a skill chosen and what it
            // does over the squares. A command a tick used the very skill the
            // panel was showing, and run 229's frame caught the victory.
            guard !Self.pinnedSkillInfo else { return }
            for model in [battleModel, arenaModel, realmModel].compactMap({ $0 }) {
                model.selectSkill(0)
                model.confirmTarget()
            }
        }
    }

    /// A tab's screen as the phone draws it: the screen, and under it the
    /// game's tab bar with the tab's own door lit — LAID OUT, as `RootView`
    /// lays it out, so the screen is 58 points shorter than the window.
    ///
    /// Until run 216 the bar was the screen's `.safeAreaInset`, and an inset
    /// applied outside a screen's `NavigationStack` never reaches the content
    /// inside it: the arena's offence, the summon deck, the collection's
    /// Train and the chapter map's lowest medallions were all laid out to the
    /// window's foot and painted over by the bar. A frame is a hard limit an
    /// inset is not. A function and not a nested view, so no name can
    /// collide; generic rather than an opaque parameter, which nothing else
    /// in the tree uses.
    private func tabbed<Content: View>(_ tab: RootView.Tab, _ screen: Content) -> some View {
        VStack(spacing: 0) {
            screen
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            GameTabBar(selection: .constant(tab))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch current {
        case "island":
            // With the tab bar the app really shows under it (GameTabBar,
            // 2026-09-22), which the tour had never photographed.
            tabbed(.island, IslandView(pinnedZoom: Self.pinnedIslandZoom) { _ in })
        case "island_decor":
            // The island's decoration sheet: the catalogue with the tour's
            // brazier and sphinx owned and standing, the rest priced.
            IslandDecorView()
        case "events":
            // The events calendar on a Festival Monday (2026-09-28, week
            // 143 from the calendar's epoch): the gift band, the TODAY card
            // and the weekend's headline all on one frame, whatever day CI
            // runs on. `-tour-events-week plain` is the Monday after, an
            // ordinary week, for the band every other week shows.
            EventsView(now: Self.pinnedPlainWeek ? Self.plainMonday : Self.festivalMonday, onClaim: { _ in nil })
        case "demigods":
            // The social screen on the seeded offline world (the CI build
            // carries no iCloud entitlement): the Guild tab by default, and
            // `-tour-social-tab friends|inbox|ranks` for the others, which
            // the CI job relaunches for.
            // ONE service for the step: built inside `body` it was rebuilt
            // on every tick of the tour, and each fresh instance had refreshed
            // nothing yet, so run 176 photographed four empty tabs.
            SocialView(social: Self.tourSocial,
                       opening: SocialTab.pinnedFromArguments ?? .guild, onAttack: { _ in }, onClaim: { _ in })
        case "regalia":
            // The Regalia sheet of the seed's awakened unit, whose item the
            // seed sets to level III so the ladder shows a rung climbed and
            // rungs to go.
            if let unit = store.player.units.first(where: { $0.isAwakened }) ?? store.player.units.first {
                RegaliaSheet(unitID: unit.id)
            } else {
                CollectionView()
            }
        case "collection":
            // Under the tab bar since phase B: both layouts are sized for the
            // 271 points a tab gets under it.
            tabbed(.collection, CollectionView())
        case "collection_stage":
            // The collection's other shape: the rail along the bottom, the
            // picked unit's model on the stage, the words and slots on the
            // left. Opened in that layout because nothing here taps the
            // switch; the `collection` step above keeps the Cards.
            tabbed(.collection, CollectionView(initialLayout: .stage))
        case "detail":
            // Zeus, the regalia locked; `-tour-detail awakened` is the seed's
            // awakened unit, its regalia at III, for the unlocked plate and
            // the awakening line in the skills.
            if let unit = detailUnit {
                UnitDetailView(unitID: unit.id)
            } else {
                CollectionView()
            }
        case "training":
            // Power up with nothing offered by default; `-tour-training
            // feed|evolve|fuse` for the three ledgers no frame had shown.
            switch Self.pinnedTraining ?? "" {
            case "feed":
                TrainingView(selectedUnitID: feedCandidate?.id, offersOnOpen: true)
            case "evolve":
                TrainingView(initialMode: .evolve, selectedUnitID: evolveCandidate?.id, offersOnOpen: true)
            case "fuse":
                TrainingView(initialMode: .fuse)
            default:
                TrainingView()
            }
        case "awaken":
            // The Hall of Ka's Awaken ledger on the strongest unit of the seed
            // that has an awakened form and has not taken it: the whole
            // awakened name carved, the bonus, the four essences as painted
            // requirement tiles with have/need all met (the seed grants the
            // essences), the ? that says where each drops, and AWAKEN live —
            // with the BECOMES card beside the figure on the altar. The
            // training step (3) opens on Power up, so this panel had never
            // been photographed while the owner was testing exactly it
            // (2026-09-17).
            TrainingView(initialMode: .awaken, selectedUnitID: awakeningCandidate?.id)
        case "summon":
            if let root = Self.pinnedRoot {
                RootView(initialTab: root)
            } else {
                tabbed(.summon, SummonView())
            }
        case "reveal":
            // A second launch with `-tour-reveal awakened` shows an awakened
            // 5★ on the beam — the frame the owner sent back on 2026-09-17
            // ("If awakened characters look like this we have a HUGE
            // problem"), so the awakened look is judged here every run.
            SummonRevealView(results: Self.demoReveal(awakened: Self.revealAwakened)) {}
        case "battle":
            if let battleModel {
                BattleView(model: battleModel)
            } else {
                Theme.surface.ignoresSafeArea()
                    .onAppear { startBattle() }
            }
        case "arena":
            // The lobby on the Arena of Souls, under the tab bar, on the
            // seed's mid-ladder standing and full defence.
            tabbed(.arena, ArenaView())
        case "arena_battle":
            // The arena fight is a different stage, a 4v4 and an AI-built
            // enemy team, so the camera and the placement are photographed
            // here as well as in the campaign.
            if let arenaModel {
                BattleView(model: arenaModel)
            } else {
                Theme.surface.ignoresSafeArea()
                    .onAppear { startArenaBattle() }
            }
        case "halls":
            // The Hall of Embers on its current floor (B3 on the seed), or
            // the hall `-tour-dungeon` names. Pushed from the Labyrinth, a
            // full-screen cover, so no tab bar.
            NavigationStack {
                DungeonLevelsView(chapterID: Self.pinnedDungeon ?? "hall_ember", focusFloor: Self.pinnedDungeonFloor)
            }
        case "labyrinth":
            LabyrinthView(opening: Self.pinnedLabyrinthWing)
        case "dungeon":
            // The Vault on B7 by default; `-tour-dungeon` and
            // `-tour-dungeon-floor` for the Necropolis, the mastered B1 and
            // the locked B10.
            NavigationStack {
                DungeonLevelsView(chapterID: Self.pinnedDungeon ?? "lab_colossus", focusFloor: Self.pinnedDungeonFloor,
                                  opensSweep: Self.pinnedDungeonSweep)
            }
        case "relic_picker":
            if let unit = store.player.units.first(where: { $0.blueprintID.hasPrefix("zeus") }) ?? store.player.units.first {
                RelicPickerView(unitID: unit.id, slot: 2)
            } else {
                RelicInventoryView()
            }
        case "relic_powerup":
            // The power-up screen on the best relic the roster owns.
            if let relic = bestRelic {
                RelicDetailView(relicID: relic.id)
            } else {
                RelicInventoryView()
            }
        case "relic_drop":
            // The card a relic drop opens from the chest's shelf: Sell, Keep,
            // Lock and keep.
            if let relic = bestRelic {
                RelicDropCard(relicID: relic.id)
                    .background(Color.black.ignoresSafeArea())
            } else {
                RelicInventoryView()
            }
        case "relic_filter":
            // The inventory with its filter sheet open.
            RelicInventoryView(openingFilter: true)
        case "launch":
            // The loading screen, frozen part way along its bar, on the key
            // art when it is in the bundle.
            LaunchView(progress: LaunchProgress(
                preview: 0.62, step: "Raising the stages",
                art: BundleArt.exists(LaunchProgress.keyArt) ? LaunchProgress.keyArt : "banner_olympus_stirs"
            ))
        case "codex":
            // The Codex (Docs/CODEX.md): the book on its first page with a
            // reward waiting, read off the tour's roster; `-tour-codex-page`
            // opens one form's page, `-tour-codex-awakened` the awakened faces.
            CodexView(awakened: Self.pinnedCodexAwakened,
                      page: Self.pinnedCodexPage.flatMap {
                          CodexPageRequest(blueprintID: $0, kind: Self.pinnedCodexAwakened ? .awakened : .base)
                      })
        case "shrines":
            // The Labyrinth's Hidden Shrines (Docs/SHRINES.md): one shrine open
            // and three piece stocks — one ready to summon, one part-way, one
            // begun (`GameStore.seedTourShrines`).
            LabyrinthView(opening: .shrines)
                .onAppear { store.seedTourShrines() }
        case "treasury":
            // The Treasury (Docs/STORE.md): the bazaar opened on its first
            // stall, the Blessing twelve days into thirty and the Chalice's
            // first-purchase double spent (`GameStore.seedTourTreasury`);
            // `-tour-treasury-odds` photographs the odds disclosure instead.
            if ProcessInfo.processInfo.arguments.contains("-tour-treasury-odds") {
                TreasuryOddsSheet()
            } else {
                ShopView(treasury: true)
                    .onAppear { store.seedTourTreasury() }
            }
        case "stress":
            // The memory stress (2026-09-24; the owner: "when I do many
            // summons, or sometimes when I play chapters, or randomly the app
            // crashes"). The plain launch is the summon screen at rest, the
            // baseline; `-tour-stress summon` pulls thirty singles and three
            // ten-pulls through the summon screen's own calls and reveal, and
            // `-tour-stress battle` plays six campaign fights on auto-repeat
            // at the top speed — each printing `[Mem]` after every pull or
            // fight and `[TourCue] stress-done` at the end (`TourStressView`).
            TourStressView(mode: Self.argument(after: "-tour-stress"))
        case "draft":
            // The Draft Arena's board mid-draft on the tour's roster (a fixed
            // seed, the player first): the ban phase by default, `-tour-draft
            // picks` two picks each with the player's turn open, `-tour-draft
            // leaders` both bans landed and both leaders chosen (Docs/DRAFT.md).
            DraftView(tourStage: DraftTourStage(rawValue: Self.argument(after: "-tour-draft") ?? "") ?? .bans)
        case "sign_in":
            // The account door, as a first launch shows it once the loading
            // screen has dissolved: the key art, the wordmark, Apple's button
            // and the guest link. Inert here — the CI build signs nothing and
            // the tour plays as a fixed guest — so nothing is tapped.
            SignInView(isOpening: false, notice: nil, onApple: { _ in }, onGuest: {})
        case "tribute":
            // A tribute chest's card: the road's, earned by the tour's player
            // (three stages of the Duat walked) and waiting to be claimed.
            if let chapter = StageDatabase.chapter("duat_1") {
                TributeCard(tribute: TributeService.tributes(for: chapter)[0], chapterID: chapter.id, difficulty: .normal)
            } else {
                CampaignView(openingChapter: "duat_1")
            }
        case "guide":
            if Self.pinnedGuideCaret {
                // Her caret on the Collection tab, drawn by the same overlay
                // RootView's `.guide` puts above the bar: the frame proves
                // the tab bar's `.guideAnchor("tab_collection")` reaches an
                // overlay drawn over the screen and the bar together. No
                // caret on the frame means the anchor is not getting out.
                tabbed(.island, IslandView(isActive: false) { _ in })
                    .overlayPreferenceValue(GuideAnchorKey.self) { anchors in
                        GeometryReader { proxy in
                            if let anchor = anchors["tab_collection"] {
                                GuideCaret(
                                    prompt: LessonBook.all.first(where: { $0.id == "first_relic" })?.prompt
                                        ?? "Open the collection",
                                    target: proxy[anchor],
                                    bounds: proxy.size
                                )
                            }
                        }
                    }
            } else {
                // Athena over the island, saying the first thing she says.
                // The tour's save is a veteran's, so the opening would be
                // silent on its own: the plate is put up directly, which is
                // what a picture of it needs. Over the island AND its bar,
                // as RootView draws her (its `.guide` is applied to the
                // stack that holds both).
                ZStack {
                    tabbed(.island, IslandView(isActive: false) { _ in })
                    GuidePlate(
                        beat: LessonBook.opening.first?.beats.first
                            ?? LessonBeat("The gods of five worlds are asleep under the stone."),
                        title: LessonBook.opening.first?.title ?? "",
                        isLast: false,
                        onAdvance: {},
                        onSkip: {}
                    )
                }
            }
        case "lessons":
            LessonsView()
        case "night_market":
            // The rolled shelf. Opened straight on its stall, because nothing
            // in a pinned tour taps the bazaar's dropdown.
            ShopView(opening: .nightMarket)
        case "counsel":
            // Athena's road: the tier the tour's save is on, its steps and the
            // tier's prize. Opened on that tab for the same reason.
            MissionsView(opening: .counsel)
        case "sweep":
            // Two plans for this step met in phase B (2026-09-22) and are
            // merged: the frame of old showed the receipt over the BRIEFING,
            // a screen the game never draws, and nothing showed the briefing
            // alone. So the plain launch is a real sweep of Duat 1-1 (the
            // tour's save three-stars it) and its receipt over the Duat's map
            // under the tab bar, where the game puts it; and `-tour-briefing
            // <stageID>` is the briefing alone, as the sheet it is — no bar,
            // no sweep, no receipt. The CI job relaunches it three times: an
            // unmastered campaign stage, the mastered one with Sweep live,
            // and Labyrinth B10's six sets.
            if let id = Self.pinnedBriefing {
                if let stage = StageDatabase.stage(id) ?? StageDatabase.stage("duat_1_4") {
                    StageBriefingView(stage: stage, onStart: { _ in }, onSweep: { _ in })
                }
            } else {
                tabbed(.campaign, TourSweepScene())
            }
        case "mileage":
            // The Duat banner's exchange, with the tour's save partway up it:
            // the 4★ row can be taken and the 5★ row cannot, which is the
            // difference the screen exists to show. The plain launch puts the
            // head of the board the save can afford on the counter (the gold
            // TAKE); `-tour-mileage-pick dearest` the dearest 5★, which it
            // cannot (the rose price and "35 MORE").
            MileageSheet(
                banner: Banner.duatOpens,
                preselect: Self.pinnedMileagePick ? MileageService.catalogue(for: Banner.duatOpens).first?.id : nil
            ) { _ in }
        case "selector":
            // The opening gift, presented directly. The tour's save has
            // already spent it (a veteran's save would otherwise pop this
            // over the summoning room at step 4), so it is put up here the
            // way the guide plate is. `-tour-selector-pick first` lights the
            // first candidate, for the gold TAKE.
            SelectorSheet(preselect: Self.pinnedSelectorPick ? SelectorService.candidates().first?.id : nil) { _ in }
        case "relic_roll":
            // The choice of two, on a relic whose seed the tour's save sets.
            // The same screen as step 19, in the state it spends most of a
            // player's attention in.
            if let relic = store.player.relics.first(where: { $0.hasPendingRoll }) ?? bestRelic {
                RelicDetailView(relicID: relic.id)
            }
        case "relic_sets":
            // The set reference, opened from a unit so its counts show.
            if let unit = store.player.units.first(where: { $0.blueprintID.hasPrefix("zeus") }) ?? store.player.units.first {
                RelicSetsSheet(unitID: unit.id)
            } else {
                RelicSetsSheet()
            }
        case "dungeon_battle":
            // A Labyrinth run on auto, so the frames catch the second and
            // third waves walking on and the Wave chip counting.
            if let dungeonModel {
                BattleView(model: dungeonModel)
            } else {
                Theme.surface.ignoresSafeArea()
                    .onAppear { startDungeonBattle() }
            }
        case "realm_battle":
            // A fight on the realm named at launch (-tour-environment), one
            // command a tick, so each set's floor, walls, light and weather
            // are seen — the other battle steps only ever show Egypt.
            if let realmModel {
                BattleView(model: realmModel)
            } else {
                Theme.surface.ignoresSafeArea()
                    .onAppear { startRealmBattle() }
            }
        case "relics":
            RelicInventoryView(openingRelic: Self.pinnedRelicPick == "legend" ? fullestWornRelic : nil)
        case "shop":
            // The Daily stall, or the one `-tour-shop-stall` names.
            ShopView(opening: Self.pinnedShopStall ?? .daily)
        case "chapter_map":
            // The first chapter as a place: the painting, the road, the
            // medallions and the chests; the world map is the `island`
            // step's neighbour and is seen from there. Under the tab bar,
            // which is how the phone measures the map. `-tour-chapter-scroll`
            // unrolls the scroll; `-tour-tier hell` is Hell on the walked
            // copy, which clears Normal and Hard so Hell is open.
            if let tier = Self.pinnedTier {
                tabbed(.campaign, CampaignView(
                    openingChapter: "duat_1",
                    openingDifficulty: tier,
                    previewPlayer: CampaignView.tourWalk(store.player, chapterIndex: 0, tier: tier)
                ))
            } else {
                tabbed(.campaign, CampaignView(openingChapter: "duat_1", openingScroll: Self.pinnedChapterScroll))
            }
        case "stage_popup":
            // The fourth stage's card over the map: story, enemies, drops,
            // power, Fight. `-tour-popup-stage duat_1_5` for the boss's.
            tabbed(.campaign, CampaignView(openingChapter: "duat_1", openingStage: Self.pinnedPopupStage ?? "duat_1_4"))
        case "chapter_maps":
            // Every chapter's map in turn (-tour-chapter K), so a painted
            // region's medallions are seen on their landmarks before the
            // owner does — on the WALKED copy (`CampaignView.tourWalk`):
            // the chapters before K full, K four stages in. Eleven of run
            // 211's twelve frames showed a chapter no player can open, every
            // medallion locked. The copy is never written to the save, which
            // persists between the tour's launches.
            tabbed(.campaign, CampaignView(
                openingChapter: StageDatabase.chapters[Self.pinnedChapter].id,
                previewPlayer: CampaignView.tourWalk(store.player, chapterIndex: Self.pinnedChapter)
            ))
        case "missions":
            // The Daily list, or the one `-tour-missions-tab` names.
            MissionsView(opening: Self.pinnedMissionsTab ?? .missions)
        case "victory":
            if Self.pinnedVictoryField {
                // A real win's end (`-tour-victory field`): the beat on the
                // field, the reckoning over it, the level-up, the chest.
                if let victoryModel {
                    BattleView(model: victoryModel)
                } else {
                    Theme.surface.ignoresSafeArea()
                        .onAppear { startVictoryField() }
                }
            } else {
                // The two acts of a win without fighting one: the reckoning,
                // then the chest opening on its spoils. `autoplay` taps
                // through for the camera.
                BattleResultView(summary: Self.demoVictory(relic: bestRelic), onDismiss: {}, autoplay: true, store: store)
                    .background(Color.black.ignoresSafeArea())
            }
        case "raid_grade":
            // A raid's win: the same two acts with the grade stamped on the
            // reckoning and the aether on the shelf. The grade and its line
            // are computed by `RaidGradeService` from a 46-turn kill of the
            // serpent, so the frame shows what the code writes, not a mock.
            BattleResultView(summary: Self.demoRaidVictory(relic: bestRelic), onDismiss: {}, autoplay: true, store: store)
                .background(Color.black.ignoresSafeArea())
        case "raids":
            // The Titans wing: the serpent's room with the tour save's best
            // grade stamped on it, the mark to beat, and the aether held;
            // `-tour-raid raid_unwrapped_king` scrolls the rail to the Umbra
            // Titan, whose three-line name is the one that has to fit.
            LabyrinthView(opening: .raids, raid: Self.pinnedRaid)
        case "relic_awaken":
            // The awakening on the tour save's 6★ +15 (the debug seed's, with
            // the aether to pay for it): the rite in the first frame, then
            // the halo on the stone, the Awakened chip and the fifth sub
            // stat's choice of two. Performed on a settled screen, with a cue
            // the CI job times the frame from (`TourRite`).
            //
            // Picked by a rule that still holds AFTER the awakening: the
            // store changes the moment it lands, this `content` is
            // re-evaluated, and a rule of "not yet awakened" swapped the
            // sheet for the best climbing relic between the two frames —
            // run 159 photographed the Vigil +12 twice and the rite never.
            if let relic = store.player.relics.first(where: { $0.grade >= 6 && $0.isMaxLevel }) {
                TourRite(relicID: relic.id, awakens: !relic.isAwakened)
            } else if let relic = bestRelic {
                RelicDetailView(relicID: relic.id)
            }
        case "boons":
            // The socket's picker, opened on the tour save's shut cache: its
            // three doors on the right, the boons owned on the left, for
            // Zeus's socket (the detail step shows the socket filled).
            if let zeus = store.player.units.first(where: { $0.blueprintID.hasPrefix("zeus") }) {
                BoonPickerView(unitID: zeus.id, openingCache: true)
            } else {
                BoonPickerView(openingCache: true)
            }
        case "resonance":
            // The team picker on the tour save's campaign team: its two
            // Egyptians light The Weighing of Hearts I, and the hint names
            // what one more Greek would light.
            TeamPickerView(slot: .campaign, maxSize: 5)
        case "more":
            // More, a sheet over the island (no tab bar). `-tour-more
            // diagnostics` opens the debug build's desk behind its one row.
            if Self.pinnedMoreDiagnostics {
                NavigationStack { DiagnosticsDesk() }
            } else {
                SettingsView(opening: Self.pinnedMoreOpening)
            }
        default:
            SettingsView()
        }
    }

    /// The unit the detail step opens: Zeus, or with `-tour-detail
    /// awakened` the seed's awakened unit (the starter, regalia at III).
    private var detailUnit: Unit? {
        let units = store.player.units
        if Self.pinnedDetailAwakened, let awakened = units.first(where: { $0.isAwakened }) {
            return awakened
        }
        return units.first(where: { $0.blueprintID.hasPrefix("zeus") }) ?? units.first
    }

    /// The unit the `feed` ledger opens on: the strongest one still BELOW its
    /// level cap. A unit at the cap would have Auto pick nothing and the
    /// ledger show its Evolve redirect instead of the ghost gauge.
    private var feedCandidate: ResolvedUnit? {
        store.resolvedUnits
            .filter { !$0.unit.isMaxLevel && $0.unit.acquiredFrom != Self.arenaSquadTag }
            .max { $0.power < $1.power }
    }

    /// The seed's level-40 arena squad (`GameStore.grantTourRoster`, run
    /// 216) is tagged, and the Hall of Ka's steps pass over it, so its
    /// frames keep the units they were composed on.
    private static let arenaSquadTag = "tour-arena"

    /// The unit the `evolve` ledger opens on: one ready to evolve, preferring
    /// one with enough unlocked units of its own grade to pay for it (an
    /// evolution eats as many as its stars), the highest grade first. The
    /// seed has one since run 216 — a water Shabti at its cap of 35, with the
    /// four level-1 Shabtis to pay — so the ledger photographs a LIVE Evolve.
    private var evolveCandidate: Unit? {
        let units = store.player.units
        let ready = units.filter { $0.canEvolve }
        let paidFor = ready.filter { unit in
            units.filter { $0.id != unit.id && !$0.isLocked && $0.stars == unit.stars }.count >= unit.stars
        }
        return (paidFor.isEmpty ? ready : paidFor).max { $0.stars < $1.stars }
    }

    /// The Allies step's service on the seeded offline world, made once.
    private static let tourSocial = SocialService(backend: LocalSocialBackend(seed: 7, persisting: false))

    /// A Monday of a Festival week, for the events step.
    private static var festivalMonday: Date {
        EventCalendar.calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12)) ?? Date()
    }

    /// The Monday a week after `festivalMonday`: the Festival comes every
    /// fourth week, so this one is an ordinary week (`-tour-events-week
    /// plain`).
    private static var plainMonday: Date {
        EventCalendar.calendar.date(byAdding: .day, value: 7, to: festivalMonday) ?? festivalMonday
    }

    /// The unit the awaken step opens on: not yet awakened, with an awakened
    /// form to take, the highest grade and level first.
    private var awakeningCandidate: Unit? {
        store.player.units
            .filter { !$0.isAwakened && $0.acquiredFrom != Self.arenaSquadTag }
            .filter { UnitDatabase.blueprint($0.blueprintID)?.awakening != nil }
            .max { ($0.stars, $0.level) < ($1.stars, $1.level) }
    }

    /// The relic the relic steps photograph: the highest grade, and among
    /// those the highest level, so the level track and the rim both show —
    /// but never one already at +15, whose power-up panel has nothing to
    /// photograph (the seed's awakening candidate is one, for step 40).
    private var bestRelic: Relic? {
        let climbing = store.player.relics.filter { !$0.isMaxLevel }
        return (climbing.isEmpty ? store.player.relics : climbing)
            .max(by: { ($0.grade, $0.level) < ($1.grade, $1.level) })
    }

    /// The worn relic with the most for the inventory's panel to hold: four
    /// subs, then a four-piece set (its effect wraps), then Legend, then the
    /// grade. The seed's rolls differ run to run, so it is found, not named.
    private var fullestWornRelic: UUID? {
        store.player.relics
            .filter { $0.equippedBy != nil }
            .max(by: { a, b in
                let left = (a.subStats.count, a.set.piecesRequired, a.resolvedQuality.rawValue, a.grade)
                let right = (b.subStats.count, b.set.piecesRequired, b.resolvedQuality.rawValue, b.grade)
                return left < right
            })?.id
    }

    private func tick() {
        ticksOnStep += 1
        guard ticksOnStep >= Self.schedule[min(index, Self.schedule.count - 1)].ticks else { return }
        ticksOnStep = 0
        if index + 1 < Self.schedule.count {
            index += 1
            if current == "battle" { startBattle() }
            if current == "arena_battle" { startArenaBattle() }
            if current == "dungeon_battle" { startDungeonBattle() }
            if current == "realm_battle" { startRealmBattle() }
        }
    }

    /// The first stage set in the pinned realm. It is locked on a fresh
    /// save, so the engine is built directly rather than through the
    /// store's gate: no energy is spent and no clear is recorded.
    private func startRealmBattle() {
        guard realmModel == nil else { return }
        let environment = Self.pinnedEnvironment ?? .olympusGate
        guard let stage = StageDatabase.allStages.first(where: { $0.environment == environment }) else { return }
        let team = CampaignService.resolveTeam(store.player.campaignTeam, player: store.player)
        guard !team.isEmpty else { return }
        let engine = BattleEngine(
            playerTeam: team,
            opponentTeam: StageDatabase.buildEnemies(for: stage),
            mode: .campaign,
            seed: 7,
            laterWaves: stage.laterWaves.map { StageDatabase.buildEnemies(spawns: $0) }
        )
        let model = BattleViewModel(engine: engine, context: .campaign(stage), store: store)
        model.autoBattle = false
        realmModel = model
    }

    private func seedIfNeeded() {
        guard !seeded else { return }
        seeded = true
        store.grantTourRoster()
        // The opening's lessons, given. Without this the library photographs
        // as fourteen greyed rows — true of a save that has never met Athena,
        // and useless as a picture of the screen: what it is FOR is the
        // difference between a lesson kept and a lesson still locked.
        //
        // The shell's own frame (`-tour-root`) is the one launch that draws
        // RootView, whose `.guide` puts Athena up for the next unread lesson:
        // on run 217 her plate covered the deck and the rail the frame exists
        // to prove. That launch alone has read everything and skipped the
        // opening, so she is silent. The save persists between the tour's
        // launches, so every other launch sets the record back to exactly the
        // first four — what it always was, since nothing in the tour taps her
        // on — or the lessons step (31) would photograph every row kept.
        let lessonsWanted: [String] = Self.pinnedRoot != nil
            ? (LessonBook.all.map(\.id) + [LessonBook.openingSkipped]).sorted()
            : LessonBook.opening.prefix(4).map(\.id)
        if store.player.lessonsRead != lessonsWanted {
            store.update { player in
                player.lessonsRead = lessonsWanted
            }
        }
    }

    private func startBattle() {
        guard battleModel == nil else { return }
        // The first gate is the one stage every account has open; a fresh
        // save has not cleared it, so Reed Fields would refuse and the step
        // would stay black.
        for id in ["duat_1_1", "duat_1_2"] {
            guard let stage = StageDatabase.stage(id),
                  let engine = store.startCampaignBattle(stage: stage) else { continue }
            let model = BattleViewModel(engine: engine, context: .campaign(stage), store: store)
            // Not on auto: a levelled team won the first gate before the
            // runner's first frame and every battle frame was the victory
            // panel. Waiting for a command shows the stage, the HUD and the
            // idle clips, which is what the frames are for.
            model.autoBattle = false
            battleModel = model
            return
        }
    }

    private func startDungeonBattle() {
        guard dungeonModel == nil else { return }
        guard let stage = StageDatabase.stage("lab_colossus_1"),
              let engine = store.startCampaignBattle(stage: stage) else { return }
        let model = BattleViewModel(engine: engine, context: .campaign(stage), store: store)
        // On auto: the point of the step is the waves, and the tour roster
        // clears the first in a few turns.
        model.autoBattle = true
        dungeonModel = model
    }

    /// The victory step's real win (`pinnedVictoryField`). The seed makes the
    /// win level the demigod and the leader, so the level-up and a LEVEL UP
    /// over a plate are both in the frames: the first gate pays 30 demigod
    /// experience and 240 a unit, and each is set one short of its next
    /// level. The save persists between the tour's launches, so the steps
    /// after this one see both a level higher — as they would after any win.
    private func startVictoryField() {
        guard victoryModel == nil, let stage = StageDatabase.stage("duat_1_1") else { return }
        seedIfNeeded()
        let losing = Self.pinnedVictory == "defeat"
        store.update { player in
            if !losing {
                player.experience = max(0, player.experienceToNextLevel - 1)
                if let leader = player.campaignTeam.leaderID,
                   let index = player.units.firstIndex(where: { $0.id == leader }),
                   !player.units[index].isMaxLevel {
                    let unit = player.units[index]
                    let needed = ProgressionService.experienceForNextLevel(level: unit.level, stars: unit.stars)
                    player.units[index].experience = max(0, needed - 1)
                }
            }
            player.wallet.energy = max(player.wallet.energy, 40)
        }
        guard let engine = store.startCampaignBattle(stage: stage) else { return }
        let model = BattleViewModel(engine: engine, context: .campaign(stage), store: store)
        victoryModel = model
        if losing {
            // Waiting for a command nobody gives, then the gear's Forfeit:
            // the game's own way to lose, settled as a loss.
            model.autoBattle = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 7) {
                model.forfeit()
            }
            return
        }
        // On auto at the top speed: the frames are of the fight's END.
        model.autoBattle = true
        model.speed = BattleSpeed.top
    }

    private func startArenaBattle() {
        guard arenaModel == nil else { return }
        guard let opponent = store.arenaPool.first,
              let engine = store.startArenaBattle(against: opponent) else { return }
        let model = BattleViewModel(engine: engine, context: .arena(opponent), store: store)
        model.autoBattle = false
        arenaModel = model
    }

    /// A 5★ reveal without spending a scroll, so the stage is caught with a
    /// real model on it.
    private static func demoReveal(awakened: Bool = false) -> [SummonResult] {
        // Awakened: Ares in light, the owner's own frame, on the shipped
        // `ares_awakened` mesh; otherwise the fire Sekhmet as before.
        let wanted = awakened ? "ares_radiance" : "sekhmet_ember"
        guard let blueprint = UnitDatabase.blueprint(wanted) ?? UnitDatabase.summonPool.first.flatMap(UnitDatabase.blueprint) else {
            return []
        }
        var unit = Unit(blueprint: blueprint)
        if awakened { unit.isAwakened = true }
        return [SummonResult(
            unit: unit,
            blueprint: blueprint,
            stars: blueprint.naturalStars,
            isNew: true,
            isFeatured: true,
            fromPity: false
        )]
    }

    /// `-tour-reveal awakened` asks the reveal step for an awakened result.
    private static var revealAwakened: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let at = args.firstIndex(of: "-tour-reveal"), at + 1 < args.count else { return false }
        return args[at + 1] == "awakened"
    }

    /// A won stage as the result screen reads it: three of the first
    /// families, one of them the MVP, one fallen, and a chest with every
    /// kind of spoil in it, so the tiles are all photographed at once.
    private static func demoVictory(relic: Relic? = nil) -> BattleSummary {
        let cast: [(id: String, dealt: Double, taken: Double, healed: Double, kills: Int, survived: Bool)] = [
            ("anubis_umbra", 14_820, 3_960, 0, 3, true),
            ("sekhmet_ember", 9_140, 6_210, 0, 2, true),
            ("thoth_radiance", 2_380, 1_100, 5_640, 0, true),
            ("zeus_tide", 6_470, 8_900, 0, 1, false),
        ]
        var stats: [BattleSummary.UnitStat] = []
        for member in cast {
            guard let blueprint = UnitDatabase.blueprint(member.id) else { continue }
            stats.append(BattleSummary.UnitStat(
                id: UUID(),
                name: blueprint.name,
                portraitName: blueprint.model.portraitName(awakened: false),
                element: blueprint.element,
                stars: blueprint.naturalStars,
                dealt: member.dealt,
                taken: member.taken,
                healed: member.healed,
                kills: member.kills,
                survived: member.survived
            ))
        }
        let loot: [BattleSummary.Loot] = [
            .init(glyph: "circle.hexagongrid.fill", title: "Drachma", amount: "+1,240", tint: .gold, key: "drachma"),
            .init(glyph: "arrow.up.circle.fill", title: "Unit EXP", amount: "+860", tint: .verdigris, key: "unit_exp"),
            .init(glyph: "sparkles", title: "Divinity", amount: "+15", tint: .marble, key: "divinity"),
            .init(glyph: RelicSet.fury.glyph, title: relic?.displayName ?? "Hero Fury Relic", amount: nil,
                  tint: .gold, stars: relic?.grade ?? 5, relic: relic),
            .init(glyph: "drop.triangle.fill", title: "Mid Ember Essence", amount: "+3", tint: .element(.ember), key: "essence_ember_mid"),
            .init(glyph: ScrollType.unknown.glyph, title: ScrollType.unknown.displayName, amount: "+1", tint: .scroll(.unknown), key: ItemArt.key(scroll: .unknown)),
        ]
        return BattleSummary(
            outcome: .victory,
            lines: [],
            stars: 3,
            title: "The Weighing of the Heart",
            turns: 11,
            damageDealt: stats.reduce(0) { $0 + $1.dealt },
            damageTaken: stats.reduce(0) { $0 + $1.taken },
            unitStats: stats,
            mvpID: stats.first?.id,
            loot: loot,
            isFirstClear: true
        )
    }

    /// The serpent's raid as its result screen reads it: the demo win's cast,
    /// a kill on turn 46 graded by the real service, and the raid's own shelf
    /// — its 6★ relic, the aether the grade pays, a whetstone, its essence.
    private static func demoRaidVictory(relic: Relic? = nil) -> BattleSummary {
        var summary = demoVictory(relic: relic)
        summary.stars = 2
        summary.turns = 46
        summary.isFirstClear = false
        guard let raid = StageDatabase.raids.first, let profile = raid.profile else { return summary }
        let result = BattleResult(
            outcome: .victory, turnsTaken: 46, survivorFraction: 0.75,
            totalDamageDealt: summary.damageDealt, totalDamageTaken: summary.damageTaken,
            seed: 0, raidShare: 1
        )
        let grade = RaidGradeService.grade(result: result, profile: profile)
        let pay = RaidGradeService.aether(for: grade)
        let elemental = Aether.id(for: RaidGradeService.element(of: raid))
        summary.title = raid.name
        summary.raidGrade = grade
        summary.raidGradeLine = RaidGradeService.caption(grade: grade, result: result, profile: profile)
        summary.loot = [
            .init(glyph: "circle.hexagongrid.fill", title: "Drachma", amount: "+12,000", tint: .gold, key: "drachma"),
            .init(glyph: "arrow.up.circle.fill", title: "Unit EXP", amount: "+2,400", tint: .verdigris, key: "unit_exp"),
            .init(glyph: RelicSet.fury.glyph, title: relic?.displayName ?? "Legend Fury Relic", amount: nil,
                  tint: .gold, stars: relic?.grade ?? 6, relic: relic),
            .init(glyph: "circle.hexagonpath.fill", title: Aether.name(for: elemental), amount: "+\(pay.elemental)",
                  tint: .element(RaidGradeService.element(of: raid)), key: elemental),
            .init(glyph: "circle.hexagonpath.fill", title: Aether.name(for: Aether.pure), amount: "+\(pay.pure)",
                  tint: .marble, key: Aether.pure),
            .init(glyph: RelicStone.Kind.whetstone.glyph, title: "Hero Whetstone", amount: "+1", tint: .rarity(RelicQuality.hero.rarity), key: "whetstone_hero"),
            .init(glyph: "drop.triangle.fill", title: "High Ember Essence", amount: "+2", tint: .element(.ember), key: "essence_ember_high"),
        ]
        return summary
    }
}

/// The relic's rite, performed where the CI job can time it. The rite runs
/// on its own clock — the veil up by 0.35 s, AWAKENED settled by about 1.4,
/// the fade out from 2.8 (from 6 under the tour, `RelicAwakeningRite
/// .closesAfter`, since a CI screenshot lands two to three seconds after it
/// is asked for) — and awakening on appear put its start wherever
/// the launch happened to finish: run 223's frame caught the peak and run
/// 224's, with the same sleep, the fade out (a khaki wash, the caption at
/// 70%). So the relic's screen is drawn first and left to settle, then the
/// awakening is performed on a fresh copy of it (its `onAppear` is what
/// awakens) and `[TourCue] rite` goes to stdout the same moment; the job
/// waits for that line and photographs the peak a fixed time after it.
private struct TourRite: View {
    let relicID: UUID
    /// False once the relic is awakened: a later launch on the same save
    /// has no rite to perform, and prints no cue.
    let awakens: Bool

    @State private var armed = false

    var body: some View {
        Group {
            if armed {
                RelicDetailView(relicID: relicID, awakenOnAppear: true)
            } else {
                RelicDetailView(relicID: relicID)
            }
        }
        .onAppear {
            guard awakens, !armed else { return }
            // Long enough for the launch's first draw — run 224's main
            // thread was busy 0.8 s bringing this screen up — to be over.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                armed = true
                print("[TourCue] rite")
            }
        }
    }
}

/// The sweep, photographed where the game shows it: the receipt over the
/// chapter's map (TourView wraps this in the tab bar, since the map is a
/// tab). It runs a REAL sweep on the tour's save — `duat_1_1`, which the
/// debug save three-stars — rather than building a receipt by hand, because a
/// hand-built one would photograph a screen the game cannot actually produce.
///
/// Until phase B (2026-09-22) the receipt stood over the stage's BRIEFING,
/// which the game never draws: the briefing is a sheet that closes before a
/// sweep runs, and the receipt is `CampaignView`'s own overlay on the map.
/// The receipt is laid over the map here rather than through the campaign
/// screen because nothing on it opens a receipt from outside; the two draw
/// the same, the card over the whole screen and the bar outside it. The
/// briefing alone is `-tour-briefing`. Inside the debug block since then too:
/// it stood after the `#endif`, compiled into the release build for nothing.
private struct TourSweepScene: View {
    @EnvironmentObject private var store: GameStore
    @State private var receipt: SweepReceipt?

    private var stage: Stage? { StageDatabase.stage("duat_1_1") }

    var body: some View {
        ZStack {
            CampaignView(openingChapter: "duat_1")
                .dimsTabBar(receipt != nil)
            if let receipt {
                SweepReceiptCard(
                    receipt: receipt,
                    loot: BattleSummary.loot(from: receipt.outcome) {
                        store.resolved($0)?.name ?? "Unit"
                    },
                    onClose: {}
                )
            }
        }
        .onAppear {
            guard let stage, receipt == nil else { return }
            receipt = store.sweep(stage: stage, runs: 5)
            print("[Tour] sweep duat_1_1 runs=\(receipt?.runs ?? -1) "
                  + "mastered=\(SweepService.isMastered(stage, player: store.player)) "
                  + "powered=\(SweepService.isPowered(stage, player: store.player))")
        }
    }
}

/// Tour step 53, the memory stress (2026-09-24). The owner's phone crashes
/// "when I do many summons, or sometimes when I play chapters, or randomly",
/// and no CI step had ever done either many times in one launch: every step
/// is a fresh launch that shows one screen. This one does the work a player
/// does and prints the process's footprint after every piece of it
/// (`MemoryProbe`), so the console of each run carries the memory curve,
/// and a crash on the way leaves its report beside the frames.
///
/// `-tour-stress summon`: thirty singles, then three ten-pulls, on the
/// Endless Scroll (every family, so the most different models), through the
/// summon screen's own calls — `GameStore.summon`, the first figure warmed,
/// the 0.45 s wind-up, the reveal in a full-screen cover over the summon
/// screen. A reveal advances only on a tap, which a tour cannot make, so each
/// pull of a ten-pull is the reveal of the pulls from it onwards, rebuilt as
/// a tap would have moved it on (its stage is keyed by the pull and was
/// rebuilt on a tap too), and it warms the next pull itself; the ten-card
/// grid a tap on Skip opens is the one screen the loop does not reach.
///
/// `-tour-stress battle`: three stages the tour's save has cleared, each on
/// auto-repeat for two runs (`BattleViewModel(repeatCount:)`, the path the
/// briefing's run count takes: the engine swapped and the scene rebuilt in
/// place between runs, a new battle screen per stage) at the top speed, in a
/// full-screen cover over the chapter map as the map presents it, and the
/// result panel held three seconds before the cover closes.
///
/// Both print `[TourCue] stress-done` at the end; the CI job waits for it.
private struct TourStressView: View {
    let mode: String?

    @EnvironmentObject private var store: GameStore
    @StateObject private var driver = TourStressDriver()

    private var isBattle: Bool { mode == "battle" }

    var body: some View {
        let tab: RootView.Tab = isBattle ? .campaign : .summon
        VStack(spacing: 0) {
            Group {
                if isBattle {
                    CampaignView(openingChapter: "duat_1")
                } else {
                    SummonView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            GameTabBar(selection: .constant(tab))
        }
        .fullScreenCover(isPresented: Binding(
            get: { driver.cover != nil },
            set: { presented in if !presented { driver.cover = nil } }
        )) {
            coverContent
        }
        .onAppear {
            driver.run(mode: mode, with: store)
        }
    }

    @ViewBuilder
    private var coverContent: some View {
        if let cover = driver.cover {
            switch cover {
            case .reveal(let results, let serial):
                SummonRevealView(results: results, scroll: TourStressDriver.banner.scroll) {
                    driver.cover = nil
                }
                .id(serial)
                .environmentObject(store)
            case .battle(let model, let serial):
                BattleView(model: model)
                    .id(serial)
                    .environmentObject(store)
            }
        } else {
            Color.black.ignoresSafeArea()
        }
    }
}

/// The loop behind `TourStressView`, on the main actor like the screens it
/// drives.
@MainActor
private final class TourStressDriver: ObservableObject {
    enum Cover {
        case reveal([SummonResult], Int)
        case battle(BattleViewModel, Int)
    }

    /// The Endless Scroll: every family in the pool.
    static let banner = Banner.standard
    static let singles = 30
    static let tenPulls = 3
    /// How long a reveal stands before the tap that moves it on: long enough
    /// for the stage to build, the charge (0.8–1.25 s) to play and the figure
    /// to be drawn on its beam.
    static let singleHold: Double = 2.8
    static let pullHold: Double = 2.4
    /// A full-screen cover's dismissal, before the next is presented.
    static let dismissal: Double = 1.0
    /// Stages the tour's save has cleared (`GameStore.grantTourRoster`), so
    /// the level-12 team wins and every run is played to its end.
    static let battlePlan: [(stage: String, runs: Int)] = [("duat_1_1", 2), ("duat_1_2", 2), ("duat_1_3", 2)]
    /// The battle's speed control steps ×1 → ×2 → ×3 (Docs/FEEL.md W1.1;
    /// it stepped to ×4 until 2026-09-24), so ×3 is its top.
    static let topSpeed: Double = BattleSpeed.top
    /// A run still going after this is forfeited, so a stuck fight cannot
    /// hold the step past the job's wait.
    static let runLimit: Double = 70
    /// The result panel on screen before the cover closes.
    static let resultHold: Double = 3

    @Published var cover: Cover?
    private var serial = 0
    private var started = false

    func run(mode: String?, with game: GameStore) {
        guard !started else { return }
        started = true
        guard let mode else {
            MemoryProbe.log("stress baseline (no -tour-stress)")
            return
        }
        Task { @MainActor in
            // The screen underneath draws and settles first.
            await pause(3)
            if mode == "battle" {
                await battles(game)
            } else if mode == "parse" {
                await parses()
            } else {
                await summons(game)
            }
            MemoryProbe.log("stress \(mode) done")
            print("[TourCue] stress-done")
        }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: Summons

    private static let purgeEachReveal = ProcessInfo.processInfo.arguments.contains("-tour-stress-purge")
    private static let warnEachReveal = ProcessInfo.processInfo.arguments.contains("-tour-stress-warn")

    private func summons(_ game: GameStore) async {
        let scroll = Self.banner.scroll
        let needed = Self.singles + Self.tenPulls * 10
        let held = game.player.wallet.count(of: scroll)
        if held < needed {
            game.update { player in
                player.wallet.add(scroll, needed - held)
            }
        }
        MemoryProbe.log("stress summon start: \(Self.singles) singles and \(Self.tenPulls) ten-pulls on \(Self.banner.title)")
        for pull in 1...Self.singles {
            await summon(game, count: 1, label: "single \(pull)/\(Self.singles)")
        }
        for ten in 1...Self.tenPulls {
            await summon(game, count: 10, label: "ten-pull \(ten)/\(Self.tenPulls)")
        }
    }

    /// One press of the summon button, as `SummonView.perform` makes it, and
    /// its reveal played through.
    private func summon(_ game: GameStore, count: Int, label: String) async {
        let results = game.summon(banner: Self.banner, count: count)
        guard let first = results.first else {
            print("[Tour] stress: \(label) summoned nothing (\(game.lastError ?? "no error given"))")
            return
        }
        // `SummonView.warmFirstFigure`, then the circle's wind-up.
        ModelLibrary.shared.warm([first.blueprint.model])
        await pause(0.45)
        for position in results.indices {
            serial += 1
            cover = .reveal(Array(results[position...]), serial)
            await pause(count == 1 ? Self.singleHold : Self.pullHold)
        }
        cover = nil
        await pause(Self.dismissal)
        // The memory experiment (2026-09-24, -tour-stress-purge): runs
        // 242-244 grew about 16 MB with every NEW family summoned and nothing
        // with a repeat, even with the model cache at its cap, so something
        // keeps each family's pixels outside the cache. Emptying everything
        // the app itself holds after each reveal says whether it is ours: if
        // the curve still climbs, it is SceneKit's.
        if Self.purgeEachReveal {
            ModelLibrary.shared.purge()
            ModelLibrary.shared.purgeClips()
        }
        // Part four (2026-09-24, -tour-stress-warn): run 248's summon stress
        // ended at 1,571 MB with no 3D view alive and 440 MB in the model
        // cache, and reading the files through the importer with nothing
        // drawn kept nothing (the parse launch). What is left is held by a
        // framework that lets go only when told memory is short, or it is
        // freed memory the allocator kept. After each reveal: the simulator's
        // own memory warning (what Debug → Simulate Memory Warning sends; our
        // caches purge on it as well), a second for the frameworks to act,
        // then the allocator asked to hand every free page back.
        if Self.warnEachReveal {
            MemoryProbe.log("stress summon \(label) before the warning")
            let application = UIApplication.shared
            let simulate = NSSelectorFromString("_performMemoryWarning")
            if application.responds(to: simulate) {
                application.perform(simulate)
            } else {
                NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: application)
            }
            await pause(1.0)
            let released = malloc_zone_pressure_relief(nil, 0)
            print("[Tour] stress: the allocator gave back \(released / 1_048_576) MB")
        }
        let what = count == 1
            ? "\(first.stars)★ \(first.blueprint.id)"
            : "\(results.filter { $0.stars >= 4 }.count) of \(results.count) at 4★ or better"
        MemoryProbe.log("stress summon \(label) (\(what))")
    }

    // MARK: Parses

    /// `-tour-stress parse` (2026-09-24): runs 246 and 247 kept about 11 MB
    /// a reveal with every cache of ours emptied after each one, a repeat
    /// family adding next to nothing and a new one ten to forty, and handing
    /// SceneKit decoded textures instead of files (run 247) did not move the
    /// slope. So the importer keeps something for each FILE it has read. This
    /// reads files with no reveal, no view and no cache of ours, one kind at
    /// a time, each inside its own autorelease pool, and prints the footprint
    /// after each; the slope of a phase names what is kept. idle: nothing,
    /// the control. raw: eight families' full meshes by URL, each parsed and
    /// dropped. clips: eight other families' clip files by URL, with the
    /// loader's options, each parsed and dropped. repeat: the first raw
    /// family's mesh eight times more.
    private func parses() async {
        let assets = Array(Set(UnitDatabase.summonPool.compactMap { UnitDatabase.blueprint($0)?.model.assetName })).sorted()
        let meshes = Array(assets.prefix(8))
        let clipFamilies = Array(assets.dropFirst(8).prefix(8))
        MemoryProbe.log("stress parse start: \(meshes.count) meshes, \(clipFamilies.count) clip sets, \(assets.count) families in the pool")
        for tick in 1...4 {
            await pause(1.5)
            MemoryProbe.log("stress parse idle \(tick)/4")
        }
        for (slot, asset) in meshes.enumerated() {
            let read = parseOnce(asset, clip: false)
            await pause(0.8)
            MemoryProbe.log("stress parse raw \(slot + 1)/\(meshes.count) \(asset)\(read ? "" : " (not found)")")
        }
        for (slot, asset) in clipFamilies.enumerated() {
            var files = 0
            for clip in AnimationClip.allCases where parseOnce("\(asset)_\(clip.rawValue)", clip: true) {
                files += 1
            }
            await pause(0.8)
            MemoryProbe.log("stress parse clips \(slot + 1)/\(clipFamilies.count) \(asset) (\(files) files)")
        }
        if let first = meshes.first {
            for time in 1...8 {
                parseOnce(first, clip: false)
                await pause(0.8)
                MemoryProbe.log("stress parse repeat \(time)/8 \(first)")
            }
        }
    }

    /// One file parsed and dropped inside its own autorelease pool, so what
    /// is left afterwards is what something kept, not what waits for a
    /// drain. A clip file is read with the loader's options.
    @discardableResult
    private func parseOnce(_ name: String, clip: Bool) -> Bool {
        guard let url = ModelLibrary.shared.tourURL(for: name) else { return false }
        return autoreleasepool { () -> Bool in
            let options: [SCNSceneSource.LoadingOption: Any]? = clip
                ? [.animationImportPolicy: SCNSceneSource.AnimationImportPolicy.playRepeatedly]
                : nil
            return (try? ModelLibrary.parseScene(at: url, options: options)) != nil
        }
    }

    // MARK: Battles

    private func battles(_ game: GameStore) async {
        let total = Self.battlePlan.reduce(0) { $0 + $1.runs }
        MemoryProbe.log("stress battle start: \(total) runs on auto-repeat at ×\(Int(Self.topSpeed))")
        var fought = 0
        for plan in Self.battlePlan {
            guard let stage = StageDatabase.stage(plan.stage) else {
                print("[Tour] stress: no stage \(plan.stage)")
                continue
            }
            // Energy for every run, so the repeat never stops for it.
            game.update { player in
                player.wallet.energy = max(player.wallet.energy, 200)
            }
            guard let engine = game.startCampaignBattle(stage: stage) else {
                print("[Tour] stress: \(plan.stage) would not start (\(game.lastError ?? "no error given"))")
                continue
            }
            let model = BattleViewModel(engine: engine, context: .campaign(stage), store: game, repeatCount: plan.runs)
            model.speed = Self.topSpeed
            serial += 1
            cover = .battle(model, serial)
            let began = Date()
            let limit = Self.runLimit * Double(plan.runs)
            var logged = 0
            var forfeited = false
            while true {
                let session = model.repeatSession
                while logged < (session?.completed ?? 0) {
                    logged += 1
                    fought += 1
                    MemoryProbe.log("stress battle \(fought)/\(total) \(plan.stage) run \(logged) of \(plan.runs)")
                }
                if let session, session.isFinished { break }
                if session == nil, model.outcome != nil { break }
                let elapsed = Date().timeIntervalSince(began)
                if elapsed > limit + 15 {
                    print("[Tour] stress: \(plan.stage) never ended")
                    break
                }
                if elapsed > limit, !forfeited {
                    forfeited = true
                    print("[Tour] stress: \(plan.stage) forfeited after \(Int(elapsed)) s")
                    model.forfeit()
                }
                await pause(0.5)
            }
            if let reason = model.repeatSession?.stoppedBecause {
                print("[Tour] stress: \(plan.stage) stopped: \(reason)")
            }
            await pause(Self.resultHold)
            cover = nil
            await pause(Self.dismissal)
            MemoryProbe.log("stress battle \(plan.stage) closed")
        }
    }
}
#endif
