import Foundation

// The third roster and batch 3: sixty-eight families from one table.
//
// The first eleven families were each written out by hand. At thirty more
// that stops being a virtue, so this file is a table — one row per family
// with the numbers, names and words that make it itself — and a builder that
// turns a row into five element variants with a full kit. What varies by
// family is the row; what varies by element is the shared tables in
// `UnitDatabase+Roster.swift` (`signature`, `control`, `blessing`); what
// varies by role is a **kit**, one of eight skill shapes below. A player who
// has learned one striker knows every striker's shape and reads the family's
// difference in its numbers and its names, which is how the genre keeps a
// roster of hundreds legible.
extension UnitDatabase {

    // MARK: - Kits

    /// The eight skill shapes. Each is three actives (two for a 3★) and a
    /// passive that awakening unlocks (none for a 3★).
    enum Kit {
        /// Melee attacker: a strike, a two-hit break, a line-wide finisher;
        /// kills feed him.
        case striker
        /// Precise attacker: two cuts, a defence-ignoring blow, a sure crit.
        case duelist
        /// Ranged attacker (`melee` false): a shot, a spread, a line-wide
        /// volley that takes the turn away; first off the mark.
        case marksman
        /// Tank whose big hit scales with his own health; a roar that
        /// provokes; a shield when he falls low.
        case bruiser
        /// Guardian: a strike, a shield wall for the team, a counter stance.
        case warden
        /// Healer: a strike, a team heal with a cleanse, immunity and the
        /// element's blessing with a bar push; heals the weakest each turn.
        case healer
        /// Support and control: a strike, a line-wide control, a team surge
        /// of attack and focus with a bar push; the team starts ahead.
        case oracle
        /// Debuffer: a strike, a strip with a bar knock, a line-wide break;
        /// a kill is another turn.
        case trickster
    }

    /// One family's row.
    struct FamilyRow {
        var key: String
        var name: String
        var pantheon: Pantheon
        var stars: Int
        var archetype: Archetype
        var role: CombatRole
        var kit: Kit
        var hp: Double
        var atk: Double
        var def: Double
        var spd: Double
        var height: Float
        var melee: Bool
        var costumeHue: Float
        /// The word after "of the": the family's motif, coloured per element.
        var motif: String
        /// Skill names: 0 basic, 1 second, 2 third (ignored for 3★), 3 passive.
        var skills: [String]
        /// Awakened names per element; nil for a 3★, which has no awakening.
        var awakened: [String]?
        var lore: String
    }

    // MARK: - The table

    /// The table, in four pieces.
    ///
    /// One array literal of sixty-eight rows, each with eighteen labelled
    /// arguments, is the kind of expression Swift's type checker charges by
    /// the minute for. Four smaller literals concatenated cost nothing and
    /// read better; `familyRows` is what the rest of the code uses.
    static let familyRows: [FamilyRow] =
        familyRowsEgypt + familyRowsGreece + familyRowsNorse + familyRowsBatchThree

    static let familyRowsEgypt: [FamilyRow] = [
        // ---- Egypt
        FamilyRow(key: "horus", name: "Horus", pantheon: .egyptian, stars: 5, archetype: .god, role: .attacker, kit: .duelist,
                  hp: 430, atk: 39, def: 24, spd: 108, height: 2.10, melee: true, costumeHue: 45, motif: "Sky",
                  skills: ["Falcon Strike", "Eye of Horus", "Wings of the Sun", "Sight of the Falcon"],
                  awakened: ["Horus of the Burning Dawn", "Horus of the Flood", "Horus Sky-Rider", "Horus, Lord of the Two Lands", "Horus of the Dark Moon"],
                  lore: "The falcon who took the throne back from his uncle and lost an eye doing it. Every pharaoh since has claimed to be him, and the eye is the amulet on every mummy's chest."),
        FamilyRow(key: "isis", name: "Isis", pantheon: .egyptian, stars: 5, archetype: .god, role: .support, kit: .healer,
                  hp: 540, atk: 25, def: 31, spd: 106, height: 2.00, melee: false, costumeHue: 45, motif: "Throne",
                  skills: ["Ankh's Touch", "Knot of Isis", "Breath of Life", "Great of Magic"],
                  awakened: ["Isis of the Kiln", "Isis of the Inundation", "Isis of the Wind-Wings", "Isis, Great of Magic", "Isis of the Hidden Name"],
                  lore: "She gathered the pieces of her murdered husband, breathed him back, and raised their son to take his throne. The greatest magician among the gods: she learned Ra's secret name by making him tell her."),
        FamilyRow(key: "set", name: "Set", pantheon: .egyptian, stars: 4, archetype: .god, role: .attacker, kit: .trickster,
                  hp: 470, atk: 33, def: 23, spd: 110, height: 2.20, melee: true, costumeHue: 15, motif: "Storm",
                  skills: ["Desert Claw", "Red Wind", "Chaos Unbound", "Lord of the Red Land"],
                  awakened: ["Set of the Sandstorm", "Set of the Drowning", "Set of the Red Wind", "Set the Sun-Guard", "Set of the Black Night"],
                  lore: "The god of the desert, the storm and disorder, who killed his brother and fought his nephew for eighty years. Also the one who stands at the prow of Ra's boat every night and spears the serpent."),
        FamilyRow(key: "bastet", name: "Bastet", pantheon: .egyptian, stars: 4, archetype: .god, role: .attacker, kit: .striker,
                  hp: 455, atk: 34, def: 22, spd: 114, height: 1.95, melee: true, costumeHue: 45, motif: "Hearth",
                  skills: ["Twin Sickles", "Cat's Pounce", "Night Hunt", "Nine Lives"],
                  awakened: ["Bastet of the Warm Hearth", "Bastet of the Delta", "Bastet of the Quick Wind", "Bastet, Eye of Ra", "Bastet of the Night Hunt"],
                  lore: "Once a lioness of war like her sister Sekhmet, she softened into the cat of the home, the guardian of women and children and the reason a cat's death was mourned like a person's."),
        FamilyRow(key: "sobek", name: "Sobek", pantheon: .egyptian, stars: 4, archetype: .god, role: .defender, kit: .bruiser,
                  hp: 600, atk: 25, def: 31, spd: 96, height: 2.30, melee: true, costumeHue: 45, motif: "River",
                  skills: ["Jaw Snap", "River's Roar", "Death Roll", "Lord of the Waters"],
                  awakened: ["Sobek of the Scalding Shallows", "Sobek of the Deep Nile", "Sobek of the Reed Wind", "Sobek of the Bright Bank", "Sobek of the Black Water"],
                  lore: "The crocodile god of the Nile, feared and fed. Where the river was kind he was the protector of the pharaoh; where it took people he was that too."),
        FamilyRow(key: "hathor", name: "Hathor", pantheon: .egyptian, stars: 4, archetype: .god, role: .support, kit: .oracle,
                  hp: 510, atk: 24, def: 29, spd: 108, height: 2.00, melee: false, costumeHue: 45, motif: "Dance",
                  skills: ["Sistrum Shake", "Song of the Sycamore", "Golden Revel", "Mistress of Joy"],
                  awakened: ["Hathor of the Bright Fire", "Hathor of the Flood Dance", "Hathor of the Wind Song", "Hathor, Lady of Gold", "Hathor of the Evening"],
                  lore: "Music, wine, love and the dance; the cow whose horns hold the sun. The kindest of the gods, and the one Ra sent out when he wanted humanity punished, which did not end kindly."),
        FamilyRow(key: "scarab_knight", name: "Scarab Knight", pantheon: .egyptian, stars: 3, archetype: .spirit, role: .defender, kit: .warden,
                  hp: 350, atk: 21, def: 27, spd: 95, height: 1.90, melee: true, costumeHue: 190, motif: "Tomb",
                  skills: ["Shell Bash", "Carapace Wall", "", ""],
                  awakened: nil,
                  lore: "A tomb guard sealed in with its master, its armour cast in the shape of the beetle that rolls the sun. It has not noticed the centuries."),
        FamilyRow(key: "mummy", name: "Mummy", pantheon: .egyptian, stars: 3, archetype: .spirit, role: .attacker, kit: .trickster,
                  hp: 320, atk: 23, def: 21, spd: 92, height: 1.90, melee: true, costumeHue: 45, motif: "Wrappings",
                  skills: ["Grasping Bandage", "Curse of the Tomb", "", ""],
                  awakened: nil,
                  lore: "Wrapped, sealed and forgotten; woken by a summoner who did not read the warning on the door."),
        FamilyRow(key: "jackal_warrior", name: "Jackal Warrior", pantheon: .egyptian, stars: 3, archetype: .hero, role: .attacker, kit: .striker,
                  hp: 300, atk: 26, def: 19, spd: 104, height: 1.90, melee: true, costumeHue: 45, motif: "Necropolis",
                  skills: ["Jackal Cut", "Duat Lunge", "", ""],
                  awakened: nil,
                  lore: "A soldier of Anubis's necropolis guard, masked as his master. Where the dead are, he stands."),
    ]

