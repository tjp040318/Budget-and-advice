import Foundation

/// Every unit definition in the game.
///
/// Blueprint stats are expressed at **1★, level 1**. `ProgressionService` scales
/// them by grade and level, which keeps this file readable: a designer compares
/// two units by looking at two numbers, not at two curves.
///
/// Adding a character is adding one static property and one line in `all`. The
/// summon pool is separate from `all` so that campaign enemies and boss units
/// can exist without ever appearing in the gacha.
///
/// The numbers below are not guesses. They were tuned against `tools/balance.py`,
/// which mirrors these constants and plays the campaign a few hundred times per
/// stage — see `Docs/BALANCE.md` for what the curve is supposed to look like.
enum UnitDatabase {

    // MARK: - Registry

    static let all: [UnitBlueprint] = anubisFamily + [
        shabti,
        serpopard,
        sunScarab,
        sandstoneSentinel,
        ammit,
        apep
    ]

    private static let index: [String: UnitBlueprint] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    static func blueprint(_ id: String) -> UnitBlueprint? { index[id] }

    /// Unit ids the gacha is allowed to produce. Enemies are deliberately absent.
    static let summonPool: [String] = anubisFamily.map { $0.id }

    static func summonable(stars: Int) -> [UnitBlueprint] {
        summonPool.compactMap { blueprint($0) }.filter { $0.naturalStars == stars }
    }

    // MARK: - THE ANUBIS FAMILY
    //
    // Five elemental variants of one character, the way the genre does it: the
    // same silhouette and the same kit *shape*, differentiated by stat lean, by
    // one changed effect per skill, and by leader skill. They are five separate
    // summonable units and five separate collection entries.
    //
    // Crucially they are ONE 3D MODEL. Every variant points at `assetName:
    // "anubis"` and differs only by `auraHex`, which the renderer uses to tint
    // the rim light, the aura and the summon beam. That is how the genre keeps
    // an enormous roster affordable, and it means the art cost of this whole
    // family is a single Meshy export. See Docs/ART_PIPELINE.md.
    //
    // Anubis is the family to build the pipeline against for three reasons.
    // The revive in slot 2 forces the engine to handle dead-unit targeting,
    // state restoration and turn-order re-entry — the parts most likely to be
    // quietly broken. A kit that heals, strips, cleanses, shields, brands and
    // revives touches every field in the data model. And a jackal head *is* the
    // silhouette, which sidesteps the uncanny human face that image-to-3D tools
    // are worst at.

    static let anubisEmber    = anubisVariant(.ember)
    static let anubisTide     = anubisVariant(.tide)
    static let anubisGale     = anubisVariant(.gale)
    static let anubisRadiance = anubisVariant(.radiance)
    static let anubisUmbra    = anubisVariant(.umbra)

    /// The unit a new account starts with.
    static var starter: UnitBlueprint { anubisUmbra }

    /// Everything in the Anubis family, in wheel order.
    static var anubisFamily: [UnitBlueprint] {
        [anubisEmber, anubisTide, anubisGale, anubisRadiance, anubisUmbra]
    }

    /// Per-element identity: name, stat lean, and the one thing each variant
    /// does that the others do not.
    private struct AnubisFlavour {
        var id: String
        var name: String
        var epithet: String
        var awakenedName: String
        var role: CombatRole
        var hp: Double
        var atk: Double
        var def: Double
        var spd: Double
        var auraHex: String
        var leader: LeaderSkill
        var judgement: DamageSpec
        var judgementExtras: [UtilityEffect]
        var judgementStatus: [StatusSpec]
        var riteStatus: StatusKind
        var reviveFraction: Double
        var strikeStatus: StatusSpec
        var essence: String
    }

