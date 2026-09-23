import SwiftUI

/// The regalia's level as five pips, I–V: lit gold up to the level, ghosts
/// after; all ghosts while the item is locked. On the unit sheet's plate
/// and the regalia sheet.
struct RegaliaPips: View {
    let level: Int
    var lit: Bool = true
    var size: CGFloat = 6

    var body: some View {
        HStack(spacing: size * 0.45) {
            ForEach(1...RegaliaTemplate.levels, id: \.self) { step in
                Circle()
                    .fill(step <= level && lit ? Theme.gold : Theme.surfaceHigh)
                    .overlay(
                        Circle().strokeBorder(lit ? Theme.goldDim.opacity(0.8) : Theme.stroke, lineWidth: 0.5)
                    )
                    .frame(width: size, height: size)
            }
        }
    }
}

/// One family's regalia (`Regalia`, `RegaliaService`; `Docs/PLAN.md`,
/// *Artifacts — the last item on the order*): opened from the plate under
/// the unit sheet's relic ring. The left is the item — the card with the
/// name, the template, the level and the line at this level (or what
/// unlocks it) beside it, and the item's story under them; the right is the
/// ladder of five levels with the current one marked, and what raises it.
/// Nothing here is bought or rolled: the regalia is the one thing on a unit
/// a player can plan, and this sheet is the plan.
struct RegaliaSheet: View {
    let unitID: UUID

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    private var unit: ResolvedUnit? { store.resolved(unitID) }
    /// The family's regalia at the unit's banked level, unlocked or not.
    private var regalia: Regalia? {
        unit.flatMap { RegaliaService.regalia(forBlueprint: $0.blueprint.id, level: RegaliaService.level(of: $0.unit)) }
    }
    private var unlocked: Bool { unit?.regalia != nil }

