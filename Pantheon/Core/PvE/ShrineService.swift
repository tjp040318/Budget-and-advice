import Foundation

// MARK: - Hidden Shrines and summoning pieces (2026-09-23; Docs/SHRINES.md)
//
// Summoners War's Secret Dungeon, in the Labyrinth's terms. A win on a
// Labyrinth level or a Hall of Essence floor sometimes finds a hidden shrine:
// one battle, open for an hour, keyed to one family FORM — a family and an
// element, never Radiance or Umbra (`Banner.excludingLightDark`). Every win
// there pays summoning pieces of that form, and enough pieces summon it
// through the same reveal a scroll plays: 20 for a 3★, 40 for a 4★, 100 for a
// 5★ (Summoners War's are 40, 50 and 100; the reasons are in the doc).
//
// The numbers are measured by `python3 tools/balance.py --shrines`, which
// mirrors every constant below and asserts the shape — about one shrine a day
// of normal play, one 4★ a shrine's hour, and a 5★ by pieces slower than
// naming one by mileage. `PantheonTests/ShrineTests.swift` pins them. Change
// a number in all three.

/// A hidden shrine open now. It lives in the save (`Player.shrines`) from the
/// clear that found it until its hour is out; an expired one is pruned, never
/// fought. New fields must be Optional: this rides inside a save.
struct HiddenShrine: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    /// The form it is keyed to, a blueprint id (`anubis_tide`). Never a
    /// Radiance or an Umbra form: `ShrineService.pool` has none.
    var blueprintID: String
    /// The Labyrinth level or Hall floor it was found on (`Stage.id`). The
    /// shrine's foes take that stage's level, grade and multiplier, and a run
    /// costs that stage's energy, so the team that found it can take it.
    var foundOn: String
    var openedAt: Date
    var expiresAt: Date
    /// Wins in it so far, for the room's line.
    var wins: Int = 0

    func isOpen(at date: Date) -> Bool { date < expiresAt }
}

/// What one settled clear did to the shrines: a shrine found, or pieces paid.
enum ShrineNews: Equatable, Sendable {
    case opened(HiddenShrine)
    case pieces(blueprintID: String, count: Int)
}

/// The pieces held of one form, as the room lists them.
struct ShrineStock: Identifiable, Equatable, Sendable {
    let blueprint: UnitBlueprint
    let pieces: Int

    var id: String { blueprint.id }
    var price: Int { ShrineService.price(of: blueprint) }
    var isReady: Bool { pieces >= price }
}

/// The shrines' rules: where one is found, what it is, what a win pays and
/// what the pieces buy. Pure functions of the save and a seeded stream, so a
/// test can replay any of it; `GameStore+Shrines.swift` is the store's side.
enum ShrineService {

    // MARK: The rules (mirrored in tools/balance.py as SHRINE_*)