    static let familyRowsGreece: [FamilyRow] = [
        // ---- Greece
        FamilyRow(key: "athena", name: "Athena", pantheon: .greek, stars: 5, archetype: .god, role: .defender, kit: .warden,
                  hp: 560, atk: 30, def: 34, spd: 104, height: 2.05, melee: true, costumeHue: 35, motif: "Aegis",
                  skills: ["Spear of Wisdom", "Aegis Wall", "Gorgon Shield", "Grey-Eyed"],
                  awakened: ["Athena Promachos", "Athena of the Harbour", "Athena of the Owl's Wing", "Athena Parthenos", "Athena Nyx"],
                  lore: "Born in armour from her father's head. Wisdom, weaving, the olive and the war that is planned rather than raged; the city that took her name never lost a fight it should have won."),
        FamilyRow(key: "poseidon", name: "Poseidon", pantheon: .greek, stars: 5, archetype: .god, role: .defender, kit: .bruiser,
                  hp: 580, atk: 31, def: 30, spd: 100, height: 2.15, melee: true, costumeHue: 35, motif: "Deep",
                  skills: ["Trident Thrust", "Tidal Roar", "Earthshaker", "Lord of the Deep"],
                  awakened: ["Poseidon of the Boiling Sea", "Poseidon of the Abyss", "Poseidon Storm-Bringer", "Poseidon of the Bright Shallows", "Poseidon of the Drowned"],
                  lore: "The sea fell to him by lot when the brothers divided the world. Horses, earthquakes and storms are his too, and he holds grudges longer than his brother holds thunder."),
        FamilyRow(key: "hades", name: "Hades", pantheon: .greek, stars: 5, archetype: .god, role: .support, kit: .trickster,
                  hp: 500, atk: 34, def: 28, spd: 103, height: 2.10, melee: false, costumeHue: 45, motif: "Underworld",
                  skills: ["Bident", "Helm of Darkness", "Gates of Erebus", "The Unseen One"],
                  awakened: ["Hades of the Pyre", "Hades of the Styx", "Hades of the Cold Wind", "Hades Plouton", "Hades the Unseen"],
                  lore: "The eldest brother, who drew the underworld and kept it in order for ten thousand years. Not evil, whatever the living say; only exact, and never short of tenants."),
        FamilyRow(key: "apollo", name: "Apollo", pantheon: .greek, stars: 4, archetype: .god, role: .support, kit: .healer,
                  hp: 490, atk: 28, def: 27, spd: 110, height: 2.00, melee: false, costumeHue: 45, motif: "Sun",
                  skills: ["Sunbolt", "Paean", "Hymn of Delos", "Far-Shooter"],
                  awakened: ["Apollo of the Noon Fire", "Apollo of the Delian Spring", "Apollo of the Laurel Wind", "Apollo Phoebus", "Apollo of the Plague Night"],
                  lore: "Music, prophecy, healing and the plague, the bow and the lyre; the most Greek of the gods, and the one who never quite got the girl."),
        FamilyRow(key: "artemis", name: "Artemis", pantheon: .greek, stars: 4, archetype: .god, role: .attacker, kit: .marksman,
                  hp: 450, atk: 33, def: 22, spd: 115, height: 1.95, melee: false, costumeHue: 120, motif: "Hunt",
                  skills: ["Silver Arrow", "Hunter's Volley", "Rain of the Moon", "Mistress of Animals"],
                  awakened: ["Artemis of the Torch", "Artemis of the Lake", "Artemis of the Hills", "Artemis Phosphoros", "Artemis of the Dark Wood"],
                  lore: "Apollo's twin, born first and midwife to her brother. The hunt, the wild, the moon and the girls who would rather not marry; she turns the men who watch her bathe into stags."),
        FamilyRow(key: "hermes", name: "Hermes", pantheon: .greek, stars: 4, archetype: .god, role: .support, kit: .oracle,
                  hp: 470, atk: 29, def: 25, spd: 122, height: 1.95, melee: false, costumeHue: 45, motif: "Road",
                  skills: ["Caduceus", "Winged Word", "Herald's Call", "Swift-Foot"],
                  awakened: ["Hermes of the Hearth-Road", "Hermes of the Ford", "Hermes Argeiphontes", "Hermes of the Bright Road", "Hermes Psychopompos"],
                  lore: "Born at dawn, stole Apollo's cattle by noon, invented the lyre to pay for them by dusk. Messenger, thief, guide of the dead, patron of everyone who travels and everyone who lies."),
        FamilyRow(key: "minotaur", name: "Minotaur", pantheon: .greek, stars: 3, archetype: .monster, role: .defender, kit: .bruiser,
                  hp: 380, atk: 25, def: 24, spd: 90, height: 2.40, melee: true, costumeHue: 20, motif: "Labyrinth",
                  skills: ["Horn Toss", "Bull Rush", "", ""],
                  awakened: nil,
                  lore: "The bull-man of Crete, fed on tribute in a maze built to hold him. Theseus killed one; there were more."),
        FamilyRow(key: "cyclops", name: "Cyclops", pantheon: .greek, stars: 3, archetype: .monster, role: .attacker, kit: .striker,
                  hp: 360, atk: 28, def: 20, spd: 88, height: 2.60, melee: true, costumeHue: 30, motif: "Forge",
                  skills: ["Club Smash", "Boulder Heave", "", ""],
                  awakened: nil,
                  lore: "One eye, one thought at a time, and the strength to forge thunderbolts or eat sailors, depending on the cyclops."),
        FamilyRow(key: "amazon", name: "Amazon", pantheon: .greek, stars: 3, archetype: .hero, role: .attacker, kit: .duelist,
                  hp: 310, atk: 26, def: 20, spd: 106, height: 1.90, melee: true, costumeHue: 35, motif: "Steppe",
                  skills: ["Labrys Cut", "Crescent Guard", "", ""],
                  awakened: nil,
                  lore: "Daughters of Ares who fought from horseback and needed no husbands. Heracles took a belt from their queen; it cost him more than the belt."),
        FamilyRow(key: "medusa", name: "Medusa", pantheon: .greek, stars: 3, archetype: .monster, role: .support, kit: .oracle,
                  hp: 320, atk: 24, def: 21, spd: 100, height: 1.95, melee: false, costumeHue: 45, motif: "Gaze",
                  skills: ["Serpent Lash", "Petrifying Gaze", "", ""],
                  awakened: nil,
                  lore: "A priestess cursed with snakes for hair and a stare that turns flesh to stone. The hero who took her head still used it afterwards."),
    ]

    static let familyRowsNorse: [FamilyRow] = [
        // ---- Norse
        FamilyRow(key: "odin", name: "Odin", pantheon: .norse, stars: 5, archetype: .god, role: .support, kit: .oracle,
                  hp: 520, atk: 33, def: 28, spd: 108, height: 2.10, melee: false, costumeHue: 45, motif: "Ravens",
                  skills: ["Gungnir", "Word of the Runes", "Wild Hunt", "All-Father"],
                  awakened: ["Odin of the Pyre", "Odin of the Well", "Odin Wind-Rider", "Odin Grimnir", "Odin of the Hanged"],
                  lore: "He hung nine nights on the world tree and gave an eye at the well for wisdom. Ravens bring him the world each morning; wolves eat from his hand; he is waiting for the end and arming for it."),
        FamilyRow(key: "thor", name: "Thor", pantheon: .norse, stars: 5, archetype: .god, role: .attacker, kit: .striker,
                  hp: 470, atk: 41, def: 26, spd: 100, height: 2.20, melee: true, costumeHue: 45, motif: "Hammer",
                  skills: ["Mjölnir", "Thunder Crack", "Giant-Slayer", "Son of Earth"],
                  awakened: ["Thor of the Forge-Fire", "Thor of the Midgard Sea", "Thor Storm-Rider", "Thor Vingthor", "Thor of the Last Night"],
                  lore: "Red-bearded, short-tempered, the giants' worst problem and the farmers' favourite god. The hammer always comes back. So does he."),
        FamilyRow(key: "freya", name: "Freya", pantheon: .norse, stars: 5, archetype: .god, role: .support, kit: .healer,
                  hp: 530, atk: 27, def: 30, spd: 107, height: 2.00, melee: false, costumeHue: 45, motif: "Falcon Cloak",
                  skills: ["Brísingamen", "Tears of Gold", "Fólkvangr", "Lady of the Slain"],
                  awakened: ["Freya of the Hearth-Fire", "Freya of the Amber Sea", "Freya Falcon-Winged", "Freya Vanadís", "Freya of the Long Night"],
                  lore: "Love and war both; she takes half the battle-dead to her hall before Odin gets his pick. She wept amber for a missing husband and taught the gods magic they were embarrassed to learn."),
        FamilyRow(key: "loki", name: "Loki", pantheon: .norse, stars: 5, archetype: .god, role: .attacker, kit: .trickster,
                  hp: 445, atk: 37, def: 23, spd: 112, height: 2.00, melee: true, costumeHue: 120, motif: "Lie",
                  skills: ["Sly Knife", "Shape-Shift", "Bound Serpent", "Sky-Treader"],
                  awakened: ["Loki Flame-Tongue", "Loki of the Salmon Leap", "Loki of the Wind-Shoes", "Loki Bright-Lie", "Loki of the Bound Venom"],
                  lore: "Blood-brother to Odin, father of the wolf and the world-serpent, the one who cut Sif's hair and won it back in gold. Every gift the gods own came from a trick of his, and so will their end."),
        FamilyRow(key: "tyr", name: "Tyr", pantheon: .norse, stars: 4, archetype: .god, role: .defender, kit: .bruiser,
                  hp: 570, atk: 26, def: 32, spd: 97, height: 2.05, melee: true, costumeHue: 210, motif: "Oath",
                  skills: ["Sword-Hand", "Wolf's Bargain", "Thing-Keeper", "One-Handed"],
                  awakened: ["Tyr of the Burning Oath", "Tyr of the Ford", "Tyr of the High Wind", "Tyr Sky-Bright", "Tyr of the Dark Court"],
                  lore: "He put his hand in the wolf's mouth so the gods could bind it, and lost the hand when they did. Justice and the oath; the god you swear by when you mean it."),
        FamilyRow(key: "heimdall", name: "Heimdall", pantheon: .norse, stars: 4, archetype: .god, role: .defender, kit: .warden,
                  hp: 540, atk: 27, def: 33, spd: 102, height: 2.10, melee: true, costumeHue: 45, motif: "Bridge",
                  skills: ["Rainbow Blade", "Bifrost Ward", "Gjallarhorn", "Nine Mothers"],
                  awakened: ["Heimdall of the Bright Fire", "Heimdall of the Nine Waves", "Heimdall Wind-Hearer", "Heimdall Gold-Tooth", "Heimdall of the Long Watch"],
                  lore: "He hears grass grow and sees a hundred leagues by night. He stands at the bridge's end with the horn that will sound once, and everyone knows what it means."),
        FamilyRow(key: "hel", name: "Hel", pantheon: .norse, stars: 4, archetype: .god, role: .support, kit: .trickster,
                  hp: 500, atk: 31, def: 27, spd: 101, height: 2.00, melee: false, costumeHue: 200, motif: "Half-Dead",
                  skills: ["Cold Touch", "Corpse-Gate", "Nágrindr", "Half of Her"],
                  awakened: ["Hel of the Grave-Fire", "Hel of the Frozen River", "Hel of the Grey Wind", "Hel of the Pale Dawn", "Hel of the Sunless Hall"],
                  lore: "Loki's daughter, half a living woman and half a corpse, given the dead who did not die fighting. Her hall is called Sleet-Cold and her plate is Hunger; she keeps what she is given."),
        FamilyRow(key: "skadi", name: "Skadi", pantheon: .norse, stars: 4, archetype: .god, role: .attacker, kit: .marksman,
                  hp: 460, atk: 32, def: 24, spd: 112, height: 2.05, melee: false, costumeHue: 200, motif: "Snowfield",
                  skills: ["Ice Arrow", "Skater's Volley", "Avalanche", "Ski-Goddess"],
                  awakened: ["Skadi of the Hearth-Snow", "Skadi of the Fjord", "Skadi Blizzard-Born", "Skadi of the Bright Snow", "Skadi of the Winter Night"],
                  lore: "A giant's daughter who came armed to Asgard for her father's blood-price and left with a husband chosen by his feet. She hunts on skis and will not live by the sea."),
        FamilyRow(key: "valkyrie", name: "Valkyrie", pantheon: .norse, stars: 3, archetype: .spirit, role: .attacker, kit: .duelist,
                  hp: 310, atk: 26, def: 21, spd: 108, height: 1.95, melee: true, costumeHue: 210, motif: "Chooser",
                  skills: ["Spear Thrust", "Chooser's Cut", "", ""],
                  awakened: nil,
                  lore: "One of Odin's choosers of the slain, who rides over the field and decides who goes to the hall."),
        FamilyRow(key: "draugr", name: "Draugr", pantheon: .norse, stars: 3, archetype: .spirit, role: .defender, kit: .warden,
                  hp: 360, atk: 22, def: 26, spd: 88, height: 1.95, melee: true, costumeHue: 200, motif: "Barrow",
                  skills: ["Grave Axe", "Barrow Shield", "", ""],
                  awakened: nil,
                  lore: "A dead warrior who did not stay in his mound. Heavier than a living man, meaner, and hard to kill twice."),
        FamilyRow(key: "berserker", name: "Berserker", pantheon: .norse, stars: 3, archetype: .hero, role: .attacker, kit: .striker,
                  hp: 320, atk: 28, def: 17, spd: 103, height: 2.00, melee: true, costumeHue: 20, motif: "Bear-Shirt",
                  skills: ["Twin Axes", "Bear Rage", "", ""],
                  awakened: nil,
                  lore: "He bites his shield before a fight and feels no wound during it. The pelt is the point: he is not entirely a man while he wears it."),
        FamilyRow(key: "frost_troll", name: "Frost Troll", pantheon: .norse, stars: 3, archetype: .monster, role: .defender, kit: .bruiser,
                  hp: 400, atk: 24, def: 25, spd: 85, height: 2.50, melee: true, costumeHue: 200, motif: "Glacier",
                  skills: ["Ice Club", "Glacier Roar", "", ""],
                  awakened: nil,
                  lore: "Sunlight turns it to stone, which is the only argument it listens to."),
        FamilyRow(key: "dwarf_smith", name: "Dwarf Smith", pantheon: .norse, stars: 3, archetype: .hero, role: .support, kit: .oracle,
                  hp: 330, atk: 21, def: 24, spd: 94, height: 1.40, melee: true, costumeHue: 20, motif: "Forge",
                  skills: ["Hammer Blow", "Forge Blessing", "", ""],
                  awakened: nil,
                  lore: "One of the sons of Ivaldi, who made Odin's spear, Thor's hammer and Freya's necklace and were paid in tricks."),
    ]

