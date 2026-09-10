import Foundation

/// Turns saved `Unit`s into fightable `ResolvedUnit`s, and owns every rule about
/// levelling, evolving, awakening and skilling up.
///
/// Nothing else in the game is allowed to compute a final stat. If a number
/// shows up in the UI and in battle, it came from `resolve(_:in:)`.
enum ProgressionService {

    // MARK: - Scaling curves

    /// Stat multiplier by star grade. 1.35 per star is the whole curve: a 6★ is
    /// 4.48x a 1★, which is what makes a farmed 3★ genuinely usable and a 6★
    /// genuinely worth the cost.
    static func gradeMultiplier(stars: Int) -> Double {
        pow(1.35, Double(max(1, stars) - 1))
    }

    /// Stat multiplier by level. Linear so the level-up screen reads honestly.
    static func levelMultiplier(level: Int) -> Double {
        1 + 0.075 * Double(max(1, level) - 1)
    }

    static func maxLevel(stars: Int) -> Int { stars * 10 + 5 }

    /// XP needed to go from `level` to `level + 1`.
    static func experienceForNextLevel(level: Int, stars: Int) -> Int {
        let base = 120 + level * 95
        return Int(Double(base) * (1 + Double(stars) * 0.22))
    }

    // MARK: - Resolution

    /// Base stats before any equipment: grade, level and awakening only.
    static func baseStats(for unit: Unit, blueprint: UnitBlueprint) -> Stats {
        let grade = gradeMultiplier(stars: unit.stars)
        let levelScale = levelMultiplier(level: unit.level)
        let scale = grade * levelScale

        var stats = Stats(
            hp: blueprint.baseStats.hp * scale,
            atk: blueprint.baseStats.atk * scale,
            def: blueprint.baseStats.def * scale,
            // Speed and the rate stats do not scale. That is what makes a fast
            // 3★ support relevant next to a slow 5★ god.
            spd: blueprint.baseStats.spd,
            critRate: blueprint.baseStats.critRate,
            critDamage: blueprint.baseStats.critDamage,
            accuracy: blueprint.baseStats.accuracy,
            resistance: blueprint.baseStats.resistance
        )

        if unit.isAwakened, let awakening = blueprint.awakening {
            stats += awakening.statBonus
        }
        return stats
    }

    /// Joins a unit to its blueprint and equipped relics and computes finals.
    static func resolve(_ unit: Unit, relics allRelics: [Relic]) -> ResolvedUnit? {
        guard let blueprint = UnitDatabase.blueprint(unit.blueprintID) else { return nil }
        let equipped = unit.equippedRelics.values.compactMap { id in
            allRelics.first(where: { $0.id == id })
        }
        return resolve(unit, blueprint: blueprint, equipped: equipped)
    }

    static func resolve(_ unit: Unit, blueprint: UnitBlueprint, equipped: [Relic]) -> ResolvedUnit {
        let base = baseStats(for: unit, blueprint: blueprint)
        var flat = Stats.zero
        var percent: [StatKind: Double] = [:]

        // 1. Relic main stats and sub stats.
        for relic in equipped {
            for modifier in relic.allStats {
                accumulate(modifier, flat: &flat, percent: &percent, speedIsPercent: false)
            }
        }

        // 2. Completed set bonuses, once per completed set.
        var tally: [RelicSet: Int] = [:]
        for relic in equipped { tally[relic.set, default: 0] += 1 }
        for (set, count) in tally {
            let completions = count / set.piecesRequired
            guard completions > 0, let bonus = set.statBonus else { continue }
            for _ in 0..<completions {
                accumulate(bonus, flat: &flat, percent: &percent, speedIsPercent: true)
            }
        }

        // 3. Percentages always apply to the *base*, never to relic flats. That
        //    keeps "+35% ATK" meaning the same thing on every build.
        var final = base
        final.hp += flat.hp + base.hp * (percent[.hpPercent] ?? 0)
        final.atk += flat.atk + base.atk * (percent[.atkPercent] ?? 0)
        final.def += flat.def + base.def * (percent[.defPercent] ?? 0)
        final.spd += flat.spd + base.spd * (percent[.spd] ?? 0)
        final.critRate += flat.critRate
        final.critDamage += flat.critDamage
        final.accuracy += flat.accuracy
        final.resistance += flat.resistance

        let skills = blueprint.resolvedSkills(levels: unit.skillLevels, awakened: unit.isAwakened)

        return ResolvedUnit(
            unit: unit,
            blueprint: blueprint,
            relics: equipped,
            stats: final.clamped(),
            skills: skills
        )
    }

