import SwiftUI

/// The boon's colour on every screen: a Bane or a Ward in its element, the
/// seven of no colour in gold.
extension BoonKind {
    var tint: Color { element?.color ?? Theme.gold }
}

/// A pointy-top hexagon — the relic ring's own shape — for the socket at
/// its centre and for the boon cards.
struct BoonHexagon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for index in 0..<6 {
            let angle = (Double(index) * 60 - 90) * Double.pi / 180
            let point = CGPoint(x: centre.x + CGFloat(cos(angle)) * radius, y: centre.y + CGFloat(sin(angle)) * radius)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// The boons: the caches not yet opened, the boons owned, and the socket
/// they go in (`Docs/PLAN.md`, *Boons — the earned socket*). Opened from the
/// centre of a unit's relic ring — with `unitID`, so Equip is offered — and
/// from the relic inventory's menu without one, as the list. The left is the
/// list, caches first and then the boons best-fit-first for the unit's role;
/// the right is the one panel: a cache's THREE DOORS, or a boon's card with
/// its line, its pushes, the push's choice of two, and what to do with it.
struct BoonPickerView: View {
    var unitID: UUID? = nil
    /// Opens on the first cache's three doors: the CI tour's `boons` step.
    var openingCache: Bool = false

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var pickedID: UUID?
    @State private var showSellConfirm = false
    @State private var showSources = false
    @State private var glow = false

    private var unit: ResolvedUnit? { unitID.flatMap { store.resolved($0) } }
    private var role: CombatRole { unit?.role ?? .attacker }
    private var caches: [BoonCache] { store.player.boonCaches ?? [] }
    private var boons: [Boon] {
        (store.player.boons ?? []).sorted { BoonService.fit($0, for: role) > BoonService.fit($1, for: role) }
    }
    private var pickedCache: BoonCache? { caches.first(where: { $0.id == pickedID }) }
    /// The boon in the panel: the one tapped, else the best fit, unless a
    /// cache is what was tapped.
    private var pickedBoon: Boon? {
        if let boon = boons.first(where: { $0.id == pickedID }) { return boon }
        return pickedCache == nil ? boons.first : nil
    }

    /// What the panel's last row clears at its foot: the marble's lower
    /// acanthus reaches about 17 points up (measured on the cream unit
    /// sheet, whose inset for it went with that sheet on 2026-09-24). This
    /// padding is inside the scroll, so when the three doors run a point or
    /// two past the plate the overflow comes off it: 20, and the last door
    /// still clears the scrolls by the 18 that sheet kept.
    private static let panelFoot: CGFloat = 20

    private static let sources = "Caches fall from a Titan at S or better (one kill in four, a 6★), the Labyrinth's "
        + "tenth level (one run in ten, a 5★), the Tower's 25th, 50th, 75th and 100th floors, and a realm's "
        + "Judgment on Hell. The Halls never."

    var body: some View {
        NavigationStack {
            GameScreen(
                "Boons",
                subtitle: unit.map { "The socket of \($0.name)" } ?? "\(boons.count) boons · \(caches.count) caches",
                dismiss: { dismiss() }
            ) {
                BarButton(
                    title: "Sources",
                    systemImage: "map.fill",
                    tint: showSources ? Theme.gold : Theme.textSecondary
                ) {
                    showSources.toggle()
                }
                if let unit, unit.boon != nil {
                    BarButton(title: "Unequip", systemImage: "minus.circle", tint: Theme.textSecondary) {
                        store.unequipBoon(from: unit.id)
                    }
                }
            } content: {
                HStack(alignment: .top, spacing: 8) {
                    list
                        .frame(maxWidth: .infinity)
                    panel
                        .frame(width: 300)
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.vertical, 6)
            }
            .confirmationDialog(
                "Sell \(pickedBoon?.displayName ?? "this boon") for \(pickedBoon.map { BoonService.sellValue($0) } ?? 0) drachma?",
                isPresented: $showSellConfirm,
                titleVisibility: .visible
            ) {
                Button("Sell", role: .destructive) {
                    if let boon = pickedBoon, store.sellBoons([boon.id]) != nil {
                        AudioLibrary.shared.play(.uiConfirm)
                        pickedID = nil
                    }
                }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("A socketed boon comes out of its socket first. A locked boon is never sold.")
            }
            .onAppear {
                if openingCache, let first = caches.first { pickedID = first.id }
            }
        }
    }

