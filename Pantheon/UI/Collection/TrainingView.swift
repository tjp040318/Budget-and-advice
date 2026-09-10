import SwiftUI

/// The Hall of Ka: where a unit is made stronger.
///
/// Summoners War's power-up circle, evolution and awakening under one roof.
/// Pick a unit, then feed it: every fed unit is consumed for experience, a fed
/// duplicate of the same character is a skill-up on top, evolution takes
/// same-grade fodder at max level, awakening takes essences. The rules all
/// live in `ProgressionService` and `GameStore`; this screen only shows their
/// consequences before the player commits, and what changed after.
///
/// The fourth mode is the fusion hexagram (`FusionService`), which is the odd
/// one out: it trains nobody, so it needs no unit selected and takes the whole
/// frame — a row of recipe panels rather than the rail, the fodder grid and the
/// cost column the other three share.
///
/// The chrome is `GameScreen`, and the shape is the genre's rather than the
/// platform's: the mode switch that used to be a full-width segmented picker
/// under a navigation bar is three segments in the 34-point strip, and the
/// screen is three columns instead of one long scroll — the roster you pick
/// from is a rail down the left, the fodder grid takes the middle, and what it
/// costs stands in a column at the right with its button always on screen.
/// Nothing scrolls but the two lists that can outgrow the frame.
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

    /// The rail is two cards wide; the cost column is fixed so the fodder grid
    /// takes every point the two of them leave.
    private let railWidth: CGFloat = 156
    private let costWidth: CGFloat = 214
    private let cardColumns = [GridItem(.adaptive(minimum: 68, maximum: 78), spacing: 6)]

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
                    } else {
                        HStack(alignment: .top, spacing: 8) {
                            rosterRail
                            detail
                        }
                    }
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.vertical, 8)
            }
            .onAppear {
                if targetID == nil { targetID = units.first?.id }
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

    // MARK: - Target

    /// The roster as a rail down the left rather than a strip across the top:
    /// in landscape the height is the scarce dimension, and two columns of
    /// cards keep eight units in reach where the strip kept four.
    private var rosterRail: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Who trains")
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: cardColumns, spacing: 8) {
                    ForEach(units) { unit in
                        Button {
                            targetID = unit.id
                        } label: {
                            // `UnitCard` fills its square with a portrait that
                            // is taller than it is wide, and `clipShape` does
                            // not clip hit-testing: the art overhangs the card
                            // by about a third of its height. In a strip that
                            // was harmless; in a grid the overhang reaches the
                            // row above, and the later card wins the tap. The
                            // hit area is the card's own rectangle.
                            UnitCard(unit: unit, isSelected: unit.id == targetID, size: 68)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .frame(width: railWidth)
    }

    @ViewBuilder
    private var detail: some View {
        if let target {
            VStack(spacing: 8) {
                targetPanel(target)
                switch mode {
                case .powerUp: powerUp(target)
                case .evolve: evolve(target)
                case .awaken: awaken(target)
                // Fusion never reaches here: the content builder sends `.fuse`
                // to the board before the target is looked at.
                case .fuse: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            EmptyState(
                icon: "person.crop.circle.badge.questionmark",
                title: "Choose a unit",
                message: "Tap a unit in the rail to train it."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func targetPanel(_ unit: ResolvedUnit) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(unit.name)
                        .font(Theme.title(16))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(String(repeating: "★", count: unit.stars))
                        .font(Theme.numeric(12))
                        .foregroundStyle(Theme.gold)
                }
                StatBar(
                    value: Double(unit.unit.experience),
                    maximum: Double(ProgressionService.experienceForNextLevel(level: unit.level, stars: unit.stars)),
                    tint: Theme.info,
                    height: 6,
                    label: unit.unit.isMaxLevel ? "Lv.\(unit.level) — max for \(unit.stars)★" : "Lv.\(unit.level) / \(unit.unit.maxLevel)"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Power \(unit.power)")
                .font(Theme.numeric(13))
                .foregroundStyle(Theme.gold)

            // What the last commit did, beside the unit it was done to, rather
            // than in a panel of its own that pushed everything down.
            if let outcome {
                Text(outcome)
                    .font(Theme.body(12).weight(.bold))
                    .foregroundStyle(Theme.gold)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 170, alignment: .trailing)
            }
        }
        .padding(10)
        .panelBackground()
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
            .frame(maxWidth: costWidth, maxHeight: .infinity, alignment: .topLeading)
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
        // A 6★ has no fodder column, so its one panel takes the whole frame.
        let panelWidth: CGFloat = maxed ? .infinity : costWidth

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
                            AudioLibrary.shared.play(.uiConfirm)
                        }
                    }
                }
            }
            .frame(maxWidth: panelWidth, maxHeight: .infinity, alignment: .topLeading)
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
                                AudioLibrary.shared.play(.uiConfirm)
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
                .frame(maxWidth: costWidth, maxHeight: .infinity, alignment: .topLeading)
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
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
            // A painting scaled to fill is wider than its frame and `clipShape`
            // does not clip hit-testing, so it would swallow taps meant for the
            // panel beside it.
            .allowsHitTesting(false)
            Text(caption)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                // `maxWidth`, not `width`: the two tiles and the arrow want
                // 254 points and the awakening panel has about 288 on a
                // notched phone but 241 on an SE, and a rigid width would
                // draw over the essences column rather than give way.
                .frame(maxWidth: 108)
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
                    UnitCard(unit: candidate, isSelected: fodder.contains(candidate.id), size: 68)
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
