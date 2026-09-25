import Foundation
import SwiftUI
import Combine

/// Where a battle came from, and what to do when it ends.
enum BattleContext: Identifiable {
    case campaign(Stage)
    case arena(ArenaOpponent)
    /// A guild war attack (2026-09-17): a friend-list rival's defence,
    /// fought as an arena attack but settled through the social layer —
    /// never through `.arena`, whose settle path moves rank points.
    case guildWar(WarTarget)
    /// A Draft Arena bout (2026-09-23, Docs/DRAFT.md): the four each side
    /// kept after the draft and the bans, leaders first, fought in the
    /// arena's mode and settled through `GameStore.finishDraftBout` — never
    /// through `.arena`, whose settle path moves the arena's rank points.
    case draft(DraftBout)

    var id: String {
        switch self {
        case .campaign(let stage): return "campaign_\(stage.id)"
        case .arena(let opponent): return "arena_\(opponent.id)"
        case .guildWar(let target): return "war_\(target.id)"
        case .draft(let bout): return "draft_\(bout.id)"
        }
    }

    var environment: BattleEnvironment {
        switch self {
        case .campaign(let stage): return stage.environment
        case .arena, .guildWar, .draft: return .arenaOfSouls
        }
    }

    var title: String {
        switch self {
        case .campaign(let stage): return stage.name
        case .arena(let opponent): return "vs \(opponent.name)"
        case .guildWar(let target): return "vs \(target.profile.name)"
        case .draft(let bout): return "vs \(bout.rivalName)"
        }
    }
}