    // MARK: - The list

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if showSources {
                    Text(Self.sources)
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.surfaceRaised))
                }
                if caches.isEmpty && boons.isEmpty {
                    EmptyState(icon: "seal", title: "No boons yet", message: Self.sources)
                }
                ForEach(caches) { cache in
                    cacheRow(cache)
                }
                ForEach(boons) { boon in
                    boonRow(boon)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func rowBackground(picked: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(picked ? Theme.surfaceHigh : Theme.surfaceRaised)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(picked ? Theme.gold : Theme.stroke.opacity(0.6), lineWidth: picked ? 1.5 : 0.5)
            )
    }

    private func cacheRow(_ cache: BoonCache) -> some View {
        let picked = pickedID == cache.id
        return Button {
            Juice.haptic(.light)
            pickedID = cache.id
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    BoonHexagon()
                        .fill(Theme.gold.opacity(0.18))
                        .frame(width: 44, height: 44)
                    BoonHexagon()
                        .stroke(Theme.gold, lineWidth: 1)
                        .frame(width: 44, height: 44)
                    Image(systemName: "seal.fill")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(Theme.gold)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(cache.displayName)
                        .font(Theme.body(12).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Shut · three boons inside, take one")
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                    StarRow(stars: cache.grade, size: 7)
                }
                Spacer(minLength: 0)
                if !cache.source.isEmpty {
                    Text(cache.source.uppercased())
                        .font(Theme.body(9).weight(.black))
                        .tracking(0.8)
                        .foregroundStyle(Theme.goldDim)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(picked: picked))
        }
        // A row of the scrolling list: quiet, its tick kept (2026-09-24).
        .buttonStyle(GamePressStyle(.quiet))
    }

    private func boonRow(_ boon: Boon) -> some View {
        let picked = pickedID == boon.id || (pickedID == nil && pickedBoon?.id == boon.id)
        let wearer = boon.equippedBy.flatMap { store.resolved($0)?.name }
        return Button {
            Juice.haptic(.light)
            pickedID = boon.id
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    BoonHexagon()
                        .fill(boon.kind.tint.opacity(0.2))
                        .frame(width: 44, height: 44)
                    BoonHexagon()
                        .stroke(Theme.gold.opacity(0.8), lineWidth: 1)
                        .frame(width: 44, height: 44)
                    Image(systemName: boon.kind.glyph)
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(boon.kind.tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(boon.displayName)
                            .font(Theme.body(12).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                        if boon.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9, weight: .black))
                                .foregroundStyle(Theme.gold)
                        }
                    }
                    Text(boon.shortLine)
                        .font(Theme.numeric(11))
                        .foregroundStyle(Theme.gold)
                    HStack(spacing: 6) {
                        StarRow(stars: boon.grade, size: 7)
                        Text("pushed \(boon.pushes)/\(BoonService.maxPushes)")
                            .font(Theme.body(9))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if let wearer {
                    Text(wearer)
                        .font(Theme.body(9).weight(.bold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground(picked: picked))
        }
        .buttonStyle(GamePressStyle(.quiet))
    }

    // MARK: - The panel

    /// The panel's words scroll inside the plate, so the plate is never
    /// taller than the frame: as a fixed stack, the three doors at the type
    /// floors were taller than the frame, and the overflow pushed the whole
    /// screen up — the back medallion cut by the top edge, the doors' foot
    /// under the home indicator (run 217). A panel that fits never bounces.
    ///
    /// Its foot clears the marble's lower acanthus (`panelFoot`): the last
    /// door runs the panel's width, and at the plain inset its bottom
    /// corners met the scrolls (runs 223 and 224, 41-boons).
    private var panel: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                if let cache = pickedCache {
                    cachePanel(cache)
                } else if let boon = pickedBoon {
                    boonPanel(boon)
                } else {
                    EmptyState(icon: "seal", title: "Nothing picked", message: "Pick a boon or a cache on the left.")
                }
            }
            .padding(.horizontal, Theme.panelInset)
            .padding(.top, Theme.panelInset)
            .padding(.bottom, Self.panelFoot)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .panelBackground(radius: Theme.tightCorner)
    }

    /// A cache's three doors: the kind is the player's; the size rolls once
    /// he has chosen. Each door prints the range its roll can land in.
    private func cachePanel(_ cache: BoonCache) -> some View {
        let doors = BoonService.offers(for: cache)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "seal.fill")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Theme.gold)
                Text("THREE DOORS")
                    .font(Theme.title(12))
                    .tracking(1.2)
                    .foregroundStyle(Theme.goldDeep)
                Spacer(minLength: 0)
                StarRow(stars: cache.grade, size: 8)
            }
            // One line, so the three doors fit the plate whole; the push is
            // explained on the boon's own card, where it is bought.
            Text("Pick one; its size rolls when you choose.")
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(doors.enumerated()), id: \.offset) { index, kind in
                doorCard(kind, grade: cache.grade) {
                    openDoor(cache, choice: index)
                }
            }
        }
    }

    private func doorCard(_ kind: BoonKind, grade: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    BoonHexagon()
                        .fill(kind.tint.opacity(0.2))
                        .frame(width: 40, height: 40)
                    BoonHexagon()
                        .stroke(Theme.gold.opacity(0.8), lineWidth: 1)
                        .frame(width: 40, height: 40)
                    Image(systemName: kind.glyph)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(kind.tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.displayName)
                        .font(Theme.body(12).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(kind.line(over: BoonService.rollSpan(kind, grade: grade)))
                        .font(Theme.body(10))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(kind.family.hook.displayName)
                        .font(Theme.body(9).weight(.bold))
                        .foregroundStyle(Theme.goldDim)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Theme.gold)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.gold.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(GamePressStyle(.plate))
    }

    /// The door's press ticked on touch-down; the confirm is the "done".
    private func openDoor(_ cache: BoonCache, choice: Int) {
        guard let boon = store.openBoonCache(cache.id, choice: choice) else { return }
        AudioLibrary.shared.play(.uiConfirm)
        pickedID = boon.id
        flare()
    }

    /// A boon's card: the line, the pushes, the push or its choice of two,
    /// and Equip, Lock and Sell.
    private func boonPanel(_ boon: Boon) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    BoonHexagon()
                        .fill(boon.kind.tint.opacity(0.2))
                        .frame(width: 56, height: 56)
                    BoonHexagon()
                        .stroke(Theme.gold, lineWidth: 1.5)
                        .frame(width: 56, height: 56)
                    Image(systemName: boon.kind.glyph)
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(boon.kind.tint)
                }
                .scaleEffect(glow ? 1.1 : 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(boon.displayName.uppercased())
                        .font(Theme.title(13))
                        .tracking(0.8)
                        .foregroundStyle(Theme.goldDeep)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    StarRow(stars: boon.grade, size: 8)
                    Text(boon.kind.family.hook.displayName)
                        .font(Theme.body(9))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            Text(boon.line)
                .font(Theme.body(11).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            pushTrack(boon)
            if let wearer = boon.equippedBy {
                Text("In the socket of \(store.resolved(wearer)?.name ?? "a unit")")
                    .font(Theme.body(10).weight(.bold))
                    .foregroundStyle(Theme.gold)
            }
            if boon.hasPendingRoll {
                pushChoice(boon)
            } else {
                pushButton(boon)
            }
            actionRow(boon)
        }
    }

    /// Five pips, and the roll against the grade's base.
    private func pushTrack(_ boon: Boon) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<BoonService.maxPushes, id: \.self) { index in
                Circle()
                    .fill(index < boon.pushes ? Theme.gold : Theme.stroke.opacity(0.5))
                    .frame(width: 9, height: 9)
            }
            Text("Pushed \(boon.pushes) of \(BoonService.maxPushes)")
                .font(Theme.body(10).weight(.bold))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            Text(String(format: "%.2f× the base", boon.quality))
                .font(Theme.numeric(10))
                .foregroundStyle(Theme.gold)
        }
    }

    private func pushChoice(_ boon: Boon) -> some View {
        let offers = BoonService.pushCandidates(for: boon)
        let unitSuffix = boon.kind.family == .swiftFooted ? "" : "%"
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Theme.gold)
                Text("CHOOSE YOUR PUSH")
                    .font(Theme.title(12))
                    .tracking(1.2)
                    .foregroundStyle(Theme.goldDeep)
                Spacer(minLength: 0)
            }
            Text("The push is paid. Take either bump; the floor never drops.")
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(offers) { offer in
                Button {
                    takePush(boon, offer)
                } label: {
                    HStack(spacing: 8) {
                        Text("+\(BoonKind.percent(offer.bump))\(unitSuffix)")
                            .font(Theme.numeric(13).weight(.bold))
                            .foregroundStyle(Theme.gold)
                        Text("→ \(boon.kind.shortLine(offer.after))")
                            .font(Theme.numeric(11))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, 9)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.surfaceRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Theme.goldDim.opacity(0.6), lineWidth: 0.5)
                    )
                }
                .buttonStyle(GamePressStyle(.plate))
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(Theme.surfaceHigh)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .strokeBorder(Theme.gold, lineWidth: 1.5)
        )
    }

    private func pushButton(_ boon: Boon) -> some View {
        let cost = BoonService.pushCost(for: boon)
        let held = Aether.count(cost.aetherID, player: store.player)
        let refusal = BoonService.pushError(boon, player: store.player)
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                push(boon)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 12, weight: .black))
                    Text(boon.isFullyPushed ? "Fully pushed" : "Push \(boon.pushes + 1) of \(BoonService.maxPushes)")
                        .font(Theme.body(11).weight(.bold))
                    Spacer(minLength: 4)
                    Text("\(cost.drachma.formatted()) drachma · \(cost.aether) \(Aether.name(for: cost.aetherID))")
                        .font(Theme.numeric(10))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(refusal == nil ? Theme.ink : Theme.textSecondary)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(refusal == nil ? Theme.gold : Theme.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.goldDim.opacity(0.7), lineWidth: 1)
                )
            }
            .buttonStyle(GamePressStyle(.primary, dimsWhenDisabled: true))
            .disabled(refusal != nil)
            Text(refusal?.errorDescription
                 ?? "You hold \(store.player.wallet.drachma.formatted()) drachma and \(held) \(Aether.name(for: cost.aetherID)).")
                .font(Theme.body(9))
                .foregroundStyle(refusal == nil ? Theme.textSecondary : Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The push and its choice: each press ticked on touch-down, so the
    /// confirm alone says it took.
    private func push(_ boon: Boon) {
        guard store.pushBoon(boon.id) != nil else { return }
        AudioLibrary.shared.play(.uiConfirm)
    }

    private func takePush(_ boon: Boon, _ offer: BoonService.PushCandidate) {
        guard store.takeBoonPush(boon.id, candidate: offer.id) != nil else { return }
        AudioLibrary.shared.play(.uiConfirm)
        flare()
    }

    private func flare() {
        withAnimation(.easeOut(duration: 0.25)) { glow = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.4)) { glow = false }
        }
    }

    private func actionRow(_ boon: Boon) -> some View {
        HStack(spacing: 6) {
            if let unit {
                if boon.equippedBy == unit.id {
                    actionButton("Unequip", "minus.circle", tint: Theme.textSecondary) {
                        store.unequipBoon(from: unit.id)
                    }
                } else {
                    actionButton("Equip on \(unit.name)", "checkmark.circle.fill", tint: Theme.gold) {
                        store.equipBoon(boon.id, on: unit.id)
                        AudioLibrary.shared.play(.uiConfirm)
                    }
                }
            }
            actionButton(
                boon.isLocked ? "Unlock" : "Lock",
                boon.isLocked ? "lock.fill" : "lock.open",
                tint: boon.isLocked ? Theme.gold : Theme.textSecondary
            ) {
                store.toggleBoonLock(boon.id)
            }
            actionButton("Sell \(BoonService.sellValue(boon).formatted())", "cart.fill", tint: Theme.danger) {
                showSellConfirm = true
            }
            .disabled(boon.isLocked)
        }
    }

    private func actionButton(_ title: String, _ symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .black))
                Text(title)
                    .font(Theme.body(10).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Theme.surface))
            .overlay(Capsule().strokeBorder(tint.opacity(0.4), lineWidth: 1))
        }
        // Sell is disabled on a locked boon: half strength, as `.plain` drew it.
        .buttonStyle(GamePressStyle(.plate, dimsWhenDisabled: true))
    }
}