    private static func accumulate(
        _ modifier: StatModifier,
        flat: inout Stats,
        percent: inout [StatKind: Double],
        speedIsPercent: Bool
    ) {
        switch modifier.kind {
        case .hpFlat: flat.hp += modifier.value
        case .atkFlat: flat.atk += modifier.value
        case .defFlat: flat.def += modifier.value
        case .hpPercent, .atkPercent, .defPercent:
            percent[modifier.kind, default: 0] += modifier.value
        case .spd:
            if speedIsPercent {
                percent[.spd, default: 0] += modifier.value
            } else {
                flat.spd += modifier.value
            }
        case .critRate: flat.critRate += modifier.value
        case .critDamage: flat.critDamage += modifier.value
        case .accuracy: flat.accuracy += modifier.value
        case .resistance: flat.resistance += modifier.value
        }
    }

    // MARK: - Levelling

    /// Feeds experience into a unit, levelling as far as the grade allows.
    /// Returns the number of levels gained.
    @discardableResult
    static func grantExperience(_ amount: Int, to unit: inout Unit) -> Int {
        guard amount > 0 else { return 0 }
        let cap = maxLevel(stars: unit.stars)
        guard unit.level < cap else { return 0 }

        unit.experience += amount
        var gained = 0
        while unit.level < cap {
            let needed = experienceForNextLevel(level: unit.level, stars: unit.stars)
            guard unit.experience >= needed else { break }
            unit.experience -= needed
            unit.level += 1
            gained += 1
        }
        if unit.level >= cap { unit.experience = 0 }
        return gained
    }

    /// XP a unit is worth when fed to another unit.
    static func feedValue(of unit: Unit) -> Int {
        let gradeWorth = Int(pow(2.1, Double(unit.stars)) * 130)
        let levelWorth = (unit.level - 1) * 60 * unit.stars
        return gradeWorth + levelWorth
    }

    // MARK: - Evolution

    /// Cost in same-grade fodder units to evolve. Classic ladder: one per star.
    static func evolutionFodderRequired(currentStars: Int) -> Int { currentStars }

    static func drachmaCostToEvolve(currentStars: Int) -> Int {
        [0, 3_000, 8_000, 20_000, 60_000, 150_000][min(currentStars, 5)]
    }

    enum EvolutionError: Error, LocalizedError {
        case notMaxLevel
        case alreadyMaxGrade
        case notEnoughFodder(needed: Int, have: Int)
        case notEnoughDrachma(needed: Int)

        var errorDescription: String? {
            switch self {
            case .notMaxLevel: return "This unit must be at max level to evolve."
            case .alreadyMaxGrade: return "This unit is already 6★."
            case .notEnoughFodder(let needed, let have):
                return "Evolution needs \(needed) fodder units of the same grade — you selected \(have)."
            case .notEnoughDrachma(let needed):
                return "Evolution costs \(needed) drachma."
            }
        }
    }

    /// Raises the star grade, resetting to level 1 as the genre expects.
    static func evolve(_ unit: inout Unit, fodder: [Unit], wallet: inout Wallet) throws {
        guard unit.stars < 6 else { throw EvolutionError.alreadyMaxGrade }
        guard unit.level >= maxLevel(stars: unit.stars) else { throw EvolutionError.notMaxLevel }

        let needed = evolutionFodderRequired(currentStars: unit.stars)
        let valid = fodder.filter { $0.stars == unit.stars && $0.id != unit.id && !$0.isLocked }
        guard valid.count >= needed else {
            throw EvolutionError.notEnoughFodder(needed: needed, have: valid.count)
        }

        let cost = drachmaCostToEvolve(currentStars: unit.stars)
        guard wallet.drachma >= cost else { throw EvolutionError.notEnoughDrachma(needed: cost) }

        wallet.drachma -= cost
        unit.stars += 1
        unit.level = 1
        unit.experience = 0
    }

