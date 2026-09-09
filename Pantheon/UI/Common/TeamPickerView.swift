import SwiftUI

/// Builds a team for a slot. Position 0 is the leader, and the leader skill is
/// shown as you change it — the whole point of the screen.
///
/// Landscape shape: a fixed rail on the left holds the lineup, the leader
/// skill and the Save plate; the roster owns the whole frame to the right of
/// it. The old stack put the roster last — under a navigation bar, the lineup,
/// a leader panel and a section header — and left it one row of cards tall on
/// a phone. Nothing here changes what the screen does; the picker's init and
/// the preset it writes are untouched, because three screens present it.
struct TeamPickerView: View {
    let slot: GameStore.TeamSlot
    let maxSize: Int

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [UUID] = []

    /// Wide enough for four lineup tiles across, narrow enough to leave the
    /// roster seven columns on a landscape phone.
    private let railWidth: CGFloat = 300
    private let rosterColumns = [GridItem(.adaptive(minimum: 70, maximum: 84), spacing: 8)]
    private let lineupColumns = [GridItem(.adaptive(minimum: 56, maximum: 70), spacing: 6)]

    private var selectedUnits: [ResolvedUnit] {
        selected.compactMap { store.resolved($0) }
    }

    private var roster: [ResolvedUnit] {
        store.resolvedUnits.sorted { $0.power > $1.power }
    }

    var body: some View {
        NavigationStack {
            GameScreen(
                title,
                subtitle: "\(selected.count)/\(maxSize) chosen",
                dismiss: { dismiss() }
            ) {
                BarCount(value: "\(roster.count)", systemImage: "person.3.fill")
            } content: {
                HStack(spacing: 10) {
                    rail
                    rosterGrid
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.vertical, 8)
            }
            .onAppear {
                selected = store.teamPreset(for: slot).unitIDs
            }
        }
    }

    private var title: String {
        switch slot {
        case .campaign: return "Campaign Team"
        case .arenaOffense: return "Arena Offence"
        case .arenaDefense: return "Arena Defence"
        }
    }

    // MARK: - Rail

    /// The lineup and the leader skill scroll together if a long leader skill
    /// needs the room; the Save plate is pinned below them either way.
    private var rail: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(spacing: 8) {
                    lineup
                    leaderPanel
                }
            }
            PrimaryButton(title: "Save team", isEnabled: !selected.isEmpty) {
                var preset = store.teamPreset(for: slot)
                preset.unitIDs = selected
                store.setTeam(preset, for: slot)
                dismiss()
            }
        }
        .frame(width: railWidth)
    }

    private var lineup: some View {
        SectionPanel(title: "Lineup", accessory: "\(selected.count)/\(maxSize)") {
            LazyVGrid(columns: lineupColumns, spacing: 6) {
                let lineupUnits = selectedUnits
                ForEach(lineupUnits.indices, id: \.self) { index in
                    let unit = lineupUnits[index]
                    VStack(spacing: 3) {
                        UnitCard(unit: unit, size: 58)
                        if index == 0 {
                            Text("LEADER")
                                .font(Theme.body(8).weight(.black))
                                .tracking(1)
                                .foregroundStyle(Theme.gold)
                        }
                    }
                    .onTapGesture { toggle(unit.id) }
                }
                if selected.count < maxSize {
                    EmptyTeamSlot(size: 58)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var leaderPanel: some View {
        if let leader = selectedUnits.first {
            SectionPanel(title: "Leader skill", accessory: nil) {
                VStack(alignment: .leading, spacing: 5) {
                    if let leaderSkill = leader.blueprint.leaderSkill {
                        Text(leaderSkill.description)
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textPrimary)
                        let affected = selectedUnits.filter { leaderSkill.applies(to: $0.blueprint) }.count
                        Text("Applies to \(affected) of \(selectedUnits.count) units in this team.")
                            .font(Theme.body(10))
                            .foregroundStyle(affected > 1 ? Theme.success : Theme.textSecondary)
                    } else {
                        Text("\(leader.name) has no leader skill. Any unit can lead; only the bonus is lost.")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Roster

    private var rosterGrid: some View {
        ScrollView {
            LazyVGrid(columns: rosterColumns, spacing: 8) {
                ForEach(roster) { unit in
                    Button {
                        toggle(unit.id)
                    } label: {
                        UnitCard(
                            unit: unit,
                            isSelected: selected.contains(unit.id),
                            size: 70
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Tapping a selected unit removes it; tapping a new one appends it, which
    /// makes the tap order the lineup order and the first tap the leader.
    private func toggle(_ id: UUID) {
        if let index = selected.firstIndex(of: id) {
            selected.remove(at: index)
        } else if selected.count < maxSize {
            selected.append(id)
        }
    }
}
