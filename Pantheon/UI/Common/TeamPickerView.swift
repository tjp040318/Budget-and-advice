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

    /// Wide enough for a full team of faces across the lineup panel (five
    /// 52-point faces and their gaps are the panel's 284 points inside),
    /// narrow enough to leave the roster five columns on a landscape phone.
    private let railWidth: CGFloat = 300
    private let rosterColumns = [GridItem(.adaptive(minimum: 70, maximum: 84), spacing: 8)]
    private static let faceGap: CGFloat = 6
    /// How far the rail and the roster fade out at their foot, and the room
    /// left after their last line so it can scroll clear of the fade.
    private static let footFadeHeight: CGFloat = 18

    /// The lineup's face: the largest that puts `maxSize` of them in one
    /// row inside the panel (its 8-point padding each side), at most 52.
    private var face: CGFloat {
        let slots = CGFloat(max(1, maxSize))
        let inside = railWidth - 16 - (slots - 1) * Self.faceGap
        return min(52, (inside / slots).rounded(.down))
    }

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

    /// The lineup and the team's bonuses scroll together if a long leader
    /// skill needs the room; the Save plate is pinned below them either way.
    /// The scroll ends in a fade, not a cut: run 217 sliced the resonance's
    /// words through the middle of a line on the edge above Save.
    private var rail: some View {
        VStack(spacing: 8) {
            ScrollView {
                VStack(spacing: 8) {
                    lineup
                    bonusesPanel
                    Color.clear.frame(height: Self.footFadeHeight)
                }
            }
            .mask { footFade }
            PrimaryButton(title: "Save team", isEnabled: !selected.isEmpty) {
                var preset = store.teamPreset(for: slot)
                preset.unitIDs = selected
                store.setTeam(preset, for: slot)
                dismiss()
            }
        }
        .frame(width: railWidth)
    }

    /// The team as FACES in one row on one top line, every slot shown, the
    /// leader crowned — the briefing's "Your team" row that opens this
    /// screen, the same tiles. It was 58-point name cards in an adaptive
    /// grid with a LEADER line under the first: the taller leader cell was
    /// centred 9 points above the others with its label on the panel's
    /// border, a full team wrapped to a second row of one, and the panel's
    /// 150 points pushed the resonance off the rail (run 217). The names
    /// are on the roster's cards beside it, the selected ones rimmed.
    private var lineup: some View {
        SectionPanel(title: "Lineup", accessory: "\(selected.count)/\(maxSize)") {
            let lineupUnits = selectedUnits
            HStack(alignment: .top, spacing: Self.faceGap) {
                ForEach(lineupUnits.indices, id: \.self) { index in
                    let unit = lineupUnits[index]
                    UnitPortraitTile(unit: unit, size: face, isLeader: index == 0)
                        .onTapGesture { toggle(unit.id) }
                }
                ForEach(0..<max(0, maxSize - lineupUnits.count), id: \.self) { _ in
                    EmptyUnitSlot(size: face, onGlass: false)
                }
                Spacer(minLength: 0)
            }
            // Room over the leader's crown under the header, and the faces'
            // feet above the panel's acanthus corners, which reach about 18
            // points up from its foot.
            .padding(.top, 3)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Everything the composition gives, in ONE panel: the leader's skill
    /// and how many it reaches, what the lineup lights (`ResonanceService`)
    /// with each line's words, and the nearest thing one more unit would
    /// light. It was two panels, and on a phone the second sat below the
    /// fold under the Save plate with only its title showing (run 162's
    /// frame); one panel of rows fits above it with a resonance lit.
    @ViewBuilder
    private var bonusesPanel: some View {
        let blueprints = selectedUnits.map(\.blueprint)
        let lit = ResonanceService.active(for: blueprints)
        let hint = ResonanceService.hint(for: blueprints, maxSize: maxSize)
        if let leader = selectedUnits.first {
            SectionPanel(title: "Team bonuses", accessory: lit.isEmpty ? nil : "\(lit.count) lit") {
                VStack(alignment: .leading, spacing: 6) {
                    bonusRow(glyph: "crown.fill") {
                        if let leaderSkill = leader.blueprint.leaderSkill {
                            let affected = selectedUnits.filter { leaderSkill.applies(to: $0.blueprint) }.count
                            Text("LEADER · \(affected) OF \(selectedUnits.count)")
                                .font(Theme.title(11))
                                .tracking(0.8)
                                .foregroundStyle(affected > 1 ? Theme.goldDeep : Theme.textSecondary)
                            Text(leaderSkill.description)
                                .font(Theme.body(10))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("LEADER")
                                .font(Theme.title(11))
                                .tracking(0.8)
                                .foregroundStyle(Theme.textSecondary)
                            Text("\(leader.name) has no leader skill. Any unit can lead; only the bonus is lost.")
                                .font(Theme.body(10))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    ForEach(lit) { resonance in
                        bonusRow(glyph: resonance.kind.glyph) {
                            Text(resonance.displayName.uppercased())
                                .font(Theme.title(11))
                                .tracking(0.8)
                                .foregroundStyle(Theme.goldDeep)
                            Text(resonance.line)
                                .font(Theme.body(10))
                                .foregroundStyle(Theme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let hint {
                        Text(hint)
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// One bonus: its glyph in gold, and its name over its words.
    private func bonusRow<Content: View>(glyph: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: glyph)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(Theme.gold)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2, content: content)
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
            .padding(.bottom, Self.footFadeHeight)
        }
        // The last visible row fades rather than stopping on a hard line
        // with its names cut off (run 217's third row of Shabti).
        .mask { footFade }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A scroll's mask: opaque down to its last `footFadeHeight` points,
    /// which fade to nothing — a fixed height, so a short rail and a tall
    /// roster fade over the same distance.
    private var footFade: some View {
        VStack(spacing: 0) {
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.footFadeHeight)
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