    // MARK: - Awakening

    enum AwakeningError: Error, LocalizedError {
        case notAwakenable
        case alreadyAwakened
        case missingEssence(id: String, needed: Int, have: Int)

        var errorDescription: String? {
            switch self {
            case .notAwakenable: return "This unit has no awakened form."
            case .alreadyAwakened: return "This unit is already awakened."
            case .missingEssence(let id, let needed, let have):
                return "Needs \(needed)x \(EssenceCatalog.name(for: id)) — you have \(have)."
            }
        }
    }

    static func awaken(_ unit: inout Unit, essences: inout [String: Int]) throws {
        guard let blueprint = UnitDatabase.blueprint(unit.blueprintID),
              let awakening = blueprint.awakening else { throw AwakeningError.notAwakenable }
        guard !unit.isAwakened else { throw AwakeningError.alreadyAwakened }

        for (id, needed) in awakening.essenceCost {
            let have = essences[id] ?? 0
            guard have >= needed else {
                throw AwakeningError.missingEssence(id: id, needed: needed, have: have)
            }
        }
        for (id, needed) in awakening.essenceCost {
            essences[id, default: 0] -= needed
        }
        unit.isAwakened = true
        // Awakening can add a skill slot (the passive); keep levels in step.
        while unit.skillLevels.count < blueprint.skills.count {
            unit.skillLevels.append(1)
        }
    }

    // MARK: - Skill-ups

    /// Feeding a duplicate raises one random un-maxed skill.
    @discardableResult
    static func applySkillUp(to unit: inout Unit, using rng: inout SeededRandom) -> Int? {
        guard let blueprint = UnitDatabase.blueprint(unit.blueprintID) else { return nil }
        while unit.skillLevels.count < blueprint.skills.count { unit.skillLevels.append(1) }

        let upgradable = blueprint.skills.indices.filter { index in
            let maxLevel = blueprint.skills[index].maxSkillLevel
            return unit.skillLevels[index] < maxLevel
        }
        guard let choice = rng.pickMutating(upgradable) else { return nil }
        unit.skillLevels[choice] += 1
        return choice
    }
}

/// Names for awakening materials. Kept separate so the awakening screen can list
/// requirements without the blueprint knowing about UI strings.
enum EssenceCatalog {
    static let names: [String: String] = [
        "essence_radiance_low": "Low Radiance Essence",
        "essence_radiance_mid": "Mid Radiance Essence",
        "essence_radiance_high": "High Radiance Essence",
        "essence_umbra_low": "Low Umbra Essence",
        "essence_umbra_mid": "Mid Umbra Essence",
        "essence_umbra_high": "High Umbra Essence",
        "essence_ember_mid": "Mid Ember Essence",
        "essence_tide_mid": "Mid Tide Essence",
        "essence_gale_mid": "Mid Gale Essence",
        "essence_magic_low": "Low Magic Essence",
        "essence_magic_mid": "Mid Magic Essence",
        "essence_magic_high": "High Magic Essence"
    ]

    static func name(for id: String) -> String { names[id] ?? id }
}

// MARK: - Fusion

/// The fusion hexagram: four raised units traded for one the gacha never gives.
///
/// This is the genre's strongest mid-game goal, and almost all of it already
/// existed here — evolution, levelling, the collection, the star grades. What
/// was missing was a reason to keep the third Shabti instead of feeding it. A
/// recipe names four corners; each corner names one *elemental variant* by id
/// with the grade and the level it must be at, which is the hexagram's own
/// rule (the genre asks for a specific monster, never "any wind unit"), and
/// the reward is a unit that is not in `UnitDatabase.summonPool` at all.
///
/// The table is the exclusion list: `fusionOnlyIDs` is derived from it and
/// `UnitDatabase.summonPool` filters on that, so a recipe cannot promise
/// something the gacha is quietly still handing out. The two cannot drift
/// because there is only one list.
///
/// Every prize is the light or the dark variant of a family whose other three
/// elements stay summonable, which is the genre's convention: the light and
/// the dark of a family are the ones you cannot pull. Hades was the wind form
/// while only three of his five cards had been painted — a prize whose card is
/// a letter on a gradient is not a prize — and moved to the dark one the day
/// the batch finished him, which is also the form the helm belongs to. Six ids
/// out of the seventy-eight in the pool: a banner still has plenty to give.
enum FusionService {

