import Foundation
import SceneKit
import SwiftUI

/// The battle screen: 3D stage underneath, HUD on top.
///
/// The HUD answers four questions, and every piece below exists to answer
/// exactly one of them without the player stopping to look:
///
///   *Whose turn is it?* — the gold dot on the attack gauge, the gold ring on
///   that unit's team plate, and the actor plate in the bottom-left corner,
///   which is filled during an enemy turn as well as the player's so the
///   corner never goes blank and never means two different things.
///   *Who is next?* — the gauge, read left to right.
///   *What just happened to whom?* — the combat feed on the right: one line
///   per health change and per status landing, named, on its own dark plate.
///   The 3D damage numbers land on a sunlit floor and were measured at 1.05:1
///   against it; these are 14:1 whatever the stage.
///   *What will this button do?* — every skill tile carries its own forecast
///   line (estimated damage, hit count, or HEAL/BUFF), and the plate spells
///   out the skill in hand before it is committed rather than after.
struct BattleView: View {

    @State private var ultimateFlash: Double = 0
    @StateObject var model: BattleViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showForfeitConfirm = false
    @State private var showLog = false
    @State private var summary: BattleSummary?
    /// A skill held down: its card shows until a tap or four seconds.
    @State private var heldSkill: Skill?

    /// The skill under the player's finger, before the tap has committed to
    /// anything. A press on a tile sets it and a lift clears it, so the plate
    /// describes a skill *while it is being considered* — the old plate only
    /// ever described a skill that had already been chosen, and skills that
    /// pick their own targets fire on the tap, so those were never described
    /// at all.
    @State private var previewSlot: Int?

    /// The combat feed, and the snapshots it is diffed against. The model
    /// publishes `displayedCombatants` one battle event at a time, so a
    /// health delta between two publishes is exactly one hit.
    @State private var feed: [BattleFeedEntry] = []
    @State private var lastHealth: [UUID: Double] = [:]
    @State private var lastStatuses: [UUID: Set<StatusKind>] = [:]
    /// Drives the halo on the ready dot. Started once, in `onAppear`.
    @State private var readyPulse = false

    /// One line of the combat feed.
    struct BattleFeedEntry: Identifiable {
        let id = UUID()
        var glyph: String
        var name: String
        var value: String
        var tint: Color
        var isPlayer: Bool
    }

