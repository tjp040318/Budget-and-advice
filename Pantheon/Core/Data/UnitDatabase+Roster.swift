import Foundation

// The second roster: Olympus filled out, and Egypt's healer.
//
// The first three families each got a file's worth of prose. These seven are
// built from the same parts with less ceremony, because the parts are proven:
// a per-element table of stats, epithet and leader skill; three skills whose
// element-specific pieces come from the shared tables below; a passive that
// awakening unlocks; and one model per family with five tints. A 3★ family is
// two skills and a leader, the shape the Shabti set.
//
// Greece before this file had one god and nothing under him, so a common roll
// on the Greek banner had nowhere to land. Now: Hoplite, Satyr and Harpy at
// 3★, Heracles and Perseus at 4★, Ares beside Zeus at 5★. Egypt gains Thoth,
// the roster's first healer.
extension UnitDatabase {

    // MARK: - Shared element tables

    /// The debuff a family's basic attack leaves per element. The first three
    /// families taught players to expect these, so every new family keeps
    /// them: fire burns, water slows, wind makes the next hit glance, light
    /// weakens the attack, dark breaks the defence.
    static func signature(_ element: Element) -> StatusKind {
        switch element {
        case .ember: return .burn
        case .tide: return .speedDown
        case .gale: return .glancing
        case .radiance: return .attackDown
        case .umbra: return .defenseDown
        }
    }

    /// How a family's control skill takes a turn away, per element.
    static func control(_ element: Element) -> StatusKind {
        switch element {
        case .ember: return .stun
        case .tide: return .freeze
        case .gale: return .silence
        case .radiance: return .provoke
        case .umbra: return .sleep
        }
    }

    /// The buff a family's team skill grants, per element.
    static func blessing(_ element: Element) -> StatusKind {
        switch element {
        case .ember: return .attackUp
        case .tide: return .defenseUp
        case .gale: return .speedUp
        case .radiance: return .immunity
        case .umbra: return .critRateUp
        }
    }

    static func essence(_ element: Element) -> String {
        "essence_\(element.rawValue)_mid"
    }

    /// The basic attack's ladder, shared by every family: five skill-ups.
    static let basicLadder: [SkillUpgrade] = [
        SkillUpgrade(kind: .damageMultiplier, amount: 0.05, label: "Damage +5%"),
        SkillUpgrade(kind: .damageMultiplier, amount: 0.05, label: "Damage +5%"),
        SkillUpgrade(kind: .effectChance, amount: 0.05, label: "Effect Rate +5%"),
        SkillUpgrade(kind: .damageMultiplier, amount: 0.10, label: "Damage +10%"),
        SkillUpgrade(kind: .effectChance, amount: 0.10, label: "Effect Rate +10%")
    ]

    /// A damaging second or third skill's ladder: damage, then a cooldown.
    static let strikeLadder: [SkillUpgrade] = [
        SkillUpgrade(kind: .damageMultiplier, amount: 0.05, label: "Damage +5%"),
        SkillUpgrade(kind: .damageMultiplier, amount: 0.10, label: "Damage +10%"),
        SkillUpgrade(kind: .effectChance, amount: 0.10, label: "Effect Rate +10%"),
        SkillUpgrade(kind: .cooldown, amount: 1, label: "Cooldown -1")
    ]

    /// A support skill's ladder: effect rate, then a cooldown.
    static let supportLadder: [SkillUpgrade] = [
        SkillUpgrade(kind: .effectChance, amount: 0.10, label: "Effect Rate +10%"),
        SkillUpgrade(kind: .healing, amount: 0.10, label: "Recovery +10%"),
        SkillUpgrade(kind: .cooldown, amount: 1, label: "Cooldown -1")
    ]

    static func turns(_ n: Int) -> String { n == 1 ? "1 turn" : "\(n) turns" }

    static func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    // MARK: - Per-element identity

    /// What changes between the five variants of one character.
    struct ElementKit {
        var epithet: String
        var awakenedName: String
        var hp: Double
        var atk: Double
        var def: Double
        var spd: Double
        var leader: LeaderSkill
    }

    // MARK: - THE ARES FAMILY (5★, Greek, attacker)
    //
    // The berserker. Where Sekhmet breaks a target's defence and kills it, Ares
    // kills and gets stronger for it: War Frenzy raises his own attack and
    // critical rate and pushes his attack bar, Slaughter hits harder the more
    // health the target has lost and can grant another turn, and the awakened
    // passive rewards every kill with more attack and more bar.

    static var aresFamily: [UnitBlueprint] { Element.allCases.map(aresVariant) }

