import Foundation

/// Athena, and everything she teaches.
///
/// The owner asked for "a full tutorial of the entire game. Like how
/// summoners war uses Ellia, maybe we should have a 2D Athena that runs you
/// through the tutorial", and then settled the shape of it: she is a VOICE,
/// never a unit ("Ellia can't battle"), the first fight cannot be lost, and
/// the opening is skippable AND replayable — "that would be a good idea,
/// let's expand on that".
///
/// The expansion is this file. Every single thing she says is a LESSON with
/// an id, and none of them are thrown away: `LessonsView` lists them all,
/// the given ones replayable for ever and the locked ones named but greyed,
/// so the tutorial becomes the game's manual instead of eight minutes that
/// are spent once. Almost nothing in the genre does that — Summoners War's
/// Ellia teaches and is gone, and her Summoner's Way is a reward checklist
/// rather than the words themselves.
///
/// Two kinds of lesson, and the difference is `goal`:
///
/// - A **step** of the opening has one. She says her piece, and then her
///   caret sits on the thing she named until the SAVE says it is done. The
///   goal is read off what the player owns and has cleared, never off a flag
///   written by the screen that did it — the rule `FirstHourStep` was built
///   on, which is what lets a save made before the guide existed land on the
///   right step instead of restarting a veteran at the beginning.
/// - A **pop-in** has none. She appears once when a system first becomes
///   reachable, says what it is, and is marked read.
enum GuideFace: String, Sendable, CaseIterable {
    case calm, pleased, concerned, urging

    /// `Portraits/athena_<face>.png`, painted as one 2 x 2 sheet so the four
    /// are the same woman (`tools/athena_art.py`).
    var imageName: String { "athena_\(rawValue)" }
}

/// One thing she says, and the face she says it with.
struct LessonBeat: Sendable {
    let says: String
    let face: GuideFace

    init(_ says: String, _ face: GuideFace = .calm) {
        self.says = says
        self.face = face
    }
}

/// How the library groups her lessons.
enum LessonTopic: String, CaseIterable, Sendable, Identifiable {
    case opening, fighting, gods, relics, training, places, economy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .opening: return "The Opening"
        case .fighting: return "Fighting"
        case .gods: return "Gods"
        case .relics: return "Relics"
        case .training: return "Training"
        case .places: return "Places"
        case .economy: return "Coin"
        }
    }
}

struct Lesson: Identifiable, Sendable {
    let id: String
    /// Its name in the library.
    let title: String
    let topic: LessonTopic
    let beats: [LessonBeat]
    /// The control her caret sits on once she has finished speaking, by the
    /// name a view registered with `.guideAnchor(_:)`. Nil for a pop-in,
    /// which points at nothing.
    let anchor: String?
    /// The one line that stays under the caret while the player does it. The
    /// test of an opening is whether somebody who has never seen the game
    /// knows what to press, not whether the prose is nice.
    let prompt: String?
    /// Done, read off the save. Nil means the lesson is over when she stops
    /// talking.
    let goal: (@Sendable (Player) -> Bool)?
    /// When she offers it unasked. A lesson that never unlocks is still in
    /// the library, greyed, which is how a player sees what the game holds.
    let unlock: @Sendable (Player) -> Bool

    init(
        id: String,
        title: String,
        topic: LessonTopic,
        beats: [LessonBeat],
        anchor: String? = nil,
        prompt: String? = nil,
        goal: (@Sendable (Player) -> Bool)? = nil,
        unlock: @escaping @Sendable (Player) -> Bool = { _ in true }
    ) {
        self.id = id
        self.title = title
        self.topic = topic
        self.beats = beats
        self.anchor = anchor
        self.prompt = prompt
        self.goal = goal
        self.unlock = unlock
    }

    /// A step of the opening keeps its caret up until the player does it; a
    /// pop-in is done when it has been read.
    var isStep: Bool { goal != nil }
}

/// Every lesson in the game, in the order she gives them.
///
/// The names of the anchors are the ones the screens register: `island_gate`,
/// `island_circle`, `island_hall`, `tab_collection`. A lesson pointing at an
/// anchor no view has registered simply shows its line without a caret, which
/// is the safe way for this to fail.
enum LessonBook {
    // MARK: - The opening