    // MARK: Table types

    /// One corner of the hexagram: which character, at what grade and level.
    struct Ingredient: Equatable, Sendable {
        /// A blueprint id — `anubis_radiance`, not `anubis`.
        var blueprintID: String
        /// The grade the copy must have reached. Above the family's natural
        /// grade on purpose: a corner is an evolution project, not a pull.
        var stars: Int
        var level: Int

        var blueprint: UnitBlueprint? { UnitDatabase.blueprint(blueprintID) }

        /// "Anubis (Radiance)" — what the panel calls the corner. Falls back to
        /// the raw id so a typo in the table is visible on screen rather than
        /// blank.
        var title: String {
            guard let blueprint = blueprint else { return blueprintID }
            return "\(blueprint.name) (\(blueprint.element.displayName))"
        }

        /// "4★ Lv.30": the corner's price in one phrase.
        var requirement: String { "\(stars)★ Lv.\(level)" }
    }

    /// One hexagram: a name, a line of lore, four corners and a bill.
    struct Recipe: Identifiable, Equatable, Sendable {
        var id: String
        var name: String
        /// Blueprint id of the reward. Never in the summon pool — see
        /// `fusionOnlyIDs`.
        var resultID: String
        var drachmaCost: Int
        var lore: String
        var ingredients: [Ingredient]

        var result: UnitBlueprint? { UnitDatabase.blueprint(resultID) }

        /// Whether the gacha really cannot produce this — measured against the
        /// pool rather than asserted. `UnitDatabase.summonPool` filters on
        /// `fusionOnlyIDs`, and if that filter is ever dropped the panel says
        /// so out loud, the way `Color(hex:)` falls back to magenta instead of
        /// to nothing.
        var isExclusive: Bool { !UnitDatabase.summonPool.contains(resultID) }
    }

    /// Why a corner is not filled. The panel shows this in place of a tick, so
    /// the player knows whether to summon, to evolve or to level.
    enum Shortfall: Equatable, Sendable {
        case notOwned
        case grade(have: Int, need: Int)
        case level(have: Int, need: Int)
        /// Every copy is locked or standing on a team. Fusion never eats one of
        /// those, so the player is told rather than quietly robbed.
        case reserved

        /// The full phrase, for the sentence under the Fuse button.
        var summary: String {
            switch self {
            case .notOwned: return "none owned"
            case .grade(let have, let need): return "\(have)★ / \(need)★"
            case .level(let have, let need): return "Lv.\(have) / \(need)"
            case .reserved: return "locked or on a team"
            }
        }

        /// The same thing in a corner tile, which is 62 points wide. Anything
        /// longer than about ten characters shrinks itself into a smudge, so
        /// the two wordy cases lose their words and the sentence under the
        /// button carries them instead.
        var short: String {
            switch self {
            case .notOwned: return "none"
            case .reserved: return "reserved"
            case .grade, .level: return summary
            }
        }
    }

    /// One corner as the player stands today.
    struct Slot: Identifiable, Sendable {
        var ingredient: Ingredient
        /// The unit fusion would consume for this corner. Nil when it is short.
        var unitID: UUID?
        var shortfall: Shortfall?

        /// A recipe never names the same variant twice, so the corner's
        /// blueprint id identifies it inside its own panel.
        var id: String { ingredient.blueprintID }
        var isMet: Bool { unitID != nil }
    }

    /// A recipe measured against a save: what would be spent, what is short.
    struct Plan: Identifiable, Sendable {
        var recipe: Recipe
        var slots: [Slot]
        var costMet: Bool

        var id: String { recipe.id }
        var missing: [Slot] { slots.filter { !$0.isMet } }
        var canFuse: Bool { missing.isEmpty && costMet }

        /// The one line a disabled Fuse button carries. Naming the first short
        /// corner beats "requirements not met", because the player can act on
        /// it; more than one short corner is a count, because the corner tiles
        /// already mark which ones.
        var blocker: String? {
            if missing.count > 1 { return "\(missing.count) corners short" }
            if let slot = missing.first {
                return "\(slot.ingredient.title): \(slot.shortfall?.summary ?? "not ready")"
            }
            if !costMet { return "Needs \(recipe.drachmaCost) drachma" }
            return nil
        }
    }