    private static func aresKit(_ element: Element) -> ElementKit {
        switch element {
        case .ember:
            return ElementKit(epithet: "of the Red Field", awakenedName: "Ares, Bane of Cities",
                              hp: 420, atk: 40, def: 22, spd: 104,
                              leader: LeaderSkill(stat: .atkPercent, amount: 0.33, scope: .pantheon(.greek)))
        case .tide:
            return ElementKit(epithet: "of the Bronze Tide", awakenedName: "Ares Enyalios",
                              hp: 450, atk: 37, def: 24, spd: 103,
                              leader: LeaderSkill(stat: .hpPercent, amount: 0.33, scope: .pantheon(.greek)))
        case .gale:
            return ElementKit(epithet: "of the Screaming Charge", awakenedName: "Ares Stormlance",
                              hp: 405, atk: 39, def: 21, spd: 110,
                              leader: LeaderSkill(stat: .spd, amount: 0.20, scope: .pantheon(.greek)))
        case .radiance:
            return ElementKit(epithet: "of the Burnished Shield", awakenedName: "Ares Aureate",
                              hp: 430, atk: 38, def: 24, spd: 104,
                              leader: LeaderSkill(stat: .critRate, amount: 0.24, scope: .allAllies))
        case .umbra:
            return ElementKit(epithet: "of the Black Standard", awakenedName: "Ares Brotoloigos",
                              hp: 415, atk: 41, def: 21, spd: 105,
                              leader: LeaderSkill(stat: .atkPercent, amount: 0.24, scope: .allAllies))
        }
    }

    private static func aresVariant(_ element: Element) -> UnitBlueprint {
        let k = aresKit(element)
        let id = "ares_\(element.rawValue)"
        let sig = signature(element)
        let strike = StatusSpec(sig, chance: 0.30, turns: 2, target: .singleEnemy)

        return UnitBlueprint(
            id: id,
            name: "Ares",
            epithet: k.epithet,
            pantheon: .greek,
            element: element,
            archetype: .god,
            role: .attacker,
            naturalStars: 5,
            baseStats: Stats(
                hp: k.hp, atk: k.atk, def: k.def, spd: k.spd,
                critRate: 0.20, critDamage: 0.50,
                accuracy: 0.0, resistance: 0.15
            ),
            growthPerLevel: .zero,
            skills: [
                Skill(
                    id: "\(id)_s1",
                    name: "Sword of War",
                    description: "Cuts one enemy down with a \(percent(strike.chance)) chance to inflict \(sig.displayName) for \(turns(strike.turns)).",
                    slot: 0,
                    cooldown: 0,
                    target: .singleEnemy,
                    damage: DamageSpec(multiplier: 3.00),
                    statuses: [strike],
                    levelUpBonuses: basicLadder,
                    animation: .attackBasic,
                    cameraShot: .standard,
                    vfx: "lioness_rake"
                ),
                Skill(
                    id: "\(id)_s2",
                    name: "War Frenzy",
                    description: "Roars for blood: Attack Up and Focus on himself for 2 turns, and his attack bar fills by 30%.",
                    slot: 1,
                    cooldown: 3,
                    target: .caster,
                    damage: nil,
                    statuses: [
                        StatusSpec(.attackUp, chance: 1.0, turns: 2, target: .caster),
                        StatusSpec(.critRateUp, chance: 1.0, turns: 2, target: .caster)
                    ],
                    utilities: [.attackBarChange(0.30, chance: 1.0, .caster)],
                    levelUpBonuses: [
                        SkillUpgrade(kind: .cooldown, amount: 1, label: "Cooldown -1")
                    ],
                    animation: .castRelease,
                    cameraShot: .heroLowAngle,
                    vfx: "blood_thirst"
                ),
                Skill(
                    id: "\(id)_s3",
                    name: "Slaughter",
                    description: "A killing blow that deals up to 80% more damage the more health the target has lost, with a 35% chance to take another turn.",
                    slot: 2,
                    cooldown: 4,
                    target: .singleEnemy,
                    damage: DamageSpec(multiplier: 4.60, bonusPerMissingHealth: 0.008),
                    utilities: [.extraTurn(chance: 0.35)],
                    levelUpBonuses: strikeLadder,
                    animation: .ultimate,
                    cameraShot: .impactClose,
                    vfx: "eye_of_ra"
                ),
                Skill(
                    id: "\(id)_passive",
                    name: "Blood of War",
                    description: "[Awakened] Every kill grants Attack Up for 2 turns and fills his attack bar by 30%.",
                    slot: 3,
                    cooldown: 0,
                    target: .caster,
                    damage: nil,
                    statuses: [StatusSpec(.attackUp, chance: 1.0, turns: 2, target: .caster)],
                    utilities: [.attackBarChange(0.30, chance: 1.0, .caster)],
                    isPassive: true,
                    trigger: .onKill,
                    requiresAwakening: true,
                    animation: .castRelease,
                    cameraShot: .heroLowAngle,
                    vfx: "blood_thirst"
                )
            ],
            leaderSkill: k.leader,
            awakening: Awakening(
                awakenedName: k.awakenedName,
                bonusDescription: "Attack +10%, Critical Rate +10%, and the Blood of War passive is unlocked.",
                statBonus: Stats(atk: 4, critRate: 0.10),
                skillOverrides: [:],
                essenceCost: [essence(element): 15, "essence_magic_mid": 10, "essence_magic_high": 5]
            ),
            model: ModelSpec(
                assetName: "ares",
                height: 2.10,
                weaponAttachNode: "weapon_r",
                auraHex: element.accentHex,
                portraitName: "portrait_\(id)",
                melee: true,
                costumeHue: 35
            ),
            lore: """
            The other gods tolerate him the way a city tolerates its garrison. Where \
            Athena fights to end a war, Ares fights because the war is there, and the \
            field is never so red that he leaves it. Even his father calls him the most \
            hateful of all the gods. The soldiers who pray to him know better than to \
            ask for victory. They ask that he notice them.
            """
        )
    }