    private static func anubisFlavour(_ element: Element) -> AnubisFlavour {
        switch element {
        case .ember:
            return AnubisFlavour(
                id: "anubis_ember", name: "Anubis",
                epithet: "of the Burning Sands",
                awakenedName: "Anubis, Keeper of the Ash Road",
                role: .attacker,
                hp: 422, atk: 32, def: 25, spd: 104,
                auraHex: "#F2703C",
                leader: LeaderSkill(stat: .atkPercent, amount: 0.33, scope: .pantheon(.egyptian)),
                judgement: DamageSpec(multiplier: 4.30),
                judgementExtras: [],
                judgementStatus: [StatusSpec(.burn, chance: 0.75, turns: 2, target: .singleEnemy)],
                riteStatus: .attackUp,
                reviveFraction: 0.50,
                strikeStatus: StatusSpec(.brand, chance: 0.30, turns: 2, target: .singleEnemy, rollsPerHit: true),
                essence: "essence_ember_mid"
            )
        case .tide:
            return AnubisFlavour(
                id: "anubis_tide", name: "Anubis",
                epithet: "of the Still Waters",
                awakenedName: "Anubis, Ferryman of the Reed Sea",
                role: .defender,
                hp: 566, atk: 24, def: 32, spd: 101,
                auraHex: "#3C9BF2",
                leader: LeaderSkill(stat: .hpPercent, amount: 0.40, scope: .pantheon(.egyptian)),
                judgement: DamageSpec(multiplier: 3.60),
                judgementExtras: [.lifesteal(0.40)],
                judgementStatus: [],
                riteStatus: .recovery,
                reviveFraction: 0.50,
                strikeStatus: StatusSpec(.brand, chance: 0.30, turns: 2, target: .singleEnemy, rollsPerHit: true),
                essence: "essence_tide_mid"
            )
        case .gale:
            return AnubisFlavour(
                id: "anubis_gale", name: "Anubis",
                epithet: "of the Desert Wind",
                awakenedName: "Anubis, Breath of the Khamsin",
                role: .controller,
                hp: 442, atk: 27, def: 26, spd: 116,
                auraHex: "#4FC98A",
                leader: LeaderSkill(stat: .spd, amount: 0.23, scope: .pantheon(.egyptian)),
                judgement: DamageSpec(multiplier: 3.70),
                judgementExtras: [.attackBarChange(-0.25, chance: 0.70, .singleEnemy)],
                judgementStatus: [StatusSpec(.speedDown, chance: 0.70, turns: 2, target: .singleEnemy)],
                riteStatus: .speedUp,
                reviveFraction: 0.50,
                strikeStatus: StatusSpec(.speedDown, chance: 0.25, turns: 2, target: .singleEnemy, rollsPerHit: true),
                essence: "essence_gale_mid"
            )
        case .radiance:
            return AnubisFlavour(
                id: "anubis_radiance", name: "Anubis",
                epithet: "of the Solar Barque",
                awakenedName: "Anubis, Pilot of the Night Sun",
                role: .support,
                hp: 504, atk: 26, def: 29, spd: 105,
                auraHex: "#F5D96B",
                leader: LeaderSkill(stat: .resistance, amount: 0.40, scope: .allAllies),
                judgement: DamageSpec(multiplier: 3.50),
                judgementExtras: [.strip(count: 2, chance: 0.75, .singleEnemy)],
                judgementStatus: [],
                riteStatus: .immunity,
                reviveFraction: 0.70,
                strikeStatus: StatusSpec(.brand, chance: 0.30, turns: 2, target: .singleEnemy, rollsPerHit: true),
                essence: "essence_radiance_mid"
            )
        case .umbra:
            return AnubisFlavour(
                id: "anubis_umbra", name: "Anubis",
                epithet: "Guardian of the Scales",
                awakenedName: "Anubis, Lord of the Sacred Land",
                role: .support,
                hp: 480, atk: 27, def: 28, spd: 107,
                auraHex: "#7FE0C8",
                leader: LeaderSkill(stat: .critRate, amount: 0.25, scope: .pantheon(.egyptian)),
                judgement: DamageSpec(multiplier: 4.10, bonusPerMissingHealth: 1.10),
                judgementExtras: [.strip(count: 1, chance: 0.70, .singleEnemy)],
                judgementStatus: [],
                riteStatus: .immunity,
                reviveFraction: 0.50,
                strikeStatus: StatusSpec(.brand, chance: 0.30, turns: 2, target: .singleEnemy, rollsPerHit: true),
                essence: "essence_umbra_mid"
            )
        }
    }

