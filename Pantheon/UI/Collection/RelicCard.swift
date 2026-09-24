import SwiftUI
import UIKit

// MARK: - The relic card family (2026-09-24, Docs/PLAN.md *Relics the genre's way*)
//
// The owner, with our relic card beside Summoners War's rune card: "Look how
// easy it is to see everything, and to understand what's going on." Ours
// carried about eighty words against one stone — thirty of them a paragraph
// about aether — and printed its main stat 8.7 points tall in gold on cream
// at 3.1:1. This file is the reliquary's half that is about ONE relic, built
// from the kit (`RelicKit.swift`, `RelicTile.swift`) on basalt:
//
// - `RelicCard` — the relic as numbers: the main stat at 24 points, every sub
//   at 16 with its roll marks, the set in two words, the level rail; and on
//   the right the state the relic is in — CLIMB (the odds, the cost, POWER UP
//   and TO ▾), ROLL (the choice of two), AWAKEN (4 → 5 subs, the +15 main
//   before → after, the aether as tiles, PAY WITH) or PEAK — over five
//   action plates. Replaces `RelicDetailView`.
// - `RelicDropSheet` — what a drop opens from the chest's shelf, with ONE
//   best-fit dial beside the best relic owned for that slot, and Equip.
//   Replaces `RelicDropCard`.
// - `RelicWearerChooser` — equip on a unit, the roster ordered by who gains
//   most. Replaces `RelicWearerPicker`.
// - `RelicStoneBench` — hone and gem on the painted stones. Replaces
//   `RelicStoneSheet`.
// - `RelicSetsReference` — every set, dark; a tap opens the bag filtered to
//   it. Replaces `RelicSetsSheet`.
//
// Every change to a relic goes through the store's relic methods and nothing
// here changes a number. The five system dialogs these screens had are one
// game card (`RelicConfirmCard`), and the awakening still plays
// `RelicAwakeningRite`, reused as it is.

// MARK: - The card

/// One relic, the genre's rune card in our materials: a basalt LEFT with the
/// relic's numbers — the tile, the quality and set, who wears it, the main
/// stat and where the next level and +15 take it, the sub stats with their
/// roll marks and the last roll lit, the set's line and the level rail — and
/// a basalt RIGHT holding the state the relic is in over the five things to
/// do with it (CHANGE / REMOVE or EQUIP, HONE, REROLL, SELL; the lock is in
/// the strip).
///
/// The fit dial is not here: the card judges a relic already chosen; the bag
/// panel and the drop sheet judge fit.
struct RelicCard: View {
    let relicID: UUID
    /// The CI tour's `relic_awaken` step (`TourRite`): performs the awakening
    /// with the set's own colour as the screen appears, so the rite and the
    /// fifth sub's choice are photographed without a tap. Does nothing on a
    /// relic that cannot be awakened.
    let awakenOnAppear: Bool

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    /// The aether colour the player pays with; nil is the set's own.
    @State private var payingElement: Element? = nil
    /// The rite is up: the stone in its pillar of light.
    @State private var riteShown = false
    /// The last attempt or roll taken, for the result strip and the lit sub.
    @State private var lastOutcome: RelicService.PowerUpOutcome? = nil
    /// What a power-up to +N came to.
    @State private var runReport: RelicCardRun? = nil
    /// The tile's gold flare when a power-up lands.
    @State private var glow = false
    @State private var shakeOffset: CGFloat = 0
    /// The confirmation over the screen: sell, reroll, awaken.
    @State private var cardAsking: RelicConfirm? = nil
    /// The sheet this card has opened.
    @State private var door: RelicCardDoor? = nil

    init(relicID: UUID, awakenOnAppear: Bool = false) {
        self.relicID = relicID
        self.awakenOnAppear = awakenOnAppear
    }

    private var relic: Relic? { store.player.relic(relicID) }
    private var wearer: ResolvedUnit? { relic?.equippedBy.flatMap { store.resolved($0) } }

    /// The left column's width: 330, or 300 on a phone whose safe frame is
    /// under 720 points (the SE).
    private static func leftWidth(forSafeWidth width: CGFloat) -> CGFloat {
        width < 720 ? 300 : 330
    }

    var body: some View {
        NavigationStack {
            GameScreen(stripTitle, subtitle: stripSubtitle, dismiss: { dismiss() }) {
                lockButton
                BarWallet(wallet: store.player.wallet, shows: [.drachma])
            } content: {
                cardContent
            }
            // Over the GameScreen, not its content, so the strip is veiled
            // with the rest (run 221's lesson for the rite).
            .overlay { riteLayer }
            .overlay { confirmLayer }
            .onAppear { awakenIfAsked() }
            .sheet(item: $door) { opened in
                doorView(opened)
                    .environmentObject(store)
            }
        }
    }

    // MARK: The strip

    private var stripTitle: String {
        guard let relic else { return "Relic" }
        return "\(relic.set.displayName) · Slot \(relic.slot)"
    }

    /// "Legend · +15 · on Zeus": the family's name, never an awakened title,
    /// which wrapped the old strip (run 220).
    private var stripSubtitle: String? {
        guard let relic else { return nil }
        let worn = wearer.map { "on \($0.blueprint.name)" } ?? "not worn"
        return "\(relic.resolvedQuality.displayName) · +\(relic.level) · \(worn)"
    }

    private var lockButton: some View {
        let locked = relic?.isLocked == true
        return BarButton(
            title: locked ? "Locked" : "Lock",
            systemImage: locked ? "lock.fill" : "lock.open",
            tint: locked ? Theme.gold : Theme.textSecondary
        ) {
            store.toggleRelicLock(relicID)
        }
    }

    // MARK: The content

    @ViewBuilder
    private var cardContent: some View {
        if let relic {
            GeometryReader { proxy in
                columns(relic, size: proxy.size)
            }
            .background { ReliquaryBackdrop() }
        } else {
            RelicCardGone { dismiss() }
        }
    }

    private func columns(_ relic: Relic, size: CGSize) -> some View {
        HStack(alignment: .top, spacing: 8) {
            leftPanel(relic)
                .frame(width: Self.leftWidth(forSafeWidth: size.width))
            rightPanel(relic)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: size.width, height: size.height, alignment: .top)
        // The rite stands over the whole screen; the columns go out of focus
        // under it, so its words never lie across a button's.
        .blur(radius: riteShown ? 10 : 0)
    }

    // MARK: LEFT — the relic