    var body: some View {
        ZStack {
            BattleSceneView(controller: model.sceneController) { id in
                model.tapUnit(id)
            }
            .ignoresSafeArea()

            // A landscape HUD: one row across the top with the turn order in
            // it, the two teams' readouts down the sides, and a bottom bar
            // whose middle is open, so a short screen keeps its centre for
            // the stage.
            //
            // It is measured against the height it is actually handed and not
            // against a full-size phone's, because every band of it but the
            // team column has a fixed height that cannot give, and a VStack
            // that runs out of room does not shrink or clip — it draws past
            // its frame, which here means the skill buttons slide under the
            // home indicator. The HUD gets 381 points on a 16 Pro and 354 on
            // a 13 mini, which iOS 17 still runs: 375 on its side with 21 of
            // them under the indicator.
            GeometryReader { geo in
                let boss = model.displayedCombatants.first { $0.isBoss && $0.isAlive }
                VStack(spacing: 6) {
                    topBar
                    if let boss {
                        bossBar(boss)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        teamColumn(plate: teamPlateHeight(hudHeight: geo.size.height, boss: boss != nil))
                        Spacer(minLength: 0)
                        combatFeed
                    }
                    Spacer(minLength: 0)
                    commandBar
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }

            // The frame goes white for a beat as an ultimate's cut-in lands.
            Color.white
                .opacity(ultimateFlash)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .onChange(of: model.cutIn) { _, cutIn in
                    guard let cutIn, !cutIn.isSpeech else { return }
                    ultimateFlash = 0.6
                    withAnimation(.easeOut(duration: 0.5)) { ultimateFlash = 0 }
                }

            if let cutIn = model.cutIn {
                cutInBanner(cutIn)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                    .onAppear {
                        // A skill's name is read at a glance; a sentence is
                        // not, so a boss's line is held nearly twice as long.
                        DispatchQueue.main.asyncAfter(deadline: .now() + (cutIn.isSpeech ? 2.4 : 1.15)) {
                            withAnimation(.easeIn(duration: 0.2)) {
                                if model.cutIn == cutIn { model.cutIn = nil }
                            }
                        }
                    }
            }

            if showLog { logOverlay }

            if let heldSkill {
                skillCard(heldSkill)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .onTapGesture { withAnimation { self.heldSkill = nil } }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            withAnimation { self.heldSkill = nil }
                        }
                    }
            }

            if let banner = model.repeatBanner {
                Text(banner)
                    .font(Theme.title(16))
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Theme.plate.opacity(0.6)))
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            withAnimation { model.repeatBanner = nil }
                        }
                    }
            }

            if let summary {
                BattleResultView(summary: summary) { dismiss() }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            model.begin()
            // A chapter boss or a raid says its one line as the fight opens;
            // every other stage returns from this without doing anything.
            model.announceBoss()
            AudioLibrary.shared.playMusic(.battle)
            withAnimation(.easeInOut(duration: 0.75).repeatForever(autoreverses: true)) {
                readyPulse = true
            }
        }
        .onDisappear { AudioLibrary.shared.playMusic(.island) }
        // Any health or status change anywhere on the field, hashed into one
        // Int. `log.count` cannot be the trigger: the log is trimmed at 200
        // lines, so in a long fight the count stops rising and `onChange`
        // stops firing while the fight carries on.
        .onChange(of: battlePulse) { _, _ in ingestFeed() }
        // A new actor means the old one's skill preview is meaningless.
        .onChange(of: model.awaitingActor?.id) { _, _ in previewSlot = nil }
        .onChange(of: model.outcome?.outcome) { _, newValue in
            guard newValue != nil else { return }
            // Let the last animation land before the result panel takes over.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // On a repeat run this banks the loot and starts the next
                // fight instead of returning a panel.
                if let concluded = model.conclude() {
                    withAnimation(.easeOut(duration: 0.35)) {
                        summary = concluded
                    }
                }
            }
        }
        .confirmationDialog(
            "Forfeit this battle?",
            isPresented: $showForfeitConfirm,
            titleVisibility: .visible
        ) {
            Button("Forfeit", role: .destructive) { model.forfeit() }
            Button("Keep fighting", role: .cancel) {}
        } message: {
            Text("It counts as a loss, and energy already spent is not refunded.")
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                showForfeitConfirm = true
            } label: {
                hudChip {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 14)
                }
            }

            hudChip {
                // One line, always: a boss stage is named "<place> — Confrontation",
                // long enough to wrap and shove the whole HUD down over the field.
                Text(model.context.title)
                    .font(Theme.title(14))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 150, alignment: .leading)
            }

            if model.waveCount > 1 {
                hudChip {
                    Text("Wave \(model.waveIndex)/\(model.waveCount)")
                        .font(Theme.numeric(11))
                        .foregroundStyle(Theme.gold)
                        .lineLimit(1)
                }
            }

            turnGauge

            Spacer(minLength: 0)

            Button {
                model.autoBattle.toggle()
            } label: {
                hudChip(active: model.autoBattle) {
                    Text("AUTO")
                        .font(Theme.body(11).weight(.bold))
                        .foregroundStyle(model.autoBattle ? Theme.gold : Theme.textSecondary)
                }
            }
            .accessibilityAddTraits(model.autoBattle ? .isSelected : [])

            Button {
                model.speed = model.speed >= 3 ? 1 : model.speed * 2
            } label: {
                hudChip(active: model.speed > 1) {
                    Text("×\(Int(model.speed))")
                        .font(Theme.numeric(12).weight(.bold))
                        .foregroundStyle(model.speed > 1 ? Theme.gold : Theme.textSecondary)
                        .frame(minWidth: 20)
                }
            }

            if let session = model.repeatSession {
                // Runs done of runs asked for; a tap stops after this one.
                Button {
                    model.stopRepeating()
                } label: {
                    hudChip(active: true) {
                        HStack(spacing: 4) {
                            Image(systemName: "repeat")
                            Text("\(min(session.completed + 1, session.requested))/\(session.requested)")
                        }
                        .font(Theme.numeric(11).weight(.bold))
                        .foregroundStyle(Theme.gold)
                    }
                }
            }

            Button {
                withAnimation { showLog.toggle() }
            } label: {
                hudChip(active: showLog) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(showLog ? Theme.gold : Theme.textSecondary)
                        .frame(width: 16)
                }
            }
        }
        .padding(.top, 6)
    }

    /// One height and one shape for every control in the top row, and one way
    /// for a stateful control — AUTO, fast-forward, the log — to say it is
    /// on: a gold plate under a gold hairline.
    private func hudChip<C: View>(active: Bool = false, @ViewBuilder _ content: () -> C) -> some View {
        content()
            .frame(height: 30)
            .padding(.horizontal, 10)
            .background(Capsule().fill(active ? Theme.goldDeep.opacity(0.92) : Theme.plate.opacity(0.6)))
            .overlay(Capsule().strokeBorder(active ? Theme.gold : Theme.stroke, lineWidth: 1))
    }

    // MARK: - The attack gauge

    /// The genre's clock: every living unit's portrait slides along one
    /// track as its attack bar fills — yours above the line with a blue
    /// ring, theirs below with a red one, gold where a unit stands ready.
    /// Read left to right it is the turn order and the distance between
    /// turns, and a speed buff or a bar knock is visible the moment it lands.
    ///
    /// Each portrait also wears its own health as an arc around it. That is
    /// the only readout in the frame that covers the *enemy* line, and it
    /// means "who is nearly dead" and "who moves next" are one glance rather
    /// than two.
    private var turnGauge: some View {
        let units = model.displayedCombatants.filter(\.isAlive)
        let dot: CGFloat = 26
        return GeometryReader { geo in
            let width = geo.size.width
            let placed = gaugePositions(units, width: width, dot: dot)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.plate.opacity(0.6))
                    .frame(width: width, height: 10)
                    .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
                ForEach(1..<4, id: \.self) { quarter in
                    Rectangle()
                        .fill(Theme.stroke)
                        .frame(width: 1, height: 10)
                        .offset(x: width * CGFloat(quarter) / 4)
                }
                // The far end of the track is where a turn happens. Painting
                // it gold gives the gold dot somewhere to have arrived at,
                // instead of leaving it as one more coloured circle in a row.
                Capsule()
                    .fill(Theme.gold.opacity(0.30))
                    .frame(width: 18, height: 10)
                    .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.7), lineWidth: 1))
                    .offset(x: max(0, width - 18))
                ForEach(units) { unit in
                    let x = placed[unit.id] ?? 0
                    gaugeDot(unit, ready: model.awaitingActor?.id == unit.id)
                        .offset(x: x, y: unit.side == .player ? -9 : 9)
                        .animation(.easeOut(duration: 0.35), value: x)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        // Flexible, because the row it sits in also carries a stage name, a
        // wave counter and a repeat chip; fixed at 300 it pushed them off.
        // Two calls, not one: `frame` has a fixed overload and a flexible
        // one and no overload mixes their labels.
        .frame(minWidth: 150, maxWidth: 260)
        .frame(height: 48)
    }

    /// Where each portrait sits on the track. Two units with level bars land
    /// on the same pixel — and a fresh wave arrives with every enemy at zero,
    /// so three enemies read as one dot. Walk each side in bar order and hold
    /// each portrait a little clear of the one before it; the order, which is
    /// what the gauge is for, is unchanged.
    private func gaugePositions(_ units: [Combatant], width: CGFloat, dot: CGFloat) -> [UUID: CGFloat] {
        let span = max(0, width - dot)
        var placed: [UUID: CGFloat] = [:]
        for side in [BattleSide.player, BattleSide.opponent] {
            var lastX = -CGFloat.greatestFiniteMagnitude
            let line = units
                .filter { $0.side == side }
                .sorted { $0.attackBar < $1.attackBar }
            for unit in line {
                let ready = model.awaitingActor?.id == unit.id
                let fraction = ready ? 1.0 : min(1, max(0, unit.attackBar))
                let x = min(max(CGFloat(fraction) * span, lastX + dot * 0.62), span)
                placed[unit.id] = x
                lastX = x
            }
        }
        return placed
    }

    private func gaugeDot(_ unit: Combatant, ready: Bool) -> some View {
        let portrait = unit.model.portraitName(awakened: unit.isAwakened)
        let ring = ready ? Theme.gold : (unit.side == .player ? Theme.info : Theme.danger)
        return ZStack {
            // A halo that is only ever worn by the unit whose turn it is, and
            // that breathes, so the gold dot is found by movement before it is
            // found by colour.
            if ready {
                Circle()
                    .fill(Theme.gold.opacity(0.35))
                    .frame(width: 34, height: 34)
                    .scaleEffect(readyPulse ? 1.22 : 0.96)
                    .blur(radius: 3)
            }
            Circle()
                .fill(unit.side == .player ? Theme.info.opacity(0.35) : Theme.danger.opacity(0.35))
            if BundleImage.exists(portrait) {
                BundleImage(name: portrait)
                    .aspectRatio(contentMode: .fill)
                    .clipShape(Circle())
            } else {
                Text(String(unit.name.prefix(1)))
                    .font(Theme.body(10).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            // The health arc, on a black channel of its own so it never has to
            // be read against the portrait behind it.
            Circle()
                .strokeBorder(Color.black.opacity(0.7), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(max(0.02, unit.healthFraction)))
                .stroke(healthTint(unit.healthFraction), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(1.5)
                .animation(.easeOut(duration: 0.25), value: unit.healthFraction)
            Circle()
                .strokeBorder(ring, lineWidth: ready ? 2 : 1)
        }
        .frame(width: 26, height: 26)
        .scaleEffect(ready ? 1.2 : 1)
        .shadow(color: ready ? Theme.gold.opacity(0.9) : .clear, radius: 6)
        .overlay(alignment: unit.side == .player ? .top : .bottom) {
            // A chevron pointing at the ready unit, outside the dot, on the
            // side the dot's own line sits on. Colour alone was not enough:
            // a fire unit's element accent and the gold ring are the same
            // family on a sunlit stage.
            if ready {
                Image(systemName: unit.side == .player ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(Theme.gold)
                    .shadow(color: .black.opacity(0.8), radius: 1.5)
                    .offset(y: unit.side == .player ? -3 : 3)
            }
        }
    }

    // MARK: - The player's team

    /// Five plates down the left edge: portrait, name, health as a bar *and*
    /// as a number, and the statuses on that unit.
    ///
    /// Before this the only per-unit health readout in the HUD was the acting
    /// unit's, so a five-unit team had four members whose health lived only in
    /// a world-space bar measured at 3.3pt tall and 1.21:1 against the floor.
    /// The enemy boss had a wide bar with exact figures; the player's own team
    /// had nothing. Every bar here is the same length whatever the unit's
    /// height or its distance from the camera, which the world bars can never
    /// be, so the team can actually be ranked by health.
    private func teamColumn(plate: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.playerTeam) { unit in
                teamPlate(unit, height: plate)
            }
        }
        .frame(width: 154, alignment: .leading)
        // A readout, never a control. A plate's filled background is
        // hit-testable whatever is drawn on it, and this column stands over
        // the back of the stage, which in a camera solved from above and
        // behind is exactly where the enemy line is: without this, a tap meant
        // for a target lands on the HUD and the turn does not happen.
        .allowsHitTesting(false)
    }

    /// How tall one team plate may be.
    ///
    /// Every other band of the HUD has a measured height and none of them can
    /// give: the top row is 54 (a 48pt gauge with 6 of padding over it), a boss
    /// bar is 26 and its gap 6, the command bar is 117 (a 38pt portrait and a
    /// 58pt skill readout inside 16 of padding on the left; a 36pt target strip
    /// over a 74pt skill row on the right), the four gaps between the bands are
    /// 6 apiece and the bottom padding is 8. What is left over is the column's.
    /// On a 16 Pro a boss fight leaves it 146 and the plates come out at 27; on
    /// a 13 mini it leaves 119 and they come out at their 23pt floor. They stop
    /// growing at 30 — past that they are only fatter, and the field behind
    /// them is worth more than the chrome.
    private func teamPlateHeight(hudHeight: CGFloat, boss: Bool) -> CGFloat {
        let count = CGFloat(max(1, model.playerTeam.count))
        let fixed: CGFloat = 54 + 24 + 117 + 8 + (boss ? 32 : 0)
        let budget = max(96, hudHeight - fixed)
        return min(30, max(23, (budget - (count - 1) * 2) / count))
    }

    private func teamPlate(_ unit: Combatant, height: CGFloat) -> some View {
        let acting = model.awaitingActor?.id == unit.id
        let aimed = model.selectedSkillSlot != nil && model.highlightedTarget == unit.id
        let alive = unit.isAlive
        let edge: Color = acting ? Theme.gold : (aimed ? Theme.info : Theme.stroke)
        // The portrait is the piece that gives when the column is squeezed:
        // the name and the health line beside it lay out at 21 points together
        // at `Theme.fontScale`, and shrinking those drops them below what the
        // phone resolves, which is what the density pass had to undo.
        let portrait = max(14, height - 6)
        let inset: CGFloat = height >= 26 ? 2 : 1
        return HStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(unit.element.color.opacity(0.25))
                if BundleImage.exists(unit.model.portraitName(awakened: unit.isAwakened)) {
                    // Framed before it is clipped, never after: an
                    // `.aspectRatio(.fill)` image reports the size it needs to
                    // cover the proposal, so the day a portrait ships that is
                    // not square it would carry its own clip shape out of this
                    // cell and draw over the plates above and below it. This is
                    // the rule `UnitCard` is built on.
                    BundleImage(name: unit.model.portraitName(awakened: unit.isAwakened))
                        .aspectRatio(contentMode: .fill)
                        .frame(width: portrait, height: portrait)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(alive ? unit.element.color : Theme.stroke, lineWidth: 1)
                if !alive {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.black.opacity(0.6))
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(Theme.danger)
                }
            }
            .frame(width: portrait, height: portrait)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(unit.name)
                        .font(Theme.body(10).weight(.bold))
                        .foregroundStyle(alive ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    statusPips(unit.statuses)
                }
                HStack(spacing: 3) {
                    StatBar(
                        value: unit.currentHealth,
                        maximum: unit.maxHealth,
                        tint: healthTint(unit.healthFraction),
                        height: 6
                    )
                    .frame(width: 68)
                    // The figure as well as the bar: a bar answers "how hurt",
                    // a number answers "can this unit survive the next hit",
                    // and only one of those is a decision.
                    Text("\(Int(unit.currentHealth.rounded()))")
                        .font(Theme.numeric(8))
                        .foregroundStyle(alive ? Theme.textSecondary : Theme.danger)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: 30, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, inset)
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(acting ? Theme.goldDeep.opacity(0.5) : Theme.plate.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(edge, lineWidth: acting ? 1.8 : 1)
        )
        .shadow(color: acting ? Theme.gold.opacity(0.5) : .black.opacity(0.45), radius: acting ? 6 : 3, y: 1)
        .opacity(alive ? 1 : 0.55)
        .animation(.easeOut(duration: 0.2), value: acting)
    }

    /// Statuses at team-plate size: the glyph on a coloured disc, three of
    /// them and a count. The named chips are for the actor plate and the boss
    /// bar, where there is room for words.
    private func statusPips(_ statuses: [ActiveStatus]) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(statuses.prefix(3).enumerated()), id: \.offset) { _, status in
                Image(systemName: status.kind.glyph)
                    .font(.system(size: 6.5, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 11, height: 11)
                    .background(
                        Circle().fill(status.kind.isBuff ? Color(hex: "#2E8FBF") : Color(hex: "#B8403A"))
                    )
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5))
            }
            if statuses.count > 3 {
                Text("+\(statuses.count - 3)")
                    .font(Theme.numeric(7))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - The combat feed

    /// What just happened, in words, on the right-hand side.
    ///
    /// The 3D damage numbers are drawn onto whatever floor they land on, and
    /// three of them from a three-hit skill overlap almost completely. These
    /// do not overlap, they name their victim, and they sit on their own dark
    /// plate, so the answer to "what just happened to whom" survives a bright
    /// stage and a ×3 fast-forward.
    private var combatFeed: some View {
        VStack(alignment: .trailing, spacing: 3) {
            ForEach(feed) { entry in
                HStack(spacing: 5) {
                    Image(systemName: entry.glyph)
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(entry.tint)
                        .frame(width: 11)
                    Text(entry.name)
                        .font(Theme.body(10.5).weight(.semibold))
                        .foregroundStyle(entry.isPlayer ? Theme.info : Theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(entry.value)
                        .font(Theme.numeric(11))
                        .foregroundStyle(entry.tint)
                        .lineLimit(1)
                }
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(Capsule().fill(Theme.plate.opacity(0.6)))
                .overlay(Capsule().strokeBorder(entry.tint.opacity(0.55), lineWidth: 1))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: 190, alignment: .trailing)
        .allowsHitTesting(false)
    }

    /// Every health and status figure on the field, folded into one Int, so a
    /// single `onChange` can drive the feed. Health is rounded to a whole
    /// point because that is the resolution the feed prints at.
    private var battlePulse: Int {
        var value = model.displayedCombatants.count &* 7919
        for unit in model.displayedCombatants {
            value = value &* 31 &+ Int(unit.currentHealth.rounded())
            for status in unit.statuses {
                value = value &* 31 &+ status.kind.hashValue
            }
        }
        return value
    }

    /// Diffs the model's displayed world against the last snapshot and turns
    /// the difference into feed lines. A unit seen for the first time — the
    /// opening of the battle, or a wave walking on — is recorded without
    /// emitting anything, or every fight would open with five phantom hits.
    private func ingestFeed() {
        var arrivals: [BattleFeedEntry] = []
        for unit in model.displayedCombatants {
            let previousHealth = lastHealth[unit.id]
            lastHealth[unit.id] = unit.currentHealth
            if let previousHealth {
                let delta = unit.currentHealth - previousHealth
                if delta <= -1 {
                    arrivals.append(BattleFeedEntry(
                        glyph: "burst.fill",
                        name: unit.name,
                        value: "-\(Int((-delta).rounded()))",
                        tint: Theme.danger,
                        isPlayer: unit.side == .player
                    ))
                } else if delta >= 1 {
                    arrivals.append(BattleFeedEntry(
                        glyph: "cross.case.fill",
                        name: unit.name,
                        value: "+\(Int(delta.rounded()))",
                        tint: Theme.success,
                        isPlayer: unit.side == .player
                    ))
                }
                if previousHealth > 0, unit.currentHealth <= 0 {
                    arrivals.append(BattleFeedEntry(
                        glyph: "xmark.seal.fill",
                        name: unit.name,
                        value: "DOWN",
                        tint: Theme.danger,
                        isPlayer: unit.side == .player
                    ))
                }
            }

            let now = Set(unit.statuses.map(\.kind))
            let before = lastStatuses[unit.id] ?? now
            lastStatuses[unit.id] = now
            for kind in now.subtracting(before).sorted(by: { $0.rawValue < $1.rawValue }) {
                arrivals.append(BattleFeedEntry(
                    glyph: kind.glyph,
                    name: unit.name,
                    value: kind.displayName,
                    tint: kind.isBuff ? Theme.info : Color(hex: "#E0803C"),
                    isPlayer: unit.side == .player
                ))
            }
        }
        guard !arrivals.isEmpty else { return }

        withAnimation(.easeOut(duration: 0.16)) {
            feed.append(contentsOf: arrivals)
            // Four lines is a three-hit skill plus its debuff. More than that
            // and the newest line is scrolling away before it has been read.
            if feed.count > 4 { feed.removeFirst(feed.count - 4) }
        }
        // The line lives as long as the turn it belongs to, so at ×3 it clears
        // before the next skill starts rather than piling up.
        let ids = Set(arrivals.map(\.id))
        let life = 2.4 / max(0.5, model.speed)
        DispatchQueue.main.asyncAfter(deadline: .now() + life) {
            withAnimation(.easeIn(duration: 0.2)) {
                feed.removeAll { ids.contains($0.id) }
            }
        }
    }

    // MARK: - Command bar

    /// The actor at the left, the skills at the right, nothing in between:
    /// the player line stands in the open middle of a landscape screen.
    ///
    /// The left plate is filled on an enemy turn too, by the unit named in the
    /// last turn header, so the corner keeps one meaning — "this is who is
    /// acting" — instead of appearing and vanishing with the player's turn.
    private var commandBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            if let actor = model.awaitingActor {
                actorPlate(actor, waiting: true)
            } else if let acting = playbackActor {
                actorPlate(acting, waiting: false)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                if let actor = model.awaitingActor {
                    if model.selectedSkillSlot != nil {
                        targetStrip(actor)
                    }
                    skillRow(actor)
                } else if model.isPlayingBack {
                    skipButton
                }
            }
        }
    }

    /// Who is acting while the turn plays back. `awaitingActor` is nil for
    /// every enemy turn and for every turn on auto, and the model does not
    /// publish the unit the engine is resolving — but it does write a turn
    /// header into the log, and the name in it is the answer.
    private var playbackActor: Combatant? {
        guard let line = model.log.last(where: { $0.hasPrefix("— Turn ") }),
              let separator = line.range(of: ": ") else { return nil }
        let name = String(line[separator.upperBound...])
        return model.displayedCombatants.first { $0.name == name && $0.isAlive }
            ?? model.displayedCombatants.first { $0.name == name }
    }

    private func skillRow(_ actor: Combatant) -> some View {
        HStack(spacing: 6) {
            ForEach(model.availableSkills) { option in
                SkillButton(
                    skill: option.skill,
                    cooldown: option.cooldown,
                    isSelected: model.selectedSkillSlot == option.slot,
                    forecast: forecast(option.skill, actor: actor),
                    onHold: { withAnimation { heldSkill = option.skill } },
                    onPreview: { pressed in
                        previewSlot = pressed ? option.slot : nil
                    }
                ) {
                    model.selectSkill(option.slot)
                }
            }
        }
        .padding(6)
        // 14 around the buttons' 8 plus 6 of padding: concentric corners.
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.plate.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
    }

    private var skipButton: some View {
        Button {
            model.skipAnimation()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "forward.fill")
                Text("Skip")
            }
            .font(Theme.body(12).weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 14)
            .frame(height: 30)
            .background(Capsule().fill(Theme.plate.opacity(0.6)))
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        }
    }

    /// The unit whose turn it is: portrait, health, what it is under, and
    /// what the skill in hand will do — all in the corner, where the genre
    /// keeps it, so the field stays clear.
    private func actorPlate(_ actor: Combatant, waiting: Bool) -> some View {
        // ONE ROW, 54 points, and see-through. The owner: "that HUD at the
        // bottom left is too big and covers too much. Maybe dont make it dark
        // like that." It stood 129 points tall — a third of the phone — as a
        // solid plate, with the skill's words stacked under the unit. The
        // words now sit BESIDE the unit, the two-line hint is gone, and the
        // plate is a half-strength scrim the stage shows through.
        let tint = waiting ? Theme.gold : actor.element.color
        return HStack(alignment: .center, spacing: 9) {
            ZStack {
                if BundleImage.exists(actor.model.portraitName(awakened: actor.isAwakened)) {
                    BundleImage(name: actor.model.portraitName(awakened: actor.isAwakened), renderedAt: 40)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(tint, lineWidth: 1.5)
                    .frame(width: 40, height: 40)
            }
            .shadow(color: tint.opacity(0.6), radius: 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(actor.name)
                        .font(Theme.body(12).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    ElementBadge(element: actor.element, compact: true)
                    // One word saying whose turn this is. On an enemy turn
                    // it is the only thing on screen that says the fight is
                    // not waiting for the player. It is tinted by side and
                    // not by state, because red is the colour this HUD uses
                    // for harm: a red badge over one of the player's own
                    // units reads as something happening TO it rather than
                    // as it taking its turn.
                    let ownTurn = waiting || actor.side == .player
                    Text(waiting ? "YOUR TURN" : (actor.side == .player ? "ACTING" : "ENEMY TURN"))
                        .font(Theme.body(8).weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(ownTurn ? Theme.ink : Theme.textPrimary)
                        .padding(.horizontal, 5)
                        .frame(height: 13)
                        .background(Capsule().fill(
                            waiting ? Theme.gold
                                : (actor.side == .player ? Theme.info.opacity(0.9) : Theme.danger.opacity(0.8))
                        ))
                        .fixedSize()
                }
                HStack(spacing: 5) {
                    StatBar(
                        value: actor.currentHealth,
                        maximum: actor.maxHealth,
                        tint: healthTint(actor.healthFraction),
                        height: 5
                    )
                    .frame(width: 66)
                    Text("\(Int(actor.currentHealth.rounded())) / \(Int(actor.maxHealth.rounded()))")
                        .font(Theme.numeric(9))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    if !actor.statuses.isEmpty {
                        statusChips(actor.statuses, compact: true)
                    }
                }
            }
            .frame(width: 148, alignment: .leading)
            .clipped()

            Rectangle()
                .fill(Theme.stroke.opacity(0.8))
                .frame(width: 1, height: 34)

            skillReadout(actor, waiting: waiting)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(Theme.plate.opacity(0.46))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .strokeBorder(waiting ? Theme.gold.opacity(0.5) : Theme.stroke.opacity(0.6), lineWidth: 1)
        )
    }

    /// What the skill in hand does, spelled out before it is committed: its
    /// name and the numbers on one line, its words on the two under them.
    ///
    /// The slot it describes is the one under the player's finger if there is
    /// one, and the aimed slot otherwise. That ordering is the whole point:
    /// a skill that picks its own targets used to fire on the tap, so waiting
    /// for `selectedSkillSlot` meant those skills were only ever described
    /// in the past tense, in the log. Once a skill is armed the gold tag at
    /// the end says how to commit, because an armed skill that aims itself
    /// gives the player nothing on the field to tap.
    private func skillReadout(_ actor: Combatant, waiting: Bool) -> some View {
        let slot = previewSlot ?? model.selectedSkillSlot
        let skill = slot.flatMap { actor.skill(at: $0) }
        let cooling = slot.flatMap { index -> Int? in
            actor.cooldowns.indices.contains(index) ? actor.cooldowns[index] : nil
        } ?? 0
        let armed = model.selectedSkillSlot != nil && previewSlot == nil
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Text(skill?.name ?? (waiting ? "Choose a skill" : "Resolving…"))
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(skill == nil ? Theme.textSecondary : Theme.gold)
                    .lineLimit(1)
                if let skill {
                    if let damage = skill.damage {
                        let hits = damage.hits > 1 ? " ×\(damage.hits)" : ""
                        Chip(
                            text: "≈\(Int(estimatedDamage(skill, actor: actor)))\(hits)",
                            systemImage: "bolt.fill",
                            tint: Theme.gold,
                            filled: true
                        )
                    }
                    if cooling > 0 {
                        Chip(text: "COOLING \(cooling)", systemImage: "clock.fill", tint: Theme.textSecondary)
                    } else if skill.cooldown > 0 {
                        Chip(text: "CD \(skill.cooldown)", systemImage: "clock.fill", tint: Theme.textSecondary)
                    }
                    if let status = skill.statuses.first {
                        Chip(
                            text: "\(status.kind.displayName) \(Int(status.chance * 100))%",
                            systemImage: status.kind.glyph,
                            tint: status.kind.isBuff ? Theme.info : Theme.danger
                        )
                    }
                    if let aim = aimedTarget, skill.target.hitsEnemies {
                        matchupChip(attacker: actor, defender: aim)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: 6) {
                Text(skill?.description ?? (waiting
                    ? "Tap a skill to read it; hold it for the full card."
                    : (model.log.last ?? "")))
                    .font(Theme.body(9))
                    .foregroundStyle(skill == nil ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if armed, waiting, let skill {
                    Text(BattleViewModel.needsTarget(skill) ? "TAP A TARGET" : "TAP AGAIN")
                        .font(Theme.body(8).weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 6)
                        .frame(height: 14)
                        .background(Capsule().fill(Theme.gold))
                        .fixedSize()
                }
            }
        }
        .frame(width: 214, height: 40, alignment: .topLeading)
        .clipped()
    }

    /// The target the next tap would hit, if one is aimed.
    private var aimedTarget: Combatant? {
        model.displayedCombatants.first { $0.id == model.highlightedTarget }
    }

    /// Aiming lives beside the skills, not across the screen from them.
    ///
    /// It used to be a line under the top bar with Confirm in it: the button
    /// that finishes the action was in the opposite corner from the buttons
    /// that started it, which is a whole diagonal of thumb travel per turn.
    private func targetStrip(_ actor: Combatant) -> some View {
        let aim = aimedTarget
        return HStack(spacing: 8) {
            Image(systemName: "scope")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.gold)
            if let aim {
                if BundleImage.exists(aim.model.portraitName(awakened: aim.isAwakened)) {
                    BundleImage(name: aim.model.portraitName(awakened: aim.isAwakened))
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(aim.element.color, lineWidth: 1)
                        )
                }
                // Capped and truncating, because it is the one piece of this
                // strip that has no natural width: "the Unwrapped King" is
                // 45 points wider than "Anubis", and the strip has to stand
                // beside a 307pt actor plate inside a landscape frame that is
                // 722 points wide once the safe area is off it.
                Text(aim.name)
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 72, alignment: .leading)
                StatBar(
                    value: aim.currentHealth,
                    maximum: aim.maxHealth,
                    tint: healthTint(aim.healthFraction),
                    height: 5
                )
                .frame(width: 48)
                matchupChip(attacker: actor, defender: aim)
            } else {
                Text("Tap a target on the field")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            if aim != nil {
                Button {
                    model.confirmTarget()
                } label: {
                    Text("Confirm")
                        .font(Theme.body(11).weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Capsule().fill(Theme.gold))
                }
            }
            Button {
                model.cancelTargeting()
            } label: {
                Text("Cancel")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(Theme.surface))
                    .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.plate.opacity(0.6)))
        .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
    }

    // MARK: - Shared readouts

    /// One health colour ramp for the whole HUD. Green until 60%, amber to
    /// 30%, red under it — the old single break at 30% meant a unit on 35%
    /// looked exactly like one on 100%, which is the difference between
    /// healing it this turn and losing it next turn.
    private func healthTint(_ fraction: Double) -> Color {
        if fraction < 0.3 { return Theme.danger }
        if fraction < 0.6 { return Color(hex: "#F2A03C") }
        return Theme.success
    }

    /// How the element wheel reads for this particular attack, as a chip, so
    /// "will this hurt" is answered before the skill is spent rather than by
    /// the size of the number afterwards.
    private func matchupChip(attacker: Combatant, defender: Combatant) -> some View {
        let matchup = attacker.element.matchup(against: defender.element)
        let text: String
        let tint: Color
        let glyph: String
        switch matchup {
        case .advantage:
            text = "STRONG ×1.5"
            tint = Theme.success
            glyph = "arrow.up.right.circle.fill"
        case .neutral:
            text = "NEUTRAL"
            tint = Theme.textSecondary
            glyph = "equal.circle.fill"
        case .disadvantage:
            text = "WEAK ×0.7"
            tint = Theme.danger
            glyph = "arrow.down.right.circle.fill"
        }
        return Chip(text: text, systemImage: glyph, tint: tint, filled: matchup != .neutral)
    }

    /// What a skill will do, in one short string, for the face of its tile.
    private func forecast(_ skill: Skill, actor: Combatant) -> String? {
        if let damage = skill.damage {
            let value = Int(estimatedDamage(skill, actor: actor))
            return damage.hits > 1 ? "≈\(value) ×\(damage.hits)" : "≈\(value)"
        }
        if skill.utilities.contains(where: {
            if case .healTargetMaxHealth = $0 { return true }
            if case .healFromAttack = $0 { return true }
            return false
        }) { return "HEAL" }
        if skill.utilities.contains(where: {
            if case .revive = $0 { return true }
            return false
        }) { return "REVIVE" }
        if skill.utilities.contains(where: {
            if case .cleanse = $0 { return true }
            return false
        }) { return "CLEANSE" }
        if skill.utilities.contains(where: {
            if case .strip = $0 { return true }
            return false
        }) { return "STRIP" }
        if let status = skill.statuses.first {
            return status.kind.isBuff ? "BUFF" : "DEBUFF"
        }
        return nil
    }

    /// The damage the skill would do to the unit currently aimed at — its real
    /// defence and the real element matchup, not the collection screen's
    /// standing dummy. It is an estimate and it is labelled with a ≈: the crit
    /// roll and the damage variance are still ahead of it.
    private func estimatedDamage(_ skill: Skill, actor: Combatant) -> Double {
        guard let damage = skill.damage else { return 0 }
        let target = aimedTarget
            ?? model.displayedCombatants.first { $0.side == actor.side.opposing && $0.isAlive }
        var value = DamageCalculator.previewDamage(
            attackStat: actor.scalingValue(for: damage.scaling),
            spec: damage,
            againstDefense: target?.currentStats.def ?? 800
        )
        if let target, target.side != actor.side {
            value *= actor.element.matchup(against: target.element).damageMultiplier
        }
        return value.rounded()
    }

    /// Who a skill lands on, in one or two words.
    private func scopeWord(_ target: TargetSelector) -> String {
        switch target {
        case .singleEnemy: return "1 enemy"
        case .allEnemies: return "All enemies"
        case .randomEnemies(let count): return "\(count) random"
        case .lowestHealthEnemy: return "Weakest"
        case .caster: return "Self"
        case .singleAlly: return "1 ally"
        case .allAllies: return "All allies"
        case .lowestHealthAlly: return "Hurt ally"
        case .deadAlly: return "Fallen ally"
        case .otherAllies: return "Other allies"
        }
    }

    /// Buffs and debuffs as chips: blue for a buff, red for a debuff, the
    /// turns left last. `compact` drops the name and keeps the glyph, and it
    /// stops at four rather than six: compact or not, four chips are 105
    /// points, and these now share the actor plate's health line rather than
    /// having a line of their own. The rest are counted in a `+n`.
    private func statusChips(_ statuses: [ActiveStatus], compact: Bool = false) -> some View {
        let limit = 4
        return HStack(spacing: 3) {
            ForEach(Array(statuses.prefix(limit).enumerated()), id: \.offset) { _, status in
                HStack(spacing: 2) {
                    Image(systemName: status.kind.glyph)
                        .font(.system(size: 9, weight: .bold))
                    if !compact {
                        Text(status.kind.displayName)
                            .font(Theme.body(9).weight(.semibold))
                            .lineLimit(1)
                    }
                    Text("\(status.turnsRemaining)")
                        .font(Theme.numeric(9))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Capsule().fill(status.kind.isBuff ? Color(hex: "#2E8FBF") : Color(hex: "#B8403A")))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
            }
            if statuses.count > limit {
                Text("+\(statuses.count - limit)")
                    .font(Theme.numeric(9))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    /// The boss's bar across the top: the fight that matters, on one line.
    private func bossBar(_ boss: Combatant) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.danger)
            Text(boss.name.uppercased())
                .font(Theme.body(10).weight(.black))
                .tracking(1.2)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            // maxWidth, not width: with four named chips beside it the row
            // would otherwise be wider than the screen.
            VStack(alignment: .leading, spacing: 2) {
                // A raid boss's barrier sits ON the health bar, because it is
                // the bar the player is actually hitting: damage goes into it
                // first, and the health underneath does not move until it
                // breaks. Drawn in the boss's current weakness colour so the
                // two pieces of information a raid turn needs — what is
                // soaking the damage, and what it is soft to — are one glance.
                if let barrier = model.raidBarrierFraction(boss.id) {
                    let tint = model.raidWeakness(boss.id)?.color ?? Theme.gold
                    StatBar(value: barrier, maximum: 1, tint: tint, height: 4)
                        .frame(maxWidth: 260)
                }
                StatBar(value: boss.currentHealth, maximum: boss.maxHealth, tint: Theme.danger, height: 6)
                    .frame(maxWidth: 260)
            }
            Text("\(Int(boss.currentHealth.rounded())) / \(Int(boss.maxHealth.rounded()))")
                .font(Theme.numeric(9))
                .foregroundStyle(Theme.textSecondary)
            if let weakness = model.raidWeakness(boss.id) {
                Chip(text: "Open to \(weakness.displayName)", systemImage: weakness.glyph, tint: weakness.color)
            }
            // Only above 1: an enrage that has not started yet is not news.
            if model.raidEnrage(boss.id) > 1.001 {
                Chip(
                    text: String(format: "Enraged ×%.1f", model.raidEnrage(boss.id)),
                    systemImage: "flame.fill",
                    tint: Theme.danger,
                    filled: true
                )
            }
            if !boss.statuses.isEmpty {
                statusChips(boss.statuses)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(Theme.plate.opacity(0.6)))
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
        // The one thing a player taps a boss for is to aim at it, and a boss
        // is by definition the tallest thing on the stage — its head reaches
        // the band this bar lies across. A filled capsule takes the tap.
        .allowsHitTesting(false)
    }

    /// An ultimate's announcement: a dark band across the field, the
    /// caster's card sliding in from the left and the skill's name from the
    /// right, gone in a second.
    private func cutInBanner(_ cutIn: BattleViewModel.CutIn) -> some View {
        let accent = Color(hex: cutIn.accentHex)
        // Annotated rather than inferred inside the modifier: nil is the
        // "leave it alone" value for both, and a bare ternary against nil is
        // the sort of thing that needs a compiler to settle.
        let speechLines: Int? = cutIn.isSpeech ? 3 : nil
        let speechWidth: CGFloat? = cutIn.isSpeech ? 420 : nil
        return VStack {
            Spacer().frame(height: 90)
            ZStack {
                LinearGradient(
                    colors: [.clear, Theme.ink.opacity(0.92), Theme.ink.opacity(0.92), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                Rectangle().fill(accent.opacity(0.9)).frame(height: 2).frame(maxHeight: .infinity, alignment: .top)
                Rectangle().fill(accent.opacity(0.9)).frame(height: 2).frame(maxHeight: .infinity, alignment: .bottom)
                HStack(spacing: 16) {
                    if BundleImage.exists(cutIn.portrait) {
                        BundleImage(name: cutIn.portrait)
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(accent, lineWidth: 2))
                            .shadow(color: accent.opacity(0.8), radius: 12)
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cutIn.unitName.uppercased())
                            .font(Theme.body(11).weight(.bold))
                            .tracking(1.6)
                            .foregroundStyle(accent)
                        // A skill's name is two or three words and wears the
                        // display face; a boss's line is a sentence, and at 26pt
                        // an eighty-character one runs straight out of the 84pt
                        // band. It is set smaller, allowed three lines and given
                        // a width to wrap inside.
                        Text(cutIn.skillName)
                            .font(cutIn.isSpeech ? Theme.title(15) : Theme.display(26))
                            .foregroundStyle(Theme.textPrimary)
                            // Every one of these is written so that it is the
                            // no-op it used to be when this is not speech: the
                            // ultimate's announcement must look exactly as it did.
                            .lineLimit(speechLines)
                            .minimumScaleFactor(cutIn.isSpeech ? 0.8 : 1)
                            .fixedSize(horizontal: false, vertical: cutIn.isSpeech)
                            .frame(maxWidth: speechWidth, alignment: .leading)
                            .shadow(color: accent.opacity(0.9), radius: 10)
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(height: 84)
            Spacer()
        }
    }

    /// The card a held skill shows: name, cooldown, what it does.
    private func skillCard(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(skill.name)
                    .font(Theme.title(15))
                    .foregroundStyle(Theme.gold)
                Spacer()
                Text(skill.cooldown > 0 ? "Cooldown \(skill.cooldown) turns" : "No cooldown")
                    .font(Theme.numeric(10))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(skill.description)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tap to close")
                .font(Theme.body(9))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: 360)
        .background(Theme.panel(Theme.tightCorner))
    }

    // MARK: - Log

    private var logOverlay: some View {
        VStack {
            Spacer()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(model.log.indices, id: \.self) { index in
                            let line = model.log[index]
                            Text(line)
                                .font(Theme.body(11))
                                .foregroundStyle(
                                    line.hasPrefix("—") ? Theme.gold : Theme.textSecondary
                                )
                                .id(index)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 150)
                .background(Theme.panel())
                .onChange(of: model.log.count) { _, count in
                    withAnimation { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 96)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// One skill in the command bar.
struct SkillButton: View {
    let skill: Skill
    let cooldown: Int
    let isSelected: Bool
    /// One line under the name saying what the skill will do — "≈1240 ×3",
    /// "HEAL", "DEBUFF". Worked out by the view that knows the caster's stats
    /// and what is aimed at, because the tile does not.
    var forecast: String? = nil
    /// Held down: show what the skill does.
    var onHold: (() -> Void)? = nil
    /// True the moment a finger lands on the tile, false when it lifts, so the
    /// actor plate can describe a skill that has not been cast yet.
    var onPreview: ((Bool) -> Void)? = nil
    let action: () -> Void

    /// Set by a hold so the release that follows it is not read as a tap:
    /// reading a skill must never cast it.
    @State private var wasHeld = false

    private var isReady: Bool { cooldown <= 0 }

    var body: some View {
        Button {
            if wasHeld { wasHeld = false; return }
            if isReady { action() }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(isReady ? Theme.surfaceRaised : Theme.surface)

                VStack(spacing: 1) {
                    Image(systemName: glyph)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isReady ? Theme.gold : Theme.textSecondary)
                    Text(skill.name)
                        .font(Theme.body(9).weight(.semibold))
                        .foregroundStyle(isReady ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.8)
                    if let forecast {
                        // The forecast is the answer to "what will this button
                        // do" without spending a turn to find out. It sits on
                        // its own dark strip so it reads at the same contrast
                        // whether the tile is lit or dimmed by a cooldown.
                        Text(forecast)
                            .font(Theme.numeric(8))
                            .foregroundStyle(isReady ? Theme.gold : Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.horizontal, 3)
                            .frame(height: 12)
                            .background(Capsule().fill(Theme.ink.opacity(0.75)))
                    }
                }
                .padding(3)

                if !isReady {
                    RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                        .fill(Color.black.opacity(0.62))
                    Text("\(cooldown)")
                        .font(Theme.display(24))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .frame(width: 60, height: 62)
            .overlay(alignment: .topTrailing) {
                // Who it lands on, as a glyph in the corner: one figure, three
                // figures, a heart. Reading the shape of a skill should not
                // need the description panel.
                Image(systemName: Self.targetGlyph(for: skill))
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(2)
                    .background(Circle().fill(Theme.ink.opacity(0.85)))
                    .offset(x: 2, y: -2)
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .strokeBorder(isSelected ? Theme.gold : Theme.stroke, lineWidth: isSelected ? 2 : 1)
            )
        }
        // A ButtonStyle rather than a gesture: `isPressed` is the one way to
        // watch a finger land that cannot swallow the tap it is watching, and
        // the scale it drives is most of what makes the bar feel alive.
        .buttonStyle(PressStyle(onPress: { pressed in onPreview?(pressed) }))
        // A hold shows the card even on a skill that is cooling down.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                wasHeld = true
                onHold?()
                // The button may or may not fire on the release after a hold
                // (it varies by iOS); either way the flag is spent shortly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { wasHeld = false }
            }
        )
        .disabled(!isReady && onHold == nil)
    }

    /// Reports the press to the caller and shrinks the tile while it is held.
    struct PressStyle: ButtonStyle {
        var onPress: (Bool) -> Void

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.93 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .onChange(of: configuration.isPressed) { _, pressed in onPress(pressed) }
        }
    }

    private var glyph: String { Self.glyph(for: skill) }

    /// A glyph per skill shape, so the bar is readable without art. The
    /// unit sheet's skill tiles use the same one.
    static func glyph(for skill: Skill) -> String {
        if skill.utilities.contains(where: {
            if case .healTargetMaxHealth = $0 { return true }
            if case .healFromAttack = $0 { return true }
            return false
        }) { return "cross.case.fill" }
        if skill.cooldown >= 4 { return "burst.fill" }
        if skill.statuses.contains(where: { $0.kind.isHardCC }) { return "bolt.slash.fill" }
        if (skill.damage?.hits ?? 1) > 1 { return "square.stack.3d.down.right.fill" }
        return skill.cooldown > 0 ? "flame.fill" : "figure.fencing"
    }

    /// A glyph per target shape: how many, and which side.
    static func targetGlyph(for skill: Skill) -> String {
        switch skill.target {
        case .allEnemies: return "person.3.fill"
        case .randomEnemies: return "die.face.5.fill"
        case .allAllies, .otherAllies: return "heart.circle.fill"
        case .singleAlly, .lowestHealthAlly: return "heart.fill"
        case .deadAlly: return "arrow.uturn.up.circle.fill"
        case .caster: return "person.crop.circle.fill"
        default: return "person.fill"
        }
    }
}

/// The end of a battle, in two acts.
///
/// The owner: "when we win a battle, it should first show the stats of the
/// battle, then you tap to show a chest that opens or like a greek chest, as
/// it opens it shows your prize. Again, I want this to feel PREMIUM."
///
/// ACT ONE, THE RECKONING. The word, the stars ticking in one at a time, the
/// three numbers of the fight, and a row per unit saying what each one did —
/// damage dealt as a bar against the best, damage taken, healing, kills — with
/// a laurel on the one that did the most. A defeat gets the same reckoning in
/// wine instead of gold, and a Continue button, because there is no chest to
/// open after losing.
///
/// ACT TWO, THE CHEST. One tap and the reckoning gives way to a marble
/// strongbox bound in bronze, shut, waiting. A second tap lifts the lid: a
/// flash, rays, the inside lit gold, and the spoils rise out of it one by one
/// onto a shelf above, each with a tick and a pulse in the hand. Only then does
/// Continue appear. Every timed step checks it still belongs to the current
/// sequence, so a tap that skips ahead cannot be followed by a stale step.
///
/// Nothing here is a flat fill. The chest is stone plate and bronze plate over
/// a bevel; the tiles are panels; the light is additive over the scrim. That
/// is the whole difference between a receipt and a reward.
struct BattleResultView: View {
    let summary: BattleSummary
    let onDismiss: () -> Void
    /// The CI tour sets this so a five-second photograph catches the chest
    /// open with the spoils out, rather than the reckoning waiting for a tap.
    var autoplay: Bool = false

    private enum Phase { case reckoning, chest, opened }

    @State private var phase: Phase = .reckoning
    @State private var shownStars = 0
    @State private var rowsShown = 0
    @State private var lidOpen = false
    /// The chest has lifted and faded under the flash; the spoils remain.
    @State private var chestGone = false
    @State private var flash: Double = 0
    @State private var raysShown = false
    @State private var rays: Double = 0
    @State private var lootShown = 0
    @State private var continueShown = false
    @State private var pulse = false
    @State private var sequence = 0

    private var won: Bool { summary.outcome == .victory }
    private var hasSpoils: Bool { won && !summary.loot.isEmpty }

    var body: some View {
        ZStack {
            // The scrim. Darker than the old 0.78 because the stage under it is
            // sunlit now, and the two acts are read against it.
            Color.black.opacity(0.84).ignoresSafeArea()

            switch phase {
            case .reckoning:
                reckoning
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            case .chest, .opened:
                chestAct
                    .transition(.opacity)
            }
        }
        .onAppear { beginReckoning() }
    }

    // MARK: - Act one

    private var reckoning: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                verdict
                    .frame(width: 292)
                unitRows
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 26)
            .padding(.top, 12)

            Spacer(minLength: 6)

            if hasSpoils {
                Text("TAP TO CLAIM YOUR SPOILS")
                    .font(Theme.body(11).weight(.black))
                    .tracking(2.2)
                    .foregroundStyle(Theme.gold)
                    .opacity(pulse ? 1 : 0.45)
                    .padding(.bottom, 14)
            } else {
                PrimaryButton(title: "Continue", action: onDismiss)
                    .frame(width: 220)
                    .padding(.bottom, 12)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard hasSpoils else { return }
            advanceToChest()
        }
    }

    /// The word, the stars and the three numbers.
    private var verdict: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headline)
                .font(Theme.display(46))
                .foregroundStyle(won ? Theme.gold : (summary.outcome == .draw ? Theme.marble : Theme.wine))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .shadow(color: (won ? Theme.gold : Theme.wine).opacity(0.45), radius: 18)
            if !summary.title.isEmpty {
                Text(summary.title)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            if won, summary.stars > 0 {
                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { index in
                        Image(systemName: "star.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(index <= shownStars ? Theme.gold : Theme.stroke)
                            .scaleEffect(index <= shownStars ? 1 : 0.7)
                            .shadow(color: Theme.gold.opacity(index <= shownStars ? 0.7 : 0), radius: 8)
                            .animation(.spring(response: 0.32, dampingFraction: 0.55), value: shownStars)
                    }
                    if summary.isFirstClear {
                        Chip(text: "First clear", systemImage: "seal.fill", tint: Theme.verdigris, filled: true)
                            .padding(.leading, 6)
                    }
                }
                .padding(.top, 2)
            }
            HStack(spacing: 8) {
                statTile("TURNS", value: "\(summary.turns)")
                statTile("DEALT", value: Int(summary.damageDealt).formatted())
                statTile("TAKEN", value: Int(summary.damageTaken).formatted())
            }
            .padding(.top, 8)
        }
    }

    private func statTile(_ label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(Theme.body(8).weight(.black))
                .tracking(1.4)
                .foregroundStyle(Theme.goldDim)
            Text(value)
                .font(Theme.numeric(15))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Theme.panel(Theme.tightCorner))
    }

    /// One row per unit, damage as a bar against the best in the team, and the
    /// laurel on whoever earned it.
    private var unitRows: some View {
        let best = max(1, summary.unitStats.map { $0.dealt + $0.healed }.max() ?? 1)
        return VStack(spacing: 6) {
            ForEach(Array(summary.unitStats.enumerated()), id: \.element.id) { index, unit in
                unitRow(unit, share: (unit.dealt + unit.healed) / best)
                    .opacity(index < rowsShown ? 1 : 0)
                    .offset(x: index < rowsShown ? 0 : 28)
                    .animation(.spring(response: 0.42, dampingFraction: 0.8), value: rowsShown)
            }
            if summary.unitStats.isEmpty {
                Text("No reckoning for this one.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func unitRow(_ unit: BattleSummary.UnitStat, share: Double) -> some View {
        let isMVP = unit.id == summary.mvpID
        return HStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if BundleImage.exists(unit.portraitName) {
                        BundleImage(name: unit.portraitName, renderedAt: 44)
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle().fill(unit.element.color.opacity(0.5))
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .rarityFrame(Rarity(stars: unit.stars), radius: 6)
                .saturation(unit.survived ? 1 : 0.15)
                .opacity(unit.survived ? 1 : 0.6)
                if isMVP {
                    Image(systemName: "laurel.leading")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(Theme.ink)
                        .padding(3)
                        .background(Circle().fill(Theme.gold))
                        .offset(x: 6, y: -6)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(unit.name)
                        .font(Theme.title(12))
                        .foregroundStyle(isMVP ? Theme.gold : Theme.textPrimary)
                        .lineLimit(1)
                    if isMVP {
                        Text("MVP")
                            .font(Theme.body(8).weight(.black))
                            .tracking(1)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.gold))
                    }
                    if !unit.survived {
                        Chip(text: "Fallen", systemImage: "xmark", tint: Theme.wine)
                    }
                    Spacer(minLength: 0)
                    if unit.kills > 0 {
                        Chip(text: "\(unit.kills) \(unit.kills == 1 ? "kill" : "kills")", systemImage: "bolt.fill", tint: Theme.gold)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.plate.opacity(0.6))
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.goldDim, Theme.gold], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * share))
                    }
                }
                .frame(height: 5)
                HStack(spacing: 10) {
                    Text("Dealt \(Int(unit.dealt).formatted())")
                    if unit.healed > 0 { Text("Healed \(Int(unit.healed).formatted())") }
                    Text("Taken \(Int(unit.taken).formatted())")
                }
                .font(Theme.numeric(9))
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.panel(Theme.tightCorner))
    }

    // MARK: - Act two

    private var chestAct: some View {
        ZStack {
            // Rays behind the chest, additive, only once it is open. Half
            // the reveal's strength: there is a shelf of tiles to read here.
            AngularGradient(
                colors: [Theme.gold.opacity(0), Theme.gold.opacity(0.16), Theme.gold.opacity(0),
                         Theme.gold.opacity(0.16), Theme.gold.opacity(0), Theme.gold.opacity(0.16),
                         Theme.gold.opacity(0), Theme.gold.opacity(0.16), Theme.gold.opacity(0)],
                center: .center
            )
            .scaleEffect(2.2)
            .opacity(raysShown ? 1 : 0)
            .animation(.easeOut(duration: 0.8), value: raysShown)
            .rotationEffect(.degrees(rays))
            .blendMode(.plusLighter)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            RadialGradient(
                colors: [Theme.gold.opacity(lidOpen ? 0.34 : 0.08), Theme.gold.opacity(lidOpen ? 0.12 : 0.03), .clear],
                center: .init(x: 0.5, y: 0.62),
                startRadius: 0,
                endRadius: lidOpen ? 330 : 160
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.6), value: lidOpen)

            // One centred stack: the shelf the spoils rise onto, the chest,
            // the line under it. The first cut pinned the shelf to the top
            // and the chest to the bottom with a spacer between, and the
            // tour photographed the Continue button sitting on the chest.
            VStack(spacing: 14) {
                Spacer(minLength: 0)

                lootShelf
                    .frame(height: 122)

                RewardChestView(open: lidOpen, gone: chestGone)
                    .frame(width: 300, height: 170)
                    .contentShape(Rectangle())
                    .onTapGesture { openChest() }

                Group {
                    if phase == .chest {
                        Text("TAP TO OPEN")
                            .font(Theme.body(11).weight(.black))
                            .tracking(2.2)
                            .foregroundStyle(Theme.gold)
                            .opacity(pulse ? 1 : 0.45)
                    } else if continueShown {
                        PrimaryButton(title: "Continue", action: onDismiss)
                            .frame(width: 220)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else {
                        Color.clear.frame(height: 1)
                    }
                }
                .frame(height: 44)

                Spacer(minLength: 0)
            }

            // The flash on the lid coming up. White over gold, gone in under
            // half a second.
            Color(hex: "#FFF3D0")
                .opacity(flash * 0.85)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .blendMode(.plusLighter)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if phase == .chest { openChest() } else if phase == .opened, !continueShown { finishOpeningNow() }
        }
    }

    private var lootShelf: some View {
        HStack(spacing: 10) {
            ForEach(Array(summary.loot.prefix(7).enumerated()), id: \.element.id) { index, item in
                LootTile(item: item)
                    .opacity(index < lootShown ? 1 : 0)
                    .scaleEffect(index < lootShown ? 1 : 0.5)
                    .offset(y: index < lootShown ? 0 : 90)
                    .animation(.spring(response: 0.45, dampingFraction: 0.66), value: lootShown)
            }
            if summary.loot.count > 7 {
                Text("+\(summary.loot.count - 7) more")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .opacity(lootShown >= 7 ? 1 : 0)
            }
        }
    }

    // MARK: - Sequencing

    private func after(_ seconds: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    private func beginReckoning() {
        sequence += 1
        let mine = sequence
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        AudioLibrary.shared.play(won ? .victory : .defeat, volume: 0.9)
        Juice.haptic(won ? .heavy : .medium)

        let stars = won ? summary.stars : 0
        for i in 0..<stars {
            after(0.45 + Double(i) * 0.18) {
                guard mine == sequence else { return }
                shownStars = i + 1
                AudioLibrary.shared.play(.starTick, volume: 0.8)
                Juice.haptic(i == stars - 1 ? .medium : .light)
            }
        }
        let rowStart = 0.45 + Double(stars) * 0.18 + 0.1
        for i in 0..<summary.unitStats.count {
            after(rowStart + Double(i) * 0.09) {
                guard mine == sequence else { return }
                rowsShown = i + 1
            }
        }
        if autoplay, hasSpoils {
            after(rowStart + Double(summary.unitStats.count) * 0.09 + 3.2) {
                guard mine == sequence else { return }
                advanceToChest()
                // `advanceToChest()` has just bumped the sequence, so the
                // second step must guard on the NEW number: guarding on
                // `mine` here is what left the tour's chest shut.
                // Two seconds closed, so the tour photographs the chest
                // on its beat before the lid goes.
                let chestSequence = sequence
                after(2.2) {
                    guard chestSequence == sequence else { return }
                    openChest()
                }
            }
        }
    }

    private func advanceToChest() {
        guard phase == .reckoning else { return }
        sequence += 1
        AudioLibrary.shared.play(.uiConfirm, volume: 0.6)
        Juice.haptic(.light)
        withAnimation(.easeInOut(duration: 0.4)) { phase = .chest }
        withAnimation(.linear(duration: 22).repeatForever(autoreverses: false)) { rays = 360 }
    }

    private func openChest() {
        guard phase == .chest else { return }
        sequence += 1
        let mine = sequence
        phase = .opened
        Juice.haptic(.medium)
        // The chest shakes, the lid swings back and the light stands up out
        // of it (`RewardChestView`, about a second); then the flash, under
        // which the chest lifts away, and the spoils rise onto the shelf.
        lidOpen = true
        after(0.3) {
            guard mine == sequence else { return }
            AudioLibrary.shared.play(.summonBurst, volume: 0.9)
        }
        after(1.4) {
            guard mine == sequence else { return }
            Juice.haptic(.heavy)
            flash = 1
            withAnimation(.easeOut(duration: 0.5)) { flash = 0 }
            raysShown = true
            chestGone = true
        }

        let count = min(7, summary.loot.count)
        for i in 0..<count {
            after(1.6 + Double(i) * 0.14) {
                guard mine == sequence else { return }
                lootShown = i + 1
                AudioLibrary.shared.play(.starTick, volume: 0.7)
                Juice.haptic(.light)
            }
        }
        after(1.6 + Double(count) * 0.14 + 0.35) {
            guard mine == sequence else { return }
            withAnimation(.easeOut(duration: 0.3)) { continueShown = true }
        }
    }

    /// A tap during the opening lands everything at once.
    private func finishOpeningNow() {
        sequence += 1
        lidOpen = true
        chestGone = true
        raysShown = true
        flash = 0
        lootShown = min(7, summary.loot.count)
        withAnimation(.easeOut(duration: 0.2)) { continueShown = true }
    }

    private var headline: String {
        switch summary.outcome {
        case .victory: return "VICTORY"
        case .defeat: return "DEFEAT"
        case .draw: return "DRAW"
        }
    }
}