/// Drives one battle: owns the engine, owns the scene, and keeps the HUD in
/// step with what the player is actually watching.
///
/// The engine resolves a whole turn the instant an action is submitted. The
/// scene then plays that turn back over a couple of seconds. The HUD reads
/// `displayedCombatants`, which advances with the *animation*, so health bars
/// and status pips never jump ahead of the hit that caused them.
@MainActor
final class BattleViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var displayedCombatants: [Combatant] = []
    @Published private(set) var turnOrderPreview: [Combatant] = []
    @Published private(set) var awaitingActor: Combatant?
    @Published private(set) var selectedSkillSlot: Int?
    @Published private(set) var isPlayingBack = false
    @Published private(set) var outcome: BattleResult?
    /// The wave on the field, 1-based; a dungeon run has three.
    @Published private(set) var waveIndex = 1
    /// A chapter boss's one line, in a band across the field for a couple
    /// of seconds as it arrives (`announceBoss`). Cleared by the view. While
    /// it is up the field's plates are dimmed to a quarter, so the band
    /// reads alone (run 224, 18-b). An ultimate's announcement is no longer
    /// here: it is the scene's splash (Docs/FEEL.md W2.1,
    /// `BattleSceneController.onFieldCue`), with the world held under it;
    /// and a giant's line rides its entrance's ribbon (W2.11).
    @Published var bossSpeech: BossSpeech? {
        didSet {
            if (bossSpeech == nil) != (oldValue == nil) {
                sceneController.plates.setPlatesDimmed(bossSpeech != nil)
            }
        }
    }

    struct BossSpeech: Equatable {
        var portrait: String
        var speaker: String
        var line: String
        var accentHex: String
    }
    @Published private(set) var log: [String] = []
    @Published var autoBattle = false {
        didSet {
            engine.autoBattle = autoBattle
            if autoBattle, awaitingActor != nil { takeAutoTurn() }
        }
    }
    /// ×1, ×2 or ×3 (`BattleSpeed`, Docs/FEEL.md W1.1): the speed the last
    /// fight on this device was left at, and remembered again with every
    /// change, so a player who watches at ×2 is not set back to ×1 by each
    /// new fight. The scene reads it only through `speedMultiplier`.
    @Published var speed: Double = BattleSpeed.remembered() {
        didSet {
            sceneController.speedMultiplier = speed
            BattleSpeed.remember(speed)
        }
    }
    /// Set when the player taps a unit while choosing a target.
    @Published var highlightedTarget: UUID?

    let context: BattleContext
    let sceneController = BattleSceneController()

    private var engine: BattleEngine
    private var pendingEvents: [BattleEvent] = []

    var waveCount: Int { engine.waveCount }
    /// Not private: the result view hands it to the relic drop card.
    /// Strong since 2026-09-24: it was `unowned`, and a store rebuilt under a
    /// live fight (a sign-out from the foreground credential check) trapped
    /// the delayed `conclude()`. The model lives only as long as its view, so
    /// holding the store cannot form a cycle.
    let store: GameStore

    // MARK: - Init

    init(engine: BattleEngine, context: BattleContext, store: GameStore, repeatCount: Int = 1) {
        self.engine = engine
        self.context = context
        self.store = store
        self.displayedCombatants = engine.combatants
        sceneController.delegate = self
        sceneController.speedMultiplier = speed
        // A repeat run is on auto from the first turn; a property observer
        // does not fire in an initialiser, so the engine is told directly.
        if repeatCount > 1, case .campaign = context {
            repeatSession = RepeatSession(requested: repeatCount)
            autoBattle = true
            engine.autoBattle = true
        }
        // The team as it stands before the fight, for the plates' EXP bars
        // at the end; `restart` takes it again for every run of a repeat.
        snapshotTeam()
    }

    // MARK: - Auto-repeat

    /// The same stage several times over on auto, the grind the genre is
    /// built on: what was asked for, what is done, and what it all paid.
    /// Campaign stages and hall floors only; the arena spends an attack per
    /// fight and is fought by hand.
    struct RepeatSession {
        var requested: Int
        var completed = 0
        var wins = 0
        var drachma = 0
        var unitExperience = 0
        var divinity = 0
        var relics: [Relic] = []
        var essences: [String: Int] = [:]
        var scrolls: [String: Int] = [:]
        var stones: [String: Int] = [:]
        var aether: [String: Int] = [:]
        var boonCaches: [BoonCache] = []
        var stoppedBecause: String?
        /// The demigod levels every run raised and the level the last of
        /// them reached: ONE level-up beat at the session's end, never one a
        /// run (Docs/FEEL.md W1.6).
        var playerLevelsGained = 0
        var newPlayerLevel = 0
        /// The last run's stars, for the VICTORY stamp over its field; a
        /// session's reckoning shows none (W1.7).
        var lastStars = 0

        var isFinished: Bool { completed >= requested || stoppedBecause != nil }
    }

    @Published private(set) var repeatSession: RepeatSession?
    /// A line for the HUD between runs ("Run 3 of 10"); the view clears it.
    @Published var repeatBanner: String?

    /// Asks the session to end after the run in progress.
    func stopRepeating() {
        guard var session = repeatSession else { return }
        session.requested = min(session.requested, session.completed + 1)
        repeatSession = session
    }

    /// Called by the view once the outcome has landed. On a repeat run with
    /// runs still to go, banks the rewards, starts the next fight and returns
    /// nil; otherwise returns the summary the result panel shows.
    func conclude() -> BattleSummary? {
        guard let result = outcome else { return nil }
        guard case .campaign(let stage) = context, var session = repeatSession else {
            return finish()
        }
        let stageOutcome = store.finishCampaignBattle(stage: stage, result: result)
        session.completed += 1
        if result.outcome == .victory { session.wins += 1 }
        session.drachma += stageOutcome.drachma
        session.unitExperience += stageOutcome.unitExperience
        session.divinity += stageOutcome.divinityEarned
        session.relics += stageOutcome.relicsEarned
        for (id, count) in stageOutcome.essencesEarned { session.essences[id, default: 0] += count }
        for (id, count) in stageOutcome.scrollsEarned { session.scrolls[id, default: 0] += count }
        for (id, count) in stageOutcome.stonesEarned { session.stones[id, default: 0] += count }
        for (id, count) in stageOutcome.aetherEarned { session.aether[id, default: 0] += count }
        session.boonCaches += stageOutcome.boonCachesEarned
        session.playerLevelsGained += stageOutcome.playerLevelsGained
        if stageOutcome.playerLevelsGained > 0 { session.newPlayerLevel = stageOutcome.newPlayerLevel }
        session.lastStars = stageOutcome.stars

        if result.outcome != .victory {
            session.stoppedBecause = "Stopped after a defeat."
        } else if session.completed < session.requested, store.player.wallet.energy < EventCalendar.energyCost(for: stage) {
            session.stoppedBecause = "Out of energy."
        }
        repeatSession = session
        guard !session.isFinished else { return repeatSummary(session) }

        guard let next = store.startCampaignBattle(stage: stage) else {
            session.stoppedBecause = "The next run could not start."
            repeatSession = session
            return repeatSummary(session)
        }
        repeatBanner = "Run \(session.completed + 1) of \(session.requested)"
        restart(with: next)
        return nil
    }

    /// Swaps in a fresh engine for the same stage and plays it from the top;
    /// the scene is rebuilt, the HUD reset, the log kept.
    private func restart(with next: BattleEngine) {
        engine = next
        // This run's team, as the settle of the last one left it: the level
        // its plates' badges start at.
        snapshotTeam()
        engine.autoBattle = true
        autoBattle = true
        outcome = nil
        awaitingActor = nil
        selectedSkillSlot = nil
        highlightedTarget = nil
        pendingEvents = []
        waveIndex = 1
        tallies = [:]
        lastHitter = [:]
        log.append("— Again")
        displayedCombatants = engine.combatants
        hasBegun = false
        begin()
        // An auto-repeat run goes on without a reckoning, so the music the
        // last run's end stopped starts again here.
        AudioLibrary.shared.playMusic(.battle)
    }

    private func repeatSummary(_ session: RepeatSession) -> BattleSummary {
        var lines: [BattleSummary.Line] = [
            .init(icon: "repeat", label: "Runs", value: "\(session.wins) won of \(session.completed)")
        ]
        if session.drachma > 0 {
            lines.append(.init(icon: "circle.hexagongrid.fill", label: "Drachma", value: "+\(session.drachma)"))
        }
        if session.unitExperience > 0 {
            lines.append(.init(icon: "arrow.up.circle.fill", label: "Unit EXP", value: "+\(session.unitExperience)"))
        }
        if session.divinity > 0 {
            lines.append(.init(icon: "sparkles", label: "Divinity", value: "+\(session.divinity)"))
        }
        if !session.relics.isEmpty {
            let byGrade = Dictionary(grouping: session.relics, by: \.grade)
            let text = byGrade.keys.sorted(by: >).map { "\($0)★ ×\(byGrade[$0]?.count ?? 0)" }.joined(separator: ", ")
            lines.append(.init(icon: "shield.lefthalf.filled", label: "Relics", value: text))
        }
        for (id, count) in session.stones.sorted(by: { $0.key < $1.key }) {
            lines.append(.init(icon: "diamond.fill", label: RelicStone.from(id: id)?.displayName ?? id, value: "+\(count)"))
        }
        for (id, count) in session.aether.sorted(by: { $0.key < $1.key }) {
            lines.append(.init(icon: "circle.hexagonpath.fill", label: Aether.name(for: id), value: "+\(count)"))
        }
        if !session.boonCaches.isEmpty {
            lines.append(.init(icon: "seal.fill", label: "Boon caches", value: "×\(session.boonCaches.count)"))
        }
        for (id, count) in session.essences.sorted(by: { $0.key < $1.key }) {
            lines.append(.init(icon: "drop.triangle.fill", label: EssenceCatalog.name(for: id), value: "+\(count)"))
        }
        for (id, count) in session.scrolls.sorted(by: { $0.key < $1.key }) {
            lines.append(.init(icon: "scroll.fill", label: ScrollType(rawValue: id)?.displayName ?? id, value: "+\(count)"))
        }
        if let why = session.stoppedBecause {
            lines.append(.init(icon: "exclamationmark.triangle.fill", label: why, value: ""))
        }
        var loot: [BattleSummary.Loot] = []
        if session.drachma > 0 {
            loot.append(.init(glyph: "circle.hexagongrid.fill", title: "Drachma", amount: "+\(session.drachma.formatted())", tint: .gold))
        }
        if session.unitExperience > 0 {
            loot.append(.init(glyph: "arrow.up.circle.fill", title: "Unit EXP", amount: "+\(session.unitExperience.formatted())", tint: .verdigris))
        }
        if session.divinity > 0 {
            loot.append(.init(glyph: "sparkles", title: "Divinity", amount: "+\(session.divinity)", tint: .marble))
        }
        for relic in session.relics {
            loot.append(.init(glyph: relic.set.glyph, title: relic.displayName, amount: nil, tint: .gold, stars: relic.grade, relic: relic))
        }
        for (id, count) in session.stones.sorted(by: { $0.key < $1.key }) {
            guard let stone = RelicStone.from(id: id) else { continue }
            loot.append(.init(glyph: stone.kind.glyph, title: stone.displayName, amount: "+\(count)", tint: .rarity(stone.tier.quality.rarity)))
        }
        for cache in session.boonCaches {
            loot.append(.init(glyph: "seal.fill", title: cache.displayName, amount: "×1", tint: .gold,
                              stars: cache.grade, key: "boon_cache_\(cache.grade)"))
        }
        for (id, count) in session.aether.sorted(by: { $0.key < $1.key }) {
            loot.append(.init(glyph: "circle.hexagonpath.fill", title: Aether.name(for: id), amount: "+\(count)",
                              tint: Aether.element(of: id).map { .element($0) } ?? .marble, key: id))
        }
        for (id, count) in session.essences.sorted(by: { $0.key < $1.key }) {
            let element = Element(rawValue: id.split(separator: "_").dropFirst().first.map(String.init) ?? "")
            loot.append(.init(glyph: "drop.triangle.fill", title: EssenceCatalog.name(for: id), amount: "+\(count)", tint: element.map { .element($0) } ?? .verdigris))
        }
        for (id, count) in session.scrolls.sorted(by: { $0.key < $1.key }) {
            if let scroll = ScrollType(rawValue: id) {
                loot.append(.init(glyph: scroll.glyph, title: scroll.displayName, amount: "+\(count)", tint: .scroll(scroll)))
            }
        }
        let (stats, mvp) = reckoning()
        let won = session.wins > 0
        var summary = BattleSummary(
            outcome: won ? .victory : .defeat, lines: lines, stars: 0,
            title: "\(session.wins) of \(session.completed) runs won",
            turns: outcome?.turnsTaken ?? 0,
            damageDealt: outcome?.totalDamageDealt ?? 0, damageTaken: outcome?.totalDamageTaken ?? 0,
            unitStats: stats, mvpID: mvp, loot: won ? loot : []
        )
        // The beat at the end is the LAST run's field, with the last run's
        // bars on its plates (`unitsAtStart` is taken again for every run);
        // the demigod's level-up is the whole session's, as one (W1.6, W1.7).
        summary.experience = experienceGains()
        summary.levelUp = levelUp(gained: session.playerLevelsGained, newLevel: session.newPlayerLevel)
        summary.stampStars = session.lastStars
        return summary
    }

    // MARK: - The end of the fight on the field (Docs/FEEL.md W1.6, W1.7)

    /// Each of the player's units as it stood when THIS run began, by the
    /// unit's own id: where its plate's gold bar starts in the triumph.
    /// Campaign fights only. Taken at `init` and again by `restart` for every
    /// run of an auto-repeat, because the plate's badge shows the level the
    /// run's own engine was built with (`Combatant.level`): measured from the
    /// session's start, a unit that levelled in runs 3 and 8 of ten had its
    /// badge bumped two levels past its real one in the last run's triumph
    /// (review, 2026-09-24).
    private var unitsAtStart: [UUID: Unit] = [:]

    private func snapshotTeam() {
        unitsAtStart = [:]
        guard case .campaign = context else { return }
        for combatant in engine.combatants where combatant.side == .player {
            guard let id = combatant.sourceUnitID, let unit = store.player.unit(id) else { continue }
            unitsAtStart[id] = unit
        }
    }

    /// What the fight did to each SURVIVOR's experience, for the gold bars
    /// its plate fills on the field (`BattleSceneController.celebrate`):
    /// keyed by the COMBATANT's id — the scene's own key, fresh every run —
    /// and measured from the unit as it stood at the start to the unit as
    /// the settle left it. Call it after the settle. The arena, a guild war
    /// and a draft bout pay no unit experience, so their survivors pose with
    /// their health still up (an empty map: "units missing from the map just
    /// pose").
    private func experienceGains() -> [UUID: ExperienceGain] {
        guard case .campaign = context else { return [:] }
        var gains: [UUID: ExperienceGain] = [:]
        for combatant in displayedCombatants where combatant.side == .player && combatant.isAlive {
            guard let id = combatant.sourceUnitID,
                  let before = unitsAtStart[id],
                  let after = store.player.unit(id) else { continue }
            gains[combatant.id] = BattleSummary.experienceGain(before: before, after: after)
        }
        return gains
    }

    /// The demigod's level-up for the beat between the reckoning and the
    /// chest, or nil when the settle raised no level. The bar it names is
    /// the wallet the settle left: every level-up fills it.
    private func levelUp(gained: Int, newLevel: Int) -> PlayerLevelUp? {
        guard gained > 0, newLevel > gained else { return nil }
        return PlayerLevelUp.between(newLevel - gained, newLevel, maxEnergy: store.player.wallet.maxEnergy)
    }

    /// `onAppear` can fire more than once for the same view; starting the
    /// engine twice would replay the opening turn, so it is guarded.
    private var hasBegun = false

    func begin() {
        guard !hasBegun else { return }
        hasBegun = true
        sceneController.build(combatants: engine.combatants, environment: context.environment)
        warmArrivals()
        consume(engine.start())
    }

    // MARK: - The way in (Docs/FEEL.md W2.24)

    /// The fight's first build, under the stage card: it holds its queue
    /// until the card leaves (`BattleSceneController.revealField`) and draws
    /// everything the fight can play once under it (`effectPlan`). Guarded
    /// as `begin()` is, so a second call cannot leave the hold set for an
    /// auto-repeat's next build.
    func beginUnderCard() {
        guard !hasBegun else { return }
        sceneController.holdsForStageCard = true
        sceneController.predrawPlan = effectPlan
        begin()
    }

    /// What the stage card says, read once as the fight opens: the realm
    /// and the place over the stage's name (or the rival's), the waves and
    /// the tier, and the field's power beside the team's.
    private(set) lazy var stageCard: StageCardInfo = makeStageCard()

    private func makeStageCard() -> StageCardInfo {
        let place: String = context.environment.displayName.uppercased()
        let painting: String = context.environment.backdropName
        #if DEBUG
        // The skill reel's card names the families it plays, in the order
        // they cast, and carries no powers: it is a showing, not a fight.
        if let reel = skillReel {
            return StageCardInfo(
                eyebrow: "SKILL REEL · \(place)", title: context.title, detail: reel.roll,
                theirLabel: "", theirPower: nil, ourPower: nil, painting: painting
            )
        }
        #endif
        let team: Int = engine.combatants.filter { $0.side == .player }.reduce(0) { total, fighter in
            guard let id = fighter.sourceUnitID, let unit = store.resolved(id) else { return total }
            return total + unit.power
        }
        let ours: Int? = team > 0 ? team : nil
        switch context {
        case .campaign(let stage):
            var eyebrow = place
            if let chapter = StageDatabase.chapter(stage.chapterID) {
                eyebrow = "\(chapter.realmName.uppercased()) · \(place)"
            }
            var details: [String] = [waveCount == 1 ? "1 WAVE" : "\(waveCount) WAVES"]
            let tier = CampaignDifficulty.split(stage.id).difficulty
            if tier != .normal { details.append(tier.displayName.uppercased()) }
            if stage.isBoss { details.append("BOSS") }
            return StageCardInfo(
                eyebrow: eyebrow, title: stage.name, detail: details.joined(separator: "  ·  "),
                theirLabel: "STAGE POWER", theirPower: stage.recommendedPower > 0 ? stage.recommendedPower : nil,
                ourPower: ours, painting: painting
            )
        case .arena(let opponent):
            return StageCardInfo(
                eyebrow: "THE ARENA · \(place)", title: opponent.name,
                detail: "\(opponent.tier.displayName.uppercased())  ·  \(opponent.points.formatted()) POINTS",
                theirLabel: "RIVAL POWER", theirPower: opponent.power > 0 ? opponent.power : nil,
                ourPower: ours, painting: painting
            )
        case .guildWar(let target):
            let theirs: Int = target.opponentTeam.reduce(0) { $0 + $1.power }
            return StageCardInfo(
                eyebrow: "GUILD WAR · \(place)", title: target.profile.name,
                detail: "LEVEL \(target.profile.level)  ·  \(target.pointsForWin) POINTS FOR A WIN",
                theirLabel: "RIVAL POWER", theirPower: theirs > 0 ? theirs : nil,
                ourPower: ours, painting: painting
            )
        case .draft(let bout):
            let theirs: Int = bout.rivalTeam.reduce(0) { $0 + $1.power }
            let drafted: Int = bout.playerTeam.reduce(0) { $0 + $1.power }
            return StageCardInfo(
                eyebrow: "THE DRAFT ARENA · \(place)", title: bout.rivalName,
                detail: "RATING \(bout.rivalRating.formatted())",
                theirLabel: "RIVAL POWER", theirPower: theirs > 0 ? theirs : nil,
                ourPower: drafted > 0 ? drafted : ours, painting: painting
            )
        }
    }

    /// Everything this fight can draw — every wave's fighters, the later
    /// waves' read off their blueprints — for the pre-draw under the stage
    /// card (`EffectPlan`, `VFXLibrary.predraw`).
    var effectPlan: EffectPlan {
        var fighters: [PlannedFighter] = engine.combatants.map { fighter in
            PlannedFighter(element: fighter.element, melee: fighter.model.melee, boss: fighter.isBoss,
                           auraHex: fighter.model.auraHex, effects: fighter.skills.map(\.vfx))
        }
        if case .campaign(let stage) = context {
            for spawn in stage.laterWaves.flatMap({ $0 }) {
                guard let blueprint = UnitDatabase.blueprint(spawn.blueprintID) else { continue }
                let boss: Bool = blueprint.archetype == .primordial || blueprint.model.height >= 3.0
                fighters.append(PlannedFighter(element: blueprint.element, melee: blueprint.model.melee, boss: boss,
                                               laterWave: true, auraHex: blueprint.model.auraHex,
                                               effects: blueprint.skills.map(\.vfx)))
            }
        }
        return EffectPlan.of(fighters)
    }

    /// Every later wave's figures and clips — the walk its arrivals take
    /// onto their marks among them (Docs/FEEL.md W2.10) — parsed off the
    /// main thread while the first wave fights, as the briefing's warm pass
    /// already does for a fight it launches (`CampaignView.warmModels`); a
    /// fight begun any other way arrived with nothing warmed and parsed each
    /// wave on the main thread as it walked on. Cheap when warm: the caches
    /// answer first.
    private func warmArrivals() {
        guard case .campaign(let stage) = context, !stage.laterWaves.isEmpty else { return }
        let forms = stage.laterWaves.flatMap { $0 }.compactMap { spawn -> (spec: ModelSpec, awakened: Bool)? in
            guard let blueprint = UnitDatabase.blueprint(spawn.blueprintID) else { return nil }
            // Drawn awakened when awakened or a boss, as `UnitNode` draws it.
            let lit = spawn.awakened || blueprint.archetype == .primordial || blueprint.model.height >= 3.0
            return (spec: blueprint.model, awakened: lit)
        }
        let crowded = ModelLibrary.detail(forCombatantCount: engine.combatants.count) == .low
        ModelLibrary.shared.warm(forms: forms, crowded: crowded)
    }

    /// Set the first time a boss speaks, for the reason `hasBegun` exists.
    private var hasSpoken = false

    /// The boss's line, once, the moment the boss is on the field: at the
    /// opening when it stands in the first wave, and otherwise when its wave
    /// walks on — a boss that spoke before it arrived was announcing a mob
    /// fight.
    ///
    /// Only a chapter's boss stage and a raid have one (`StageDatabase.bossLine`);
    /// everything else returns without touching `bossSpeech`, so an ordinary
    /// fight is exactly as it was. Guarded on `hasSpoken` for the same reason
    /// `begin()` is guarded: `onAppear` fires more than once, and an
    /// auto-repeat run keeps this view alive across fights — the line belongs
    /// to walking in, not to every lap. A GIANT (`Combatant.isBoss`) says it
    /// on its entrance's ribbon (Docs/FEEL.md W2.11, `entranceCard(for:)`)
    /// rather than in a band of its own over the ribbon.
    func announceBoss(ifPresentIn combatants: [Combatant]) {
        guard !hasSpoken else { return }
        guard case .campaign(let stage) = context,
              let boss = StageDatabase.bossLine(for: stage),
              waveIndex == stage.speakerWave(of: boss.blueprintID),
              let speaker = combatants.first(where: { $0.blueprintID == boss.blueprintID && $0.side == .opponent }),
              let blueprint = UnitDatabase.blueprint(boss.blueprintID) else { return }
        hasSpoken = true
        guard !speaker.isBoss else { return }
        bossSpeech = BossSpeech(
            portrait: blueprint.model.portraitName(awakened: false),
            speaker: blueprint.name,
            line: boss.line,
            accentHex: blueprint.element.accentHex
        )
    }

    /// The words on a boss's entrance ribbon (W2.11): its name and epithet,
    /// its line when it is the stage's speaker, and a Titan's weakness at
    /// this moment. Read off the engine, which has placed the boss before
    /// the HUD's copy of the field has caught up with it.
    func entranceCard(for id: UUID) -> BossEntranceCard? {
        guard let boss = engine.combatants.first(where: { $0.id == id })
                ?? displayedCombatants.first(where: { $0.id == id }) else { return nil }
        var line: String?
        if case .campaign(let stage) = context, let spoken = StageDatabase.bossLine(for: stage),
           spoken.blueprintID == boss.blueprintID {
            line = spoken.line
        }
        return BossEntranceCard(
            name: boss.name,
            epithet: UnitDatabase.blueprint(boss.blueprintID)?.epithet ?? "",
            line: line,
            weakness: engine.raidWeakness(for: id)
        )
    }

    // MARK: - Player input

    var playerTeam: [Combatant] { displayedCombatants.filter { $0.side == .player } }
    var opponentTeam: [Combatant] { displayedCombatants.filter { $0.side == .opponent } }

    // MARK: - What a raid boss is doing
    //
    // Read straight off the engine rather than mirrored into a @Published
    // field. A raid's barrier, weakness and enrage change on the BOSS's turn,
    // and `displayedCombatants` deliberately lags the engine so health bars
    // drain with the animation; mirroring these would have made the barrier
    // and the health disagree with each other on screen. The HUD reads them
    // during a render that `displayedCombatants` has already invalidated, so
    // they refresh with everything else.

    /// The barrier on a raid boss, 0...1 of its full size, or nil for a boss
    /// that carries none. The size in points is the boss's own, so a barrier
    /// at full always reads full whatever the boss's health is.
    func raidBarrierFraction(_ id: UUID) -> Double? {
        guard let bar = engine.raidBarrier(for: id), bar.maximum > 0 else { return nil }
        return min(1, max(0, bar.remaining / bar.maximum))
    }

    /// The element the boss is open to at this moment, or nil if it is not a
    /// raid boss or its weakness has not rotated in yet.
    func raidWeakness(_ id: UUID) -> Element? { engine.raidWeakness(for: id) }

    /// What the boss's enrage multiplies its damage by. 1 until its clock runs
    /// out, and worth showing only above 1.
    func raidEnrage(_ id: UUID) -> Double { engine.raidEnrage(for: id) }

    /// Skills the waiting actor can use, with their cooldown state.
    var availableSkills: [SkillOption] {
        guard let actor = awaitingActor else { return [] }
        return actor.skills.indices.compactMap { slot in
            let skill = actor.skills[slot]
            guard !skill.isPassive else { return nil }
            return SkillOption(
                slot: slot,
                skill: skill,
                cooldown: actor.cooldowns.indices.contains(slot) ? actor.cooldowns[slot] : 0
            )
        }
    }

    /// Whether the player has to aim this one, or it picks its own targets.
    static func needsTarget(_ skill: Skill) -> Bool {
        switch skill.target {
        case .singleEnemy, .lowestHealthEnemy, .singleAlly, .deadAlly: return true
        default: return false
        }
    }

    /// The first tap ARMS a skill. The second uses it.
    ///
    /// It used to be that a skill picking its own targets fired on the first
    /// tap, and only a single-target one waited. The owner met that on
    /// 2026-09-10: "when I click skill 3 for Anubis, it just immediately uses
    /// it instead of showing me what it is first." He is right, and the
    /// inconsistency was the worst part of it — two of a unit's skills paused
    /// to be read and the third went off, so the one skill a player is least
    /// likely to know is the one he could not look at without spending a turn.
    ///
    /// Now every skill arms first and shows its words in the actor plate. A
    /// second tap on the SAME skill commits it, which is also what tapping a
    /// target does for the ones that need one, so the rhythm is the same
    /// either way: choose, read, commit.
    func selectSkill(_ slot: Int) {
        guard let actor = awaitingActor, actor.isSkillReady(slot) else { return }
        guard let skill = actor.skill(at: slot) else { return }

        if selectedSkillSlot == slot {
            if Self.needsTarget(skill) {
                if let target = highlightedTarget { submit(slot: slot, target: target) }
            } else {
                submit(slot: slot, target: nil)
            }
            return
        }

        selectedSkillSlot = slot
        // Pre-aim at the most obvious target so the second tap works without
        // choosing one; a skill that needs no target simply has none.
        highlightedTarget = Self.needsTarget(skill) ? defaultTarget(for: skill, actor: actor) : nil
    }

    func tapUnit(_ combatantID: UUID) {
        guard let actor = awaitingActor, let slot = selectedSkillSlot else { return }
        let legal = engine.validTargets(for: actor.id, skillSlot: slot)
        guard legal.contains(combatantID) else { return }
        submit(slot: slot, target: combatantID)
    }

    /// Confirms the currently highlighted target.
    func confirmTarget() {
        guard let slot = selectedSkillSlot, let target = highlightedTarget else { return }
        submit(slot: slot, target: target)
    }

    func cancelTargeting() {
        selectedSkillSlot = nil
        highlightedTarget = nil
    }

    private func defaultTarget(for skill: Skill, actor: Combatant) -> UUID? {
        let legal = engine.validTargets(for: actor.id, skillSlot: skill.slot)
        let candidates = displayedCombatants.filter { legal.contains($0.id) }
        if skill.target.hitsEnemies {
            return candidates.min(by: { $0.currentHealth < $1.currentHealth })?.id
        }
        return candidates.min(by: { $0.healthFraction < $1.healthFraction })?.id
    }

    private func submit(slot: Int, target: UUID?) {
        guard let actor = awaitingActor else { return }
        awaitingActor = nil
        selectedSkillSlot = nil
        highlightedTarget = nil
        let events = engine.submit(
            BattleAction(actorID: actor.id, skillSlot: slot, targetID: target)
        )
        consume(events)
    }

    private func takeAutoTurn() {
        guard let actor = awaitingActor else { return }
        var rng = SeededRandom(seed: UInt64(actor.attackBar * 1_000_000) &+ UInt64(engine.turnNumber))
        let action = AIController.chooseAction(
            actorIndex: engine.combatants.firstIndex(where: { $0.id == actor.id }) ?? 0,
            combatants: engine.combatants,
            engine: engine,
            rng: &rng
        )
        awaitingActor = nil
        consume(engine.submit(action))
    }

    // MARK: - Playback

    private func consume(_ events: [BattleEvent]) {
        guard !events.isEmpty else {
            settleAfterPlayback()
            return
        }
        pendingEvents = events
        isPlayingBack = true
        // The cards of the splashes these events may bring, decoded while
        // the turn plays up to them (Docs/FEEL.md W2.1).
        sceneController.warmSplashCards(for: splashCasters(in: events))
        sceneController.enqueue(events)
    }

    /// The fighters whose ultimate's splash may play before the next batch
    /// (Docs/FEEL.md W2.1): every one these events cast, and the unit the
    /// engine now waits on when its ultimate is ready — the player may
    /// choose it, and auto may, and its cast is presented the moment it is
    /// chosen, so its card must be decoded before then. Read off the
    /// engine, which is already at the turn these events end on; a later
    /// wave's arrival is there too, before the scene has placed it.
    ///
    /// The waiting unit's ultimate is found by the clip its cast will carry
    /// (`Skill.presentedClip`, 2026-09-25), which is what the scene keys the
    /// splash on — not by the kit's stored `animation`, which the engine no
    /// longer puts on a cast.
    private func splashCasters(in events: [BattleEvent]) -> [Combatant] {
        var ids: [UUID] = []
        for event in events {
            if case .skillCast(let actor, _, _, _, _, let animation, _) = event, animation == .ultimate,
               !ids.contains(actor) {
                ids.append(actor)
            }
        }
        if let waiting = engine.awaitingActor, !ids.contains(waiting),
           let actor = engine.combatants.first(where: { $0.id == waiting }),
           let slot = actor.skills.firstIndex(where: { $0.presentedClip == .ultimate && !$0.isPassive }),
           actor.isSkillReady(slot) {
            ids.append(waiting)
        }
        return ids.compactMap { id in engine.combatants.first(where: { $0.id == id }) }
    }

    /// Jumps to the end of the current turn's animation.
    func skipAnimation() {
        sceneController.flush(combatants: engine.combatants)
    }

    /// Abandons the battle. Campaign energy is not refunded once a turn has
    /// resolved, which is the standard rule and is stated on the confirm dialog.
    ///
    /// The fight stops where it stands: the turn waiting for the player is
    /// withdrawn, and `settleAfterPlayback` hands out no other (a forfeit on
    /// auto used to play on underneath, and since the end of a fight is shown
    /// on the field — DEFEAT over the drained set, Docs/FEEL.md W1.7 — that
    /// would be the enemies fighting on under the word, and a win arriving
    /// after the loss had been settled).
    func forfeit() {
        guard outcome == nil else { return }
        awaitingActor = nil
        selectedSkillSlot = nil
        highlightedTarget = nil
        // And the turn being played stops where it stands, rather than
        // playing on under DEFEAT (`BattleSceneController.halt`).
        sceneController.halt()
        isPlayingBack = false
        outcome = BattleResult(
            outcome: .defeat,
            turnsTaken: engine.turnNumber,
            survivorFraction: 0,
            totalDamageDealt: 0,
            totalDamageTaken: 0,
            seed: 0
        )
    }

    private func settleAfterPlayback() {
        isPlayingBack = false
        displayedCombatants = engine.combatants
        sceneController.syncPlates(combatants: engine.combatants)
        refreshTurnOrder()

        if let result = engine.result {
            // A forfeit during the last turn's playback has already ended
            // the fight; the engine's own end does not overwrite the loss
            // (it would be settled a second time).
            if outcome == nil { outcome = result }
            return
        }
        // Forfeited: no turn is handed out after the loss (`forfeit`).
        guard outcome == nil else { return }

        if let waitingID = engine.awaitingActor,
           let actor = engine.combatants.first(where: { $0.id == waitingID }) {
            awaitingActor = actor
            if autoBattle {
                takeAutoTurn()
            } else {
                #if DEBUG
                if castTourUltimate(for: actor) { return }
                if takeReelTurn(actor) { return }
                #endif
                // One soft chime: the player's turn, heard (FEEL.md W1.4).
                AudioLibrary.shared.play(.turnChime, volume: 0.35)
                armBasicAttack(for: actor)
            }
        }
    }

    #if DEBUG
    /// Under the CI tour's `-tour-cutin` the player's first turn with an
    /// ultimate ready casts it at once — aimed as a tap on its square would
    /// aim it — so the step photographs a real cast's splash and its
    /// spotlight (`BattleSceneController`'s lab holds each for its frame).
    private static let touringCutIn = ProcessInfo.processInfo.arguments.contains("-tour")
        && ProcessInfo.processInfo.arguments.contains("-tour-cutin")
    private var tourUltimateCast = false

    private func castTourUltimate(for actor: Combatant) -> Bool {
        guard Self.touringCutIn, !tourUltimateCast,
              let slot = actor.skills.indices.first(where: { index in
                  let skill = actor.skills[index]
                  return !skill.isPassive && skill.presentedClip == .ultimate && actor.isSkillReady(index)
              }),
              let skill = actor.skill(at: slot) else { return false }
        tourUltimateCast = true
        let target = Self.needsTarget(skill) ? defaultTarget(for: skill, actor: actor) : nil
        submit(slot: slot, target: target)
        return true
    }

    // MARK: The skill reel (TourView's `skill_reel` step)

    /// The reel this fight plays (`playing(_:stage:store:)`), or nil for
    /// every other fight.
    private(set) var skillReel: SkillReel?
    /// Where the reel stands: which family is at the front, the slots it
    /// has cast, how many casts the reel has made, and when it began.
    private var reelPhase: ReelPhase = .waiting
    private var reelSegment = 0
    private var reelSlotsCast: [Int] = []
    private var reelCasts = 0
    private var reelBegan = Date()
    /// The next turn waits `reelSegmentLead` first: a family has just
    /// stepped up, under its banner.
    private var reelLeadOwed = false

    /// The reel's clock. It waits for the stage to be seen and the job's
    /// recorder to be running (`holdReelForRecorder`), then plays its
    /// families one after another, and is done when the last one's kit is
    /// spent: the fight then waits on a turn nobody takes.
    private enum ReelPhase {
        case waiting, holding, running, done
    }

    /// The file the CI job touches in the app's own tmp folder once its
    /// recorder is running (`xcrun simctl get_app_container … data`), and
    /// the longest the reel waits for it: without it the first cast would
    /// be spent before the video began, or the reel would open on seconds
    /// of an idle field.
    private static let reelGoFile = "skill-reel-go"
    private static let reelGoLimit: TimeInterval = 15
    /// From the go to the first family's banner, the banner to its first
    /// cast, a family's banner (put up as its field is built, over the
    /// fight's own 1.2-s opening) to its first cast, a square armed to its
    /// cast, and a spent kit to the next family's field: together about
    /// eight seconds of a reel of five families, and the four new fields'
    /// openings five more. The rest of its minute and a quarter is casts.
    private static let reelAfterGo: TimeInterval = 0.8
    private static let reelFirstLead: TimeInterval = 1.0
    private static let reelSegmentLead: TimeInterval = 0.3
    private static let reelCastGap: TimeInterval = 0.25
    private static let reelSegmentGap: TimeInterval = 0.3

    private static var reelGoPath: String {
        FileManager.default.temporaryDirectory.appendingPathComponent(reelGoFile).path
    }

    /// The skill reel's fight (Docs/PLAN.md *Skills that look like
    /// themselves*): the first family's field on the real engine, at ×1,
    /// fought by hand with the reel's hand on every turn (`takeReelTurn`).
    /// A campaign fight in form, for the stage's set and card, that never
    /// ends: the dummies outlast every kit and never act, so nothing is
    /// ever settled into the save.
    static func playing(_ reel: SkillReel, stage: Stage, store: GameStore) -> BattleViewModel? {
        guard let first = reel.segments.first else { return nil }
        let engine = BattleEngine(
            playerTeam: first.playerTeam,
            opponentTeam: first.opponentTeam,
            mode: .campaign,
            seed: reel.seed
        )
        let model = BattleViewModel(engine: engine, context: .campaign(stage), store: store)
        model.skillReel = reel
        model.autoBattle = false
        model.speed = 1
        // Every figure and every clip the reel will play, parsed off the
        // main thread while the card stands, as the briefing warms a fight
        // it launches (`CampaignView.warmModels`): a clip first parsed at
        // its cast is a hitch in the middle of the video.
        let fielded: [ResolvedUnit] = reel.segments.flatMap { $0.playerTeam } + first.opponentTeam
        let forms = fielded.map { (spec: $0.blueprint.model, awakened: $0.unit.isAwakened) }
        let crowded: Bool = ModelLibrary.detail(forCombatantCount: engine.combatants.count) == .low
        ModelLibrary.shared.warm(forms: forms, crowded: crowded)
        // A go left by an earlier launch of this install would start the
        // reel before this launch's recorder.
        try? FileManager.default.removeItem(atPath: reelGoPath)
        let casts: Int = reel.segments.reduce(0) { $0 + $1.castCount }
        print("[Tour] reel: \(reel.segments.count) families, \(casts) casts planned: "
              + reel.segments.map(\.banner).joined(separator: ", "))
        return model
    }

    /// The reel's hand on a player's turn, or false to leave the turn to the
    /// player (no reel, or the reel done). The family at the front casts
    /// the next skill of its kit in slot order — basic, second, third —
    /// each a breath after its square is armed; a family whose kit is spent
    /// hands the field to the next (`stepUpReel`); and a unit the reel is
    /// not showing that gets a turn anyway (a bar push) takes its basic, so
    /// the fight moves on and the console says so.
    private func takeReelTurn(_ actor: Combatant) -> Bool {
        guard let reel = skillReel else { return false }
        switch reelPhase {
        case .done:
            return false
        case .holding:
            return true
        case .waiting:
            reelPhase = .holding
            print("[TourCue] reel-ready")
            holdReelForRecorder(since: Date())
            return true
        case .running:
            break
        }
        if reelLeadOwed {
            reelLeadOwed = false
            resumeReel(after: Self.reelSegmentLead)
            return true
        }
        guard reel.segments.indices.contains(reelSegment) else { return false }
        let segment = reel.segments[reelSegment]
        guard actor.side == .player, actor.slot == segment.caster else {
            castForReel(actor, slot: 0, outOfTurn: true)
            return true
        }
        if let slot = nextReelSlot(for: actor) {
            reelSlotsCast.append(slot)
            castForReel(actor, slot: slot, outOfTurn: false)
            return true
        }
        if reelSegment + 1 < reel.segments.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.reelSegmentGap) { [weak self] in
                self?.stepUpReel()
            }
            return true
        }
        reelPhase = .done
        let clock: String = String(format: "%.1f", Date().timeIntervalSince(reelBegan))
        print("[Tour] reel: done, \(reelCasts) casts in \(clock) s")
        print("[TourCue] reel-done")
        return false
    }

    /// The first turn is up and the stage has been seen (the card has
    /// lifted: its hold keeps the queue until then), and `[TourCue]
    /// reel-ready` has told the CI job to start its recorder: the reel waits
    /// for the job's word that it is running — its file in the app's tmp
    /// folder — or `reelGoLimit`, whichever comes first, looking ten times
    /// a second. Then `[TourCue] reel-go`, the first family's banner, and
    /// its first cast.
    private func holdReelForRecorder(since asked: Date) {
        let heard: Bool = FileManager.default.fileExists(atPath: Self.reelGoPath)
        let waited: Double = Date().timeIntervalSince(asked)
        guard heard || waited >= Self.reelGoLimit else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.holdReelForRecorder(since: asked)
            }
            return
        }
        try? FileManager.default.removeItem(atPath: Self.reelGoPath)
        guard reelPhase == .holding, let reel = skillReel, let first = reel.segments.first else { return }
        reelPhase = .running
        reelBegan = Date()
        let after: String = String(format: "%.1f", waited)
        let why: String = heard ? "the recorder is running, \(after) s after ready" : "no word from a recorder in \(after) s"
        print("[TourCue] reel-go (\(why))")
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reelAfterGo) { [weak self] in
            guard let self, self.reelPhase == .running else { return }
            self.repeatBanner = first.banner
            self.resumeReel(after: Self.reelFirstLead)
        }
    }

    /// Takes the turn still waiting on the reel, `delay` from now.
    private func resumeReel(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, let actor = self.awaitingActor else { return }
            if !self.takeReelTurn(actor) {
                // The reel ended on this turn: it is the player's, as any
                // other fight's would be.
                self.armBasicAttack(for: actor)
            }
        }
    }

    /// The caster's next skill in slot order that it has not cast in this
    /// segment: ready, not a passive, and with a target when it needs one
    /// (a revive with nobody fallen is passed over).
    private func nextReelSlot(for actor: Combatant) -> Int? {
        actor.skills.indices.first { slot in
            guard !reelSlotsCast.contains(slot), actor.isSkillReady(slot), let skill = actor.skill(at: slot) else {
                return false
            }
            return !Self.needsTarget(skill) || reelTarget(slot: slot, actor: actor) != nil
        }
    }

    /// Who a reel cast is aimed at: a blow at one enemy lands on the middle
    /// of the enemy line, where the home camera looks; a skill for one ally
    /// on the caster's nearest neighbour, so its effect crosses the line.
    private func reelTarget(slot: Int, actor: Combatant) -> UUID? {
        guard let skill = actor.skill(at: slot) else { return nil }
        let legal: [UUID] = engine.validTargets(for: actor.id, skillSlot: slot)
        let candidates: [Combatant] = engine.combatants.filter { legal.contains($0.id) }
        if skill.target.hitsEnemies {
            let line: [Combatant] = candidates.sorted { $0.slot < $1.slot }
            return line.isEmpty ? nil : line[line.count / 2].id
        }
        let others: [Combatant] = candidates.filter { $0.id != actor.id }
        let nearest: Combatant? = others.min { abs($0.slot - actor.slot) < abs($1.slot - actor.slot) }
        return nearest?.id ?? candidates.first?.id
    }

    /// Arms the square (the HUD shows it lit, its target marked), says in
    /// the console what the cast is and which clip it asks for — and which
    /// clip will really play, when the family ships no file for it
    /// (`ModelLibrary.resolvedClip`) — and casts it `reelCastGap` later.
    private func castForReel(_ actor: Combatant, slot: Int, outOfTurn: Bool) {
        guard let skill = actor.skill(at: slot) else { return }
        let target: UUID? = Self.needsTarget(skill) ? reelTarget(slot: slot, actor: actor) : nil
        selectedSkillSlot = slot
        highlightedTarget = target
        reelCasts += 1
        let asked: AnimationClip = skill.presentedClip
        let asset: String = ModelLibrary.shared.clipAsset(for: actor.model, awakened: actor.isAwakened)
        let plays: AnimationClip = ModelLibrary.shared.resolvedClip(asked, for: asset)
        let clip: String = plays == asked ? asked.rawValue : "\(asked.rawValue), playing \(plays.rawValue)"
        let hits: Int = skill.damage?.hits ?? 0
        let verb: String = outOfTurn ? "takes a turn out of the reel's order with" : "casts"
        let clock: String = String(format: "%.1f", Date().timeIntervalSince(reelBegan))
        print("[Tour] reel +\(clock) s: cast \(reelCasts), \(actor.name) \(verb) \(skill.name) "
              + "(slot \(slot + 1), \(clip), \(hits) hit(s), \(skill.vfx))")
        let id = actor.id
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.reelCastGap) { [weak self] in
            guard let self, self.awaitingActor?.id == id else { return }
            self.submit(slot: slot, target: target)
        }
    }

    /// The next family steps up: its field on a fresh engine (the same line,
    /// only it at speed), built in place the way an auto-repeat's next run
    /// is (`restart`), under its banner — never the stage card, which is
    /// the fight's first build's alone.
    private func stepUpReel() {
        guard let reel = skillReel, reelPhase == .running, reelSegment + 1 < reel.segments.count else { return }
        reelSegment += 1
        reelSlotsCast = []
        let segment = reel.segments[reelSegment]
        let seed: UInt64 = reel.seed &+ UInt64(reelSegment)
        engine = BattleEngine(
            playerTeam: segment.playerTeam,
            opponentTeam: segment.opponentTeam,
            mode: .campaign,
            seed: seed
        )
        snapshotTeam()
        outcome = nil
        awaitingActor = nil
        selectedSkillSlot = nil
        highlightedTarget = nil
        pendingEvents = []
        waveIndex = 1
        tallies = [:]
        lastHitter = [:]
        log.append("— \(segment.banner)")
        displayedCombatants = engine.combatants
        repeatBanner = segment.banner
        reelLeadOwed = true
        hasBegun = false
        let clock: String = String(format: "%.1f", Date().timeIntervalSince(reelBegan))
        print("[Tour] reel +\(clock) s: \(segment.banner) steps up")
        begin()
    }
    #endif

    /// The basic attack is in hand the moment a turn opens, aimed at the
    /// obvious target, so one tap on an enemy attacks — the genre's rhythm,
    /// and the owner's (2026-09-15): "attacks should default to skill 1, so I
    /// don't ALWAYS have to click skill 1 if 2 and 3 are on cooldown." The
    /// other skills still arm first and commit on a second tap; a tap on the
    /// armed basic's square commits it on the marked target.
    private func armBasicAttack(for actor: Combatant) {
        guard actor.isSkillReady(0), let skill = actor.skill(at: 0) else { return }
        selectedSkillSlot = 0
        highlightedTarget = Self.needsTarget(skill) ? defaultTarget(for: skill, actor: actor) : nil
    }

    /// Predicts the next few actors from current speed and attack bars. It is a
    /// projection, not a promise — attack-bar manipulation changes it mid-turn,
    /// which is exactly what makes the preview worth showing.
    private func refreshTurnOrder() {
        var simulated = engine.combatants.filter(\.isAlive).map {
            (id: $0.id, bar: $0.attackBar, speed: max(1.0, $0.currentStats.spd))
        }
        var order: [UUID] = []

        for _ in 0..<6 {
            guard !simulated.isEmpty else { break }
            // Time for each to reach a full bar; smallest goes next.
            let times = simulated.map { (1.0 - $0.bar) / ($0.speed * BattleEngine.attackBarRate) }
            guard let nextIndex = times.indices.min(by: { times[$0] < times[$1] }) else { break }
            let elapsed = times[nextIndex]
            for index in simulated.indices {
                simulated[index].bar = min(1.0, simulated[index].bar + simulated[index].speed * BattleEngine.attackBarRate * elapsed)
            }
            order.append(simulated[nextIndex].id)
            simulated[nextIndex].bar = 0
        }

        turnOrderPreview = order.compactMap { id in
            engine.combatants.first(where: { $0.id == id })
        }
    }

    // MARK: - Results

    /// Applies rewards. Returns a summary the result screen renders.
    /// The player's units with what each did, and who did the most. Score is
    /// damage dealt plus healing: a healer who kept the line alive is worth
    /// the laurel as much as the unit that landed the numbers.
    private func reckoning() -> (stats: [BattleSummary.UnitStat], mvp: UUID?) {
        let mine = displayedCombatants.filter { $0.side == .player }
        let stats = mine.map { unit -> BattleSummary.UnitStat in
            let tally = tallies[unit.id] ?? Tally()
            let stars = unit.sourceUnitID.flatMap { store.resolved($0)?.stars } ?? 3
            return BattleSummary.UnitStat(
                id: unit.id,
                name: unit.name,
                portraitName: unit.model.portraitName(awakened: unit.isAwakened),
                element: unit.element,
                stars: stars,
                dealt: tally.dealt,
                taken: tally.taken,
                healed: tally.healed,
                kills: tally.kills,
                survived: unit.isAlive
            )
        }
        let mvp = stats.max { first, second in
            let one: Double = first.dealt + first.healed
            let other: Double = second.dealt + second.healed
            return one < other
        }
        let mvpShare: Double = (mvp?.dealt ?? 0) + (mvp?.healed ?? 0)
        return (stats, mvpShare > 0 ? mvp?.id : nil)
    }

    private func loot(from stageOutcome: StageOutcome) -> [BattleSummary.Loot] {
        BattleSummary.loot(from: stageOutcome) { self.store.resolved($0)?.name ?? "Unit" }
    }

    func finish() -> BattleSummary {
        guard let result = outcome else {
            return BattleSummary(outcome: .draw, lines: [], stars: 0)
        }
        let (stats, mvp) = reckoning()

        switch context {
        case .campaign(let stage):
            let stageOutcome = store.finishCampaignBattle(stage: stage, result: result)
            var lines: [BattleSummary.Line] = []
            if stageOutcome.drachma > 0 {
                lines.append(.init(icon: "circle.hexagongrid.fill", label: "Drachma", value: "+\(stageOutcome.drachma)"))
            }
            if stageOutcome.unitExperience > 0 {
                lines.append(.init(icon: "arrow.up.circle.fill", label: "Unit EXP", value: "+\(stageOutcome.unitExperience)"))
            }
            if stageOutcome.divinityEarned > 0 {
                lines.append(.init(icon: "sparkles", label: "Divinity", value: "+\(stageOutcome.divinityEarned)"))
            }
            for relic in stageOutcome.relicsEarned {
                lines.append(.init(icon: "shield.lefthalf.filled", label: relic.displayName, value: "\(relic.grade)★"))
            }
            for (id, count) in stageOutcome.stonesEarned.sorted(by: { $0.key < $1.key }) {
                lines.append(.init(icon: "diamond.fill", label: RelicStone.from(id: id)?.displayName ?? id, value: "+\(count)"))
            }
            for (id, count) in stageOutcome.aetherEarned.sorted(by: { $0.key < $1.key }) {
                lines.append(.init(icon: "circle.hexagonpath.fill", label: Aether.name(for: id), value: "+\(count)"))
            }
            for cache in stageOutcome.boonCachesEarned {
                lines.append(.init(icon: "seal.fill", label: cache.displayName, value: "×1"))
            }
            for (id, count) in stageOutcome.essencesEarned {
                lines.append(.init(icon: "drop.triangle.fill", label: EssenceCatalog.name(for: id), value: "+\(count)"))
            }
            for (id, count) in stageOutcome.scrollsEarned {
                let name = ScrollType(rawValue: id)?.displayName ?? id
                lines.append(.init(icon: "scroll.fill", label: name, value: "+\(count)"))
            }
            for (unitID, levels) in stageOutcome.leveledUnits {
                let name = store.resolved(unitID)?.name ?? "Unit"
                lines.append(.init(icon: "chevron.up.circle.fill", label: "\(name) levelled", value: "+\(levels)"))
            }
            // A raid's chest opens on a loss too, when the grade paid aether:
            // the outcome then holds nothing but the aether, so the shelf
            // shows exactly what a D was worth. An ordinary defeat has no
            // grade and no shelf, as before.
            let graded = stageOutcome.raidGrade != nil
            return BattleSummary(
                outcome: result.outcome, lines: lines, stars: stageOutcome.stars,
                title: stage.name, turns: result.turnsTaken,
                damageDealt: result.totalDamageDealt, damageTaken: result.totalDamageTaken,
                unitStats: stats, mvpID: mvp,
                loot: result.outcome == .victory || graded ? loot(from: stageOutcome) : [],
                isFirstClear: stageOutcome.isFirstClear,
                raidGrade: stageOutcome.raidGrade,
                raidGradeLine: RaidGradeService.caption(for: stage, result: result) ?? "",
                experience: result.outcome == .victory ? experienceGains() : [:],
                levelUp: levelUp(gained: stageOutcome.playerLevelsGained, newLevel: stageOutcome.newPlayerLevel)
            )

        case .arena(let opponent):
            let (delta, laurels) = store.finishArenaBattle(result: result, opponent: opponent)
            let lines: [BattleSummary.Line] = [
                .init(icon: "trophy.fill", label: "Rank Points", value: delta >= 0 ? "+\(delta)" : "\(delta)"),
                .init(icon: "laurel.leading", label: "Laurels", value: "+\(laurels)")
            ]
            var loot: [BattleSummary.Loot] = []
            if result.outcome == .victory {
                loot.append(.init(glyph: "trophy.fill", title: "Rank Points",
                                  amount: delta >= 0 ? "+\(delta)" : "\(delta)", tint: .gold, key: "rank_points"))
                loot.append(.init(glyph: "laurel.leading", title: "Laurels", amount: "+\(laurels)", tint: .laurel, key: "laurels"))
            }
            return BattleSummary(
                outcome: result.outcome,
                lines: lines,
                stars: result.outcome == .victory ? 3 : 0,
                title: "vs \(opponent.name)", turns: result.turnsTaken,
                damageDealt: result.totalDamageDealt, damageTaken: result.totalDamageTaken,
                unitStats: stats, mvpID: mvp, loot: loot
            )

        case .guildWar(let target):
            // The points a win is worth are known before the report comes
            // back (the war's rules are the client's as well as the
            // backend's); the report itself goes up in the background.
            let points = result.outcome == .victory && !target.beaten ? target.pointsForWin : 0
            store.finishWarAttack(target, result: result)
            let lines: [BattleSummary.Line] = [
                .init(icon: "shield.lefthalf.filled", label: "War Points", value: "+\(points)")
            ]
            var loot: [BattleSummary.Loot] = []
            if points > 0 {
                loot.append(.init(glyph: "shield.lefthalf.filled", title: "War Points", amount: "+\(points)", tint: .gold, key: "rank_points"))
            }
            return BattleSummary(
                outcome: result.outcome,
                lines: lines,
                stars: result.outcome == .victory ? 3 : 0,
                title: "vs \(target.profile.name)", turns: result.turnsTaken,
                damageDealt: result.totalDamageDealt, damageTaken: result.totalDamageTaken,
                unitStats: stats, mvpID: mvp, loot: loot
            )

        case .draft(let bout):
            // The Draft Arena's own ladder and purse (`DraftService
            // .applyResult`): the rating's swing, and the laurels of a paid
            // bout — none once the day's five are spent.
            let settled = store.finishDraftBout(bout, result: result)
            let swing = settled.ratingDelta >= 0 ? "+\(settled.ratingDelta)" : "\(settled.ratingDelta)"
            let lines: [BattleSummary.Line] = [
                .init(icon: "rosette", label: "Draft rating", value: swing),
                .init(icon: "laurel.leading", label: "Laurels", value: "+\(settled.laurels)")
            ]
            var loot: [BattleSummary.Loot] = []
            if result.outcome == .victory {
                loot.append(.init(glyph: "rosette", title: "Draft Rating", amount: swing, tint: .gold, key: "rank_points"))
                if settled.laurels > 0 {
                    loot.append(.init(glyph: "laurel.leading", title: "Laurels", amount: "+\(settled.laurels)", tint: .laurel, key: "laurels"))
                }
            }
            return BattleSummary(
                outcome: result.outcome,
                lines: lines,
                stars: result.outcome == .victory ? 3 : 0,
                title: "vs \(bout.rivalName)", turns: result.turnsTaken,
                damageDealt: result.totalDamageDealt, damageTaken: result.totalDamageTaken,
                unitStats: stats, mvpID: mvp, loot: loot
            )
        }
    }

    // MARK: - The reckoning's tallies
    //
    // Kept on the class, not in the scene-delegate extension that fills
    // them: an extension may declare methods and computed properties only.
    /// What each combatant did, kept as the display advances so the reckoning
    /// at the end can name a most valuable unit. Kills go to whoever landed
    /// the last hit, which is the only definition a player will agree with.
    struct Tally {
        var dealt: Double = 0
        var taken: Double = 0
        var healed: Double = 0
        var kills: Int = 0
    }
    private var tallies: [UUID: Tally] = [:]
    private var lastHitter: [UUID: UUID] = [:]
}