    enum FusionError: Error, LocalizedError {
        case unknownResult(id: String)
        case ingredientShort(name: String, detail: String)
        case notEnoughDrachma(needed: Int)

        var errorDescription: String? {
            switch self {
            case .unknownResult(let id):
                return "This recipe points at a unit that does not exist (\(id))."
            case .ingredientShort(let name, let detail):
                return "\(name) is not ready — \(detail)."
            case .notEnoughDrachma(let needed):
                return "Fusion costs \(needed) drachma."
            }
        }
    }

    // MARK: - The table

    /// Six hexagrams, two per difficulty step.
    ///
    /// The shape of the ladder is the point. The first two ask for four units
    /// at 4★ — three of them commons the player is already drowning in — and
    /// one god at the 4★ level cap: a weekend. The middle two raise two corners
    /// to 5★, which is an evolution ladder each (4★→5★ is four 4★ fodder and
    /// 60,000 drachma). The last two ask for 5★ everywhere, including a common
    /// evolved twice, and cost 120,000 on top; that is a month, and the reward
    /// is a 5★ god no amount of summoning can produce.
    ///
    /// Corners cross pantheons on purpose. A recipe that could be filled out of
    /// one banner would be a shopping list; one that wants a Greek hoplite, an
    /// Egyptian shabti and a Norse watchman is a reason to summon on all three.
    ///
    /// The drachma figures sit against the numbers `tools/balance.py --economy`
    /// prints: a full chapter-1 clear pays 7,350, one relic to +15 expects
    /// about 300,000 and the whole 6★ evolution ladder is 241,000. So 40,000 is
    /// five chapters' worth of first clears — noticeable, not painful — and
    /// 120,000 is a real choice against a relic. The evolving the corners need
    /// costs more than any of it, which is as it should be: the bill is the
    /// units, not the coin.
    static let recipes: [Recipe] = [
        Recipe(
            id: "red_beer",
            name: "The Red Beer",
            resultID: "sekhmet_radiance",
            drachmaCost: 40_000,
            lore: "Ra sent his Eye out to punish humanity and then could not call her back. The gods dyed seven thousand jars of beer red, flooded a field with it, and let her drink the ground dry; she woke gentle, and has been the sun's own lioness since. The circle needs the field, the jars, and somebody to pour.",
            ingredients: [
                Ingredient(blueprintID: "shabti_radiance", stars: 4, level: 30),
                Ingredient(blueprintID: "jackal_warrior_ember", stars: 4, level: 30),
                Ingredient(blueprintID: "satyr_ember", stars: 4, level: 30),
                Ingredient(blueprintID: "anubis_radiance", stars: 4, level: 45)
            ]
        ),
        Recipe(
            id: "burnished_shield",
            name: "The Burnished Shield",
            resultID: "ares_radiance",
            drachmaCost: 40_000,
            lore: "War the way a city means it: the line at the gate at dawn, shields overlapping, nobody enjoying himself. Greece never much liked Ares — but the men on the wall prayed to him anyway, and it is their bronze that polishes him bright.",
            ingredients: [
                Ingredient(blueprintID: "hoplite_radiance", stars: 4, level: 30),
                Ingredient(blueprintID: "shabti_ember", stars: 4, level: 30),
                Ingredient(blueprintID: "harpy_gale", stars: 4, level: 30),
                Ingredient(blueprintID: "heracles_radiance", stars: 4, level: 45)
            ]
        ),
        Recipe(
            id: "dark_moon_eye",
            name: "The Dark Moon Eye",
            resultID: "horus_umbra",
            drachmaCost: 80_000,
            lore: "Set tore out the falcon's left eye and stamped the pieces into the sand; Thoth found them and put the eye back together, all but a sixty-fourth part. That missing piece is why the moon wanes, and why this eye opens in the dark.",
            ingredients: [
                Ingredient(blueprintID: "shabti_umbra", stars: 4, level: 45),
                Ingredient(blueprintID: "harpy_umbra", stars: 4, level: 45),
                Ingredient(blueprintID: "anubis_tide", stars: 5, level: 30),
                Ingredient(blueprintID: "perseus_gale", stars: 5, level: 30)
            ]
        ),
        Recipe(
            id: "storm_below",
            name: "The Storm Below",
            resultID: "zeus_umbra",
            drachmaCost: 80_000,
            lore: "Before the first ploughing a farmer prays to Zeus Under-the-Earth and to Demeter, and means the rain that stays in the ground rather than the bolt that splits the oak. He answers to that name too. Same god, darker coat, and the harvest is his.",
            ingredients: [
                Ingredient(blueprintID: "hoplite_umbra", stars: 4, level: 45),
                Ingredient(blueprintID: "satyr_umbra", stars: 4, level: 45),
                Ingredient(blueprintID: "heracles_ember", stars: 5, level: 30),
                Ingredient(blueprintID: "heimdall_tide", stars: 5, level: 30)
            ]
        ),
        Recipe(
            id: "sealed_book",
            name: "The Sealed Book",
            resultID: "thoth_umbra",
            drachmaCost: 120_000,
            lore: "The book that holds every word the god knows was sunk in the river in a box of iron, in a box of bronze, in a box of ivory, in a box of silver, in a box of gold, with a serpent coiled round it that came back each time it was killed. The prince who finally took it read it, and had buried his children by morning.",
            ingredients: [
                Ingredient(blueprintID: "shabti_gale", stars: 5, level: 30),
                Ingredient(blueprintID: "jackal_warrior_radiance", stars: 5, level: 30),
                Ingredient(blueprintID: "anubis_umbra", stars: 5, level: 40),
                Ingredient(blueprintID: "heimdall_radiance", stars: 5, level: 40)
            ]
        ),
        Recipe(
            id: "unseen_helm",
            name: "The Unseen Helm",
            resultID: "hades_umbra",
            drachmaCost: 120_000,
            lore: "The cyclopes made him a helm that takes its wearer out of sight, and he lends it out: to the hero who wanted the gorgon's head, to the gods when they fought the giants. It always comes back. What comes back wearing it is not always what borrowed it.",
            ingredients: [
                Ingredient(blueprintID: "satyr_gale", stars: 5, level: 30),
                Ingredient(blueprintID: "harpy_gale", stars: 5, level: 40),
                Ingredient(blueprintID: "perseus_umbra", stars: 5, level: 40),
                Ingredient(blueprintID: "heracles_umbra", stars: 5, level: 40)
            ]
        )
    ]