    /// Batch 3: thirty-six more families, Egypt 12, Greece 10, Norse 14.
    static let familyRowsBatchThree: [FamilyRow] = [
        // ---- Batch 3: thirty-six more, Egypt 12, Greece 10, Norse 14.
        // Every one of these is an original design described, never a named
        // likeness (a named god once came back from the painter as an actor's
        // photo). The concepts are tools/batch/concepts_batch3.sh, the cards
        // portraits_batch3.sh, the meshes tools/batch/wave3.txt.

        // ---- Egypt, batch 3
        FamilyRow(key: "ra", name: "Ra", pantheon: .egyptian, stars: 5, archetype: .god, role: .attacker, kit: .marksman,
                  hp: 450, atk: 38, def: 25, spd: 104, height: 2.15, melee: false, costumeHue: 45, motif: "Sun",
                  skills: ["Sun Spear", "Solar Barque", "Noon Fire", "Eye of Ra"],
                  awakened: ["Ra of the Burning Noon", "Ra of the Western Waters", "Ra of the Sky-Barque", "Ra, the Aten Risen", "Ra of the Twelfth Hour"],
                  lore: "The sun himself, who sails the sky by day and the underworld by night, and was old enough that Isis tricked his secret name out of him with a snake."),
        FamilyRow(key: "osiris", name: "Osiris", pantheon: .egyptian, stars: 5, archetype: .god, role: .support, kit: .healer,
                  hp: 560, atk: 26, def: 32, spd: 102, height: 2.10, melee: false, costumeHue: 45, motif: "Reeds",
                  skills: ["Crook and Flail", "Rising Waters", "Field of Reeds", "Lord of the Silent"],
                  awakened: ["Osiris of the Ember Reeds", "Osiris of the Inundation", "Osiris of the West Wind", "Osiris Wennefer", "Osiris of the Long Night"],
                  lore: "Killed by his brother, boxed, drowned, cut in fourteen pieces and put back together by his wife; he became king of the dead, and every Egyptian hoped to become him."),
        FamilyRow(key: "ptah", name: "Ptah", pantheon: .egyptian, stars: 4, archetype: .god, role: .support, kit: .oracle,
                  hp: 500, atk: 26, def: 30, spd: 104, height: 2.05, melee: false, costumeHue: 200, motif: "Forge",
                  skills: ["Maker's Word", "Opening of the Mouth", "Hammer of Memphis", "Who Made All Things"],
                  awakened: ["Ptah of the Kiln", "Ptah of the Nile Clay", "Ptah of the Bellows", "Ptah, Lord of Truth", "Ptah of the Dark Workshop"],
                  lore: "The craftsman god of Memphis, who thought the world and then spoke it; sculptors and architects prayed to him, and the Greeks named the whole country after his temple."),
        FamilyRow(key: "khnum", name: "Khnum", pantheon: .egyptian, stars: 4, archetype: .god, role: .defender, kit: .warden,
                  hp: 580, atk: 25, def: 33, spd: 96, height: 2.20, melee: true, costumeHue: 45, motif: "Wheel",
                  skills: ["Ram's Charge", "Potter's Wheel", "Source of the Nile", "Shaper of Bodies"],
                  awakened: ["Khnum of the Kiln Fire", "Khnum of the Cataract", "Khnum of the High Desert", "Khnum of the First Light", "Khnum of the Cavern"],
                  lore: "The ram-headed god who shaped every child on a potter's wheel and guarded the caves the Nile was thought to rise from."),
        FamilyRow(key: "nephthys", name: "Nephthys", pantheon: .egyptian, stars: 4, archetype: .god, role: .support, kit: .trickster,
                  hp: 480, atk: 32, def: 24, spd: 110, height: 2.00, melee: false, costumeHue: 45, motif: "Twilight",
                  skills: ["Mourner's Wail", "Veil of the House", "Kite's Cry", "Sister of the Dead"],
                  awakened: ["Nephthys of the Pyre", "Nephthys of the Salt Marsh", "Nephthys of the Night Wind", "Nephthys of the Last Light", "Nephthys of the Hidden House"],
                  lore: "Set's wife and Isis's sister, who chose her sister's side, mourned Osiris as a kite and nursed the child Horus in secret."),
        FamilyRow(key: "maat", name: "Ma'at", pantheon: .egyptian, stars: 4, archetype: .god, role: .support, kit: .healer,
                  hp: 520, atk: 24, def: 30, spd: 108, height: 1.95, melee: false, costumeHue: 45, motif: "Feather",
                  skills: ["Feather Touch", "Weighing of Hearts", "Order Restored", "Truth Upheld"],
                  awakened: ["Ma'at of the Lamp", "Ma'at of the Still Water", "Ma'at of the Feather", "Ma'at of the Clear Sky", "Ma'at of the Silent Hall"],
                  lore: "Truth, balance and the right order of things, wearing one ostrich feather; every heart was weighed against it, and the ones that were heavier were eaten."),
        FamilyRow(key: "serqet", name: "Serqet", pantheon: .egyptian, stars: 4, archetype: .god, role: .attacker, kit: .trickster,
                  hp: 460, atk: 34, def: 23, spd: 112, height: 1.95, melee: true, costumeHue: 45, motif: "Sting",
                  skills: ["Scorpion Sting", "Seven Scorpions", "Venom of the Sands", "She Who Lets Breathe"],
                  awakened: ["Serqet of the Burning Sand", "Serqet of the Delta", "Serqet of the Dust Storm", "Serqet of the Noon Glare", "Serqet of the Tomb"],
                  lore: "The scorpion goddess who could kill with a sting or draw the venom back out; seven scorpions walked with Isis under her orders."),
        FamilyRow(key: "taweret", name: "Taweret", pantheon: .egyptian, stars: 4, archetype: .god, role: .defender, kit: .bruiser,
                  hp: 640, atk: 24, def: 30, spd: 92, height: 2.30, melee: true, costumeHue: 45, motif: "River",
                  skills: ["Hippo Charge", "Bellow of the Reeds", "Great One's Bulk", "Guardian of the Cradle"],
                  awakened: ["Taweret of the Hot Shallows", "Taweret of the Deep Nile", "Taweret of the Reed Wind", "Taweret of the Bright Bank", "Taweret of the Night River"],
                  lore: "A pregnant hippopotamus standing on her hind legs with a crocodile's back and a lion's paws, fierce to everything except mothers and children."),
        FamilyRow(key: "anhur", name: "Anhur", pantheon: .egyptian, stars: 4, archetype: .god, role: .attacker, kit: .duelist,
                  hp: 450, atk: 36, def: 23, spd: 110, height: 2.10, melee: true, costumeHue: 45, motif: "Spear",
                  skills: ["Sky Spear", "Bringer Back", "Lion Hunt", "He Who Leads Back"],
                  awakened: ["Anhur of the Red Land", "Anhur of the Cataract", "Anhur of the Hunting Wind", "Anhur of the High Sun", "Anhur of the Far Desert"],
                  lore: "The hunter-warrior of Thinis who went south to fetch the Sun's angry daughter home; soldiers wore his four plumes and mock-fought in his name."),
        FamilyRow(key: "bes", name: "Bes", pantheon: .egyptian, stars: 3, archetype: .spirit, role: .support, kit: .oracle,
                  hp: 340, atk: 22, def: 24, spd: 100, height: 1.40, melee: true, costumeHue: 45, motif: "Drum",
                  skills: ["Tambourine Slap", "Dance of the Household", "", ""],
                  awakened: nil,
                  lore: "A bandy-legged dwarf with a lion's mane and his tongue out, who danced, drummed and made faces to scare demons off the house and away from the childbed."),
        FamilyRow(key: "medjay", name: "Medjay", pantheon: .egyptian, stars: 3, archetype: .hero, role: .attacker, kit: .marksman,
                  hp: 300, atk: 26, def: 19, spd: 106, height: 1.90, melee: false, costumeHue: 20, motif: "Road",
                  skills: ["Desert Arrow", "Patrol Volley", "", ""],
                  awakened: nil,
                  lore: "Nubian scouts who policed the desert roads and the tombs for the pharaoh; the name outlived the people and came to mean any guard worth hiring."),
        FamilyRow(key: "cobra_priestess", name: "Cobra Priestess", pantheon: .egyptian, stars: 3, archetype: .hero, role: .support, kit: .healer,
                  hp: 330, atk: 21, def: 23, spd: 100, height: 1.90, melee: false, costumeHue: 45, motif: "Cobra",
                  skills: ["Cobra Hiss", "Uraeus Blessing", "", ""],
                  awakened: nil,
                  lore: "A priestess of the cobra goddess who wore the uraeus, spat the venom of her patron's wrath, and mended what it bit."),

        // ---- Greece, batch 3
        FamilyRow(key: "hera", name: "Hera", pantheon: .greek, stars: 5, archetype: .god, role: .support, kit: .oracle,
                  hp: 530, atk: 32, def: 29, spd: 108, height: 2.10, melee: false, costumeHue: 45, motif: "Peacock",
                  skills: ["Sceptre of Argos", "Hundred Eyes", "Queen's Decree", "Wrath of the Wife"],
                  awakened: ["Hera of the Hearth Fire", "Hera of the Argive Shore", "Hera of the Mountain Air", "Hera in Gold", "Hera of the Jealous Night"],
                  lore: "Queen of the gods and keeper of marriage, whose husband gave her endless reasons for vengeance and whose hundred-eyed watchman ended up on a peacock's tail."),
        FamilyRow(key: "hephaestus", name: "Hephaestus", pantheon: .greek, stars: 4, archetype: .god, role: .defender, kit: .warden,
                  hp: 590, atk: 28, def: 34, spd: 94, height: 2.05, melee: true, costumeHue: 20, motif: "Anvil",
                  skills: ["Hammer Blow", "Bronze Bulwark", "Net of Chains", "Forge-Born"],
                  awakened: ["Hephaestus of the Furnace", "Hephaestus of the Cooling Trough", "Hephaestus of the Bellows Wind", "Hephaestus of the Bright Bronze", "Hephaestus of the Deep Forge"],
                  lore: "Thrown off Olympus as a baby and lame ever after, he built the gods' palaces, Achilles' shield and the net that caught his wife with Ares."),
        FamilyRow(key: "demeter", name: "Demeter", pantheon: .greek, stars: 4, archetype: .god, role: .support, kit: .healer,
                  hp: 540, atk: 24, def: 30, spd: 104, height: 2.00, melee: false, costumeHue: 45, motif: "Harvest",
                  skills: ["Sickle Sweep", "Bread of the Earth", "Harvest Blessing", "Mother of Grain"],
                  awakened: ["Demeter of the Hearth Bread", "Demeter of the Spring Rain", "Demeter of the Threshing Wind", "Demeter of the Golden Field", "Demeter of the Fallow Winter"],
                  lore: "Goddess of grain, who searched the world for her stolen daughter and let nothing grow until she was found; winter is the four months she is gone."),
        FamilyRow(key: "dionysus", name: "Dionysus", pantheon: .greek, stars: 4, archetype: .god, role: .support, kit: .trickster,
                  hp: 470, atk: 32, def: 24, spd: 110, height: 2.00, melee: false, costumeHue: 45, motif: "Vine",
                  skills: ["Thyrsus Strike", "Wine-Dark Madness", "Revel", "God of the Vine"],
                  awakened: ["Dionysus of the Torchlit Revel", "Dionysus of the Sea Voyage", "Dionysus of the Mountain Dance", "Dionysus Crowned in Ivy", "Dionysus of the Midnight Rite"],
                  lore: "Twice born, of a mortal mother and then his father's thigh; god of wine, theatre and losing your mind, who turned pirates into dolphins for kidnapping him."),
        FamilyRow(key: "aphrodite", name: "Aphrodite", pantheon: .greek, stars: 4, archetype: .god, role: .support, kit: .oracle,
                  hp: 500, atk: 26, def: 27, spd: 112, height: 1.95, melee: false, costumeHue: 45, motif: "Foam",
                  skills: ["Golden Kiss", "Charm", "Girdle of Desire", "Born of the Foam"],
                  awakened: ["Aphrodite of the Rose Fire", "Aphrodite of the Foam", "Aphrodite of the Warm Wind", "Aphrodite in Golden Light", "Aphrodite of the Hidden Night"],
                  lore: "Born from sea foam, married to the smith and loved by the war god; her golden belt made anyone irresistible, and her promise of the most beautiful woman started the Trojan War."),
        FamilyRow(key: "nike", name: "Nike", pantheon: .greek, stars: 4, archetype: .god, role: .attacker, kit: .duelist,
                  hp: 440, atk: 36, def: 22, spd: 116, height: 1.95, melee: true, costumeHue: 45, motif: "Wreath",
                  skills: ["Winged Cut", "Laurel Strike", "Victory Lap", "Never Beaten"],
                  awakened: ["Nike of the Burning Race", "Nike of the Naval Victory", "Nike of the Swift Wind", "Nike in Gold", "Nike of the Night Battle"],
                  lore: "Victory herself, winged and never still; she rode Zeus's chariot in the war against the Titans and has stood on trophies ever since."),
        FamilyRow(key: "achilles", name: "Achilles", pantheon: .greek, stars: 4, archetype: .demigod, role: .attacker, kit: .striker,
                  hp: 460, atk: 36, def: 24, spd: 108, height: 2.05, melee: true, costumeHue: 35, motif: "Bronze",
                  skills: ["Pelian Spear", "Wrath", "Shield of Hephaestus", "Dipped in the Styx"],
                  awakened: ["Achilles of the Burning Ships", "Achilles of the River Fight", "Achilles Swift-Footed", "Achilles in Bright Bronze", "Achilles of the Black Ships"],
                  lore: "Dipped in the Styx by the heel his mother held, the best of the Greeks at Troy; he sulked in his tent, killed Hector for Patroclus, and died of an arrow in the one place she had missed."),
        FamilyRow(key: "atalanta", name: "Atalanta", pantheon: .greek, stars: 3, archetype: .hero, role: .attacker, kit: .marksman,
                  hp: 300, atk: 26, def: 19, spd: 110, height: 1.90, melee: false, costumeHue: 120, motif: "Chase",
                  skills: ["Huntress' Arrow", "Golden Apples", "", ""],
                  awakened: nil,
                  lore: "Left on a hillside and raised by a bear, she outran every suitor until one dropped golden apples; she drew first blood on the Calydonian boar."),
        FamilyRow(key: "siren", name: "Siren", pantheon: .greek, stars: 3, archetype: .monster, role: .support, kit: .oracle,
                  hp: 320, atk: 24, def: 21, spd: 104, height: 1.90, melee: false, costumeHue: 190, motif: "Song",
                  skills: ["Luring Note", "Song of the Rocks", "", ""],
                  awakened: nil,
                  lore: "Bird-women on a rocky island who sang sailors onto the reef; Odysseus had himself tied to the mast to hear them and live."),
        FamilyRow(key: "nymph", name: "Nymph", pantheon: .greek, stars: 3, archetype: .spirit, role: .support, kit: .healer,
                  hp: 330, atk: 21, def: 23, spd: 102, height: 1.85, melee: false, costumeHue: 120, motif: "Spring",
                  skills: ["Water Splash", "Spring Blessing", "", ""],
                  awakened: nil,
                  lore: "The spirits of springs, trees and mountains, who lived as long as their tree or their stream and healed whoever drank from them."),

        // ---- Norse, batch 3
        FamilyRow(key: "baldr", name: "Baldr", pantheon: .norse, stars: 5, archetype: .god, role: .support, kit: .healer,
                  hp: 550, atk: 27, def: 30, spd: 106, height: 2.10, melee: false, costumeHue: 45, motif: "Mistletoe",
                  skills: ["Light of Breidablik", "Unharmed", "Mistletoe Ward", "Beloved of All"],
                  awakened: ["Baldr of the Bright Hearth", "Baldr of the Burning Ship", "Baldr of the Summer Wind", "Baldr the Shining", "Baldr of the Long Sleep"],
                  lore: "The bright god whom every thing in the world swore not to harm, except the mistletoe; Loki put a sprig in his blind brother's hand, and the gods' grief began the end."),
        FamilyRow(key: "frigg", name: "Frigg", pantheon: .norse, stars: 5, archetype: .god, role: .support, kit: .oracle,
                  hp: 520, atk: 31, def: 29, spd: 110, height: 2.05, melee: false, costumeHue: 45, motif: "Spindle",
                  skills: ["Spindle Cast", "Foresight", "Mother's Oath", "Queen of Asgard"],
                  awakened: ["Frigg of the Hearth", "Frigg of the Marsh Halls", "Frigg of the Falcon Cloak", "Frigg in Gold", "Frigg of the Long Night"],
                  lore: "Odin's wife, who knows every fate and tells none; she made the whole world swear to spare her son, and it was her one omission that Loki found."),
        FamilyRow(key: "surtr", name: "Surtr", pantheon: .norse, stars: 5, archetype: .titan, role: .attacker, kit: .striker,
                  hp: 500, atk: 40, def: 26, spd: 100, height: 2.60, melee: true, costumeHue: 15, motif: "Flame",
                  skills: ["Flaming Sword", "Muspell's Fire", "World-Burner", "Lord of the Fire Giants"],
                  awakened: ["Surtr of the World-Fire", "Surtr of the Boiling Sea", "Surtr of the Ash Wind", "Surtr of the Blinding Blaze", "Surtr of the Charred Dark"],
                  lore: "The fire giant who waits at the southern edge of the world with a sword brighter than the sun, and at the end of things walks north and burns it all."),
        FamilyRow(key: "njord", name: "Njord", pantheon: .norse, stars: 4, archetype: .god, role: .defender, kit: .warden,
                  hp: 570, atk: 27, def: 32, spd: 100, height: 2.10, melee: true, costumeHue: 200, motif: "Harbour",
                  skills: ["Oar Strike", "Harbour Wall", "Fair Wind", "Lord of Noatun"],
                  awakened: ["Njord of the Beacon Fire", "Njord of the Deep Harbour", "Njord of the Fair Wind", "Njord of the Bright Shallows", "Njord of the Black Water"],
                  lore: "God of the sea, the wind and the wealth of ships, a hostage of the Vanir who married a giantess and could not stand her mountains any more than she could stand his gulls."),
        FamilyRow(key: "idunn", name: "Idunn", pantheon: .norse, stars: 4, archetype: .god, role: .support, kit: .healer,
                  hp: 510, atk: 24, def: 29, spd: 108, height: 1.95, melee: false, costumeHue: 45, motif: "Orchard",
                  skills: ["Apple Toss", "Apples of Youth", "Orchard Ward", "Keeper of the Apples"],
                  awakened: ["Idunn of the Warm Orchard", "Idunn of the Spring Well", "Idunn of the Blossom Wind", "Idunn of the Golden Apples", "Idunn of the Winter Store"],
                  lore: "Keeper of the apples that keep the gods young; when Loki let a giant carry her off, every god went grey within a week."),
        FamilyRow(key: "sif", name: "Sif", pantheon: .norse, stars: 4, archetype: .god, role: .attacker, kit: .duelist,
                  hp: 450, atk: 35, def: 24, spd: 108, height: 2.00, melee: true, costumeHue: 45, motif: "Wheat",
                  skills: ["Golden Cut", "Harvest Blade", "Rowan Guard", "Hair of Gold"],
                  awakened: ["Sif of the Burning Field", "Sif of the Dew", "Sif of the Rippling Wheat", "Sif of the Golden Hair", "Sif of the Shorn Night"],
                  lore: "Thor's wife, whose golden hair Loki cut off as a prank; the dwarves forged her new hair of real gold that grew like the old, and made the hammer on the same visit."),
        FamilyRow(key: "ullr", name: "Ullr", pantheon: .norse, stars: 4, archetype: .god, role: .attacker, kit: .marksman,
                  hp: 440, atk: 35, def: 23, spd: 112, height: 2.05, melee: false, costumeHue: 200, motif: "Yew",
                  skills: ["Yew Arrow", "Snow Volley", "Ski Charge", "Lord of the Bow"],
                  awakened: ["Ullr of the Winter Fire", "Ullr of the Frozen Lake", "Ullr of the Whistling Wind", "Ullr of the Snow Glare", "Ullr of the Polar Night"],
                  lore: "God of the bow, the ski and the shield, whom the Norse swore oaths on; he crossed the sea on a shield and was so good at everything cold that they called winter his weather."),
        FamilyRow(key: "vidar", name: "Vidar", pantheon: .norse, stars: 4, archetype: .god, role: .defender, kit: .bruiser,
                  hp: 610, atk: 26, def: 32, spd: 94, height: 2.20, melee: true, costumeHue: 20, motif: "Silence",
                  skills: ["Iron Boot", "Silent Stand", "Jaw-Breaker", "The Silent One"],
                  awakened: ["Vidar of the Ember Ash", "Vidar of the Marsh", "Vidar of the Storm Wind", "Vidar of the New Dawn", "Vidar of the Wolf's Night"],
                  lore: "Odin's silent son, who wears a shoe made of every scrap of leather ever thrown away and uses it to hold the wolf's jaw open while he tears it apart."),
        FamilyRow(key: "fenrir", name: "Fenrir", pantheon: .norse, stars: 4, archetype: .monster, role: .attacker, kit: .striker,
                  hp: 480, atk: 37, def: 23, spd: 110, height: 2.30, melee: true, costumeHue: 200, motif: "Chain",
                  skills: ["Wolf Bite", "Broken Fetter", "Swallow the Sky", "Bound and Raging"],
                  awakened: ["Fenrir of the Ash Fire", "Fenrir of the Lake Island", "Fenrir of the Howling Wind", "Fenrir of the Sun-Chase", "Fenrir of the Endless Night"],
                  lore: "Loki's wolf son, raised among the gods until he grew too big; bound by a ribbon made of impossible things, with a sword in his jaws, until the day he breaks free."),
        FamilyRow(key: "bragi", name: "Bragi", pantheon: .norse, stars: 4, archetype: .god, role: .support, kit: .oracle,
                  hp: 490, atk: 27, def: 26, spd: 112, height: 2.05, melee: false, costumeHue: 45, motif: "Verse",
                  skills: ["Sharp Verse", "Runes on the Tongue", "Mead of Poetry", "First of Skalds"],
                  awakened: ["Bragi of the Fireside Tale", "Bragi of the Mead-Well", "Bragi of the Winged Word", "Bragi of the Golden Harp", "Bragi of the Night's Saga"],
                  lore: "The god of poetry, with runes carved on his tongue, who welcomes the dead heroes to the hall with a song; his wife keeps the apples that keep him young."),
        FamilyRow(key: "einherjar", name: "Einherjar", pantheon: .norse, stars: 3, archetype: .spirit, role: .defender, kit: .warden,
                  hp: 350, atk: 22, def: 27, spd: 96, height: 1.95, melee: true, costumeHue: 210, motif: "Hall",
                  skills: ["Shield Bash", "Wall of the Hall", "", ""],
                  awakened: nil,
                  lore: "The battle-dead whom the valkyries carry to Odin's hall, who fight each other all day, rise again at dusk and feast all night until the last battle."),
        FamilyRow(key: "shield_maiden", name: "Shield Maiden", pantheon: .norse, stars: 3, archetype: .hero, role: .attacker, kit: .duelist,
                  hp: 310, atk: 26, def: 21, spd: 108, height: 1.90, melee: true, costumeHue: 210, motif: "Fjord",
                  skills: ["Seax Cut", "Shield Wall Break", "", ""],
                  awakened: nil,
                  lore: "Women who took up the shield and the spear and went raiding beside the men; the sagas tell of Lagertha and Hervor, and the burials tell of many more."),
        FamilyRow(key: "light_elf", name: "Light Elf", pantheon: .norse, stars: 3, archetype: .spirit, role: .support, kit: .healer,
                  hp: 320, atk: 21, def: 22, spd: 106, height: 1.85, melee: false, costumeHue: 45, motif: "Glow",
                  skills: ["Starlight Dart", "Glow of Alfheim", "", ""],
                  awakened: nil,
                  lore: "The bright elves of Alfheim, fairer than the sun to look at, who were given to Freyr as a tooth-gift and heal what they choose to touch."),
        FamilyRow(key: "dark_elf", name: "Dark Elf", pantheon: .norse, stars: 3, archetype: .spirit, role: .attacker, kit: .trickster,
                  hp: 310, atk: 25, def: 20, spd: 110, height: 1.85, melee: true, costumeHue: 280, motif: "Pitch",
                  skills: ["Poisoned Knife", "Smith's Curse", "", ""],
                  awakened: nil,
                  lore: "The dark elves of Svartalfheim, blacker than pitch, who forge the gods' treasures and curse them as they hand them over."),
    
    ]