/// One entry in the battle command bar.
struct SkillOption: Identifiable {
    var slot: Int
    var skill: Skill
    var cooldown: Int

    var id: Int { slot }
    var isReady: Bool { cooldown <= 0 }
}

struct BattleSummary {
    struct Line: Identifiable {
        var id = UUID()
        var icon: String
        var label: String
        var value: String
    }

    /// One of the player's units, as the reckoning reads it out.
    struct UnitStat: Identifiable {
        var id: UUID
        var name: String
        var portraitName: String
        var element: Element
        var stars: Int
        var dealt: Double
        var taken: Double
        var healed: Double
        var kills: Int
        var survived: Bool
    }

    /// A colour the model can name without importing SwiftUI; the view turns
    /// it into paint.
    enum LootTint {
        case gold, verdigris, laurel, wine, marble
        case element(Element)
        case scroll(ScrollType)
        /// A whetstone or a gem, in its tier's metal.
        case rarity(Rarity)
    }

    /// One thing the chest gives up. A relic carries itself so the tile can
    /// draw the stone and open the drop card; everything else is a glyph on
    /// a plate.
    struct Loot: Identifiable {
        var id = UUID()
        var glyph: String
        var title: String
        /// The count printed on the tile's corner. Nil for a relic: it is
        /// one stone, and its slot is the badge on the stone's own corner.
        /// "Slot 3" printed as the amount lay in large outlined type across
        /// the lower half of the painted stone, over its seal, and read as a
        /// count (runs 220 and 221).
        var amount: String? = nil
        var tint: LootTint
        var stars: Int? = nil
        var relic: Relic? = nil
        /// The `ItemArt` key the tile paints; nil for a relic, which draws
        /// itself, or a spoil with no painting of its own.
        var key: String? = nil
    }

