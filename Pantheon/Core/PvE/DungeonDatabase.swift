import Foundation

/// The Halls of Essence: one hall per element, five floors each, a boss on
/// every floor, open every day and cleared as often as the energy holds. This
/// is where the awakening essences come from — the campaign drops magic
/// essences, the halls drop the element's own — and where the relics worth
/// keeping start to appear, because the floor sets the grade.
///
/// A floor is a `Stage` whose chapter is the hall, so the campaign's plumbing
/// (`CampaignService.startBattle`, `applyRewards`, the briefing, the battle
/// screen, auto-repeat) runs a floor with no special case: a hall's progress
/// lives in `campaignProgress` under the hall's id, the next floor opens when
/// the one before it falls, and every clear pays — only the divinity is
/// first-clear.
enum DungeonDatabase {

    struct Hall: Identifiable, Sendable {
        var id: String
        var element: Element
        var name: String
        var summary: String
        var environment: BattleEnvironment
        var chapter: Chapter

        var floors: [Stage] { chapter.stages }
    }

    static let floorCount = 5

    static let halls: [Hall] = [
        hall(
            id: "hall_ember", element: .ember, name: "Hall of Embers",
            summary: "A furnace with a floor. The heat comes up through the stone and the things that live in it do not mind.",
            environment: .duatGate,
            roster: ["enemy_cyclops", "enemy_berserker", "sandstone_sentinel"],
            bossID: "apep"
        ),
        hall(
            id: "hall_tide", element: .tide, name: "Hall of Tides",
            summary: "The sea comes in under the door twice a day. What it leaves behind has teeth.",
            environment: .aegeanCliffs,
            roster: ["enemy_frost_troll", "enemy_frost_troll", "enemy_amazon"],
            bossID: "boss_hydra"
        ),
        hall(
            id: "hall_gale", element: .gale, name: "Hall of Gales",
            summary: "The wind never stops in here, and it carries the giants' winter down from the roof.",
            environment: .midgardFjord,
            roster: ["serpopard", "enemy_amazon", "enemy_valkyrie"],
            bossID: "boss_jotunn"
        ),
        hall(
            id: "hall_radiance", element: .radiance, name: "Hall of Radiance",
            summary: "No shadow anywhere. The choosers of the slain patrol it, and they choose.",
            environment: .olympusGate,
            roster: ["sun_scarab", "enemy_medusa", "enemy_valkyrie"],
            bossID: "enemy_valkyrie"
        ),
        hall(
            id: "hall_umbra", element: .umbra, name: "Hall of Shadows",
            summary: "The lamps are painted on. The devourer waits at the bottom, and she has never once been full.",
            environment: .serpentDeep,
            roster: ["enemy_draugr", "enemy_minotaur", "shabti"],
            bossID: "ammit"
        ),
    ]

    static func hall(_ id: String) -> Hall? { halls.first(where: { $0.id == id }) }

    /// The scroll a hall drops: its element's, or the light & dark scroll
    /// for the two that have no scroll of their own.
    static func scroll(for element: Element) -> ScrollType {
        switch element {
        case .ember: return .ember
        case .tide: return .tide
        case .gale: return .gale
        case .radiance, .umbra: return .lightDark
        }
    }

    /// The hall a stage belongs to, if it is a floor of one.
    static func hall(containing stage: Stage) -> Hall? { hall(stage.chapterID) }

    static var allFloors: [Stage] { halls.flatMap(\.floors) }

    // MARK: - Building a hall

    /// Five floors that climb from a 4★ warm-up to a 6★ wall. The grade of
    /// the mobs rises with the floor rather than their level, the way the
    /// genre does it, and a chapter-wide multiplier tightens the top floors;
    /// the boss keeps its own grade when that is higher and stands at x1.4.
    /// The numbers are in `tools/balance.py` (`HALLS`) and were tuned
    /// there: floor 1 for a levelled 4★ team, floor 3 for 5★s with relics,
    /// floor 5 for a maxed 6★ team.
    static func hall(
        id: String, element: Element, name: String, summary: String,
        environment: BattleEnvironment, roster: [String], bossID: String
    ) -> Hall {
        var stages: [Stage] = []
        for floor in 1...floorCount {
            let level = 20 + floor * 8
            let stars = min(6, 3 + floor)
            let difficulty = 0.75 + Double(floor) * 0.10
            var enemies: [EnemySpawn] = []
            for slot in 0..<3 {
                let blueprintID = roster[(floor + slot) % roster.count]
                enemies.append(EnemySpawn(blueprintID: blueprintID, level: level, stars: stars, statMultiplier: difficulty))
            }
            let bossNatural = UnitDatabase.blueprint(bossID)?.naturalStars ?? stars
            enemies.append(EnemySpawn(
                blueprintID: bossID, level: level, stars: max(stars, bossNatural),
                statMultiplier: difficulty * 1.4
            ))

            let essence = "essence_\(element.rawValue)_mid"
            let high = "essence_\(element.rawValue)_high"
            stages.append(Stage(
                id: "\(id)_\(floor)",
                chapterID: id,
                index: floor,
                name: "\(name) B\(floor)",
                energyCost: 5 + floor,
                recommendedPower: Int(3_000 * pow(1.65, Double(floor - 1))),
                enemies: enemies,
                rewards: StageRewards(
                    drachma: 800 + floor * 300,
                    playerExperience: 40 + floor * 12,
                    unitExperience: 300 + floor * 120,
                    relicChance: min(1.0, 0.5 + Double(floor) * 0.1),
                    relicGrade: min(6, 2 + floor),
                    essenceChances: [essence: min(1.0, 0.5 + Double(floor) * 0.1), high: Double(floor) * 0.1],
                    scrollChances: [scroll(for: element).rawValue: 0.12],
                    firstClearDivinity: 30
                ),
                environment: environment,
                isBoss: true
            ))
        }
        let chapter = Chapter(id: id, pantheon: environment.pantheon, name: name, summary: summary, stages: stages)
        return Hall(id: id, element: element, name: name, summary: summary, environment: environment, chapter: chapter)
    }
}
