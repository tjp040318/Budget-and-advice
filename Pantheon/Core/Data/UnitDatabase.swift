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

    static let all: [UnitBlueprint] = anubisFamily + sekhmetFamily + zeusFamily + shabtiFamily + secondRoster + thirdRoster + [
        shabti,
        serpopard,
        sunScarab,
        sandstoneSentinel,
        ammit,
        apep,
        labyrinthMinotaur,
        cyclopsShepherd,
        amazonRaider,
        medusaOfTheCape,
        lernaeanHydra,
        barrowDraugr,
        berserkerChieftain,
        valkyrieChooser,
        frostTroll,
        jotunnKing,
        lostLegionCenturion,
        morningGladiator,
        coldHearthVestal,
        palatinePraetorian,
        bronzeColossus,
        tombJiangshi,
        buriedArmySoldier,
        coldLampFox,
        buriedArmyGeneral,
        longmenDragon,
        colossusOfTheVault,
        unwrappedKing
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
    ///
    /// The six fusion prizes are absent too, and that filter is the whole
    /// promise the Hall of Ka's hexagram makes: a recipe that costs four
    /// raised units and 120,000 drachma for something a scroll might have
    /// handed over anyway is not a reward, it is a tax. `FusionService`
    /// derives `fusionOnlyIDs` from its own recipe table, so the exclusion
    /// list cannot drift from the prizes — there is only one list. Reading it
    /// here cannot re-enter this file, because that table is literals.
    static let summonPool: [String] = (anubisFamily + sekhmetFamily + zeusFamily + shabtiFamily + secondRoster + thirdRoster)
        .filter { $0.hasShippedArt && !FusionService.isFusionOnly($0.id) }
        .map { $0.id }

    /// Everything a player can ever own: the gacha's pool plus what only the
    /// hexagram gives. The codex counts against this, not against the pool,
    /// or a fused god would push the readout past its own total.
    static let collectiblePool: [String] = summonPool + FusionService.fusionOnlyIDs.sorted()

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

    // Cached, not computed. These were `static var` bodies, so every reader
    // rebuilt the whole family — five blueprints and their skill kits — from
    // scratch. `all`, `summonPool` and `collectiblePool` each read them, and so
    // does every screen that asks the database anything, so the roster was
    // being constructed several times over on whichever thread asked first.
    // With seventy-nine families that is 395 blueprints a rebuild, and it is
    // what the owner felt as "it did get really laggy after I clicked on
    // Arena" on 2026-09-10: the arena builds five opponents the moment it
    // appears and was paying for the roster again to do it. A `static let` is
    // built once, lazily, under a one-time lock.
    static let shabtiFamily: [UnitBlueprint] = Element.allCases.map(shabtiVariant)

    private static func shabtiVariant(_ element: Element) -> UnitBlueprint {
        let id = "shabti_\(element.rawValue)"
        let epithet: String
        let stats: (hp: Double, atk: Double, def: Double, spd: Double)
        switch element {
        case .ember:
            epithet = "Kiln Servant"
            stats = (290, 26, 19, 97)
        case .tide:
            epithet = "Nile Servant"
            stats = (320, 23, 21, 96)
        case .gale:
            epithet = "Dune Servant"
            stats = (285, 24, 18, 106)
        case .radiance:
            epithet = "Sun Servant"
            stats = (305, 24, 22, 98)
        case .umbra:
            epithet = "Tomb Servant"
            stats = (300, 25, 20, 98)
        }

        // A servant answers five ways. The family used to come out of the
        // enemy factory with one special and an element rider on it; a real
        // second skill per element is a real kit, so it is written out here
        // the way the factory's own comment asks. Dark, the Tomb Servant, is
        // the home: Answer the Call as first written.
        let special: Skill
        switch element {
        case .ember:
            special = smite(id, slot: 1, "Kiln Fire",
                            "A blow with a 60% chance to Burn the target for 2 turns, hitting 10% harder for every harmful effect on it.",
                            cd: 3, DamageSpec(multiplier: 2.20, bonusPerTargetDebuff: 0.10),
                            statuses: [status(.burn, 0.60)], vfx: "impact_ember")
        case .tide:
            special = smite(id, slot: 1, "Nile Undertow",
                            "A blow with a 50% chance to Freeze the target for 1 turn.",
                            cd: 3, DamageSpec(multiplier: 2.30), statuses: [status(.freeze, 0.50, turns: 1)], vfx: "impact_tide")
        case .gale:
            special = smite(id, slot: 1, "Dust Devil",
                            "Two quick blows on one enemy, each with a 30% chance to make its next hit Glancing for 2 turns.",
                            cd: 3, DamageSpec(multiplier: 1.20, hits: 2), statuses: [status(.glancing, 0.30, perHit: true)],
                            vfx: "impact_gale")
        case .radiance:
            special = smite(id, slot: 1, "Sunlit Ward",
                            "A blow with a 60% chance to inflict Attack Down for 2 turns; the servant takes a shield worth 15% of its maximum health for 2 turns.",
                            cd: 3, DamageSpec(multiplier: 2.10),
                            statuses: [status(.attackDown, 0.60), status(.shield, 1.0, on: .caster, magnitude: 0.15)],
                            vfx: "impact_radiance")
        case .umbra:
            special = smite(id, slot: 1, "Answer the Call",
                            "Answers for its master with one blow, with a 40% chance to Break the target's defence for 2 turns.",
                            cd: 3, DamageSpec(multiplier: 2.30), statuses: [status(.defenseDown, 0.40)], vfx: "heart_weigh")
        }

        return UnitBlueprint(
            id: id,
            name: "Shabti",
            epithet: epithet,
            pantheon: .egyptian,
            element: element,
            archetype: .spirit,
            role: .attacker,
            naturalStars: 3,
            baseStats: Stats(
                hp: stats.hp, atk: stats.atk, def: stats.def, spd: stats.spd,
                critRate: 0.15, critDamage: 0.50, accuracy: 0.0, resistance: 0.15
            ),
            growthPerLevel: .zero,
            skills: [
                Skill(
                    id: "\(id)_s1",
                    name: "Clay Grasp",
                    description: "Attacks the enemy.",
                    slot: 0,
                    cooldown: 0,
                    target: .singleEnemy,
                    damage: DamageSpec(multiplier: 1.60),
                    animation: .attackBasic,
                    cameraShot: .standard,
                    vfx: "impact_generic"
                ),
                special
            ],
            leaderSkill: nil,
            awakening: nil,
            // Every Shabti wears the one shabti model, tinted by element.
            model: ModelSpec(assetName: "shabti", auraHex: element.accentHex, portraitName: "portrait_\(id)"),
            lore: """
            A figurine placed in the tomb to answer for its master when the dead are \
            called to work the fields. Ask, and it says: here I am.
            """
        )
    }

    // MARK: - THE ANUBIS FAMILY
    //
    // Five elemental variants of one character, the way the genre does it: the
    // same silhouette and the same kit *shape*, differentiated by stat lean, by
    // leader skill, and by a second and third skill of the element's own. They
    // are five separate summonable units and five separate collection entries.
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
    static let anubisFamily: [UnitBlueprint] =
        [anubisEmber, anubisTide, anubisGale, anubisRadiance, anubisUmbra]

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
                strikeStatus: StatusSpec(.brand, chance: 0.30, turns: 2, target: .singleEnemy, rollsPerHit: true),
                essence: "essence_umbra_mid"
            )
        }
    }

    /// Builds one elemental variant. Everything the five share lives here;
    /// everything that differs comes out of `anubisFlavour`.
    private static func anubisVariant(_ element: Element) -> UnitBlueprint {
        let f = anubisFlavour(element)

        // The judge's five ways. Every form weighs one heart and every form's
        // rite brings a fallen ally back — that is what Anubis IS — and dark,
        // the Guardian of the Scales, is the home: the weighing and the
        // Opening of the Mouth as first written.
        let second: Skill
        let third: Skill
        switch element {
        case .ember:
            second = smite(f.id, slot: 1, "Verdict of Ash",
                           "Weighs one enemy against the feather and finds it wanting: a blow that ignores 30% of its defence, with a 70% chance to Burn it for 2 turns, hitting 15% harder for every harmful effect on it.",
                           cd: 3, DamageSpec(multiplier: 3.70, defenseIgnore: 0.30, bonusPerTargetDebuff: 0.15),
                           statuses: [status(.burn, 0.70)], vfx: "impact_ember")
            third = ritual(f.id, slot: 2, "Rite of the Ash Road",
                           "Revives one fallen ally with 40% health and grants every ally Attack Up for 2 turns; every enemy has a 50% chance to Burn for 2 turns.",
                           cd: 5, statuses: [status(.attackUp, 1.0, on: .allAllies), status(.burn, 0.50, on: .allEnemies)],
                           utilities: [.revive(healthFraction: 0.40)], vfx: "duat_rite")
        case .tide:
            second = smite(f.id, slot: 1, "Ferryman's Toll",
                           "Weighs one enemy against the feather: a crushing blow with a 60% chance to Freeze it for 1 turn and a 70% chance to drag its attack bar back by 25%.",
                           cd: 3, DamageSpec(multiplier: 3.50),
                           statuses: [status(.freeze, 0.60, turns: 1)],
                           utilities: [.attackBarChange(-0.25, chance: 0.70, .singleEnemy)], vfx: "impact_tide")
            third = ritual(f.id, slot: 2, "Rite of the Reed Sea",
                           "Revives one fallen ally with 50% health, heals every ally for 30% of their maximum health and grants Defense Up for 2 turns; every enemy has a 60% chance to have its attack bar dragged back by 20%.",
                           cd: 5, statuses: [status(.defenseUp, 1.0, on: .allAllies)],
                           utilities: [.revive(healthFraction: 0.50), .healTargetMaxHealth(0.30, .allAllies),
                                       .attackBarChange(-0.20, chance: 0.60, .allEnemies)], vfx: "heal")
        case .gale:
            second = smite(f.id, slot: 1, "Khamsin Lash",
                           "Three strikes of the balance-arm on one enemy, each with a 30% chance to make its next hit Glancing for 2 turns, and a 30% chance to take another turn.",
                           cd: 3, DamageSpec(multiplier: 1.40, hits: 3),
                           statuses: [status(.glancing, 0.30, perHit: true)], utilities: [.extraTurn(chance: 0.30)],
                           vfx: "impact_gale")
            third = ritual(f.id, slot: 2, "Breath of the Khamsin",
                           "Revives one fallen ally with 40% health, grants every ally Haste for 2 turns, and fills the team's attack bar by 25%.",
                           cd: 5, statuses: [status(.speedUp, 1.0, on: .allAllies)],
                           utilities: [.revive(healthFraction: 0.40), .attackBarChange(0.25, chance: 1.0, .allAllies)], vfx: "buff")
        case .radiance:
            second = smite(f.id, slot: 1, "Solar Verdict",
                           "Weighs one enemy in the light of the barque: a strike that always crits and removes up to two beneficial effects from it with a 75% chance, with a 60% chance to inflict Attack Down for 2 turns.",
                           cd: 3, DamageSpec(multiplier: 3.20, alwaysCrits: true),
                           statuses: [status(.attackDown, 0.60)], utilities: [.strip(count: 2, chance: 0.75, .singleEnemy)],
                           vfx: "impact_radiance")
            third = ritual(f.id, slot: 2, "Rite of the Night Sun",
                           "Revives one fallen ally with 70% health, removes up to two harmful effects from every ally, and grants Immunity and a shield worth 15% of his maximum health for 2 turns.",
                           cd: 5, statuses: [status(.immunity, 1.0, on: .allAllies), status(.shield, 1.0, on: .allAllies, magnitude: 0.15)],
                           utilities: [.revive(healthFraction: 0.70), .cleanse(count: 2, .allAllies)], vfx: "maat_shield")
        case .umbra:
            second = smite(f.id, slot: 1, "Weighing of the Heart",
                           "Weighs one enemy against the feather: a blow that deals up to 110% more damage the more health the target has lost, and strips one beneficial effect from it with a 70% chance.",
                           cd: 3, DamageSpec(multiplier: 4.10, bonusPerMissingHealth: 1.10),
                           utilities: [.strip(count: 1, chance: 0.70, .singleEnemy)], vfx: "heart_weigh")
            third = ritual(f.id, slot: 2, "Opening of the Mouth",
                           "Performs the rite. Revives one fallen ally at 50% health, heals every ally for 25% of their maximum health, and grants the team Immunity for 2 turns.",
                           cd: 5, statuses: [status(.immunity, 1.0, on: .allAllies)],
                           utilities: [.revive(healthFraction: 0.50), .healTargetMaxHealth(0.25, .allAllies)], vfx: "duat_rite")
        }

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

                // Slot 1 — the judgement, and slot 2 — the rite, the element's
                // own. The revive quietly does nothing when nobody is dead, so
                // the rite is always worth pressing: it either brings somebody
                // back or it is the team's buff and whatever else it carries.
                second,
                third,

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

    // MARK: - THE SEKHMET FAMILY
    //
    // The second family, and the roster's first real damage archetype. Where
    // Anubis heals, strips and revives, Sekhmet breaks defence and kills. Every
    // variant breaks a defence somewhere in its kit — that is the family's
    // identity the way the revive is Anubis's — and the five differ by what
    // the claws leave behind, by the second and third skill, which are the
    // element's own, and by the leader skill.
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
    static let sekhmetFamily: [UnitBlueprint] =
        [sekhmetEmber, sekhmetTide, sekhmetGale, sekhmetRadiance, sekhmetUmbra]

    /// Per-element identity for Sekhmet: the stat lean and what the claws
    /// inflict. The Eye and the Wrath are the element's own, in `sekhmetVariant`.
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
                essence: "essence_radiance_mid"
            )
        case .umbra:
            // The plague-bringer. Her third skill is a plague on the enemy
            // rather than a gift to the team, and her Seven Arrows grow with
            // every affliction and drink from the wound.
            return SekhmetFlavour(
                id: "sekhmet_umbra",
                epithet: "Mistress of Plague",
                awakenedName: "Sekhmet, Bringer of the Seven Arrows",
                role: .attacker,
                hp: 450, atk: 34, def: 26, spd: 105,
                auraHex: "#9B5FD9",
                leader: LeaderSkill(stat: .hpPercent, amount: 0.33, scope: .allAllies),
                rakeStatus: StatusSpec(.unrecoverable, chance: 0.30, turns: 2, target: .singleEnemy, rollsPerHit: true),
                essence: "essence_umbra_mid"
            )
        }
    }

    /// Builds one elemental variant. Everything the five share lives here;
    /// everything that differs comes out of `sekhmetFlavour`.
    private static func sekhmetVariant(_ element: Element) -> UnitBlueprint {
        let f = sekhmetFlavour(element)

        // The lioness's five ways. Every form breaks a defence somewhere and
        // every third skill is unleashed on the whole line; fire, the
        // Scorching Noon, is the home: the Eye and the Wrath as first written.
        let second: Skill
        let third: Skill
        switch element {
        case .ember:
            second = smite(f.id, slot: 1, "Eye of Ra",
                           "Fixes one enemy with the Eye of Ra and breaks its defence for 2 turns with an 85% chance.",
                           cd: 3, DamageSpec(multiplier: 4.80), statuses: [status(.defenseDown, 0.85)], vfx: "eye_of_ra")
            third = smite(f.id, slot: 2, "Wrath of the Eye",
                          "Unleashes the Eye on every enemy. Grants the team Attack Up for 2 turns.",
                          cd: 5, DamageSpec(multiplier: 2.60), target: .allEnemies,
                          statuses: [status(.attackUp, 1.0, on: .allAllies)], vfx: "wrath_of_the_eye")
        case .tide:
            second = smite(f.id, slot: 1, "Red Nile Draught",
                           "Fixes one enemy with the Eye: a blow with a 70% chance to Freeze it for 1 turn and a 60% chance to Break its defence for 2 turns.",
                           cd: 3, DamageSpec(multiplier: 4.00),
                           statuses: [status(.freeze, 0.70, turns: 1), status(.defenseDown, 0.60)], vfx: "impact_tide")
            third = smite(f.id, slot: 2, "Seven Thousand Jars",
                          "Pours the red flood over the whole enemy line: each has a 50% chance to be Slowed for 2 turns and a 60% chance to have its attack bar dragged back by 25%; the team takes Defense Up for 2 turns.",
                          cd: 5, DamageSpec(multiplier: 2.40), target: .allEnemies,
                          statuses: [status(.speedDown, 0.50, on: .allEnemies), status(.defenseUp, 1.0, on: .allAllies)],
                          utilities: [.attackBarChange(-0.25, chance: 0.60, .allEnemies)], vfx: "wrath_of_the_eye")
        case .gale:
            second = smite(f.id, slot: 1, "Khamsin Claws",
                           "Three rakes on one enemy, each with a 35% chance to Break its defence for 2 turns, and a 30% chance to take another turn.",
                           cd: 3, DamageSpec(multiplier: 1.50, hits: 3),
                           statuses: [status(.defenseDown, 0.35, perHit: true)], utilities: [.extraTurn(chance: 0.30)],
                           vfx: "lioness_rake")
            third = smite(f.id, slot: 2, "Roar of the Burning Wind",
                          "Roars over the whole enemy line with a 40% chance to make each one's next hit Glancing for 2 turns; the team takes Haste for 2 turns and its attack bar fills by 20%.",
                          cd: 5, DamageSpec(multiplier: 2.30), target: .allEnemies,
                          statuses: [status(.glancing, 0.40, on: .allEnemies), status(.speedUp, 1.0, on: .allAllies)],
                          utilities: [.attackBarChange(0.20, chance: 1.0, .allAllies)], vfx: "wrath_of_the_eye")
        case .radiance:
            second = smite(f.id, slot: 1, "Eye of the Disc",
                           "Fixes one enemy with the sun's own Eye: a strike that always crits, removes one beneficial effect from it with an 85% chance, and has a 75% chance to Break its defence for 2 turns.",
                           cd: 3, DamageSpec(multiplier: 3.60, alwaysCrits: true),
                           statuses: [status(.defenseDown, 0.75)], utilities: [.strip(count: 1, chance: 0.85, .singleEnemy)],
                           vfx: "eye_of_ra")
            third = smite(f.id, slot: 2, "Noon Without Shadow",
                          "Unleashes the disc's light on the whole enemy line with a 50% chance to inflict Attack Down on each for 2 turns; the team takes Focus and a shield worth 12% of her maximum health for 2 turns.",
                          cd: 5, DamageSpec(multiplier: 2.40), target: .allEnemies,
                          statuses: [status(.attackDown, 0.50, on: .allEnemies), status(.critRateUp, 1.0, on: .allAllies),
                                     status(.shield, 1.0, on: .allAllies, magnitude: 0.12)], vfx: "olympian_decree")
        case .umbra:
            second = smite(f.id, slot: 1, "Seven Arrows",
                           "Looses the plague on one enemy: a blow that heals her for 40% of the damage and hits 20% harder for every harmful effect on it, with a 75% chance to Break its defence for 2 turns.",
                           cd: 3, DamageSpec(multiplier: 4.00, bonusPerTargetDebuff: 0.20),
                           statuses: [status(.defenseDown, 0.75)], utilities: [.lifesteal(0.40)], vfx: "heart_weigh")
            third = smite(f.id, slot: 2, "Breath of Plague",
                          "Breathes plague over the whole enemy line for damage that grows the more health each has lost, with a 50% chance to Brand each for 2 turns and a 40% chance to Break its defence.",
                          cd: 5, DamageSpec(multiplier: 2.30, bonusPerMissingHealth: 0.50), target: .allEnemies,
                          statuses: [status(.brand, 0.50, on: .allEnemies), status(.defenseDown, 0.40, on: .allEnemies)],
                          vfx: "blood_thirst")
        }

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

                // Slot 1 — the Eye, and slot 2 — the Wrath on the whole line,
                // the element's own.
                second,
                third,

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

    // MARK: - THE ZEUS FAMILY
    //
    // The third family, and the first from a second pantheon. Zeus is the
    // roster's control archetype: Anubis sustains, Sekhmet kills, Zeus decides
    // who gets to act. Every variant hits the whole enemy line somewhere in
    // its kit and takes turns away from it — a stun, a freeze, a sleep, a
    // knockback down the attack bar, or a provoke that drags every enemy onto
    // him — and fire's Keraunos is the one bolt that ignores 40% of defence
    // and then hands the team something; the other four kits are the
    // element's own (`zeusVariant`). The awakened passive pushes the whole
    // team's attack bar at the start of battle, so a Zeus team moves first.
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
    static let zeusFamily: [UnitBlueprint] =
        [zeusEmber, zeusTide, zeusGale, zeusRadiance, zeusUmbra]

    /// Per-element identity for Zeus: the stat lean and what the bolt leaves
    /// on its target. The second and third skills are the element's own, in
    /// `zeusVariant`.
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
                essence: "essence_ember_mid"
            )
        case .tide:
            // The rain-bringer. The sturdiest Zeus: one freezing bolt that
            // drags the bar and a deluge on the line with a shield on the
            // whole team behind it.
            return ZeusFlavour(
                id: "zeus_tide",
                epithet: "of the Storm-Dark Sea",
                awakenedName: "Zeus Ombrios",
                role: .defender,
                hp: 505, atk: 31, def: 29, spd: 103,
                auraHex: "#4FC3F7",
                leader: LeaderSkill(stat: .hpPercent, amount: 0.33, scope: .pantheon(.greek)),
                boltStatus: StatusSpec(.speedDown, chance: 0.35, turns: 2, target: .singleEnemy),
                essence: "essence_tide_mid"
            )
        case .gale:
            // The turn-thief. No hard control at all: four scattered bolts
            // that may earn him another turn, and a storm on the line that
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
                essence: "essence_gale_mid"
            )
        case .radiance:
            // All eyes on the king. The Eye of Panoptes provokes the enemy
            // line onto Zeus himself and shields him for it, which is why this
            // variant is the one built to take the hits, and the Aegis grants
            // the team Immunity.
            return ZeusFlavour(
                id: "zeus_radiance",
                epithet: "Bringer of Day",
                awakenedName: "Zeus Panoptes",
                role: .defender,
                hp: 480, atk: 32, def: 28, spd: 106,
                auraHex: "#FFE680",
                leader: LeaderSkill(stat: .accuracy, amount: 0.35, scope: .pantheon(.greek)),
                boltStatus: StatusSpec(.brand, chance: 0.35, turns: 2, target: .singleEnemy),
                essence: "essence_radiance_mid"
            )
        case .umbra:
            // The Zeus beneath the earth. The black cloud puts the line to
            // sleep and brands it, and the bolt from below drinks and breaks
            // — the one variant whose kit gives the team nothing at all.
            return ZeusFlavour(
                id: "zeus_umbra",
                epithet: "of the Black Cloud",
                awakenedName: "Zeus Katachthonios",
                role: .controller,
                hp: 470, atk: 34, def: 26, spd: 104,
                auraHex: "#A07CFF",
                leader: LeaderSkill(stat: .critRate, amount: 0.24, scope: .allAllies),
                boltStatus: StatusSpec(.attackDown, chance: 0.35, turns: 2, target: .singleEnemy),
                essence: "essence_umbra_mid"
            )
        }
    }

    /// Builds one elemental variant. Everything the five share lives here;
    /// everything that differs comes out of `zeusFlavour`.
    private static func zeusVariant(_ element: Element) -> UnitBlueprint {
        let f = zeusFlavour(element)

        // The stormlord's five ways. Every form hits the whole line somewhere
        // and every form decides who gets to act; fire, the Scorching Sky, is
        // the home: the Thunderclap and the Keraunos as first written.
        let second: Skill
        let third: Skill
        switch element {
        case .ember:
            second = smite(f.id, slot: 1, "Thunderclap",
                           "Splits the sky over every enemy. Each has a 55% chance to be stunned for 1 turn.",
                           cd: 4, DamageSpec(multiplier: 2.00), target: .allEnemies,
                           statuses: [status(.stun, 0.55, turns: 1, on: .allEnemies)], vfx: "thunderclap")
            third = smite(f.id, slot: 2, "Keraunos",
                          "Brings the Keraunos down on one enemy, ignoring 40% of its defence. Grants the team Attack Up for 2 turns.",
                          cd: 5, DamageSpec(multiplier: 5.00, defenseIgnore: 0.40),
                          statuses: [status(.attackUp, 1.0, on: .allAllies)], vfx: "keraunos")
        case .tide:
            second = smite(f.id, slot: 1, "Hail of Ombrios",
                           "A crushing bolt on one enemy with a 70% chance to Freeze it for 1 turn and a 70% chance to drag its attack bar back by 30%; Zeus takes Defense Up for 2 turns.",
                           cd: 4, DamageSpec(multiplier: 3.60),
                           statuses: [status(.freeze, 0.70, turns: 1), status(.defenseUp, 1.0, on: .caster)],
                           utilities: [.attackBarChange(-0.30, chance: 0.70, .singleEnemy)], vfx: "thunderbolt")
            third = smite(f.id, slot: 2, "Deluge of Deucalion",
                          "Opens the sky over the whole enemy line: a bolt that ignores 30% of each one's defence, with a 50% chance to Slow each for 2 turns; every ally takes a shield worth 20% of his maximum health for 2 turns.",
                          cd: 5, DamageSpec(multiplier: 2.50, defenseIgnore: 0.30), target: .allEnemies,
                          statuses: [status(.speedDown, 0.50, on: .allEnemies), status(.shield, 1.0, on: .allAllies, magnitude: 0.20)],
                          vfx: "thunderclap")
        case .gale:
            second = smite(f.id, slot: 1, "Ourios Gusts",
                           "Four bolts at random enemies, each with a 25% chance to make its victim's next hit Glancing for 2 turns, and a 30% chance to take another turn.",
                           cd: 4, DamageSpec(multiplier: 1.15, hits: 4), target: .randomEnemies(count: 4),
                           statuses: [status(.glancing, 0.25, perHit: true)], utilities: [.extraTurn(chance: 0.30)],
                           vfx: "thunderbolt")
            third = smite(f.id, slot: 2, "Crown of Storms",
                          "Splits the sky over the whole enemy line, then takes Haste for 2 turns and fills the whole team's attack bar by 30%.",
                          cd: 5, DamageSpec(multiplier: 2.40), target: .allEnemies,
                          statuses: [status(.speedUp, 1.0, on: .allAllies)],
                          utilities: [.attackBarChange(0.30, chance: 1.0, .allAllies)], vfx: "thunderclap")
        case .radiance:
            second = smite(f.id, slot: 1, "Eye of Panoptes",
                           "Sees the whole enemy line at once: damage with a 60% chance to Provoke each onto Zeus for 1 turn, removing one beneficial effect from each with a 70% chance; Zeus takes a shield worth 20% of his maximum health for 2 turns.",
                           cd: 4, DamageSpec(multiplier: 1.80), target: .allEnemies,
                           statuses: [status(.provoke, 0.60, turns: 1, on: .allEnemies), status(.shield, 1.0, on: .caster, magnitude: 0.20)],
                           utilities: [.strip(count: 1, chance: 0.70, .allEnemies)], vfx: "eye_of_ra")
            third = smite(f.id, slot: 2, "Aegis of Day",
                          "Brings the Aegis down on one enemy: a sure critical bolt that ignores 40% of its defence, with an 80% chance to inflict Attack Down for 2 turns; every ally gains Immunity for 2 turns.",
                          cd: 5, DamageSpec(multiplier: 4.60, defenseIgnore: 0.40, alwaysCrits: true),
                          statuses: [status(.attackDown, 0.80), status(.immunity, 1.0, on: .allAllies)], vfx: "keraunos")
        case .umbra:
            second = smite(f.id, slot: 1, "Black Cloud",
                           "Draws the black cloud over the whole enemy line: each has a 45% chance to be put to Sleep for 1 turn and a 50% chance to be Branded for 2 turns.",
                           cd: 4, DamageSpec(multiplier: 1.90), target: .allEnemies,
                           statuses: [status(.sleep, 0.45, turns: 1, on: .allEnemies), status(.brand, 0.50, on: .allEnemies)],
                           vfx: "thunderclap")
            third = smite(f.id, slot: 2, "Chthonic Bolt",
                          "Brings the Keraunos up from beneath the earth on one enemy: a bolt that ignores 40% of its defence and grows the more health it has lost, healing Zeus for 30% of the damage, with a 75% chance to Break its defence for 2 turns.",
                          cd: 5, DamageSpec(multiplier: 4.60, defenseIgnore: 0.40, bonusPerMissingHealth: 0.50),
                          statuses: [status(.defenseDown, 0.75)], utilities: [.lifesteal(0.30)], vfx: "keraunos")
        }

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

                // Slots 1 and 2 — the element's own: the turn it takes away
                // from the line, one roll per target, and the bolt or the
                // storm that follows.
                second,
                third,

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
        auraHex: String,
        assetName: String? = nil,
        portraitName: String? = nil,
        height: Float? = nil,
        standInAsset: String? = nil
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
                assetName: assetName ?? id,
                height: height ?? (archetype == .primordial ? 7.2 : 1.9),
                auraHex: auraHex,
                portraitName: portraitName ?? "portrait_\(id)",
                standInAsset: standInAsset
            ),
            lore: epithet
        )
    }

    // MARK: - The Greek and Norse campaigns
    //
    // The creatures of Olympus and Yggdrasil fight in their chapters with the
    // roster's own models and cards (`assetName`, `portraitName`) and a
    // two-skill enemy kit of their own, so a summoned Minotaur and the one in
    // the labyrinth look the same and play differently. They are enemies:
    // not in the pool, never summoned. The two bosses have models of their
    // own, unrigged, moved by the loader's procedural motion.

    static let labyrinthMinotaur = enemy(
        id: "enemy_minotaur", name: "Minotaur", epithet: "Beast of the Labyrinth",
        element: .umbra, archetype: .monster, role: .defender, stars: 3,
        hp: 390, atk: 27, def: 25, spd: 92,
        basicName: "Horn Toss", basicMultiplier: 1.60,
        specialName: "Bull Rush", specialMultiplier: 3.00,
        specialStatus: StatusSpec(.speedDown, chance: 0.50, turns: 2, target: .singleEnemy),
        pantheon: .greek, auraHex: "#B0502C",
        assetName: "minotaur", portraitName: "portrait_minotaur_umbra", height: 2.4
    )

    static let cyclopsShepherd = enemy(
        id: "enemy_cyclops", name: "Cyclops", epithet: "Shepherd of the Isle",
        element: .ember, archetype: .monster, role: .attacker, stars: 3,
        hp: 370, atk: 30, def: 20, spd: 88,
        basicName: "Club Smash", basicMultiplier: 1.70,
        specialName: "Boulder Heave", specialMultiplier: 2.40, specialTarget: .allEnemies,
        specialStatus: StatusSpec(.defenseDown, chance: 0.35, turns: 2, target: .allEnemies),
        pantheon: .greek, auraHex: "#E07A3C",
        assetName: "cyclops", portraitName: "portrait_cyclops_ember", height: 2.6
    )

    static let amazonRaider = enemy(
        id: "enemy_amazon", name: "Amazon", epithet: "Raider of the Steppe",
        element: .gale, archetype: .hero, role: .attacker, stars: 3,
        hp: 310, atk: 28, def: 20, spd: 108,
        basicName: "Labrys Cut", basicMultiplier: 1.70,
        specialName: "Crescent Sweep", specialMultiplier: 2.80,
        specialStatus: StatusSpec(.defenseDown, chance: 0.40, turns: 2, target: .singleEnemy),
        pantheon: .greek, auraHex: "#A8E0B8",
        assetName: "amazon", portraitName: "portrait_amazon_gale"
    )

    static let medusaOfTheCape = enemy(
        id: "enemy_medusa", name: "Medusa", epithet: "Gaze of the Cape",
        element: .radiance, archetype: .monster, role: .support, stars: 3,
        hp: 330, atk: 26, def: 21, spd: 100,
        basicName: "Serpent Lash", basicMultiplier: 0.90, basicHits: 2,
        specialName: "Petrifying Gaze", specialMultiplier: 2.00,
        specialStatus: StatusSpec(.stun, chance: 0.35, turns: 1, target: .singleEnemy),
        specialCooldown: 4,
        pantheon: .greek, auraHex: "#F0E0A0",
        assetName: "medusa", portraitName: "portrait_medusa_radiance"
    )

    /// The boss of the Marsh of Lerna: three bites a turn and a breath that
    /// softens the whole line.
    static let lernaeanHydra = enemy(
        id: "boss_hydra", name: "Lernaean Hydra", epithet: "Nine Heads of the Marsh",
        element: .tide, archetype: .primordial, role: .attacker, stars: 5,
        hp: 1050, atk: 40, def: 30, spd: 92,
        basicName: "Three Bites", basicMultiplier: 0.80, basicHits: 3,
        specialName: "Venom Breath", specialMultiplier: 2.40, specialTarget: .allEnemies,
        specialStatus: StatusSpec(.defenseDown, chance: 0.50, turns: 2, target: .allEnemies),
        specialCooldown: 4,
        pantheon: .greek, auraHex: "#5EC8A0", height: 7.0
    )

    static let barrowDraugr = enemy(
        id: "enemy_draugr", name: "Draugr", epithet: "Guard of the Barrow",
        element: .umbra, archetype: .spirit, role: .defender, stars: 3,
        hp: 370, atk: 23, def: 27, spd: 88,
        basicName: "Grave Axe", basicMultiplier: 1.60,
        specialName: "Barrow Grip", specialMultiplier: 2.60,
        specialStatus: StatusSpec(.speedDown, chance: 0.50, turns: 2, target: .singleEnemy),
        pantheon: .norse, auraHex: "#6C8AA0",
        assetName: "draugr", portraitName: "portrait_draugr_umbra"
    )

    static let berserkerChieftain = enemy(
        id: "enemy_berserker", name: "Berserker", epithet: "Chieftain of the Bear-Shirts",
        element: .ember, archetype: .hero, role: .attacker, stars: 3,
        hp: 330, atk: 30, def: 17, spd: 103,
        basicName: "Twin Axes", basicMultiplier: 0.95, basicHits: 2,
        specialName: "Bear Rage", specialMultiplier: 3.20,
        specialStatus: StatusSpec(.defenseDown, chance: 0.45, turns: 2, target: .singleEnemy),
        pantheon: .norse, auraHex: "#E06040",
        assetName: "berserker", portraitName: "portrait_berserker_ember", height: 2.0
    )

    static let valkyrieChooser = enemy(
        id: "enemy_valkyrie", name: "Valkyrie", epithet: "Chooser of the Slain",
        element: .radiance, archetype: .spirit, role: .attacker, stars: 3,
        hp: 315, atk: 27, def: 21, spd: 108,
        basicName: "Spear Thrust", basicMultiplier: 1.70,
        specialName: "Chooser's Cut", specialMultiplier: 3.00,
        specialStatus: StatusSpec(.attackDown, chance: 0.45, turns: 2, target: .singleEnemy),
        pantheon: .norse, auraHex: "#F0F0FF",
        assetName: "valkyrie", portraitName: "portrait_valkyrie_radiance"
    )

    static let frostTroll = enemy(
        id: "enemy_frost_troll", name: "Frost Troll", epithet: "Thing Under the Glacier",
        element: .tide, archetype: .monster, role: .defender, stars: 3,
        hp: 430, atk: 25, def: 26, spd: 84,
        basicName: "Ice Club", basicMultiplier: 1.60,
        specialName: "Glacier Roar", specialMultiplier: 2.40, specialTarget: .allEnemies,
        specialStatus: StatusSpec(.freeze, chance: 0.30, turns: 1, target: .allEnemies),
        specialCooldown: 4,
        pantheon: .norse, auraHex: "#A0E0FF",
        assetName: "frost_troll", portraitName: "portrait_frost_troll_tide", height: 2.5
    )

    /// The boss of the Hall of Jötunheim: slow, enormous, and his avalanche
    /// can freeze the line.
    static let jotunnKing = enemy(
        id: "boss_jotunn", name: "Jötunn", epithet: "King Under the Ice",
        element: .gale, archetype: .primordial, role: .defender, stars: 5,
        hp: 1150, atk: 37, def: 34, spd: 88,
        basicName: "Ice Axe", basicMultiplier: 1.90,
        specialName: "Avalanche", specialMultiplier: 2.60, specialTarget: .allEnemies,
        specialStatus: StatusSpec(.freeze, chance: 0.35, turns: 1, target: .allEnemies),
        specialCooldown: 4,
        pantheon: .norse, auraHex: "#9CD8FF", height: 7.5
    )

    // MARK: - The Roman and Chinese campaigns
    //
    // The Seven Hills and the Jade Court fight with their commons' models and
    // cards, as Olympus and Yggdrasil do. Until those meshes ship (batch 4
    // waits for credits) each stands in as a shipped figure of its kind
    // (`standInAsset`), so the chapters play now rather than when the
    // credits arrive; the family's own mesh takes over the moment it lands.

    static let lostLegionCenturion = enemy(
        id: "enemy_centurion", name: "Centurion", epithet: "Of the Lost Legion",
        element: .umbra, archetype: .spirit, role: .defender, stars: 3,
        hp: 380, atk: 24, def: 27, spd: 92,
        basicName: "Gladius Thrust", basicMultiplier: 1.60,
        specialName: "Pilum Cast", specialMultiplier: 2.80,
        specialStatus: StatusSpec(.defenseDown, chance: 0.40, turns: 2, target: .singleEnemy),
        pantheon: .roman, auraHex: "#8C7A9C",
        assetName: "centurion", portraitName: "portrait_centurion_umbra", height: 1.95,
        standInAsset: "hoplite"
    )

    static let morningGladiator = enemy(
        id: "enemy_gladiator", name: "Gladiator", epithet: "Of the Morning Games",
        element: .ember, archetype: .hero, role: .attacker, stars: 3,
        hp: 330, atk: 30, def: 18, spd: 104,
        basicName: "Arena Cut", basicMultiplier: 1.70,
        specialName: "Crowd's Roar", specialMultiplier: 3.10,
        specialStatus: StatusSpec(.defenseDown, chance: 0.40, turns: 2, target: .singleEnemy),
        pantheon: .roman, auraHex: "#E07040",
        assetName: "gladiator", portraitName: "portrait_gladiator_ember", height: 1.95,
        standInAsset: "berserker"
    )

    static let coldHearthVestal = enemy(
        id: "enemy_vestal", name: "Vestal", epithet: "Keeper of the Cold Hearth",
        element: .radiance, archetype: .hero, role: .support, stars: 3,
        hp: 340, atk: 25, def: 22, spd: 102,
        basicName: "Ember Cast", basicMultiplier: 0.90, basicHits: 2,
        specialName: "Sacred Fire", specialMultiplier: 2.00, specialTarget: .allEnemies,
        specialStatus: StatusSpec(.burn, chance: 0.40, turns: 2, target: .allEnemies),
        specialCooldown: 4,
        pantheon: .roman, auraHex: "#FFE8B0",
        assetName: "vestal", portraitName: "portrait_vestal_radiance", height: 1.85,
        standInAsset: "cobra_priestess"
    )

    /// A second enemy on the centurion's mesh, as the five elements already
    /// are: the palace guard in the sea's colour, with a shield that stuns.
    static let palatinePraetorian = enemy(
        id: "enemy_praetorian", name: "Praetorian", epithet: "Guard of the Palatine",
        element: .tide, archetype: .hero, role: .defender, stars: 3,
        hp: 400, atk: 25, def: 26, spd: 90,
        basicName: "Pilum Thrust", basicMultiplier: 1.60,
        specialName: "Shield Bash", specialMultiplier: 2.60,
        specialStatus: StatusSpec(.stun, chance: 0.35, turns: 1, target: .singleEnemy),
        specialCooldown: 4,
        pantheon: .roman, auraHex: "#7CB0D0",
        assetName: "centurion", portraitName: "portrait_centurion_tide", height: 1.95,
        standInAsset: "hoplite"
    )

    /// The boss of the Sand of the Colosseum: the bronze giant of the Sun
    /// that stood by the amphitheatre's gate and gave it its name, stepped
    /// down off its plinth. Slow, enormous, and its crown sets the line alight.
    static let bronzeColossus = enemy(
        id: "boss_bronze_colossus", name: "Colossus of the Sun", epithet: "Bronze Giant of the Amphitheatre",
        element: .ember, archetype: .primordial, role: .defender, stars: 5,
        hp: 1200, atk: 38, def: 36, spd: 84,
        basicName: "Bronze Fist", basicMultiplier: 1.90,
        specialName: "Sun-Crown Blaze", specialMultiplier: 2.70, specialTarget: .allEnemies,
        specialStatus: StatusSpec(.burn, chance: 0.45, turns: 2, target: .allEnemies),
        specialCooldown: 4,
        pantheon: .roman, auraHex: "#FFB347", height: 7.0,
        standInAsset: "boss_colossus"
    )

    static let tombJiangshi = enemy(
        id: "enemy_jiangshi", name: "Jiangshi", epithet: "Hopping Dead of the Tombs",
        element: .umbra, archetype: .spirit, role: .attacker, stars: 3,
        hp: 335, atk: 28, def: 21, spd: 96,
        basicName: "Stiff Claws", basicMultiplier: 0.90, basicHits: 2,
        specialName: "Hopping Lunge", specialMultiplier: 3.00,
        specialStatus: StatusSpec(.defenseDown, chance: 0.40, turns: 2, target: .singleEnemy),
        pantheon: .chinese, auraHex: "#9C8CC0",
        assetName: "jiangshi", portraitName: "portrait_jiangshi_umbra", height: 1.90,
        standInAsset: "mummy"
    )

    static let buriedArmySoldier = enemy(
        id: "enemy_terracotta_soldier", name: "Terracotta Soldier", epithet: "Of the Buried Army",
        element: .radiance, archetype: .spirit, role: .defender, stars: 3,
        hp: 420, atk: 24, def: 28, spd: 86,
        basicName: "Bronze Halberd", basicMultiplier: 1.60,
        specialName: "Ranks of Clay", specialMultiplier: 2.40, specialTarget: .allEnemies,
        specialStatus: StatusSpec(.defenseDown, chance: 0.35, turns: 2, target: .allEnemies),
        specialCooldown: 4,
        pantheon: .chinese, auraHex: "#E8D0A0",
        assetName: "terracotta_soldier", portraitName: "portrait_terracotta_soldier_radiance", height: 1.95,
        standInAsset: "sandstone_sentinel"
    )

    static let coldLampFox = enemy(
        id: "enemy_fox_spirit", name: "Fox Spirit", epithet: "Of the Cold Lamp",
        element: .gale, archetype: .spirit, role: .support, stars: 3,
        hp: 320, atk: 27, def: 21, spd: 110,
        basicName: "Fox-Fire", basicMultiplier: 1.70,
        specialName: "Beguiling Glance", specialMultiplier: 2.00,
        specialStatus: StatusSpec(.stun, chance: 0.35, turns: 1, target: .singleEnemy),
        specialCooldown: 4,
        pantheon: .chinese, auraHex: "#B8E8C8",
        assetName: "fox_spirit", portraitName: "portrait_fox_spirit_gale", height: 1.85,
        standInAsset: "nymph"
    )

    /// A second enemy on the soldier's mesh: the van's general, a head
    /// taller, kiln-hot.
    static let buriedArmyGeneral = enemy(
        id: "enemy_terracotta_general", name: "Terracotta General", epithet: "Of the First Emperor's Van",
        element: .ember, archetype: .spirit, role: .defender, stars: 3,
        hp: 440, atk: 27, def: 27, spd: 88,
        basicName: "Halberd Sweep", basicMultiplier: 1.60,
        specialName: "Kiln-Fired Charge", specialMultiplier: 2.80,
        specialStatus: StatusSpec(.defenseDown, chance: 0.45, turns: 2, target: .singleEnemy),
        pantheon: .chinese, auraHex: "#E89050",
        assetName: "terracotta_soldier", portraitName: "portrait_terracotta_soldier_ember", height: 2.20,
        standInAsset: "sandstone_sentinel"
    )

    /// The boss of the Dragon King's Gate: a carp that leapt the falls at
    /// Longmen and became a dragon, and never stopped growing. Three coils a
    /// turn, and the flood behind it can freeze the line. The serpent stands
    /// in for it until its own mesh is made.
    static let longmenDragon = enemy(
        id: "boss_longmen_dragon", name: "Dragon of Longmen", epithet: "Carp That Leapt the Falls",
        element: .tide, archetype: .primordial, role: .attacker, stars: 5,
        hp: 1100, atk: 41, def: 31, spd: 90,
        basicName: "Fang and Coil", basicMultiplier: 0.85, basicHits: 3,
        specialName: "Flood of the Falls", specialMultiplier: 2.50, specialTarget: .allEnemies,
        specialStatus: StatusSpec(.freeze, chance: 0.35, turns: 1, target: .allEnemies),
        specialCooldown: 4,
        pantheon: .chinese, auraHex: "#5FB8E8", height: 6.6,
        standInAsset: "dragon_king"
    )

    // MARK: - The Labyrinth's bosses

    /// The Vault's colossus: a statue that stood up. Slow, enormous, and
    /// its fall can stun the whole line.
    static let colossusOfTheVault = enemy(
        id: "boss_colossus", name: "Colossus", epithet: "Statue That Stood Up",
        element: .radiance, archetype: .primordial, role: .defender, stars: 5,
        hp: 1250, atk: 36, def: 40, spd: 80,
        basicName: "Stone Fist", basicMultiplier: 1.90,
        specialName: "Fall of the Colossus", specialMultiplier: 2.80, specialTarget: .allEnemies,
        specialStatus: StatusSpec(.stun, chance: 0.30, turns: 1, target: .allEnemies),
        specialCooldown: 4,
        auraHex: "#F5D96B", portraitName: "portrait_boss_colossus", height: 8.0,
        standInAsset: "sandstone_sentinel"
    )

    /// The Necropolis's king: unwrapped, quick for a dead man, and his
    /// ledger slows everyone it names.
    static let unwrappedKing = enemy(
        id: "boss_unwrapped_king", name: "Unwrapped King", epithet: "Who Was Never Weighed",
        element: .umbra, archetype: .spirit, role: .controller, stars: 5,
        hp: 1000, atk: 42, def: 30, spd: 96,
        basicName: "Crook and Flail", basicMultiplier: 0.95, basicHits: 2,
        specialName: "Weight of the Ledger", specialMultiplier: 2.60, specialTarget: .allEnemies,
        specialStatus: StatusSpec(.speedDown, chance: 0.50, turns: 2, target: .allEnemies),
        specialCooldown: 4,
        auraHex: "#B08CFF", portraitName: "portrait_boss_unwrapped_king", height: 6.0,
        standInAsset: "mummy"
    )
}