    var outcome: BattleOutcome
    var lines: [Line]
    var stars: Int

    // The reckoning. Defaulted so the places that only ever built a three
    // field summary keep compiling; `finish()` and the repeat summary fill
    // them, the forfeit path does not need them.
    var title: String = ""
    var turns: Int = 0
    var damageDealt: Double = 0
    var damageTaken: Double = 0
    var unitStats: [UnitStat] = []
    var mvpID: UUID? = nil
    var loot: [Loot] = []
    var isFirstClear: Bool = false
    /// A raid's grade and the line that says what earned it; nil and empty
    /// for every other fight.
    var raidGrade: RaidGrade? = nil
    var raidGradeLine: String = ""
    /// Each surviving player unit's experience across the fight, keyed by
    /// its COMBATANT id: the gold bars its plate fills on the field while
    /// the survivors pose (Docs/FEEL.md W1.7). Empty where the fight paid no
    /// unit experience (the arena, a guild war, a draft bout, a loss).
    var experience: [UUID: ExperienceGain] = [:]
    /// The demigod's level-up, for the beat between the reckoning and the
    /// chest (W1.6); nil when the fight raised no level. An auto-repeat's is
    /// every run's levels as one.
    var levelUp: PlayerLevelUp? = nil
    /// The stars the VICTORY stamp slams in over the field when they are not
    /// `stars`: an auto-repeat's reckoning shows none (a session has no
    /// stars), and its stamp shows the last run's. Nil reads `stars`.
    var stampStars: Int? = nil

