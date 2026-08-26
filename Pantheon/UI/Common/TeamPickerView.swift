import SwiftUI

/// Builds a team for a slot. Position 0 is the leader, and the leader skill is
/// shown as you change it — the whole point of the screen.
struct TeamPickerView: View {
    let slot: GameStore.TeamSlot
    let maxSize: Int

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: [UUID] = []

    private var selectedUnits: [ResolvedUnit] {
        selected.compactMap { store.resolved($0) }
    }

    private var roster: [ResolvedUnit] {
        store.resolvedUnits.sorted { $0.power > $1.power }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    lineup
                    leaderPanel
                    SectionHeader(title: "Your units", accessory: "\(roster.count)")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                        ForEach(roster) { unit in
                            Button {
                                toggle(unit.id)
                            } label: {
                                UnitCard(
                                    unit: unit,
                                    isSelected: selected.contains(unit.id),
                                    size: 96
                                )
                            }
                        }
                    }
                }
                .padding(16)
            }
            .screen(title)
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Save team", isEnabled: !selected.isEmpty) {
                    var preset = store.teamPreset(for: slot)
                    preset.unitIDs = selected
                    store.setTeam(preset, for: slot)
                    dismiss()
                }
                .padding(16)
                .background(Theme.ink)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
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

    private var lineup: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: "Lineup",
                accessory: "\(selected.count)/\(maxSize)"
            )
            HStack(spacing: 8) {
                let lineupUnits = selectedUnits
                ForEach(lineupUnits.indices, id: \.self) { index in
                    let unit = lineupUnits[index]
                    VStack(spacing: 3) {
                        UnitCard(unit: unit, size: 72)
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
                    EmptyTeamSlot(size: 72)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private var leaderPanel: some View {
        if let leader = selectedUnits.first {
            VStack(alignment: .leading, spacing: 5) {
                SectionHeader(title: "Leader skill")
                if let leaderSkill = leader.blueprint.leaderSkill {
                    Text(leaderSkill.description)
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textPrimary)
                    let affected = selectedUnits.filter { leaderSkill.applies(to: $0.blueprint) }.count
                    Text("Applies to \(affected) of \(selectedUnits.count) units in this team.")
                        .font(Theme.body(11))
                        .foregroundStyle(affected > 1 ? Theme.success : Theme.textSecondary)
                } else {
                    Text("\(leader.name) has no leader skill. Any unit can lead; only the bonus is lost.")
                        .font(Theme.body(13))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .panelBackground()
        }
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