/// One spoil on the shelf. A relic wears its rarity frame; everything else
/// is its glyph on a bronze-rimmed plate.
struct LootTile: View {
    let item: BattleSummary.Loot

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                if let stars = item.stars {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.stonePlate)
                        .frame(width: 42, height: 42)
                        .rarityFrame(Rarity(stars: stars), radius: 7)
                } else {
                    Circle()
                        .fill(Theme.stonePlate)
                        .frame(width: 42, height: 42)
                        .overlay(Circle().strokeBorder(Theme.bronzeFrame, lineWidth: 1.5))
                }
                Image(systemName: item.glyph)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(paint)
                    .shadow(color: paint.opacity(0.6), radius: 6)
            }
            if let stars = item.stars {
                StarRow(stars: stars, size: 7)
            }
            Text(item.title)
                .font(Theme.body(9).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 24)
            Text(item.amount)
                .font(Theme.numeric(12))
                .foregroundStyle(Theme.gold)
                .lineLimit(1)
        }
        .frame(width: 92)
        .padding(.vertical, 8)
        .background(Theme.panel(Theme.tightCorner))
    }

    private var paint: Color {
        switch item.tint {
        case .gold: return Theme.gold
        case .verdigris: return Theme.verdigris
        case .laurel: return Theme.laurel
        case .wine: return Theme.wine
        case .marble: return Theme.marble
        case .element(let element): return element.color
        case .scroll(let scroll): return scroll.tint
        }
    }
}