    /// How full a unit's EXP bar stands, 0...1 of the level it is at: its
    /// experience over what the next level needs (`ProgressionService`). A
    /// unit at its grade's cap reads full; the cap zeroes its experience.
    static func experienceShare(of unit: Unit) -> Double {
        let cap = ProgressionService.maxLevel(stars: unit.stars)
        guard unit.level < cap else { return 1 }
        let needed = ProgressionService.experienceForNextLevel(level: unit.level, stars: unit.stars)
        guard needed > 0 else { return 1 }
        let share = Double(unit.experience) / Double(needed)
        return min(1, max(0, share))
    }

    /// One unit's fight on its plate: the bar before, the bar after, and the
    /// levels between them.
    static func experienceGain(before: Unit, after: Unit) -> ExperienceGain {
        ExperienceGain(
            from: experienceShare(of: before),
            to: experienceShare(of: after),
            levelsGained: max(0, after.level - before.level)
        )
    }

    /// The chest's contents for one settled stage, as tiles.
    ///
    /// A type method rather than a method on the battle screen because the
    /// sweep shows the same haul without ever building a battle: one
    /// vocabulary of spoils for the game, so a swept run and a fought one
    /// cannot be drawn differently. `unitName` is the only thing it cannot
    /// work out for itself.
    static func loot(
        from stageOutcome: StageOutcome,
        unitName: (UUID) -> String
    ) -> [BattleSummary.Loot] {
        var items: [BattleSummary.Loot] = []
        if stageOutcome.drachma > 0 {
            items.append(.init(glyph: "circle.hexagongrid.fill", title: "Drachma",
                               amount: "+\(stageOutcome.drachma.formatted())", tint: .gold, key: "drachma"))
        }
        if stageOutcome.unitExperience > 0 {
            items.append(.init(glyph: "arrow.up.circle.fill", title: "Unit EXP",
                               amount: "+\(stageOutcome.unitExperience.formatted())", tint: .verdigris, key: "unit_exp"))
        }
        if stageOutcome.divinityEarned > 0 {
            items.append(.init(glyph: "sparkles", title: "Divinity",
                               amount: "+\(stageOutcome.divinityEarned)", tint: .marble, key: "divinity"))
        }
        // No amount: a relic's slot is the badge on its stone (`Loot.amount`).
        for relic in stageOutcome.relicsEarned {
            items.append(.init(glyph: relic.set.glyph, title: relic.displayName,
                               amount: nil, tint: .gold, stars: relic.grade, relic: relic))
        }
        for (id, count) in stageOutcome.stonesEarned.sorted(by: { $0.key < $1.key }) {
            guard let stone = RelicStone.from(id: id) else { continue }
            items.append(.init(glyph: stone.kind.glyph, title: stone.displayName,
                               amount: "+\(count)", tint: .rarity(stone.tier.quality.rarity), key: id))
        }
        // Sorted by id, so the elemental aether stands before the pure.
        for (id, count) in stageOutcome.aetherEarned.sorted(by: { $0.key < $1.key }) {
            items.append(.init(glyph: "circle.hexagonpath.fill", title: Aether.name(for: id),
                               amount: "+\(count)", tint: Aether.element(of: id).map { .element($0) } ?? .marble, key: id))
        }
        // A boon cache: the shelf shows the sealed thing; it opens on the
        // unit sheet's socket, where its three doors are a choice.
        for cache in stageOutcome.boonCachesEarned {
            items.append(.init(glyph: "seal.fill", title: cache.displayName, amount: "×1",
                               tint: .gold, stars: cache.grade, key: "boon_cache_\(cache.grade)"))
        }
        for (id, count) in stageOutcome.essencesEarned.sorted(by: { $0.key < $1.key }) {
            let element = Element(rawValue: id.split(separator: "_").dropFirst().first.map(String.init) ?? "")
            items.append(.init(glyph: "drop.triangle.fill", title: EssenceCatalog.name(for: id),
                               amount: "+\(count)", tint: element.map { .element($0) } ?? .verdigris, key: id))
        }
        for (id, count) in stageOutcome.scrollsEarned.sorted(by: { $0.key < $1.key }) {
            if let scroll = ScrollType(rawValue: id) {
                items.append(.init(glyph: scroll.glyph, title: scroll.displayName,
                                   amount: "+\(count)", tint: .scroll(scroll), key: ItemArt.key(scroll: scroll)))
            } else {
                items.append(.init(glyph: "scroll.fill", title: id, amount: "+\(count)", tint: .gold))
            }
        }
        for (unitID, levels) in stageOutcome.leveledUnits {
            let name = unitName(unitID)
            items.append(.init(glyph: "chevron.up.circle.fill", title: "\(name) levelled",
                               amount: "+\(levels)", tint: .laurel, key: "level_up"))
        }
        return items
    }
}