    /// The ids the gacha must never produce, taken straight off the table so
    /// the promise and the pool cannot disagree. `UnitDatabase.summonPool`
    /// filters on this; nothing else needs to know.
    ///
    /// Only literals go into `recipes`, so reading this cannot re-enter
    /// `UnitDatabase` while `summonPool` is still being built.
    static let fusionOnlyIDs: Set<String> = Set(recipes.map { $0.resultID })

    static func isFusionOnly(_ blueprintID: String) -> Bool {
        fusionOnlyIDs.contains(blueprintID)
    }

    /// Ids in the table that no blueprint answers to: empty, or the table has a
    /// typo in it. Worth asserting from a test, because a bad id shows up in
    /// the game only as a corner that can never be filled.
    static var brokenReferences: [String] {
        recipes.flatMap { recipe -> [String] in
            var broken: [String] = []
            if UnitDatabase.blueprint(recipe.resultID) == nil { broken.append(recipe.resultID) }
            broken.append(contentsOf: recipe.ingredients
                .map { $0.blueprintID }
                .filter { UnitDatabase.blueprint($0) == nil })
            return broken
        }
    }

    // MARK: - Eligibility

    /// Units fusion must never consume: locked, or standing on a team.
    ///
    /// Losing the campaign leader to a fusion is the kind of thing a player
    /// never forgives, so every team counts — campaign, both arena lines and
    /// the saved presets — even when the unit is unlocked. Taking it off the
    /// team is one tap; getting it back is not.
    static func reservedUnitIDs(of player: Player) -> Set<UUID> {
        var ids = Set(player.units.filter { $0.isLocked }.map { $0.id })
        ids.formUnion(player.campaignTeam.unitIDs)
        ids.formUnion(player.arenaOffenseTeam.unitIDs)
        ids.formUnion(player.arenaDefenseTeam.unitIDs)
        for team in player.savedTeams { ids.formUnion(team.unitIDs) }
        return ids
    }