    /// Every variant this file adds.
    /// A `let`, not a `var`. As a computed property this rebuilt all sixty-eight
    /// families — three hundred and forty blueprints with their skills, leader
    /// skills and awakenings — on every read, and it is read by both
    /// `UnitDatabase.all` and `UnitDatabase.summonPool`.
    static let thirdRoster: [UnitBlueprint] = {
        familyRows.flatMap { row in Element.allCases.map { family(row, element: $0) } }
    }()

    /// The families by key, for the tour and the stages.
    static func family(named key: String) -> [UnitBlueprint] {
        guard let row = familyRows.first(where: { $0.key == key }) else { return [] }
        return Element.allCases.map { family(row, element: $0) }
    }

    // MARK: - The builder

    /// The adjective an element puts in front of a family's motif.
    static func elementWord(_ element: Element) -> String {
        switch element {
        case .ember: return "Burning"
        case .tide: return "Tidal"
        case .gale: return "Windswept"
        case .radiance: return "Radiant"
        case .umbra: return "Shadowed"
        }
    }

    /// Stats lean a little by element, the way the hand-written families do:
    /// fire hits harder, water lasts, wind is quick, light resists, dark
    /// trades defence for attack.
    static func lean(_ row: FamilyRow, _ element: Element) -> (hp: Double, atk: Double, def: Double, spd: Double, res: Double) {
        switch element {
        case .ember: return (row.hp, row.atk * 1.05, row.def, row.spd, 0.15)
        case .tide: return (row.hp * 1.07, row.atk * 0.95, row.def * 1.05, row.spd - 1, 0.15)
        case .gale: return (row.hp * 0.96, row.atk, row.def * 0.95, row.spd + 6, 0.15)
        case .radiance: return (row.hp * 1.02, row.atk * 0.97, row.def * 1.04, row.spd, 0.25)
        case .umbra: return (row.hp * 0.98, row.atk * 1.04, row.def * 0.94, row.spd + 1, 0.15)
        }
    }