/// The battle's speeds, the genre's three (Docs/FEEL.md W1.1): the control
/// steps ×1 → ×2 → ×3 → ×1, as Summoners War's does. It stepped 1 → 2 → 4,
/// and at ×4 the juice's skip threshold turned every freeze, shake and
/// haptic off, so a player who tapped it twice lost the fight's whole feel
/// without knowing why. Skip is the one way to watch a turn with no feedback.
///
/// The choice is remembered between fights on THIS device (`key` in
/// UserDefaults — how a player likes to watch, never part of the save), and
/// not under the CI tour: its battle frames start at ×1 whatever an earlier
/// launch of the tour chose, and a step that wants another speed sets it.
enum BattleSpeed {
    static let key = "battleSpeed"
    /// The fastest the control goes; the stress tour runs its fights at it.
    static let top: Double = 3

    /// The control's next step.
    static func next(after speed: Double) -> Double {
        let step = settled(speed)
        return step >= top ? 1 : step + 1
    }

    /// Any speed as one of the three: rounded, and held inside ×1…×3.
    static func settled(_ speed: Double) -> Double {
        guard speed.isFinite else { return 1 }
        return min(top, max(1, speed.rounded()))
    }

    /// The speed the last fight on this device was left at; ×1 when none
    /// was, or under the tour.
    static func remembered(in defaults: UserDefaults = .standard) -> Double {
        guard remembers, let stored = defaults.object(forKey: key) as? Double else { return 1 }
        return settled(stored)
    }

