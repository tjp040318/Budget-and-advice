import SwiftUI

// MARK: - The Hidden Shrines, in the Labyrinth (2026-09-23; Docs/SHRINES.md)
//
// The Labyrinth's fifth room, built as the Titans' is: a PLACE — the chosen
// form's pantheon painted full-bleed under the dark scrims, a glass rail down
// the left and the room beside it. The rail holds the shrines open now, each
// with its clock, and the pieces held of every other form; the room holds the
// chosen one's face, its pieces as a meter with the next win's ghost, what a
// win pays as tiles, and the deck: Fight, Auto for the wins the unit still
// needs, and Summon once enough are held — which plays the scroll's own
// reveal. The same room opens over a dungeon's room when a fight there found
// a shrine (`ShrineNoticeCard`, `ShrineRoomScreen`).
//
// Sized for an iPhone 16 Pro in landscape inside a Labyrinth cover: 750 × 329
// points under the strip. The rail is the Titans' 222; the room's 502 inside
// its padding hold a 96-point face column, a glass plate of five 44-point
// tiles (five names of 59 and four gaps of 10, 337 of its 376), and a deck of
// two buttons.

/// A form as the face every place draws: the blueprint at level 1 with
/// nothing worn, which is what a summon from pieces hands over.
private func shrineFace(_ blueprint: UnitBlueprint) -> ResolvedUnit {
    ProgressionService.resolve(Unit(blueprint: blueprint), blueprint: blueprint, equipped: [])
}

/// The name before any epithet.
private func shrineName(_ name: String) -> String {
    name.split(separator: ",", maxSplits: 1).first.map { String($0) } ?? name
}

/// The rules in words, off the constants so they cannot drift: the room's ?
/// and the empty room both say them.
private func shrineRules() -> String {
    let chance = String(format: "%.1f%%", ShrineService.discoveryPerEnergy * 100)
    let prices = ShrineService.piecesPerSummon.keys.sorted()
        .map { "\(ShrineService.piecesPerSummon[$0] ?? 0) a \($0)★" }
        .joined(separator: ", ")
    return "A win on any Labyrinth level or Hall floor can find a hidden shrine — \(chance) for each point of "
        + "energy the run cost. It stays open \(ShrineService.windowMinutes) minutes and is keyed to one form, "
        + "never Radiance or Umbra. A win there pays \(ShrineService.piecesPerRun) pieces, one more half the time; "
        + "\(prices) summon it. Pieces never expire, and half the time a new shrine is a form you have begun."
}

/// One entry on the shrines' rail: a shrine open now, the pieces held of a
/// form whose shrine is not, a section's name, or the quiet row that says
/// none is open. Private to this file; the name is unique in the tree.
private enum ShrineRailEntry: Identifiable {
    case shrine(HiddenShrine)
    case stock(ShrineStock)
    case heading(String)
    case quiet

    var id: String {
        switch self {
        case .shrine(let shrine): return ShrineRailEntry.shrineKey(shrine.id)
        case .stock(let stock): return "stock-" + stock.id
        case .heading(let title): return "heading-" + title
        case .quiet: return "quiet"
        }
    }

    var isPickable: Bool {
        switch self {
        case .shrine, .stock: return true
        case .heading, .quiet: return false
        }
    }

    static func shrineKey(_ id: UUID) -> String { "shrine-" + id.uuidString }
}

/// What the last fight in a shrine paid, for the card over the room.
private struct ShrineReceipt: Identifiable, Equatable {
    let id = UUID()
    let blueprintID: String
    let gained: Int
    let held: Int
}

/// The Labyrinth's Shrines wing, and the room `ShrineRoomScreen` opens.
struct ShrinesWing: View {
    @EnvironmentObject private var store: GameStore

    /// The rail entry the room shows; nil reads as the first shrine open, or
    /// the first stock.
    @State private var selectedID: String?
    @State private var battle: BattleContext?
    @State private var engine: BattleEngine?
    @State private var repeatRuns = 1
    @State private var reveal: SummonResult?
    @State private var showTeamPicker = false
    @State private var receipt: ShrineReceipt?
    /// The form a fight is for and its pieces before it, so the room can say
    /// what the fight paid when it comes back.
    @State private var fightingForm: String?
    @State private var piecesBefore = 0
    /// Moved when the soonest shrine closes, so the room redraws without it.
    @State private var clock = Date()