/// The reward chest: the Meshy-made box and lid — `prop_reward_chest` and
/// `prop_reward_chest_lid`, one 30-credit image-to-3D mesh from a Gemini
/// concept, cut in two by `tools/prop.py --split-lid` — on a small stage of
/// its own, transparent over the act's rays and glow.
///
/// Closed, it sits on its shadow, turns a few degrees either way so the gold
/// catches the light, and gives a hop every second or so: the tap prompt's
/// beat. Opened, it shakes, the lid swings back past open and settles on the
/// hinge the split left at its back edge, a pillar of gold light stands up
/// out of the box with sparks rising in it, and at the flash the chest lifts
/// and fades and the spoils are what is left. The owner, with the drawn
/// marble strongbox on his phone: "That chest SUCKS. Maybe get a 3D model?
/// Where it opens and then flashes and goes away and shows the reward (like
/// summoners war)."
struct RewardChestView: UIViewRepresentable {
    var open: Bool
    var gone: Bool

    /// Where the split put the lid's origin: the middle of its back-bottom
    /// edge, in metres of a 1 m chest. `prop.py` prints it as it ships; a
    /// lid hinged anywhere else swings through the box or floats.
    private static let hinge = SCNVector3(0, 0.617, -0.433)

    final class Coordinator {
        var scene: SCNScene?
        let chest = SCNNode()
        var lid: SCNNode?
        var opened = false
        var vanished = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        view.scene = scene
        // Transparent, like the reveal's stage: the rays and the gold glow
        // behind this view are the light the chest sits in. The beam and the
        // sparks it spawns are the reveal's own and write no alpha.
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = false
        view.rendersContinuously = true
        // The tap belongs to SwiftUI.
        view.isUserInteractionEnabled = false