    // MARK: - THE HERACLES FAMILY (4★, Greek, defender)
    //
    // The bruiser. A tank whose damage scales with his own health, so building
    // him sturdy also builds him dangerous: the Nemean Roar drags the enemy
    // line onto him and raises his defence, the Twelve Labours hit for a share
    // of his maximum health, and awakened, the Lion's Hide shields him the
    // first time he falls below half.

    static var heraclesFamily: [UnitBlueprint] { Element.allCases.map(heraclesVariant) }

    private static func heraclesKit(_ element: Element) -> ElementKit {
        switch element {
        case .ember:
            return ElementKit(epithet: "the Lion-Slayer", awakenedName: "Heracles Olympian",
                              hp: 560, atk: 26, def: 30, spd: 98,
                              leader: LeaderSkill(stat: .hpPercent, amount: 0.25, scope: .pantheon(.greek)))
        case .tide:
            return ElementKit(epithet: "of the Stables", awakenedName: "Heracles Alexikakos",
                              hp: 600, atk: 24, def: 32, spd: 96,
                              leader: LeaderSkill(stat: .defPercent, amount: 0.25, scope: .pantheon(.greek)))
        case .gale:
            return ElementKit(epithet: "of the Golden Hind", awakenedName: "Heracles Swift-Foot",
                              hp: 540, atk: 27, def: 28, spd: 106,
                              leader: LeaderSkill(stat: .spd, amount: 0.15, scope: .pantheon(.greek)))
        case .radiance:
            return ElementKit(epithet: "of the Apples", awakenedName: "Heracles Kallinikos",
                              hp: 570, atk: 25, def: 31, spd: 98,
                              leader: LeaderSkill(stat: .resistance, amount: 0.25, scope: .allAllies))
        case .umbra:
            return ElementKit(epithet: "of the Hound's Gate", awakenedName: "Heracles of Erebos",
                              hp: 550, atk: 28, def: 29, spd: 99,
                              leader: LeaderSkill(stat: .hpPercent, amount: 0.18, scope: .allAllies))
        }
    }