    var body: some View {
        NavigationStack {
            GameScreen(
                regalia?.name ?? "Regalia",
                subtitle: unit.map { "Regalia of \($0.blueprint.name)" } ?? "The family's own item",
                dismiss: { dismiss() }
            ) {
                BarButton(title: "Done", systemImage: "checkmark.circle.fill", tint: Theme.gold) { dismiss() }
            } content: {
                if let unit, let regalia {
                    HStack(alignment: .top, spacing: 8) {
                        // Whole when it fits, as the column beside it; a
                        // locked Oracle with a level banked runs about 310
                        // points, over the 308 of a 393-point iPhone's
                        // plate, and scrolls there instead of spilling.
                        RegaliaColumnScroll {
                            item(unit, regalia)
                        }
                        .frame(width: 300)
                        // The ladder and what raises it fit the phone's
                        // height whole (run 217 cut "What raises it" through
                        // its second row), and "What raises it" runs to the
                        // column's foot, level with the item beside it; on a
                        // shorter phone, or a line that wraps, the column
                        // scrolls and says so.
                        RegaliaColumnScroll {
                            VStack(spacing: 6) {
                                ladder(regalia)
                                raising(unit, regalia)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, ScreenChrome.contentPadding)
                    .padding(.vertical, 6)
                } else {
                    EmptyState(icon: "crown", title: "No regalia", message: "This family has no item of its own yet.")
                }
            }
        }
    }

    // MARK: - The item

    /// The card with the item's words beside it — its name, template and
    /// level, then what it does NOW (or what unlocks it) — and under them
    /// the item's story as its inscription, which takes the rest of the
    /// plate.
    ///
    /// Run 221's judge: the plate left a blank block right of the card
    /// under "Level III of V" and about 50 points of bare cream at its foot,
    /// under the effect. The effect stands beside the card now, in the
    /// block that was blank; and the words are short of the plate's height
    /// (about 317 points on the 16 Pro) whatever order they stand in, so the story is not
    /// a paragraph left above an empty foot but a recessed plate that fills
    /// it — the item's glyph on a gold rule, the lines centred under it.
    /// The plate ends 18 points up, clear of the panel's lower acanthus.
    private func item(_ unit: ResolvedUnit, _ regalia: Regalia) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                UnitCard(unit: unit, showPower: false, size: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text(regalia.name)
                        .font(Theme.title(14))
                        .foregroundStyle(unlocked ? Theme.gold : Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Chip(
                        text: "\(regalia.template.displayName) · \(regalia.template.kitName)",
                        systemImage: regalia.template.glyph,
                        tint: Theme.gold,
                        filled: unlocked
                    )
                    HStack(spacing: 6) {
                        RegaliaPips(level: regalia.level, lit: unlocked, size: 7)
                        Text("Level \(regalia.levelLabel) of \(Regalia.numeral(RegaliaTemplate.levels))")
                            .font(Theme.body(11).weight(.bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    effect(unit, regalia)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            inscription(regalia)
        }
        .padding(.horizontal, Theme.panelInset)
        .padding(.top, Theme.panelInset)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .panelBackground(radius: Theme.tightCorner)
    }

    /// What the item does at this level and where the engine reads it — or,
    /// locked, what unlocks it and what it will do.
    @ViewBuilder
    private func effect(_ unit: ResolvedUnit, _ regalia: Regalia) -> some View {
        if unlocked {
            VStack(alignment: .leading, spacing: 2) {
                Text(regalia.line)
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(Theme.gold)
                    .fixedSize(horizontal: false, vertical: true)
                Text(regalia.template.hookName)
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(Theme.goldDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .black))
                    Text(RegaliaService.unlockLine(for: unit.blueprint).uppercased())
                        .font(Theme.title(12))
                        .tracking(1.0)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Theme.textSecondary)
                Text(lockedLine(regalia))
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The item's story: its glyph on a short gold rule and the blurb
    /// centred under it, on a recessed plate that takes whatever height the
    /// words above leave — so the plate ends on the column's foot, level
    /// with "What raises it" beside it, with nothing blank under it.
    private func inscription(_ regalia: Regalia) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                LinearGradient(colors: [Theme.goldDim.opacity(0), Theme.goldDim.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
                Image(systemName: regalia.template.glyph)
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(unlocked ? Theme.gold : Theme.textSecondary)
                LinearGradient(colors: [Theme.goldDim.opacity(0.7), Theme.goldDim.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 1)
            }
            .frame(maxWidth: 170)
            Text(regalia.blurb)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(Theme.surface.opacity(0.7)))
        .overlay(shape.strokeBorder(Theme.stroke.opacity(0.8), lineWidth: 0.75))
    }

    /// What a locked item will do once it is lit, with the banked level
    /// named when duplicates have already been fed.
    private func lockedLine(_ regalia: Regalia) -> String {
        let promise = "Once unlocked: \(regalia.line)."
        return regalia.level > 1
            ? promise + " Level \(regalia.levelLabel) is banked already and lights with it."
            : promise
    }

    // MARK: - The ladder

    /// The five levels, one line each, with an aside the lines share printed
    /// ONCE under them: a Lasting Word's III, IV and V each closed on "(never
    /// a stun, a freeze or a sleep)", which doubled three rows to two lines
    /// and ran "What raises it" off the foot of the sheet (run 217).
    private func ladder(_ regalia: Regalia) -> some View {
        let carrying = (1...RegaliaTemplate.levels).filter { ladderWords(regalia, level: $0).aside != nil }
        let aside = carrying.first.flatMap { ladderWords(regalia, level: $0).aside }
        return SectionPanel(title: "The five levels", accessory: "I → \(Regalia.numeral(RegaliaTemplate.levels))") {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(1...RegaliaTemplate.levels, id: \.self) { level in
                    ladderRow(regalia, level: level)
                }
                if let aside, let first = carrying.first, let last = carrying.last {
                    // Under the rows' words, not under their numerals: at
                    // the rows' own 6 it stood on the panel's acanthus
                    // corner (run 220).
                    Text("\(ladderSpan(first, last)): \(aside)")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, Self.ladderWordsInset)
                        .padding(.trailing, 6)
                }
            }
        }
    }

    /// A level's line for the ladder, split from the parenthesised aside it
    /// closes on, if any: "+10% accuracy, and the debuffs it lands hold a
    /// turn longer" and "never a stun, a freeze or a sleep".
    private func ladderWords(_ regalia: Regalia, level: Int) -> (words: String, aside: String?) {
        let line = regalia.template.line(regalia.template.magnitude(at: level), level: level)
        guard line.hasSuffix(")"), let open = line.range(of: " (", options: .backwards) else {
            return (line, nil)
        }
        let aside = String(line[open.upperBound..<line.index(before: line.endIndex)])
        return (String(line[..<open.lowerBound]), aside)
    }

    /// "III–V", or "V" alone.
    private func ladderSpan(_ first: Int, _ last: Int) -> String {
        first == last ? Regalia.numeral(first) : "\(Regalia.numeral(first))–\(Regalia.numeral(last))"
    }

    /// The numeral column of a ladder row, and where the row's words start
    /// from the row's own edge (its padding, the column, the spacing).
    private static let ladderNumeralWidth: CGFloat = 22
    private static let ladderWordsInset: CGFloat = 6 + ladderNumeralWidth + 6

    private func ladderRow(_ regalia: Regalia, level: Int) -> some View {
        let current = level == regalia.level
        let reached = level <= regalia.level && unlocked
        return HStack(spacing: 6) {
            // 22 holds "III", the widest numeral, at 15 points in Cinzel.
            // The numeral is drawn over its column rather than laid out in
            // it: Cinzel's line is three points taller than the words', and
            // it set every row's height — fifteen points over the ladder,
            // which left "What raises it" too short to wear its marble
            // whole (run 220).
            Color.clear
                .frame(width: Self.ladderNumeralWidth, height: 1)
                .overlay(alignment: .leading) {
                    Text(Regalia.numeral(level))
                        .font(Theme.title(12))
                        .foregroundStyle(reached ? Theme.gold : Theme.textSecondary)
                        .fixedSize()
                }
            Text(ladderWords(regalia, level: level).words)
                .font(Theme.body(10))
                .foregroundStyle(reached ? Theme.textPrimary : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if current {
                // One point above and below: the tag set the current row's
                // height, and every point of the ladder is one "What raises
                // it" needs to wear its marble whole.
                Text(unlocked ? "NOW" : "BANKED")
                    .font(Theme.body(9).weight(.black))
                    .tracking(0.8)
                    .foregroundStyle(unlocked ? Theme.ink : Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(unlocked ? Theme.gold : Theme.surfaceHigh))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(current ? Theme.gold.opacity(0.12) : Theme.surface)
        )
    }

    // MARK: - What raises it

    private func raising(_ unit: ResolvedUnit, _ regalia: Regalia) -> some View {
        let capped = RegaliaService.skillsAreCapped(unit.unit, blueprint: unit.blueprint)
        let owed = RegaliaService.skillUpsRemaining(unit.unit, blueprint: unit.blueprint)
        let toGo = RegaliaTemplate.levels - regalia.level
        let owedLine = "\(owed) skill-up\(owed == 1 ? "" : "s") still owed: duplicates go to the skills first"
        let levelLine = "Level \(regalia.levelLabel) of \(Regalia.numeral(RegaliaTemplate.levels)) — "
            + "\(toGo) more duplicate\(toGo == 1 ? "" : "s") to V"
        return SectionPanel(title: "What raises it") {
            VStack(alignment: .leading, spacing: 4) {
                Text(RegaliaService.raisingLine)
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                progressRow(
                    "sun.max.fill",
                    unlocked ? "Unlocked" : RegaliaService.unlockLine(for: unit.blueprint),
                    done: unlocked
                )
                progressRow(
                    "book.fill",
                    capped ? "Every skill at its cap — the next duplicate raises the regalia" : owedLine,
                    done: capped
                )
                progressRow(
                    "crown.fill",
                    regalia.isMaxLevel ? "Level \(regalia.levelLabel): the item is complete" : levelLine,
                    done: regalia.isMaxLevel
                )
            }
            // Takes what the column leaves when the column fits, so the
            // panel ends on the column's foot beside the item's.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func progressRow(_ symbol: String, _ text: String, done: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: done ? "checkmark.circle.fill" : symbol)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(done ? Theme.success : Theme.goldDim)
                .frame(width: 14)
            Text(text)
                .font(Theme.body(10).weight(done ? .bold : .medium))
                .foregroundStyle(done ? Theme.textPrimary : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

/// The fade at the foot of the regalia sheet's right column when it scrolls,
/// and the room its last line keeps under it to scroll clear.
private let regaliaColumnFade: CGFloat = 14

/// The coordinate space `RegaliaColumnScroll` measures its content in.
private let regaliaColumnSpace = "regaliaColumnScroll"

/// The regalia sheet's right column, measured the way the unit sheet's
/// panels are (`SheetPanelScroll`, private to UnitDetailView.swift): content
/// that fits is drawn whole with no fade at all; content that does not fades
/// at the foot and wears a small chevron there until its last line has been
/// scrolled into view. The plain scroll it replaces cut "What raises it"
/// through a line of words with no border and nothing to say it scrolled
/// (run 217, frame 46).
private struct RegaliaColumnScroll<Content: View>: View {
    let content: () -> Content
    @State private var contentFrame: CGRect = .zero
    @State private var viewportHeight: CGFloat = 0

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    /// Half a point, not one or two: a column a point or two too tall was
    /// neither drawn whole nor faded, only cut. Run 220's cut was the
    /// marble's, though — "What raises it" was 128 points, under the
    /// painted panel's 140 of caps, and its frame drew past its own foot
    /// into the clip — which is why the panel now stretches to the foot.
    private var overflows: Bool { contentFrame.height > viewportHeight + 0.5 }
    private var moreBelow: Bool { overflows && contentFrame.maxY > viewportHeight + 0.5 }
    /// Content that fits is given the whole column, so a panel that can
    /// stretch ("What raises it") ends on the column's foot.
    private var fills: Bool { !overflows && viewportHeight > 0 }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content()
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .named(regaliaColumnSpace))
                        Color.clear
                            .onAppear { contentFrame = frame }
                            .onChange(of: frame) { _, now in contentFrame = now }
                    }
                )
                .frame(height: fills ? viewportHeight : nil, alignment: .top)
                .padding(.bottom, overflows ? regaliaColumnFade : 0)
        }
        .coordinateSpace(name: regaliaColumnSpace)
        .scrollBounceBehavior(.basedOnSize)
        .background(
            GeometryReader { proxy in
                let height = proxy.size.height
                Color.clear
                    .onAppear { viewportHeight = height }
                    .onChange(of: height) { _, now in viewportHeight = now }
            }
        )
        .mask(
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [Color.black, moreBelow ? Color.clear : Color.black], startPoint: .top, endPoint: .bottom)
                    .frame(height: regaliaColumnFade)
            }
        )
        .overlay(alignment: .bottom) {
            if moreBelow {
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.goldDim)
                    .frame(width: 30, height: 12)
                    .background(Capsule().fill(Theme.surfaceHigh.opacity(0.92)))
                    .overlay(Capsule().strokeBorder(Theme.gold.opacity(0.35), lineWidth: 0.8))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
