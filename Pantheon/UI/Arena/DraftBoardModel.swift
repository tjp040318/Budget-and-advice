import SwiftUI

// MARK: - The Draft Arena's board model (2026-09-23; Docs/DRAFT.md)
//
// The screen's state: the draft (`DraftSession`, a value), the player's
// picks this turn before they are locked in, the strike he is about to make,
// the filters, and the words of the rival's last decision. The rival takes
// its picks on its own clock, a beat apart, so the board shows each one land.

/// How long the rival weighs a pick, and how long the coin spins before the
/// first pick opens by itself. Globals, so a task's closure reads them
/// without touching the model's actor.
private let draftRivalThinks: UInt64 = 850_000_000
private let draftCoinSettles: UInt64 = 2_600_000_000

/// What the board shows after a fought bout, read back off the save: the
/// bout was settled inside the battle (`BattleViewModel.finish`), so the
/// board compares the record from before the fight with the record after.
struct DraftBoutReport: Equatable {
    var outcome: BattleOutcome
    var ratingBefore: Int
    var ratingAfter: Int
    var laurels: Int
    var tierBefore: DraftTier
    var tierAfter: DraftTier
    var paidBoutsLeft: Int

    var delta: Int { ratingAfter - ratingBefore }
    var promoted: Bool { tierAfter.rawValue > tierBefore.rawValue }
}

@MainActor
final class DraftBoardModel: ObservableObject {

    @Published private(set) var session: DraftSession?
    @Published private(set) var isBuilding = false
    /// The box was read and holds fewer than five different monsters.
    @Published private(set) var isLocked = false
    /// The player's picks this turn, before Lock in.
    @Published var pending: [UUID] = []
    /// The unit whose words stand in the lock bar.
    @Published var inspected: UUID?
    /// The rival unit the player is about to strike.
    @Published var banTarget: UUID?
    @Published var elementFilter: Element?
    @Published var roleFilter: DraftRole?
    @Published private(set) var report: DraftBoutReport?
    /// The rival's latest decision, in words.
    @Published private(set) var rivalLine: String?

    /// The CI tour's frozen board: nothing moves by itself.
    let tourStage: DraftTourStage?

    /// Bumped by every build and every scheduled beat, so a beat from an
    /// earlier draft does nothing.
    private var ticket = 0
    /// The record and the laurels when the fight began.
    private var recordBefore: DraftRecord?
    private var laurelsBefore = 0

    init(tourStage: DraftTourStage? = nil) {
        self.tourStage = tourStage
    }

    // MARK: Building

    /// Builds the draft the first time the board appears; later appearances
    /// (the battle's cover closing) keep it.
    func prepare(store: GameStore) {
        guard session == nil, !isBuilding, !isLocked else { return }
        build(store: store)
    }

    /// A new draft against the rival that waits for the player: the same one
    /// until a bout is fought (`DraftService.sessionSeed`). Built off the
    /// main thread — a box of fourteen, searched for its strength.
    func build(store: GameStore) {
        store.refreshDraft()
        let player = store.player
        let stage = tourStage
        let now = Date()
        ticket += 1
        let mine = ticket
        isBuilding = true
        isLocked = false
        session = nil
        report = nil
        pending = []
        banTarget = nil
        inspected = nil
        rivalLine = nil
        Task.detached(priority: .userInitiated) { [weak self] in
            let built: DraftSession?
            if let stage {
                built = DraftService.scriptedSession(player: player, stage: stage)
            } else {
                built = DraftService.makeSession(player: player, seed: DraftService.sessionSeed(player: player, now: now))
            }
            await self?.install(built, ticket: mine)
        }
    }

    /// The built draft onto the board — unless a later build has started
    /// since (Draft again tapped twice), whose draft is the one to show.
    private func install(_ built: DraftSession?, ticket issued: Int) {
        guard issued == ticket else { return }
        isBuilding = false
        guard let built else {
            isLocked = true
            return
        }
        session = built
        if let stage = tourStage {
            presetTour(stage, on: built)
        } else if built.phase == .toss {
            landCoin()
        }
    }

    /// The tour's three frames: the heuristic's own next pick for the player
    /// chosen and waiting on Lock in; the player's best strike marked; the
    /// bans landed with the rival's words.
    private func presetTour(_ stage: DraftTourStage, on built: DraftSession) {
        switch stage {
        case .picks:
            if let next = DraftService.choice(for: .player, in: built) {
                pending = [next.unitID]
                inspected = next.unitID
            }
            if let last = built.picks.last(where: { $0.side == .rival }) {
                rivalLine = DraftWords.pickLine(last, in: built)
            }
        case .bans:
            banTarget = DraftService.banChoice(against: .rival, in: built)?.unitID
            rivalLine = DraftWords.sealedLine(built)
        case .leaders:
            rivalLine = DraftWords.strikeLine(built)
        }
    }