    private static func heraclesVariant(_ element: Element) -> UnitBlueprint {
        let k = heraclesKit(element)
        let id = "heracles_\(element.rawValue)"
        let sig = signature(element)
        let strike = StatusSpec(sig, chance: 0.30, turns: 2, target: .singleEnemy)
        let roar = StatusSpec(.provoke, chance: 0.50, turns: 1, target: .allEnemies)

        return UnitBlueprint(
            id: id,
            name: "Heracles",
            epithet: k.epithet,
            pantheon: .greek,
            element: element,
            archetype: .demigod,
            role: .defender,
            naturalStars: 4,
            baseStats: Stats(
                hp: k.hp, atk: k.atk, def: k.def, spd: k.spd,
                critRate: 0.15, critDamage: 0.50,
                accuracy: 0.0, resistance: 0.20
            ),
            growthPerLevel: .zero,
            skills: [
                Skill(
                    id: "\(id)_s1",
                    name: "Club Swing",
                    description: "Swings the club at one enemy with a \(percent(strike.chance)) chance to inflict \(sig.displayName) for \(turns(strike.turns)).",
                    slot: 0,
                    cooldown: 0,
                    target: .singleEnemy,
                    damage: DamageSpec(multiplier: 2.90),
                    statuses: [strike],
                    levelUpBonuses: basicLadder,
                    animation: .attackBasic,
                    cameraShot: .standard,
                    vfx: "impact_generic"
                ),
                Skill(
                    id: "\(id)_s2",
                    name: "Nemean Roar",
                    description: "Roars at the whole enemy line for modest damage with a 50% chance to Provoke each of them for 1 turn, and takes Defense Up for 2 turns.",
                    slot: 1,
                    cooldown: 4,
                    target: .allEnemies,
                    damage: DamageSpec(multiplier: 1.60),
                    statuses: [
                        roar,
                        StatusSpec(.defenseUp, chance: 1.0, turns: 2, target: .caster)
                    ],
                    levelUpBonuses: strikeLadder,
                    animation: .attackHeavy,
                    cameraShot: .pushIn,
                    vfx: "wrath_of_the_eye"
                ),
                Skill(
                    id: "\(id)_s3",
                    name: "Twelve Labours",
                    description: "Brings the club down for damage equal to 30% of his maximum health, ignoring 30% of the target's defence.",
                    slot: 2,
                    cooldown: 4,
                    target: .singleEnemy,
                    damage: DamageSpec(multiplier: 0.30, scaling: .maxHealth, defenseIgnore: 0.30),
                    levelUpBonuses: strikeLadder,
                    animation: .ultimate,
                    cameraShot: .impactClose,
                    vfx: "heart_weigh"
                ),
                Skill(
                    id: "\(id)_passive",
                    name: "Lion's Hide",
                    description: "[Awakened] The first time he falls below half health, a shield worth 30% of his maximum health and Defense Up for 2 turns.",
                    slot: 3,
                    cooldown: 0,
                    target: .caster,
                    damage: nil,
                    statuses: [
                        StatusSpec(.shield, chance: 1.0, turns: 2, target: .caster, magnitude: 0.30),
                        StatusSpec(.defenseUp, chance: 1.0, turns: 2, target: .caster)
                    ],
                    isPassive: true,
                    trigger: .onLowHealth,
                    requiresAwakening: true,
                    animation: .castRelease,
                    cameraShot: .heroLowAngle,
                    vfx: "maat_shield"
                )
            ],
            leaderSkill: k.leader,
            awakening: Awakening(
                awakenedName: k.awakenedName,
                bonusDescription: "Health +8%, Defence +8%, and the Lion's Hide passive is unlocked.",
                statBonus: Stats(hp: 45, def: 3),
                skillOverrides: [:],
                essenceCost: [essence(element): 10, "essence_magic_mid": 8, "essence_magic_high": 3]
            ),
            model: ModelSpec(
                assetName: "heracles",
                height: 2.05,
                weaponAttachNode: "weapon_r",
                auraHex: element.accentHex,
                portraitName: "portrait_\(id)",
                melee: true,
                costumeHue: 38
            ),
            lore: """
            Hera sent two serpents to his crib and he strangled them both before he \
            could speak. The twelve labours were a penance, not a boast: he did them to \
            be clean of something, and came out of them wearing the first one's skin. \
            He is the only mortal-born the gods let onto Olympus, and he still fights \
            like a man who expects to be sent back.
            """
        )
    }

    // MARK: - THE PERSEUS FAMILY (4★, Greek, attacker)
    //
    // Speed and control. Two quick cuts, a shield that turns the team's
    // defence up and his own into a counter, and the Gorgon's Gaze: the whole
    // enemy line, one roll each, the element's way of taking a turn away.
    // Awakened, the winged sandals put him ahead of the field at the start.

    static var perseusFamily: [UnitBlueprint] { Element.allCases.map(perseusVariant) }

    private static func perseusKit(_ element: Element) -> ElementKit {
        switch element {
        case .ember:
            return ElementKit(epithet: "of the Bronze Blade", awakenedName: "Perseus Gorgon-Bane",
                              hp: 470, atk: 31, def: 24, spd: 110,
                              leader: LeaderSkill(stat: .atkPercent, amount: 0.25, scope: .pantheon(.greek)))
        case .tide:
            return ElementKit(epithet: "of the Sea-Rock", awakenedName: "Perseus Wave-Rider",
                              hp: 500, atk: 29, def: 26, spd: 108,
                              leader: LeaderSkill(stat: .defPercent, amount: 0.25, scope: .pantheon(.greek)))
        case .gale:
            return ElementKit(epithet: "of the Winged Sandals", awakenedName: "Perseus Sky-Walker",
                              hp: 455, atk: 30, def: 23, spd: 118,
                              leader: LeaderSkill(stat: .spd, amount: 0.18, scope: .pantheon(.greek)))
        case .radiance:
            return ElementKit(epithet: "of the Mirror Shield", awakenedName: "Perseus Argive",
                              hp: 480, atk: 30, def: 25, spd: 110,
                              leader: LeaderSkill(stat: .accuracy, amount: 0.25, scope: .allAllies))
        case .umbra:
            return ElementKit(epithet: "of the Dark Helm", awakenedName: "Perseus Unseen",
                              hp: 465, atk: 32, def: 23, spd: 111,
                              leader: LeaderSkill(stat: .critDamage, amount: 0.25, scope: .allAllies))
        }
    }