    /// Every shrine stage's chapter: its id is `shrine_<form>`, index 1, and
    /// `CampaignService` runs it as it runs a Hall floor — its progress, its
    /// star mark and its quest count stand under this one id.
    static let chapterID = "shrine"
    /// Summoners War's exact hour, and the Night Market's clock.
    static let windowMinutes = 60
    /// A clear that would find a fourth finds nothing: a shrine is never
    /// taken away to make room.
    static let maxOpen = 3
    /// A win's chance of finding a shrine, for each point of energy the stage
    /// costs: 3% on Hall B1 (6), 3.5% on Labyrinth B7, 4% on B10, 5% on Hall
    /// B5. Proportional to the energy, so no floor is a cheaper shrine farm
    /// than another, and a deeper floor finds one more often per clear.
    static let discoveryPerEnergy = 0.005
    /// Pieces a summon takes, by the form's natural grade.
    static let piecesPerSummon: [Int: Int] = [3: 20, 4: 40, 5: 100]
    /// Every win pays this many, and one more at `bonusPieceChance`: 3.5 a
    /// win, a 4★ in about eleven.
    static let piecesPerRun = 3
    static let bonusPieceChance = 0.5
    /// How often a new shrine is a form the player already holds pieces of
    /// (weighted by the pieces held): the answer to Summoners War's stranded
    /// pieces, so a god once started comes back.
    static let returnChance = 0.5
    /// The shrine's grade by how deep the clear was — the found stage's relic
    /// grade: Labyrinth B1–3 and Hall B1 are 3, B4–6 and Hall B2 are 4, B7–9
    /// and Hall B3–5 are 5, B10 is 6. Toward 3★ and 4★; a 5★ is rare.
    static let gradeWeights: [Int: [Int: Double]] = [
        3: [3: 0.75, 4: 0.24, 5: 0.01],
        4: [3: 0.63, 4: 0.35, 5: 0.02],
        5: [3: 0.53, 4: 0.43, 5: 0.04],
        6: [3: 0.44, 4: 0.51, 5: 0.05],
    ]
    /// Beside the pieces, a win pays the found floor's drachma and
    /// experience, the form's element's Mid essence at this chance and an
    /// Unknown Scroll at `scrollChance` — and no relic, as a secret dungeon
    /// pays no runes: energy spent here is not spent on the relic hunt.
    static let essenceChance = 0.30
    static let scrollChance = 0.10
    /// The form as the last wave's boss, at the Labyrinth boss's multiplier.
    static let bossMultiplier = 1.6

    static var window: TimeInterval { TimeInterval(windowMinutes * 60) }

    // MARK: The forms

    /// Every form a shrine can be keyed to: the summon pool's fire, water and
    /// wind forms of 3★ to 5★ (96, 132 and 63 on 2026-09-23). Built through
    /// `Banner.excludingLightDark`, the one place the premium rule is
    /// spelled, and filtered again on the element, so no shrine can ever
    /// hand over a Radiance or an Umbra unit. The fusion prizes are not in
    /// the summon pool, so they are not here either.
    static let pool: [UnitBlueprint] = Banner.excludingLightDark(UnitDatabase.summonPool)
        .compactMap { UnitDatabase.blueprint($0) }
        .filter { !$0.element.isLightOrDark && piecesPerSummon[$0.naturalStars] != nil }

    /// Whether a form can be a shrine's (and so be summoned from pieces).
    static func isShrineForm(_ blueprintID: String) -> Bool {
        pool.contains { $0.id == blueprintID }
    }

    // MARK: Where shrines are found

    /// A Labyrinth level or a Hall of Essence floor: the clears that can find one.
    static func isSource(_ stage: Stage) -> Bool {
        DungeonDatabase.labyrinth(containing: stage) != nil || DungeonDatabase.hall(containing: stage) != nil
    }

    static func isShrineStage(_ stage: Stage) -> Bool { stage.chapterID == chapterID }

    /// A win's chance of finding a shrine here.
    static func discoveryChance(for stage: Stage) -> Double {
        guard isSource(stage) else { return 0 }
        return min(1, Double(stage.energyCost) * discoveryPerEnergy)
    }

    /// How deep a clear was, as the grade of the relic its stage pays (3–6).
    static func depth(of stage: Stage) -> Int { min(6, max(3, stage.rewards.relicGrade)) }

    /// The elements a shrine found here can be: a Hall's own — the Hall of
    /// Tides finds water, Summoners War's rule — or fire, water and wind from
    /// the Labyrinth and the Halls of Radiance and Shadows, whose elements no
    /// shrine ever is.
    static func elements(foundOn stage: Stage) -> [Element] {
        if let hall = DungeonDatabase.hall(containing: stage), !hall.element.isLightOrDark {
            return [hall.element]
        }
        return [.ember, .tide, .gale]
    }

    // MARK: The open shrines

    /// The shrines open at `now`, soonest to close first.
    static func openShrines(player: Player, at now: Date) -> [HiddenShrine] {
        (player.shrines ?? []).filter { $0.isOpen(at: now) }.sorted { $0.expiresAt < $1.expiresAt }
    }

