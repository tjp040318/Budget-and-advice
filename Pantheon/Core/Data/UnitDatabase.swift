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

    static let all: [UnitBlueprint] = anubisFamily + sekhmetFamily + zeusFamily + shabtiFamily + secondRoster + [
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

    /// Unit ids the gacha is allowed to produce. Enemies are deliberately
    /// absent, and so is any family whose portraits have not shipped yet —
    /// Sekhmet and Zeus joined the pool the moment their five files were in the
    /// bundle, with no code change. The Shabti family is the 3★ tier: what a
    /// common roll gives, and what the Hall of Ka feeds to the gods.
    static let summonPool: [String] = (anubisFamily + sekhmetFamily + zeusFamily + shabtiFamily + secondRoster)
        .filter { $0.hasShippedArt }
        .map { $0.id }

    static func summonable(stars: Int) -> [UnitBlueprint] {
        summonPool.compactMap { blueprint($0) }.filter { $0.naturalStars == stars }
    }

    // MARK: - THE SHABTI FAMILY
    //
    // The gacha's common tier and the Hall of Ka's fodder: tomb servants,
    // figurines made to answer for their master, in five elements. Summoners
    // War's low-star monsters do this job — most pulls are food, and food is
    // what raises the gods — so each is a real two-skill unit that is usable
    // on day one and worth feeding on day two. Natural 3★, a grade below the
    // roster's weakest god, so evolving them is the road to 4★ and 5★ fodder.

    static var shabtiFamily: [UnitBlueprint] { Element.allCases.map(shabtiVariant) }

    private static func shabtiVariant(_ element: Element) -> UnitBlueprint {
        let epithet: String
        let stats: (hp: Double, atk: Double, def: Double, spd: Double)
        let status: StatusSpec
        switch element {
        case .ember:
            epithet = "Kiln Servant"
            stats = (290, 26, 19, 97)
            status = StatusSpec(.burn, chance: 0.40, turns: 2, target: .singleEnemy)
        case .tide:
            epithet = "Nile Servant"
            stats = (320, 23, 21, 96)
            status = StatusSpec(.speedDown, chance: 0.45, turns: 2, target: .singleEnemy)
        case .gale:
            epithet = "Dune Servant"
            stats = (285, 24, 18, 106)
            status = StatusSpec(.glancing, chance: 0.45, turns: 2, target: .singleEnemy)
        case .radiance:
            epithet = "Sun Servant"
            stats = (305, 24, 22, 98)
            status = StatusSpec(.attackDown, chance: 0.45, turns: 2, target: .singleEnemy)
        case .umbra:
            epithet = "Tomb Servant"
            stats = (300, 25, 20, 98)
            status = StatusSpec(.defenseDown, chance: 0.40, turns: 2, target: .singleEnemy)
        }
        return enemy(
            id: "shabti_\(element.rawValue)",
            name: "Shabti",
            epithet: epithet,
            element: element,
            archetype: .spirit,
            role: .attacker,
            stars: 3,
            hp: stats.hp, atk: stats.atk, def: stats.def, spd: stats.spd,
            basicName: "Clay Grasp",
            basicMultiplier: 1.60,
            specialName: "Answer the Call",
            specialMultiplier: 2.30,
            specialStatus: status,
            auraHex: element.accentHex
        )
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
                // Orientation is detected from the mesh (ModelOrientation);
                // this is only an override on top of that. Leave at 0 unless
                // the console log says the auto-detect picked the wrong sign.
                pitchCorrection: 0,
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

    // MARK: - THE SEKHMET FAMILY
    //
    // The second family, and the roster's first real damage archetype. Where
    // Anubis heals, strips and revives, Sekhmet breaks defence and kills. Every
    // variant's Eye of Ra carries Defense Break — that is the family's identity
    // the way the revive is Anubis's — and the five differ by what the claws
    // leave behind, what the Eye does besides breaking, what the Wrath grants
    // the team, and the leader skill.
    //
    // Natural 5★, which also gives the gacha's 5★ tier its first occupants: until
    // now a 5★ result fell back down the grades and produced an Anubis.
    //
    // One mesh, five tints, exactly as Anubis: every variant loads `sekhmet`. The
    // model is generated by tools/meshy.py — see Docs/ART_PIPELINE.md.

    static let sekhmetEmber    = sekhmetVariant(.ember)
    static let sekhmetTide     = sekhmetVariant(.tide)
    static let sekhmetGale     = sekhmetVariant(.gale)
    static let sekhmetRadiance = sekhmetVariant(.radiance)
    static let sekhmetUmbra    = sekhmetVariant(.umbra)

    /// Everything in the Sekhmet family, in wheel order.
    static var sekhmetFamily: [UnitBlueprint] {
        [sekhmetEmber, sekhmetTide, sekhmetGale, sekhmetRadiance, sekhmetUmbra]
    }

    /// Per-element identity for Sekhmet: the stat lean, what the claws inflict,
    /// what the Eye does on top of breaking defence, and what the Wrath gives.
    private struct SekhmetFlavour {
        var id: String
        var epithet: String
        var awakenedName: String
        var role: CombatRole
        var hp: Double
        var atk: Double
        var def: Double
        var spd: Double
        var auraHex: String
        var leader: LeaderSkill
        var rakeStatus: StatusSpec
        var eye: DamageSpec
        var eyeExtras: [UtilityEffect]
        var wrathStatus: StatusSpec
        var essence: String
    }

    private static func sekhmetFlavour(_ element: Element) -> SekhmetFlavour {
        switch element {
        case .ember:
            // The archetype itself: the most attack, the least health, and the
            // biggest Eye. Burn on the claws is the damage-over-time the family
            // was designed around.
            return SekhmetFlavour(
                id: "sekhmet_ember",
                epithet: "of the Scorching Noon",
                awakenedName: "Sekhmet, Eye of Ra",
                role: .attacker,
                hp: 410, atk: 38, def: 23, spd: 106,
                auraHex: "#F25A3C",
                leader: LeaderSkill(stat: .atkPercent, amount: 0.38, scope: .element(.ember)),
                rakeStatus: StatusSpec(.burn, chance: 0.30, turns: 2, target: .singleEnemy, rollsPerHit: true),
                eye: DamageSpec(multiplier: 4.80),
                eyeExtras: [],
                wrathStatus: StatusSpec(.attackUp, chance: 1.0, turns: 2, target: .allAllies),
                essence: "essence_ember_mid"
            )
        case .tide:
            return SekhmetFlavour(
                id: "sekhmet_tide",
                epithet: "of the Red Nile",
                awakenedName: "Sekhmet, Who Drank the River Red",
                role: .attacker,
                hp: 480, atk: 32, def: 28, spd: 102,
                auraHex: "#3CA8F2",
                leader: LeaderSkill(stat: .defPercent, amount: 0.38, scope: .pantheon(.egyptian)),
                rakeStatus: StatusSpec(.attackDown, chance: 0.25, turns: 2, target: .singleEnemy, rollsPerHit: true),
                eye: DamageSpec(multiplier: 4.40),
                eyeExtras: [.lifesteal(0.30)],
                wrathStatus: StatusSpec(.defenseUp, chance: 1.0, turns: 2, target: .allAllies),
                essence: "essence_tide_mid"
            )
        case .gale:
            return SekhmetFlavour(
                id: "sekhmet_gale",
                epithet: "of the Khamsin's Roar",
                awakenedName: "Sekhmet, Breath of the Burning Wind",
                role: .attacker,
                hp: 416, atk: 34, def: 24, spd: 114,
                auraHex: "#5FD98A",
                leader: LeaderSkill(stat: .accuracy, amount: 0.40, scope: .allAllies),
                rakeStatus: StatusSpec(.speedDown, chance: 0.25, turns: 2, target: .singleEnemy, rollsPerHit: true),
                eye: DamageSpec(multiplier: 4.40),
                eyeExtras: [.attackBarChange(-0.30, chance: 0.75, .singleEnemy)],
                wrathStatus: StatusSpec(.speedUp, chance: 1.0, turns: 2, target: .allAllies),
                essence: "essence_gale_mid"
            )
        case .radiance:
            // The Eye of Ra is literally her: the Radiance Eye never misses its
            // mark, so it always crits and trades multiplier for it.
            return SekhmetFlavour(
                id: "sekhmet_radiance",
                epithet: "Lady of the Sun Disc",
                awakenedName: "Sekhmet, Flame of the Disc",
                role: .attacker,
                hp: 440, atk: 35, def: 26, spd: 107,
                auraHex: "#FFD94F",
                leader: LeaderSkill(stat: .critDamage, amount: 0.35, scope: .pantheon(.egyptian)),
                rakeStatus: StatusSpec(.glancing, chance: 0.30, turns: 2, target: .singleEnemy, rollsPerHit: true),
                eye: DamageSpec(multiplier: 3.80, alwaysCrits: true),
                eyeExtras: [],
                wrathStatus: StatusSpec(.critRateUp, chance: 1.0, turns: 2, target: .allAllies),
                essence: "essence_radiance_mid"
            )
        case .umbra:
            // The plague-bringer. Her Wrath is a curse on the enemy rather than
            // a gift to the team, and her Eye grows with every affliction.
            return SekhmetFlavour(
                id: "sekhmet_umbra",
                epithet: "Mistress of Plague",
                awakenedName: "Sekhmet, Bringer of the Seven Arrows",
                role: .attacker,
                hp: 450, atk: 34, def: 26, spd: 105,
                auraHex: "#9B5FD9",
                leader: LeaderSkill(stat: .hpPercent, amount: 0.33, scope: .allAllies),
                rakeStatus: StatusSpec(.unrecoverable, chance: 0.30, turns: 2, target: .singleEnemy, rollsPerHit: true),
                eye: DamageSpec(multiplier: 4.40, bonusPerTargetDebuff: 0.20),
                eyeExtras: [],
                wrathStatus: StatusSpec(.attackDown, chance: 0.60, turns: 2, target: .allEnemies),
                essence: "essence_umbra_mid"
            )
        }
    }

    /// Builds one elemental variant. Everything the five share lives here;
    /// everything that differs comes out of `sekhmetFlavour`.
    private static func sekhmetVariant(_ element: Element) -> UnitBlueprint {
        let f = sekhmetFlavour(element)

        return UnitBlueprint(
            id: f.id,
            name: "Sekhmet",
            epithet: f.epithet,
            pantheon: .egyptian,
            element: element,
            archetype: .god,
            role: f.role,
            naturalStars: 5,
            baseStats: Stats(
                hp: f.hp, atk: f.atk, def: f.def, spd: f.spd,
                critRate: 0.15, critDamage: 0.50,
                accuracy: 0.0, resistance: 0.15
            ),
            growthPerLevel: .zero,   // Growth is derived from grade; see ProgressionService.
            skills: [
                // Slot 0 — basic attack, no cooldown. Two rakes, each rolling
                // the variant's affliction.
                Skill(
                    id: "\(f.id)_s1",
                    name: "Rake of the Lioness",
                    description: "Rakes the enemy twice. Each strike has a \(Int(f.rakeStatus.chance * 100))% chance to inflict \(f.rakeStatus.kind.displayName).",
                    slot: 0,
                    cooldown: 0,
                    target: .singleEnemy,
                    damage: DamageSpec(multiplier: 1.50, hits: 2),
                    statuses: [f.rakeStatus],
                    levelUpBonuses: [
                        SkillUpgrade(kind: .damageMultiplier, amount: 0.05, label: "Damage +5%"),
                        SkillUpgrade(kind: .damageMultiplier, amount: 0.05, label: "Damage +5%"),
                        SkillUpgrade(kind: .effectChance, amount: 0.05, label: "Effect Rate +5%"),
                        SkillUpgrade(kind: .damageMultiplier, amount: 0.10, label: "Damage +10%"),
                        SkillUpgrade(kind: .effectChance, amount: 0.10, label: "Effect Rate +10%")
                    ],
                    animation: .attackBasic,
                    cameraShot: .standard,
                    vfx: "lioness_rake"
                ),

                // Slot 1 — the Eye. The Defense Break is on every variant; what
                // rides along with it is not.
                Skill(
                    id: "\(f.id)_s2",
                    name: "Eye of Ra",
                    description: sekhmetEyeText(f),
                    slot: 1,
                    cooldown: 3,
                    target: .singleEnemy,
                    damage: f.eye,
                    statuses: [
                        StatusSpec(.defenseDown, chance: 0.85, turns: 2, target: .singleEnemy)
                    ],
                    utilities: f.eyeExtras,
                    levelUpBonuses: [
                        SkillUpgrade(kind: .damageMultiplier, amount: 0.05, label: "Damage +5%"),
                        SkillUpgrade(kind: .damageMultiplier, amount: 0.10, label: "Damage +10%"),
                        SkillUpgrade(kind: .effectChance, amount: 0.10, label: "Effect Rate +10%"),
                        SkillUpgrade(kind: .cooldown, amount: 1, label: "Cooldown -1")
                    ],
                    animation: .attackHeavy,
                    cameraShot: .pushIn,
                    vfx: "eye_of_ra"
                ),

                // Slot 2 — the Wrath. Damage to the whole enemy line, then the
                // variant's gift to the team — or, for Umbra, its curse on the
                // enemy.
                Skill(
                    id: "\(f.id)_s3",
                    name: "Wrath of the Eye",
                    description: sekhmetWrathText(f),
                    slot: 2,
                    cooldown: 5,
                    target: .allEnemies,
                    damage: DamageSpec(multiplier: 2.60),
                    statuses: [f.wrathStatus],
                    levelUpBonuses: [
                        SkillUpgrade(kind: .damageMultiplier, amount: 0.05, label: "Damage +5%"),
                        SkillUpgrade(kind: .damageMultiplier, amount: 0.10, label: "Damage +10%"),
                        SkillUpgrade(kind: .effectChance, amount: 0.10, label: "Effect Rate +10%"),
                        SkillUpgrade(kind: .cooldown, amount: 1, label: "Cooldown -1")
                    ],
                    animation: .ultimate,
                    cameraShot: .cinematicOrbit,
                    vfx: "wrath_of_the_eye"
                ),

                // Slot 3 — passive, locked until awakening. A kill feeds her.
                Skill(
                    id: "\(f.id)_passive",
                    name: "Thirst of the Lioness",
                    description: "[Awakened] Whenever Sekhmet kills an enemy she takes another turn and recovers 15% of her maximum health.",
                    slot: 3,
                    cooldown: 0,
                    target: .caster,
                    damage: nil,
                    utilities: [
                        .extraTurn(chance: 1.0),
                        .healTargetMaxHealth(0.15, .caster)
                    ],
                    isPassive: true,
                    trigger: .onKill,
                    requiresAwakening: true,
                    animation: .castRelease,
                    cameraShot: .heroLowAngle,
                    vfx: "blood_thirst"
                )
            ],
            leaderSkill: f.leader,
            awakening: Awakening(
                awakenedName: f.awakenedName,
                bonusDescription: "CRIT Rate +15%, Accuracy +15%, and the Thirst of the Lioness passive is unlocked.",
                statBonus: Stats(critRate: 0.15, accuracy: 0.15),
                skillOverrides: [:],
                essenceCost: [
                    f.essence: 15,
                    "essence_magic_mid": 10,
                    "essence_magic_high": 5
                ]
            ),
            // One mesh, five tints. Every variant loads the same `sekhmet` model.
            model: ModelSpec(
                assetName: "sekhmet",
                scale: 1.0,
                height: 2.0,
                pitchCorrection: 0,
                weaponAttachNode: "weapon_r",
                handAttachNode: "hand_r",
                chestAttachNode: "spine_03",
                auraHex: f.auraHex,
                portraitName: "portrait_\(f.id)"
            ),
            lore: """
            Ra grew old, and mankind mocked him, so he sent his Eye against them \
            in the shape of a lioness. She killed until the fields were red and \
            found that she liked it, and only seven thousand jars of beer dyed the \
            colour of blood, poured out across the plain, were enough to stop her. \
            She drank the flood and slept. The gods have been careful with her since.
            """
        )
    }

    private static func sekhmetEyeText(_ f: SekhmetFlavour) -> String {
        var parts = ["Fixes one enemy with the Eye of Ra and breaks its defence for 2 turns with an 85% chance."]
        if f.eye.alwaysCrits {
            parts.append("The Eye always lands a critical hit.")
        }
        if f.eye.bonusPerTargetDebuff > 0 {
            parts.append("Deals more damage for every harmful effect on the target.")
        }
        for extra in f.eyeExtras {
            switch extra {
            case .lifesteal(let fraction):
                parts.append("Recovers health equal to \(Int(fraction * 100))% of the damage dealt.")
            case .attackBarChange(let delta, let chance, _):
                parts.append("Reduces the target's attack bar by \(Int(abs(delta) * 100))% with a \(Int(chance * 100))% chance.")
            case .strip(let count, let chance, _):
                parts.append("Strips up to \(count) buff\(count == 1 ? "" : "s") with a \(Int(chance * 100))% chance.")
            default:
                break
            }
        }
        return parts.joined(separator: " ")
    }

    private static func sekhmetWrathText(_ f: SekhmetFlavour) -> String {
        let status = f.wrathStatus
        let effect: String
        switch status.target {
        case .allAllies:
            effect = "Grants the team \(status.kind.displayName) for \(status.turns) turns."
        default:
            effect = "Inflicts \(status.kind.displayName) on every enemy for \(status.turns) turns with a \(Int(status.chance * 100))% chance."
        }
        return "Unleashes the Eye on every enemy. \(effect)"
    }


    // MARK: - THE ZEUS FAMILY
    //
    // The third family, and the first from a second pantheon. Zeus is the
    // roster's control archetype: Anubis sustains, Sekhmet kills, Zeus decides
    // who gets to act. Every variant's Thunderclap hits the whole enemy line
    // and takes turns away from it — a stun, a freeze, a sleep, a knockback
    // down the attack bar, or a provoke that drags every enemy onto him — and
    // every Keraunos is one bolt that ignores 40% of defence and then hands the
    // team something. The awakened passive pushes the whole team's attack bar
    // at the start of battle, so a Zeus team moves first.
    //
    // Natural 5★ and Greek. Leader skills that buff a stat are scoped to Greek
    // allies, which is how the genre seeds a second pantheon before it has a
    // roster: today that means the Zeus variants, tomorrow it means Olympus.
    //
    // One mesh, five tints, exactly as the Egyptians: every variant loads
    // `zeus`. The model was generated by tools/meshy.py; the task ids are in
    // Art/Models/zeus.meshy.json.

    static let zeusEmber    = zeusVariant(.ember)
    static let zeusTide     = zeusVariant(.tide)
    static let zeusGale     = zeusVariant(.gale)
    static let zeusRadiance = zeusVariant(.radiance)
    static let zeusUmbra    = zeusVariant(.umbra)

    /// Everything in the Zeus family, in wheel order.
    static var zeusFamily: [UnitBlueprint] {
        [zeusEmber, zeusTide, zeusGale, zeusRadiance, zeusUmbra]
    }

    /// Per-element identity for Zeus: the stat lean, what the bolt leaves on
    /// its target, how the Thunderclap takes the enemy's turn away, and what
    /// the Keraunos gives the team once it has landed.
    private struct ZeusFlavour {
        var id: String
        var epithet: String
        var awakenedName: String
        var role: CombatRole
        var hp: Double
        var atk: Double
        var def: Double
        var spd: Double
        var auraHex: String
        var leader: LeaderSkill
        var boltStatus: StatusSpec
        var clapStatus: StatusSpec
        var clapExtras: [UtilityEffect]
        var keraunosStatus: StatusSpec?
        var keraunosExtras: [UtilityEffect]
        var essence: String
    }

    private static func zeusFlavour(_ element: Element) -> ZeusFlavour {
        switch element {
        case .ember:
            // The archetype itself: the stun, the biggest bolt, Attack Up for
            // the team once the Keraunos has landed.
            return ZeusFlavour(
                id: "zeus_ember",
                epithet: "of the Scorching Sky",
                awakenedName: "Zeus Keraunios",
                role: .controller,
                hp: 445, atk: 36, def: 25, spd: 105,
                auraHex: "#FF9A3C",
                leader: LeaderSkill(stat: .atkPercent, amount: 0.33, scope: .pantheon(.greek)),
                boltStatus: StatusSpec(.burn, chance: 0.35, turns: 2, target: .singleEnemy),
                clapStatus: StatusSpec(.stun, chance: 0.55, turns: 1, target: .allEnemies),
                clapExtras: [],
                keraunosStatus: StatusSpec(.attackUp, chance: 1.0, turns: 2, target: .allAllies),
                keraunosExtras: [],
                essence: "essence_ember_mid"
            )
        case .tide:
            // The rain-bringer. The sturdiest Zeus, a freeze instead of a
            // stun, and a shield on the whole team behind the Keraunos.
            return ZeusFlavour(
                id: "zeus_tide",
                epithet: "of the Storm-Dark Sea",
                awakenedName: "Zeus Ombrios",
                role: .defender,
                hp: 505, atk: 31, def: 29, spd: 103,
                auraHex: "#4FC3F7",
                leader: LeaderSkill(stat: .hpPercent, amount: 0.33, scope: .pantheon(.greek)),
                boltStatus: StatusSpec(.speedDown, chance: 0.35, turns: 2, target: .singleEnemy),
                clapStatus: StatusSpec(.freeze, chance: 0.55, turns: 1, target: .allEnemies),
                clapExtras: [],
                keraunosStatus: StatusSpec(.shield, chance: 1.0, turns: 2, target: .allAllies, magnitude: 0.20),
                keraunosExtras: [],
                essence: "essence_tide_mid"
            )
        case .gale:
            // The turn-thief. No hard control at all: the Thunderclap knocks
            // every enemy down the attack bar and slows them, and the Keraunos
            // carries the team forward instead of buffing a stat.
            return ZeusFlavour(
                id: "zeus_gale",
                epithet: "of the Whirlwind",
                awakenedName: "Zeus Ourios",
                role: .controller,
                hp: 450, atk: 33, def: 25, spd: 112,
                auraHex: "#8AE68A",
                leader: LeaderSkill(stat: .spd, amount: 0.24, scope: .pantheon(.greek)),
                boltStatus: StatusSpec(.glancing, chance: 0.35, turns: 2, target: .singleEnemy),
                clapStatus: StatusSpec(.speedDown, chance: 0.70, turns: 2, target: .allEnemies),
                clapExtras: [.attackBarChange(-0.30, chance: 1.0, .allEnemies)],
                keraunosStatus: nil,
                keraunosExtras: [.attackBarChange(0.25, chance: 1.0, .allAllies)],
                essence: "essence_gale_mid"
            )
        case .radiance:
            // All eyes on the king. The Thunderclap provokes the enemy line
            // onto Zeus himself, which is why this variant is the one built to
            // take the hits, and the Keraunos grants the team Immunity.
            return ZeusFlavour(
                id: "zeus_radiance",
                epithet: "Bringer of Day",
                awakenedName: "Zeus Panoptes",
                role: .defender,
                hp: 480, atk: 32, def: 28, spd: 106,
                auraHex: "#FFE680",
                leader: LeaderSkill(stat: .accuracy, amount: 0.35, scope: .pantheon(.greek)),
                boltStatus: StatusSpec(.brand, chance: 0.35, turns: 2, target: .singleEnemy),
                clapStatus: StatusSpec(.provoke, chance: 0.60, turns: 1, target: .allEnemies),
                clapExtras: [],
                keraunosStatus: StatusSpec(.immunity, chance: 1.0, turns: 2, target: .allAllies),
                keraunosExtras: [],
                essence: "essence_radiance_mid"
            )
        case .umbra:
            // The Zeus beneath the earth. Sleep instead of a stun, and the
            // Keraunos brands every enemy rather than gifting the team — the
            // one variant whose rite points outward.
            return ZeusFlavour(
                id: "zeus_umbra",
                epithet: "of the Black Cloud",
                awakenedName: "Zeus Katachthonios",
                role: .controller,
                hp: 470, atk: 34, def: 26, spd: 104,
                auraHex: "#A07CFF",
                leader: LeaderSkill(stat: .critRate, amount: 0.24, scope: .allAllies),
                boltStatus: StatusSpec(.attackDown, chance: 0.35, turns: 2, target: .singleEnemy),
                clapStatus: StatusSpec(.sleep, chance: 0.55, turns: 1, target: .allEnemies),
                clapExtras: [],
                keraunosStatus: StatusSpec(.brand, chance: 0.75, turns: 2, target: .allEnemies),
                keraunosExtras: [],
                essence: "essence_umbra_mid"
            )
        }
    }

    /// Builds one elemental variant. Everything the five share lives here;
    /// everything that differs comes out of `zeusFlavour`.
    private static func zeusVariant(_ element: Element) -> UnitBlueprint {
        let f = zeusFlavour(element)

        return UnitBlueprint(
            id: f.id,
            name: "Zeus",
            epithet: f.epithet,
            pantheon: .greek,
            element: element,
            archetype: .god,
            role: f.role,
            naturalStars: 5,
            baseStats: Stats(
                hp: f.hp, atk: f.atk, def: f.def, spd: f.spd,
                critRate: 0.15, critDamage: 0.50,
                accuracy: 0.10, resistance: 0.15
            ),
            growthPerLevel: .zero,   // Growth is derived from grade; see ProgressionService.
            skills: [
                // Slot 0 — basic attack, no cooldown. One bolt, one target, and
                // the variant's affliction riding on it.
                Skill(
                    id: "\(f.id)_s1",
                    name: "Thunderbolt",
                    description: zeusBoltText(f),
                    slot: 0,
                    cooldown: 0,
                    target: .singleEnemy,
                    damage: DamageSpec(multiplier: 3.10),
                    statuses: [f.boltStatus],
                    levelUpBonuses: [
                        SkillUpgrade(kind: .damageMultiplier, amount: 0.05, label: "Damage +5%"),
                        SkillUpgrade(kind: .damageMultiplier, amount: 0.05, label: "Damage +5%"),
                        SkillUpgrade(kind: .effectChance, amount: 0.05, label: "Effect Rate +5%"),
                        SkillUpgrade(kind: .damageMultiplier, amount: 0.10, label: "Damage +10%"),
                        SkillUpgrade(kind: .effectChance, amount: 0.10, label: "Effect Rate +10%")
                    ],
                    animation: .attackBasic,
                    cameraShot: .standard,
                    vfx: "thunderbolt"
                ),

                // Slot 1 — the Thunderclap. The whole enemy line, modest damage,
                // and the family's reason to exist: the turn it takes away. One
                // roll per target, never per hit.
                Skill(
                    id: "\(f.id)_s2",
                    name: "Thunderclap",
                    description: zeusClapText(f),
                    slot: 1,
                    cooldown: 4,
                    target: .allEnemies,
                    damage: DamageSpec(multiplier: 2.00),
                    statuses: [f.clapStatus],
                    utilities: f.clapExtras,
                    levelUpBonuses: [
                        SkillUpgrade(kind: .damageMultiplier, amount: 0.05, label: "Damage +5%"),
                        SkillUpgrade(kind: .effectChance, amount: 0.10, label: "Effect Rate +10%"),
                        SkillUpgrade(kind: .effectChance, amount: 0.10, label: "Effect Rate +10%"),
                        SkillUpgrade(kind: .cooldown, amount: 1, label: "Cooldown -1")
                    ],
                    animation: .attackHeavy,
                    cameraShot: .cinematicOrbit,
                    vfx: "thunderclap"
                ),

                // Slot 2 — the Keraunos. One bolt that ignores 40% of the
                // target's defence, then the variant's gift to the team — or,
                // for Umbra, its brand on the enemy.
                Skill(
                    id: "\(f.id)_s3",
                    name: "Keraunos",
                    description: zeusKeraunosText(f),
                    slot: 2,
                    cooldown: 5,
                    target: .singleEnemy,
                    damage: DamageSpec(multiplier: 5.00, defenseIgnore: 0.40),
                    statuses: f.keraunosStatus.map { [$0] } ?? [],
                    utilities: f.keraunosExtras,
                    levelUpBonuses: [
                        SkillUpgrade(kind: .damageMultiplier, amount: 0.05, label: "Damage +5%"),
                        SkillUpgrade(kind: .damageMultiplier, amount: 0.10, label: "Damage +10%"),
                        SkillUpgrade(kind: .damageMultiplier, amount: 0.10, label: "Damage +10%"),
                        SkillUpgrade(kind: .cooldown, amount: 1, label: "Cooldown -1")
                    ],
                    animation: .ultimate,
                    cameraShot: .impactClose,
                    vfx: "keraunos"
                ),

                // Slot 3 — passive, locked until awakening. The king's team
                // moves first: the whole attack bar is raised when the battle
                // begins.
                Skill(
                    id: "\(f.id)_passive",
                    name: "King of Olympus",
                    description: "[Awakened] When the battle begins, the attack bar of every ally is raised by 30%.",
                    slot: 3,
                    cooldown: 0,
                    target: .allAllies,
                    damage: nil,
                    utilities: [
                        .attackBarChange(0.30, chance: 1.0, .allAllies)
                    ],
                    isPassive: true,
                    trigger: .onBattleStart,
                    requiresAwakening: true,
                    animation: .castRelease,
                    cameraShot: .heroLowAngle,
                    vfx: "olympian_decree"
                )
            ],
            leaderSkill: f.leader,
            awakening: Awakening(
                awakenedName: f.awakenedName,
                bonusDescription: "Accuracy +20%, Resistance +10%, and the King of Olympus passive is unlocked.",
                statBonus: Stats(accuracy: 0.20, resistance: 0.10),
                skillOverrides: [:],
                essenceCost: [
                    f.essence: 15,
                    "essence_magic_mid": 10,
                    "essence_magic_high": 5
                ]
            ),
            // One mesh, five tints. Every variant loads the same `zeus` model.
            model: ModelSpec(
                assetName: "zeus",
                scale: 1.0,
                height: 2.15,
                pitchCorrection: 0,
                weaponAttachNode: "weapon_r",
                handAttachNode: "hand_r",
                chestAttachNode: "spine_03",
                auraHex: f.auraHex,
                portraitName: "portrait_\(f.id)"
            ),
            lore: """
            Kronos swallowed each of his children as they were born, and the sixth \
            was hidden on Crete and raised by a goat and a nymph until he was grown. \
            He came back, made his father give the others up, and fought the Titans \
            for ten years before the Cyclopes forged him the thunderbolt that ended \
            it. The sky fell to him by lot. He has held it since, and nothing that \
            has tried to take it is still standing.
            """
        )
    }

    private static func zeusBoltText(_ f: ZeusFlavour) -> String {
        let s = f.boltStatus
        return "Hurls a bolt at one enemy with a \(Int(s.chance * 100))% chance to inflict \(s.kind.displayName) for \(turnsText(s.turns))."
    }

    private static func zeusClapText(_ f: ZeusFlavour) -> String {
        let s = f.clapStatus
        var parts = ["Splits the sky over every enemy."]
        switch s.kind {
        case .stun:
            parts.append("Each has a \(Int(s.chance * 100))% chance to be stunned for \(turnsText(s.turns)).")
        case .freeze:
            parts.append("Each has a \(Int(s.chance * 100))% chance to be frozen for \(turnsText(s.turns)).")
        case .sleep:
            parts.append("Each has a \(Int(s.chance * 100))% chance to be put to sleep for \(turnsText(s.turns)).")
        case .provoke:
            parts.append("Each has a \(Int(s.chance * 100))% chance to be provoked into attacking Zeus for \(turnsText(s.turns)).")
        default:
            parts.append("Each has a \(Int(s.chance * 100))% chance to suffer \(s.kind.displayName) for \(turnsText(s.turns)).")
        }
        for extra in f.clapExtras {
            if case .attackBarChange(let delta, let chance, _) = extra, delta < 0 {
                let odds = chance >= 1.0 ? "" : " with a \(Int(chance * 100))% chance"
                parts.append("Knocks every enemy's attack bar back by \(Int(abs(delta) * 100))%\(odds).")
            }
        }
        return parts.joined(separator: " ")
    }

    private static func zeusKeraunosText(_ f: ZeusFlavour) -> String {
        var parts = ["Brings the Keraunos down on one enemy, ignoring 40% of its defence."]
        if let s = f.keraunosStatus {
            switch s.target {
            case .allAllies:
                parts.append("Grants the team \(s.kind.displayName) for \(turnsText(s.turns)).")
            default:
                parts.append("Inflicts \(s.kind.displayName) on every enemy for \(turnsText(s.turns)) with a \(Int(s.chance * 100))% chance.")
            }
        }
        for extra in f.keraunosExtras {
            if case .attackBarChange(let delta, _, _) = extra, delta > 0 {
                parts.append("Raises the whole team's attack bar by \(Int(delta * 100))%.")
            }
        }
        return parts.joined(separator: " ")
    }

    private static func turnsText(_ turns: Int) -> String {
        turns == 1 ? "1 turn" : "\(turns) turns"
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