    static let opening: [Lesson] = [
        Lesson(
            id: "welcome",
            title: "The sleeping gods",
            topic: .opening,
            beats: [
                LessonBeat("The gods of five worlds are asleep under the stone. You are the one who wakes them."),
                LessonBeat("I am Athena. I will not fight for you — that is not what I am for.", .calm),
                LessonBeat("I will show you where everything is, and then I will get out of your way.", .pleased),
            ]
        ),
        Lesson(
            id: "first_fight",
            title: "The first blow",
            topic: .opening,
            beats: [
                LessonBeat("Start at the Gate of the Duat. Two shabti wait on the other side of it.", .urging),
                LessonBeat("In the fight, tap the enemy you want struck. Your god does the rest."),
                LessonBeat("You cannot lose this one. I have seen to it.", .pleased),
            ],
            anchor: "island_gate",
            prompt: "The Gate of the Duat. Tap it, then fight the first stage.",
            goal: { player in FirstHourStep.fight.isDone(for: player) }
        ),
        Lesson(
            id: "first_summon",
            title: "A god of your own",
            topic: .opening,
            beats: [
                LessonBeat("The dead pay for the walking. Everything they carried was in that box.", .pleased),
                LessonBeat("Now the Summoning Circle. A scroll opens, and a god steps out of it.", .urging),
            ],
            anchor: "island_circle",
            prompt: "The Summoning Circle. Open a scroll.",
            goal: { player in FirstHourStep.summon.isDone(for: player) }
        ),
        Lesson(
            id: "first_relic",
            title: "Nothing on",
            topic: .opening,
            beats: [
                LessonBeat("Yours now.", .pleased),
                LessonBeat("A god wearing nothing is a god at half strength. Relics are the difference."),
                LessonBeat("Collection, then the one you just took, then any slot on the ring around them.", .urging),
            ],
            anchor: "tab_collection",
            prompt: "Collection → your new god → a relic slot → Equip.",
            // `FirstHourStep.equip` carries the reasoning: a new save already
            // wears the starter's six, so this counts a SECOND unit in relics
            // and stands down when there is nobody to dress or nothing spare
            // to dress them in.
            goal: { player in FirstHourStep.equip.isDone(for: player) }
        ),
        Lesson(
            id: "first_powerup",
            title: "The Hall of Ka",
            topic: .opening,
            beats: [
                LessonBeat("Armed. Good.", .pleased),
                LessonBeat("Last thing. The Hall of Ka takes the gods you will never field and pours them into the one you will.", .urging),
                LessonBeat("It is not cruelty. It is arithmetic."),
            ],
            anchor: "island_hall",
            prompt: "Hall of Ka: pick a god, feed it the ones you don't want.",
            goal: { player in FirstHourStep.powerUp.isDone(for: player) }
        ),
        Lesson(
            id: "farewell",
            title: "Out of your way",
            topic: .opening,
            beats: [
                LessonBeat("That is the shape of it: fight, summon, dress, feed.", .pleased),
                LessonBeat("Everything else I have to say is kept in More, under Lessons. Ask me twice if you like — I do not mind repeating myself."),
                LessonBeat("Go and wake somebody.", .pleased),
            ]
        ),
    ]

    // MARK: - The pop-ins, one per system, where it first becomes reachable