    /// 60 + 6 + 38 + 6 + the subs (up to 110) + 6 + 26 + 6 + 16: 274 of the
    /// 280 points inside the panel on the design phone. The set and the rail
    /// stand at the foot whatever the sub count, so they never move.
    private func leftPanel(_ relic: Relic) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(relic)
            RelicCardMainWell(relic: relic)
            RelicCardSubList(relic: relic, highlight: lastOutcome?.subStatChange, waitingWords: "choose one →")
            Spacer(minLength: 0)
            SetEffectRow(set: relic.set, piecesOnUnit: piecesOnWearer(relic), style: .compact, onInfo: {
                door = .sets(unitID: wearer?.id)
            })
            LevelRail(level: relic.level)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BasaltPanel())
    }

    private func header(_ relic: Relic) -> some View {
        HStack(alignment: .center, spacing: 10) {
            RelicTile(relic: relic, size: .large, flare: glow)
            VStack(alignment: .leading, spacing: 1) {
                RelicCardQualityLine(relic: relic)
                Text(relic.set.displayName)
                    .font(Theme.title(19))
                    .carved(glow: false)
                    .lineLimit(1)
                wearerLine(relic)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 60)
    }

    private func wearerLine(_ relic: Relic) -> some View {
        HStack(spacing: 4) {
            Text("Slot \(relic.slot) ·")
                .font(Theme.body(12))
                .foregroundStyle(RelicPalette.dim)
                .fixedSize()
            wearerName
        }
        .lineLimit(1)
        .frame(height: 18)
    }

    @ViewBuilder
    private var wearerName: some View {
        if let wearer {
            WearerBadge(unit: wearer, size: 18)
            Text(wearer.blueprint.name)
                .font(Theme.body(12).weight(.bold))
                .foregroundStyle(RelicPalette.value)
        } else {
            Text("not worn")
                .font(Theme.body(12))
                .foregroundStyle(RelicPalette.dim)
        }
    }

    /// How many pieces of this relic's set its wearer has on; nil when it is
    /// not worn, so the set's line describes the set rather than a build.
    private func piecesOnWearer(_ relic: Relic) -> Int? {
        guard let wearer else { return nil }
        return wearer.relics.filter { $0.set == relic.set }.count
    }

    // MARK: RIGHT — the state and the actions

    private func rightPanel(_ relic: Relic) -> some View {
        VStack(spacing: 8) {
            CardFadingScroll {
                stagePanel(relic)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)
            actionRow(relic)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BasaltPanel())
    }

    @ViewBuilder
    private func stagePanel(_ relic: Relic) -> some View {
        switch RelicCardStage.of(relic) {
        case .climb:
            climbPanel(relic)
        case .roll:
            rollPanel(relic)
        case .awaken:
            awakenPanel(relic)
        case .peak:
            peakPanel(relic)
        }
    }

    // MARK: (a) CLIMB

    private func climbPanel(_ relic: Relic) -> some View {
        let cost = RelicService.upgradeCost(grade: relic.grade, level: relic.level)
        let chance = RelicService.successChance(toLevel: relic.level + 1)
        let affordable = store.player.wallet.drachma >= cost
        return VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader(title: "Power-up", accessory: "+\(relic.level) → +\(relic.level + 1)")
            oddsRow(relic, chance: chance, cost: cost, affordable: affordable)
            climbButtons(relic, affordable: affordable)
            news
            teaser(relic)
        }
    }

    /// The odds, the price and what the next level buys, with the rule a
    /// player must not have to guess — a failure costs the drachma and
    /// nothing else — one tap away.
    private func oddsRow(_ relic: Relic, chance: Double, cost: Int, affordable: Bool) -> some View {
        HStack(spacing: 10) {
            OddsDial(chance: chance)
            CostWell(key: "drachma", amount: cost, affordable: affordable, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                nextMainLine(relic)
                climbHint(relic)
            }
            Spacer(minLength: 4)
            InfoDot(title: "Power-up") {
                RelicCardAside(words: "A failed attempt spends the drachma and keeps the level. It never takes a level or a sub stat.")
            }
        }
        .frame(height: 52)
    }

    @ViewBuilder
    private func nextMainLine(_ relic: Relic) -> some View {
        if let next = relic.nextMainStat {
            Text("\(next.kind.displayName) +\(next.kind.format(next.value))")
                .font(Theme.numeric(14))
                .foregroundStyle(RelicPalette.value)
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// What the next level does beyond the main stat: a sub stat at +3, +6,
    /// +9 and +12, the main stat's jump at +15.
    @ViewBuilder
    private func climbHint(_ relic: Relic) -> some View {
        let upcoming = relic.level + 1
        if RelicService.levelRollsSubStat(upcoming) {
            RelicCardHint(systemImage: "sparkles",
                          words: relic.subStats.count < relic.subStatCap ? "adds a sub" : "grows a sub")
        } else if upcoming == relic.maxLevel {
            RelicCardHint(systemImage: "crown.fill",
                          words: "main \(RelicCardFigures.multiplier(awakened: relic.isAwakened))")
        }
    }

    private func climbButtons(_ relic: Relic, affordable: Bool) -> some View {
        HStack(spacing: 8) {
            PrimaryButton(title: "Power up", systemImage: "arrow.up.circle.fill", isEnabled: affordable) {
                powerUpOnce()
            }
            .offset(x: shakeOffset)
            toMenu(relic, affordable: affordable)
        }
    }

    /// The genre's auto power-up: attempts until a milestone, a roll to
    /// choose, or the purse runs dry, with the bill summarised after.
    private func toMenu(_ relic: Relic, affordable: Bool) -> some View {
        let targets = [3, 6, 9, 12, 15].filter { $0 > relic.level }
        return Menu {
            ForEach(targets, id: \.self) { target in
                Button("Power up to +\(target)") {
                    powerUp(to: target)
                }
            }
        } label: {
            RelicPlateLabel(title: "To", height: PrimaryButton.height, trailingSystemImage: "chevron.down")
        }
        .menuStyle(.borderlessButton)
        .frame(width: 96)
        .disabled(!affordable)
        .opacity(affordable ? 1 : 0.5)
        .accessibilityLabel("Power up to a level")
    }

    /// Where a 6★'s climb leads, in one line: the awakening waits at +15.
    @ViewBuilder
    private func teaser(_ relic: Relic) -> some View {
        if relic.grade >= 6 && !relic.isAwakened {
            RelicCardHint(
                systemImage: "sun.max.fill",
                words: "At +15: \(relic.subStatCap + 1) subs · main \(RelicCardFigures.multiplier(awakened: true))"
            )
        }
    }

    /// The last attempt, the last run to +N, or the roll just taken.
    @ViewBuilder
    private var news: some View {
        if let runReport {
            runNews(runReport)
        } else if let lastOutcome {
            outcomeNews(lastOutcome)
        }
    }

    /// A run's line: where it got, in how many attempts, and what it spent.
    private func runNews(_ run: RelicCardRun) -> RelicCardNews {
        RelicCardNews(good: run.succeeded, headline: run.headline, coin: run.spent, words: run.rollWords)
    }

    private func outcomeNews(_ outcome: RelicService.PowerUpOutcome) -> RelicCardNews {
        if outcome.succeeded {
            return RelicCardNews(good: true, headline: "+\(outcome.level)",
                                 words: outcome.subStatChange.map(RelicCardFigures.changeWords))
        }
        return RelicCardNews(good: false, headline: "still +\(outcome.level)", coin: outcome.cost)
    }

    // MARK: (b) ROLL

    /// The two outcomes a +3/+6/+9/+12 (or the awakening's fifth sub)
    /// offers, derived from the relic's own seed: closing the card and
    /// coming back shows the same pair.
    private func rollPanel(_ relic: Relic) -> some View {
        let offers = RelicService.candidates(for: relic)
        let fifth = relic.isAwakened && relic.isMaxLevel
        return VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader(title: "Choose one", accessory: fifth ? "5th sub" : "+\(relic.level)")
            haltedRun
            ForEach(offers) { offer in
                RelicRollOffer(offer: offer) {
                    take(offer)
                }
            }
            nextAttempt(relic)
        }
    }

    /// A run to +N that halted here at the roll: what it spent getting here,
    /// said above the choice as the old card did.
    @ViewBuilder
    private var haltedRun: some View {
        if let runReport, runReport.paused {
            runNews(runReport)
        }
    }

    /// The climb's next price, read-only while the roll waits, so nothing
    /// moves when the player takes one.
    @ViewBuilder
    private func nextAttempt(_ relic: Relic) -> some View {
        if relic.level < relic.maxLevel {
            RelicCardCostLine(
                words: "Next: \(RelicCardFigures.percent(RelicService.successChance(toLevel: relic.level + 1)))",
                cost: RelicService.upgradeCost(grade: relic.grade, level: relic.level)
            )
        }
    }

    // MARK: (c) AWAKEN

    /// A 6★ at +15: what the awakening gives as two numbers, what it costs as
    /// two painted tiles with have / need, and the colour to pay with. No
    /// refusal sentence: the rose counts and the dim button say it.
    private func awakenPanel(_ relic: Relic) -> some View {
        let paying = payingElement ?? relic.set.aetherElement
        let refusal = RelicService.awakeningRefusal(relic, paying: paying, player: store.player)
        return VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader(title: "Awaken", accessory: "\(relic.grade)★ · +\(relic.level)")
            awakenPlates(relic)
            awakenCosts(relic, paying: paying)
            PrimaryButton(title: "Awaken", systemImage: "sun.max.fill", isEnabled: refusal == nil) {
                cardAsking = .awaken(relic: relic, paying: paying)
            }
        }
    }

    private func awakenPlates(_ relic: Relic) -> some View {
        let kind = relic.mainStat.kind
        let ordinary = RelicReading.peakMain(relic, awakened: false)
        let awakened = RelicReading.peakMain(relic, awakened: true)
        return HStack(spacing: 8) {
            NumberPlate(eyebrow: "Sub stats", before: "\(relic.subStats.count)", after: "\(relic.subStats.count + 1)")
            NumberPlate(eyebrow: "\(kind.displayName) at +15",
                        before: "+\(kind.format(ordinary.value))",
                        after: "+\(kind.format(awakened.value))")
        }
    }

    private func awakenCosts(_ relic: Relic, paying: Element) -> some View {
        let cost = RelicService.awakeningCost(for: relic, paying: paying)
        let elementalID = Aether.id(for: paying)
        return HStack(alignment: .top, spacing: 12) {
            RequirementTile(key: elementalID, have: Aether.count(elementalID, player: store.player),
                            need: cost.elemental, size: 48)
            RequirementTile(key: Aether.pure, have: Aether.count(Aether.pure, player: store.player),
                            need: cost.pure, size: 48)
            payWith(relic, paying: paying)
                .padding(.leading, 4)
        }
    }

    /// The five colours, the set's own ringed in star gold (the fair price),
    /// the chosen one ringed outside, each with what is held.
    private func payWith(_ relic: Relic, paying: Element) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("PAY WITH")
                .font(Theme.body(11).weight(.black))
                .tracking(0.8)
                .foregroundStyle(RelicPalette.eyebrow)
                .lineLimit(1)
                .fixedSize()
            HStack(alignment: .top, spacing: 8) {
                ForEach(Element.allCases) { element in
                    payChip(relic, element: element, paying: paying)
                }
            }
        }
    }

    private func payChip(_ relic: Relic, element: Element, paying: Element) -> some View {
        let held = Aether.count(Aether.id(for: element), player: store.player)
        let need = RelicService.awakeningCost(for: relic, paying: element).elemental
        return RelicCardPayChip(element: element, held: held, need: need,
                                fair: element == relic.set.aetherElement, isOn: element == paying) {
            withAnimation(Motion.select) {
                payingElement = element
            }
        }
    }

    // MARK: (d) PEAK

    private func peakPanel(_ relic: Relic) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader(title: relic.isAwakened ? "Awakened" : "At its peak", accessory: "+\(relic.level)")
            HStack(spacing: 8) {
                NumberPlate(eyebrow: "Main at +15", before: RelicCardFigures.multiplier(awakened: relic.isAwakened))
                NumberPlate(eyebrow: "Sub stats", before: "\(relic.subStats.count) of \(relic.subStatCap)")
            }
            stonesStillWork
            news
        }
    }

    /// The main stat is at its top and the subs are what they rolled; the
    /// stones still work on them — this points at HONE.
    private var stonesStillWork: some View {
        HStack(spacing: 6) {
            ItemIcon(key: "whetstone_hero", size: 20, glow: false)
            ItemIcon(key: "gem_hero", size: 20, glow: false)
            Text("still work")
                .font(Theme.body(12))
                .foregroundStyle(RelicPalette.dim)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Whetstones and gems still work on this relic")
    }

    // MARK: The action row

    /// Always shown, 52 tall, the plates 7 apart and sharing the width.
    private func actionRow(_ relic: Relic) -> some View {
        HStack(spacing: 7) {
            wearerPlates(relic)
            RelicIconPlate(title: "Hone", itemKey: "whetstone_hero", systemImage: "seal.fill",
                           isEnabled: !relic.subStats.isEmpty) {
                door = .stones
            }
            rerollPlate(relic)
            sellPlate(relic)
        }
        .frame(height: 52)
    }

    /// Worn: CHANGE (Manage on this slot) and REMOVE (free, at once). Not
    /// worn: EQUIP (the wearer chooser).
    @ViewBuilder
    private func wearerPlates(_ relic: Relic) -> some View {
        if let wearer {
            RelicIconPlate(title: "Change", systemImage: "arrow.left.arrow.right") {
                door = .change(unitID: wearer.id, slot: relic.slot)
            }
            RelicIconPlate(title: "Remove", systemImage: "minus.circle") {
                store.unequip(slot: relic.slot, from: wearer.id)
            }
        } else {
            RelicIconPlate(title: "Equip", systemImage: "person.crop.circle.badge.plus") {
                door = .wearer
            }
        }
    }

    private func rerollPlate(_ relic: Relic) -> some View {
        let minimum = RelicService.reappraisalMinimumLevel
        let cost = RelicService.reappraisalCost(relic)
        let ready = relic.level >= minimum
        let affordable = store.player.wallet.drachma >= cost
        return RelicIconPlate(title: ready ? "Reroll" : "Reroll +\(minimum)",
                              systemImage: "arrow.triangle.2.circlepath",
                              isEnabled: ready && affordable) {
            cardAsking = .reappraise(relic: relic, cost: cost)
        }
    }

    @ViewBuilder
    private func sellPlate(_ relic: Relic) -> some View {
        if relic.isLocked {
            RelicIconPlate(title: "Locked", systemImage: "lock.fill", finish: .wine, isEnabled: false) {}
        } else {
            RelicIconPlate(title: "Sell", itemKey: "drachma", systemImage: "circle.hexagongrid.fill", finish: .wine) {
                cardAsking = .sell(relics: [relic], total: RelicService.sellValue(relic))
            }
        }
    }

    // MARK: Overlays and doors

    @ViewBuilder
    private var riteLayer: some View {
        if riteShown, let relic {
            RelicAwakeningRite(relic: relic) {
                withAnimation(Motion.exit) {
                    riteShown = false
                }
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var confirmLayer: some View {
        if let cardAsking {
            RelicConfirmCard(confirm: cardAsking) {
                answer(cardAsking)
            } onCancel: {
                self.cardAsking = nil
            }
        }
    }

    @ViewBuilder
    private func doorView(_ opened: RelicCardDoor) -> some View {
        switch opened {
        case .change(let unitID, let slot):
            RelicsScreen(unitID: unitID, opening: .slot(slot))
        case .wearer:
            RelicWearerChooser(relicID: relicID)
        case .stones:
            RelicStoneBench(relicID: relicID)
        case .sets(let unitID):
            RelicSetsReference(unitID: unitID)
        }
    }

    // MARK: Actions

    /// The confirmation card's answer. Its own confirm plate has already
    /// sounded, so only the haptic is added here.
    private func answer(_ ask: RelicConfirm) {
        cardAsking = nil
        switch ask {
        case .sell:
            sellRelic()
        case .reappraise:
            reappraise()
        case .awaken(_, let paying):
            performAwakening(paying: paying)
        case .leaveDraft:
            break
        }
    }

    private func sellRelic() {
        guard store.sellRelics([relicID]) != nil else { return }
        Juice.notify(.success)
        dismiss()
    }

    /// Every sub rolled again from scratch; the last roll's light goes with
    /// the subs it lit.
    private func reappraise() {
        store.reappraiseRelic(relicID)
        lastOutcome = nil
        runReport = nil
        Juice.notify(.success)
    }

    private func awakenIfAsked() {
        guard awakenOnAppear, let relic else { return }
        let element = relic.set.aetherElement
        if RelicService.awakeningRefusal(relic, paying: element, player: store.player) == nil {
            performAwakening(paying: element)
        }
    }

    /// The awakening itself, then the rite over the screen; the fifth sub
    /// stat's choice of two stands on the card once the rite fades.
    private func performAwakening(paying element: Element) {
        guard store.awakenRelic(relicID, paying: element) != nil else { return }
        lastOutcome = nil
        runReport = nil
        AudioLibrary.shared.play(.riteRelicAwaken, volume: 0.9)
        Juice.haptic(.heavy)
        withAnimation(Motion.panel) {
            riteShown = true
        }
    }

    private func take(_ offer: RelicService.RollCandidate) {
        guard let change = store.takeRelicRoll(relicID, candidate: offer.id) else { return }
        // The card's press ticked on touch-down; the confirm is the "done".
        AudioLibrary.shared.play(.uiConfirm)
        lastOutcome = RelicService.PowerUpOutcome(
            succeeded: true,
            level: store.player.relic(relicID)?.level ?? 0,
            cost: 0,
            chance: 1,
            subStatChange: change
        )
        runReport = nil
        withAnimation(.easeOut(duration: 0.25)) { glow = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.4)) { glow = false }
        }
    }

    /// Attempts until the target, a roll to choose or the purse runs out:
    /// the strip says how many, what they cost and what they came to.
    private func powerUp(to target: Int) {
        let outcomes = store.powerUpRelic(relicID, to: target)
        guard let last = outcomes.last else { return }
        lastOutcome = last
        let spent = outcomes.reduce(0) { $0 + $1.cost }
        let rolls = outcomes.compactMap(\.subStatChange).map(RelicCardFigures.rollWords)
        let level = relic?.level ?? 0
        let reached = level >= target
        let paused = !reached && relic?.hasPendingRoll == true
        let report = RelicCardRun(target: target, reached: reached, paused: paused, level: level,
                                  attempts: outcomes.count, spent: spent, rolls: rolls)
        runReport = report
        // A run to +N rings or cracks once, with no drum roll: the roll is a
        // single attempt's (Docs/FEEL.md W2.2). A halt at a roll to choose
        // rings: the run did what it was asked, up to the choice it may not
        // make for the player (the old card cracked there).
        if report.succeeded {
            AudioLibrary.shared.play(.relicRing, volume: 0.9)
            Juice.notify(.success)
            withAnimation(.easeOut(duration: 0.15)) { glow = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeIn(duration: 0.5)) { glow = false }
            }
        } else {
            AudioLibrary.shared.play(.relicCrack, volume: 0.9)
            Juice.notify(.warning)
        }
    }

    /// One attempt: a short drum roll, then the anvil's ring and the flare
    /// on a success, or a dull crack and a shake on a failure.
    private func powerUpOnce() {
        guard let outcome = store.powerUpRelic(relicID) else { return }
        lastOutcome = outcome
        runReport = nil
        AudioLibrary.shared.play(.relicRoll, volume: 0.7)
        if outcome.succeeded {
            AudioLibrary.shared.play(.relicRing, volume: 0.9, delay: AudioLibrary.Sound.rollLead)
            Juice.notify(.success)
            withAnimation(.easeOut(duration: 0.15)) { glow = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation(.easeIn(duration: 0.5)) { glow = false }
            }
        } else {
            AudioLibrary.shared.play(.relicCrack, volume: 0.9, delay: AudioLibrary.Sound.rollLead)
            Juice.notify(.error)
            shake()
        }
    }

    private func shake() {
        withAnimation(.default.speed(4)) { shakeOffset = 7 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.default.speed(4)) { shakeOffset = -7 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(.default.speed(4)) { shakeOffset = 0 }
        }
    }
}

