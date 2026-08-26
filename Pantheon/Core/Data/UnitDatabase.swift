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
enum UnitDatabase {

    // MARK: - Registry

    static let all: [UnitBlueprint] = [
        zeus,
        shadeOfTartarus,
        harpy,
        naiad,
        bronzeAutomaton,
        cerberus,
        menoetius
    ]

    private static let index: [String: UnitBlueprint] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    static func blueprint(_ id: String) -> UnitBlueprint? { index[id] }

    /// Unit ids the gacha is allowed to produce. Enemies are deliberately absent.
    static let summonPool: [String] = ["zeus"]

    static func summonable(stars: Int) -> [UnitBlueprint] {
        summonPool.compactMap { blueprint($0) }.filter { $0.naturalStars == stars }
    }

    // MARK: - ZEUS

    /// The first fully authored character. Everything about the pipeline —
    /// stats, three actives, an awakened passive, a leader skill, a model spec —
    /// is exercised here, so the next god is a copy-edit rather than a design.
    static let zeus = UnitBlueprint(
        id: "zeus",
        name: "Zeus",
        epithet: "King of Olympus",
        pantheon: .greek,
        element: .radiance,
        archetype: .god,
        role: .attacker,
        naturalStars: 5,

        // 1★ Lv1 values. At 6★ Lv65 this lands near 10.9k HP / 890 ATK / 580 DEF.
        baseStats: Stats(
            hp: 415, atk: 34, def: 22, spd: 104,
            critRate: 0.15, critDamage: 0.50,
            accuracy: 0.0, resistance: 0.15
        ),
        growthPerLevel: .zero, // Growth is derived from grade; see ProgressionService.

        skills: [
            // Slot 0 — basic attack, no cooldown.
            Skill(
                id: "zeus_s1",
                name: "Arc Lightning",
                description: "Strikes the enemy 3 times with forked lightning. Each strike has a 20% chance to Slow the target for 2 turns.",
                slot: 0,
                cooldown: 0,
                target: .singleEnemy,
                damage: DamageSpec(multiplier: 1.05, hits: 3),
                statuses: [
                    StatusSpec(.speedDown, chance: 0.20, turns: 2, target: .singleEnemy, rollsPerHit: true)
                ],
                levelUpBonuses: [
                    SkillUpgrade(kind: .damageMultiplier, amount: 0.05, label: "Damage +5%"),
                    SkillUpgrade(kind: .damageMultiplier, amount: 0.05, label: "Damage +5%"),
                    SkillUpgrade(kind: .effectChance, amount: 0.05, label: "Effect Rate +5%"),
                    SkillUpgrade(kind: .damageMultiplier, amount: 0.10, label: "Damage +10%"),
                    SkillUpgrade(kind: .effectChance, amount: 0.10, label: "Effect Rate +10%")
                ],
                animation: .attackBasic,
                cameraShot: .standard,
                vfx: "arc_lightning"
            ),

            // Slot 1 — the single-target punish.
            Skill(
                id: "zeus_s2",
                name: "Thunderbolt",
                description: "Hurls a bolt that ignores 30% of the target's Defense and Stuns for 1 turn with a 70% chance.",
                slot: 1,
                cooldown: 3,
                target: .singleEnemy,
                damage: DamageSpec(multiplier: 4.20, defenseIgnore: 0.30),
                statuses: [
                    StatusSpec(.stun, chance: 0.70, turns: 1, target: .singleEnemy)
                ],
                levelUpBonuses: [
                    SkillUpgrade(kind: .damageMultiplier, amount: 0.05, label: "Damage +5%"),
                    SkillUpgrade(kind: .damageMultiplier, amount: 0.10, label: "Damage +10%"),
                    SkillUpgrade(kind: .effectChance, amount: 0.10, label: "Effect Rate +10%"),
                    SkillUpgrade(kind: .cooldown, amount: 1, label: "Cooldown -1")
                ],
                animation: .attackHeavy,
                cameraShot: .pushIn,
                vfx: "thunderbolt"
            ),

            // Slot 2 — the ultimate.
            Skill(
                id: "zeus_s3",
                name: "Aegis of Olympus",
                description: "Calls the storm down on every enemy, dealing more damage the more debuffs they carry, with a 50% chance to Stun. Grants Attack Up to all allies for 2 turns.",
                slot: 2,
                cooldown: 5,
                target: .allEnemies,
                damage: DamageSpec(multiplier: 3.40, bonusPerTargetDebuff: 0.15),
                statuses: [
                    StatusSpec(.stun, chance: 0.50, turns: 1, target: .allEnemies),
                    StatusSpec(.attackUp, chance: 1.0, turns: 2, target: .allAllies)
                ],
                levelUpBonuses: [
                    SkillUpgrade(kind: .damageMultiplier, amount: 0.05, label: "Damage +5%"),
                    SkillUpgrade(kind: .damageMultiplier, amount: 0.05, label: "Damage +5%"),
                    SkillUpgrade(kind: .effectChance, amount: 0.10, label: "Effect Rate +10%"),
                    SkillUpgrade(kind: .damageMultiplier, amount: 0.10, label: "Damage +10%"),
                    SkillUpgrade(kind: .cooldown, amount: 1, label: "Cooldown -1")
                ],
                animation: .ultimate,
                cameraShot: .cinematicOrbit,
                vfx: "olympus_storm"
            ),

            // Slot 3 — passive, locked until awakening.
            Skill(
                id: "zeus_passive",
                name: "Stormlord",
                description: "[Awakened] When Zeus defeats an enemy, his skill cooldowns reset and he gains Attack Up for 2 turns.",
                slot: 3,
                cooldown: 0,
                target: .caster,
                damage: nil,
                statuses: [
                    StatusSpec(.attackUp, chance: 1.0, turns: 2, target: .caster)
                ],
                utilities: [.resetOwnCooldowns],
                isPassive: true,
                trigger: .onKill,
                requiresAwakening: true,
                animation: .castRelease,
                cameraShot: .heroLowAngle,
                vfx: "stormlord_surge"
            )
        ],

        leaderSkill: LeaderSkill(
            stat: .atkPercent,
            amount: 0.33,
            scope: .pantheon(.greek),
            appliesInArena: true,
            appliesInCampaign: true
        ),

        awakening: Awakening(
            awakenedName: "Zeus, Aegis-Bearer",
            bonusDescription: "Speed +15, CRIT Rate +15%, and the Stormlord passive is unlocked.",
            statBonus: Stats(spd: 15, critRate: 0.15),
            skillOverrides: [:],
            essenceCost: [
                "essence_radiance_high": 10,
                "essence_radiance_mid": 15,
                "essence_magic_high": 5
            ]
        ),

        model: ModelSpec(
            assetName: "zeus",
            scale: 1.0,
            height: 2.05,
            weaponAttachNode: "weapon_r",
            handAttachNode: "hand_r",
            chestAttachNode: "spine_03",
            auraHex: "#FFE9A8",
            portraitName: "portrait_zeus"
        ),

        lore: """
        He divided the world with his brothers and kept the sky. Every oath sworn \
        on earth is sworn to him, and every one of them he remembers. The storm is \
        not his weapon. It is his temper, and it arrives first.
        """
    )