    // MARK: The coin and the rival's clock

    private func landCoin() {
        ticket += 1
        let mine = ticket
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: draftCoinSettles)
            guard let self, self.ticket == mine else { return }
            self.beginPicking()
        }
    }

    /// The coin has landed: the first pick opens (the Begin plate, or the
    /// coin's own clock).
    func beginPicking() {
        guard var current = session, current.phase == .toss else { return }
        current.beginPicking()
        withAnimation(.easeOut(duration: 0.25)) {
            session = current
        }
        scheduleRival()
    }

    private func scheduleRival() {
        guard tourStage == nil, let current = session, current.sideToPick == .rival else { return }
        ticket += 1
        let mine = ticket
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: draftRivalThinks)
            guard let self, self.ticket == mine else { return }
            self.rivalStep()
        }
    }

    private func rivalStep() {
        guard var current = session, current.sideToPick == .rival else { return }
        guard let made = current.rivalPicks() else { return }
        rivalLine = DraftWords.pickLine(made, in: current)
        withAnimation(Motion.select) {
            session = current
        }
        Juice.haptic(.light)
        AudioLibrary.shared.play(.uiTap, volume: 0.6)
        scheduleRival()
    }

    // MARK: The player's hand

    /// A tap on the roster: the unit's words in the lock bar, and on the
    /// player's turn a pick chosen or unchosen. A full turn swaps its last
    /// choice for the new one.
    func tap(_ unitID: UUID) {
        guard let current = session else { return }
        inspected = unitID
        guard current.sideToPick == .player, let unit = current.unit(unitID) else { return }
        if let index = pending.firstIndex(of: unitID) {
            withAnimation(.easeOut(duration: 0.2)) {
                _ = pending.remove(at: index)
            }
            return
        }
        guard current.canPick(unitID, for: .player) else { return }
        let twin = pending.contains { chosen in current.unit(chosen)?.blueprint.id == unit.blueprint.id }
        guard !twin else { return }
        if pending.count >= current.picksLeftInTurn, !pending.isEmpty {
            pending.removeLast()
        }
        withAnimation(Motion.select) {
            pending.append(unitID)
        }
        // The roster's faces wear the quiet press, so a pick ticks here.
        Juice.haptic(.light)
    }

    var canLockIn: Bool {
        guard let current = session, current.sideToPick == .player else { return false }
        return pending.count == current.picksLeftInTurn
    }

    /// The turn's picks go in; the rival's clock starts.
    func lockIn() {
        guard var current = session, current.sideToPick == .player,
              pending.count == current.picksLeftInTurn else { return }
        for id in pending {
            current.pick(id)
        }
        pending = []
        inspected = nil
        rivalLine = current.phase == .banning ? DraftWords.sealedLine(current) : nil
        withAnimation(Motion.select) {
            session = current
        }
        scheduleRival()
    }

    /// Marks, or unmarks, the rival unit to strike.
    func strike(_ rivalUnitID: UUID) {
        guard let current = session, current.phase == .banning,
              current.picked(.rival).contains(where: { $0.id == rivalUnitID }) else { return }
        // No tick of its own: the strike card's press and the column's
        // slot (`DraftSlotRow`) each tick as the finger lands.
        withAnimation(.easeOut(duration: 0.2)) {
            banTarget = banTarget == rivalUnitID ? nil : rivalUnitID
        }
    }

    /// Both strikes land: the rival's, sealed at the tenth pick, and the
    /// player's. The leaders are crowned.
    func commitBan() {
        guard var current = session, let target = banTarget else { return }
        guard current.ban(target) else { return }
        banTarget = nil
        rivalLine = DraftWords.strikeLine(current)
        withAnimation(Motion.panel) {
            session = current
        }
        Juice.haptic(.heavy)
    }

    func crown(_ unitID: UUID) {
        guard var current = session else { return }
        guard current.crown(unitID) else { return }
        // No tick of its own, as `strike`.
        withAnimation(.easeOut(duration: 0.2)) {
            session = current
        }
    }

    /// A tap on a place in either column: a strike while the bans are open, a
    /// crown while the leaders are, else the unit's words.
    func tapSlot(_ unitID: UUID) {
        guard let current = session else { return }
        switch current.phase {
        case .banning: strike(unitID)
        case .leaders: crown(unitID)
        case .toss, .picking: inspected = unitID
        }
    }

    // MARK: The roster

    func roster(in current: DraftSession) -> [ResolvedUnit] {
        current.playerBox.filter { unit in
            (elementFilter == nil || unit.element == elementFilter)
                && (roleFilter == nil || DraftRole(unit.role) == roleFilter)
        }
    }

    func tileState(_ unit: ResolvedUnit, in current: DraftSession) -> DraftTileState {
        if let index = pending.firstIndex(of: unit.id) { return .pending(index + 1) }
        if current.pick(of: unit.id) != nil { return .picked }
        if current.picked(.player).contains(where: { $0.blueprint.id == unit.blueprint.id }) { return .twin }
        let chosenTwin = pending.contains { chosen in current.unit(chosen)?.blueprint.id == unit.blueprint.id }
        if chosenTwin { return .twin }
        return current.sideToPick == .player ? .open : .waiting
    }

    /// A side's five places as the column draws them.
    func slots(_ side: DraftSide, in current: DraftSession) -> [DraftSlotModel] {
        let order = current.order
        let numbers = order.indices.filter { order[$0] == side }.map { $0 + 1 }
        let made = current.picked(side)
        let chosen: [ResolvedUnit] = side == .player ? pending.compactMap { current.unit($0) } : []
        let onClock = current.sideToPick == side ? current.picksLeftInTurn : 0
        let struck: UUID? = current.phase == .leaders ? current.struck(side) : nil
        let target: UUID? = side == .rival && current.phase == .banning ? banTarget : nil
        let crowned: UUID? = current.phase == .leaders ? current.leader(side) : nil
        let tappable = (side == .rival && current.phase == .banning) || (side == .player && current.phase == .leaders)
        var places: [DraftSlotModel] = []
        for index in 0..<DraftService.picksPerSide {
            let number = index < numbers.count ? numbers[index] : index + 1
            if index < made.count {
                let unit = made[index]
                places.append(DraftSlotModel(
                    index: index, pickNumber: number, unit: unit,
                    isPending: false, isOnClock: false,
                    isStruck: unit.id == struck, isStrikeTarget: unit.id == target,
                    isLeader: unit.id == crowned, isTappable: tappable && unit.id != struck
                ))
                continue
            }
            let waiting = index - made.count
            if waiting < chosen.count {
                places.append(DraftSlotModel(
                    index: index, pickNumber: number, unit: chosen[waiting],
                    isPending: true, isOnClock: true,
                    isStruck: false, isStrikeTarget: false,
                    isLeader: false, isTappable: false
                ))
                continue
            }
            places.append(DraftSlotModel(
                index: index, pickNumber: number, unit: nil,
                isPending: false, isOnClock: waiting < onClock,
                isStruck: false, isStrikeTarget: false,
                isLeader: false, isTappable: false
            ))
        }
        return places
    }

    // MARK: The fight

    /// The fight's engine and bout, and the record as it stood, to read the
    /// bout back when the battle's cover closes.
    func beginFight(store: GameStore) -> (engine: BattleEngine, bout: DraftBout)? {
        guard let current = session, let made = store.startDraftBout(current) else { return nil }
        recordBefore = store.draftRecord
        laurelsBefore = store.player.wallet.laurels
        return made
    }

    /// The battle's cover has closed: if a bout was settled, the report.
    func concludeFight(store: GameStore) {
        guard let held = recordBefore else { return }
        recordBefore = nil
        let after = store.draftRecord
        guard after.bouts > held.bouts else { return }
        let won = after.wins > held.wins
        let paid = max(0, store.player.wallet.laurels - laurelsBefore)
        withAnimation(.easeOut(duration: 0.3)) {
            report = DraftBoutReport(
                outcome: won ? .victory : .defeat,
                ratingBefore: held.rating,
                ratingAfter: after.rating,
                laurels: paid,
                tierBefore: held.tier,
                tierAfter: after.tier,
                paidBoutsLeft: max(0, DraftService.paidBoutsPerDay - after.paidToday)
            )
        }
    }

    /// Another draft, against the next rival.
    func again(store: GameStore) {
        build(store: store)
    }
}