    private static func perseusVariant(_ element: Element) -> UnitBlueprint {
        let k = perseusKit(element)
        let id = "perseus_\(element.rawValue)"
        let sig = signature(element)
        let ctrl = control(element)
        let cut = StatusSpec(sig, chance: 0.25, turns: 2, target: .singleEnemy)
        let gaze = StatusSpec(ctrl, chance: 0.45, turns: 1, target: .allEnemies)

        return UnitBlueprint(
            id: id,
            name: "Perseus",
            epithet: k.epithet,
            pantheon: .greek,
            element: element,
            archetype: .hero,
            role: .attacker,
            naturalStars: 4,
            baseStats: Stats(
                hp: k.hp, atk: k.atk, def: k.def, spd: k.spd,
                critRate: 0.15, critDamage: 0.50,
                accuracy: 0.10, resistance: 0.15
            ),
            growthPerLevel: .zero,
            skills: [
                Skill(
                    id: "\(id)_s1",
                    name: "Harpe Cuts",
                    description: "Two quick cuts. Each has a \(percent(cut.chance)) chance to inflict \(sig.displayName) for \(turns(cut.turns)).",
                    slot: 0,
                    cooldown: 0,
                    target: .singleEnemy,
                    damage: DamageSpec(multiplier: 1.45, hits: 2),
                    statuses: [cut],
                    levelUpBonuses: basicLadder,
                    animation: .attackBasic,
                    cameraShot: .standard,
                    vfx: "scale_strike"
                ),
                Skill(
                    id: "\(id)_s2",
                    name: "Mirror Shield",
                    description: "Raises the polished shield: Defense Up for every ally for 2 turns, and he takes a Counter stance for 2 turns.",
                    slot: 1,
                    cooldown: 4,
                    target: .allAllies,
                    damage: nil,
                    statuses: [
                        StatusSpec(.defenseUp, chance: 1.0, turns: 2, target: .allAllies),
                        StatusSpec(.counterStance, chance: 1.0, turns: 2, target: .caster)
                    ],
                    levelUpBonuses: [
                        SkillUpgrade(kind: .cooldown, amount: 1, label: "Cooldown -1")
                    ],
                    animation: .castRelease,
                    cameraShot: .pushIn,
                    vfx: "maat_shield"
                ),
                Skill(
                    id: "\(id)_s3",
                    name: "Gorgon's Gaze",
                    description: "Uncovers the head of Medusa before the whole enemy line for damage and a \(percent(gaze.chance)) chance to inflict \(ctrl.displayName) on each for \(turns(gaze.turns)).",
                    slot: 2,
                    cooldown: 5,
                    target: .allEnemies,
                    damage: DamageSpec(multiplier: 2.20),
                    statuses: [gaze],
                    levelUpBonuses: strikeLadder,
                    animation: .ultimate,
                    cameraShot: .cinematicOrbit,
                    vfx: "wrath_of_the_eye"
                ),
                Skill(
                    id: "\(id)_passive",
                    name: "Winged Sandals",
                    description: "[Awakened] When the battle begins, his attack bar fills by 25% and he gains Haste for 2 turns.",
                    slot: 3,
                    cooldown: 0,
                    target: .caster,
                    damage: nil,
                    statuses: [StatusSpec(.speedUp, chance: 1.0, turns: 2, target: .caster)],
                    utilities: [.attackBarChange(0.25, chance: 1.0, .caster)],
                    isPassive: true,
                    trigger: .onBattleStart,
                    requiresAwakening: true,
                    animation: .castRelease,
                    cameraShot: .heroLowAngle,
                    vfx: "buff"
                )
            ],
            leaderSkill: k.leader,
            awakening: Awakening(
                awakenedName: k.awakenedName,
                bonusDescription: "Speed +8, Accuracy +15%, and the Winged Sandals passive is unlocked.",
                statBonus: Stats(spd: 8, accuracy: 0.15),
                skillOverrides: [:],
                essenceCost: [essence(element): 10, "essence_magic_mid": 8, "essence_magic_high": 3]
            ),
            model: ModelSpec(
                assetName: "perseus",
                height: 1.90,
                weaponAttachNode: "weapon_r",
                auraHex: element.accentHex,
                portraitName: "portrait_\(id)",
                melee: true,
                costumeHue: 35
            ),
            lore: """
            His grandfather locked his mother in a bronze room to keep her from having \
            him, and Zeus came in as rain. Sent for the Gorgon's head as a joke that was \
            meant to kill him, he came back with it in a bag, having borrowed a mirror \
            shield, a helm of darkness and a pair of winged sandals from gods who found \
            him worth the loan. He turned a king to stone with the head and then gave it \
            back. He is the one hero who kept his promises and died old.
            """
        )
    }