        let coordinator = context.coordinator
        coordinator.scene = scene
        let chest = coordinator.chest
        chest.addChildNode(StageBuilder.loadProp("prop_reward_chest") ?? Self.standInBox())
        let lid = SCNNode()
        lid.position = Self.hinge
        lid.addChildNode(StageBuilder.loadProp("prop_reward_chest_lid") ?? Self.standInLid())
        chest.addChildNode(lid)
        // The split leaves both halves open shells, and an open lid shows the
        // camera its inside — back faces, culled, a ghost outline in the
        // first frames. Both sides drawn: the lid has an inside, the box has
        // a floor and walls to look into.
        chest.enumerateHierarchy { node, _ in
            for material in node.geometry?.materials ?? [] { material.isDoubleSided = true }
        }
        coordinator.lid = lid
        scene.rootNode.addChildNode(chest)

        // The shadow under it, the reveal's own image.
        let shadow = SCNPlane(width: 2.1, height: 1.4)
        let shadowMaterial = SCNMaterial()
        shadowMaterial.lightingModel = .constant
        shadowMaterial.diffuse.contents = SummonStageView.contactShadowImage
        shadowMaterial.writesToDepthBuffer = false
        shadow.firstMaterial = shadowMaterial
        let shadowNode = SCNNode(geometry: shadow)
        shadowNode.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        shadowNode.position = SCNVector3(0, 0.004, 0)
        shadowNode.opacity = 0.7
        scene.rootNode.addChildNode(shadowNode)