    static let systems: [Lesson] = [
        Lesson(
            id: "relic_power",
            title: "Feeding a stone",
            topic: .relics,
            beats: [
                LessonBeat("A relic can be fed drachma to grow. It is sure of itself up to +3."),
                LessonBeat("After that it starts to fail, and it takes your coin whether it works or not.", .concerned),
                LessonBeat("At +3, +6, +9 and +12 it gains a new stat or grows one it has. At +15 its main stat trebles. That is what you are paying for."),
            ],
            unlock: { player in player.relics.count >= 4 }
        ),
        Lesson(
            id: "sets",
            title: "Two of a kind, four of a kind",
            topic: .relics,
            beats: [
                LessonBeat("Relics come in sets. Two of one set, or four, and the set itself starts working."),
                LessonBeat("Each chapter of the campaign gives up two sets and no others. The map tells you which — the genre hides it; I will not."),
            ],
            unlock: { player in player.relics.count >= 8 }
        ),
        Lesson(
            id: "elements",
            title: "The wheel",
            topic: .fighting,
            beats: [
                LessonBeat("Fire beats wind, wind beats water, water beats fire. Light and dark only ever beat each other."),
                LessonBeat("The arrow over an enemy's head tells you which way the fight leans before you commit to it.", .urging),
            ],
            unlock: { player in (player.campaignProgress["duat_1"] ?? 0) >= 2 }
        ),
        Lesson(
            id: "evolve",
            title: "More stars",
            topic: .training,
            beats: [
                LessonBeat("A god at the top of its level is not finished — it is ready."),
                LessonBeat("Evolution spends other gods of the same grade to add a star, and a star is worth more than any amount of levelling."),
            ],
            unlock: { player in player.units.count >= 6 }
        ),
        Lesson(
            id: "labyrinth",
            title: "Under the island",
            topic: .places,
            beats: [
                LessonBeat("There is a way down. Three dungeons, ten floors each, and every run gives up a relic of that dungeon's own sets.", .urging),
                LessonBeat("The Halls of Essence are down there too. Essence is what an awakening costs."),
            ],
            unlock: { player in (player.campaignProgress["duat_1"] ?? 0) >= 4 }
        ),
        Lesson(
            id: "arena",
            title: "Other summoners",
            topic: .places,
            beats: [
                LessonBeat("The arena puts your four against somebody else's. They do not play; their gods do."),
                LessonBeat("Win and you take rank. Rank pays laurels, and laurels buy things coin cannot."),
            ],
            unlock: { player in player.level >= 5 }
        ),
        Lesson(
            id: "tiers",
            title: "Hard, and worse",
            topic: .fighting,
            beats: [
                LessonBeat("Every chapter you have finished will play again, harder."),
                LessonBeat("Hard fields the same creatures a grade up and pays nearly twice. Hell is beyond that, and every stage of it drops a six-star relic.", .urging),
            ],
            unlock: { player in player.level >= 12 }
        ),
        Lesson(
            id: "night_market",
            title: "The Night Market",
            topic: .economy,
            beats: [
                LessonBeat("There is a market that keeps no fixed stock. What is on the table changes on the hour, and when it changes it is gone."),
                LessonBeat("Drachma buys most of it, which is the only place your coin is worth anything but relic dust."),
                LessonBeat("Divinity buys another look, if you cannot wait an hour. It costs more each time you ask.", .urging),
            ],
            unlock: { player in (player.campaignProgress["duat_1"] ?? 0) >= 3 }
        ),
    ]

    /// Written into the read set when the player skips: the opening stops,
    /// its carets with it, and the pop-ins carry on — the genre's guide does
    /// not fall silent for ever because somebody skipped the first eight
    /// minutes, and every skipped lesson is still in the library.
    static let openingSkipped = "opening_skipped"

    static let all: [Lesson] = opening + systems

    static func lesson(_ id: String) -> Lesson? { all.first { $0.id == id } }

    /// The lesson she should be giving, or nil for silence: the first step of
    /// the opening whose goal is unmet, and after that the first pop-in that
    /// has unlocked and not been read.
    static func current(for player: Player, seen: Set<String>) -> Lesson? {
        guard !seen.contains(openingSkipped) else {
            return systems.first { !seen.contains($0.id) && $0.unlock(player) }
        }
        for lesson in opening where !seen.contains(lesson.id) {
            if let goal = lesson.goal, goal(player) { continue }
            return lesson
        }
        // A step whose goal is still unmet keeps its caret up even after its
        // words have been read.
        for lesson in opening where seen.contains(lesson.id) {
            if let goal = lesson.goal, !goal(player) { return lesson }
        }
        return systems.first { !seen.contains($0.id) && $0.unlock(player) }
    }
}
