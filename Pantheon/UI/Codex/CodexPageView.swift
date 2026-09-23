import SwiftUI

/// One page of the Codex: a form of a family, in its plain or awakened face
/// (2026-09-23; Docs/CODEX.md).
///
/// Three glass plates over the pantheon's painting. On the left the card —
/// the painting in its carved frame once recorded, in shadow under a "?"
/// until then — the form's full name, and the page's reward with its Claim:
/// the form's own divinity and, the first time a page of the family is
/// taken, the family's first. In the middle the skills, read the way the
/// unit sheet reads them (`ProgressionService.resolve` of the form at level
/// 1, awakened for an awakened page: icons in a row, the chosen one's words
/// under them, the leader skill as the crown's tile), and the family's lore.
/// On the right WHERE TO GET IT, read off the systems themselves
/// (`CodexService.sources`): the banners whose pools draw it with the
/// grade's rate and the mileage it costs there — a Radiance or Umbra form
/// lists the Light & Dark scroll alone — a fusion recipe, the Night Market,
/// the opening gift; an awakened page leads with the awakening and its bill.
///
/// The strip steps through the family: its five elements as the filter's
/// tiles, and Form or Awakened. An unrecorded form keeps its name, skills,
/// lore and roads in view — the genre's book shows what it is hunting — and
/// only the card and the reward wait.
///
/// Measured on an iPhone 16 Pro's content box of 750 × 329: the card plate
/// 200 wide, 293 points of it filled (a 108-point card, the name on two
/// lines, the reward's row and its line, the 34-point Claim); the roads
/// plate 224; the skills the 282 between (266 on an iPhone 16, whose safe
/// width is 734). Both word plates scroll on whole rows.
struct CodexPageView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    let familyKey: String
    @State private var pageElement: Element
    @State private var pageKind: CodexFormKind
    /// The skill whose words are shown; `leaderSlot` for the crown's.
    @State private var pickedSkill = 0
    @State private var pageReceipt: [ShopService.Grant] = []
    @State private var pageReceiptID = UUID()

    init(request: CodexPageRequest) {
        familyKey = request.familyKey
        _pageElement = State(initialValue: request.element)
        _pageKind = State(initialValue: request.kind)
    }

    private static let cardColumn: CGFloat = 200
    private static let sourceColumn: CGFloat = 224
    private static let cardSize: CGFloat = 108
    private static let skillIcon: CGFloat = 38
    private static let leaderSlot = -1

    var body: some View {
        let family = CodexService.family(key: familyKey)
        let book = CodexService.ledger(for: store.player)
        let entry = family.flatMap { $0.entry(pageElement, pageKind) ?? $0.entry(pageElement, .base) }

        GameScreen(family?.name ?? "Codex", subtitle: family.map { realmLine($0) }, dismiss: { dismiss() }) {
            ElementFilterTiles(selection: elementChoice)
            if family?.awakenable ?? false {
                BarSegments(options: [(value: CodexFormKind.base, title: "Form"),
                                      (value: CodexFormKind.awakened, title: "Awakened")],
                            selection: $pageKind)
            }
            BarWallet(wallet: store.player.wallet, shows: [.divinity])
        } content: {
            if let family, let entry {
                page(family: family, entry: entry, book: book)
            } else {
                EmptyState(icon: "book.closed", title: "Not in the Codex", message: "This form has no page yet.")
            }
        }
        .onChange(of: pageKind) { _, _ in pickedSkill = 0 }
    }

    /// "Egyptian · The Duat": whose the family is, and where it lives.
    private func realmLine(_ family: CodexFamily) -> String {
        "\(family.pantheon.displayName) · \(family.pantheon.realmName)"
    }

    /// The strip's element tiles: a tap moves the page to that element; the
    /// lit tile's second tap, which the filter reads as "none", is ignored.
    private var elementChoice: Binding<Element?> {
        Binding(
            get: { pageElement },
            set: { chosen in
                guard let chosen else { return }
                pageElement = chosen
                pickedSkill = 0
            }
        )
    }

    // MARK: - The page

    private func page(family: CodexFamily, entry: CodexEntry, book: CodexLedger) -> some View {
        ZStack(alignment: .topLeading) {
            PlaceBackdrop(
                painting: CodexArt.painting(for: family.pantheon),
                focus: CodexArt.focus(for: family.pantheon),
                wash: CodexArt.wash(for: family.pantheon)
            )
            HStack(alignment: .top, spacing: 10) {
                cardPlate(entry: entry, book: book)
                    .frame(width: Self.cardColumn)
                skillPlate(entry: entry)
                    .frame(maxWidth: .infinity)
                sourcePlate(entry: entry)
                    .frame(width: Self.sourceColumn)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay(alignment: .bottom) {
            if !pageReceipt.isEmpty {
                GrantReceipt(title: "Recorded", grants: pageReceipt, onGlass: true)
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: - The card and its reward

    private func cardPlate(entry: CodexEntry, book: CodexLedger) -> some View {
        let standing = book.standing(entry)
        let payout = CodexService.reward(for: entry, ledger: book)
        return VStack(spacing: 6) {
            CodexCard(entry: entry, standing: standing, size: Self.cardSize)
            Text(CodexService.formName(for: entry))
                .font(Theme.body(12).weight(.bold))
                .foregroundStyle(Theme.onGlass)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            GlassSectionHeader(title: "Record", accessory: standingWord(standing),
                               accessoryTint: standing == .ready ? Theme.onGlassGold : Theme.onGlassDim)
            HStack(spacing: 8) {
                RewardTile(key: "divinity", amount: "+\(payout.entry)", size: 40, showsTitle: false, onGlass: true)
                if payout.familyFirst > 0 {
                    RewardTile(key: "divinity", amount: "+\(payout.familyFirst)", size: 40, showsTitle: false, onGlass: true)
                }
                Spacer(minLength: 0)
            }
            Text(rewardLine(entry, payout: payout))
                .font(Theme.body(11))
                .foregroundStyle(Theme.onGlassDim)
                .lineLimit(1)
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
            ClaimPlate(status: claimStatus(standing), title: standing == .unrecorded ? "Not recorded" : "Claim",
                       onGlass: true) {
                claim(entry)
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(GlassPlate(radius: Theme.tightCorner + 4, opacity: 0.74))
    }

    private func standingWord(_ standing: CodexStanding) -> String {
        switch standing {
        case .unrecorded: return "Not yet"
        case .ready: return "Waiting"
        case .claimed: return "Taken"
        }
    }

    private func claimStatus(_ standing: CodexStanding) -> ClaimStatus {
        switch standing {
        case .unrecorded: return .waiting
        case .ready: return .ready
        case .claimed: return .done
        }
    }

    /// What the tiles above it are for: "+10 the form · +20 new family".
    /// At its widest — a 5★ Umbra face, "+80 awakened ×2 · +50 new family"
    /// — 171 points of Manrope at 11 in the plate's 180.
    private func rewardLine(_ entry: CodexEntry, payout: CodexReward) -> String {
        let face = entry.kind == .awakened ? "awakened" : "the form"
        let premium = entry.element.isLightOrDark ? " ×2" : ""
        guard payout.familyFirst > 0 else { return "+\(payout.entry) \(face)\(premium)" }
        return "+\(payout.entry) \(face)\(premium) · +\(payout.familyFirst) new family"
    }

    private func claim(_ entry: CodexEntry) {
        guard let paid = store.claimCodexEntry(entry.id), !paid.isEmpty else { return }
        let id = UUID()
        withAnimation(.easeOut(duration: 0.2)) {
            pageReceipt = CodexService.merged(paid)
            pageReceiptID = id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            guard pageReceiptID == id else { return }
            withAnimation(.easeIn(duration: 0.25)) { pageReceipt = [] }
        }
    }

    // MARK: - The skills and the lore

    private func skillPlate(entry: CodexEntry) -> some View {
        let preview = CodexArt.preview(entry)
        let skills = preview?.skills ?? []
        let ranged = !(entry.blueprint?.model.melee ?? true)
        let icons = SkillArt.keys(for: skills, element: entry.element, ranged: ranged)
        let leader = entry.blueprint?.leaderSkill
        let chosen = min(max(0, pickedSkill), max(0, skills.count - 1))
        // 38 while four tiles or fewer share the row, 34 for five (an
        // awakened face's four skills and the crown: 5 × 40 + 4 × 6 = 224 of
        // the 246 the plate has inside on an iPhone 16, 262 on a 16 Pro), 30
        // past that, so a longer kit never runs out of the plate.
        let tiles = skills.count + (leader == nil ? 0 : 1)
        let icon: CGFloat = tiles > 5 ? 30 : (tiles == 5 ? 34 : Self.skillIcon)
        return VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader(title: "Skills", accessory: roleLine(entry))
            HStack(spacing: 6) {
                ForEach(skills.indices, id: \.self) { slot in
                    Button {
                        Juice.haptic(.light)
                        pickedSkill = slot
                    } label: {
                        skillTile(skills[slot], key: slot < icons.count ? icons[slot] : nil,
                                  element: entry.element, ranged: ranged, icon: icon,
                                  selected: pickedSkill != Self.leaderSlot && slot == chosen)
                    }
                    .buttonStyle(PlateButtonStyle())
                    .accessibilityLabel(skills[slot].name)
                }
                if leader != nil {
                    Button {
                        Juice.haptic(.light)
                        pickedSkill = Self.leaderSlot
                    } label: {
                        leaderTile(icon: icon, selected: pickedSkill == Self.leaderSlot)
                    }
                    .buttonStyle(PlateButtonStyle())
                    .accessibilityLabel("Leader skill")
                }
                Spacer(minLength: 0)
            }
            RestingList(onGlass: true) {
                VStack(alignment: .leading, spacing: 8) {
                    if pickedSkill == Self.leaderSlot, let leader {
                        leaderWords(leader)
                            .restingRow()
                    } else if skills.indices.contains(chosen) {
                        skillWords(skills[chosen])
                            .restingRow()
                    }
                    GlassSectionHeader(title: "Lore")
                        .padding(.top, 4)
                        .restingRow(goneBelow: 0.9, wholeFrom: 0.99)
                    Text(entry.blueprint?.lore ?? "")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.onGlassDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, RowRest.footFade + 4)
            }
            .id("\(entry.id)_\(pickedSkill)")
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(GlassPlate(radius: Theme.tightCorner + 4, opacity: 0.74))
    }

    /// "4★ God · Attacker".
    private func roleLine(_ entry: CodexEntry) -> String {
        guard let blueprint = entry.blueprint else { return "\(entry.stars)★" }
        return "\(entry.stars)★ \(blueprint.archetype.displayName) · \(blueprint.role.displayName)"
    }

    /// A skill's painted icon in its dark socket, in a plate rimmed gold when
    /// its words are the ones shown — the unit sheet's tile, on glass.
    private func skillTile(_ skill: Skill, key: String?, element: Element, ranged: Bool,
                           icon: CGFloat, selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
        return SkillIcon(skill: skill, element: element, ranged: ranged, resolvedKey: key,
                         size: icon, socket: true)
            .padding(3)
            .background(shape.fill(selected ? Color.white.opacity(0.14) : Color.black.opacity(0.25)))
            .overlay(shape.strokeBorder(selected ? Theme.gold : Theme.glassRim.opacity(0.5),
                                        lineWidth: selected ? 1.5 : 1))
    }

    /// The leader skill's tile: the gold crown in the skills' socket.
    private func leaderTile(icon: CGFloat, selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
        let socket = RoundedRectangle(cornerRadius: icon * 0.22, style: .continuous)
        return ZStack {
            socket.fill(Theme.socketFill)
            socket.strokeBorder(Theme.goldDeep.opacity(0.85), lineWidth: 1)
            Image(systemName: "crown.fill")
                .font(.system(size: icon * 0.44, weight: .black))
                .foregroundStyle(Theme.goldText)
                .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
        }
        .frame(width: icon, height: icon)
        .padding(3)
        .background(shape.fill(selected ? Color.white.opacity(0.14) : Color.black.opacity(0.25)))
        .overlay(shape.strokeBorder(selected ? Theme.gold : Theme.glassRim.opacity(0.5),
                                    lineWidth: selected ? 1.5 : 1))
    }

    /// The chosen skill: its name, PASSIVE or its cooldown, and what it does.
    private func skillWords(_ skill: Skill) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(skill.name)
                .font(Theme.body(12).weight(.bold))
                .foregroundStyle(Theme.onGlass)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if skill.isPassive {
                    Text("PASSIVE")
                        .font(Theme.body(11).weight(.black))
                        .foregroundStyle(Theme.onGlassGold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Theme.gold.opacity(0.25)))
                        .fixedSize()
                }
                if skill.cooldown > 0 {
                    Label("\(skill.cooldown) turns", systemImage: "clock.fill")
                        .font(Theme.numeric(11.5))
                        .foregroundStyle(Theme.onGlassDim)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            Text(skill.description)
                .font(Theme.body(12))
                .foregroundStyle(Theme.onGlassDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The leader skill's words, as the unit sheet says them.
    private func leaderWords(_ leader: LeaderSkill) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.onGlassGold)
                Text("Leader skill")
                    .font(Theme.body(12).weight(.bold))
                    .foregroundStyle(Theme.onGlass)
                    .lineLimit(1)
            }
            Text(leader.description)
                .font(Theme.body(12))
                .foregroundStyle(Theme.onGlassDim)
                .fixedSize(horizontal: false, vertical: true)
            Text("When this unit leads: the first of the team.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.onGlassEyebrow)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Where to get it

    private func sourcePlate(entry: CodexEntry) -> some View {
        let roads = CodexService.sources(for: entry, player: store.player)
        return VStack(alignment: .leading, spacing: 8) {
            GlassSectionHeader(title: "Where to get it")
            if roads.isEmpty {
                Text("No road leads to this form yet.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.onGlassDim)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            } else {
                RestingList(onGlass: true) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(roads) { road in
                            CodexSourceRow(source: road)
                                .restingRow()
                        }
                    }
                    .padding(.bottom, RowRest.footFade + 4)
                }
                .id(entry.id)
            }
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(GlassPlate(radius: Theme.tightCorner + 4, opacity: 0.74))
    }
}