    /// Measures a recipe against a save: which corner each owned unit fills and
    /// what the rest are short of.
    ///
    /// Nothing here mutates, so the screen can call it every time it draws and
    /// `fuse` can call it again to check its own work.
    static func plan(for recipe: Recipe, player: Player) -> Plan {
        let reserved = reservedUnitIDs(of: player)
        var spoken: Set<UUID> = []
        var slots: [Slot] = []

        for ingredient in recipe.ingredients {
            let copies = player.units.filter {
                $0.blueprintID == ingredient.blueprintID && !spoken.contains($0.id)
            }
            let free = copies.filter { !reserved.contains($0.id) }
            let qualifying = free
                .filter { $0.stars >= ingredient.stars && $0.level >= ingredient.level }
                // The weakest qualifying copy goes in. A player who has raised
                // two of a character should not have to check which one the
                // hexagram took.
                .sorted { ($0.stars, $0.level) < ($1.stars, $1.level) }

            if let chosen = qualifying.first {
                spoken.insert(chosen.id)
                slots.append(Slot(ingredient: ingredient, unitID: chosen.id, shortfall: nil))
            } else {
                slots.append(Slot(
                    ingredient: ingredient,
                    unitID: nil,
                    shortfall: shortfall(for: ingredient, copies: copies, free: free)
                ))
            }
        }

        return Plan(
            recipe: recipe,
            slots: slots,
            costMet: player.wallet.drachma >= recipe.drachmaCost
        )
    }

    /// The one thing to fix, measured against the nearest copy the player owns.
    private static func shortfall(for ingredient: Ingredient, copies: [Unit], free: [Unit]) -> Shortfall {
        guard !copies.isEmpty else { return .notOwned }
        guard let best = free.max(by: { ($0.stars, $0.level) < ($1.stars, $1.level) }) else {
            return .reserved
        }
        if best.stars < ingredient.stars {
            return .grade(have: best.stars, need: ingredient.stars)
        }
        return .level(have: best.level, need: ingredient.level)
    }

    // MARK: - Fusing

    /// Spends the four corners and the drachma, and returns the new unit.
    ///
    /// The result arrives at its natural grade, level 1 and **not** awakened:
    /// the hexagram gives the character, and the Hall of Ka still has something
    /// to sell the player afterwards. A duplicate is not folded into a skill-up
    /// the way a summoned one is — the whole unit is the prize.
    @discardableResult
    static func fuse(_ recipe: Recipe, player: inout Player) throws -> Unit {
        guard let blueprint = UnitDatabase.blueprint(recipe.resultID) else {
            throw FusionError.unknownResult(id: recipe.resultID)
        }

        // Not `let plan = plan(...)`: a local of that name shadows the static
        // it is calling and Swift reads it as using itself before it exists.
        let assessment = plan(for: recipe, player: player)
        if let short = assessment.missing.first {
            throw FusionError.ingredientShort(
                name: short.ingredient.title,
                detail: short.shortfall?.summary ?? "not ready"
            )
        }
        guard player.wallet.drachma >= recipe.drachmaCost else {
            throw FusionError.notEnoughDrachma(needed: recipe.drachmaCost)
        }

        let consumed = assessment.slots.compactMap { $0.unitID }
        player.wallet.drachma -= recipe.drachmaCost

        // Take the relics off the corners before they disappear, exactly as
        // evolution fodder does; a relic that goes with its wearer is gone.
        for id in consumed {
            guard let index = player.units.firstIndex(where: { $0.id == id }) else { continue }
            for slot in Array(player.units[index].equippedRelics.keys) {
                RelicService.unequip(slot: slot, from: id, player: &player)
            }
        }
        player.units.removeAll { consumed.contains($0.id) }

        var unit = Unit(blueprint: blueprint)
        unit.acquiredFrom = "fusion"
        player.codex.insert(blueprint.id)
        player.units.append(unit)
        return unit
    }
}