// MARK: - The board's words

/// Every sentence the board says, written once: the phase's prompt, the
/// rival's reasons, a strike's advice, a unit's matchups.
enum DraftWords {

    static func prompt(_ session: DraftSession, pending: Int, report: DraftBoutReport?) -> String {
        if report != nil { return "The bout is over" }
        switch session.phase {
        case .toss:
            return "The coin is in the air"
        case .picking:
            guard let side = session.sideToPick else { return "The picks are in" }
            if side == .rival { return "\(session.rival.name) is choosing" }
            let left = max(0, session.picksLeftInTurn - pending)
            if left == 0 { return session.picksLeftInTurn > 1 ? "Lock in your picks" : "Lock in your pick" }
            return left == 1 ? "Your turn · choose one" : "Your turn · choose two"
        case .banning:
            return "Strike one of their five"
        case .leaders:
            return "Crown your leader"
        }
    }

    /// "Theron takes Sekhmet: Ember beats your Perseus."
    static func pickLine(_ pick: DraftPick, in session: DraftSession) -> String {
        guard let unit = session.unit(pick.unitID) else { return "" }
        let name = DraftService.captionName(unit)
        let rival = session.rival.name
        switch pick.reason {
        case .counters(let names)?:
            return "\(rival) takes \(name): \(unit.element.displayName) beats your \(list(names))."
        case .healer?:
            return "\(rival) takes \(name): they had no healer."
        case .tank?:
            return "\(rival) takes \(name): they had no one in front."
        case .leader?:
            return "\(rival) takes \(name) to lead."
        case .strongest?:
            return "\(rival) takes \(name), the strongest they had left."
        case nil:
            return "\(rival) takes \(name)."
        }
    }