    /// `focus` opens the room on that shrine: the notice card's "Enter".
    init(focus: UUID? = nil) {
        _selectedID = State(initialValue: focus.map { ShrineRailEntry.shrineKey($0) })
    }

    /// The Titans' rail width: a name on two lines of Cinzel at 13 beside a
    /// 40-point face, the count and the clock under it.
    private static let railWidth: CGFloat = 222

    /// The strip's subtitle for the Labyrinth's Shrines wing and the room's
    /// own screen: at most 110 points of Manrope at 11 ("1 open · an hour
    /// each"), inside the 126 a five-segment strip leaves with a veteran's
    /// wallet on an iPhone 16 Pro.
    static func subtitle(player: Player, now: Date = Date()) -> String {
        let open = ShrineService.openShrines(player: player, at: now).count
        let held = ShrineService.stocks(player: player).count
        if open > 0 { return held > 0 ? "\(open) open · \(held) held" : "\(open) open · an hour each" }
        return held > 0 ? "None open · \(held) held" : "Hidden · an hour each"
    }

    var body: some View {
        let now = max(clock, Date())
        let open = ShrineService.openShrines(player: store.player, at: now)
        let stocks = ShrineService.stocks(player: store.player)
        let entries = railEntries(open: open, stocks: stocks)
        let chosen = chosenEntry(entries)
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ShrineRailHead(title: "Shrines")
                WholeRowRail(width: Self.railWidth, items: entries, focus: chosen?.id) { entry in
                    railRow(entry, isOn: entry.id == chosen?.id)
                }
            }
            .frame(width: Self.railWidth)
            room(chosen, now: now)
                .id(chosen?.id ?? "quiet")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { ground(chosen) }
        .overlay(alignment: .bottom) {
            if let receipt {
                receiptCard(receipt)
                    .padding(.bottom, PrimaryButton.height + 20)
                    .transition(.opacity)
            }
        }
        .task(id: receipt?.id) {
            guard receipt != nil else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation(.easeOut(duration: 0.3)) { receipt = nil }
        }
        .task(id: open.first?.expiresAt) {
            // Redraw the moment the soonest shrine closes, so its room and
            // its Fight go with it rather than on the next tap.
            guard let closes = open.first?.expiresAt else { return }
            let wait: Double = max(0, closes.timeIntervalSinceNow) + 0.5
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            clock = Date()
        }
        .sheet(isPresented: $showTeamPicker) {
            TeamPickerView(slot: .campaign, maxSize: 5)
                .environmentObject(store)
        }
        .fullScreenCover(item: $battle, onDismiss: settleFight) { context in
            battleScreen(context)
        }
        .background {
            Color.clear
                .fullScreenCover(item: $reveal) { result in
                    // The scroll's own reveal, its circle lit in the form's
                    // element: the element's scroll is the one whose light
                    // the pieces carry.
                    SummonRevealView(results: [result], scroll: DungeonDatabase.scroll(for: result.blueprint.element)) {
                        reveal = nil
                    }
                }
        }
    }

    // MARK: - The rail

    /// The shrines open now, soonest to close first, then the pieces held of
    /// every form whose shrine is not open under a label of their own. A
    /// form with an open shrine shows its pieces on the shrine's row.
    private func railEntries(open: [HiddenShrine], stocks: [ShrineStock]) -> [ShrineRailEntry] {
        var list: [ShrineRailEntry] = open.map { ShrineRailEntry.shrine($0) }
        if open.isEmpty { list.append(.quiet) }
        let openForms = Set(open.map { $0.blueprintID })
        let loose = stocks.filter { !openForms.contains($0.id) }
        if !loose.isEmpty {
            list.append(.heading("Pieces held"))
            list += loose.map { ShrineRailEntry.stock($0) }
        }
        return list
    }

    private func chosenEntry(_ entries: [ShrineRailEntry]) -> ShrineRailEntry? {
        let pickable = entries.filter { $0.isPickable }
        return pickable.first { $0.id == selectedID } ?? pickable.first
    }

    @ViewBuilder
    private func railRow(_ entry: ShrineRailEntry, isOn: Bool) -> some View {
        switch entry {
        case .shrine(let shrine):
            if let blueprint = UnitDatabase.blueprint(shrine.blueprintID) {
                let held = ShrineService.pieces(of: blueprint.id, player: store.player)
                let price = ShrineService.price(of: blueprint)
                railButton(entry, isOn: isOn, label: "\(shrineName(blueprint.name)), shrine open, \(held) of \(price) pieces") {
                    HStack(spacing: 8) {
                        UnitPortraitTile(unit: shrineFace(blueprint), size: 40, showsLevel: false)
                        VStack(alignment: .leading, spacing: 2) {
                            rowName(blueprint, isOn: isOn)
                            HStack(spacing: 6) {
                                Text("\(held)/\(price)")
                                    .font(Theme.numeric(11.5))
                                    .foregroundStyle(held >= price ? Theme.onGlassSuccess : Theme.onGlassDim)
                                    .lineLimit(1)
                                    .fixedSize()
                                ShrineClock(expiresAt: shrine.expiresAt)
                            }
                        }
                        Spacer(minLength: 2)
                    }
                }
            }
        case .stock(let stock):
            railButton(entry, isOn: isOn, label: "\(shrineName(stock.blueprint.name)), \(stock.pieces) of \(stock.price) pieces") {
                HStack(spacing: 8) {
                    UnitPortraitTile(unit: shrineFace(stock.blueprint), size: 40, showsLevel: false)
                    VStack(alignment: .leading, spacing: 3) {
                        rowName(stock.blueprint, isOn: isOn)
                        HStack(spacing: 6) {
                            Text("\(stock.pieces)/\(stock.price)")
                                .font(Theme.numeric(11.5))
                                .foregroundStyle(stock.isReady ? Theme.onGlassSuccess : Theme.onGlassDim)
                                .lineLimit(1)
                                .fixedSize()
                            GlassMeter(value: Double(stock.pieces), maximum: Double(stock.price), height: 4)
                                .frame(width: 44)
                        }
                    }
                    Spacer(minLength: 2)
                    if stock.isReady {
                        Circle()
                            .fill(Color(hex: "#E8BE50"))
                            .frame(width: 9, height: 9)
                            .shadow(color: Color(hex: "#E8BE50").opacity(0.8), radius: 4)
                    }
                }
            }
        case .heading(let title):
            PlaceRailLabel(title)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .quiet:
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.black.opacity(0.35))
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(Theme.onGlassEyebrow)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("None open")
                        .font(Theme.title(13))
                        .foregroundStyle(Theme.onGlass)
                        .lineLimit(1)
                        .fixedSize()
                    Text("A dungeon win finds one")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.onGlassDim)
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(GlassRowPlate(isOn: false))
        }
    }

    /// A row's plate and its tap: picks the entry for the room. (One-letter
    /// generic names, as `BattleView`'s: the checker reads a longer one as a
    /// type nothing declares.)
    private func railButton<L: View>(
        _ entry: ShrineRailEntry,
        isOn: Bool,
        label: String,
        @ViewBuilder content: () -> L
    ) -> some View {
        Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            selectedID = entry.id
        } label: {
            content()
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(GlassRowPlate(isOn: isOn))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// A form's name on the rail, on up to two lines of Cinzel at 13 —
    /// "Terracotta Soldier" takes both — never shrunk, never cut.
    private func rowName(_ blueprint: UnitBlueprint, isOn: Bool) -> some View {
        Text(shrineName(blueprint.name))
            .font(Theme.title(13))
            .foregroundStyle(isOn ? Color(hex: "#FFF1C2") : Theme.onGlass)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - The place

    /// The chosen form's shrine's place — its pantheon's (`ShrineService.home`)
    /// — full-bleed under the dark scrims, with motes in its element's light;
    /// the Hall of Two Truths when nothing is chosen. A background, so it is
    /// exactly the size of the room and never grows the strip's column.
    private func ground(_ entry: ShrineRailEntry?) -> some View {
        let blueprint = form(of: entry)
        let place = blueprint.map { ShrineService.home(of: $0.pantheon) } ?? .hallOfTwoTruths
        return ZStack {
            PlaceBackdrop(painting: place.backdropName, focus: .center)
            PlaceAmbience(shafts: [], motes: 16, moteColor: blueprint?.element.color ?? Theme.gold, seed: 962)
        }
        .allowsHitTesting(false)
    }

    private func form(of entry: ShrineRailEntry?) -> UnitBlueprint? {
        switch entry {
        case .shrine(let shrine)?: return UnitDatabase.blueprint(shrine.blueprintID)
        case .stock(let stock)?: return stock.blueprint
        case .heading?, .quiet?, nil: return nil
        }
    }

    // MARK: - The room

    @ViewBuilder
    private func room(_ entry: ShrineRailEntry?, now: Date) -> some View {
        switch entry {
        case .shrine(let shrine)?:
            if let blueprint = UnitDatabase.blueprint(shrine.blueprintID), let stage = ShrineService.stage(for: shrine) {
                roomFrame {
                    shrineTitle(shrine, blueprint: blueprint)
                } middle: {
                    HStack(alignment: .top, spacing: 10) {
                        faceColumn(blueprint, stage: stage)
                        shrinePlate(shrine, blueprint: blueprint, stage: stage)
                    }
                } deck: {
                    shrineDeck(shrine, blueprint: blueprint, stage: stage, now: now)
                }
            } else {
                quietRoom
            }
        case .stock(let stock)?:
            roomFrame {
                roomTitle(eyebrow: "Pieces held · \(stock.blueprint.naturalStars)★ \(stock.blueprint.element.displayName)",
                          name: stock.blueprint.name)
            } middle: {
                HStack(alignment: .top, spacing: 10) {
                    faceColumn(stock.blueprint, stage: nil)
                    stockPlate(stock)
                }
            } deck: {
                stockDeck(stock)
            }
        case .heading?, .quiet?, nil:
            quietRoom
        }
    }

    /// Every room's frame: the title on the painting's dark top, a middle
    /// that scrolls only if it must, and the deck pinned to the foot.
    private func roomFrame<T: View, M: View, D: View>(
        @ViewBuilder title: () -> T,
        @ViewBuilder middle: () -> M,
        @ViewBuilder deck: () -> D
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            title()
            ScrollView(.vertical, showsIndicators: false) {
                middle()
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)
            deck()
        }
        .padding(.leading, 14)
        .padding(.trailing, ScreenChrome.contentPadding)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The carved name with its eyebrow, and the rules behind the ?.
    private func roomTitle(eyebrow: String, name: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            PlaceTitle(eyebrow: eyebrow, title: shrineName(name), size: 20)
            Spacer(minLength: 6)
            rulesDot
        }
    }

    /// A shrine's title: its clock ticks in the eyebrow, as the Night
    /// Market's does.
    private func shrineTitle(_ shrine: HiddenShrine, blueprint: UnitBlueprint) -> some View {
        HStack(alignment: .center, spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                PlaceTitle(
                    eyebrow: "\(blueprint.element.displayName) shrine · closes in "
                        + ShrineService.countdown(to: shrine.expiresAt, now: context.date),
                    title: shrineName(blueprint.name),
                    size: 20
                )
            }
            Spacer(minLength: 6)
            rulesDot
        }
    }

    private var rulesDot: some View {
        InfoDot(title: "Hidden shrines", seated: true) {
            Text(shrineRules())
                .font(Theme.body(11))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The form standing on the painted floor, what it is, and — for a
    /// shrine — the team's power against the floor it was found on, green
    /// when it meets it and rose when not.
    private func faceColumn(_ blueprint: UnitBlueprint, stage: Stage?) -> some View {
        let power = store.team(store.player.campaignTeam).reduce(0) { $0 + $1.power }
        return VStack(spacing: 5) {
            UnitPortraitTile(unit: shrineFace(blueprint), size: 84, showsLevel: false)
                .background(alignment: .bottom) { ShrineFloorPool() }
            Text("\(blueprint.naturalStars)★ · \(blueprint.element.displayName)")
                .font(Theme.body(11).weight(.bold))
                .foregroundStyle(Theme.onGlassEyebrow)
                .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                .lineLimit(1)
                .fixedSize()
                .padding(.top, 4)
            Text(blueprint.role.displayName)
                .font(Theme.body(11))
                .foregroundStyle(Theme.onGlassDim)
                .lineLimit(1)
                .fixedSize()
            if let stage {
                let strong = power >= stage.recommendedPower
                Text("\(BarWallet.compact(power)) / \(BarWallet.compact(stage.recommendedPower))")
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(strong ? Theme.onGlassSuccess : Theme.onGlassDanger)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityLabel("Team power \(power), the shrine asks \(stage.recommendedPower)")
            }
        }
        .frame(width: 96)
        .padding(.top, 4)
    }

    /// The pieces as a meter with the next win's ghost, what is left, and
    /// what a win pays as tiles: the pieces, the drachma and experience with
    /// today's event in them, the element's essence and the Unknown Scroll.
    private func shrinePlate(_ shrine: HiddenShrine, blueprint: UnitBlueprint, stage: Stage) -> some View {
        let held = ShrineService.pieces(of: blueprint.id, player: store.player)
        let price = ShrineService.price(of: blueprint)
        let boosts = EventCalendar.boosts(for: stage)
        let rewards = stage.rewards
        let low = ShrineService.piecesPerRun
        let essence = "essence_\(blueprint.element.rawValue)_mid"
        let drachma: Int = Int(Double(rewards.drachma) * boosts.drachma)
        let experience: Int = Int(Double(rewards.unitExperience) * boosts.experience)
        return VStack(alignment: .leading, spacing: 7) {
            piecesBlock(held: held, price: price)
            GlassSectionHeader(title: "A win pays", accessory: shrine.wins == 1 ? "1 won" : "\(shrine.wins) won")
            HStack(alignment: .top, spacing: 10) {
                ShrinePieceTile(blueprint: blueprint, amount: "\(low)–\(low + 1)", size: 44)
                RewardTile(key: "drachma", title: "Drachma", amount: "+\(drachma.formatted())", size: 44, onGlass: true)
                RewardTile(key: "unit_exp", title: "Unit EXP", amount: "+\(experience.formatted())", size: 44, onGlass: true)
                RewardTile(key: essence, title: "Mid", amount: percent(ShrineService.essenceChance), size: 44, onGlass: true)
                RewardTile(key: ItemArt.key(scroll: .unknown), title: "Unknown", amount: percent(ShrineService.scrollChance),
                           size: 44, onGlass: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(GlassPlate(radius: Theme.cornerRadius))
    }

    /// The pieces of a form whose shrine is closed, and what brings it back.
    private func stockPlate(_ stock: ShrineStock) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            piecesBlock(held: stock.pieces, price: stock.price)
            GlassSectionHeader(title: "Its shrine")
            Text("Closed. A Labyrinth or Hall win finds shrines, and half of them are a form whose pieces you hold, the nearest to whole the likeliest.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.onGlassDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(GlassPlate(radius: Theme.cornerRadius))
    }

    /// "Pieces 26 / 40", the meter with the ghost of the next win's three,
    /// and the line under it: what is left and about how many wins that is.
    private func piecesBlock(held: Int, price: Int) -> some View {
        let ready = held >= price
        let short = max(0, price - held)
        let perWin: Double = Double(ShrineService.piecesPerRun) + ShrineService.bonusPieceChance
        let wins = Int((Double(short) / perWin).rounded(.up))
        let ghost: Double = Double(min(price, held + ShrineService.piecesPerRun))
        let noun: String = wins == 1 ? "win" : "wins"
        let line: String = ready
            ? "Enough to summon. Wins past it begin the next."
            : "\(short) more to summon — about \(wins) \(noun)."
        return VStack(alignment: .leading, spacing: 6) {
            GlassSectionHeader(
                title: "Pieces",
                accessory: "\(held) / \(price)",
                accessoryTint: ready ? Theme.onGlassSuccess : Theme.onGlassGold
            )
            GlassMeter(value: Double(held), maximum: Double(price), projected: ready ? nil : ghost,
                       tint: ready ? Theme.onGlassSuccess : Theme.gold, height: 6)
            Text(line)
                .font(Theme.body(11))
                .foregroundStyle(ready ? Theme.onGlassSuccess : Theme.onGlassDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func percent(_ chance: Double) -> String {
        "\(Int((chance * 100).rounded()))%"
    }

    // MARK: - The decks

    /// A shrine's deck. Not yet enough pieces: Auto for the wins the unit
    /// still needs (as far as the energy goes, ten at most) beside Fight —
    /// one tap from the rail to the battle. Enough: Summon, the gold one,
    /// with Fight on glass beside it for the next copy. Every reason Fight
    /// is dead is its own title.
    @ViewBuilder
    private func shrineDeck(_ shrine: HiddenShrine, blueprint: UnitBlueprint, stage: Stage, now: Date) -> some View {
        let team = store.team(store.player.campaignTeam)
        let cost = EventCalendar.energyCost(for: stage)
        let energy = store.player.wallet.energy
        let isOpen = shrine.isOpen(at: now)
        let held = ShrineService.pieces(of: blueprint.id, player: store.player)
        let price = ShrineService.price(of: blueprint)
        let ready = held >= price
        let perWin: Double = Double(ShrineService.piecesPerRun) + ShrineService.bonusPieceChance
        let short: Double = Double(max(0, price - held))
        let needed = Int((short / perWin).rounded(.up))
        let affordable = cost > 0 ? energy / cost : 0
        let autoRuns = min(10, needed, affordable)
        let fightWords = Self.fightTitle(isOpen: isOpen, teamIsEmpty: team.isEmpty, energy: energy, cost: cost)
        let fightLive = isOpen && (team.isEmpty || energy >= cost)
        HStack(spacing: 10) {
            if ready {
                PrimaryButton(title: "Summon", systemImage: "sparkles") {
                    summon(blueprint.id)
                }
                .frame(maxWidth: 220)
            }
            Spacer(minLength: 6)
            if !ready, isOpen, !team.isEmpty, autoRuns >= 2 {
                PrimaryButton(title: "Auto ×\(autoRuns)", systemImage: "repeat", style: .glass) {
                    fight(shrine, runs: autoRuns)
                }
                .frame(maxWidth: 150)
                .accessibilityLabel("Fight \(autoRuns) times on auto, \(autoRuns * cost) energy")
            }
            PrimaryButton(
                title: fightWords,
                systemImage: team.isEmpty ? "person.2.fill" : "play.fill",
                isEnabled: fightLive,
                style: fightLive && !ready ? .painted : .glass
            ) {
                if team.isEmpty {
                    showTeamPicker = true
                } else {
                    fight(shrine, runs: 1)
                }
            }
            .frame(maxWidth: 230)
        }
    }

    /// Every reason Fight is dead is its own title: a closed shrine, an
    /// empty team (which opens the picker), a short wallet.
    private static func fightTitle(isOpen: Bool, teamIsEmpty: Bool, energy: Int, cost: Int) -> String {
        if !isOpen { return "Closed" }
        if teamIsEmpty { return "Choose a team" }
        if energy < cost { return "Needs \(cost) energy" }
        return "Fight — \(cost) energy"
    }

    /// A closed form's deck: Summon when enough are held, otherwise what is
    /// still to find on dim glass — readable either way.
    private func stockDeck(_ stock: ShrineStock) -> some View {
        let short: Int = stock.price - stock.pieces
        let title: String = stock.isReady ? "Summon" : "\(short) more pieces"
        return HStack(spacing: 10) {
            Spacer(minLength: 6)
            PrimaryButton(
                title: title,
                systemImage: stock.isReady ? "sparkles" : "puzzlepiece.fill",
                isEnabled: stock.isReady,
                style: stock.isReady ? .painted : .glass
            ) {
                summon(stock.blueprint.id)
            }
            .frame(maxWidth: 260)
        }
    }

    // MARK: - No shrine at all

    /// Nothing open and nothing held: the room says how a shrine is found
    /// and what it pays, read off the rules.
    private var quietRoom: some View {
        roomFrame {
            HStack(alignment: .center, spacing: 10) {
                PlaceTitle(eyebrow: "The Labyrinth keeps its secrets", title: "No shrine is open", size: 20)
                Spacer(minLength: 6)
            }
        } middle: {
            VStack(alignment: .leading, spacing: 7) {
                GlassSectionHeader(title: "How one is found")
                Text(shrineRules())
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.onGlass)
                    .fixedSize(horizontal: false, vertical: true)
                GlassSectionHeader(title: "Where it stands")
                Text("Each form's shrine stands in its own pantheon's place, and fields the form itself — three waves of it, the last its boss — at the depth it was found.")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.onGlassDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(GlassPlate(radius: Theme.cornerRadius))
        } deck: {
            EmptyView()
        }
    }

    // MARK: - What a fight paid

    private func receiptCard(_ receipt: ShrineReceipt) -> some View {
        let blueprint = UnitDatabase.blueprint(receipt.blueprintID)
        let price = blueprint.map { ShrineService.price(of: $0) } ?? 0
        let ready = receipt.held >= price
        let togo: Int = price - receipt.held
        let standing: String = ready
            ? "\(receipt.held) / \(price) · ready to summon"
            : "\(receipt.held) / \(price) · \(togo) to go"
        return HStack(spacing: 12) {
            if let blueprint {
                ShrinePieceTile(blueprint: blueprint, amount: "+\(receipt.gained)", size: 48, title: nil)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("THE SHRINE PAID")
                    .font(Theme.title(13))
                    .tracking(1.4)
                    .carved(glow: false)
                    .lineLimit(1)
                    .fixedSize()
                Text(blueprint.map { shrineName($0.name) } ?? receipt.blueprintID)
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(Theme.onGlass)
                    .lineLimit(1)
                    .fixedSize()
                Text(standing)
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(ready ? Theme.onGlassSuccess : Theme.onGlassDim)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(GlassPlate(radius: 12, opacity: 0.88))
        .onTapGesture {
            withAnimation(.easeOut(duration: 0.2)) { self.receipt = nil }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Doing things

    private func fight(_ shrine: HiddenShrine, runs: Int) {
        guard let start = store.startShrineBattle(shrine) else { return }
        Juice.haptic(.light)
        fightingForm = shrine.blueprintID
        piecesBefore = ShrineService.pieces(of: shrine.blueprintID, player: store.player)
        repeatRuns = max(1, runs)
        engine = start.engine
        battle = .campaign(start.stage)
    }

    /// The battle cover closed: what the fight (or the auto session) paid
    /// stands over the room for a few seconds.
    private func settleFight() {
        engine = nil
        guard let form = fightingForm else { return }
        fightingForm = nil
        let held = ShrineService.pieces(of: form, player: store.player)
        let gained = held - piecesBefore
        guard gained > 0 else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            receipt = ShrineReceipt(blueprintID: form, gained: gained, held: held)
        }
    }

    private func summon(_ blueprintID: String) {
        guard let result = store.summonFromPieces(blueprintID) else { return }
        AudioLibrary.shared.play(.uiConfirm)
        Juice.haptic(.medium)
        reveal = result
    }

    /// A shrine fight is a campaign battle: the same view model, the same
    /// result panel, auto-repeat when Auto asked for it, and
    /// `GameStore.finishCampaignBattle` pays each win's pieces.
    @ViewBuilder
    private func battleScreen(_ context: BattleContext) -> some View {
        if let engine {
            BattleView(model: BattleViewModel(engine: engine, context: context, store: store, repeatCount: repeatRuns))
                .environmentObject(store)
        } else {
            Theme.surface
                .ignoresSafeArea()
                .onAppear { battle = nil }
        }
    }
}

// MARK: - The room on its own

/// The shrines' room as its own screen, over a dungeon's room: what the
/// notice card's "Enter the shrine" opens, on that shrine.
struct ShrineRoomScreen: View {
    let focus: UUID?

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GameScreen("Hidden Shrines", subtitle: ShrinesWing.subtitle(player: store.player), dismiss: { dismiss() }) {
                BarWallet(wallet: store.player.wallet)
            } content: {
                ShrinesWing(focus: focus)
            }
        }
    }
}

// MARK: - A shrine has opened

/// The genre's "Secret Dungeon discovered!": a card over the dungeon's room
/// when the fight (or the sweep) that just came back found a shrine — the
/// form's face, what it is, its clock, what it pays, and the door. "Later"
/// leaves it in the Labyrinth's Shrines wing for the rest of its hour.
struct ShrineNoticeCard: View {
    let shrine: HiddenShrine
    let onEnter: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
            if let blueprint = UnitDatabase.blueprint(shrine.blueprintID) {
                card(blueprint)
            }
        }
        .transition(.opacity)
    }

    private func card(_ blueprint: UnitBlueprint) -> some View {
        let price = ShrineService.price(of: blueprint)
        let low = ShrineService.piecesPerRun
        return VStack(spacing: 12) {
            Text("A HIDDEN SHRINE HAS OPENED")
                .font(Theme.title(13))
                .tracking(2.0)
                .foregroundStyle(Theme.onGlassEyebrow)
                .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                .lineLimit(1)
                .fixedSize()
            HStack(alignment: .center, spacing: 14) {
                UnitPortraitTile(unit: shrineFace(blueprint), size: 84, showsLevel: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text(shrineName(blueprint.name).uppercased())
                        .font(Theme.display(22))
                        .carved()
                        .lineLimit(1)
                        .minimumScaleFactor(Theme.titleFloor / 22)
                    Text("\(blueprint.naturalStars)★ · \(blueprint.element.displayName) · \(blueprint.role.displayName)")
                        .font(Theme.body(11).weight(.bold))
                        .foregroundStyle(Theme.onGlassEyebrow)
                        .lineLimit(1)
                        .fixedSize()
                    ShrineClock(expiresAt: shrine.expiresAt, prefix: "Closes in ")
                    Text("Every win pays \(low)–\(low + 1) of its pieces; \(price) summon it.")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.onGlassDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                PrimaryButton(title: "Later", systemImage: "clock", style: .glass) {
                    onClose()
                }
                .frame(maxWidth: 150)
                PrimaryButton(title: "Enter the shrine", systemImage: "sparkles") {
                    onEnter()
                }
                .frame(maxWidth: 250)
            }
        }
        .padding(16)
        .frame(width: 440)
        .background(GlassPlate(radius: 16, opacity: 0.9))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - The small parts

/// A shrine's clock, ticking once a second: an hourglass and "42:18", rose
/// once the hour is out.
struct ShrineClock: View {
    let expiresAt: Date
    var prefix: String = ""
    var tint: Color = Theme.onGlassEyebrow

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let open = expiresAt > context.date
            HStack(spacing: 3) {
                Image(systemName: "hourglass")
                    .font(.system(size: 10, weight: .bold))
                Text(prefix + ShrineService.countdown(to: expiresAt, now: context.date))
                    .font(Theme.numeric(11.5))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(open ? tint : Theme.onGlassDanger)
        }
        .accessibilityLabel("Closes in \(ShrineService.countdown(to: expiresAt, now: Date()))")
    }
}

/// Summoning pieces as a reward tile: the form's own card in the dark
/// bronze socket every tile on glass wears, a puzzle-piece seal on its
/// shoulder, and the count on its corner in the tiles' outlined figures.
/// There is no painted piece yet (Docs/SHRINES.md, *Not done*), and the card
/// says whose pieces they are better than a generic shard would.
struct ShrinePieceTile: View {
    let blueprint: UnitBlueprint
    let amount: String
    var size: CGFloat = 44
    var title: String? = "Pieces"

    private var corner: CGFloat { max(6, size * 0.16) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return VStack(spacing: max(2, size * 0.05)) {
            ZStack(alignment: .bottomTrailing) {
                shape.fill(Theme.socketFill)
                PortraitPainting(name: blueprint.model.portraitName, size: size - 6)
                    .frame(width: size - 6, height: size - 6)
                    .clipShape(RoundedRectangle(cornerRadius: max(4, corner - 2), style: .continuous))
                    .frame(width: size, height: size)
                OutlinedText(
                    text: amount,
                    font: Theme.numeric(max(10.5, size * 0.21)).weight(.black),
                    width: max(0.8, size * 0.016)
                )
                .fixedSize()
                .padding(.trailing, max(3, size * 0.07))
                .padding(.bottom, max(2, size * 0.05))
            }
            .frame(width: size, height: size)
            .overlay(shape.strokeBorder(Theme.bronzeFrame, lineWidth: max(1, size * 0.02)))
            .overlay(alignment: .topLeading) {
                Image(systemName: "puzzlepiece.fill")
                    .font(.system(size: max(8, size * 0.2), weight: .black))
                    .foregroundStyle(Theme.onGlassGold)
                    .shadow(color: .black.opacity(0.9), radius: 1)
                    .offset(x: -3, y: -3)
            }
            .shadow(color: .black.opacity(0.4), radius: size * 0.05, y: size * 0.03)
            if let title {
                Text(title)
                    .font(Theme.body(max(9, size * 0.15)).weight(.semibold))
                    .foregroundStyle(Theme.onGlass)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: size * 1.35)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(amount) pieces of \(shrineName(blueprint.name))")
    }
}

/// The rail's label pinned above its scroll, on the rail's own dark glass:
/// the Titans' rail head, which is private to the Labyrinth's file.
private struct ShrineRailHead: View {
    let title: String

    var body: some View {
        PlaceRailLabel(title)
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color(hex: "#0E0B08").opacity(0.86), Color(hex: "#0E0B08").opacity(0.62)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .ignoresSafeArea(.container, edges: .leading)
                .allowsHitTesting(false)
            )
    }
}

/// The floor a face stands on: a warm pool of light on the painted floor and
/// a dark contact shadow at the tile's foot — the Labyrinth rooms' own, drawn
/// wider than the tile without being measured.
private struct ShrineFloorPool: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(RadialGradient(colors: [Theme.gold.opacity(0.30), Theme.gold.opacity(0.08), .clear],
                                     center: .center, startRadius: 4, endRadius: 88))
                .frame(width: 176, height: 46)
                .blendMode(.plusLighter)
            Ellipse()
                .fill(RadialGradient(colors: [Color.black.opacity(0.8), .clear], center: .center,
                                     startRadius: 2, endRadius: 54))
                .frame(width: 116, height: 18)
        }
        .offset(y: 25)
        .allowsHitTesting(false)
    }
}