    // MARK: - THE THOTH FAMILY (5★, Egyptian, support)
    //
    // The roster's first healer. Words of Healing restores the team and
    // cleanses it; the Book of the Dead grants Immunity and the element's
    // blessing and pushes the whole team's attack bar; awakened, the Scribe
    // heals the weakest ally at the start of each of his turns. He casts from
    // where he stands.

    static var thothFamily: [UnitBlueprint] { Element.allCases.map(thothVariant) }

    private static func thothKit(_ element: Element) -> ElementKit {
        switch element {
        case .ember:
            return ElementKit(epithet: "of the Burning Reed", awakenedName: "Thoth Djehuty",
                              hp: 520, atk: 26, def: 30, spd: 108,
                              leader: LeaderSkill(stat: .atkPercent, amount: 0.25, scope: .pantheon(.egyptian)))
        case .tide:
            return ElementKit(epithet: "of the Inundation", awakenedName: "Thoth of the Flood",
                              hp: 560, atk: 24, def: 32, spd: 106,
                              leader: LeaderSkill(stat: .hpPercent, amount: 0.33, scope: .pantheon(.egyptian)))
        case .gale:
            return ElementKit(epithet: "of the Wind-Read Sky", awakenedName: "Thoth the Measurer",
                              hp: 505, atk: 25, def: 29, spd: 116,
                              leader: LeaderSkill(stat: .spd, amount: 0.20, scope: .pantheon(.egyptian)))
        case .radiance:
            return ElementKit(epithet: "of the Silver Disc", awakenedName: "Thoth, Lord of Khemenu",
                              hp: 530, atk: 25, def: 31, spd: 108,
                              leader: LeaderSkill(stat: .resistance, amount: 0.30, scope: .allAllies))
        case .umbra:
            return ElementKit(epithet: "of the Sealed Book", awakenedName: "Thoth, Keeper of Secrets",
                              hp: 515, atk: 27, def: 30, spd: 109,
                              leader: LeaderSkill(stat: .accuracy, amount: 0.30, scope: .allAllies))
        }
    }

    private static func thothVariant(_ element: Element) -> UnitBlueprint {
        let k = thothKit(element)
        let id = "thoth_\(element.rawValue)"
        let sig = signature(element)
        let bless = blessing(element)
        let stroke = StatusSpec(sig, chance: 0.35, turns: 2, target: .singleEnemy)

        return UnitBlueprint(
            id: id,
            name: "Thoth",
            epithet: k.epithet,
            pantheon: .egyptian,
            element: element,
            archetype: .god,
            role: .support,
            naturalStars: 5,
            baseStats: Stats(
                hp: k.hp, atk: k.atk, def: k.def, spd: k.spd,
                critRate: 0.15, critDamage: 0.50,
                accuracy: 0.15, resistance: 0.20
            ),
            growthPerLevel: .zero,
            skills: [
                Skill(
                    id: "\(id)_s1",
                    name: "Reed Stroke",
                    description: "Writes a judgement on one enemy with a \(percent(stroke.chance)) chance to inflict \(sig.displayName) for \(turns(stroke.turns)).",
                    slot: 0,
                    cooldown: 0,
                    target: .singleEnemy,
                    damage: DamageSpec(multiplier: 2.60),
                    statuses: [stroke],
                    levelUpBonuses: basicLadder,
                    animation: .attackBasic,
                    cameraShot: .standard,
                    vfx: "impact_generic"
                ),
                Skill(
                    id: "\(id)_s2",
                    name: "Words of Healing",
                    description: "Heals every ally for 30% of their maximum health and removes up to 2 harmful effects from each.",
                    slot: 1,
                    cooldown: 4,
                    target: .allAllies,
                    damage: nil,
                    utilities: [
                        .healTargetMaxHealth(0.30, .allAllies),
                        .cleanse(count: 2, .allAllies)
                    ],
                    levelUpBonuses: supportLadder,
                    animation: .castRelease,
                    cameraShot: .pushIn,
                    vfx: "heal"
                ),
                Skill(
                    id: "\(id)_s3",
                    name: "Book of the Dead",
                    description: "Reads from the book: Immunity and \(bless.displayName) for every ally for 2 turns, and the team's attack bar fills by 25%.",
                    slot: 2,
                    cooldown: 5,
                    target: .allAllies,
                    damage: nil,
                    statuses: [
                        StatusSpec(.immunity, chance: 1.0, turns: 2, target: .allAllies),
                        StatusSpec(bless, chance: 1.0, turns: 2, target: .allAllies)
                    ],
                    utilities: [.attackBarChange(0.25, chance: 1.0, .allAllies)],
                    levelUpBonuses: [
                        SkillUpgrade(kind: .cooldown, amount: 1, label: "Cooldown -1")
                    ],
                    animation: .ultimate,
                    cameraShot: .cinematicOrbit,
                    vfx: "duat_rite"
                ),
                Skill(
                    id: "\(id)_passive",
                    name: "Scribe of Ma'at",
                    description: "[Awakened] At the start of each of his turns, the ally with the least health is healed for 10% of their maximum health.",
                    slot: 3,
                    cooldown: 0,
                    target: .lowestHealthAlly,
                    damage: nil,
                    utilities: [.healTargetMaxHealth(0.10, .lowestHealthAlly)],
                    isPassive: true,
                    trigger: .onTurnStart,
                    requiresAwakening: true,
                    animation: .castRelease,
                    cameraShot: .heroLowAngle,
                    vfx: "heal"
                )
            ],
            leaderSkill: k.leader,
            awakening: Awakening(
                awakenedName: k.awakenedName,
                bonusDescription: "Health +8%, Resistance +15%, and the Scribe of Ma'at passive is unlocked.",
                statBonus: Stats(hp: 42, resistance: 0.15),
                skillOverrides: [:],
                essenceCost: [essence(element): 15, "essence_magic_mid": 10, "essence_magic_high": 5]
            ),
            model: ModelSpec(
                assetName: "thoth",
                height: 2.05,
                weaponAttachNode: "weapon_r",
                auraHex: element.accentHex,
                portraitName: "portrait_\(id)",
                melee: false,
                costumeHue: 45
            ),
            lore: """
            He invented writing, then used it to record the verdict every time a heart \
            was weighed, and no one has found an error. He arbitrates between gods who \
            would otherwise fight, he measured the year, and he wrote the spells the dead \
            need in a book he keeps on him. The other gods come to him with problems. He \
            comes back with the answer already written down.
            """
        )
    }