/// The four states the card's right half can be in.
private enum RelicCardStage {
    case climb, roll, awaken, peak

    static func of(_ relic: Relic) -> RelicCardStage {
        if relic.hasPendingRoll { return .roll }
        if relic.level < relic.maxLevel { return .climb }
        if relic.grade >= 6 && !relic.isAwakened { return .awaken }
        return .peak
    }
}

/// The sheets the card opens: Manage on the wearer's slot, the wearer
/// chooser, the stone bench, and the set reference.
private enum RelicCardDoor: Identifiable {
    case change(unitID: UUID, slot: Int)
    case wearer
    case stones
    case sets(unitID: UUID?)

    var id: String {
        switch self {
        case .change(let unitID, let slot):
            return "change-\(unitID.uuidString)-\(slot)"
        case .wearer:
            return "wearer"
        case .stones:
            return "stones"
        case .sets(let unitID):
            return "sets-\(unitID?.uuidString ?? "all")"
        }
    }
}

/// What a power-up to +N came to: the target reached, a halt at a roll to
/// choose (a success — the run stops there by design, so the player picks),
/// or a stop short of both (the purse ran dry).
private struct RelicCardRun: Equatable {
    let target: Int
    let reached: Bool
    /// Halted short of the target at a +3/+6/+9/+12 whose roll waits.
    let paused: Bool
    let level: Int
    let attempts: Int
    let spent: Int
    let rolls: [String]

    var succeeded: Bool { reached || paused }

    var headline: String {
        if reached { return "+\(target) in \(attempts)" }
        if paused { return "+\(level) in \(attempts)" }
        return "Stopped at +\(level) in \(attempts)"
    }

    var rollWords: String? {
        rolls.isEmpty ? nil : rolls.joined(separator: " · ")
    }
}

// MARK: - The drop

/// What a relic drop opens from the chest's shelf, the genre's rune-obtained
/// card: the stone large in its quality's light on the left, and on the right
/// its numbers, the set, ONE fit dial for the role it suits best beside the
/// best relic already owned for that slot, and Keep, Equip, Lock or Sell
/// before the bag ever sees it.
struct RelicDropSheet: View {
    let relicID: UUID

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var dropAsking: RelicConfirm? = nil
    @State private var dropChoosing = false

    init(relicID: UUID) {
        self.relicID = relicID
    }

    private var relic: Relic? { store.player.relic(relicID) }

    /// The showcase's width: 300, or 260 on a safe frame under 720 points,
    /// where the four buttons need the room.
    private static func showcaseWidth(forSafeWidth width: CGFloat) -> CGFloat {
        width < 720 ? 260 : 300
    }

    var body: some View {
        NavigationStack {
            GameScreen("A relic dropped", subtitle: relic?.displayName, dismiss: { dismiss() }) {
                BarWallet(wallet: store.player.wallet, shows: [.drachma])
            } content: {
                dropContent
            }
            .overlay { dropConfirmLayer }
            .sheet(isPresented: $dropChoosing) {
                RelicWearerChooser(relicID: relicID)
                    .environmentObject(store)
            }
        }
    }