    static func remember(_ speed: Double, in defaults: UserDefaults = .standard) {
        guard remembers else { return }
        defaults.set(settled(speed), forKey: key)
    }

    /// False under the CI tour (`-tour`).
    static let remembers = !ProcessInfo.processInfo.arguments.contains("-tour")
}

/// The demigod's level-up as the battle's beat shows it (Docs/FEEL.md W1.6):
/// the level reached, what the levels paid, and what they opened. What they
/// paid is read off the settle's own per-level numbers
/// (`CampaignService.maxEnergyPerLevel`, `divinityPerLevel`), never a copy.
struct PlayerLevelUp: Equatable, Sendable {
    let fromLevel: Int
    let level: Int
    /// The energy bar every level-up fills (`CampaignService.applyRewards`
    /// sets the energy to it), as the settle left it.
    let maxEnergy: Int
    let unlocks: [LevelUnlock]

    var levelsGained: Int { max(0, level - fromLevel) }
    var maxEnergyGained: Int { levelsGained * CampaignService.maxEnergyPerLevel }
    var divinity: Int { levelsGained * CampaignService.divinityPerLevel }

    static func between(_ from: Int, _ to: Int, maxEnergy: Int) -> PlayerLevelUp {
        PlayerLevelUp(fromLevel: from, level: to, maxEnergy: maxEnergy, unlocks: LevelUnlock.between(from, to))
    }
}