    // MARK: - Campaign enemies
    //
    // These never appear in the gacha. They exist so Olympus has something to
    // fight and so the arena pool has filler beside the summonable roster.

    static let shadeOfTartarus = enemy(
        id: "shade_tartarus",
        name: "Shade of Tartarus",
        epithet: "Escaped Remnant",
        element: .umbra,
        archetype: .spirit,
        role: .attacker,
        stars: 2,
        hp: 260, atk: 26, def: 14, spd: 98,
        basicName: "Grasp",
        basicMultiplier: 1.6,
        specialName: "Wailing Dark",
        specialMultiplier: 2.6,
        specialStatus: StatusSpec(.attackDown, chance: 0.45, turns: 2, target: .singleEnemy),
        auraHex: "#6C4FA0"
    )

    static let harpy = enemy(
        id: "harpy",
        name: "Harpy",
        epithet: "Storm-Snatcher",
        element: .gale,
        archetype: .monster,
        role: .attacker,
        stars: 3,
        hp: 300, atk: 31, def: 16, spd: 116,
        basicName: "Talon Rake",
        basicMultiplier: 0.95,
        basicHits: 2,
        specialName: "Shrieking Dive",
        specialMultiplier: 3.1,
        specialStatus: StatusSpec(.speedDown, chance: 0.55, turns: 2, target: .singleEnemy),
        auraHex: "#7FD8A8"
    )