    /// Builds one elemental variant. Everything the five share lives here;
    /// everything that differs comes out of `anubisFlavour`.
    private static func anubisVariant(_ element: Element) -> UnitBlueprint {
        let f = anubisFlavour(element)
        let riteName = f.riteStatus.displayName

        return UnitBlueprint(
            id: f.id,
            name: f.name,
            epithet: f.epithet,
            pantheon: .egyptian,
            element: element,
            archetype: .god,
            role: f.role,
            naturalStars: 4,
            baseStats: Stats(
                hp: f.hp, atk: f.atk, def: f.def, spd: f.spd,
                critRate: 0.15, critDamage: 0.50,
                accuracy: 0.0, resistance: 0.15
            ),
            growthPerLevel: .zero,   // Growth is derived from grade; see ProgressionService.
            skills: [
                // Slot 0 — basic attack, no cooldown.
                Skill(
                    id: "\(f.id)_s1",
                    name: "Jackal's Due",
                    description: "Strikes twice with the balance-arm. Each strike has a \(Int(f.strikeStatus.chance * 100))% chance to inflict \(f.strikeStatus.kind.displayName).",
                    slot: 0,
                    cooldown: 0,
                    target: .singleEnemy,
                    damage: DamageSpec(multiplier: 1.50, hits: 2),
                    statuses: [f.strikeStatus],
                    levelUpBonuses: [
                        SkillUpgrade(kind: .damageMultiplier, amount: 0.05, label: "Damage +5%"),
                        SkillUpgrade(kind: .damageMultiplier, amount: 0.05, label: "Damage +5%"),
                        SkillUpgrade(kind: .effectChance, amount: 0.05, label: "Effect Rate +5%"),
                        SkillUpgrade(kind: .damageMultiplier, amount: 0.10, label: "Damage +10%"),
                        SkillUpgrade(kind: .effectChance, amount: 0.10, label: "Effect Rate +10%")
                    ],
                    animation: .attackBasic,
                    cameraShot: .standard,
                    vfx: "scale_strike"
                ),

                // Slot 1 — the judgement. This is where the five variants stop
                // resembling each other.
                Skill(
                    id: "\(f.id)_s2",
                    name: "Weighing of the Heart",
                    description: anubisJudgementText(f),
                    slot: 1,
                    cooldown: 3,
                    target: .singleEnemy,
                    damage: f.judgement,
                    statuses: f.judgementStatus,
                    utilities: f.judgementExtras,
                    levelUpBonuses: [
                        SkillUpgrade(kind: .damageMultiplier, amount: 0.05, label: "Damage +5%"),
                        SkillUpgrade(kind: .damageMultiplier, amount: 0.10, label: "Damage +10%"),
                        SkillUpgrade(kind: .effectChance, amount: 0.10, label: "Effect Rate +10%"),
                        SkillUpgrade(kind: .cooldown, amount: 1, label: "Cooldown -1")
                    ],
                    animation: .attackHeavy,
                    cameraShot: .pushIn,
                    vfx: "heart_weigh"
                ),

                // Slot 2 — the rite. The revive quietly does nothing when nobody
                // is dead, so the skill is always worth pressing: it either
                // brings somebody back or it is a full-team heal and a buff.
                Skill(
                    id: "\(f.id)_s3",
                    name: "Opening of the Mouth",
                    description: "Performs the rite. Revives one fallen ally at \(Int(f.reviveFraction * 100))% health, heals every ally for 25% of their maximum health, and grants the team \(riteName) for 2 turns.",
                    slot: 2,
                    cooldown: 5,
                    target: .allAllies,
                    damage: nil,
                    statuses: [
                        StatusSpec(f.riteStatus, chance: 1.0, turns: 2, target: .allAllies)
                    ],
                    utilities: [
                        .revive(healthFraction: f.reviveFraction),
                        .healTargetMaxHealth(0.25, .allAllies)
                    ],
                    levelUpBonuses: [
                        SkillUpgrade(kind: .healing, amount: 0.10, label: "Healing +10%"),
                        SkillUpgrade(kind: .healing, amount: 0.10, label: "Healing +10%"),
                        SkillUpgrade(kind: .healing, amount: 0.15, label: "Healing +15%"),
                        SkillUpgrade(kind: .cooldown, amount: 1, label: "Cooldown -1")
                    ],
                    animation: .ultimate,
                    cameraShot: .cinematicOrbit,
                    vfx: "duat_rite"
                ),

                // Slot 3 — passive, locked until awakening. Fires once per battle.
                Skill(
                    id: "\(f.id)_passive",
                    name: "Scales of Ma'at",
                    description: "[Awakened] The first time Anubis falls below half health, he sheds every debuff and raises a shield worth 20% of his maximum health for 3 turns.",
                    slot: 3,
                    cooldown: 0,
                    target: .caster,
                    damage: nil,
                    statuses: [
                        StatusSpec(.shield, chance: 1.0, turns: 3, target: .caster, magnitude: 0.20)
                    ],
                    utilities: [.cleanse(count: 5, .caster)],
                    isPassive: true,
                    trigger: .onLowHealth,
                    requiresAwakening: true,
                    animation: .castRelease,
                    cameraShot: .heroLowAngle,
                    vfx: "maat_shield"
                )
            ],
            leaderSkill: f.leader,
            awakening: Awakening(
                awakenedName: f.awakenedName,
                bonusDescription: "Speed +15, Accuracy +15%, and the Scales of Ma'at passive is unlocked.",
                statBonus: Stats(spd: 15, accuracy: 0.15),
                skillOverrides: [:],
                essenceCost: [
                    f.essence: 15,
                    "essence_magic_mid": 10,
                    "essence_magic_high": 5
                ]
            ),
            // One mesh, five tints. Every variant loads the same `anubis` model.
            model: ModelSpec(
                assetName: "anubis",
                scale: 1.0,
                height: 2.05,
                weaponAttachNode: "weapon_r",
                handAttachNode: "hand_r",
                chestAttachNode: "spine_03",
                auraHex: f.auraHex,
                portraitName: "portrait_\(f.id)"
            ),
            lore: """
            He does not judge. He only measures, and the measuring is exact. \
            Every heart that comes to the hall is set against a single feather, \
            and the jackal watches the arm of the balance without hurry, because \
            it has never once been wrong and he has never once been asked to hurry.
            """
        )
    }

