import SceneKit
import SwiftUI

/// The Hall of Ka: where a unit is made stronger, and a place.
///
/// Summoners War's power-up circle, evolution and awakening under one roof.
/// Pick a unit, then feed it: every fed unit is consumed for experience, a fed
/// duplicate of the same character is a skill-up on top, evolution takes
/// same-grade fodder at max level, awakening takes essences. The rules all
/// live in `ProgressionService` and `GameStore`; this screen only shows their
/// consequences before the player commits, and what changed after.
///
/// It was three plain panels. The owner, with the power-up grid on his phone:
/// "can we do something for the consuming like with the summoning temple? A
/// place with a full UI for powering up, awakening, evolve etc?" So it is the
/// summon screen's shape now — the stage left, the words right. The painting
/// is a temple sanctuary with an empty altar dais in its left third
/// (`hall_of_ka_bg`); the chosen unit stands on that dais in the flesh, its
/// real model on a rune ring over the painted stone (`AltarStageView`, a
/// transparent SceneKit view the size of the frame, the island's trick); the
/// roster to pick from is a rail of cards down the left edge; the fodder, the
/// requirements, the cost and the button are a panel over the right side.
/// A rite is played on the altar: the fed units fly into the figure as orbs
/// of their element and it flares, an evolution stands it in a pillar of
/// light, an awakening does the same and then the reveal plays the new form.
///
/// The fourth mode is the fusion hexagram (`FusionService`), which is the odd
/// one out: it trains nobody, so it needs no unit selected and takes the whole
/// frame — a row of recipe panels over the same painting.
struct TrainingView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    @State private var targetID: UUID?
    @State private var mode: Mode = .powerUp
    @State private var fodder: Set<UUID> = []
    @State private var outcome: String?
    /// Set when an awakening or a fusion succeeds: the summon reveal plays the
    /// new form in on the beam under its name. Both events are rarer than a
    /// summon, so both get the beam.
    @State private var reveal: SummonResult?
    /// The rite the altar is playing, stamped so the stage plays each once.
    @State private var ceremony: AltarCeremony?
    /// The words of the moment over the altar — "LEVEL UP!" — for a breath.
    @State private var stamp: AltarStamp?
    @State private var stampSequence = 0

    enum Mode: String, CaseIterable {
        case powerUp = "Power up"
        case evolve = "Evolve"
        case awaken = "Awaken"
        case fuse = "Fuse"
    }

    /// Which tab the screen opens on. Every caller wants the default; the CI
    /// tour wants a way to photograph the fusion board without a tap, and
    /// `@State` cannot read another property without an initialiser.
    init(initialMode: Mode = .powerUp) {
        _mode = State(initialValue: initialMode)
    }

    /// The mode switch as the strip's segments, in the order it always had.
    private var modes: [(value: Mode, title: String)] {
        Mode.allCases.map { (value: $0, title: $0.rawValue) }
    }

    /// Everything owned, strongest first, so the unit worth training is near
    /// the top of the rail.
    private var units: [ResolvedUnit] {
        store.resolvedUnits.sorted { $0.power > $1.power }
    }

    private var target: ResolvedUnit? {
        guard let targetID else { return nil }
        return units.first { $0.id == targetID }
    }

    private var subtitle: String {
        if mode == .fuse {
            let ready = plans.filter { $0.canFuse }.count
            return "\(FusionService.recipes.count) hexagrams · \(ready) ready"
        }
        guard let target else { return "\(units.count) units" }
        return "\(target.name) · Lv.\(target.level)"
    }

    /// Every recipe measured against the save. Six recipes of four corners
    /// against a roster of a hundred is a few hundred comparisons, which is
    /// cheaper than a cache that goes stale the moment a fusion eats something.
    private var plans: [FusionService.Plan] {
        FusionService.recipes.map { FusionService.plan(for: $0, player: store.player) }
    }

    /// The rail is one card wide down the left edge; the panel over the right
    /// side is fixed so the altar keeps the width between them, where the
    /// painting's dais is. On a notched phone the frame is about 820 points
    /// wide inside the padding: 76 for the rail, 424 for the panel, and the
    /// three hundred between them are the stage, with the dais's centre 29%
    /// of the way across the whole frame — under the figure.
    private let railWidth: CGFloat = 76
    private let panelWidth: CGFloat = 424
    private let costWidth: CGFloat = 178
    private let cardColumns = [GridItem(.adaptive(minimum: 64, maximum: 72), spacing: 6)]

    var body: some View {
        NavigationStack {
            GameScreen("Hall of Ka", subtitle: subtitle, dismiss: { dismiss() }) {
                // Always shown: fusion needs no unit picked, so hiding the
                // switch with an empty roster would hide the one mode that
                // still works.
                BarSegments(options: modes, selection: $mode)
                BarWallet(wallet: store.player.wallet, shows: [.drachma])
            } content: {
                Group {
                    if mode == .fuse {
                        fusionBoard
                            .padding(.horizontal, ScreenChrome.contentPadding)
                            .padding(.vertical, 8)
                    } else {
                        hall
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(hallPainting)
            }
            .onAppear {
                if targetID == nil { targetID = units.first?.id }
                // The altar loads a unit's model the moment it is picked; the
                // top of the rail is warmed off the main thread so the first
                // few taps do not stall on parsing.
                ModelLibrary.shared.warm(units.prefix(6).map(\.blueprint.model), crowded: false, clips: false)
            }
            .onChange(of: mode) { _, _ in
                fodder = []
                // The label belongs to the mode that wrote it: "Ares fused"
                // beside Zeus in the Power up column is a lie the next tap
                // would have to explain.
                outcome = nil
            }
            .onChange(of: targetID) { _, _ in
                fodder = []
                outcome = nil
            }
            .fullScreenCover(item: $reveal) { result in
                SummonRevealView(results: [result]) { reveal = nil }
            }
        }
    }

    // MARK: - The hall

    /// The sanctuary painting, the size of the frame and never larger.
    ///
    /// A `.background`, never a sibling: a fill-aspect painting under an
    /// unbounded frame reports its own size and grows every ancestor with it
    /// — the mistake that emptied the dungeon screen's frames. Off a
    /// GeometryReader with a fixed frame it can measure nothing.
    private var hallPainting: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.ink
                if BundleImage.exists("hall_of_ka_bg") {
                    BundleImage(name: "hall_of_ka_bg")
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                }
                // A little darker under the panel, so its words read, and the
                // painting's own vignette carried to the edges.
                LinearGradient(colors: [.clear, .clear, Theme.plate.opacity(0.35)],
                               startPoint: .leading, endPoint: .trailing)
            }
        }
        // A painting swallows taps far beyond its frame otherwise.
        .allowsHitTesting(false)
    }

    /// The stage under everything, then the rail, the altar's words and the
    /// panel across it.
    private var hall: some View {
        ZStack(alignment: .topLeading) {
            AltarStageView(unit: target, ceremony: ceremony)
                .allowsHitTesting(false)

            HStack(alignment: .top, spacing: 8) {
                rosterRail
                altarWords
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                if let target {
                    modePanel(target)
                        .frame(width: panelWidth)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(.horizontal, ScreenChrome.contentPadding)
            .padding(.vertical, 8)
        }
    }

    /// The roster as a rail of single cards down the left edge: in landscape
    /// the height is the scarce dimension, and one column of small cards
    /// keeps five units in reach and the painting's columns in view.
    private var rosterRail: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WHO TRAINS")
                .font(Theme.body(9).weight(.black))
                .tracking(1.4)
                .foregroundStyle(Theme.gold)
                .padding(.leading, 2)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(units) { unit in
                        Button {
                            targetID = unit.id
                        } label: {
                            // `UnitCard` fills its square with a portrait that
                            // is taller than it is wide, and `clipShape` does
                            // not clip hit-testing: the art overhangs the card
                            // by about a third of its height. The hit area is
                            // the card's own rectangle.
                            UnitCard(unit: unit, isSelected: unit.id == targetID, size: 64)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(6)
        .background(Theme.plate.opacity(0.42), in: RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
        .frame(width: railWidth)
    }

    /// Over the altar: who stands on it and how far along they are, in one
    /// translucent line, and the stamp of the moment when there is one.
    @ViewBuilder
    private var altarWords: some View {
        if let target {
            VStack(spacing: 0) {
                unitPlate(target)
                Spacer(minLength: 0)
                if let stamp {
                    stampView(stamp)
                        .padding(.bottom, 36)
                }
                Spacer(minLength: 0)
            }
        } else {
            EmptyState(
                icon: "person.crop.circle.badge.questionmark",
                title: "Choose a unit",
                message: "Tap a unit in the rail to train it."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func unitPlate(_ unit: ResolvedUnit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(unit.name)
                    .font(Theme.title(16))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                StarRow(stars: unit.stars, natural: unit.blueprint.naturalStars, size: 10)
                Spacer(minLength: 4)
                Text("Power \(unit.power)")
                    .font(Theme.numeric(12))
                    .foregroundStyle(Theme.gold)
            }
            StatBar(
                value: Double(unit.unit.experience),
                maximum: Double(ProgressionService.experienceForNextLevel(level: unit.level, stars: unit.stars)),
                tint: Theme.info,
                height: 5,
                label: unit.unit.isMaxLevel ? "Lv.\(unit.level) — max for \(unit.stars)★" : "Lv.\(unit.level) / \(unit.unit.maxLevel)"
            )
            // What the last commit did, beside the unit it was done to.
            if let outcome {
                Text(outcome)
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(Theme.gold)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.plate.opacity(0.46), in: RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
    }

    /// "LEVEL UP!" and the line under it, sprung in and gone in a breath.
    private func stampView(_ stamp: AltarStamp) -> some View {
        VStack(spacing: 2) {
            Text(stamp.title)
                .font(Theme.display(30))
                .foregroundStyle(Theme.gold)
                .shadow(color: Theme.gold.opacity(0.6), radius: 12)
                .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
            if !stamp.detail.isEmpty {
                Text(stamp.detail)
                    .font(Theme.numeric(13))
                    .foregroundStyle(Theme.textPrimary)
                    .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
            }
        }
        .multilineTextAlignment(.center)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
        .id(stamp.id)
    }

    @ViewBuilder
    private func modePanel(_ target: ResolvedUnit) -> some View {
        switch mode {
        case .powerUp: powerUp(target)
        case .evolve: evolve(target)
        case .awaken: awaken(target)
        // Fusion never reaches here: the content builder sends `.fuse`
        // to the board before the target is looked at.
        case .fuse: EmptyView()
        }
    }

    /// Shows the moment's words over the altar for a breath and a half.
    private func show(_ title: String, _ detail: String) {
        stampSequence += 1
        let mine = stampSequence
        withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
            stamp = AltarStamp(id: mine, title: title, detail: detail)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            guard mine == stampSequence else { return }
            withAnimation(.easeOut(duration: 0.4)) { stamp = nil }
        }
    }

    private func play(_ kind: AltarCeremony.Kind, tint: String) {
        ceremony = AltarCeremony(stamp: (ceremony?.stamp ?? 0) + 1, kind: kind, tintHex: tint)
    }

    // MARK: - Power up

    private func powerUp(_ target: ResolvedUnit) -> some View {
        let candidates = units.filter { $0.id != target.id && !$0.unit.isLocked }
        let chosen = candidates.filter { fodder.contains($0.id) }
        let experience = chosen.reduce(0) { $0 + ProgressionService.feedValue(of: $1.unit) }
        let duplicates = chosen.filter { $0.blueprint.id == target.blueprint.id }.count
        let cost = chosen.count * 500
        var preview = target.unit
        let gained = ProgressionService.grantExperience(experience, to: &preview)
        let affordable = store.player.wallet.drachma >= cost

        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Feed", accessory: "\(chosen.count) / 12")
                Text("Every unit you pick is consumed. A duplicate of \(target.name) is a skill-up as well as experience.")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if candidates.isEmpty {
                    EmptyState(
                        icon: "tray",
                        title: "Nothing to feed",
                        message: "Summon more units, or unlock one. Locked units are never consumed."
                    )
                } else {
                    ScrollView(showsIndicators: false) {
                        fodderGrid(candidates, limit: 12)
                            .padding(.bottom, 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .panelBackground()

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Result")
                resultRow("Experience", "+\(experience)")
                resultRow("Level", gained > 0 ? "Lv.\(target.level) → Lv.\(preview.level)" : "Lv.\(target.level), no change")
                if duplicates > 0 {
                    resultRow("Skill-ups", "×\(duplicates)", tint: Theme.gold)
                }
                resultRow("Cost", "\(cost) drachma", tint: affordable ? Theme.textPrimary : Theme.danger)
                if target.unit.isMaxLevel {
                    Text("\(target.name) is at the level cap for \(target.stars)★. Evolve to keep going.")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                PrimaryButton(
                    title: chosen.isEmpty ? "Pick units to feed" : "Power up",
                    systemImage: "arrow.up.circle.fill",
                    isEnabled: !chosen.isEmpty && affordable
                ) {
                    commitPowerUp(target, feeding: chosen)
                }
            }
            .frame(width: costWidth)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .panelBackground()
        }
    }

    private func commitPowerUp(_ target: ResolvedUnit, feeding chosen: [ResolvedUnit]) {
        let before = target.unit
        store.levelUp(target.id, feeding: chosen.map(\.id))
        fodder = []
        guard let after = store.resolved(target.id)?.unit else { return }
        var parts: [String] = []
        if after.level > before.level { parts.append("Lv.\(before.level) → Lv.\(after.level)") }
        let skillUps = zip(after.skillLevels, before.skillLevels).filter { $0 > $1 }.count
        if skillUps > 0 { parts.append("skill-up ×\(skillUps)") }
        if parts.isEmpty {
            outcome = after.level == before.level ? "Experience banked" : "Powered up"
        } else {
            outcome = "Powered up: " + parts.joined(separator: ", ")
        }
        Juice.notify(.success)
        AudioLibrary.shared.play(.uiConfirm)
        // The rite: the fed units fly into the figure and it flares; the
        // words land as the orbs do.
        play(.feed(count: chosen.count), tint: target.blueprint.element.accentHex)
        let title = after.level > before.level ? "LEVEL UP!" : (skillUps > 0 ? "SKILL UP!" : "POWERED UP")
        let detail = after.level > before.level
            ? "Lv.\(before.level) → Lv.\(after.level)" + (skillUps > 0 ? "  ·  skill-up ×\(skillUps)" : "")
            : (skillUps > 0 ? "skill-up ×\(skillUps)" : "+\(after.experience - before.experience) experience")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55 + 0.06 * Double(min(12, chosen.count))) {
            show(title, detail)
        }
    }

    // MARK: - Evolve

    private func evolve(_ target: ResolvedUnit) -> some View {
        let required = ProgressionService.evolutionFodderRequired(currentStars: target.stars)
        let cost = ProgressionService.drachmaCostToEvolve(currentStars: target.stars)
        let candidates = units.filter { $0.id != target.id && !$0.unit.isLocked && $0.stars == target.stars }
        let chosen = candidates.filter { fodder.contains($0.id) }
        let affordable = store.player.wallet.drachma >= cost
        let ready = target.unit.canEvolve && chosen.count == required && affordable
        let maxed = target.stars >= 6

        return HStack(alignment: .top, spacing: 8) {
            if !maxed {
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeader(title: "Fodder", accessory: "\(chosen.count) / \(required)")
                    if candidates.isEmpty {
                        EmptyState(
                            icon: "tray",
                            title: "No \(target.stars)★ fodder",
                            message: "Evolution takes unlocked units at exactly \(target.stars)★. Raise some fodder to that grade first."
                        )
                    } else {
                        ScrollView(showsIndicators: false) {
                            fodderGrid(candidates, limit: required)
                                .padding(.bottom, 4)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
                .panelBackground()
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: maxed ? "Fully evolved" : "Evolve to \(target.stars + 1)★")
                if maxed {
                    Text("\(target.name) is 6★, the top of the ladder.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    requirement("At max level", met: target.unit.isMaxLevel,
                                detail: "Lv.\(target.level) / \(target.unit.maxLevel)")
                    requirement("\(required) fodder at exactly \(target.stars)★", met: chosen.count == required,
                                detail: "\(chosen.count) / \(required) picked")
                    requirement("\(cost) drachma", met: affordable,
                                detail: "you have \(store.player.wallet.drachma)")
                    Text("Evolving resets the level to 1 and raises every stat; the fodder is consumed.")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 6)
                    PrimaryButton(
                        title: "Evolve",
                        systemImage: "star.circle.fill",
                        isEnabled: ready
                    ) {
                        store.evolve(target.id, fodderIDs: chosen.map(\.id))
                        fodder = []
                        if let after = store.resolved(target.id), after.stars > target.stars {
                            outcome = "\(after.name) evolved to \(after.stars)★"
                            Juice.notify(.success)
                            AudioLibrary.shared.play(.summonBurst, volume: 0.8)
                            play(.evolve, tint: target.blueprint.element.accentHex)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                show("EVOLVED", String(repeating: "★", count: after.stars))
                            }
                        }
                    }
                }
            }
            // A 6★ has no fodder column, so its one panel takes the whole width.
            .frame(maxWidth: maxed ? .infinity : costWidth)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
            .panelBackground()
        }
    }

    // MARK: - Awaken

    @ViewBuilder
    private func awaken(_ target: ResolvedUnit) -> some View {
        if let awakening = target.blueprint.awakening {
            let costs = awakening.essenceCost.sorted { $0.key < $1.key }
            let ready = costs.allSatisfy { (store.player.essences[$0.key] ?? 0) >= $0.value }
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Awakening")
                    Text(target.unit.isAwakened ? awakening.awakenedName : "Becomes \(awakening.awakenedName)")
                        .font(Theme.title(15))
                        .foregroundStyle(target.unit.isAwakened ? Theme.gold : Theme.textPrimary)
                    Text(awakening.bonusDescription)
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    // The two forms side by side — the card the unit has and the
                    // card it becomes — the way the genre sells an awakening.
                    HStack(spacing: 10) {
                        formTile(target.blueprint.model.portraitName, caption: target.blueprint.name)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.gold)
                        formTile(target.blueprint.model.portraitName(awakened: true), caption: awakening.awakenedName)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
                .panelBackground()

                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "Essences")
                    if target.unit.isAwakened {
                        Text("Already awakened.")
                            .font(Theme.body(12))
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ForEach(costs.indices, id: \.self) { index in
                            let id = costs[index].key
                            let needed = costs[index].value
                            let have = store.player.essences[id] ?? 0
                            requirement(EssenceCatalog.name(for: id), met: have >= needed, detail: "\(have) / \(needed)")
                        }
                        Text("Essences drop in the campaign; the element's own essence from its stages, magic essence from any.")
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 6)
                        PrimaryButton(title: "Awaken", systemImage: "sun.max.fill", isEnabled: ready) {
                            store.awaken(target.id)
                            if let after = store.resolved(target.id), after.unit.isAwakened {
                                outcome = "\(after.name) awakened"
                                Juice.notify(.success)
                                AudioLibrary.shared.play(.summonBurst, volume: 0.9)
                                // The altar's pillar first; the reveal of the
                                // new form follows it up.
                                play(.awaken, tint: target.blueprint.element.accentHex)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
                                    reveal = SummonResult(
                                        unit: after.unit,
                                        blueprint: after.blueprint,
                                        stars: after.stars,
                                        isNew: false,
                                        isFeatured: false,
                                        fromPity: false,
                                        isAwakening: true
                                    )
                                }
                            }
                        }
                    }
                }
                .frame(width: costWidth)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .padding(10)
                .panelBackground()
            }
        } else {
            EmptyState(
                icon: "sun.max",
                title: "No awakened form",
                message: "\(target.name) has no awakening; power up and evolve instead."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(10)
            .panelBackground()
        }
    }

    // MARK: - Pieces

    /// One form of a unit: its card and a caption. The awakened card is drawn
    /// before the unit awakens, from the file that ships with the family.
    private func formTile(_ image: String, caption: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if BundleImage.exists(image) {
                    BundleImage(name: image)
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: Theme.tightCorner)
                        .fill(Theme.surface)
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
            // A painting scaled to fill is wider than its frame and `clipShape`
            // does not clip hit-testing, so it would swallow taps meant for the
            // panel beside it.
            .allowsHitTesting(false)
            Text(caption)
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: 100)
        }
    }

    private func fodderGrid(_ candidates: [ResolvedUnit], limit: Int) -> some View {
        LazyVGrid(columns: cardColumns, spacing: 8) {
            ForEach(candidates) { candidate in
                Button {
                    if fodder.contains(candidate.id) {
                        fodder.remove(candidate.id)
                    } else if fodder.count < limit {
                        fodder.insert(candidate.id)
                        Juice.haptic(.light)
                    } else {
                        Juice.notify(.warning)
                    }
                } label: {
                    // As in the rail: the portrait overhangs the card, so the
                    // tap belongs to the card's rectangle and not to the art.
                    UnitCard(unit: candidate, isSelected: fodder.contains(candidate.id), size: 64)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func requirement(_ label: String, met: Bool, detail: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 13))
                .foregroundStyle(met ? Theme.success : Theme.stroke)
            Text(label)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Text(detail)
                .font(Theme.numeric(11))
                .foregroundStyle(met ? Theme.success : Theme.textSecondary)
        }
    }

    private func resultRow(_ label: String, _ value: String, tint: Color = Theme.textPrimary) -> some View {
        HStack {
            Text(label).font(Theme.body(12)).foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 4)
            Text(value).font(Theme.numeric(12)).foregroundStyle(tint)
        }
    }

    // MARK: - Fusion

    /// The hexagrams, one panel each, in a row that scrolls sideways.
    ///
    /// Six panels are about 1,700 points wide and a landscape frame is about
    /// 800, so this row is the one thing on the screen that scrolls. Every
    /// panel is the full height of the frame, which is what keeps the four
    /// corners and the Fuse button on the same line across all six.
    ///
    /// Nothing scrolls vertically here, so the panel has a height budget and
    /// it is written down rather than guessed at. An iPhone 16 Pro in
    /// landscape is 402 points tall; the home indicator takes 21, the strip
    /// 34 and the content's own padding 16, which leaves **331**. A panel
    /// spends 27 on the ribbon, 62 on the prize row, 22 on two lines of lore,
    /// 82 on the corner tiles, 22 on a two-line reason, 35 on the button,
    /// 30 on six gaps and 20 on its padding: **about 300**. The thirty points
    /// left are the margin, and the epithet, the lore and the reason are all
    /// line-limited so no content can spend them.
    ///
    /// This matters more than it looks. A child taller than the frame is the
    /// trap that emptied the dungeon screen's frames — an oversized view is
    /// clipped where it is drawn and not where it is measured — and here the
    /// thing that would go off the bottom is the only button on the screen.
    private var fusionBoard: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                ForEach(plans) { plan in
                    recipePanel(plan)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// One recipe: what it makes, what it is, what it takes, what it costs.
    private func recipePanel(_ plan: FusionService.Plan) -> some View {
        let recipe = plan.recipe
        let result = recipe.result

        return VStack(alignment: .leading, spacing: 5) {
            // The accessory is the compact figure — "40K" — because the
            // painted ribbon has about 248 points and a twenty-character
            // hexagram name spends most of them. The exact bill is in the line
            // above the button, where it is read just before it is paid.
            SectionHeader(title: recipe.name, accessory: BarWallet.compact(recipe.drachmaCost))

            HStack(alignment: .top, spacing: 8) {
                resultCard(result)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result?.name ?? recipe.resultID)
                        .font(Theme.title(15))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if let result {
                        Text(result.epithet)
                            .font(Theme.body(10))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        HStack(spacing: 5) {
                            StarRow(stars: result.naturalStars, size: 9)
                            ElementBadge(element: result.element, compact: true)
                        }
                    }
                    // The whole reason to do this rather than pull for it —
                    // and a red line instead if the pool filter ever comes off
                    // and the gacha starts handing the prize out again.
                    Text(recipe.isExclusive ? "No banner has this one." : "Still in the summon pool.")
                        .font(Theme.body(9).weight(.bold))
                        .foregroundStyle(recipe.isExclusive ? Theme.gold : Theme.danger)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(recipe.lore)
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 4) {
                ForEach(plan.slots) { slot in
                    ingredientTile(slot)
                }
            }

            // The spacer is what lines the six buttons up: it eats the slack,
            // so every button sits on its panel's bottom edge whether the
            // reason above it runs to one line or two. It carries no minimum,
            // because on a short frame the points it would have reserved are
            // the ones the button needs to stay on screen.
            Spacer(minLength: 0)

            Text(plan.blocker ?? "Four corners ready — \(recipe.drachmaCost) drachma.")
                .font(Theme.body(10))
                .foregroundStyle(plan.canFuse ? Theme.success : Theme.danger)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // `store.fuse(_:)` is the wiring: it calls
            // `FusionService.fuse(_:player:)` and hands back the new unit.
            PrimaryButton(
                title: plan.canFuse ? "Fuse" : "Not ready",
                systemImage: plan.canFuse ? "hexagon.fill" : "lock.fill",
                isEnabled: plan.canFuse
            ) {
                commitFusion(plan)
            }
        }
        .frame(width: 268, alignment: .topLeading)
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .panelBackground()
    }

    /// The prize's card, framed in its grade's metal.
    private func resultCard(_ blueprint: UnitBlueprint?) -> some View {
        ZStack {
            if let blueprint, BundleImage.exists(blueprint.model.portraitName) {
                BundleImage(name: blueprint.model.portraitName)
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(Theme.surface)
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
        .rarityFrame(Rarity(stars: blueprint?.naturalStars ?? 5))
        // The painting fills a square it is taller than, and `clipShape` does
        // not clip hit-testing: without this it swallows taps meant for the
        // panel beside it.
        .allowsHitTesting(false)
    }

    /// One corner: the character wanted, the grade and level it must be at, and
    /// either a tick or the one thing that is short.
    ///
    /// A corner the player cannot fill is drawn grey and half faded, so the
    /// panel reads at a glance — colour means owned — before any of the words
    /// under it are read.
    private func ingredientTile(_ slot: FusionService.Slot) -> some View {
        let blueprint = slot.ingredient.blueprint
        let met = slot.isMet

        return VStack(spacing: 2) {
            ZStack {
                if let blueprint, BundleImage.exists(blueprint.model.portraitName) {
                    BundleImage(name: blueprint.model.portraitName)
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                        .fill(Theme.surface)
                }
            }
            .frame(width: 46, height: 46)
            .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
            .saturation(met ? 1 : 0.1)
            .opacity(met ? 1 : 0.5)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .strokeBorder(met ? Theme.success : Theme.stroke, lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) {
                Image(systemName: met ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(met ? Theme.success : Theme.danger)
                    .shadow(color: .black.opacity(0.85), radius: 1)
                    .padding(2)
            }
            .overlay(alignment: .bottomLeading) {
                if let blueprint {
                    // Which of the five is wanted. Two Shabti of different
                    // elements are two different corners and one of them will
                    // not do for the other.
                    ElementBadge(element: blueprint.element, compact: true)
                        .padding(2)
                }
            }
            .allowsHitTesting(false)

            Text(blueprint?.name ?? slot.ingredient.blueprintID)
                .font(Theme.body(9).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(slot.ingredient.requirement)
                .font(Theme.numeric(9))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(met ? "ready" : (slot.shortfall?.short ?? "not ready"))
                .font(Theme.body(9))
                .foregroundStyle(met ? Theme.success : Theme.danger)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(width: 62)
    }

    private func commitFusion(_ plan: FusionService.Plan) {
        // Read before the fusion runs: the codex has the id in it the moment
        // the unit exists, and the reveal wants to know it was the first.
        let isNew = !store.player.codex.contains(plan.recipe.resultID)
        guard let created = store.fuse(plan.recipe) else { return }
        Juice.notify(.success)
        AudioLibrary.shared.play(.uiConfirm)
        reveal = SummonResult(
            unit: created.unit,
            blueprint: created.blueprint,
            stars: created.stars,
            isNew: isNew,
            isFeatured: false,
            fromPity: false
        )
    }
}

// MARK: - The altar

/// One rite on the altar, stamped so the stage plays each exactly once.
struct AltarCeremony {
    enum Kind {
        case feed(count: Int)
        case evolve
        case awaken
    }

    var stamp: Int
    var kind: Kind
    var tintHex: String
}

/// The words of a moment over the altar.
struct AltarStamp {
    var id: Int
    var title: String
    var detail: String
}

/// The chosen unit standing on the painted dais.
///
/// A transparent SceneKit view the size of the frame: the figure's real model
/// on a rune ring with a contact shadow, framed so its feet land on the
/// painting's altar — the island's trick of figures over a painting, done for
/// one, at the summon reveal's lens. The rites play here: the fed units fly
/// into the figure as orbs of its element and it flares; an evolution or an
/// awakening stands it in a pillar of its element's light.
struct AltarStageView: UIViewRepresentable {
    let unit: ResolvedUnit?
    let ceremony: AltarCeremony?

    /// Where the painting's dais is: its centre 29% of the way across the
    /// frame, its top 80% of the way down. Measured off `hall_of_ka_bg`.
    private static let daisAcross: Float = 0.29
    private static let daisDown: Float = 0.80
    /// The figure stands 56% of the frame's height: statuesque under the
    /// shaft of light, with the panel's words beside it rather than over it.
    private static let fill: Float = 0.56
    private static let lens: Float = 30

    final class Coordinator {
        var scene: SCNScene?
        var figure: SCNNode?
        var figureKey = ""
        var figureHeight: Float = 1.9
        var ring: SCNNode?
        var shadow: SCNNode?
        var cameraNode: SCNNode?
        var framedFor: Float = 0
        var playedStamp = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        view.scene = scene
        // Transparent: the painting behind this view is the hall. Everything
        // added here either blends with a real alpha channel or adds light
        // and writes no alpha (the summon stage's rule).
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X
        view.allowsCameraControl = false
        view.rendersContinuously = true
        view.isUserInteractionEnabled = false
        let coordinator = context.coordinator
        coordinator.scene = scene

        let camera = SCNCamera()
        camera.fieldOfView = CGFloat(Self.lens)
        camera.projectionDirection = .vertical
        camera.zNear = 0.5
        camera.zFar = 100
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.bloomIntensity = 0.3
        camera.bloomThreshold = 0.93
        camera.bloomBlurRadius = 12
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
        coordinator.cameraNode = cameraNode

        // Lit as the painting is: a warm key from the shaft of light above and
        // in front, a cool fill from the hall, a gold rim from behind, and an
        // ambient floor so the shadow side keeps its costume.
        let key = SCNLight()
        key.type = .directional
        key.intensity = 820
        key.color = UIColor(hex: "#FFE8C2") ?? .white
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.eulerAngles = SCNVector3(-1.0, -0.3, 0)
        scene.rootNode.addChildNode(keyNode)
        let fill = SCNLight()
        fill.type = .directional
        fill.intensity = 280
        fill.color = UIColor(hex: "#7C93D6") ?? .white
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.eulerAngles = SCNVector3(-0.4, 0.9, 0)
        scene.rootNode.addChildNode(fillNode)
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 480
        rim.color = UIColor(hex: "#FFD36A") ?? .yellow
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(-0.5, 2.7, 0)
        scene.rootNode.addChildNode(rimNode)
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 190
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        place(unit, in: coordinator)
        frameCamera(view, coordinator)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let coordinator = context.coordinator
        place(unit, in: coordinator)
        frameCamera(view, coordinator)
        if let ceremony, ceremony.stamp != coordinator.playedStamp {
            coordinator.playedStamp = ceremony.stamp
            play(ceremony, coordinator)
        }
    }

    /// The figure for the unit, rebuilt only when the unit or its form changes.
    private func place(_ unit: ResolvedUnit?, in coordinator: Coordinator) {
        guard let scene = coordinator.scene else { return }
        let key = unit.map { "\($0.blueprint.id)|\($0.unit.isAwakened)" } ?? ""
        guard key != coordinator.figureKey else { return }
        coordinator.figureKey = key
        coordinator.figure?.removeFromParentNode()
        coordinator.ring?.removeFromParentNode()
        coordinator.shadow?.removeFromParentNode()
        coordinator.figure = nil
        guard let unit else { return }
        let blueprint = unit.blueprint
        let height = blueprint.model.height
        let tint = UIColor(hex: blueprint.element.accentHex) ?? .white

        let node = ModelLibrary.shared.node(
            for: blueprint.model,
            archetype: blueprint.archetype,
            element: blueprint.element,
            awakened: unit.unit.isAwakened
        )
        if unit.unit.isAwakened {
            node.addParticleSystem(VFXLibrary.aura(tint: tint, scale: height / 1.9))
        }
        let assetName = blueprint.model.assetName
        if let idle = ModelLibrary.shared.animation(.idle, for: assetName)
            ?? ModelLibrary.shared.animation(.idleCombat, for: assetName) {
            node.addAnimation(idle, forKey: "idle")
        }
        // A three-quarter stance, turned a little toward the panel.
        node.eulerAngles.y = -0.3
        node.opacity = 0
        scene.rootNode.addChildNode(node)
        node.runAction(.fadeIn(duration: 0.35))
        coordinator.figure = node
        coordinator.figureHeight = height

        let ring = StageBuilder.runeRing(radius: CGFloat(max(1.2, height * 0.7)), tint: tint)
        scene.rootNode.addChildNode(ring)
        coordinator.ring = ring

        let size = CGFloat(height) * 0.75
        let plane = SCNPlane(width: size, height: size)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = SummonStageView.contactShadowImage
        material.writesToDepthBuffer = false
        plane.firstMaterial = material
        let shadow = SCNNode(geometry: plane)
        shadow.eulerAngles = SCNVector3(-Float.pi / 2, 0, 0)
        shadow.position = SCNVector3(0, 0.012, 0)
        shadow.renderingOrder = 5
        shadow.opacity = 0.75
        scene.rootNode.addChildNode(shadow)
        coordinator.shadow = shadow
        // A new height is a new framing.
        coordinator.framedFor = 0
    }

    /// Places the camera so the figure's feet land on the painted dais.
    ///
    /// The vertical lens makes the frame's height a known quantity: the
    /// figure is `fill` of it, the feet sit `daisDown` of the way down, and
    /// the camera is shifted — not turned — so the figure's centre line
    /// stands `daisAcross` of the way across, the reveal's rising front.
    /// Solved again only when the viewport's shape or the figure changes.
    private func frameCamera(_ view: SCNView, _ coordinator: Coordinator) {
        guard let cameraNode = coordinator.cameraNode else { return }
        let bounds = view.bounds
        // The content frame of a notched phone in landscape stands in until
        // the first real layout.
        let phoneAspect: Float = 820 / 330
        let aspect = bounds.height > 0 ? Float(bounds.width / bounds.height) : phoneAspect
        let framedFor = aspect * 1000 + coordinator.figureHeight
        guard abs(framedFor - coordinator.framedFor) > 0.01 else { return }
        coordinator.framedFor = framedFor

        let visible = coordinator.figureHeight / Self.fill
        let distance = visible / (2 * tan(Self.lens * .pi / 360))
        // The frame's centre is `daisDown - 0.5` of a frame above the feet.
        let aimY = visible * (Self.daisDown - 0.5)
        let halfWidth = visible * aspect / 2
        let x = halfWidth * (1 - 2 * Self.daisAcross)
        // A little above the aim and looking down at it, the way the painting
        // looks down at its dais.
        cameraNode.position = SCNVector3(x, aimY + visible * 0.08, distance)
        cameraNode.look(at: SCNVector3(x, aimY, 0))
    }

    /// The rite.
    private func play(_ ceremony: AltarCeremony, _ coordinator: Coordinator) {
        guard let scene = coordinator.scene, let figure = coordinator.figure else { return }
        let tint = UIColor(hex: ceremony.tintHex) ?? .white
        let height = coordinator.figureHeight
        switch ceremony.kind {
        case .feed(let count):
            // The fed units, as orbs from the panel's side, into the chest
            // one after another; then the flare and the light from below.
            let orbs = min(12, max(1, count))
            let chest = SCNVector3(0, height * 0.55, 0)
            for index in 0..<orbs {
                let orb = SCNNode(geometry: SCNSphere(radius: 0.1))
                let material = SCNMaterial()
                material.lightingModel = .constant
                material.diffuse.contents = tint
                material.emission.contents = tint
                material.blendMode = .add
                material.writesToDepthBuffer = false
                // Adds light, so it writes no alpha: the transparent view's rule.
                material.colorBufferWriteMask = [.red, .green, .blue]
                orb.geometry?.firstMaterial = material
                let column = Float(index % 3)
                let row = Float(index / 3)
                orb.position = SCNVector3(2.6 + column * 0.55, 0.5 + row * 0.4, 0.3 - column * 0.3)
                orb.opacity = 0
                scene.rootNode.addChildNode(orb)
                let fly = SCNAction.move(to: chest, duration: 0.45)
                fly.timingMode = .easeIn
                orb.runAction(.sequence([
                    .wait(duration: 0.06 * Double(index)),
                    .fadeIn(duration: 0.12),
                    fly,
                    .run { _ in VFXLibrary.spawn("buff", at: chest, in: scene, tint: tint, scale: 0.5) },
                    .removeFromParentNode(),
                ]))
            }
            figure.runAction(.sequence([
                .wait(duration: 0.06 * Double(orbs) + 0.55),
                .run { node in
                    Self.flare(node)
                    VFXLibrary.summonBeam(at: SCNVector3(0, 0, 0), in: scene, tint: tint)
                },
            ]))
        case .evolve, .awaken:
            let swell = SCNAction.sequence([.scale(by: 1.08, duration: 0.25), .scale(by: 1 / 1.08, duration: 0.4)])
            swell.timingMode = .easeInEaseOut
            figure.runAction(swell)
            Self.flare(figure)
            VFXLibrary.summonBeam(at: SCNVector3(0, 0, 0), in: scene, tint: tint)
            let effect: String
            if case .awaken = ceremony.kind { effect = "duat_rite" } else { effect = "olympian_decree" }
            VFXLibrary.spawn(effect, at: SCNVector3(0, height * 0.5, 0), in: scene, tint: tint, scale: 1.2)
        }
    }

    /// A flash of light through the figure: the battle's hit flash.
    private static func flare(_ node: SCNNode) {
        node.enumerateHierarchy { child, _ in
            for material in child.geometry?.materials ?? [] {
                let previous = material.emission.contents
                material.emission.contents = UIColor(white: 0.85, alpha: 1)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    material.emission.contents = previous
                }
            }
        }
    }
}