    @ViewBuilder
    private var dropContent: some View {
        if let relic {
            GeometryReader { proxy in
                HStack(alignment: .top, spacing: 8) {
                    showcase(relic)
                        .frame(width: Self.showcaseWidth(forSafeWidth: proxy.size.width))
                    words(relic)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .background { ReliquaryBackdrop() }
        } else {
            RelicCardGone { dismiss() }
        }
    }

    /// The stone at 110 in its quality's light, the grade, the quality, the
    /// set and what the relic is, centred.
    private func showcase(_ relic: Relic) -> some View {
        VStack(spacing: 8) {
            RelicCardDropStone(relic: relic)
            StarRow(stars: relic.grade, size: 14)
            RelicCardQualityLine(relic: relic, point: 13, letterSpace: 1.2)
            Text(relic.set.displayName)
                .font(Theme.title(21))
                .carved(glow: false)
                .lineLimit(1)
            Text("Slot \(relic.slot) · \(relic.mainStat.kind.displayName)")
                .font(Theme.body(13))
                .foregroundStyle(RelicPalette.dim)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .background(BasaltPanel())
    }

    /// The numbers scroll only if they must (an awakened drop has five
    /// subs); the buttons are pinned under them.
    private func words(_ relic: Relic) -> some View {
        VStack(spacing: 8) {
            CardFadingScroll {
                VStack(alignment: .leading, spacing: 6) {
                    RelicCardMainWell(relic: relic)
                    RelicCardSubList(relic: relic)
                    SetEffectRow(set: relic.set, piecesOnUnit: nil, style: .compact)
                    fitRow(relic)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)
            dropButtons(relic)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BasaltPanel())
    }

    /// The role the relic suits best, and the best relic already owned for
    /// that slot by the same measure — "is this one better than mine?".
    private func fitRow(_ relic: Relic) -> some View {
        let best = RelicReading.bestFit(relic)
        let rival = rivalRelic(relic, role: best.role)
        return HStack(spacing: 8) {
            RelicFitDial(value: max(0, best.value), size: 28)
            Text("Best for \(best.role.withArticle)")
                .font(Theme.body(12))
                .foregroundStyle(RelicPalette.value)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 6)
            rivalTile(rival)
        }
        .frame(height: 40)
    }

    @ViewBuilder
    private func rivalTile(_ rival: Relic?) -> some View {
        if let rival {
            Text("Your best:")
                .font(Theme.body(11))
                .foregroundStyle(RelicPalette.dim)
                .lineLimit(1)
                .fixedSize()
            RelicTile(relic: rival, size: .small, wearer: rival.equippedBy.flatMap { store.resolved($0) })
        }
    }

    /// Another owned relic of this slot with the highest efficiency for the
    /// role; nil when this is the only one.
    private func rivalRelic(_ relic: Relic, role: CombatRole) -> Relic? {
        let others = store.player.relics.filter { $0.slot == relic.slot && $0.id != relic.id }
        return others.max { RelicService.efficiency($0, for: role) < RelicService.efficiency($1, for: role) }
    }

    /// KEEP is the card's answer; Equip, Lock and Sell beside it, the price
    /// on Sell's plate.
    private func dropButtons(_ relic: Relic) -> some View {
        let value = RelicService.sellValue(relic)
        return HStack(spacing: 6) {
            PrimaryButton(title: "Keep", systemImage: "checkmark.circle.fill") {
                dismiss()
            }
            .frame(width: 138)
            RelicIconPlate(title: "Equip", systemImage: "person.crop.circle.badge.plus", height: 46) {
                dropChoosing = true
            }
            RelicIconPlate(title: relic.isLocked ? "Locked" : "Lock", systemImage: "lock.fill", height: 46,
                           isEnabled: !relic.isLocked) {
                // Lock and keep, as the old card's plate did.
                store.toggleRelicLock(relicID)
                AudioLibrary.shared.play(.uiConfirm)
                dismiss()
            }
            RelicPlateButton(title: "Sell", count: value.formatted(), itemKey: "drachma", finish: .wine,
                             height: 46, isEnabled: !relic.isLocked) {
                dropAsking = .sell(relics: [relic], total: value)
            }
            .frame(width: 88)
        }
        .frame(height: 46)
    }

    @ViewBuilder
    private var dropConfirmLayer: some View {
        if let dropAsking {
            RelicConfirmCard(confirm: dropAsking) {
                self.dropAsking = nil
                sellDrop()
            } onCancel: {
                self.dropAsking = nil
            }
        }
    }

    private func sellDrop() {
        guard store.sellRelics([relicID]) != nil else { return }
        Juice.notify(.success)
        dismiss()
    }
}

// MARK: - Equip on a unit

/// The genre's Equip from the rune bag: the roster on the left, ordered by
/// what this relic would add to each (who wants it most first, then power),
/// and on the right, for the unit tapped, NOW over THEN, every stat with its
/// change, the sets it completes or breaks, and Equip.
struct RelicWearerChooser: View {
    let relicID: UUID

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    /// The unit tapped; the tour's `-tour-card wearer` opens on the
    /// strongest (`initialUnitID`).
    @State private var chooserPick: UUID?
    /// The roster in its order, and each unit's gain, measured once on
    /// appear: a relic does not change while this screen is up.
    @State private var chooserUnits: [ResolvedUnit] = []
    @State private var chooserGains: [UUID: Int] = [:]

    private static let columns: [GridItem] = [GridItem(.adaptive(minimum: 60, maximum: 66), spacing: 6)]

    init(relicID: UUID, initialUnitID: UUID? = nil) {
        self.relicID = relicID
        _chooserPick = State(initialValue: initialUnitID)
    }

    private var relic: Relic? { store.player.relic(relicID) }

    private var chooserSubtitle: String? {
        relic.map { "\($0.displayName) · slot \($0.slot)" }
    }

    var body: some View {
        NavigationStack {
            GameScreen("Equip on", subtitle: chooserSubtitle, dismiss: { dismiss() }) {
                BarCount(value: "\(store.player.units.count)", systemImage: "person.2.fill")
            } content: {
                chooserContent
            }
            .onAppear { measure() }
        }
    }

    @ViewBuilder
    private var chooserContent: some View {
        if let relic {
            GeometryReader { proxy in
                HStack(alignment: .top, spacing: 8) {
                    rosterPanel
                        .frame(maxWidth: .infinity)
                    comparisonPanel(relic)
                        .frame(width: 310)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .background { ReliquaryBackdrop() }
        } else {
            RelicCardGone { dismiss() }
        }
    }

    // MARK: The roster

    private var rosterPanel: some View {
        CardFadingScroll {
            LazyVGrid(columns: Self.columns, spacing: 6) {
                ForEach(chooserUnits) { unit in
                    cell(unit)
                }
            }
            .padding(.vertical, 2)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BasaltPanel())
    }

    /// A face on its row plate with the power the relic would add under it.
    private func cell(_ unit: ResolvedUnit) -> some View {
        let isOn = unit.id == chooserPick
        return Button {
            // A cell of a scrolling grid: quiet, the tick in the action.
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            withAnimation(Motion.select) {
                chooserPick = unit.id
            }
        } label: {
            VStack(spacing: 2) {
                UnitPortraitTile(unit: unit, size: 56)
                gainLabel(chooserGains[unit.id])
            }
            .frame(width: 60, height: 76)
            .background(GlassRowPlate(isOn: isOn, radius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(GamePressStyle(.quiet))
        .accessibilityLabel(spokenCell(unit))
    }

    @ViewBuilder
    private func gainLabel(_ gain: Int?) -> some View {
        let amount = gain ?? 0
        if amount > 0 {
            gainText("+\(amount.formatted())", tint: RelicPalette.gain)
        } else if amount < 0 {
            gainText("−\(abs(amount).formatted())", tint: RelicPalette.loss)
        } else {
            gainText("—", tint: RelicPalette.dim)
        }
    }

    private func gainText(_ words: String, tint: Color) -> some View {
        Text(words)
            .font(Theme.numeric(11.5))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
    }

    private func spokenCell(_ unit: ResolvedUnit) -> String {
        let amount = chooserGains[unit.id] ?? 0
        let lead = "\(unit.name), level \(unit.level)"
        if amount > 0 { return "\(lead), power up \(amount)" }
        if amount < 0 { return "\(lead), power down \(-amount)" }
        return "\(lead), no change"
    }

    // MARK: The comparison

    private func comparisonPanel(_ relic: Relic) -> some View {
        Group {
            if let unit = chooserPick.flatMap({ store.resolved($0) }) {
                picked(unit, relic: relic)
            } else {
                EmptyState(icon: "person.crop.circle.badge.questionmark", title: "Who wears it?",
                           message: "Tap a unit to see the change.", onGlass: true)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BasaltPanel())
    }

    private func picked(_ unit: ResolvedUnit, relic: Relic) -> some View {
        let current = unit.relics.first { $0.slot == relic.slot }
        let after = RelicCardFigures.wearing(relic, on: unit)
        let now = RelicCardFigures.bySlot(unit.relics)
        let then = RelicCardFigures.bySlot(unit.relics, putting: relic)
        return VStack(alignment: .leading, spacing: 6) {
            CardFadingScroll {
                VStack(alignment: .leading, spacing: 6) {
                    pickedHeader(unit, current: current, relic: relic)
                    BuildRows(now: now, then: then, readOnly: true)
                    StatLedger(rows: RelicCardFigures.ledger(before: unit.stats, after: after.stats), style: .manage)
                    RelicCardSetChips(before: unit.activeRelicSets, after: after.activeRelicSets)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)
            equipButton(unit, current: current)
        }
    }

    private func pickedHeader(_ unit: ResolvedUnit, current: Relic?, relic: Relic) -> some View {
        HStack(spacing: 8) {
            UnitPortraitTile(unit: unit, size: 32, showsLevel: false)
            VStack(alignment: .leading, spacing: 1) {
                Text(unit.blueprint.name)
                    .font(Theme.title(15))
                    .carved(glow: false)
                    .lineLimit(1)
                    .minimumScaleFactor(13.0 / 15.0)
                Text(currentWords(current, relic: relic))
                    .font(Theme.body(12))
                    .foregroundStyle(RelicPalette.dim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 34)
    }

    private func currentWords(_ current: Relic?, relic: Relic) -> String {
        guard let current else { return "slot \(relic.slot) empty" }
        return "wears \(current.set.displayName) +\(current.level)"
    }

    private func equipButton(_ unit: ResolvedUnit, current: Relic?) -> some View {
        let wearsIt = current?.id == relicID
        return PrimaryButton(title: equipTitle(current: current, wearsIt: wearsIt),
                             systemImage: "checkmark.circle.fill", isEnabled: !wearsIt) {
            store.equip(relicID: relicID, on: unit.id)
            Juice.notify(.success)
            dismiss()
        }
    }

    private func equipTitle(current: Relic?, wearsIt: Bool) -> String {
        if wearsIt { return "Worn" }
        return current == nil ? "Equip" : "Replace & equip"
    }

    /// Every unit's gain from this relic, and the roster in that order.
    private func measure() {
        guard chooserUnits.isEmpty, let relic else { return }
        let units = store.resolvedUnits
        var gains: [UUID: Int] = [:]
        for unit in units {
            gains[unit.id] = RelicCardFigures.gain(of: relic, on: unit)
        }
        chooserGains = gains
        chooserUnits = units.sorted { first, second in
            let firstGain = gains[first.id] ?? 0
            let secondGain = gains[second.id] ?? 0
            if firstGain != secondGain { return firstGain > secondGain }
            return first.power > second.power
        }
    }
}

// MARK: - Hone & gem

/// The genre's grindstones and enchanted gems at a bench: the relic's subs on
/// the left as rows to pick, and on the right the stone — WHETSTONE or GEM,
/// the three tiers as painted tiles with what is held — the new stat a gem
/// would write, the span the stone gives, and its price beside the button.
struct RelicStoneBench: View {
    let relicID: UUID

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var benchSub = 0
    @State private var benchKind: RelicStone.Kind = .whetstone
    @State private var benchTier: RelicStone.Tier = .rare
    @State private var benchGemKind: StatKind? = nil
    @State private var benchNews: RelicBenchLine? = nil

    private static let gemColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6),
    ]

    private static let rules = "A whetstone's bonus sits on top of the roll and survives power-ups; honing again keeps the better. A gem replaces the stat itself — one gemmed sub per relic, the same one may be gemmed again — and clears that sub's honing. Reappraisal clears both."

    private static let sources = "Whetstones and gems drop from the Titans, from Hell bosses, from the Labyrinth's deepest levels and from the Tower's milestones."

    init(relicID: UUID) {
        self.relicID = relicID
    }

    private var relic: Relic? { store.player.relic(relicID) }
    private var stone: RelicStone { RelicStone(kind: benchKind, tier: benchTier) }
    private var held: Int { store.stoneCount(stone) }

    var body: some View {
        NavigationStack {
            GameScreen("Hone & gem", subtitle: relic?.displayName, dismiss: { dismiss() }) {
                BarWallet(wallet: store.player.wallet, shows: [.drachma])
            } content: {
                benchContent
            }
            .onAppear { preferHeldTier() }
        }
    }

    @ViewBuilder
    private var benchContent: some View {
        if let relic {
            GeometryReader { proxy in
                HStack(alignment: .top, spacing: 8) {
                    subsPanel(relic)
                        .frame(maxWidth: .infinity)
                    stonesPanel(relic)
                        .frame(width: 320)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
            .background { ReliquaryBackdrop() }
        } else {
            RelicCardGone { dismiss() }
        }
    }

    // MARK: LEFT — the subs

    private func subsPanel(_ relic: Relic) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            benchHeader(relic)
            subRows(relic)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BasaltPanel())
    }

    private func benchHeader(_ relic: Relic) -> some View {
        HStack(alignment: .center, spacing: 10) {
            RelicTile(relic: relic, size: .large)
            VStack(alignment: .leading, spacing: 2) {
                Text(relic.set.displayName)
                    .font(Theme.title(17))
                    .carved(glow: false)
                    .lineLimit(1)
                Text(relic.effectiveMainStat.displayText)
                    .font(Theme.numeric(16))
                    .foregroundStyle(RelicPalette.value)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 4)
            InfoDot(title: "Stones") {
                RelicCardAside(words: Self.rules)
            }
        }
        .frame(height: 60)
    }

    @ViewBuilder
    private func subRows(_ relic: Relic) -> some View {
        if relic.subStats.isEmpty {
            Text("No sub stat yet · +3 adds one")
                .font(Theme.body(12))
                .foregroundStyle(RelicPalette.dim)
                .lineLimit(1)
                .fixedSize()
        } else {
            let counts = RelicReading.rollCounts(relic)
            CardFadingScroll {
                VStack(spacing: 6) {
                    ForEach(relic.subStats.indices, id: \.self) { index in
                        subRow(relic, index: index, count: index < counts.count ? counts[index] : nil)
                    }
                }
                .padding(.top, 1)
            }
        }
    }

    private func subRow(_ relic: Relic, index: Int, count: Int?) -> some View {
        let sub = relic.effectiveSubStats[index]
        let selected = benchSub == index
        return Button {
            // A row of a scrolling list: quiet, the tick in the action.
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            withAnimation(Motion.select) {
                benchSub = index
                benchGemKind = nil
            }
        } label: {
            subFace(relic, index: index, sub: sub, count: count, selected: selected)
        }
        .buttonStyle(GamePressStyle(.quiet))
        .accessibilityLabel("Sub \(index + 1), \(sub.kind.displayName) plus \(sub.kind.format(sub.value))\(selected ? ", chosen" : "")")
    }

    private func subFace(_ relic: Relic, index: Int, sub: StatModifier, count: Int?, selected: Bool) -> some View {
        let bonus = relic.honedBonus(at: index)
        return HStack(spacing: 6) {
            Text("\(index + 1)")
                .font(Theme.numeric(11.5))
                .foregroundStyle(RelicPalette.eyebrow)
                .frame(width: 14)
            Text(sub.kind.displayName)
                .font(Theme.body(13).weight(.semibold))
                .foregroundStyle(RelicPalette.label)
                .lineLimit(1)
                .fixedSize()
            if relic.gemmed == index {
                ItemIcon(key: "gem_hero", size: 14, glow: false)
            }
            if bonus > 0 {
                RelicCardChip(text: "+\(sub.kind.format(bonus))", tint: RelicPalette.honed)
            }
            Spacer(minLength: 4)
            Text("+\(sub.kind.format(sub.value))")
                .font(Theme.numeric(16))
                .foregroundStyle(RelicPalette.value)
                .lineLimit(1)
                .fixedSize()
            RollMarks(count: count)
                .frame(width: 52, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(rowGround(selected))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func rowGround(_ selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if selected {
            shape.fill(RelicPalette.well)
                .overlay(shape.strokeBorder(RelicCardInk.ring, lineWidth: 1.5))
        } else {
            shape.fill(RelicPalette.basaltFoot)
                .overlay(shape.strokeBorder(RelicPalette.bronze, lineWidth: 1))
        }
    }

    // MARK: RIGHT — the stone

    /// The price and the button pinned at the foot; the kind, the tiers, a
    /// gem's new stats, the span and the last result above them in one
    /// column that scrolls only when it must. A whetstone's column fits
    /// whole; a gem's seven new stats would have had one row of room between
    /// a pinned top and a pinned foot.
    private func stonesPanel(_ relic: Relic) -> some View {
        VStack(spacing: 8) {
            CardFadingScroll {
                VStack(alignment: .leading, spacing: 8) {
                    kindSegments
                    tierTiles
                    gemChooser(relic)
                    rangeLine(relic)
                    benchNewsLine
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)
            benchFoot(relic)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(BasaltPanel())
    }

    private var kindSegments: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return HStack(spacing: 0) {
            segment(.whetstone)
            segment(.gem)
        }
        .frame(height: 34)
        .clipShape(shape)
        .overlay(shape.strokeBorder(RelicPalette.bronzeRim, lineWidth: 1.2))
    }

    /// In the scrolling column, so the quiet press, the tick in the action:
    /// a finger that only starts a scroll must not sound.
    private func segment(_ kind: RelicStone.Kind) -> some View {
        let isOn = benchKind == kind
        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            withAnimation(Motion.select) {
                benchKind = kind
                benchGemKind = nil
            }
        } label: {
            Text(kind.displayName.uppercased())
                .font(Theme.title(13))
                .tracking(1.2)
                .foregroundStyle(isOn ? RelicPalette.goldInk : RelicPalette.value)
                .lineLimit(1)
                .fixedSize()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(segmentFace(isOn))
                .contentShape(Rectangle())
        }
        .buttonStyle(GamePressStyle(.quiet))
        .accessibilityLabel("\(kind.displayName)\(isOn ? ", selected" : "")")
    }

    @ViewBuilder
    private func segmentFace(_ isOn: Bool) -> some View {
        if isOn {
            Rectangle().fill(RelicPalette.goldLeaf)
        } else {
            Rectangle().fill(RelicPalette.bronzeFace)
        }
    }

    private var tierTiles: some View {
        HStack(spacing: 8) {
            ForEach(RelicStone.Tier.allCases, id: \.self) { tier in
                tierTile(tier)
            }
        }
        .frame(height: 84)
    }

    private func tierTile(_ tier: RelicStone.Tier) -> some View {
        let sample = RelicStone(kind: benchKind, tier: tier)
        let count = store.stoneCount(sample)
        let selected = benchTier == tier
        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            withAnimation(Motion.select) {
                benchTier = tier
            }
        } label: {
            tierFace(sample, count: count, selected: selected)
        }
        .buttonStyle(GamePressStyle(.quiet))
        .accessibilityLabel("\(sample.displayName), \(count) held\(selected ? ", chosen" : "")")
    }

    /// The painted stone on a socket plate, its tier in the quality's colour
    /// and the count held; faded when none is held.
    private func tierFace(_ sample: RelicStone, count: Int, selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(spacing: 0) {
            ItemIcon(key: sample.id, size: 48, glow: false)
            Text(sample.tier.displayName.uppercased())
                .font(Theme.body(11).weight(.black))
                .tracking(0.6)
                .foregroundStyle(sample.tier.quality.tone)
                .lineLimit(1)
                .fixedSize()
            Text("×\(count)")
                .font(Theme.numeric(12.5))
                .foregroundStyle(count > 0 ? RelicPalette.value : RelicPalette.dim)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(Theme.socketFill))
        .overlay(shape.strokeBorder(Theme.bronzeFrame, lineWidth: 1))
        .overlay { selectedRing(selected, shape: shape) }
        .opacity(count > 0 ? 1 : 0.55)
        .contentShape(shape)
    }

    @ViewBuilder
    private func selectedRing(_ selected: Bool, shape: RoundedRectangle) -> some View {
        if selected {
            shape.strokeBorder(RelicCardInk.ring, lineWidth: 1.5)
                .compositingGroup()
                .shadow(color: RelicPalette.star.opacity(0.5), radius: 6)
        }
    }

    @ViewBuilder
    private var benchNewsLine: some View {
        if let benchNews {
            RelicCardNews(good: benchNews.good, headline: benchNews.headline, words: benchNews.words)
        }
    }

    /// A gem writes a new stat: the pool less the main stat and the other
    /// subs. One gemmed sub per relic — when another sub holds it, the chips
    /// shut and say which.
    @ViewBuilder
    private func gemChooser(_ relic: Relic) -> some View {
        if benchKind == .gem {
            let hasSub = relic.subStats.indices.contains(benchSub)
            let kinds: [StatKind] = hasSub ? RelicService.gemKinds(for: relic, replacing: benchSub) : []
            let holder: Int? = (relic.gemmed != nil && relic.gemmed != benchSub) ? relic.gemmed : nil
            VStack(alignment: .leading, spacing: 6) {
                Text("NEW STAT")
                    .font(Theme.body(11).weight(.black))
                    .tracking(0.8)
                    .foregroundStyle(RelicPalette.eyebrow)
                    .lineLimit(1)
                    .fixedSize()
                if let holder {
                    RelicCardChip(text: "Sub \(holder + 1) holds the gem", tint: RelicPalette.loss)
                }
                LazyVGrid(columns: Self.gemColumns, alignment: .leading, spacing: 6) {
                    ForEach(kinds) { kind in
                        gemChip(kind, blocked: holder != nil)
                    }
                }
            }
        }
    }

    private func gemChip(_ kind: StatKind, blocked: Bool) -> some View {
        let isOn = benchGemKind == kind
        return Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            benchGemKind = kind
        } label: {
            Text(kind.displayName)
                .font(Theme.body(12).weight(.semibold))
                .foregroundStyle(isOn ? RelicPalette.goldInk : RelicPalette.value)
                .lineLimit(1)
                .fixedSize()
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(chipGround(isOn))
                .contentShape(Rectangle())
        }
        .buttonStyle(GamePressStyle(.quiet))
        .disabled(blocked)
        .opacity(blocked ? 0.45 : 1)
        .accessibilityLabel("\(kind.displayName)\(isOn ? ", chosen" : "")")
    }

    @ViewBuilder
    private func chipGround(_ isOn: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        if isOn {
            shape.fill(RelicPalette.goldLeaf)
        } else {
            shape.fill(RelicPalette.well)
                .overlay(shape.strokeBorder(RelicPalette.bronze, lineWidth: 1))
        }
    }

    /// What the stone gives the chosen sub: the span, and whether it sits on
    /// top of the roll or replaces it.
    private func rangeLine(_ relic: Relic) -> some View {
        HStack(alignment: .center, spacing: 6) {
            rangeWords(relic)
            Spacer(minLength: 4)
            InfoDot(title: "Where stones drop") {
                RelicCardAside(words: Self.sources)
            }
        }
        .frame(minHeight: 26)
    }

    @ViewBuilder
    private func rangeWords(_ relic: Relic) -> some View {
        if let kind = targetKind(relic) {
            let span = RelicService.stoneSpan(stone, kind: kind)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(kind.displayName) +\(kind.format(span.lowerBound))–\(kind.format(span.upperBound))")
                    .font(Theme.numeric(16))
                    .foregroundStyle(RelicPalette.value)
                    .lineLimit(1)
                    .fixedSize()
                Text(benchKind == .whetstone ? "on top of the roll" : "replaces sub \(benchSub + 1)")
                    .font(Theme.body(12))
                    .foregroundStyle(RelicPalette.dim)
                    .lineLimit(1)
                    .fixedSize()
            }
        } else {
            Text(benchKind == .gem ? "Pick the new stat" : "Pick a sub stat")
                .font(Theme.body(12))
                .foregroundStyle(RelicPalette.dim)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func benchFoot(_ relic: Relic) -> some View {
        let affordable = store.player.wallet.drachma >= stone.cost
        return HStack(spacing: 8) {
            CostWell(key: "drachma", amount: stone.cost, affordable: affordable)
            PrimaryButton(title: benchKind == .whetstone ? "Hone" : "Gem", systemImage: stone.kind.glyph,
                          isEnabled: canUse(relic), itemKey: stone.id) {
                use()
            }
        }
    }

    // MARK: Actions

    /// The stat the stone would work on: the chosen sub's own for a
    /// whetstone, the chosen new stat for a gem.
    private func targetKind(_ relic: Relic) -> StatKind? {
        guard relic.subStats.indices.contains(benchSub) else { return nil }
        return benchKind == .gem ? benchGemKind : relic.subStats[benchSub].kind
    }

    private func canUse(_ relic: Relic) -> Bool {
        guard targetKind(relic) != nil, held > 0 else { return false }
        guard store.player.wallet.drachma >= stone.cost else { return false }
        return benchKind == .whetstone || relic.gemmed == nil || relic.gemmed == benchSub
    }

    /// Today's use: the stone and the drachma spent through the store, the
    /// result on the strip. The gold plate has already sounded the confirm.
    private func use() {
        switch benchKind {
        case .whetstone:
            guard let outcome = store.honeRelic(relicID, subStat: benchSub, tier: benchTier) else { return }
            benchNews = RelicBenchLine.honed(outcome)
        case .gem:
            guard let gemKind = benchGemKind,
                  let outcome = store.gemRelic(relicID, subStat: benchSub, with: gemKind, tier: benchTier) else { return }
            benchNews = RelicBenchLine.gemmed(outcome)
            benchGemKind = nil
        }
        let good = benchNews?.good ?? true
        Juice.notify(good ? .success : .warning)
    }

    /// Opens on the rarest whetstone tier the player can actually use when
    /// none of the default is held.
    private func preferHeldTier() {
        guard store.stoneCount(RelicStone(kind: benchKind, tier: benchTier)) == 0 else { return }
        let usable = RelicStone.Tier.allCases.first { store.stoneCount(RelicStone(kind: benchKind, tier: $0)) > 0 }
        if let usable {
            benchTier = usable
        }
    }
}

/// What a whetstone or a gem just did, for the bench's result strip.
private struct RelicBenchLine: Equatable {
    let good: Bool
    let headline: String
    let words: String

    static func honed(_ outcome: RelicService.HoneOutcome) -> RelicBenchLine {
        let kind = outcome.kind
        if outcome.improved {
            return RelicBenchLine(
                good: true,
                headline: "Honed",
                words: "\(kind.displayName) bonus +\(kind.format(outcome.before)) → +\(kind.format(outcome.after))"
            )
        }
        return RelicBenchLine(
            good: false,
            headline: "Rolled +\(kind.format(outcome.rolled))",
            words: "+\(kind.format(outcome.before)) kept"
        )
    }

    static func gemmed(_ outcome: RelicService.GemOutcome) -> RelicBenchLine {
        let replaced = outcome.before
        let written = outcome.after
        return RelicBenchLine(
            good: true,
            headline: "Gemmed",
            words: "\(replaced.kind.displayName) +\(replaced.kind.format(replaced.value)) → "
                + "\(written.kind.displayName) +\(written.kind.format(written.value))"
        )
    }
}

// MARK: - The set reference

/// Every set on one screen — its stone, its name, what it does in two words
/// (and, for the effect sets, the sentence), how many the bag holds and the
/// roster wears — and, opened from a unit, that unit's pieces per set with
/// the complete ones lit. A tap on a set opens the bag filtered to it:
/// "show me my Fury relics".
struct RelicSetsReference: View {
    /// The unit whose pieces the rows count, when opened from its sheet.
    let unitID: UUID?

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var openedSet: RelicSet? = nil

    init(unitID: UUID? = nil) {
        self.unitID = unitID
    }

    private var unit: ResolvedUnit? { unitID.flatMap { store.resolved($0) } }

    private var referenceSubtitle: String {
        unit.map { "on \($0.blueprint.name)" } ?? "2 for a stat · 4 for an effect"
    }

    var body: some View {
        NavigationStack {
            GameScreen("Relic sets", subtitle: referenceSubtitle, dismiss: { dismiss() }) {
                BarButton(title: "Done", systemImage: "checkmark.circle.fill", tint: Theme.gold) {
                    dismiss()
                }
            } content: {
                CardFadingScroll {
                    HStack(alignment: .top, spacing: 8) {
                        setColumn("Stat sets", accessory: "2 pieces",
                                  sets: RelicSet.allCases.filter { $0.piecesRequired == 2 })
                        setColumn("Effect sets", accessory: "4 pieces",
                                  sets: RelicSet.allCases.filter { $0.piecesRequired == 4 })
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .background { ReliquaryBackdrop() }
            }
            .sheet(item: $openedSet) { relicSet in
                RelicsScreen(opening: .set(relicSet))
                    .environmentObject(store)
            }
        }
    }

    private func setColumn(_ title: String, accessory: String, sets: [RelicSet]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GlassSectionHeader(title: title, accessory: accessory)
            ForEach(sets) { relicSet in
                setRow(relicSet)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .top)
        .background(BasaltPanel())
    }

    private func setRow(_ relicSet: RelicSet) -> some View {
        let owned = store.player.relics.filter { $0.set == relicSet }
        let worn = owned.filter { $0.equippedBy != nil }.count
        let onUnit: Int? = unit.map { wearer in wearer.relics.filter { $0.set == relicSet }.count }
        let complete = (onUnit ?? 0) >= relicSet.piecesRequired
        return Button {
            // A row of a scrolling list: quiet, the tick in the action.
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            openedSet = relicSet
        } label: {
            setFace(relicSet, onUnit: onUnit, complete: complete, owned: owned.count, worn: worn)
        }
        .buttonStyle(GamePressStyle(.quiet))
        .accessibilityLabel(spokenRow(relicSet, onUnit: onUnit, owned: owned.count, worn: worn))
        .accessibilityHint("Shows your relics of this set")
    }

    private func setFace(_ relicSet: RelicSet, onUnit: Int?, complete: Bool, owned: Int, worn: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            setEmblem(relicSet, complete: complete)
            VStack(alignment: .leading, spacing: 1) {
                Text(relicSet.displayName)
                    .font(Theme.title(13))
                    .foregroundStyle(complete ? RelicPalette.star : RelicPalette.value)
                    .lineLimit(1)
                    .fixedSize()
                Text(RelicReading.shortEffect(relicSet))
                    .font(Theme.body(13))
                    .foregroundStyle(RelicPalette.label)
                    .lineLimit(1)
                    .fixedSize()
                effectSentence(relicSet)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                unitCount(onUnit, required: relicSet.piecesRequired)
                Text("\(owned) owned · \(worn) worn")
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(RelicPalette.dim)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .background(rowGround(complete))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func setEmblem(_ relicSet: RelicSet, complete: Bool) -> some View {
        if complete {
            RelicSetEmblem(set: relicSet, size: 30)
                .compositingGroup()
                .shadow(color: RelicPalette.star.opacity(0.6), radius: 5)
        } else {
            RelicSetEmblem(set: relicSet, size: 30)
        }
    }

    /// The whole sentence, for the effect sets only: a stat set's two words
    /// already are its effect.
    @ViewBuilder
    private func effectSentence(_ relicSet: RelicSet) -> some View {
        if relicSet.piecesRequired == 4 {
            Text(relicSet.effectDescription)
                .font(Theme.body(11))
                .foregroundStyle(RelicPalette.dim)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func unitCount(_ onUnit: Int?, required: Int) -> some View {
        if let onUnit {
            HStack(spacing: 3) {
                Text("\(onUnit)/\(required)")
                    .font(Theme.numeric(13))
                if onUnit >= required {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                }
            }
            .foregroundStyle(countTint(onUnit, required: required))
            .lineLimit(1)
            .fixedSize()
        }
    }

    private func countTint(_ onUnit: Int, required: Int) -> Color {
        if onUnit >= required { return RelicPalette.gain }
        return onUnit > 0 ? RelicPalette.partial : RelicPalette.dim
    }

    @ViewBuilder
    private func rowGround(_ complete: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        if complete {
            shape.fill(RelicPalette.star.opacity(0.08))
                .overlay(shape.strokeBorder(RelicPalette.star.opacity(0.45), lineWidth: 1))
        } else {
            shape.fill(RelicPalette.well.opacity(0.55))
        }
    }

    private func spokenRow(_ relicSet: RelicSet, onUnit: Int?, owned: Int, worn: Int) -> String {
        var words = "\(relicSet.displayName) set, \(RelicReading.shortEffect(relicSet))"
        if let onUnit {
            words += ", \(onUnit) of \(relicSet.piecesRequired) on this unit"
        }
        return words + ", \(owned) owned, \(worn) worn"
    }
}

// MARK: - Shared parts

/// The sold state every relic screen falls back to: the relic went while the
/// screen was up (sold from a sheet over it), so it says so and closes.
private struct RelicCardGone: View {
    let leave: () -> Void

    var body: some View {
        EmptyState(icon: "shield.slash", title: "Sold", message: "This relic is gone.", onGlass: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { ReliquaryBackdrop() }
            .onAppear { leave() }
    }
}

/// "LEGEND · AWAKENED": the quality in its tone on dark, and the halo's word
/// when the relic is awakened.
private struct RelicCardQualityLine: View {
    let relic: Relic
    var point: CGFloat = 12
    var letterSpace: CGFloat = 1

    var body: some View {
        HStack(spacing: 0) {
            Text(relic.resolvedQuality.displayName.uppercased())
                .font(Theme.body(point).weight(.black))
                .tracking(letterSpace)
                .foregroundStyle(relic.resolvedQuality.tone)
            if relic.isAwakened {
                Text(" · AWAKENED")
                    .font(Theme.body(point).weight(.black))
                    .tracking(letterSpace)
                    .foregroundStyle(RelicPalette.halo)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// The main stat in its well, 38 tall: the stat, where the next level and
/// +15 take it, and its value at 24 points — star gold at +15.
private struct RelicCardMainWell: View {
    let relic: Relic

    var body: some View {
        let main = relic.effectiveMainStat
        let peaked = relic.isMaxLevel
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return HStack(spacing: 8) {
            Text(main.kind.displayName)
                .font(Theme.body(14).weight(.bold))
                .foregroundStyle(RelicPalette.label)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 6)
            roadLine
            Text("+\(main.kind.format(main.value))")
                .font(Theme.numeric(24).weight(.heavy))
                .foregroundStyle(peaked ? RelicPalette.star : RelicPalette.value)
                .shadow(color: RelicPalette.star.opacity(peaked ? 0.35 : 0), radius: 4)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(shape.fill(RelicPalette.well))
        .overlay(shape.strokeBorder(RelicPalette.bronze, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// "→ +97 · +15 +137" below +14, "→ +137" at +14, nothing at +15.
    @ViewBuilder
    private var roadLine: some View {
        if let words = roadWords {
            Text(words)
                .font(Theme.numeric(12.5))
                .foregroundStyle(RelicPalette.dim)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var roadWords: String? {
        guard let next = relic.nextMainStat else { return nil }
        var words = "→ +\(next.kind.format(next.value))"
        if relic.level < relic.maxLevel - 1 {
            let peak = relic.projectedMainStat(atLevel: relic.maxLevel)
            words += " · +15 +\(peak.kind.format(peak.value))"
        }
        return words
    }

    /// "ATK plus 93, next plus 97, at plus 15 plus 137".
    private var spoken: String {
        let main = relic.effectiveMainStat
        var words = "\(main.kind.displayName) plus \(main.kind.format(main.value))"
        if let next = relic.nextMainStat {
            words += ", next plus \(next.kind.format(next.value))"
        }
        if relic.level < relic.maxLevel - 1 {
            let peak = relic.projectedMainStat(atLevel: relic.maxLevel)
            words += ", at plus 15 plus \(peak.kind.format(peak.value))"
        }
        return words
    }
}

/// The sub stats in rows of 22 — the stat, its honing and its gem, the
/// value (the roll and the honing together) and its roll marks — the last
/// roll lit, and under them what the next sub waits on.
private struct RelicCardSubList: View {
    let relic: Relic
    var highlight: RelicService.SubStatChange? = nil
    /// The next row's words while a roll waits.
    var waitingWords: String = "choose one →"

    var body: some View {
        let subs = relic.effectiveSubStats
        let counts = RelicReading.rollCounts(relic)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(subs.indices, id: \.self) { index in
                subRow(index, sub: subs[index], count: index < counts.count ? counts[index] : nil)
            }
            nextRow
        }
    }

    private func subRow(_ index: Int, sub: StatModifier, count: Int?) -> some View {
        let lit = highlight.map { $0.kind == sub.kind } ?? false
        return HStack(spacing: 6) {
            Text(sub.kind.displayName)
                .font(Theme.body(13).weight(.semibold))
                .foregroundStyle(RelicPalette.label)
                .lineLimit(1)
                .fixedSize()
            honedChip(index, kind: sub.kind)
            gemMark(index)
            Spacer(minLength: 4)
            lastRollChip(lit)
            Text("+\(sub.kind.format(sub.value))")
                .font(Theme.numeric(16))
                .foregroundStyle(RelicPalette.value)
                .lineLimit(1)
                .fixedSize()
            // A gemmed sub has no marks (its rolls went with the gem); the
            // column keeps its width so the values stay in line.
            RollMarks(count: count)
                .frame(width: 52, alignment: .leading)
        }
        .frame(height: 22)
        .background { lastRollGround(lit) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(index, sub: sub, count: count, lit: lit))
    }

    @ViewBuilder
    private func honedChip(_ index: Int, kind: StatKind) -> some View {
        let bonus = relic.honedBonus(at: index)
        if bonus > 0 {
            RelicCardChip(text: "+\(kind.format(bonus))", tint: RelicPalette.honed)
        }
    }

    @ViewBuilder
    private func gemMark(_ index: Int) -> some View {
        if relic.gemmed == index {
            ItemIcon(key: "gem_hero", size: 14, glow: false)
        }
    }

    /// "new", or what the roll added as the player reads it ("+5%").
    @ViewBuilder
    private func lastRollChip(_ lit: Bool) -> some View {
        if lit, let change = highlight {
            RelicCardChip(text: change.isNew ? "new" : "+\(RelicReading.shownChange(change.kind, from: change.before, to: change.after))",
                          tint: RelicPalette.gain)
        }
    }

    @ViewBuilder
    private func lastRollGround(_ lit: Bool) -> some View {
        if lit {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(RelicPalette.gain.opacity(0.12))
                .padding(.horizontal, -4)
        }
    }

    @ViewBuilder
    private var nextRow: some View {
        if let words = nextWords {
            HStack(spacing: 5) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 12, weight: .semibold))
                Text(words)
                    .font(Theme.body(12))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(RelicPalette.quiet)
            .frame(height: 22)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(nextSpoken ?? words)
        }
    }

    private var nextWords: String? {
        let next = RelicReading.nextSubStat(relic)
        switch next {
        case .atLevel(let level):
            return "+\(level)"
        case .waiting:
            return waitingWords
        case .awaken:
            return "5th · awaken"
        case nil:
            return nil
        }
    }

    private var nextSpoken: String? {
        let next = RelicReading.nextSubStat(relic)
        switch next {
        case .atLevel(let level):
            return "Next sub stat at plus \(level)"
        case .waiting:
            return "A sub stat roll waits to be chosen"
        case .awaken:
            return "Awaken for a fifth sub stat"
        case nil:
            return nil
        }
    }

    private func spoken(_ index: Int, sub: StatModifier, count: Int?, lit: Bool) -> String {
        var words = "\(sub.kind.displayName) plus \(sub.kind.format(sub.value))"
        let bonus = relic.honedBonus(at: index)
        if bonus > 0 {
            words += ", honed plus \(sub.kind.format(bonus))"
        }
        if relic.gemmed == index {
            words += ", gemmed"
        } else if let count {
            words += count == 1 ? ", 1 roll" : ", \(count) rolls"
        }
        if lit {
            words += ", the last roll"
        }
        return words
    }
}

/// A small figure in a well capsule: a whetstone's bonus, the last roll's
/// gain, the gem's holder.
private struct RelicCardChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(Theme.numeric(11.5))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(Capsule().fill(RelicPalette.well))
            .overlay(Capsule().strokeBorder(RelicPalette.bronze, lineWidth: 0.8))
    }
}

/// One line of eyebrow gold with its glyph: what the next level brings,
/// where a 6★'s climb leads.
private struct RelicCardHint: View {
    let systemImage: String
    let words: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .black))
            Text(words)
                .font(Theme.body(12))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(RelicPalette.eyebrow)
    }
}

/// A sentence behind an `InfoDot`. The dot's popover is cream, so its words
/// are ink, as every other dot's are.
private struct RelicCardAside: View {
    let words: String

    var body: some View {
        Text(words)
            .font(Theme.body(12))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Next: 60% · ◉ 18,000": a rate and a price, read-only.
private struct RelicCardCostLine: View {
    let words: String
    let cost: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(words)
            Text("·")
            ItemIcon(key: "drachma", size: 14, glow: false)
            Text(cost.formatted())
        }
        .font(Theme.numeric(12.5))
        .foregroundStyle(RelicPalette.dim)
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(words), \(cost) drachma")
    }
}

/// The result strip: what an attempt, a run, a roll or a stone came to — a
/// check or a cross, the level or the verdict, the price, and what changed.
private struct RelicCardNews: View {
    let good: Bool
    let headline: String
    var coin: Int? = nil
    var words: String? = nil

    private var tone: Color { good ? RelicPalette.gain : RelicPalette.loss }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 15, style: .continuous)
        return HStack(spacing: 6) {
            Image(systemName: good ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(tone)
            Text(headline)
                .font(Theme.numeric(13))
                .foregroundStyle(tone)
                .lineLimit(1)
                .fixedSize()
            coinPart
            wordsPart
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .background(shape.fill(RelicPalette.well))
        .overlay(shape.strokeBorder(RelicPalette.bronze, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    @ViewBuilder
    private var coinPart: some View {
        if let coin {
            Text("·")
                .font(Theme.numeric(12.5))
                .foregroundStyle(RelicPalette.dim)
            ItemIcon(key: "drachma", size: 14, glow: false)
            Text(coin.formatted())
                .font(Theme.numeric(12.5))
                .foregroundStyle(RelicPalette.dim)
                .lineLimit(1)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var wordsPart: some View {
        if let words {
            Text("· \(words)")
                .font(Theme.numeric(12.5))
                .foregroundStyle(RelicPalette.value)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var spoken: String {
        var parts = [good ? "Done" : "Failed", headline]
        if let coin {
            parts.append("\(coin) drachma")
        }
        if let words {
            parts.append(words)
        }
        return parts.joined(separator: ", ")
    }
}

/// One of the choice of two: the stat, NEW or where it grows from and to,
/// and what it adds, large, in the gain green. The rim lights while pressed.
private struct RelicRollOffer: View {
    let offer: RelicService.RollCandidate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RelicRollOfferFace(change: offer.change)
        }
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        let change = offer.change
        let kind = change.kind
        if change.isNew {
            return "Take \(kind.displayName), new, plus \(kind.format(change.after))"
        }
        return "Take \(kind.displayName), plus \(kind.format(change.before)) to plus \(kind.format(change.after))"
    }
}

/// The offer's face, a view of its own so it can read the press
/// (`gamePressed`, set by `GamePressStyle` on its label).
private struct RelicRollOfferFace: View {
    let change: RelicService.SubStatChange
    @Environment(\.gamePressed) private var pressed

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(change.kind.displayName)
                    .font(Theme.body(15).weight(.bold))
                    .foregroundStyle(RelicPalette.value)
                    .lineLimit(1)
                    .fixedSize()
                detail
            }
            Spacer(minLength: 6)
            Text("+\(RelicReading.shownChange(change.kind, from: change.before, to: change.after))")
                .font(Theme.numeric(22).weight(.heavy))
                .foregroundStyle(RelicPalette.gain)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 58)
        .background(shape.fill(RelicPalette.well))
        .overlay { rim(shape) }
        .contentShape(shape)
    }

    @ViewBuilder
    private var detail: some View {
        if change.isNew {
            Text("NEW")
                .font(Theme.body(11).weight(.black))
                .tracking(0.8)
                .foregroundStyle(RelicPalette.eyebrow)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .frame(height: 17)
                .overlay(Capsule().strokeBorder(RelicPalette.eyebrow.opacity(0.7), lineWidth: 0.8))
        } else {
            Text("+\(change.kind.format(change.before)) → +\(change.kind.format(change.after))")
                .font(Theme.numeric(13))
                .foregroundStyle(RelicPalette.dim)
                .lineLimit(1)
                .fixedSize()
        }
    }

    @ViewBuilder
    private func rim(_ shape: RoundedRectangle) -> some View {
        if pressed {
            shape.strokeBorder(RelicCardInk.ring, lineWidth: 1.5)
        } else {
            shape.strokeBorder(RelicPalette.bronze, lineWidth: 1.2)
        }
    }
}

/// One colour to pay an awakening with: a dark well ringed in bronze (star
/// gold, twice as wide, for the set's own — the fair price), the element's
/// colour at its heart, a pale ring outside when chosen, and what is held
/// under it, green when it covers that colour's price.
private struct RelicCardPayChip: View {
    let element: Element
    let held: Int
    let need: Int
    let fair: Bool
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                disc
                Text("\(held)")
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(held >= need ? RelicPalette.gain : RelicPalette.dim)
                    .lineLimit(1)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel(spoken)
    }

    private var disc: some View {
        ZStack {
            Circle().fill(RelicPalette.well)
            fairRim
            Circle()
                .fill(element.color)
                .frame(width: 16, height: 16)
        }
        .frame(width: 30, height: 30)
        .overlay { chosenRing }
    }

    @ViewBuilder
    private var fairRim: some View {
        if fair {
            Circle().strokeBorder(RelicPalette.star, lineWidth: 2)
        } else {
            Circle().strokeBorder(RelicPalette.bronze, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var chosenRing: some View {
        if isOn {
            Circle()
                .strokeBorder(RelicCardInk.ring, lineWidth: 1.5)
                .padding(-3)
        }
    }

    private var spoken: String {
        var words = "\(element.displayName) Aether, \(held) held of \(need)"
        if fair {
            words += ", the set's own colour"
        }
        if isOn {
            words += ", paying with this"
        }
        return words
    }
}

/// The drop's showcase stone: the painted stone at 110 with its rim tinted
/// in the quality's enamel, in a radial of the quality's tone (and the halo
/// when awakened). The kit's stone art is private to the tile, so this is
/// the same two layers at one size.
private struct RelicCardDropStone: View {
    let relic: Relic

    private static let side: CGFloat = 110

    var body: some View {
        stone
            .frame(width: Self.side, height: Self.side)
            .background { glowLayer }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(RelicReading.spokenTile(relic))
    }

    private var glowLayer: some View {
        ZStack {
            RadialGradient(colors: [relic.resolvedQuality.tone.opacity(0.45), Color.clear],
                           center: .center, startRadius: 0, endRadius: 90)
            if relic.isAwakened {
                RadialGradient(colors: [RelicPalette.halo.opacity(0.42), Color.clear],
                               center: .center, startRadius: 0, endRadius: 84)
            }
        }
        .frame(width: 180, height: 180)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var stone: some View {
        if BundleArt.exists(relic.stoneImageName) {
            ZStack {
                BundleImage(name: relic.stoneImageName, renderedAt: Self.side)
                    .aspectRatio(contentMode: .fit)
                rim
            }
        } else {
            Image(systemName: relic.set.glyph)
                .font(.system(size: Self.side * 0.42, weight: .bold))
                .foregroundStyle(RelicPalette.star)
        }
    }

    /// `relic_rim` is a template: white on clear, tinted here.
    @ViewBuilder
    private var rim: some View {
        if let image = BundleArt.thumbnail(Relic.rimImageName, maxPixel: pixels) {
            Image(uiImage: image)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(relic.resolvedQuality.enamel)
        }
    }

    private var pixels: Int {
        max(1, Int((Self.side * UIScreen.main.scale).rounded(.up)))
    }
}

/// "SETS [+ FURY] [− VIGIL] [ZEPHYR]": what a change completes (gain), what
/// it breaks (loss), and the sets it keeps (eyebrow), three at most and a
/// count of the rest.
private struct RelicCardSetChips: View {
    let before: [ActiveRelicSet]
    let after: [ActiveRelicSet]

    var body: some View {
        let chips = RelicCardFigures.setChips(before: before, after: after)
        return HStack(spacing: 5) {
            Text("SETS")
                .font(Theme.body(11).weight(.black))
                .tracking(0.8)
                .foregroundStyle(RelicPalette.eyebrow)
                .lineLimit(1)
                .fixedSize()
            if chips.isEmpty {
                Text("none")
                    .font(Theme.body(12))
                    .foregroundStyle(RelicPalette.dim)
                    .lineLimit(1)
                    .fixedSize()
            }
            ForEach(Array(chips.prefix(3).enumerated()), id: \.offset) { _, chip in
                chipView(chip)
            }
            if chips.count > 3 {
                Text("+\(chips.count - 3)")
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(RelicPalette.dim)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .frame(height: 20)
    }

    private func chipView(_ chip: RelicCardSetChip) -> some View {
        Text(chip.text)
            .font(Theme.body(11).weight(.black))
            .foregroundStyle(chip.tint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(Capsule().fill(RelicPalette.well))
            .overlay(Capsule().strokeBorder(chip.tint.opacity(0.7), lineWidth: 1))
    }
}

/// One set chip's words and colour.
private struct RelicCardSetChip {
    let text: String
    let tint: Color
}

/// A ring colour no token names: the kit's own selection gold.
private enum RelicCardInk {
    static let ring: Color = Color(hex: "#FFE08A")
}

/// The arithmetic behind the card family's words: pure, no view.
private enum RelicCardFigures {
    /// "×3.0" or "×3.6": the +15 main stat's multiplier.
    static func multiplier(awakened: Bool) -> String {
        "×" + String(format: "%.1f", awakened ? Relic.awakenedPeak : Relic.peak)
    }

    /// "60%".
    static func percent(_ chance: Double) -> String {
        "\(Int((chance * 100).rounded()))%"
    }

    /// "CRIT DMG +21% → +26%", or "SPD new".
    static func changeWords(_ change: RelicService.SubStatChange) -> String {
        let kind = change.kind
        if change.isNew { return "\(kind.displayName) new" }
        return "\(kind.displayName) +\(kind.format(change.before)) → +\(kind.format(change.after))"
    }

    /// A run's roll, short: "SPD new", "CRIT DMG +5%".
    static func rollWords(_ change: RelicService.SubStatChange) -> String {
        let kind = change.kind
        if change.isNew { return "\(kind.displayName) new" }
        return "\(kind.displayName) +\(RelicReading.shownChange(kind, from: change.before, to: change.after))"
    }

    /// The unit as it would be with this relic in its slot.
    static func wearing(_ relic: Relic, on unit: ResolvedUnit) -> ResolvedUnit {
        var equipped = unit.relics.filter { $0.slot != relic.slot && $0.id != relic.id }
        equipped.append(relic)
        return ProgressionService.resolve(unit.unit, blueprint: unit.blueprint, equipped: equipped,
                                          boon: unit.boon, regalia: unit.regalia)
    }

    /// What the relic would add to a unit's power.
    static func gain(of relic: Relic, on unit: ResolvedUnit) -> Int {
        wearing(relic, on: unit).power - unit.power
    }

    static func bySlot(_ relics: [Relic]) -> [Int: Relic] {
        var slots: [Int: Relic] = [:]
        for relic in relics where slots[relic.slot] == nil {
            slots[relic.slot] = relic
        }
        return slots
    }

    static func bySlot(_ relics: [Relic], putting relic: Relic) -> [Int: Relic] {
        var slots = bySlot(relics)
        slots[relic.slot] = relic
        return slots
    }

    /// Manage's ledger: THEN's totals and THEN − NOW, where the change is the
    /// difference of the two figures as printed, so "29% → 33%" says 4%.
    static func ledger(before: Stats, after: Stats) -> [StatLedgerRow] {
        [
            ledgerRow("HP", before.hp, after.hp, percent: false),
            ledgerRow("ATK", before.atk, after.atk, percent: false),
            ledgerRow("DEF", before.def, after.def, percent: false),
            ledgerRow("SPD", before.spd, after.spd, percent: false),
            ledgerRow("CRIT Rate", before.critRate, after.critRate, percent: true),
            ledgerRow("CRIT DMG", before.critDamage, after.critDamage, percent: true),
            ledgerRow("Accuracy", before.accuracy, after.accuracy, percent: true),
            ledgerRow("Resistance", before.resistance, after.resistance, percent: true),
        ]
    }

    static func ledgerRow(_ label: String, _ before: Double, _ after: Double, percent: Bool) -> StatLedgerRow {
        let scale: Double = percent ? 100 : 1
        let shownBefore = Int((before * scale).rounded())
        let shownAfter = Int((after * scale).rounded())
        let delta = shownAfter - shownBefore
        let value = figure(shownAfter, percent: percent)
        guard delta != 0 else {
            return StatLedgerRow(label: label, value: value, change: nil, tone: .none)
        }
        let sign = delta > 0 ? "+" : "−"
        let change = sign + figure(abs(delta), percent: percent)
        let tone: LedgerTone = delta > 0 ? .gain : .loss
        return StatLedgerRow(label: label, value: value, change: change, tone: tone)
    }

    static func figure(_ shown: Int, percent: Bool) -> String {
        percent ? "\(shown)%" : shown.formatted()
    }

    /// The sets a change completes, breaks and keeps, by the old stat
    /// table's rule: a set counts as held when the other side has it at
    /// least as many times over.
    static func setChips(before: [ActiveRelicSet], after: [ActiveRelicSet]) -> [RelicCardSetChip] {
        let gained = after.filter { entry in
            !before.contains(where: { $0.set == entry.set && $0.completions >= entry.completions })
        }
        let lost = before.filter { entry in
            !after.contains(where: { $0.set == entry.set && $0.completions >= entry.completions })
        }
        // A set that loses one of two completions is a loss, never also a
        // kept chip beside it.
        let kept = after.filter { entry in
            !gained.contains(where: { $0.set == entry.set }) && !lost.contains(where: { $0.set == entry.set })
        }
        var chips: [RelicCardSetChip] = []
        for entry in gained {
            chips.append(RelicCardSetChip(text: "+ \(entry.set.displayName.uppercased())", tint: RelicPalette.gain))
        }
        for entry in lost {
            chips.append(RelicCardSetChip(text: "− \(entry.set.displayName.uppercased())", tint: RelicPalette.loss))
        }
        for entry in kept {
            chips.append(RelicCardSetChip(text: entry.set.displayName.uppercased(), tint: RelicPalette.eyebrow))
        }
        return chips
    }
}

/// A relic screen's scrolling column, drawn whole with no fade when its
/// content fits, and scrolling behind a fade over its last 12 points (its
/// content padded by as much, so the last row scrolls clear) only when it
/// does not — `RelicFitScroll`'s logic (runs 217–221), this file's own copy
/// under its own name. Measured with `GeometryReader`s, never
/// `ViewThatFits`, which lays out every candidate.
private struct CardFadingScroll<Content: View>: View {
    let fade: CGFloat
    let content: () -> Content
    @State private var contentHeight: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    init(fade: CGFloat = 12, @ViewBuilder content: @escaping () -> Content) {
        self.fade = fade
        self.content = content
    }

    private var overflows: Bool { contentHeight > viewportHeight + 0.5 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            content()
                .background(heightReader { contentHeight = $0 })
                .padding(.bottom, overflows ? fade : 0)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(heightReader { viewportHeight = $0 })
        .mask { footMask }
    }

    private var footMask: some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [Color.black, Color.black.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: overflows ? fade : 0)
        }
    }

    private func heightReader(_ report: @escaping (CGFloat) -> Void) -> some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            Color.clear
                .onAppear { report(height) }
                .onChange(of: height) { _, now in report(now) }
        }
    }
}