    // MARK: - The 3★ tier of Greece: Hoplite, Satyr, Harpy
    //
    // The shape the Shabti set: two skills and no awakening, a real unit on
    // day one and fodder on day two. These three also carry small leader
    // skills, because a Greek team on the day the banner opens is mostly them.

    static var hopliteFamily: [UnitBlueprint] { Element.allCases.map(hopliteVariant) }
    static var satyrFamily: [UnitBlueprint] { Element.allCases.map(satyrVariant) }
    static var harpyFamily: [UnitBlueprint] { Element.allCases.map(harpyVariant) }

    private static func hopliteVariant(_ element: Element) -> UnitBlueprint {
        let epithets: [Element: String] = [
            .ember: "of Sparta", .tide: "of Corinth", .gale: "of Athens", .radiance: "of Delphi", .umbra: "of Thebes"
        ]
        return common(
            family: "hoplite",
            name: "Hoplite",
            epithet: epithets[element] ?? "of Greece",
            element: element,
            archetype: .hero,
            role: .defender,
            hp: 340, atk: 22, def: 26, spd: 96,
            basicName: "Spear Jab",
            basicMultiplier: 1.70,
            special: Skill(
                id: "hoplite_\(element.rawValue)_s2",
                name: "Phalanx",
                description: "Locks shields: Defense Up for every ally for 2 turns and a shield worth 20% of his maximum health on himself.",
                slot: 1,
                cooldown: 4,
                target: .allAllies,
                damage: nil,
                statuses: [
                    StatusSpec(.defenseUp, chance: 1.0, turns: 2, target: .allAllies),
                    StatusSpec(.shield, chance: 1.0, turns: 2, target: .caster, magnitude: 0.20)
                ],
                levelUpBonuses: [SkillUpgrade(kind: .cooldown, amount: 1, label: "Cooldown -1")],
                animation: .castRelease,
                cameraShot: .pushIn,
                vfx: "maat_shield"
            ),
            leader: LeaderSkill(stat: .defPercent, amount: 0.15, scope: .pantheon(.greek)),
            height: 1.85,
            melee: true,
            costumeHue: 35,
            lore: "A citizen with a spear, a shield and a place in the line. The line is the weapon; he is one of its bones."
        )
    }

