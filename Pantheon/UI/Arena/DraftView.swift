import SwiftUI

/// The Draft Arena (2026-09-23; Docs/DRAFT.md): Summoners War's World Arena
/// draft on the Arena of Souls, against a demigod the game plays.
///
/// The genre's shape, landscape: the two sides' five places facing each
/// other down the left and right edges — the player's in gold with the faces
/// at the outer edge, the rival's mirrored in crimson — and between them the
/// pick-order track (ten numbered pips in the 1-2-2-2-2-1 order, the turn on
/// the clock breathing, the phase's words under it) over one glass panel that
/// changes with the phase: the coin; the player's box as a grid with element
/// and role filters and a Lock in bar that reads the unit tapped against the
/// rival's picks; the rival's five to strike, each with why it matters; the
/// four to crown with the leader's words and FIGHT; and after the bout, the
/// crown and the rating it moved. The painting is the lobby's, full bleed,
/// with dark glass where the words go (phase B's rule for a PLACE).
///
/// Every size is solved once from the frame (`DraftBoardMetrics`): an iPhone
/// 16 Pro gives the board 750 × 329 points under the strip.
struct DraftView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var draftBoard: DraftBoardModel
    @State private var fightContext: BattleContext?
    @State private var fightEngine: BattleEngine?
    /// The chest just claimed, shown as tiles for a moment.
    @State private var chestShown: DraftChest?

    /// `tourStage` freezes the board mid-draft for the CI tour (`DraftService
    /// .scriptedSession`); nil is the game's own board.
    init(tourStage: DraftTourStage? = nil) {
        _draftBoard = StateObject(wrappedValue: DraftBoardModel(tourStage: tourStage))
    }

    /// The Arena of Souls, where the lobby stands and every arena bout is
    /// fought, anchored a little lower than the lobby's crop: the board
    /// covers the gods' heads with glass anyway, and the open gaps between
    /// the columns show the sand and the stands.
    private static let painting = "arena_of_souls_bg"
    private static let paintingFocus = UnitPoint(x: 0.5, y: 0.34)

    var body: some View {
        GameScreen("Draft Arena", dismiss: { dismiss() }) {
            if store.draftRecord.pendingChest != nil {
                BarButton(title: "Chest", systemImage: "gift.fill", tint: Theme.gold) {
                    claimChest()
                }
            }
            paidWell
            ratingWell
        } content: {
            place
        }
        .onAppear { draftBoard.prepare(store: store) }
        .fullScreenCover(item: $fightContext, onDismiss: { draftBoard.concludeFight(store: store) }) { context in
            fightScreen(context)
        }
    }

    // MARK: - The strip

    /// The day's paid bouts: five pay laurels; every bout moves the rating.
    private var paidWell: some View {
        let record = store.draftRecord
        let today = record.dayKey == EventCalendar.dayKey(Date()) ? record.paidToday : 0
        let left = max(0, DraftService.paidBoutsPerDay - today)
        return HStack(spacing: 5) {
            ItemIcon(key: "laurels", size: 18, glow: false)
            Text("\(left)/\(DraftService.paidBoutsPerDay)")
                .font(Theme.numeric(12.5))
                .foregroundStyle(left > 0 ? Theme.onGlass : Theme.onGlassDim)
                .lineLimit(1)
                .fixedSize()
            Text("paid")
                .font(Theme.body(11))
                .foregroundStyle(Theme.onGlassDim)
                .lineLimit(1)
                .fixedSize()
        }
        .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
        .padding(.horizontal, 10)
        .frame(height: ScreenChrome.control)
        .background(BarWell())
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(left) of \(DraftService.paidBoutsPerDay) paid bouts left today")
    }

    /// The crown, its name in its colour, the rating, and the ? that opens
    /// the ladder.
    private var ratingWell: some View {
        let record = store.draftRecord
        return HStack(spacing: 5) {
            DraftCrest(tier: record.tier, size: 20)
            Text(record.tier.displayName.uppercased())
                .font(Theme.body(11).weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(record.tier.color)
                .lineLimit(1)
                .fixedSize()
            Text(record.rating.formatted())
                .font(Theme.numeric(12.5))
                .foregroundStyle(Theme.onGlass)
                .lineLimit(1)
                .fixedSize()
            InfoDot(title: "The crowns") { crownLadder }
        }
        .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: ScreenChrome.control)
        .background(BarWell())
        .fixedSize()
    }

    /// The ? beside the rating: every crown with its floor and a won bout's
    /// laurels there, the player's own row lit, and the rules in two lines.
    /// The cream popover every ? opens, so it is in the cream screens' ink.
    private var crownLadder: some View {
        let current = store.draftRecord.tier
        return VStack(alignment: .leading, spacing: 6) {
            Text("Each crown's floor, and the laurels a won bout pays there.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(DraftTier.allCases) { tier in
                HStack(spacing: 6) {
                    DraftCrest(tier: tier, size: 20)
                    Text(tier.displayName)
                        .font(Theme.body(12).weight(.bold))
                        .foregroundStyle(tier == current ? Theme.goldDeep : Theme.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 6)
                    Text("\(tier.threshold.formatted())+")
                        .font(Theme.numeric(11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                    HStack(spacing: 2) {
                        ItemIcon(key: "laurels", size: 14, glow: false)
                        Text("+\(tier.laurelsForWin)")
                            .font(Theme.numeric(11.5))
                            .foregroundStyle(Theme.success)
                            .lineLimit(1)
                    }
                    .fixedSize()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tier == current ? Theme.gold.opacity(0.16) : Color.clear)
                )
            }
            Text("Five bouts a day pay laurels; every bout moves the rating. A week of three bouts or more leaves a chest for its crown. Every four weeks the Olympiad turns and the rating falls halfway back to 1,000.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The place

    private var place: some View {
        GeometryReader { geo in
            let metrics = DraftBoardMetrics(size: geo.size)
            ZStack {
                PlaceBackdrop(painting: Self.painting, focus: Self.paintingFocus, wash: Color.black.opacity(0.18),
                              topScrim: 0.5, footScrim: 0.6)
                boardOrWait(metrics)
                if let chest = chestShown {
                    chestReceipt(chest)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 12)
                }
            }
        }
    }

    @ViewBuilder
    private func boardOrWait(_ metrics: DraftBoardMetrics) -> some View {
        if let session = draftBoard.session {
            board(session, metrics)
        } else if draftBoard.isLocked {
            EmptyState(
                icon: "person.2.slash",
                title: "Five to draft",
                message: "The Draft Arena asks for five different monsters of your own. Summon or fuse to fill your box.",
                onGlass: true
            )
            .background(GlassPlate(radius: 12))
            .frame(maxWidth: 440)
        } else {
            EmptyState(
                icon: "hourglass",
                title: "Finding a rival",
                message: "A demigod of your standing is choosing a box.",
                onGlass: true
            )
            .background(GlassPlate(radius: 12))
            .frame(maxWidth: 440)
        }
    }

    private func board(_ session: DraftSession, _ metrics: DraftBoardMetrics) -> some View {
        let record = store.draftRecord
        return HStack(alignment: .top, spacing: DraftBoardMetrics.gap) {
            DraftSideColumn(
                side: .player,
                title: "You",
                detail: record.rating.formatted(),
                tier: record.tier,
                slots: draftBoard.slots(.player, in: session),
                slotHeight: metrics.slot,
                nameSize: metrics.nameSize
            ) { id in
                draftBoard.tapSlot(id)
            }
            .frame(width: metrics.side)

            VStack(spacing: 6) {
                DraftOrderTrack(
                    order: session.order,
                    made: session.picks.count,
                    pending: draftBoard.pending.count,
                    onClock: session.sideToPick,
                    prompt: DraftWords.prompt(session, pending: draftBoard.pending.count, report: draftBoard.report)
                )
                middle(session, metrics)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            DraftSideColumn(
                side: .rival,
                title: session.rival.name,
                detail: session.rival.rating.formatted(),
                tier: session.rival.tier,
                slots: draftBoard.slots(.rival, in: session),
                slotHeight: metrics.slot,
                nameSize: metrics.nameSize
            ) { id in
                draftBoard.tapSlot(id)
            }
            .frame(width: metrics.side)
        }
        .padding(.horizontal, ScreenChrome.contentPadding)
        .padding(.vertical, 6)
    }

    /// The panel between the columns, by phase — and after a bout, its report.
    @ViewBuilder
    private func middle(_ session: DraftSession, _ metrics: DraftBoardMetrics) -> some View {
        if let report = draftBoard.report {
            resultPanel(report)
        } else {
            switch session.phase {
            case .toss:
                tossPanel(session, metrics)
            case .picking:
                pickPanel(session, metrics)
            case .banning:
                banPanel(session, metrics)
            case .leaders:
                leaderPanel(session)
            }
        }
    }

    // MARK: - The coin

    private func tossPanel(_ session: DraftSession, _ metrics: DraftBoardMetrics) -> some View {
        let first = session.firstPicker == .player ? "You pick first" : "\(session.rival.name) picks first"
        return VStack(spacing: 10) {
            Spacer(minLength: 0)
            DraftCoin(size: metrics.compact ? 60 : 78)
            // Two lines on a narrow middle rather than a smaller face:
            // "ARISTAIOS PICKS FIRST" is 340 points at 20.
            Text(first.uppercased())
                .font(Theme.display(20))
                .tracking(1.2)
                .carved(multiline: true)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("One pick, then two each way, then one: five a side, each from its own box. Then each strikes one of the other's five, and four fight.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.onGlassDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
            DraftActionButton(title: "Begin", systemImage: "play.fill") {
                draftBoard.beginPicking()
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlassPlate(radius: 12))
    }

    // MARK: - The picks

    private func pickPanel(_ session: DraftSession, _ metrics: DraftBoardMetrics) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                ElementFilterTiles(selection: $draftBoard.elementFilter)
                DraftRoleTiles(selection: $draftBoard.roleFilter)
                Spacer(minLength: 0)
            }
            RestingList(onGlass: true) {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: metrics.tile, maximum: metrics.tile + 14), spacing: 6)],
                    spacing: 7
                ) {
                    ForEach(draftBoard.roster(in: session)) { unit in
                        DraftRosterTile(unit: unit, size: metrics.tile, state: draftBoard.tileState(unit, in: session)) {
                            draftBoard.tap(unit.id)
                        }
                        .restingRow(goneBelow: 0.85, wholeFrom: 0.98)
                    }
                }
                .padding(.top, 6)
                .padding(.bottom, RowRest.footFade)
            }
            lockBar(session)
        }
        .padding(8)
        .background(GlassPlate(radius: 12))
    }

    /// The unit tapped, read against the rival's picks — or, while the rival
    /// is on the clock or nothing is tapped, the rival's last decision — and
    /// Lock in.
    private func lockBar(_ session: DraftSession) -> some View {
        HStack(spacing: 8) {
            lockWords(session)
                .frame(maxWidth: .infinity, alignment: .leading)
            DraftActionButton(title: "Lock in", systemImage: "lock.fill", isEnabled: draftBoard.canLockIn) {
                draftBoard.lockIn()
            }
        }
        .frame(height: 46)
    }

    @ViewBuilder
    private func lockWords(_ session: DraftSession) -> some View {
        let rivalOnClock = session.sideToPick == .rival
        if !rivalOnClock, let id = draftBoard.inspected, let unit = session.unit(id) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(DraftService.captionName(unit))
                        .font(Theme.body(13).weight(.bold))
                        .foregroundStyle(Theme.onGlass)
                        .lineLimit(1)
                        .fixedSize()
                    Image(systemName: unit.element.glyph)
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(unit.element.color)
                    Text(unit.power.formatted())
                        .font(Theme.numeric(11.5))
                        .foregroundStyle(Theme.onGlassGold)
                        .lineLimit(1)
                        .fixedSize()
                }
                Text(DraftWords.matchupNote(unit, against: session.picked(.rival)))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.onGlassDim)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
        } else if let line = draftBoard.rivalLine {
            Text(line)
                .font(Theme.body(11.5))
                .foregroundStyle(Theme.onGlassDanger)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
        } else {
            let hint: String = rivalOnClock
                ? "\(session.rival.name) is weighing your picks against the box."
                : "Tap your units to choose them, then lock them in. Two of one monster cannot stand in one five."
            Text(hint)
                .font(Theme.body(11.5))
                .foregroundStyle(Theme.onGlassDim)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - The strikes

    private func banPanel(_ session: DraftSession, _ metrics: DraftBoardMetrics) -> some View {
        let theirs = session.picked(.rival)
        let yours = session.picked(.player)
        return VStack(spacing: 8) {
            GlassSectionHeader(title: "Strike one", accessory: "theirs on you is sealed", accessoryTint: Theme.onGlassDanger)
            HStack(alignment: .top, spacing: 6) {
                ForEach(theirs) { unit in
                    strikeCandidate(unit, note: DraftWords.threatNote(unit, yours: yours, theirs: theirs), size: metrics.banTile)
                }
            }
            .frame(maxWidth: .infinity)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Text(DraftWords.sealedLine(session))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.onGlassDim)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                DraftActionButton(title: "Strike", systemImage: "xmark", tone: .crimson,
                                  isEnabled: draftBoard.banTarget != nil) {
                    draftBoard.commitBan()
                }
            }
        }
        .padding(10)
        .background(GlassPlate(radius: 12))
    }

    private func strikeCandidate(_ unit: ResolvedUnit, note: String, size: CGFloat) -> some View {
        let isTarget = draftBoard.banTarget == unit.id
        let shape = RoundedRectangle(cornerRadius: max(6, min(Theme.tightCorner, size * 0.14)), style: .continuous)
        return Button {
            draftBoard.strike(unit.id)
        } label: {
            VStack(spacing: 3) {
                UnitPortraitTile(unit: unit, size: size)
                    .overlay {
                        if isTarget {
                            DraftStrike(size: size)
                        }
                    }
                    .overlay(shape.strokeBorder(isTarget ? DraftPalette.strike : Color.clear, lineWidth: 2))
                Text(DraftService.captionName(unit))
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(isTarget ? Theme.onGlassDanger : Theme.onGlass)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(note)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.onGlassDim)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: size + 12)
            .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
        }
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel("Strike \(unit.name)")
    }

    // MARK: - The crowns

    private func leaderPanel(_ session: DraftSession) -> some View {
        let four = session.survivors(.player)
        let crowned = four.first(where: { $0.id == session.playerLeader })
        let rivalFour = session.survivors(.rival)
        let rivalCrowned = rivalFour.first(where: { $0.id == session.rivalLeader })
        let yourPower = four.reduce(0) { $0 + $1.power }
        let theirPower = rivalFour.reduce(0) { $0 + $1.power }
        return VStack(alignment: .leading, spacing: 6) {
            GlassSectionHeader(title: "Your leader", accessory: "its arena skill leads")
            HStack(spacing: 10) {
                ForEach(four) { unit in
                    Button {
                        draftBoard.crown(unit.id)
                    } label: {
                        UnitPortraitTile(unit: unit, size: 50, isLeader: unit.id == session.playerLeader)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                                    .strokeBorder(unit.id == session.playerLeader ? Theme.gold : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(GamePressStyle(.plate))
                    .accessibilityLabel("Crown \(unit.name)")
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            Text(DraftWords.crownLine(crowned))
                .font(Theme.body(11.5))
                .foregroundStyle(Theme.onGlass)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle()
                .fill(Theme.glassRim.opacity(0.3))
                .frame(height: 1)
            HStack(spacing: 8) {
                if let rivalCrowned {
                    UnitPortraitTile(unit: rivalCrowned, size: 36, isLeader: true)
                }
                Text(DraftWords.leaderLine(session))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.onGlassDim)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("POWER")
                        .font(Theme.body(11).weight(.heavy))
                        .tracking(0.6)
                        .foregroundStyle(Theme.onGlassDim)
                        .lineLimit(1)
                        .fixedSize()
                    Text("\(yourPower.formatted()) v \(theirPower.formatted())")
                        .font(Theme.numeric(12))
                        .foregroundStyle(Theme.onGlass)
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer(minLength: 4)
                DraftActionButton(title: "Fight", systemImage: "flame.fill", isEnabled: session.isReady) {
                    beginFight()
                }
            }
        }
        .padding(10)
        .background(GlassPlate(radius: 12))
    }

    // MARK: - After the bout

    private func resultPanel(_ report: DraftBoutReport) -> some View {
        let record = store.draftRecord
        let tier = report.tierAfter
        let title: String
        if report.promoted {
            title = "A new crown"
        } else if report.outcome == .victory {
            title = "Victory"
        } else {
            title = "Defeat"
        }
        let swing = report.delta >= 0 ? "+\(report.delta)" : "\(report.delta)"
        let purse = report.laurels > 0
            ? "+\(report.laurels) laurels · \(report.paidBoutsLeft) paid bouts left today"
            : "Today's paid bouts are spent; the rating still counts."
        return VStack(spacing: 6) {
            Text(title.uppercased())
                .font(Theme.display(28))
                .tracking(1.4)
                .carved()
                .lineLimit(1)
                .fixedSize()
                .opacity(report.outcome == .victory ? 1 : 0.8)
            HStack(spacing: 12) {
                DraftCrest(tier: tier, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tier.displayName.uppercased())
                        .font(Theme.title(16))
                        .tracking(1.2)
                        .foregroundStyle(tier.color)
                        .lineLimit(1)
                        .fixedSize()
                    Text(tier.crown)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.onGlassDim)
                        .lineLimit(1)
                        .fixedSize()
                    HStack(spacing: 6) {
                        Text(record.rating.formatted())
                            .font(Theme.numeric(16))
                            .foregroundStyle(Theme.onGlass)
                            .lineLimit(1)
                            .fixedSize()
                        Text(swing)
                            .font(Theme.numeric(13))
                            .foregroundStyle(report.delta >= 0 ? Theme.onGlassSuccess : Theme.onGlassDanger)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            if let next = tier.next {
                GlassMeter(
                    value: Double(record.rating - tier.threshold),
                    maximum: Double(max(1, next.threshold - tier.threshold)),
                    tint: tier.color,
                    height: 6
                )
                .frame(width: 220)
                Text("\(next.displayName.uppercased()) IN \(max(0, next.threshold - record.rating).formatted())")
                    .font(Theme.body(11).weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(Theme.onGlassDim)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                Text("THE LAST CROWN")
                    .font(Theme.body(11).weight(.heavy))
                    .tracking(0.6)
                    .foregroundStyle(Theme.onGlassGold)
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(purse)
                .font(Theme.body(11.5))
                .foregroundStyle(report.laurels > 0 ? Theme.onGlassSuccess : Theme.onGlassDim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                DraftActionButton(title: "Leave", tone: .glass, minWidth: 96) {
                    dismiss()
                }
                DraftActionButton(title: "Draft again", systemImage: "arrow.triangle.2.circlepath") {
                    draftBoard.again(store: store)
                }
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GlassPlate(radius: 12))
    }

    // MARK: - The fight

    @ViewBuilder
    private func fightScreen(_ context: BattleContext) -> some View {
        if case .draft = context, let engine = fightEngine {
            BattleView(model: BattleViewModel(engine: engine, context: context, store: store))
                .environmentObject(store)
        } else {
            Theme.surface.ignoresSafeArea()
                .onAppear { fightContext = nil }
        }
    }

    private func beginFight() {
        guard let made = draftBoard.beginFight(store: store) else { return }
        let fighters = made.bout.playerTeam + made.bout.rivalTeam
        ModelLibrary.shared.warm(forms: fighters.map { (spec: $0.blueprint.model, awakened: $0.unit.isAwakened) }, crowded: true)
        fightEngine = made.engine
        fightContext = .draft(made.bout)
    }

    // MARK: - The week's chest

    private func claimChest() {
        guard let paid = store.claimDraftChest() else { return }
        withAnimation(Motion.celebrate) {
            chestShown = paid
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            withAnimation(.easeOut(duration: 0.3)) {
                chestShown = nil
            }
        }
    }

    /// What the chest paid, as the genre's strip of reward tiles.
    private func chestReceipt(_ chest: DraftChest) -> some View {
        VStack(spacing: 6) {
            Text("\(chest.tier.displayName) chest".uppercased())
                .font(Theme.title(13))
                .tracking(1.4)
                .carved(glow: false)
                .lineLimit(1)
                .fixedSize()
            HStack(alignment: .top, spacing: 10) {
                RewardTile(key: "laurels", title: "Laurels", amount: "+\(chest.laurels)", size: 48, showsTitle: false, onGlass: true)
                ForEach(Array(chest.scrolls.enumerated()), id: \.offset) { _, part in
                    RewardTile(grant: .scrolls(part.scroll, part.count), size: 48, showsTitle: false, onGlass: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(GlassPlate(radius: 12, opacity: 0.82))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .allowsHitTesting(false)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