    static let naiad = enemy(
        id: "naiad",
        name: "Naiad",
        epithet: "Spring-Warden",
        element: .tide,
        archetype: .spirit,
        role: .support,
        stars: 3,
        hp: 340, atk: 24, def: 21, spd: 102,
        basicName: "Tide Lash",
        basicMultiplier: 1.7,
        specialName: "Wellspring",
        specialMultiplier: 0,
        specialTarget: .allAllies,
        specialStatus: StatusSpec(.recovery, chance: 1.0, turns: 2, target: .allAllies),
        specialUtilities: [.healTargetMaxHealth(0.20, .allAllies)],
        auraHex: "#6BC0F2"
    )

    static let bronzeAutomaton = enemy(
        id: "bronze_automaton",
        name: "Bronze Automaton",
        epithet: "Forge-Sentinel",
        element: .ember,
        archetype: .monster,
        role: .defender,
        stars: 3,
        hp: 480, atk: 22, def: 34, spd: 84,
        basicName: "Hammer Fall",
        basicMultiplier: 1.5,
        specialName: "Molten Vent",
        specialMultiplier: 2.2,
        specialTarget: .allEnemies,
        specialStatus: StatusSpec(.burn, chance: 0.50, turns: 2, target: .allEnemies),
        auraHex: "#F28C4F"
    )

    static let cerberus = enemy(
        id: "cerberus",
        name: "Cerberus",
        epithet: "Hound of the Threshold",
        element: .umbra,
        archetype: .monster,
        role: .attacker,
        stars: 4,
        hp: 520, atk: 36, def: 26, spd: 108,
        basicName: "Three Jaws",
        basicMultiplier: 0.85,
        basicHits: 3,
        specialName: "Gate of Hades",
        specialMultiplier: 3.3,
        specialTarget: .allEnemies,
        specialStatus: StatusSpec(.unrecoverable, chance: 0.65, turns: 2, target: .allEnemies),
        auraHex: "#8B3FA0"
    )

    /// Chapter boss. Deliberately fat and slow so a fresh Zeus can win with
    /// correct play but not by mashing the basic attack.
    static let menoetius = enemy(
        id: "menoetius",
        name: "Menoetius",
        epithet: "Titan of Violent Rage",
        element: .ember,
        archetype: .titan,
        role: .hpTank,
        stars: 5,
        hp: 980, atk: 38, def: 30, spd: 92,
        basicName: "Ruinous Sweep",
        basicMultiplier: 1.9,
        specialName: "Titanfall",
        specialMultiplier: 3.8,
        specialTarget: .allEnemies,
        specialStatus: StatusSpec(.defenseDown, chance: 0.70, turns: 2, target: .allEnemies),
        specialCooldown: 4,
        auraHex: "#E04F2F"
    )

    // MARK: - Enemy factory

    /// Enemies share one two-skill shape, so they are built from parameters
    /// rather than written out. Anything that needs a real kit gets promoted to
    /// a hand-authored blueprint like `zeus`.
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
        pantheon: Pantheon = .greek,
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
                height: archetype == .titan ? 3.4 : 1.9,
                auraHex: auraHex,
                portraitName: "portrait_\(id)"
            ),
            lore: epithet
        )
    }
}