        // A 28° lens from in front and a little above, aimed at the lock:
        // the closed chest stands about two thirds of the frame's height,
        // and the lid has room to swing up.
        let camera = SCNCamera()
        camera.fieldOfView = 28
        camera.projectionDirection = .vertical
        camera.zNear = 0.2
        camera.zFar = 60
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.bloomIntensity = 0.42
        camera.bloomThreshold = 0.9
        camera.bloomBlurRadius = 14
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 1.45, 3.4)
        cameraNode.look(at: SCNVector3(0, 0.6, 0))
        scene.rootNode.addChildNode(cameraNode)

        // Key from the front-left, warm; a cool fill from the right; a gold
        // rim from behind for the edge of the lid; an ambient floor.
        let key = SCNLight()
        key.type = .directional
        key.intensity = 900
        key.color = UIColor(hex: "#FFF1D6") ?? .white
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-0.75, -0.55, 0)
        scene.rootNode.addChildNode(keyNode)
        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 320
        fill.color = UIColor(hex: "#8FA3D9") ?? .white
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-0.4, 0.8, 0)
        scene.rootNode.addChildNode(fillNode)
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 560
        rim.color = UIColor(hex: "#FFD36A") ?? .yellow
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(-0.5, 2.7, 0)
        scene.rootNode.addChildNode(rimNode)
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 210
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // The idle: a hop on the prompt's beat, and a slow turn either way.
        let hop = SCNAction.sequence([
            .wait(duration: 1.1),
            .moveBy(x: 0, y: 0.05, z: 0, duration: 0.09),
            .moveBy(x: 0, y: -0.05, z: 0, duration: 0.14),
        ])
        chest.runAction(.repeatForever(hop), forKey: "hop")
        let swayRight = SCNAction.rotateTo(x: 0, y: 0.2, z: 0, duration: 2.8, usesShortestUnitArc: true)
        swayRight.timingMode = .easeInEaseOut
        let swayLeft = SCNAction.rotateTo(x: 0, y: -0.2, z: 0, duration: 2.8, usesShortestUnitArc: true)
        swayLeft.timingMode = .easeInEaseOut
        chest.eulerAngles.y = -0.2
        chest.runAction(.repeatForever(.sequence([swayRight, swayLeft])), forKey: "sway")

        if open { openSequence(coordinator) }
        if gone { vanish(coordinator) }
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        if open, !coordinator.opened { openSequence(coordinator) }
        if gone, !coordinator.vanished { vanish(coordinator) }
    }

    /// The shake, the lid, the light. About a second; the flash follows.
    private func openSequence(_ coordinator: Coordinator) {
        guard !coordinator.opened, let lid = coordinator.lid, let scene = coordinator.scene else { return }
        coordinator.opened = true
        let chest = coordinator.chest
        chest.removeAction(forKey: "hop")
        chest.removeAction(forKey: "sway")
        let square = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: 0.15, usesShortestUnitArc: true)
        square.timingMode = .easeOut
        chest.runAction(square)

        // Four quick jolts, a third of a second.
        var jolts: [SCNAction] = []
        for index in 0..<4 {
            let dx: CGFloat = index % 2 == 0 ? 0.06 : -0.06
            jolts.append(.moveBy(x: dx, y: 0.02, z: 0, duration: 0.04))
            jolts.append(.moveBy(x: -dx, y: -0.02, z: 0, duration: 0.04))
        }
        chest.runAction(.sequence(jolts), forKey: "shake")

        // The lid swings back past open and settles. Its origin is its back
        // edge, so a negative turn about X is what lifts the front.
        let swing = SCNAction.rotateTo(x: -2.05, y: 0, z: 0, duration: 0.32, usesShortestUnitArc: false)
        swing.timingMode = .easeOut
        let settle = SCNAction.rotateTo(x: -1.85, y: 0, z: 0, duration: 0.2, usesShortestUnitArc: false)
        settle.timingMode = .easeInEaseOut
        lid.runAction(.sequence([.wait(duration: 0.32), swing, settle]))

        // The light standing up out of the box, and a flare at its mouth.
        let gold = UIColor(hex: "#FFD36A") ?? .yellow
        chest.runAction(.sequence([
            .wait(duration: 0.5),
            .run { _ in
                VFXLibrary.summonBeam(at: SCNVector3(0, 0.3, 0), in: scene, tint: gold)
                VFXLibrary.spawn("impact_radiance", at: SCNVector3(0, 0.8, 0), in: scene, tint: gold, scale: 1.3)
            },
        ]))
    }

    /// Lifts and fades under the flash; the spoils on the shelf are what stay.
    private func vanish(_ coordinator: Coordinator) {
        guard !coordinator.vanished else { return }
        coordinator.vanished = true
        let chest = coordinator.chest
        let away = SCNAction.group([
            .fadeOut(duration: 0.32),
            .moveBy(x: 0, y: 0.5, z: 0, duration: 0.32),
            .scale(to: 1.12, duration: 0.32),
        ])
        away.timingMode = .easeIn
        chest.runAction(away)
    }

    /// A box of wood banded in gold for a bundle without the mesh, at the
    /// mesh's own size, so the sequence plays either way.
    private static func standInBox() -> SCNNode {
        let node = SCNNode()
        let box = SCNBox(width: 1.35, height: 0.62, length: 0.86, chamferRadius: 0.03)
        box.firstMaterial?.diffuse.contents = UIColor(hex: "#5A3A22") ?? .brown
        let boxNode = SCNNode(geometry: box)
        boxNode.position = SCNVector3(0, 0.31, 0)
        node.addChildNode(boxNode)
        for x in [-0.42, 0.42] as [CGFloat] {
            let band = SCNBox(width: 0.14, height: 0.64, length: 0.88, chamferRadius: 0.01)
            band.firstMaterial?.diffuse.contents = UIColor(hex: "#D9A93C") ?? .yellow
            let bandNode = SCNNode(geometry: band)
            bandNode.position = SCNVector3(Float(x), 0.31, 0)
            node.addChildNode(bandNode)
        }
        return node
    }

    private static func standInLid() -> SCNNode {
        let lid = SCNBox(width: 1.35, height: 0.36, length: 0.86, chamferRadius: 0.1)
        lid.firstMaterial?.diffuse.contents = UIColor(hex: "#D9A93C") ?? .yellow
        let node = SCNNode(geometry: lid)
        // Relative to the hinge at the back-bottom edge.
        node.position = SCNVector3(0, 0.18, 0.43)
        return node
    }
}