    /// The leader skill by role and element; pantheon-scoped for the first
    /// three elements, everyone for light and dark, as the hand-written
    /// families do.
    static func leader(_ row: FamilyRow, _ element: Element) -> LeaderSkill {
        let strong = row.stars >= 5 ? 0.33 : (row.stars == 4 ? 0.25 : 0.15)
        let wide = row.stars >= 5 ? 0.24 : (row.stars == 4 ? 0.18 : 0.10)
        switch (row.role, element) {
        case (.attacker, .ember): return LeaderSkill(stat: .atkPercent, amount: strong, scope: .pantheon(row.pantheon))
        case (.attacker, .tide): return LeaderSkill(stat: .hpPercent, amount: strong, scope: .pantheon(row.pantheon))
        case (.attacker, .gale): return LeaderSkill(stat: .spd, amount: strong * 0.6, scope: .pantheon(row.pantheon))
        case (.attacker, .radiance): return LeaderSkill(stat: .critRate, amount: wide, scope: .allAllies)
        case (.attacker, .umbra): return LeaderSkill(stat: .atkPercent, amount: wide, scope: .allAllies)
        case (.defender, .ember): return LeaderSkill(stat: .hpPercent, amount: strong, scope: .pantheon(row.pantheon))
        case (.defender, .tide): return LeaderSkill(stat: .defPercent, amount: strong, scope: .pantheon(row.pantheon))
        case (.defender, .gale): return LeaderSkill(stat: .spd, amount: strong * 0.5, scope: .pantheon(row.pantheon))
        case (.defender, .radiance): return LeaderSkill(stat: .resistance, amount: wide, scope: .allAllies)
        case (.defender, .umbra): return LeaderSkill(stat: .hpPercent, amount: wide, scope: .allAllies)
        case (.support, .ember): return LeaderSkill(stat: .atkPercent, amount: strong * 0.8, scope: .pantheon(row.pantheon))
        case (.support, .tide): return LeaderSkill(stat: .hpPercent, amount: strong, scope: .pantheon(row.pantheon))
        case (.support, .gale): return LeaderSkill(stat: .spd, amount: strong * 0.6, scope: .pantheon(row.pantheon))
        case (.support, .radiance): return LeaderSkill(stat: .resistance, amount: wide, scope: .allAllies)
        case (.support, .umbra): return LeaderSkill(stat: .accuracy, amount: wide, scope: .allAllies)
        // No row is a controller or an HP tank yet; the compiler wants them
        // covered all the same.
        case (.controller, _): return LeaderSkill(stat: .accuracy, amount: wide, scope: .allAllies)
        case (.hpTank, _): return LeaderSkill(stat: .hpPercent, amount: wide, scope: .allAllies)
        }
    }

    static func family(_ row: FamilyRow, element: Element) -> UnitBlueprint {
        let id = "\(row.key)_\(element.rawValue)"
        let s = lean(row, element)
        let sig = signature(element)
        let common = row.stars <= 3
        let awakenedName = row.awakened?[Element.allCases.firstIndex(of: element) ?? 0] ?? row.name

        // The basic attack is the same for every kit: the element's signature
        // rides on it, and the passive is the kit's. The second and third
        // skills are the ELEMENT's own — `elementalSkill` shapes them by kit
        // and element and `elementalSkillNames` names them per family — so
        // the five forms of one character fight five different ways, the way
        // the genre's do. The owner: "each units different elements need to
        // have different 2nd and 3rd skills. We cant have all 5 of the
        // elements of each character have the same attacks." A family the
        // name table has not reached keeps the row's own two names.
        let strike = StatusSpec(sig, chance: common ? 0.25 : 0.30, turns: 2, target: .singleEnemy)
        let name = { (index: Int) -> String in
            index < row.skills.count && !row.skills[index].isEmpty ? row.skills[index] : "Skill \(index + 1)"
        }
        let elementIndex = Element.allCases.firstIndex(of: element) ?? 0
        let named = elementalSkillNames[row.key].flatMap { $0.count == 10 ? $0 : nil }
        let secondName = named?[elementIndex] ?? name(1)
        let thirdName = named?[5 + elementIndex] ?? name(2)

        let basic: Skill
        let awakenedPassive: Skill
        switch row.kit {
        case .striker:
            basic = Skill(id: "\(id)_s1", name: name(0),
                          description: "Strikes one enemy with a \(percent(strike.chance)) chance to inflict \(sig.displayName) for \(turns(2)).",
                          slot: 0, cooldown: 0, target: .singleEnemy, damage: DamageSpec(multiplier: 3.00), statuses: [strike],
                          levelUpBonuses: basicLadder, animation: .attackBasic, cameraShot: .standard, vfx: "lioness_rake")
            awakenedPassive = passive(id: id, name: name(3), trigger: .onKill, target: .caster,
                          description: "[Awakened] Every kill grants Attack Up for 2 turns and fills the attack bar by 25%.",
                          statuses: [StatusSpec(.attackUp, chance: 1.0, turns: 2, target: .caster)],
                          utilities: [.attackBarChange(0.25, chance: 1.0, .caster)], vfx: "blood_thirst")
        case .duelist:
            basic = Skill(id: "\(id)_s1", name: name(0),
                          description: "Two quick cuts. Each has a \(percent(strike.chance)) chance to inflict \(sig.displayName) for \(turns(2)).",
                          slot: 0, cooldown: 0, target: .singleEnemy, damage: DamageSpec(multiplier: 1.50, hits: 2), statuses: [strike],
                          levelUpBonuses: basicLadder, animation: .attackBasic, cameraShot: .standard, vfx: "scale_strike")
            awakenedPassive = passive(id: id, name: name(3), trigger: .onTurnStart, target: .caster,
                          description: "[Awakened] Gains Focus at the start of each turn.",
                          statuses: [StatusSpec(.critRateUp, chance: 1.0, turns: 1, target: .caster)], utilities: [], vfx: "buff")
        case .marksman:
            basic = Skill(id: "\(id)_s1", name: name(0),
                          description: "A shot at one enemy with a \(percent(strike.chance)) chance to inflict \(sig.displayName) for \(turns(2)).",
                          slot: 0, cooldown: 0, target: .singleEnemy, damage: DamageSpec(multiplier: 2.90), statuses: [strike],
                          levelUpBonuses: basicLadder, animation: .attackBasic, cameraShot: .standard, vfx: "thunderbolt")
            awakenedPassive = passive(id: id, name: name(3), trigger: .onBattleStart, target: .caster,
                          description: "[Awakened] When the battle begins, the attack bar fills by 30% and Haste lasts 2 turns.",
                          statuses: [StatusSpec(.speedUp, chance: 1.0, turns: 2, target: .caster)],
                          utilities: [.attackBarChange(0.30, chance: 1.0, .caster)], vfx: "buff")
        case .bruiser:
            basic = Skill(id: "\(id)_s1", name: name(0),
                          description: "Strikes one enemy with a \(percent(strike.chance)) chance to inflict \(sig.displayName) for \(turns(2)).",
                          slot: 0, cooldown: 0, target: .singleEnemy, damage: DamageSpec(multiplier: 2.80), statuses: [strike],
                          levelUpBonuses: basicLadder, animation: .attackBasic, cameraShot: .standard, vfx: "impact_generic")
            awakenedPassive = passive(id: id, name: name(3), trigger: .onLowHealth, target: .caster,
                          description: "[Awakened] The first time he falls below half health, a shield worth 30% of his maximum health and Defense Up for 2 turns.",
                          statuses: [StatusSpec(.shield, chance: 1.0, turns: 2, target: .caster, magnitude: 0.30),
                                     StatusSpec(.defenseUp, chance: 1.0, turns: 2, target: .caster)], utilities: [], vfx: "maat_shield")
        case .warden:
            basic = Skill(id: "\(id)_s1", name: name(0),
                          description: "Strikes one enemy with a \(percent(strike.chance)) chance to inflict \(sig.displayName) for \(turns(2)).",
                          slot: 0, cooldown: 0, target: .singleEnemy, damage: DamageSpec(multiplier: 2.70), statuses: [strike],
                          levelUpBonuses: basicLadder, animation: .attackBasic, cameraShot: .standard, vfx: "impact_generic")
            awakenedPassive = passive(id: id, name: name(3), trigger: .onBattleStart, target: .allAllies,
                          description: "[Awakened] When the battle begins, every ally gains a shield worth 12% of their maximum health for 2 turns.",
                          statuses: [StatusSpec(.shield, chance: 1.0, turns: 2, target: .allAllies, magnitude: 0.12)], utilities: [], vfx: "maat_shield")
        case .healer:
            basic = Skill(id: "\(id)_s1", name: name(0),
                          description: "Strikes one enemy with a \(percent(strike.chance)) chance to inflict \(sig.displayName) for \(turns(2)).",
                          slot: 0, cooldown: 0, target: .singleEnemy, damage: DamageSpec(multiplier: 2.50), statuses: [strike],
                          levelUpBonuses: basicLadder, animation: .attackBasic, cameraShot: .standard, vfx: "impact_generic")
            awakenedPassive = passive(id: id, name: name(3), trigger: .onTurnStart, target: .lowestHealthAlly,
                          description: "[Awakened] At the start of each turn, the ally with the least health is healed for 8% of their maximum health.",
                          statuses: [], utilities: [.healTargetMaxHealth(0.08, .lowestHealthAlly)], vfx: "heal")
        case .oracle:
            basic = Skill(id: "\(id)_s1", name: name(0),
                          description: "Strikes one enemy with a \(percent(strike.chance)) chance to inflict \(sig.displayName) for \(turns(2)).",
                          slot: 0, cooldown: 0, target: .singleEnemy, damage: DamageSpec(multiplier: 2.60), statuses: [strike],
                          levelUpBonuses: basicLadder, animation: .attackBasic, cameraShot: .standard, vfx: "impact_generic")
            awakenedPassive = passive(id: id, name: name(3), trigger: .onBattleStart, target: .allAllies,
                          description: "[Awakened] When the battle begins, the attack bar of every ally is raised by 20%.",
                          statuses: [], utilities: [.attackBarChange(0.20, chance: 1.0, .allAllies)], vfx: "olympian_decree")
        case .trickster:
            basic = Skill(id: "\(id)_s1", name: name(0),
                          description: "Strikes one enemy with a \(percent(min(0.45, strike.chance + 0.10))) chance to inflict \(sig.displayName) for \(turns(2)).",
                          slot: 0, cooldown: 0, target: .singleEnemy, damage: DamageSpec(multiplier: 2.80),
                          statuses: [StatusSpec(sig, chance: min(0.45, strike.chance + 0.10), turns: 2, target: .singleEnemy)],
                          levelUpBonuses: basicLadder, animation: .attackBasic, cameraShot: .standard, vfx: "debuff")
            awakenedPassive = passive(id: id, name: name(3), trigger: .onKill, target: .caster,
                          description: "[Awakened] A kill grants another turn at once.",
                          statuses: [], utilities: [.extraTurn(chance: 1.0)], vfx: "blood_thirst")
        }

        var skills: [Skill] = [basic, elementalSkill(slot: 1, kit: row.kit, element: element, id: id, name: secondName)]
        if !common {
            skills.append(elementalSkill(slot: 2, kit: row.kit, element: element, id: id, name: thirdName))
            skills.append(awakenedPassive)
        }

        let awakening: Awakening? = common ? nil : Awakening(
            awakenedName: awakenedName,
            bonusDescription: row.stars >= 5
                ? "Attack +8%, Health +8%, Resistance +10%, and the \(name(3)) passive is unlocked."
                : "Attack +6%, Health +6%, and the \(name(3)) passive is unlocked.",
            statBonus: row.stars >= 5
                ? Stats(hp: (s.hp * 0.08).rounded(), atk: (s.atk * 0.08).rounded(), resistance: 0.10)
                : Stats(hp: (s.hp * 0.06).rounded(), atk: (s.atk * 0.06).rounded()),
            skillOverrides: [:],
            essenceCost: row.stars >= 5
                ? [essence(element): 15, "essence_magic_mid": 10, "essence_magic_high": 5]
                : [essence(element): 10, "essence_magic_mid": 8, "essence_magic_high": 3]
        )

        return UnitBlueprint(
            id: id,
            name: row.name,
            epithet: "of the \(elementWord(element)) \(row.motif)",
            pantheon: row.pantheon,
            element: element,
            archetype: row.archetype,
            role: row.role,
            naturalStars: row.stars,
            baseStats: Stats(
                hp: s.hp.rounded(), atk: s.atk.rounded(), def: s.def.rounded(), spd: s.spd.rounded(),
                critRate: row.kit == .duelist ? 0.20 : 0.15, critDamage: 0.50,
                accuracy: row.kit == .trickster || row.kit == .oracle ? 0.15 : 0.0, resistance: s.res
            ),
            growthPerLevel: .zero,
            skills: skills,
            leaderSkill: leader(row, element),
            awakening: awakening,
            model: ModelSpec(
                assetName: row.key,
                height: row.height,
                weaponAttachNode: "weapon_r",
                auraHex: element.accentHex,
                portraitName: "portrait_\(id)",
                melee: row.melee,
                costumeHue: row.costumeHue
            ),
            lore: row.lore
        )
    }