    private static func anubisJudgementText(_ f: AnubisFlavour) -> String {
        var parts = ["Weighs one enemy against the feather."]
        if f.judgement.bonusPerMissingHealth > 0 {
            parts.append("Deals heavily increased damage the more health the target has already lost.")
        }
        for status in f.judgementStatus {
            parts.append("Inflicts \(status.kind.displayName) with a \(Int(status.chance * 100))% chance.")
        }
        for extra in f.judgementExtras {
            switch extra {
            case .strip(let count, let chance, _):
                parts.append("Strips up to \(count) buff\(count == 1 ? "" : "s") with a \(Int(chance * 100))% chance.")
            case .lifesteal(let fraction):
                parts.append("Recovers health equal to \(Int(fraction * 100))% of the damage dealt.")
            case .attackBarChange(let delta, let chance, _):
                parts.append("Reduces the target's attack bar by \(Int(abs(delta) * 100))% with a \(Int(chance * 100))% chance.")
            default:
                break
            }
        }
        return parts.joined(separator: " ")
    }

    // MARK: - Campaign enemies
    //
    // These never appear in the gacha. They exist so the Duat has something to
    // fight, and so the arena pool has filler beside the summonable roster.

    static let shabti = enemy(
        id: "shabti",
        name: "Shabti",
        epithet: "Tomb Servant",
        element: .umbra,
        archetype: .spirit,
        role: .attacker,
        stars: 2,
        hp: 250, atk: 25, def: 15, spd: 96,
        basicName: "Clay Grasp",
        basicMultiplier: 1.60,
        specialName: "Answer the Call",
        specialMultiplier: 2.40,
        specialStatus: StatusSpec(.attackDown, chance: 0.45, turns: 2, target: .singleEnemy),
        auraHex: "#6C7A9C"
    )

    static let serpopard = enemy(
        id: "serpopard",
        name: "Serpopard",
        epithet: "Long-Necked Hunter",
        element: .gale,
        archetype: .monster,
        role: .attacker,
        stars: 3,
        hp: 300, atk: 31, def: 17, spd: 118,
        basicName: "Rake",
        basicMultiplier: 0.95,
        basicHits: 2,
        specialName: "Coiling Pounce",
        specialMultiplier: 3.10,
        specialStatus: StatusSpec(.speedDown, chance: 0.55, turns: 2, target: .singleEnemy),
        auraHex: "#7FD8A8"
    )

    /// The one enemy Anubis has an elemental advantage against. It exists to
    /// teach the wheel on a stage where losing is cheap.
    static let sunScarab = enemy(
        id: "sun_scarab",
        name: "Sun-Scarab Swarm",
        epithet: "Carriers of the Disc",
        element: .radiance,
        archetype: .monster,
        role: .attacker,
        stars: 3,
        hp: 285, atk: 30, def: 16, spd: 112,
        basicName: "Swarm",
        basicMultiplier: 0.85,
        basicHits: 3,
        specialName: "Solar Flare",
        specialMultiplier: 2.60,
        specialTarget: .allEnemies,
        specialStatus: StatusSpec(.glancing, chance: 0.50, turns: 2, target: .allEnemies),
        auraHex: "#F2D06B"
    )

