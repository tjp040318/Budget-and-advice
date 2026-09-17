import SwiftUI

/// The sweep control, and the receipt it leaves.
///
/// The genre puts sweep where the fight is launched from, not in a menu of
/// its own — Blue Archive's is a second button beside Start, Summoners War's
/// Scout Battle is a tab of the dungeon's own entry screen — because the
/// decision a player is making is "this stage, now, how many times", and a
/// sweep is one of the answers to it, not a different question.

/// A Sweep button that says why it is dark.
///
/// A disabled control with no reason is the single most annoying thing in a
/// menu, and this one is disabled most of the time by design: a stage is not
/// sweepable until it has been three-starred. So the refusal is a sentence
/// the player can act on, drawn beside the button rather than behind a tap.
struct SweepButton: View {
    let stage: Stage
    let runs: Int
    let onSweep: (Int) -> Void

    @EnvironmentObject private var store: GameStore

    private var refusal: String? { SweepService.refusal(stage, player: store.player) }
    private var affordable: Int { SweepService.affordableRuns(stage, player: store.player) }
    /// What a tap will actually do: what was asked for, or what the energy pays for.
    private var effectiveRuns: Int { max(1, min(runs, affordable)) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Button {
                onSweep(effectiveRuns)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 11, weight: .black))
                    Text(runs > 1 ? "Sweep ×\(effectiveRuns)" : "Sweep")
                        .font(Theme.body(12).weight(.black))
                        .tracking(0.6)
                }
                .foregroundStyle(refusal == nil ? Theme.ink : Theme.textSecondary)
                .padding(.horizontal, 14)
                .frame(height: Theme.buttonHeight)
                .background(
                    // A gradient and a colour will not unify in a ternary;
                    // every plate in the game that switches between them uses
                    // a Group, and one that did not cost a CI run.
                    Group {
                        if refusal == nil {
                            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                                .fill(Theme.goldPlate)
                        } else {
                            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                                .fill(Theme.surface)
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                        .strokeBorder(refusal == nil ? Color.clear : Theme.stroke, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .disabled(refusal != nil)

            if let refusal {
                Text(refusal)
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 240, alignment: .trailing)
            } else if runs > effectiveRuns {
                Text("Energy pays for \(effectiveRuns) of \(runs).")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.danger)
            } else {
                Text("No battle — \(EventCalendar.energyCost(for: stage) * effectiveRuns) energy")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// The receipt, over whatever screen asked for the sweep.
///
/// It is the win's own reward box (`SpoilsPanel`) rather than a list of its
/// own: a sweep pays exactly what the fights would have paid, and a player
/// who sees the same framed chest learns that without being told. The tiles
/// are all popped in at once — the victory screen deals them one by one
/// because that is the drama of a fight it just watched, and a sweep has no
/// drama to pace.
struct SweepReceiptCard: View {
    let receipt: SweepReceipt
    let loot: [BattleSummary.Loot]
    let onClose: () -> Void
    var onRelic: (Relic) -> Void = { _ in }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 8) {
                SpoilsPanel(
                    title: "\(receipt.stage.name) ×\(receipt.runs)",
                    stars: 3,
                    isFirstClear: false,
                    loot: loot,
                    shown: loot.count,
                    continueShown: true,
                    tapAction: { item in
                        guard let relic = item.relic else { return nil }
                        return { onRelic(relic) }
                    },
                    onContinue: onClose
                )
                caption
            }
            .padding(.horizontal, 24)
        }
    }

    /// The line under the chest: what it cost, and — when it matters — that
    /// the energy ran out before the runs did. A sweep that silently did
    /// eleven of twenty would be read as a bug.
    private var caption: some View {
        VStack(spacing: 2) {
            Text("\(receipt.runs) \(receipt.runs == 1 ? "run" : "runs") swept · \(receipt.energySpent) energy")
                .font(Theme.numeric(11))
                .foregroundStyle(Theme.plate)
            if receipt.cameUpShort {
                Text("The energy ran out after \(receipt.runs) of \(receipt.requested).")
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(Theme.gold)
            }
        }
        .shadow(color: .black.opacity(0.7), radius: 3)
    }
}
