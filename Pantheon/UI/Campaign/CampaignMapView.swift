import SwiftUI

/// The world: one card per realm with its chapters. A shut chapter says which
/// boss shuts it. Tapping an open chapter opens its map.
struct WorldMapView: View {
    @EnvironmentObject private var store: GameStore
    let onOpen: (Chapter) -> Void

    private struct Realm: Identifiable {
        let pantheon: Pantheon
        let chapters: [Chapter]
        var id: String { pantheon.rawValue }
    }

    private var realms: [Realm] {
        Pantheon.live.map { pantheon in
            Realm(pantheon: pantheon, chapters: StageDatabase.chapters.filter { $0.pantheon == pantheon })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if BundleImage.exists("world_map") {
                BundleImage(name: "world_map")
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 150)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            }
            ForEach(realms) { realm in
                realmCard(realm)
            }
        }
    }

    private func realmCard(_ realm: Realm) -> some View {
        let scene = realm.chapters.first?.stages.first?.environment.sceneName ?? ""
        let cleared = realm.chapters.reduce(0) { $0 + (store.player.campaignProgress[$1.id] ?? 0) }
        let total = realm.chapters.reduce(0) { $0 + $1.stages.count }
        return VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                if BundleImage.exists("\(scene)_bg") {
                    BundleImage(name: "\(scene)_bg")
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 88)
                        .frame(maxWidth: .infinity)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(realm.pantheon.color.opacity(0.3))
                        .frame(height: 88)
                }
                LinearGradient(colors: [.clear, Theme.ink.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text(realm.pantheon.displayName.uppercased())
                        .font(Theme.body(10).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(realm.pantheon.color)
                    Text(realm.pantheon.realmName)
                        .font(Theme.title(22))
                        .foregroundStyle(Theme.textPrimary)
                }
                .padding(12)
            }
            .allowsHitTesting(false)
            .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                Text("\(cleared)/\(total)")
                    .font(Theme.numeric(12))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(10)
            }

            ForEach(realm.chapters) { chapter in
                chapterRow(chapter)
            }
        }
        .padding(12)
        .panelBackground()
    }

    private func chapterRow(_ chapter: Chapter) -> some View {
        let player = store.player
        let cleared = player.campaignProgress[chapter.id] ?? 0
        let finished = cleared >= chapter.stages.count
        let unlocked = chapter.stages.first.map { CampaignService.isUnlocked($0, player: player) } ?? false
        return Button {
            if unlocked { onOpen(chapter) }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(finished ? Theme.gold.opacity(0.25) : Theme.surface)
                    Image(systemName: unlocked ? (finished ? "checkmark" : "map.fill") : "lock.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(unlocked ? Theme.gold : Theme.textSecondary)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(chapter.name)
                        .font(Theme.body(14).weight(.semibold))
                        .foregroundStyle(unlocked ? Theme.textPrimary : Theme.textSecondary)
                    if unlocked {
                        StatBar(
                            value: Double(cleared),
                            maximum: Double(chapter.stages.count),
                            tint: chapter.pantheon.color,
                            height: 4
                        )
                        .frame(width: 150)
                    } else if let gate = gateText(for: chapter) {
                        Text(gate)
                            .font(Theme.body(11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                Text("\(cleared)/\(chapter.stages.count)")
                    .font(Theme.numeric(12))
                    .foregroundStyle(Theme.textSecondary)
                if unlocked {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(Theme.surface.opacity(unlocked ? 1 : 0.45))
            )
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }

    /// Why a chapter is shut: the chapter before it, whose boss must fall.
    private func gateText(for chapter: Chapter) -> String? {
        guard let index = StageDatabase.chapters.firstIndex(where: { $0.id == chapter.id }), index > 0 else { return nil }
        return "Clear \(StageDatabase.chapters[index - 1].name) first"
    }
}

/// A chapter as a map: the stage's painting, a path winding across it and a
/// medallion per stage — gold once cleared, ringed and pulsing where the
/// player stands, shut with a lock beyond. The boss is the last and largest.
struct ChapterMapView: View {
    @EnvironmentObject private var store: GameStore
    let chapterID: String
    let onSelect: (Stage) -> Void

    @State private var pulse = false

    private var chapter: Chapter? { StageDatabase.chapter(chapterID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let chapter {
                    map(chapter)
                    header(chapter)
                    legend
                    stageRows(chapter)
                }
            }
            .padding(12)
        }
        .screen(chapter?.name ?? "Chapter")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                WalletBar(wallet: store.player.wallet)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // MARK: - Header

    private func header(_ chapter: Chapter) -> some View {
        let player = store.player
        let cleared = player.campaignProgress[chapter.id] ?? 0
        let next = chapter.stages.first(where: { CampaignService.isUnlocked($0, player: player) && !CampaignService.isCleared($0, player: player) })
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(chapter.realmName.uppercased())
                        .font(Theme.body(10).weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(chapter.pantheon.color)
                    Text(chapter.name)
                        .font(Theme.title(20))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Text("\(cleared)/\(chapter.stages.count)")
                    .font(Theme.numeric(13))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(chapter.summary)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            StatBar(
                value: Double(cleared),
                maximum: Double(chapter.stages.count),
                tint: chapter.pantheon.color,
                height: 5
            )
            if let next {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(Theme.gold)
                    Text("Next: \(next.name)")
                        .font(Theme.body(12).weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("· Power \(next.recommendedPower)")
                        .font(Theme.numeric(11))
                        .foregroundStyle(store.totalPower >= next.recommendedPower ? Theme.success : Theme.danger)
                }
            } else {
                Label("Chapter cleared", systemImage: "checkmark.seal.fill")
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(Theme.gold)
            }
        }
        .padding(12)
        .panelBackground()
    }

    // MARK: - The map

    private func map(_ chapter: Chapter) -> some View {
        let player = store.player
        let scene = chapter.stages.first?.environment.sceneName ?? ""
        return GeometryReader { geometry in
            let size = geometry.size
            let points = Self.nodePoints(count: chapter.stages.count, in: size)
            ZStack(alignment: .topLeading) {
                if BundleImage.exists("\(scene)_bg") {
                    BundleImage(name: "\(scene)_bg")
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                        .allowsHitTesting(false)
                } else {
                    Rectangle()
                        .fill(chapter.pantheon.color.opacity(0.25))
                        .frame(width: size.width, height: size.height)
                }
                Rectangle()
                    .fill(Theme.ink.opacity(0.3))
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)

                // The road: a dotted curve through the medallions.
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    if points.count > 1 {
                        for index in 1..<points.count {
                            let previous = points[index - 1]
                            let next = points[index]
                            let middle = (previous.x + next.x) / 2
                            path.addCurve(
                                to: next,
                                control1: CGPoint(x: middle, y: previous.y),
                                control2: CGPoint(x: middle, y: next.y)
                            )
                        }
                    }
                }
                .stroke(Theme.textPrimary.opacity(0.6), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [2, 8]))
                .allowsHitTesting(false)

                ForEach(Array(chapter.stages.enumerated()), id: \.element.id) { index, stage in
                    let unlocked = CampaignService.isUnlocked(stage, player: player)
                    let cleared = CampaignService.isCleared(stage, player: player)
                    node(stage, unlocked: unlocked, cleared: cleared, current: unlocked && !cleared)
                        .position(points[index])
                }
            }
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }

    /// Where the medallions sit: spread across the width, wandering up and
    /// down so the road reads as a road.
    static func nodePoints(count: Int, in size: CGSize) -> [CGPoint] {
        guard count > 0 else { return [] }
        let inset: CGFloat = 48
        let usable = max(0, size.width - inset * 2)
        return (0..<count).map { index in
            let t = count == 1 ? 0.5 : CGFloat(index) / CGFloat(count - 1)
            let wave = sin(CGFloat(index) * 1.25 + 0.6)
            return CGPoint(x: inset + usable * t, y: size.height * 0.5 + wave * size.height * 0.2)
        }
    }

    private func node(_ stage: Stage, unlocked: Bool, cleared: Bool, current: Bool) -> some View {
        let diameter: CGFloat = stage.isBoss ? 56 : 44
        return Button {
            if unlocked { onSelect(stage) }
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    if current {
                        Circle()
                            .fill(Theme.gold.opacity(pulse ? 0.35 : 0.1))
                            .frame(width: diameter + 22, height: diameter + 22)
                    }
                    Circle()
                        .fill(cleared ? Theme.gold : (unlocked ? Theme.surfaceHigh : Theme.surface.opacity(0.7)))
                        .frame(width: diameter, height: diameter)
                        .overlay(
                            Circle().strokeBorder(
                                cleared ? Theme.goldDeep : (current ? Theme.gold : Theme.stroke),
                                lineWidth: current ? 2.5 : 1.5
                            )
                        )
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
                    if cleared {
                        Image(systemName: "checkmark")
                            .font(.system(size: 16, weight: .black))
                            .foregroundStyle(Theme.ink)
                    } else if !unlocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                    } else if stage.isBoss {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.danger)
                    } else {
                        Text("\(stage.index)")
                            .font(Theme.numeric(15).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                HStack(spacing: 2) {
                    if stage.isBoss {
                        Text("BOSS")
                    } else {
                        Image(systemName: "bolt.fill")
                        Text("\(stage.energyCost)")
                    }
                }
                .font(Theme.body(9).weight(.black))
                .foregroundStyle(stage.isBoss ? Theme.danger : Theme.info)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.ink.opacity(0.75)))
            }
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }

    private var legend: some View {
        HStack(spacing: 10) {
            legendItem(color: Theme.gold, text: "cleared")
            legendItem(color: Theme.surfaceHigh, text: "next, tap to fight")
            legendItem(color: Theme.surface, text: "shut until the one before falls")
            Spacer()
        }
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 10, height: 10)
                .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            Text(text)
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: - The list under the map

    private func stageRows(_ chapter: Chapter) -> some View {
        let player = store.player
        return VStack(spacing: 6) {
            ForEach(chapter.stages) { stage in
                let unlocked = CampaignService.isUnlocked(stage, player: player)
                let cleared = CampaignService.isCleared(stage, player: player)
                Button {
                    if unlocked { onSelect(stage) }
                } label: {
                    HStack(spacing: 10) {
                        Text("\(stage.index)")
                            .font(Theme.numeric(12).weight(.bold))
                            .foregroundStyle(cleared ? Theme.gold : (unlocked ? Theme.textPrimary : Theme.textSecondary))
                            .frame(width: 22)
                        Text(stage.name)
                            .font(Theme.body(13).weight(.semibold))
                            .foregroundStyle(unlocked ? Theme.textPrimary : Theme.textSecondary)
                        if stage.isBoss {
                            Text("BOSS")
                                .font(Theme.body(8).weight(.black))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Theme.danger.opacity(0.25)))
                                .foregroundStyle(Theme.danger)
                        }
                        Spacer()
                        Text("Power \(stage.recommendedPower)")
                            .font(Theme.numeric(10))
                            .foregroundStyle(store.totalPower >= stage.recommendedPower ? Theme.success : Theme.danger)
                        Image(systemName: cleared ? "checkmark.seal.fill" : (unlocked ? "chevron.right" : "lock.fill"))
                            .font(.system(size: 11))
                            .foregroundStyle(cleared ? Theme.gold : Theme.textSecondary)
                    }
                    .padding(9)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                            .fill(Theme.surface.opacity(unlocked ? 1 : 0.4))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!unlocked)
            }
        }
    }
}