/// Something a demigod level opens, for the level-up beat's last row: a
/// building that opens, a decoration the island's chisel now sells, or a
/// building that takes its next tier (the diamonds on its name chip).
struct LevelUnlock: Equatable, Sendable {
    let label: String
    let value: String
    let glyph: String
    /// A bundle painting for the chip — a decoration's thumbnail — when the
    /// thing has one; the glyph otherwise.
    let art: String?

    /// Everything that opens on the way from `from` to `to`, in the order a
    /// player would care: a building, a decoration, a building's tier.
    static func between(_ from: Int, _ to: Int) -> [LevelUnlock] {
        guard to > from else { return [] }
        let opened = IslandDatabase.landmarks
            .filter { $0.unlockLevel > from && $0.unlockLevel <= to }
            .map { LevelUnlock(label: "Now open", value: $0.title, glyph: $0.systemImage, art: nil) }
        let pieces = IslandDatabase.decorations
            .filter { $0.unlockLevel > from && $0.unlockLevel <= to }
            .map { LevelUnlock(label: "New decoration", value: $0.title, glyph: $0.glyph, art: $0.thumbnail) }
        let tiers = IslandDatabase.landmarks
            .filter { $0.tier(atLevel: to) > $0.tier(atLevel: from) }
            .map { LevelUnlock(label: $0.title, value: "Tier \($0.tier(atLevel: to))", glyph: $0.systemImage, art: nil) }
        return opened + pieces + tiers
    }
}

// MARK: - Scene playback

extension BattleViewModel: BattleSceneDelegate {

    nonisolated func battleScene(_ controller: BattleSceneController, willPresent event: BattleEvent) {
        Task { @MainActor in
            self.record(event)
            self.applyToDisplay(event)
        }
    }

    nonisolated func battleSceneDidFinishPlayback(_ controller: BattleSceneController) {
        Task { @MainActor in
            self.settleAfterPlayback()
        }
    }

    /// Advances the HUD's copy of the world one event at a time so the numbers
    /// on screen always match the animation that is playing.
    private func applyToDisplay(_ event: BattleEvent) {
        func mutate(_ id: UUID, _ change: (inout Combatant) -> Void) {
            guard let index = displayedCombatants.firstIndex(where: { $0.id == id }) else { return }
            change(&displayedCombatants[index])
        }

        switch event {
        case .damage(let source, let target, let amount, _, _, _, let remaining, _, _):
            mutate(target) { $0.currentHealth = remaining }
            tallies[source, default: Tally()].dealt += amount
            tallies[target, default: Tally()].taken += amount
            lastHitter[target] = source
        case .healed(let source, let target, let amount, let remaining):
            mutate(target) { $0.currentHealth = remaining }
            tallies[source, default: Tally()].healed += amount
        case .statusApplied(let source, let target, let kind, let turns):
            mutate(target) {
                $0.statuses.append(ActiveStatus(kind: kind, turnsRemaining: turns, sourceID: source))
            }
        case .statusExpired(let target, let kind), .statusRemoved(let target, let kind, _):
            mutate(target) {
                if let index = $0.statuses.firstIndex(where: { $0.kind == kind }) {
                    $0.statuses.remove(at: index)
                }
            }
        case .attackBarChanged(let target, _, let newValue):
            mutate(target) { $0.attackBar = newValue }
        case .defeated(let target):
            mutate(target) { $0.currentHealth = 0; $0.statuses.removeAll() }
            if let killer = lastHitter[target] { tallies[killer, default: Tally()].kills += 1 }
        case .revived(let target, let health):
            mutate(target) { $0.currentHealth = health }
        case .cooldownStarted(let actor, let slot, let turns):
            mutate(actor) {
                if $0.cooldowns.indices.contains(slot) { $0.cooldowns[slot] = turns }
            }
        case .waveStarted(let wave, _, let opponents):
            waveIndex = wave
            for arrival in opponents where !displayedCombatants.contains(where: { $0.id == arrival.id }) {
                displayedCombatants.append(arrival)
            }
            announceBoss(ifPresentIn: opponents)
        default:
            break
        }
    }

    private func record(_ event: BattleEvent) {
        func name(_ id: UUID) -> String {
            displayedCombatants.first(where: { $0.id == id })?.name ?? "?"
        }

        let line: String?
        switch event {
        case .turnBegan(let actor, let turn):
            line = "— Turn \(turn): \(name(actor))"
        case .turnSkipped(let actor, let reason):
            line = "\(name(actor)) is \(reason.displayName) and loses the turn."
        case .skillCast(let actor, _, let skill, _, _, _, _):
            line = "\(name(actor)) uses \(skill)."
        case .damage(_, let target, let amount, let crit, let glancing, let matchup, _, _, _):
            var suffix = ""
            if crit { suffix = " (CRIT)" }
            else if glancing { suffix = " (glancing)" }
            else if matchup == .advantage { suffix = " (advantage)" }
            line = "\(name(target)) takes \(Int(amount.rounded())) damage\(suffix)."
        case .healed(_, let target, let amount, _):
            line = "\(name(target)) recovers \(Int(amount.rounded())) HP."
        case .statusApplied(_, let target, let kind, let turns):
            line = "\(name(target)) gains \(kind.displayName) for \(turns) turn\(turns == 1 ? "" : "s")."
        case .statusResisted(_, let target, let kind):
            line = "\(name(target)) resists \(kind.displayName)."
        case .counterattack(let actor, _):
            line = "\(name(actor)) counterattacks."
        case .extraTurnGranted(let actor, let source):
            line = "\(name(actor)) gains an extra turn (\(source))."
        case .passiveTriggered(let actor, let passive):
            line = "\(name(actor)): \(passive)."
        case .revived(let target, _):
            line = "\(name(target)) is revived."
        case .defeated(let target):
            line = "\(name(target)) is defeated."
        case .waveStarted(let wave, let count, _):
            line = "Wave \(wave) of \(count) takes the field."
        case .battleEnded(let result):
            line = result.outcome == .victory ? "Victory." : (result.outcome == .defeat ? "Defeat." : "Draw.")
        default:
            line = nil
        }

        if let line {
            log.append(line)
            if log.count > 200 { log.removeFirst(log.count - 200) }
        }
    }
}

// MARK: - The boss's line

extension Stage {
    /// The wave `blueprintID` stands in as the stage's speaker, 1-based: the
    /// LAST wave that fields it. A chapter's boss is appended to the final
    /// wave (`StageDatabase.generatedChapter`, and Duat 1's Apep by hand),
    /// and the same creature may walk on earlier as one of the mobs — the
    /// cyclops, the medusa, the berserker and the frost troll all do — which
    /// is no reason to speak the boss's line: the first mob of the kind said
    /// it, a wave early, and on top of that wave's stamp (review,
    /// 2026-09-24). A raid's Titan stands in the first wave; a blueprint
    /// the stage never fields answers 1.
    func speakerWave(of blueprintID: String) -> Int {
        let waves: [[EnemySpawn]] = [enemies] + laterWaves
        let fielding: [Int] = waves.indices.filter { index in
            waves[index].contains(where: { $0.blueprintID == blueprintID })
        }
        return (fielding.last ?? 0) + 1
    }
}

// MARK: - The skill reel

#if DEBUG
/// The CI tour's skill reel (TourView's `skill_reel` step, `-tour-skill-reel`;
/// Docs/PLAN.md *Skills that look like themselves*): named families each
/// cast the whole of their kit — the basic, the second skill, the third — on
/// the real engine, the real scene and the home camera, at ×1, one family
/// after another, while the CI job records the simulator.
///
/// The engine hands turns out by speed and takes no orders, and no set of
/// speeds lets one unit act three times and then another three times in one
/// fight (for A's three to come before B's first, A must be over three times
/// B's speed; for B's three to come before A's fourth, under four thirds of
/// it). So each family is a fight of its own, built in place as an
/// auto-repeat's next run is: the whole line stands in every one — a rite
/// lands on all of it — but only the family at the front keeps its speed,
/// and everyone else on the field stands at 1, so it takes every turn until
/// its kit is spent and nobody else takes one. TourView builds the reel;
/// `BattleViewModel` plays it (`takeReelTurn`).
struct SkillReel {
    let segments: [SkillReelSegment]
    /// The stage card's detail: the families in the order they cast.
    let roll: String
    /// The first family's fight's seed; each after it takes the next, so
    /// a run's crits and rolls are the same every run.
    let seed: UInt64
}

/// One family at the front of the skill reel, and the field it casts on.
struct SkillReelSegment {
    /// Its slot in the player's line, which is the same in every segment.
    let caster: Int
    /// The HUD's banner as it steps up: its name and its element.
    let banner: String
    /// The skills it will cast: every one of its kit that is not a passive.
    let castCount: Int
    let playerTeam: [ResolvedUnit]
    let opponentTeam: [ResolvedUnit]
}
#endif
