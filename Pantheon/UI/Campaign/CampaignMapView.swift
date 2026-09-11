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
        let backdrop = realm.chapters.first?.stages.first?.environment.backdropName ?? ""
        let cleared = realm.chapters.reduce(0) { $0 + (store.player.campaignProgress[$1.id] ?? 0) }
        let total = realm.chapters.reduce(0) { $0 + $1.stages.count }
        return VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                if BundleImage.exists(backdrop) {
                    BundleImage(name: backdrop)
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
    /// Which tier of the chapter the road shows. Owned by the campaign
    /// screen so it survives a change of chapter.
    @Binding var difficulty: CampaignDifficulty
    let onSelect: (Stage) -> Void

    @State private var pulse = false

    private var chapter: Chapter? { StageDatabase.chapter(chapterID)?.at(difficulty) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let base = StageDatabase.chapter(chapterID) {
                tierChips(base)
            }
            if let chapter {
                map(chapter)
                header(chapter)
                stageRows(chapter)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // MARK: - The tiers

    /// Normal, Hard, Hell as three chips, the genre's way: the tier being
    /// shown is filled in its own colour, a shut tier wears a lock and says
    /// what opens it, and a tier cleared to its boss wears a check.
    private func tierChips(_ base: Chapter) -> some View {
        let player = store.player
        return HStack(spacing: 8) {
            ForEach(CampaignDifficulty.allCases) { tier in
                let open = CampaignService.isOpen(tier, of: base, player: player)
                let cleared = (player.campaignProgress[base.id + tier.suffix] ?? 0) >= base.stages.count
                let selected = tier == difficulty
                let tint = Color(hex: tier.accentHex)
                Button {
                    guard open else { return }
                    withAnimation(.easeOut(duration: 0.2)) { difficulty = tier }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: open ? (cleared ? "checkmark.seal.fill" : tier.glyph) : "lock.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(tier.displayName.uppercased())
                            .font(Theme.body(10).weight(.black))
                            .tracking(1.2)
                    }
                    .foregroundStyle(selected ? Theme.ink : (open ? tint : Theme.textSecondary))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        Capsule().fill(selected ? tint : Theme.ink.opacity(open ? 0.55 : 0.35))
                    )
                    .overlay(
                        Capsule().strokeBorder(open ? tint.opacity(selected ? 0 : 0.7) : Theme.stroke, lineWidth: 1)
                    )
                    .opacity(open ? 1 : 0.7)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            // What the tier pays, in one line, so the reason to come back is
            // on the map and not buried in a briefing.
            Text(tierNote(difficulty, open: CampaignService.isOpen(difficulty, of: base, player: player), base: base))
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }

    private func tierNote(_ tier: CampaignDifficulty, open: Bool, base: Chapter) -> String {
        switch tier {
        case .normal:
            return "The story. Relics as the stage gives them."
        case .hard:
            return open
                ? "Enemies a grade up and ×1.2. Every stage drops a 5★ relic or better; ×1.7 drachma and EXP."
                : "Opens when \(base.name)'s boss falls on Normal."
        case .hell:
            return open
                ? "Enemies two grades up and ×1.5. Every stage drops a 6★ relic; ×2.6 drachma and EXP."
                : "Opens when \(base.name)'s boss falls on Hard."
        }
    }

    // MARK: - Header

    private func header(_ chapter: Chapter) -> some View {
        let player = store.player
        let cleared = player.campaignProgress[chapter.id] ?? 0
        let next = chapter.stages.first(where: { CampaignService.isUnlocked($0, player: player) && !CampaignService.isCleared($0, player: player) })
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(chapter.realmName.uppercased()) · \(chapter.name.uppercased())")
                        .font(Theme.body(10).weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(chapter.pantheon.color)
                    Text(chapter.summary)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Text("\(cleared)/\(chapter.stages.count)")
                    .font(Theme.numeric(13))
                    .foregroundStyle(Theme.textSecondary)
            }
            StatBar(
                value: Double(cleared),
                maximum: Double(chapter.stages.count),
                tint: chapter.pantheon.color,
                height: 4
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
        .padding(10)
        .panelBackground()
    }

    // MARK: - The map

    private func map(_ chapter: Chapter) -> some View {
        let player = store.player
        let backdrop = chapter.stages.first?.environment.backdropName ?? ""
        return GeometryReader { geometry in
            let size = geometry.size
            let points = Self.nodePoints(count: chapter.stages.count, in: size)
            ZStack(alignment: .topLeading) {
                if BundleImage.exists(backdrop) {
                    BundleImage(name: backdrop)
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
                    .fill(Theme.plate.opacity(0.3))
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
        .frame(height: 190)
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

// MARK: - The world road

/// The campaign as one painted world you travel across, the way the genre
/// does it: Egypt on the left, Greece in the middle, the Norse fjords and the
/// world tree on the right, a road running through all three, and a city on
/// the road for every chapter.
///
/// The owner asked for exactly this: "each country where the mythology took
/// place, you can have the campaigns there, like cities, and have a big
/// scrollable map that you have to progress through like Summoners War."
///
/// What was here before was a rail of eight chapter chips above one chapter's
/// stage path. That is a menu. This is a place — and the difference matters,
/// because the thing a player is meant to feel is that Yggdrasil is a long way
/// from the Duat and he walked it.
///
/// **The anchors are measured, not guessed.** `world_map.png` is 2048×1152 and
/// every city below sits on a landmark the painter actually drew: the pyramids,
/// the oasis town, the three temples, the longship harbour, the world tree, the
/// snowfield. They were checked by drawing rings at these coordinates over the
/// painting and looking at the result, the same way `Docs/ART_2D.md` §6 fixed
/// the island's landmarks. If the map is ever repainted, re-measure — do not
/// assume they carry over.
///
/// The map is taller than the frame at the zoom that makes a city tappable, so
/// it scrolls both ways, and it scrolls itself to the city the player is in
/// when it opens. `.allowsHitTesting(false)` on the painting is not optional:
/// a scaled image swallows taps far outside its visible frame, which has
/// broken three screens in this project already.
struct WorldRoadMapView: View {
    @EnvironmentObject private var store: GameStore
    /// Called with the chapter whose city was tapped.
    var onSelect: (Chapter) -> Void

    /// Where each chapter's city sits on the painting, in 0...1 of its width
    /// and height, in story order.
    static let cities: [(id: String, x: CGFloat, y: CGFloat)] = [
        ("duat_1",      0.085, 0.400),   // the pyramids
        ("duat_2",      0.205, 0.735),   // the oasis town on the delta
        ("olympus_1",   0.505, 0.430),   // the great temple
        ("olympus_2",   0.552, 0.475),   // the small temple above the olive groves
        ("olympus_3",   0.523, 0.315),   // the mountain temple
        ("yggdrasil_1", 0.733, 0.425),   // the longship harbour
        ("yggdrasil_2", 0.883, 0.120),   // the world tree
        ("yggdrasil_3", 0.845, 0.530),   // the snowfield below the peaks
    ]

    /// The painting's aspect, and how much bigger than the frame it is drawn.
    /// At 1.0 the whole world fits and a city is 20 points across, which is
    /// too small to hit; at 1.45 a city is a comfortable target and the map
    /// is worth scrolling.
    private static let aspect: CGFloat = 2048.0 / 1152.0
    private static let zoom: CGFloat = 1.45

    var body: some View {
        GeometryReader { frame in
            let mapHeight = frame.size.height * Self.zoom
            let mapWidth = mapHeight * Self.aspect
            ScrollViewReader { scroller in
                ScrollView([.horizontal, .vertical], showsIndicators: false) {
                    ZStack(alignment: .topLeading) {
                        painting(width: mapWidth, height: mapHeight)
                        road(width: mapWidth, height: mapHeight)
                        ForEach(Array(Self.cities.enumerated()), id: \.offset) { index, city in
                            if let chapter = StageDatabase.chapter(city.id) {
                                CityMedallion(
                                    chapter: chapter,
                                    order: index + 1,
                                    state: state(of: chapter),
                                    action: { onSelect(chapter) }
                                )
                                .position(x: city.x * mapWidth, y: city.y * mapHeight)
                                .id(city.id)
                            }
                        }
                    }
                    .frame(width: mapWidth, height: mapHeight)
                }
                .onAppear {
                    // Open on the city the player is in, not on the top-left
                    // corner of a map three screens wide.
                    let here = CampaignView.currentChapter(for: store.player).id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.45)) {
                            scroller.scrollTo(here, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func painting(width: CGFloat, height: CGFloat) -> some View {
        Group {
            if BundleImage.exists("world_map") {
                BundleImage(name: "world_map")
                    .aspectRatio(contentMode: .fill)
            } else {
                // Until the painting ships: sea, so the cities still read.
                LinearGradient(
                    colors: [Color(hex: "#1B3A5C"), Color(hex: "#0E2036")],
                    startPoint: .top, endPoint: .bottom
                )
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .allowsHitTesting(false)
    }

    /// The road, drawn city to city in story order. Gold behind the player,
    /// faint ahead of him, so the map itself shows how far he has come.
    private func road(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, _ in
            let points = Self.cities.map { CGPoint(x: $0.x * width, y: $0.y * height) }
            for index in 0..<max(0, points.count - 1) {
                var path = Path()
                path.move(to: points[index])
                path.addLine(to: points[index + 1])
                let travelled = StageDatabase.chapter(Self.cities[index].id).map {
                    state(of: $0) == .cleared
                } ?? false
                context.stroke(
                    path,
                    with: .color(travelled ? Color(hex: "#F5D57A").opacity(0.85) : Color.white.opacity(0.25)),
                    style: StrokeStyle(lineWidth: travelled ? 3 : 2, lineCap: .round, dash: [7, 9])
                )
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    private func state(of chapter: Chapter) -> CityState {
        let player = store.player
        let unlocked = chapter.stages.first.map { CampaignService.isUnlocked($0, player: player) } ?? false
        if !unlocked { return .locked }
        let cleared = chapter.stages.allSatisfy { CampaignService.isCleared($0, player: player) }
        return cleared ? .cleared : .open
    }
}

enum CityState {
    case locked, open, cleared
}

/// One city on the road: a medallion big enough to hit, carrying the chapter's
/// number, its name, and how much of it is done.
struct CityMedallion: View {
    @EnvironmentObject private var store: GameStore
    let chapter: Chapter
    let order: Int
    let state: CityState
    let action: () -> Void

    private var cleared: Int {
        chapter.stages.filter { CampaignService.isCleared($0, player: store.player) }.count
    }

    var body: some View {
        Button {
            guard state != .locked else { return }
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiConfirm)
            action()
        } label: {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: state == .locked
                                    ? [Color(hex: "#2A2A38"), Color(hex: "#14141C")]
                                    : [Color(hex: "#4A3A16"), Color(hex: "#1A1408")],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .frame(width: 42, height: 42)
                    Circle()
                        .strokeBorder(
                            state == .locked ? LinearGradient(colors: [Theme.stroke, Theme.stroke],
                                                              startPoint: .top, endPoint: .bottom)
                                             : Theme.goldPlate,
                            lineWidth: 2
                        )
                        .frame(width: 42, height: 42)
                    switch state {
                    case .locked:
                        Image(systemName: "lock.fill")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(Theme.textSecondary)
                    case .cleared:
                        Image(systemName: "checkmark")
                            .font(.system(size: 17, weight: .black))
                            .foregroundStyle(Theme.gold)
                    case .open:
                        Text("\(order)")
                            .font(Theme.numeric(16))
                            .foregroundStyle(Theme.gold)
                    }
                }
                .shadow(color: state == .open ? Theme.gold.opacity(0.55) : .black.opacity(0.6),
                        radius: state == .open ? 9 : 5)

                VStack(spacing: 0) {
                    Text(chapter.name)
                        .font(Theme.body(9).weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if state != .locked {
                        Text("\(cleared)/\(chapter.stages.count)")
                            .font(Theme.numeric(8))
                            .foregroundStyle(state == .cleared ? Theme.gold : Theme.textSecondary)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.72)))
                .fixedSize()
            }
        }
        .buttonStyle(.plain)
        .opacity(state == .locked ? 0.75 : 1)
    }
}