    // MARK: - The elemental second and third skills

    /// The element's own second (slot 1) and third (slot 2) skill for a kit.
    ///
    /// Eight kits by five elements is forty pairs, written out below, and
    /// each pair is a different way to fight: a fire striker's two blows burn
    /// and feed on the target's debuffs, a water striker's one blow freezes,
    /// a wind striker's three cuts may earn another turn, a light striker's
    /// blow sharpens its own aim, a dark striker's drinks. The element's
    /// grammar holds across the kits — fire burns and grows, water freezes,
    /// slows and drags the bar, wind repeats and hastens, light shields,
    /// cleanses and reveals, dark drains, strips and brands — so a player who
    /// has read one fire unit can guess the next. The numbers are mirrored in
    /// `tools/balance.py` (`ELEMENT_SKILLS`); change them in both.
    static func elementalSkill(slot: Int, kit: Kit, element: Element, id: String, name: String) -> Skill {
        let third = slot == 2
        let skillID = "\(id)_s\(slot + 1)"
        let cooldownOnly = [SkillUpgrade(kind: .cooldown, amount: 1, label: "Cooldown -1")]

        /// A damaging skill: one enemy unless `target` says the line.
        func blow(_ description: String, cd: Int, _ damage: DamageSpec, statuses: [StatusSpec] = [],
                  utilities: [UtilityEffect] = [], target: TargetSelector = .singleEnemy, vfx: String) -> Skill {
            let sweep = target != .singleEnemy
            return Skill(id: skillID, name: name, description: description, slot: slot, cooldown: cd, target: target,
                         damage: damage, statuses: statuses, utilities: utilities, levelUpBonuses: strikeLadder,
                         animation: third ? .ultimate : .attackHeavy,
                         cameraShot: sweep ? .cinematicOrbit : (third ? .impactClose : .pushIn), vfx: vfx)
        }
        /// A skill with no damage: a rite for the team, or on the enemy line.
        func rite(_ description: String, cd: Int, target: TargetSelector = .allAllies, statuses: [StatusSpec] = [],
                  utilities: [UtilityEffect] = [], ladder: [SkillUpgrade]? = nil, vfx: String) -> Skill {
            Skill(id: skillID, name: name, description: description, slot: slot, cooldown: cd, target: target,
                  damage: nil, statuses: statuses, utilities: utilities, levelUpBonuses: ladder ?? cooldownOnly,
                  animation: third ? .ultimate : .castRelease, cameraShot: third ? .heroLowAngle : .pushIn, vfx: vfx)
        }
        func status(_ kind: StatusKind, _ chance: Double, turns: Int = 2, on target: TargetSelector = .singleEnemy,
                    magnitude: Double = 0, perHit: Bool = false) -> StatusSpec {
            StatusSpec(kind, chance: chance, turns: turns, target: target, magnitude: magnitude, rollsPerHit: perHit)
        }

        switch kit {
        case .striker:
            switch element {
            case .ember:
                if !third {
                    return blow("Two blows on one enemy, each with a 50% chance to Burn it for 2 turns, hitting 15% harder for every harmful effect on it.",
                                cd: 3, DamageSpec(multiplier: 2.10, hits: 2, bonusPerTargetDebuff: 0.15),
                                statuses: [status(.burn, 0.50, perHit: true)], vfx: "lioness_rake")
                }
                return blow("Sweeps the whole enemy line with a 60% chance to Burn each for 2 turns, and takes Attack Up for 2 turns.",
                            cd: 5, DamageSpec(multiplier: 2.60),
                            statuses: [status(.burn, 0.60, on: .allEnemies), status(.attackUp, 1.0, on: .caster)],
                            target: .allEnemies, vfx: "wrath_of_the_eye")
            case .tide:
                if !third {
                    return blow("A crushing blow on one enemy with a 70% chance to Freeze it for 1 turn.",
                                cd: 4, DamageSpec(multiplier: 3.80), statuses: [status(.freeze, 0.70, turns: 1)], vfx: "impact_tide")
                }
                return blow("Sweeps the whole enemy line with a 50% chance to Slow each for 2 turns and a 60% chance to drag each attack bar back by 20%.",
                            cd: 5, DamageSpec(multiplier: 2.40), statuses: [status(.speedDown, 0.50, on: .allEnemies)],
                            utilities: [.attackBarChange(-0.20, chance: 0.60, .allEnemies)], target: .allEnemies, vfx: "duat_rite")
            case .gale:
                if !third {
                    return blow("Three quick cuts on one enemy, each with a 30% chance to make its next hit Glancing for 2 turns, and a 30% chance to take another turn.",
                                cd: 3, DamageSpec(multiplier: 1.45, hits: 3), statuses: [status(.glancing, 0.30, perHit: true)],
                                utilities: [.extraTurn(chance: 0.30)], vfx: "scale_strike")
                }
                return blow("Sweeps the whole enemy line, then takes Haste for 2 turns and fills its own attack bar by 30%.",
                            cd: 5, DamageSpec(multiplier: 2.30), statuses: [status(.speedUp, 1.0, on: .caster)],
                            utilities: [.attackBarChange(0.30, chance: 1.0, .caster)], target: .allEnemies, vfx: "thunderclap")
            case .radiance:
                if !third {
                    return blow("A blow on one enemy with a 60% chance to inflict Attack Down for 2 turns; the caster gains Focus for 2 turns.",
                                cd: 3, DamageSpec(multiplier: 3.60),
                                statuses: [status(.attackDown, 0.60), status(.critRateUp, 1.0, on: .caster)], vfx: "eye_of_ra")
                }
                return blow("Sweeps the whole enemy line with a strike that always crits and a 50% chance to inflict Attack Down on each for 2 turns.",
                            cd: 5, DamageSpec(multiplier: 2.40, alwaysCrits: true), statuses: [status(.attackDown, 0.50, on: .allEnemies)],
                            target: .allEnemies, vfx: "olympian_decree")
            case .umbra:
                if !third {
                    return blow("A blow on one enemy that heals the caster for 40% of the damage, with a 60% chance to Break its defence for 2 turns.",
                                cd: 3, DamageSpec(multiplier: 3.50), statuses: [status(.defenseDown, 0.60)],
                                utilities: [.lifesteal(0.40)], vfx: "heart_weigh")
                }
                return blow("Sweeps the whole enemy line, hitting harder the more health each has lost, with a 50% chance to Brand each for 2 turns.",
                            cd: 5, DamageSpec(multiplier: 2.30, bonusPerMissingHealth: 0.005), statuses: [status(.brand, 0.50, on: .allEnemies)],
                            target: .allEnemies, vfx: "blood_thirst")
            }
        case .duelist:
            switch element {
            case .ember:
                if !third {
                    return blow("A blow that ignores 30% of the target's defence, with a 60% chance to Burn it for 2 turns.",
                                cd: 4, DamageSpec(multiplier: 4.20, defenseIgnore: 0.30), statuses: [status(.burn, 0.60)], vfx: "lioness_rake")
                }
                return blow("A sure critical strike that hits 20% harder for every harmful effect on the target.",
                            cd: 5, DamageSpec(multiplier: 5.20, bonusPerTargetDebuff: 0.20, alwaysCrits: true), vfx: "keraunos")
            case .tide:
                if !third {
                    return blow("Two cuts on one enemy, each with a 40% chance to Freeze it for 1 turn.",
                                cd: 4, DamageSpec(multiplier: 2.10, hits: 2), statuses: [status(.freeze, 0.40, turns: 1, perHit: true)], vfx: "impact_tide")
                }
                return blow("A blow that ignores half the target's defence, with an 80% chance to drag its attack bar back by half.",
                            cd: 5, DamageSpec(multiplier: 4.80, defenseIgnore: 0.50),
                            utilities: [.attackBarChange(-0.50, chance: 0.80, .singleEnemy)], vfx: "duat_rite")
            case .gale:
                if !third {
                    return blow("Four cuts on one enemy, each with a 25% chance to make its next hit Glancing for 2 turns.",
                                cd: 3, DamageSpec(multiplier: 1.10, hits: 4), statuses: [status(.glancing, 0.25, perHit: true)], vfx: "scale_strike")
                }
                return blow("A sure critical strike, after which the caster's attack bar fills by half.",
                            cd: 5, DamageSpec(multiplier: 4.40, alwaysCrits: true),
                            utilities: [.attackBarChange(0.50, chance: 1.0, .caster)], vfx: "thunderclap")
            case .radiance:
                if !third {
                    return blow("A blow with a 60% chance to inflict Attack Down for 2 turns; the caster gains Focus for 2 turns.",
                                cd: 4, DamageSpec(multiplier: 4.00),
                                statuses: [status(.attackDown, 0.60), status(.critRateUp, 1.0, on: .caster)], vfx: "eye_of_ra")
                }
                return blow("A sure critical strike that ignores 40% of the target's defence.",
                            cd: 5, DamageSpec(multiplier: 5.40, defenseIgnore: 0.40, alwaysCrits: true), vfx: "keraunos")
            case .umbra:
                if !third {
                    return blow("A blow that heals the caster for half the damage, with a 50% chance to Brand the target for 2 turns.",
                                cd: 4, DamageSpec(multiplier: 4.20), statuses: [status(.brand, 0.50)],
                                utilities: [.lifesteal(0.50)], vfx: "heart_weigh")
                }
                return blow("An execution: a sure critical strike that hits 1% harder for every 1% of health the target has lost.",
                            cd: 5, DamageSpec(multiplier: 4.60, bonusPerMissingHealth: 0.010, alwaysCrits: true), vfx: "blood_thirst")
            }
        case .marksman:
            switch element {
            case .ember:
                if !third {
                    return blow("Two shots at one enemy, each with a 50% chance to Burn it for 2 turns.",
                                cd: 3, DamageSpec(multiplier: 2.20, hits: 2), statuses: [status(.burn, 0.50, perHit: true)], vfx: "thunderbolt")
                }
                return blow("A volley over the whole enemy line with a 60% chance to Burn each for 2 turns; the caster takes Attack Up for 2 turns.",
                            cd: 5, DamageSpec(multiplier: 2.30),
                            statuses: [status(.burn, 0.60, on: .allEnemies), status(.attackUp, 1.0, on: .caster)],
                            target: .allEnemies, vfx: "wrath_of_the_eye")
            case .tide:
                if !third {
                    return blow("Three shots at random enemies; each enemy has a 30% chance to be Slowed for 2 turns.",
                                cd: 3, DamageSpec(multiplier: 1.60, hits: 3), statuses: [status(.speedDown, 0.30, on: .allEnemies)],
                                target: .randomEnemies(count: 3), vfx: "impact_tide")
                }
                return blow("A volley over the whole enemy line with a 45% chance to Freeze each for 1 turn.",
                            cd: 5, DamageSpec(multiplier: 2.20), statuses: [status(.freeze, 0.45, turns: 1, on: .allEnemies)],
                            target: .allEnemies, vfx: "duat_rite")
            case .gale:
                if !third {
                    return blow("Five quick shots at random enemies; each enemy has a 20% chance to have its next hit Glancing for 2 turns.",
                                cd: 3, DamageSpec(multiplier: 1.05, hits: 5), statuses: [status(.glancing, 0.20, on: .allEnemies)],
                                target: .randomEnemies(count: 5), vfx: "scale_strike")
                }
                return blow("A volley over the whole enemy line, and the whole team's attack bar fills by 20%.",
                            cd: 5, DamageSpec(multiplier: 2.00),
                            utilities: [.attackBarChange(0.20, chance: 1.0, .allAllies)], target: .allEnemies, vfx: "thunderclap")
            case .radiance:
                if !third {
                    return blow("One shot that removes a beneficial effect from the target, with a 60% chance to inflict Attack Down for 2 turns.",
                                cd: 3, DamageSpec(multiplier: 4.00), statuses: [status(.attackDown, 0.60)],
                                utilities: [.strip(count: 1, chance: 0.85, .singleEnemy)], vfx: "eye_of_ra")
                }
                return blow("A volley over the whole enemy line that removes a beneficial effect from each; the caster gains Focus for 2 turns.",
                            cd: 5, DamageSpec(multiplier: 2.20), statuses: [status(.critRateUp, 1.0, on: .caster)],
                            utilities: [.strip(count: 1, chance: 0.70, .allEnemies)], target: .allEnemies, vfx: "olympian_decree")
            case .umbra:
                if !third {
                    return blow("A shot that heals the caster for 40% of the damage, with a 60% chance to Break the target's defence for 2 turns.",
                                cd: 3, DamageSpec(multiplier: 3.60), statuses: [status(.defenseDown, 0.60)],
                                utilities: [.lifesteal(0.40)], vfx: "heart_weigh")
                }
                return blow("A volley over the whole enemy line with a 40% chance to put each to Sleep for 1 turn and a 40% chance to Brand each for 2 turns.",
                            cd: 5, DamageSpec(multiplier: 2.10),
                            statuses: [status(.sleep, 0.40, turns: 1, on: .allEnemies), status(.brand, 0.40, on: .allEnemies)],
                            target: .allEnemies, vfx: "blood_thirst")
            }
        case .bruiser:
            switch element {
            case .ember:
                if !third {
                    return blow("A slam on one enemy with a 70% chance to Burn it for 2 turns; the caster takes Attack Up for 2 turns.",
                                cd: 4, DamageSpec(multiplier: 2.40),
                                statuses: [status(.burn, 0.70), status(.attackUp, 1.0, on: .caster)], vfx: "impact_ember")
                }
                return blow("A blow for damage equal to 28% of the caster's maximum health, ignoring 30% of the target's defence, with a 60% chance to Break its defence for 2 turns.",
                            cd: 4, DamageSpec(multiplier: 0.28, scaling: .maxHealth, defenseIgnore: 0.30),
                            statuses: [status(.defenseDown, 0.60)], vfx: "heart_weigh")
            case .tide:
                if !third {
                    return blow("Roars at the whole enemy line for modest damage with a 45% chance to Provoke each for 1 turn, and takes Defense Up for 2 turns.",
                                cd: 4, DamageSpec(multiplier: 1.50),
                                statuses: [status(.provoke, 0.45, turns: 1, on: .allEnemies), status(.defenseUp, 1.0, on: .caster)],
                                target: .allEnemies, vfx: "wrath_of_the_eye")
                }
                return blow("A blow for damage equal to 28% of the caster's maximum health, ignoring 30% of the target's defence, that heals the caster for 20% of its maximum health.",
                            cd: 4, DamageSpec(multiplier: 0.28, scaling: .maxHealth, defenseIgnore: 0.30),
                            utilities: [.healTargetMaxHealth(0.20, .caster)], vfx: "duat_rite")
            case .gale:
                if !third {
                    return blow("A charge at one enemy with a 60% chance to Slow it for 2 turns; the caster takes Haste for 2 turns.",
                                cd: 4, DamageSpec(multiplier: 2.60),
                                statuses: [status(.speedDown, 0.60), status(.speedUp, 1.0, on: .caster)], vfx: "impact_gale")
                }
                return blow("A blow on the whole enemy line for damage equal to 24% of the caster's maximum health, with a 40% chance to make each one's next hit Glancing for 2 turns.",
                            cd: 5, DamageSpec(multiplier: 0.24, scaling: .maxHealth), statuses: [status(.glancing, 0.40, on: .allEnemies)],
                            target: .allEnemies, vfx: "thunderclap")
            case .radiance:
                if !third {
                    return blow("A blow with a 60% chance to Provoke the target for 1 turn; the caster takes Defense Up and a shield worth 20% of its maximum health for 2 turns.",
                                cd: 4, DamageSpec(multiplier: 2.00),
                                statuses: [status(.provoke, 0.60, turns: 1), status(.defenseUp, 1.0, on: .caster),
                                           status(.shield, 1.0, on: .caster, magnitude: 0.20)], vfx: "maat_shield")
                }
                return blow("A blow for damage equal to 26% of the caster's maximum health, with an 85% chance to Provoke the target for 2 turns; the caster gains Immunity for 2 turns.",
                            cd: 4, DamageSpec(multiplier: 0.26, scaling: .maxHealth),
                            statuses: [status(.provoke, 0.85), status(.immunity, 1.0, on: .caster)], vfx: "olympian_decree")
            case .umbra:
                if !third {
                    return blow("A blow that heals the caster for half the damage, with a 60% chance to Break the target's defence for 2 turns.",
                                cd: 4, DamageSpec(multiplier: 2.60), statuses: [status(.defenseDown, 0.60)],
                                utilities: [.lifesteal(0.50)], vfx: "heart_weigh")
                }
                return blow("A blow for damage equal to 30% of the caster's maximum health that heals the caster for 30% of the damage, with a 50% chance to Brand the target for 2 turns.",
                            cd: 4, DamageSpec(multiplier: 0.30, scaling: .maxHealth), statuses: [status(.brand, 0.50)],
                            utilities: [.lifesteal(0.30)], vfx: "blood_thirst")
            }
        case .warden:
            switch element {
            case .ember:
                if !third {
                    return blow("A strike with a 70% chance to Burn the target for 2 turns; the caster takes a Counter stance for 2 turns.",
                                cd: 4, DamageSpec(multiplier: 3.00),
                                statuses: [status(.burn, 0.70), status(.counterStance, 1.0, on: .caster)], vfx: "impact_ember")
                }
                return rite("Attack Up and a shield worth 12% of their maximum health for every ally for 2 turns.",
                            cd: 5, statuses: [status(.attackUp, 1.0, on: .allAllies), status(.shield, 1.0, on: .allAllies, magnitude: 0.12)],
                            vfx: "buff")
            case .tide:
                if !third {
                    return rite("A wall for the team: every ally gains Defense Up and a shield worth 15% of their maximum health for 2 turns.",
                                cd: 4, statuses: [status(.defenseUp, 1.0, on: .allAllies), status(.shield, 1.0, on: .allAllies, magnitude: 0.15)],
                                vfx: "maat_shield")
                }
                return blow("A strike with a 70% chance to Freeze the target for 1 turn; the caster takes a shield worth 20% of its maximum health for 2 turns.",
                            cd: 5, DamageSpec(multiplier: 3.40),
                            statuses: [status(.freeze, 0.70, turns: 1), status(.shield, 1.0, on: .caster, magnitude: 0.20)], vfx: "impact_tide")
            case .gale:
                if !third {
                    return rite("Haste for every ally for 2 turns, and the team's attack bar fills by 15%.",
                                cd: 4, statuses: [status(.speedUp, 1.0, on: .allAllies)],
                                utilities: [.attackBarChange(0.15, chance: 1.0, .allAllies)], vfx: "buff")
                }
                return blow("A strike with an 85% chance to Provoke the target for 2 turns while a Counter stance covers the caster.",
                            cd: 5, DamageSpec(multiplier: 3.20),
                            statuses: [status(.provoke, 0.85), status(.counterStance, 1.0, on: .caster)], vfx: "heart_weigh")
            case .radiance:
                if !third {
                    return rite("A shield worth 18% of their maximum health for every ally for 2 turns, and one harmful effect removed from each.",
                                cd: 4, statuses: [status(.shield, 1.0, on: .allAllies, magnitude: 0.18)],
                                utilities: [.cleanse(count: 1, .allAllies)], vfx: "maat_shield")
                }
                return blow("A strike with an 85% chance to Provoke the target for 2 turns; the caster gains Immunity and a Counter stance for 2 turns.",
                            cd: 5, DamageSpec(multiplier: 3.20),
                            statuses: [status(.provoke, 0.85), status(.immunity, 1.0, on: .caster), status(.counterStance, 1.0, on: .caster)],
                            vfx: "olympian_decree")
            case .umbra:
                if !third {
                    return blow("A strike with a 60% chance to Break the target's defence for 2 turns that heals the caster for 30% of the damage.",
                                cd: 4, DamageSpec(multiplier: 3.20), statuses: [status(.defenseDown, 0.60)],
                                utilities: [.lifesteal(0.30)], vfx: "heart_weigh")
                }
                return blow("A heavy strike with an 85% chance to Provoke the target and a 50% chance to Brand it for 2 turns, while a Counter stance covers the caster.",
                            cd: 5, DamageSpec(multiplier: 3.60),
                            statuses: [status(.provoke, 0.85), status(.brand, 0.50), status(.counterStance, 1.0, on: .caster)], vfx: "blood_thirst")
            }
        case .healer:
            switch element {
            case .ember:
                if !third {
                    return rite("Heals every ally for 20% of their maximum health and grants Attack Up for 2 turns.",
                                cd: 4, statuses: [status(.attackUp, 1.0, on: .allAllies)],
                                utilities: [.healTargetMaxHealth(0.20, .allAllies)], ladder: supportLadder, vfx: "heal")
                }
                return rite("Revives one fallen ally with 30% health, heals every ally for 15% of their maximum health, and grants Attack Up for 2 turns.",
                            cd: 5, statuses: [status(.attackUp, 1.0, on: .allAllies)],
                            utilities: [.revive(healthFraction: 0.30), .healTargetMaxHealth(0.15, .allAllies)], ladder: supportLadder, vfx: "duat_rite")
            case .tide:
                if !third {
                    return rite("Heals every ally for 30% of their maximum health and removes one harmful effect from each.",
                                cd: 4, utilities: [.healTargetMaxHealth(0.30, .allAllies), .cleanse(count: 1, .allAllies)],
                                ladder: supportLadder, vfx: "heal")
                }
                return rite("Heals every ally for 20% of their maximum health, with Defense Up and Immunity for 2 turns.",
                            cd: 5, statuses: [status(.defenseUp, 1.0, on: .allAllies), status(.immunity, 1.0, on: .allAllies)],
                            utilities: [.healTargetMaxHealth(0.20, .allAllies)], ladder: supportLadder, vfx: "maat_shield")
            case .gale:
                if !third {
                    return rite("Heals every ally for 18% of their maximum health, and the team's attack bar fills by 25%.",
                                cd: 4, utilities: [.healTargetMaxHealth(0.18, .allAllies), .attackBarChange(0.25, chance: 1.0, .allAllies)],
                                ladder: supportLadder, vfx: "heal")
                }
                return rite("Haste for every ally for 2 turns, the team's attack bar fills by 30%, and one harmful effect is removed from each.",
                            cd: 5, statuses: [status(.speedUp, 1.0, on: .allAllies)],
                            utilities: [.attackBarChange(0.30, chance: 1.0, .allAllies), .cleanse(count: 1, .allAllies)], vfx: "buff")
            case .radiance:
                if !third {
                    return rite("Heals every ally for 25% of their maximum health and shields each for 12% of it for 2 turns.",
                                cd: 4, statuses: [status(.shield, 1.0, on: .allAllies, magnitude: 0.12)],
                                utilities: [.healTargetMaxHealth(0.25, .allAllies)], ladder: supportLadder, vfx: "maat_shield")
                }
                return rite("Heals every ally for 20% of their maximum health, with Immunity and Focus for 2 turns.",
                            cd: 5, statuses: [status(.immunity, 1.0, on: .allAllies), status(.critRateUp, 1.0, on: .allAllies)],
                            utilities: [.healTargetMaxHealth(0.20, .allAllies)], ladder: supportLadder, vfx: "olympian_decree")
            case .umbra:
                if !third {
                    return blow("A strike on one enemy that heals every ally for 150% of the caster's attack.",
                                cd: 3, DamageSpec(multiplier: 2.80), utilities: [.healFromAttack(1.5, .allAllies)], vfx: "heart_weigh")
                }
                return rite("Focus for every ally for 2 turns, the team's attack bar fills by 25%, and up to two beneficial effects are removed from every enemy.",
                            cd: 5, statuses: [status(.critRateUp, 1.0, on: .allAllies)],
                            utilities: [.attackBarChange(0.25, chance: 1.0, .allAllies), .strip(count: 2, chance: 0.70, .allEnemies)], vfx: "debuff")
            }
        case .oracle:
            switch element {
            case .ember:
                if !third {
                    return blow("Damages the whole enemy line with a 40% chance to Stun each for 1 turn.",
                                cd: 4, DamageSpec(multiplier: 1.60), statuses: [status(.stun, 0.40, turns: 1, on: .allEnemies)],
                                target: .allEnemies, vfx: "thunderclap")
                }
                return rite("Attack Up and Focus for every ally for 2 turns, and the team's attack bar fills by 25%.",
                            cd: 5, statuses: [status(.attackUp, 1.0, on: .allAllies), status(.critRateUp, 1.0, on: .allAllies)],
                            utilities: [.attackBarChange(0.25, chance: 1.0, .allAllies)], vfx: "olympian_decree")
            case .tide:
                if !third {
                    return blow("Damages the whole enemy line with a 50% chance to Slow each for 2 turns and a 60% chance to drag each attack bar back by 25%.",
                                cd: 4, DamageSpec(multiplier: 1.50), statuses: [status(.speedDown, 0.50, on: .allEnemies)],
                                utilities: [.attackBarChange(-0.25, chance: 0.60, .allEnemies)], target: .allEnemies, vfx: "duat_rite")
                }
                return rite("Defense Up and a shield worth 15% of their maximum health for every ally for 2 turns, and heals each for 15%.",
                            cd: 5, statuses: [status(.defenseUp, 1.0, on: .allAllies), status(.shield, 1.0, on: .allAllies, magnitude: 0.15)],
                            utilities: [.healTargetMaxHealth(0.15, .allAllies)], ladder: supportLadder, vfx: "maat_shield")
            case .gale:
                if !third {
                    return blow("Damages the whole enemy line with a 35% chance to Silence each for 2 turns, and the team's attack bar fills by 15%.",
                                cd: 4, DamageSpec(multiplier: 1.40), statuses: [status(.silence, 0.35, on: .allEnemies)],
                                utilities: [.attackBarChange(0.15, chance: 1.0, .allAllies)], target: .allEnemies, vfx: "thunderclap")
                }
                return rite("Haste for every ally for 2 turns, the team's attack bar fills by 40%, and one harmful effect is removed from each.",
                            cd: 5, statuses: [status(.speedUp, 1.0, on: .allAllies)],
                            utilities: [.attackBarChange(0.40, chance: 1.0, .allAllies), .cleanse(count: 1, .allAllies)], vfx: "buff")
            case .radiance:
                if !third {
                    return blow("Damages the whole enemy line, removing a beneficial effect from each, with a 50% chance to inflict Attack Down for 2 turns.",
                                cd: 4, DamageSpec(multiplier: 1.50), statuses: [status(.attackDown, 0.50, on: .allEnemies)],
                                utilities: [.strip(count: 1, chance: 0.80, .allEnemies)], target: .allEnemies, vfx: "eye_of_ra")
                }
                return rite("Immunity and Focus for every ally for 2 turns, and the team's attack bar fills by 20%.",
                            cd: 5, statuses: [status(.immunity, 1.0, on: .allAllies), status(.critRateUp, 1.0, on: .allAllies)],
                            utilities: [.attackBarChange(0.20, chance: 1.0, .allAllies)], vfx: "olympian_decree")
            case .umbra:
                if !third {
                    return blow("Damages the whole enemy line with a 40% chance to put each to Sleep for 1 turn and a 50% chance to Brand each for 2 turns.",
                                cd: 4, DamageSpec(multiplier: 1.60),
                                statuses: [status(.sleep, 0.40, turns: 1, on: .allEnemies), status(.brand, 0.50, on: .allEnemies)],
                                target: .allEnemies, vfx: "debuff")
                }
                return rite("A 60% chance to Break the defence of each enemy and a 40% chance to Brand it, for 2 turns; the team's attack bar fills by 20%.",
                            cd: 5, target: .allEnemies,
                            statuses: [status(.defenseDown, 0.60, on: .allEnemies), status(.brand, 0.40, on: .allEnemies)],
                            utilities: [.attackBarChange(0.20, chance: 1.0, .allAllies)], vfx: "wrath_of_the_eye")
            }
        case .trickster:
            switch element {
            case .ember:
                if !third {
                    return blow("A strike with an 80% chance to Burn the target for 2 turns that removes one beneficial effect from it.",
                                cd: 3, DamageSpec(multiplier: 3.20), statuses: [status(.burn, 0.80)],
                                utilities: [.strip(count: 1, chance: 0.85, .singleEnemy)], vfx: "lioness_rake")
                }
                return blow("Damages the whole enemy line with a 60% chance to Burn each and a 40% chance to inflict Attack Down on each for 2 turns.",
                            cd: 5, DamageSpec(multiplier: 2.00),
                            statuses: [status(.burn, 0.60, on: .allEnemies), status(.attackDown, 0.40, on: .allEnemies)],
                            target: .allEnemies, vfx: "wrath_of_the_eye")
            case .tide:
                if !third {
                    return blow("A strike with a 70% chance to Freeze the target for 1 turn and a 70% chance to drag its attack bar back by 30%.",
                                cd: 3, DamageSpec(multiplier: 3.00), statuses: [status(.freeze, 0.70, turns: 1)],
                                utilities: [.attackBarChange(-0.30, chance: 0.70, .singleEnemy)], vfx: "impact_tide")
                }
                return blow("Damages the whole enemy line with a 50% chance to Slow each for 2 turns and a 60% chance to drag each attack bar back by 30%.",
                            cd: 5, DamageSpec(multiplier: 1.90), statuses: [status(.speedDown, 0.50, on: .allEnemies)],
                            utilities: [.attackBarChange(-0.30, chance: 0.60, .allEnemies)], target: .allEnemies, vfx: "duat_rite")
            case .gale:
                if !third {
                    return blow("A strike that removes up to two beneficial effects from the target, after which the caster's attack bar fills by 30%.",
                                cd: 3, DamageSpec(multiplier: 3.20),
                                utilities: [.strip(count: 2, chance: 0.85, .singleEnemy), .attackBarChange(0.30, chance: 1.0, .caster)],
                                vfx: "scale_strike")
                }
                return blow("Damages the whole enemy line with a 50% chance to Silence each for 2 turns; the caster takes Haste for 2 turns.",
                            cd: 5, DamageSpec(multiplier: 1.90),
                            statuses: [status(.silence, 0.50, on: .allEnemies), status(.speedUp, 1.0, on: .caster)],
                            target: .allEnemies, vfx: "thunderclap")
            case .radiance:
                if !third {
                    return blow("A strike that removes up to two beneficial effects from the target, with a 60% chance to inflict Attack Down for 2 turns.",
                                cd: 3, DamageSpec(multiplier: 3.20), statuses: [status(.attackDown, 0.60)],
                                utilities: [.strip(count: 2, chance: 0.90, .singleEnemy)], vfx: "eye_of_ra")
                }
                return blow("Damages the whole enemy line, removing a beneficial effect from each, with a 50% chance to inflict Attack Down on each for 2 turns.",
                            cd: 5, DamageSpec(multiplier: 2.00), statuses: [status(.attackDown, 0.50, on: .allEnemies)],
                            utilities: [.strip(count: 1, chance: 0.70, .allEnemies)], target: .allEnemies, vfx: "olympian_decree")
            case .umbra:
                if !third {
                    return blow("A strike that removes up to two beneficial effects from the target and has a 60% chance to drag its attack bar back by 30%.",
                                cd: 3, DamageSpec(multiplier: 3.40),
                                utilities: [.strip(count: 2, chance: 0.85, .singleEnemy), .attackBarChange(-0.30, chance: 0.60, .singleEnemy)],
                                vfx: "heart_weigh")
                }
                return blow("Damages the whole enemy line with a 60% chance to Break each one's defence and a 40% chance to Brand it for 2 turns.",
                            cd: 5, DamageSpec(multiplier: 2.00),
                            statuses: [status(.defenseDown, 0.60, on: .allEnemies), status(.brand, 0.40, on: .allEnemies)],
                            target: .allEnemies, vfx: "wrath_of_the_eye")
            }
        }
    }

    private static func passive(
        id: String, name: String, trigger: PassiveTrigger, target: TargetSelector, description: String,
        statuses: [StatusSpec], utilities: [UtilityEffect], vfx: String
    ) -> Skill {
        Skill(
            id: "\(id)_passive",
            name: name,
            description: description,
            slot: 3,
            cooldown: 0,
            target: target,
            damage: nil,
            statuses: statuses,
            utilities: utilities,
            isPassive: true,
            trigger: trigger,
            requiresAwakening: true,
            animation: .castRelease,
            cameraShot: .heroLowAngle,
            vfx: vfx
        )
    }
}

// MARK: - The elemental skill names

extension UnitDatabase {
    /// Second and third skill names per family and element, in
    /// `Element.allCases` order: five second-skill names, then five
    /// third-skill names. A family missing here keeps its row's two names
    /// for every element.
    static let elementalSkillNames: [String: [String]] = [:]
}