    static func sealedLine(_ session: DraftSession) -> String {
        "\(session.rival.name) has struck one of yours in secret. Strike one of theirs and both land together."
    }

    /// "Theron strikes your Zeus: it beats their Sekhmet and Horus."
    static func strikeLine(_ session: DraftSession) -> String? {
        guard let id = session.rivalBan, let unit = session.unit(id) else { return nil }
        let name = DraftService.captionName(unit)
        let rival = session.rival.name
        switch session.rivalBanReason {
        case .counters(let names)?:
            return "\(rival) strikes your \(name): it beats their \(list(names))."
        case .healer?:
            return "\(rival) strikes your \(name), your only healer."
        case .tank?, .leader?, .strongest?, nil:
            return "\(rival) strikes your \(name), your strongest."
        }
    }

    /// The rival's crown and what it does.
    static func leaderLine(_ session: DraftSession) -> String {
        guard let id = session.rivalLeader, let unit = session.unit(id) else { return "" }
        let name = DraftService.captionName(unit)
        if let skill = DraftService.arenaLeaderSkill(unit) {
            return "\(session.rival.name) crowns \(name). \(skill.description)"
        }
        return "\(session.rival.name) crowns \(name), who leads nothing in the arena."
    }

    /// The player's crown and what it does.
    static func crownLine(_ unit: ResolvedUnit?) -> String {
        guard let unit else { return "Tap one of your four to crown it." }
        let name = DraftService.captionName(unit)
        if let skill = DraftService.arenaLeaderSkill(unit) {
            return "\(name) leads. \(skill.description)"
        }
        return "\(name) leads, with no leader skill in the arena. Any of the four can."
    }

    /// Under a rival unit the player may strike: why it matters.
    static func threatNote(_ unit: ResolvedUnit, yours: [ResolvedUnit], theirs: [ResolvedUnit]) -> String {
        let beats = yours.filter { DraftService.counters(unit.element, $0.element) }.count
        if beats >= 2 { return "Beats \(beats) of yours" }
        if beats == 1 { return "Beats one of yours" }
        if DraftService.heals(unit) { return "Their healer" }
        if let strongest = theirs.max(by: { $0.power < $1.power }), strongest.id == unit.id { return "Their strongest" }
        return DraftRole(unit.role).displayName
    }

    /// A unit's role and how its element meets the rival's picks.
    static func matchupNote(_ unit: ResolvedUnit, against theirs: [ResolvedUnit]) -> String {
        let role = DraftRole(unit.role).displayName
        guard !theirs.isEmpty else { return "\(role) · their picks are still to come" }
        let beats = theirs.filter { DraftService.counters(unit.element, $0.element) }.map { DraftService.captionName($0) }
        let beatenBy = theirs.filter { DraftService.counters($0.element, unit.element) }.map { DraftService.captionName($0) }
        var parts = [role]
        if !beats.isEmpty { parts.append("beats \(list(beats))") }
        if !beatenBy.isEmpty { parts.append("beaten by \(list(beatenBy))") }
        if beats.isEmpty && beatenBy.isEmpty { parts.append("even with their picks") }
        return parts.joined(separator: " · ")
    }

    /// "A", "A and B", "A, B and C".
    static func list(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
    }
}
