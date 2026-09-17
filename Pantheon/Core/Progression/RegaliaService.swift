import Foundation

/// The Regalia: one named item per family, the genre's post-2020 answer to
/// "what is a fifth copy for" (`Docs/PLAN.md`, *Artifacts — the last item
/// on the order*, option 3). Reads a family's regalia off the tables in
/// `UnitDatabase+Families.swift` (`regaliaNames`, `regaliaBlurbs`, the
/// hand-written templates) and the row's kit, decides whether a unit has
/// unlocked it, and raises its level when a duplicate is fed past the
/// skill-up cap. Nothing here rolls: the same family is the same item on
/// every save.
enum RegaliaService {

    /// The eleven families written out by hand (`UnitDatabase.swift`,
    /// `UnitDatabase+Roster.swift`), whose templates are chosen by hand too.
    static let handwrittenFamilies: [String] = [
        "anubis", "sekhmet", "thoth", "shabti", "zeus", "ares", "heracles", "perseus", "hoplite", "satyr", "harpy",
    ]

    /// Every family key that has a regalia: the eleven and the table's rows.
    static let familyKeys: [String] = handwrittenFamilies + UnitDatabase.familyRows.map(\.key)

    /// A family's template: the hand-written choice, else its row's kit.
    private static let templatesByFamily: [String: RegaliaTemplate] = {
        var table = UnitDatabase.handwrittenRegaliaTemplates
        for row in UnitDatabase.familyRows where table[row.key] == nil {
            table[row.key] = RegaliaTemplate.template(for: row.kit)
        }
        return table
    }()

    // MARK: - Reading a family

    /// The family a blueprint belongs to: its id less the element suffix
    /// (`zeus_ember` → `zeus`), or the id itself for the one-of-a-kind
    /// (`shabti`, the starter). A campaign enemy's id (`enemy_minotaur`,
    /// `apep`) comes back unchanged and names no family in the tables.
    static func familyKey(of blueprintID: String) -> String {
        for element in Element.allCases {
            let suffix = "_" + element.rawValue
            if blueprintID.hasSuffix(suffix) {
                return String(blueprintID.dropLast(suffix.count))
            }
        }
        return blueprintID
    }

    static func template(forFamily key: String) -> RegaliaTemplate? {
        templatesByFamily[key]
    }

    /// The family's regalia at a level, or nil for a family that has none
    /// (an enemy, a boss, an id the tables have not reached).
    static func regalia(forFamily key: String, level: Int) -> Regalia? {
        guard let name = UnitDatabase.regaliaNames[key],
              let template = template(forFamily: key) else { return nil }
        return Regalia(
            familyKey: key,
            name: name,
            blurb: UnitDatabase.regaliaBlurbs[key] ?? "",
            template: template,
            level: min(RegaliaTemplate.levels, max(1, level))
        )
    }

    /// The regalia of a blueprint's family at a level, unlocked or not: what
    /// the unit sheet names before the awakening.
    static func regalia(forBlueprint blueprintID: String, level: Int = 1) -> Regalia? {
        regalia(forFamily: familyKey(of: blueprintID), level: level)
    }

    // MARK: - A unit's own

    /// The stored level, 1...5; nil in the save is level I.
    static func level(of unit: Unit) -> Int {
        min(RegaliaTemplate.levels, max(1, unit.regaliaLevel ?? 1))
    }

    /// Unlocked by AWAKENING, the design's rule. A family that has no
    /// awakened form — every 3★ — unlocks its regalia at 6★ instead: the
    /// evolution is that family's summit, and a name on the sheet that no
    /// deed could ever light would be a lie on the screen. One clause; the
    /// lead can strike it.
    static func isUnlocked(_ unit: Unit, blueprint: UnitBlueprint) -> Bool {
        if unit.isAwakened { return true }
        return blueprint.awakening == nil && unit.stars >= 6
    }

    /// What the unit has to do to unlock it, for the sheet and the plate.
    static func unlockLine(for blueprint: UnitBlueprint) -> String {
        blueprint.awakening == nil ? "Evolve to 6★ to unlock" : "Awaken to unlock"
    }

    /// The unit's regalia, carried into battle: nil until it is unlocked.
    static func regalia(for unit: Unit, blueprint: UnitBlueprint) -> Regalia? {
        guard isUnlocked(unit, blueprint: blueprint) else { return nil }
        return regalia(forBlueprint: blueprint.id, level: level(of: unit))
    }

    /// Whether every skill is at its skill-up cap — the gate a duplicate has
    /// to pass before it feeds the regalia. Reads the same caps
    /// `ProgressionService.applySkillUp` does, a missing level counting as 1.
    static func skillsAreCapped(_ unit: Unit, blueprint: UnitBlueprint) -> Bool {
        for index in blueprint.skills.indices {
            let level = index < unit.skillLevels.count ? unit.skillLevels[index] : 1
            if level < blueprint.skills[index].maxSkillLevel { return false }
        }
        return true
    }

    /// How many skill-ups are still owed before a duplicate reaches the
    /// regalia.
    static func skillUpsRemaining(_ unit: Unit, blueprint: UnitBlueprint) -> Int {
        var remaining = 0
        for index in blueprint.skills.indices {
            let level = index < unit.skillLevels.count ? unit.skillLevels[index] : 1
            remaining += max(0, blueprint.skills[index].maxSkillLevel - level)
        }
        return remaining
    }

    /// A copy of the same FAMILY, any element: the regalia is the family's.
    static func isSameFamily(_ fodder: Unit, as unit: Unit) -> Bool {
        fodder.id != unit.id && familyKey(of: fodder.blueprintID) == familyKey(of: unit.blueprintID)
    }

    enum FeedOutcome: Equatable, Sendable {
        /// The level rose to this.
        case raised(to: Int)
        case notSameFamily
        /// Skill-ups first: this many are still owed.
        case skillsNotCapped(remaining: Int)
        case alreadyMax
        case noSuchUnit
    }

    /// Feeds one duplicate into a unit's regalia: the level rises by one when
    /// the duplicate is of the family and every skill is already capped, and
    /// never past V. The level banks whether or not the regalia is unlocked
    /// yet, so a fifth copy fed before the awakening is not fed for nothing.
    /// Pure on the unit; the caller removes the fodder, as the Hall of Ka
    /// does for a skill-up (`GameStore.levelUp`).
    @discardableResult
    static func feed(duplicate: Unit, into unit: inout Unit) -> FeedOutcome {
        guard isSameFamily(duplicate, as: unit) else { return .notSameFamily }
        guard let blueprint = UnitDatabase.blueprint(unit.blueprintID) else { return .noSuchUnit }
        guard skillsAreCapped(unit, blueprint: blueprint) else {
            return .skillsNotCapped(remaining: skillUpsRemaining(unit, blueprint: blueprint))
        }
        let current = level(of: unit)
        guard current < RegaliaTemplate.levels else { return .alreadyMax }
        unit.regaliaLevel = current + 1
        return .raised(to: current + 1)
    }

    /// The same, on a unit in the save by id — the shape the Hall of Ka's
    /// feed path calls from inside `GameStore.update`.
    @discardableResult
    static func feed(duplicate: Unit, into unitID: UUID, player: inout Player) -> FeedOutcome {
        guard let index = player.units.firstIndex(where: { $0.id == unitID }) else { return .noSuchUnit }
        return feed(duplicate: duplicate, into: &player.units[index])
    }

    /// What raises it, for the sheet.
    static let raisingLine = "Feed a duplicate of the family in the Hall of Ka once every skill is at its cap: "
        + "each copy past the cap raises the regalia a level, to V."
}