    private static func satyrVariant(_ element: Element) -> UnitBlueprint {
        let epithets: [Element: String] = [
            .ember: "Ember Piper", .tide: "River Piper", .gale: "Hill Piper", .radiance: "Noon Piper", .umbra: "Night Piper"
        ]
        return common(
            family: "satyr",
            name: "Satyr",
            epithet: epithets[element] ?? "Piper",
            element: element,
            archetype: .monster,
            role: .support,
            hp: 300, atk: 22, def: 20, spd: 104,
            basicName: "Hoof Kick",
            basicMultiplier: 1.70,
            special: Skill(
                id: "satyr_\(element.rawValue)_s2",
                name: "Wild Piping",
                description: "Plays the pipes: every ally is healed for 15% of their maximum health and gains Haste for 2 turns.",
                slot: 1,
                cooldown: 4,
                target: .allAllies,
                damage: nil,
                statuses: [StatusSpec(.speedUp, chance: 1.0, turns: 2, target: .allAllies)],
                utilities: [.healTargetMaxHealth(0.15, .allAllies)],
                levelUpBonuses: supportLadder,
                animation: .castRelease,
                cameraShot: .pushIn,
                vfx: "heal"
            ),
            leader: LeaderSkill(stat: .hpPercent, amount: 0.15, scope: .pantheon(.greek)),
            height: 1.60,
            melee: true,
            costumeHue: 45,
            lore: "Half goat, all appetite. He follows the wine and the music, and where he plays, tired feet find they can dance."
        )
    }

    private static func harpyVariant(_ element: Element) -> UnitBlueprint {
        let epithets: [Element: String] = [
            .ember: "Cinder Wing", .tide: "Storm Wing", .gale: "Gale Wing", .radiance: "Sun Wing", .umbra: "Night Wing"
        ]
        return common(
            family: "harpy",
            name: "Harpy",
            epithet: epithets[element] ?? "Wing",
            element: element,
            archetype: .monster,
            role: .attacker,
            hp: 270, atk: 28, def: 16, spd: 112,
            basicName: "Talon Rake",
            basicMultiplier: 1.00,
            basicHits: 2,
            special: Skill(
                id: "harpy_\(element.rawValue)_s2",
                name: "Screech Dive",
                description: "Dives on one enemy for heavy damage with a 60% chance to knock its attack bar back by 30%.",
                slot: 1,
                cooldown: 3,
                target: .singleEnemy,
                damage: DamageSpec(multiplier: 2.60),
                utilities: [.attackBarChange(-0.30, chance: 0.60, .singleEnemy)],
                levelUpBonuses: strikeLadder,
                animation: .attackHeavy,
                cameraShot: .pushIn,
                vfx: "lioness_rake"
            ),
            leader: LeaderSkill(stat: .spd, amount: 0.10, scope: .pantheon(.greek)),
            height: 1.75,
            melee: true,
            costumeHue: 35,
            lore: "The snatchers. They took food from tables and men from ships, and the wind that follows them smells of the sea."
        )
    }

    /// A 3★ family member: the basic attack with the element's signature
    /// debuff, one special, a small leader skill, one model for the family.
    private static func common(
        family: String,
        name: String,
        epithet: String,
        element: Element,
        archetype: Archetype,
        role: CombatRole,
        hp: Double, atk: Double, def: Double, spd: Double,
        basicName: String,
        basicMultiplier: Double,
        basicHits: Int = 1,
        special: Skill,
        leader: LeaderSkill,
        height: Float,
        melee: Bool,
        costumeHue: Float,
        lore: String
    ) -> UnitBlueprint {
        let id = "\(family)_\(element.rawValue)"
        let sig = signature(element)
        let strike = StatusSpec(sig, chance: 0.25, turns: 2, target: .singleEnemy)
        let hitsText = basicHits > 1 ? "Strikes \(basicHits) times. Each strike has" : "Strikes one enemy with"
        return UnitBlueprint(
            id: id,
            name: name,
            epithet: epithet,
            pantheon: .greek,
            element: element,
            archetype: archetype,
            role: role,
            naturalStars: 3,
            baseStats: Stats(
                hp: hp, atk: atk, def: def, spd: spd,
                critRate: 0.15, critDamage: 0.50, accuracy: 0.0, resistance: 0.15
            ),
            growthPerLevel: .zero,
            skills: [
                Skill(
                    id: "\(id)_s1",
                    name: basicName,
                    description: "\(hitsText) a \(percent(strike.chance)) chance to inflict \(sig.displayName) for \(turns(strike.turns)).",
                    slot: 0,
                    cooldown: 0,
                    target: .singleEnemy,
                    damage: DamageSpec(multiplier: basicMultiplier, hits: basicHits),
                    statuses: [strike],
                    levelUpBonuses: basicLadder,
                    animation: .attackBasic,
                    cameraShot: .standard,
                    vfx: "impact_generic"
                ),
                special
            ],
            leaderSkill: leader,
            awakening: nil,
            model: ModelSpec(
                assetName: family,
                height: height,
                weaponAttachNode: "weapon_r",
                auraHex: element.accentHex,
                portraitName: "portrait_\(id)",
                melee: melee,
                costumeHue: costumeHue
            ),
            lore: lore
        )
    }

    /// Everything this file adds, for the registry.
    static var secondRoster: [UnitBlueprint] {
        aresFamily + heraclesFamily + perseusFamily + thothFamily + hopliteFamily + satyrFamily + harpyFamily
    }
}