    /// Drops the shrines whose hour is out; an empty list is no key at all.
    static func prune(player: inout Player, at now: Date) {
        guard let all = player.shrines else { return }
        let open = all.filter { $0.isOpen(at: now) }
        player.shrines = open.isEmpty ? nil : open
    }

    /// "42:18" to a shrine's close.
    static func countdown(to date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: Finding one

    /// The form of a shrine found on `stage`: its grade off the depth (among
    /// the grades that have a form to offer), then — `returnChance` of the
    /// time, when the player holds pieces of a form of that grade the room
    /// allows — one of those, weighted by the pieces held; otherwise a form
    /// of the pool at random. A form whose shrine is already open is never
    /// offered twice. The grades are walked in order, so one seed always
    /// draws the same shrine.
    static func rollForm(foundOn stage: Stage, player: Player, rng: inout SeededRandom) -> UnitBlueprint? {
        let allowed = elements(foundOn: stage)
        let taken = Set((player.shrines ?? []).map { $0.blueprintID })
        let weights = gradeWeights[depth(of: stage)] ?? [:]
        let offered: [(value: Int, weight: Double)] = weights.keys.sorted().compactMap { grade -> (value: Int, weight: Double)? in
            let hasForm: Bool = pool.contains { $0.naturalStars == grade && allowed.contains($0.element) && !taken.contains($0.id) }
            guard hasForm else { return nil }
            let weight: Double = weights[grade] ?? 0
            return (value: grade, weight: weight)
        }
        guard let grade = rng.pickWeighted(offered) else { return nil }
        let candidates: [UnitBlueprint] = pool.filter { $0.naturalStars == grade && allowed.contains($0.element) && !taken.contains($0.id) }
        let held: [(value: UnitBlueprint, weight: Double)] = candidates.compactMap { blueprint -> (value: UnitBlueprint, weight: Double)? in
            let count: Int = pieces(of: blueprint.id, player: player)
            guard count > 0 else { return nil }
            let weight: Double = Double(count)
            return (value: blueprint, weight: weight)
        }
        if !held.isEmpty, rng.chance(returnChance) {
            return rng.pickWeighted(held)
        }
        return rng.pickMutating(candidates)
    }

    /// Rolls a win's chance and opens a shrine when it lands, while fewer
    /// than `maxOpen` are open. The chance is drawn first, so the stream
    /// reads the same whatever is open.
    @discardableResult
    static func discover(
        after stage: Stage,
        player: inout Player,
        rng: inout SeededRandom,
        now: Date
    ) -> HiddenShrine? {
        prune(player: &player, at: now)
        let chance = discoveryChance(for: stage)
        guard chance > 0, rng.chance(chance) else { return nil }
        let open = player.shrines ?? []
        guard open.count < maxOpen else { return nil }
        guard let form = rollForm(foundOn: stage, player: player, rng: &rng) else { return nil }
        let shrine = HiddenShrine(
            blueprintID: form.id,
            foundOn: stage.id,
            openedAt: now,
            expiresAt: now.addingTimeInterval(window)
        )
        player.shrines = open + [shrine]
        return shrine
    }

    // MARK: A win in one

    /// The form a shrine stage is keyed to, read off its id.
    static func formID(of stage: Stage) -> String? {
        guard isShrineStage(stage) else { return nil }
        let prefix = chapterID + "_"
        guard stage.id.hasPrefix(prefix) else { return nil }
        return String(stage.id.dropFirst(prefix.count))
    }

    /// A win's pieces: `piecesPerRun`, and one more at `bonusPieceChance`.
    static func rollPieces(rng: inout SeededRandom) -> Int {
        piecesPerRun + (rng.chance(bonusPieceChance) ? 1 : 0)
    }

    /// Pays a shrine win's pieces into the stock and counts the win on the
    /// shrine while it is still listed. A run begun inside the hour pays even
    /// when it ends after it: a repeat session runs to its count.
    @discardableResult
    static func payPieces(for stage: Stage, player: inout Player, rng: inout SeededRandom) -> Int {
        guard let form = formID(of: stage), isShrineForm(form) else { return 0 }
        let count = rollPieces(rng: &rng)
        var stock = player.shrinePieces ?? [:]
        stock[form, default: 0] += count
        player.shrinePieces = stock
        if var shrines = player.shrines, let index = shrines.firstIndex(where: { $0.blueprintID == form }) {
            shrines[index].wins += 1
            player.shrines = shrines
        }
        return count
    }

    /// Everything a settled clear does to the shrines, in one place: a
    /// shrine's win pays its pieces; a Labyrinth or Hall win rolls for a new
    /// shrine. A defeat, and any other stage, does nothing. Called once per
    /// settled run by `GameStore.noteShrines(after:result:)` — the one hook in
    /// `finishCampaignBattle` — and meant for the sweep's loop as well, where
    /// it takes the loop's own player and stream.
    @discardableResult
    static func noteClear(
        stage: Stage,
        result: BattleResult,
        player: inout Player,
        rng: inout SeededRandom,
        now: Date = Date()
    ) -> ShrineNews? {
        guard result.outcome == .victory else { return nil }
        if isShrineStage(stage) {
            let count = payPieces(for: stage, player: &player, rng: &rng)
            guard count > 0, let form = formID(of: stage) else { return nil }
            return .pieces(blueprintID: form, count: count)
        }
        guard let shrine = discover(after: stage, player: &player, rng: &rng, now: now) else { return nil }
        return .opened(shrine)
    }

    // MARK: The pieces

    static func pieces(of blueprintID: String, player: Player) -> Int {
        player.shrinePieces?[blueprintID] ?? 0
    }

    /// The pieces a summon of this form takes.
    static func price(of blueprint: UnitBlueprint) -> Int {
        piecesPerSummon[blueprint.naturalStars] ?? 100
    }

    /// Every form the player holds pieces of: ready ones first, then the
    /// nearest to ready, then by name, so the list never shuffles.
    static func stocks(player: Player) -> [ShrineStock] {
        (player.shrinePieces ?? [:]).compactMap { entry -> ShrineStock? in
            guard entry.value > 0, let blueprint = UnitDatabase.blueprint(entry.key) else { return nil }
            return ShrineStock(blueprint: blueprint, pieces: entry.value)
        }
        .sorted { left, right in
            if left.isReady != right.isReady { return left.isReady }
            let leftShare: Double = Double(left.pieces) / Double(max(1, left.price))
            let rightShare: Double = Double(right.pieces) / Double(max(1, right.price))
            if leftShare != rightShare { return leftShare > rightShare }
            return left.blueprint.id < right.blueprint.id
        }
    }

    enum ShrineError: Error, LocalizedError {
        case unknownForm
        case notEnoughPieces(needed: Int)
        case closed

        var errorDescription: String? {
            switch self {
            case .unknownForm: return "No shrine answers to that form."
            case .notEnoughPieces(let needed): return "\(needed) more pieces to summon it."
            case .closed: return "The shrine has closed. Another will open."
            }
        }
    }

    /// Spends a summon's pieces and hands the form over. A duplicate becomes
    /// a skill-up exactly as a scroll's does — this is a summon, whose result
    /// was earned rather than rolled. It pays no mileage: no banner was
    /// pulled.
    @discardableResult
    static func summon(_ blueprintID: String, player: inout Player, rng: inout SeededRandom) throws -> SummonResult {
        guard isShrineForm(blueprintID), let blueprint = UnitDatabase.blueprint(blueprintID) else {
            throw ShrineError.unknownForm
        }
        let cost = price(of: blueprint)
        let held = pieces(of: blueprintID, player: player)
        guard held >= cost else { throw ShrineError.notEnoughPieces(needed: cost - held) }

        var stock = player.shrinePieces ?? [:]
        let left = held - cost
        stock[blueprintID] = left > 0 ? left : nil
        player.shrinePieces = stock.isEmpty ? nil : stock

        let isNew = !player.codex.contains(blueprint.id)
        player.codex.insert(blueprint.id)
        var unit = Unit(blueprint: blueprint)
        unit.acquiredFrom = "shrine"
        if !isNew, let index = player.units.firstIndex(where: { $0.blueprintID == blueprint.id }) {
            _ = ProgressionService.applySkillUp(to: &player.units[index], using: &rng)
        }
        player.units.append(unit)
        return SummonResult(
            unit: unit,
            blueprint: blueprint,
            stars: unit.stars,
            isNew: isNew,
            isFeatured: false,
            fromPity: false
        )
    }

    // MARK: The battle

    /// Where a form's shrine stands: its pantheon's own place, so a shrine
    /// of Anubis is in the Hall of Two Truths and one of Odin at the roots of
    /// the tree.
    static func home(of pantheon: Pantheon) -> BattleEnvironment {
        switch pantheon {
        case .egyptian: return .hallOfTwoTruths
        case .greek: return .olympusGate
        case .norse: return .yggdrasilRoots
        case .roman: return .forumRome
        case .chinese: return .peachGarden
        default: return .hallOfTwoTruths
        }
    }

    static func stage(for shrine: HiddenShrine) -> Stage? {
        stage(formID: shrine.blueprintID, foundOn: shrine.foundOn)
    }

    /// One shrine as a `Stage`, so `CampaignService` runs it, `BattleView`
    /// fights it and auto-repeat repeats it with no special case: Summoners
    /// War's waves of one monster — three of the form, then one AWAKENED
    /// between two, then the form as the boss at `bossMultiplier` and the
    /// higher of the floor's grade and its own, with two awakened at its side
    /// (awakened only when the family has an awakening). Level, grade,
    /// multiplier, energy, recommended power, drachma and experience are the
    /// found floor's; an id no table knows falls back to a mid-game floor.
    static func stage(formID: String, foundOn: String) -> Stage? {
        guard isShrineForm(formID), let blueprint = UnitDatabase.blueprint(formID) else { return nil }
        let found = StageDatabase.stage(foundOn)
        let template = found?.enemies.first
        let level = template?.level ?? 38
        let stars = template?.stars ?? 5
        let difficulty = template?.statMultiplier ?? 1.26
        let canWake = blueprint.awakening != nil
        let plain = EnemySpawn(blueprintID: formID, level: level, stars: stars, statMultiplier: difficulty)
        let woken = EnemySpawn(blueprintID: formID, level: level, stars: stars, statMultiplier: difficulty, awakened: canWake)
        let boss = EnemySpawn(
            blueprintID: formID, level: level, stars: max(stars, blueprint.naturalStars),
            statMultiplier: difficulty * bossMultiplier, awakened: canWake
        )
        let essence = "essence_\(blueprint.element.rawValue)_mid"
        return Stage(
            id: "\(chapterID)_\(formID)",
            chapterID: chapterID,
            index: 1,
            name: "Shrine of \(blueprint.name)",
            energyCost: found?.energyCost ?? 7,
            recommendedPower: found?.recommendedPower ?? 12_000,
            enemies: [plain, plain, plain],
            rewards: StageRewards(
                drachma: found?.rewards.drachma ?? 2_250,
                playerExperience: found?.rewards.playerExperience ?? 100,
                unitExperience: found?.rewards.unitExperience ?? 900,
                essenceChances: [essence: essenceChance],
                scrollChances: [ScrollType.unknown.rawValue: scrollChance]
            ),
            environment: home(of: blueprint.pantheon),
            isBoss: true,
            laterWaves: [[plain, woken, plain], [boss, woken, woken]]
        )
    }
}