    static let sandstoneSentinel = enemy(
        id: "sandstone_sentinel",
        name: "Sandstone Sentinel",
        epithet: "Warden of the Hall",
        element: .ember,
        archetype: .monster,
        role: .defender,
        stars: 3,
        hp: 500, atk: 22, def: 36, spd: 82,
        basicName: "Slab Fall",
        basicMultiplier: 1.50,
        specialName: "Quarry Quake",
        specialMultiplier: 2.20,
        specialTarget: .allEnemies,
        specialStatus: StatusSpec(.defenseDown, chance: 0.55, turns: 2, target: .allEnemies),
        auraHex: "#E0A05F"
    )

    static let ammit = enemy(
        id: "ammit",
        name: "Ammit",
        epithet: "Devourer of the Unworthy",
        element: .umbra,
        archetype: .monster,
        role: .attacker,
        stars: 4,
        hp: 530, atk: 37, def: 27, spd: 110,
        basicName: "Three Jaws",
        basicMultiplier: 0.90,
        basicHits: 3,
        specialName: "Devour the Heart",
        specialMultiplier: 3.40,
        specialStatus: StatusSpec(.unrecoverable, chance: 0.65, turns: 2, target: .singleEnemy),
        auraHex: "#A0553F"
    )

    /// Chapter boss. Deliberately fat and slow: a fresh Anubis can win with
    /// correct play and relics, but never by mashing the basic attack.
    static let apep = enemy(
        id: "apep",
        name: "Apep",
        epithet: "The Serpent That Swallows the Sun",
        element: .ember,
        archetype: .primordial,
        role: .hpTank,
        stars: 5,
        hp: 980, atk: 39, def: 31, spd: 94,
        basicName: "Crushing Coil",
        basicMultiplier: 1.90,
        specialName: "Unmaking",
        specialMultiplier: 3.60,
        specialTarget: .allEnemies,
        specialStatus: StatusSpec(.defenseDown, chance: 0.70, turns: 2, target: .allEnemies),
        specialCooldown: 4,
        auraHex: "#E04F2F"
    )

    // MARK: - Enemy factory

    /// Enemies share one two-skill shape, so they are built from parameters
    /// rather than written out. Anything that needs a real kit gets promoted to
    /// a hand-authored blueprint like `anubis`.
    private static func enemy(
        id: String,
        name: String,
        epithet: String,
        element: Element,
        archetype: Archetype,
        role: CombatRole,
        stars: Int,
        hp: Double, atk: Double, def: Double, spd: Double,
        basicName: String,
        basicMultiplier: Double,
        basicHits: Int = 1,
        specialName: String,
        specialMultiplier: Double,
        specialTarget: TargetSelector = .singleEnemy,
        specialStatus: StatusSpec? = nil,
        specialUtilities: [UtilityEffect] = [],
        specialCooldown: Int = 3,
        pantheon: Pantheon = .egyptian,
        auraHex: String
    ) -> UnitBlueprint {
        UnitBlueprint(
            id: id,
            name: name,
            epithet: epithet,
            pantheon: pantheon,
            element: element,
            archetype: archetype,
            role: role,
            naturalStars: stars,
            baseStats: Stats(
                hp: hp, atk: atk, def: def, spd: spd,
                critRate: 0.15, critDamage: 0.50, accuracy: 0.0, resistance: 0.15
            ),
            growthPerLevel: .zero,
            skills: [
                Skill(
                    id: "\(id)_s1",
                    name: basicName,
                    description: basicHits > 1
                        ? "Attacks the enemy \(basicHits) times."
                        : "Attacks the enemy.",
                    slot: 0,
                    cooldown: 0,
                    target: .singleEnemy,
                    damage: DamageSpec(multiplier: basicMultiplier, hits: basicHits),
                    animation: .attackBasic,
                    cameraShot: .standard,
                    vfx: "impact_generic"
                ),
                Skill(
                    id: "\(id)_s2",
                    name: specialName,
                    description: specialStatus.map {
                        "Deals damage and applies \($0.kind.displayName)."
                    } ?? "Deals heavy damage.",
                    slot: 1,
                    cooldown: specialCooldown,
                    target: specialTarget,
                    damage: specialMultiplier > 0
                        ? DamageSpec(multiplier: specialMultiplier)
                        : nil,
                    statuses: specialStatus.map { [$0] } ?? [],
                    utilities: specialUtilities,
                    animation: .attackHeavy,
                    cameraShot: .pushIn,
                    vfx: "impact_generic"
                )
            ],
            leaderSkill: nil,
            awakening: nil,
            model: ModelSpec(
                assetName: id,
                height: archetype == .primordial ? 3.6 : 1.9,
                auraHex: auraHex,
                portraitName: "portrait_\(id)"
            ),
            lore: epithet
        )
    }
}
