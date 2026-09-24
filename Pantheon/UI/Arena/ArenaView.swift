import SwiftUI

/// PvP: your standing, your two teams, and the people to attack — in the
/// Arena of Souls.
///
/// Landscape shape. The page used to be one `ScrollView` under a navigation
/// bar: the rank panel, the two team panels, then the challengers, so a phone
/// showed the rank and about one opponent. It became two columns under the
/// strip — your side on the left, the challengers on the right with the full
/// height of the frame — and nothing but that list scrolls. That shape stays.
///
/// What changed on 2026-09-22 (phase B of the premium pass, PLAN.md *Phase B
/// of the premium pass*): run 211's frame was cream panels on a cream ground,
/// the one PLACE tab with no painting at all, "INITIATE" in grey-blue as the
/// weakest word on the screen, a rank panel half empty marble, and every team
/// card's name cut ("Anubis,…", "Sekh…", "Azure…", "Scara…"). The lobby is now
/// the place its fights are staged in: `arena_of_souls_bg`, the painting every
/// arena and guild-war battle stands on (`BattleContext.environment`), full
/// bleed and anchored high so the watching gods' heads stay in the band, with
/// the words on dark glass the way the summon hall has them. The teams are
/// FACES (`UnitPortraitTile`, no name strip, nothing to cut), the tier is
/// carved gold beside a crest, the challengers are three glass cards that fade
/// into the rest (Epic Seven and AFK Journey both show three), and the strip
/// holds the attacks with their refill clock, the laurel exchange and the
/// three currencies the arena touches.
///
/// Run 216's judges found it still wall-to-wall glass over brown murk, so
/// the standing came off its plate onto the painting, the painting bleeds to
/// both edges of the glass, and the "+110/day" laurels nothing pays left the
/// screen (`standingBlock`). Run 221's found the carved standing running
/// across the painted Anubis's face, so it is on glass again — a plate as
/// tall as the standing and no taller, with the painting open below it down
/// to the teams (`standingColumn`).
///
/// Two controls left the strip. Refresh was dead: `ArenaService.pool` is a
/// pure function of the points and the UTC day, so it brought back the list
/// that was already there — the list turns over by itself after every fight
/// (a win moves the points) and at midnight. Simulate became the Rate bead
/// beside the defence it rates, so the answer lands where the question is.
struct ArenaView: View {
    @EnvironmentObject private var store: GameStore
    @State private var opponents: [ArenaOpponent] = []
    @State private var pendingEngines: [String: BattleEngine] = [:]
    @State private var battle: BattleContext?
    @State private var showDefensePicker = false
    @State private var showOffensePicker = false
    /// The bazaar's laurel exchange: what the arena's own currency buys, one
    /// tap from where it is won (there was no way from here to there).
    @State private var showExchange = false
    /// The Draft Arena's board (`DraftView`), over the whole screen as a
    /// battle is: it needs the full height for two columns of five.
    @State private var showDraft = false
    @State private var defenseRating: Double?
    /// True while the challengers are being built off the main thread, so a
    /// second appearance does not start a second build over the top of the
    /// first.
    @State private var isRefreshing = false
    /// True while the defence rating is being simulated. Five whole battles
    /// run to a conclusion, so this one is emphatically not a main-thread job
    /// either — the Simulate button used to freeze the screen for as long as
    /// it took.
    @State private var isRating = false

    private var record: ArenaRecord { store.player.arena }

    /// The Arena of Souls, where every arena fight is staged, so the lobby is
    /// the fight's anteroom. The Colosseum was the other candidate and stays
    /// Rome's second chapter's (PLAN.md, *Phase B*, option C).
    private static let painting = "arena_of_souls_bg"
    /// A square painting on an 874 × 271 band (full bleed since run 216)
    /// shows about a third of its height; the centred crop took the painted
    /// gods off at the neck. At 0.26 the band opened at 0.18 of the painting
    /// and Anubis's ears and Horus's crown were under the strip; at 0.20 it
    /// opens at 0.14, so the jackal's whole head stands at the top of the
    /// band beside the carved standing, and his body fills the open painting
    /// between the standing and the teams.
    private static let paintingFocus = UnitPoint(x: 0.5, y: 0.20)
    /// One attack comes back every thirty minutes. This is
    /// `ArenaService.refreshAttacks`'s own interval, which is a local there:
    /// the strip's clock counts to the same number and must change with it.
    private static let attackRefill: TimeInterval = 30 * 60
    /// The size every face on the screen is decoded at before the list is
    /// handed over: the wide layout's 40 points (the narrow one's 32 lands in
    /// the same 128-pixel bucket).
    private static let faceWarmSize: CGFloat = 40
    /// How far the challenger cards' shadows may fall outside the list's own
    /// width before the fade's mask cuts them, so a card's shadow does not end
    /// in a hard vertical edge at the list's side.
    private static let shadowRoom: CGFloat = 12

    var body: some View {
        NavigationStack {
            GameScreen("Arena") {
                attacksWell
                exchangeButton
                // Energy left the wallet: the arena never spends it, and the
                // strip had seven readings on it (run 211).
                BarWallet(
                    wallet: store.player.wallet,
                    shows: [.laurels, .divinity, .drachma]
                )
            } content: {
                place
            }
            .onAppear(perform: refresh)
            .sheet(isPresented: $showDefensePicker) {
                TeamPickerView(slot: .arenaDefense, maxSize: ArenaService.teamSize)
                    .environmentObject(store)
                    .onDisappear { defenseRating = nil }
            }
            .sheet(isPresented: $showOffensePicker) {
                TeamPickerView(slot: .arenaOffense, maxSize: ArenaService.teamSize)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showExchange) {
                // Spelled out: `.laurels` is also a `BarWallet.Kind`.
                ShopView(opening: ShopService.Section.laurels)
                    .environmentObject(store)
            }
            .fullScreenCover(item: $battle) { context in
                battleScreen(for: context)
            }
            .fullScreenCover(isPresented: $showDraft) {
                DraftView()
                    .environmentObject(store)
            }
        }
    }

    /// Building the challengers is not free: five opponents, each a team of
    /// four units rolled out of the summon pool with six generated relics
    /// apiece and every one of them resolved through `ProgressionService`. It
    /// ran on the main thread inside `onAppear`, so the Arena could not draw
    /// its first frame until it finished — the owner felt it as "it did get
    /// really laggy after I clicked on Arena" on 2026-09-10, and the CI tour
    /// photographed the screen as pure black, with even the tour's own overlay
    /// missing, which is what a view looks like before its first frame.
    ///
    /// It now runs off the main thread and lands when it lands. The screen
    /// draws immediately with whatever it already had, which after the first
    /// visit is the previous list, and the challengers appear a moment later.
    /// The pool is deterministic in the day and the player's points, so the
    /// list that arrives is the same one that would have blocked the frame.
    /// There is no Refresh button any more (see the type's comment): this runs
    /// on appearing and after every fight.
    private func refresh() {
        let entered = Perf.begin()
        store.refreshTimedResources()
        Perf.end(entered, "arena: refreshTimedResources", over: 8)
        // The player's own four fight in every arena bout, so their meshes
        // and clips go into the model cache while the challengers are
        // still being built; the chosen opponent's follow at Fight.
        ModelLibrary.shared.warm(forms: store.team(store.player.arenaOffenseTeam).map { (spec: $0.blueprint.model, awakened: $0.unit.isAwakened) }, crowded: true)
        guard !isRefreshing else { return }
        isRefreshing = true
        // The record and the day are read HERE, on the main actor, and handed
        // to the task by value. `ArenaRecord` and `ArenaOpponent` are both
        // Sendable and `ArenaService.pool` is a pure function of them, so the
        // build genuinely happens off the main thread. Reaching back into the
        // store from inside the task would have put the work straight back
        // where it came from.
        let record = store.player.arena
        let day = Int(Date().timeIntervalSince1970 / 86_400)
        // The face size in pixels, read here because `UIScreen` is the main
        // thread's; the task decodes every challenger's portrait at it before
        // the list is handed over, so the list draws from the cache.
        let facePixels = Int((Self.faceWarmSize * UIScreen.main.scale).rounded(.up))
        Task.detached(priority: .userInitiated) {
            let started = Perf.begin()
            let built = ArenaService.pool(for: record, day: day)
                .filter { !record.defeatedOpponentIDs.contains($0.id) }
            Perf.end(started, "arena: challenger pool", over: 1)
            BundleArt.warmThumbnails(
                built.flatMap { opponent in
                    opponent.team.map { $0.blueprint.model.portraitName(awakened: $0.unit.isAwakened) }
                },
                maxPixel: facePixels
            )
            await MainActor.run {
                let landed = Perf.begin()
                opponents = built
                isRefreshing = false
                Perf.end(landed, "arena: challengers handed to the view", over: 1)
            }
        }
    }

    /// Rating the defence runs five complete battles. On the main thread that
    /// is a freeze with no spinner and no explanation, so it runs off it and
    /// the bead says so while it works.
    private func rateDefence() {
        guard !isRating else { return }
        isRating = true
        let player = store.player
        Task.detached(priority: .userInitiated) {
            let rating = ArenaService.rateDefense(player: player)
            await MainActor.run {
                defenseRating = rating
                isRating = false
            }
        }
    }

    @ViewBuilder
    private func battleScreen(for context: BattleContext) -> some View {
        if case .arena(let opponent) = context, let engine = pendingEngines[opponent.id] {
            BattleView(model: BattleViewModel(engine: engine, context: context, store: store))
                .environmentObject(store)
                .onDisappear { refresh() }
        } else {
            Theme.surface.ignoresSafeArea()
                .onAppear { battle = nil }
        }
    }

    // MARK: - The strip

    /// The attacks and when the next one comes back: every game in the genre
    /// puts a clock on its attack currency (Summoners War's wings, Raid's
    /// tokens), and run 211's "10/10" had none. The clock is a
    /// `Text(timerInterval:)`, which counts itself down without a timer here;
    /// the store's 30-second tick (`refreshTimedResources`) bumps the count.
    /// The range must run forwards or it traps, so the end is never less
    /// than a second away.
    ///
    /// Run 216's "7/10 14:32" read as the time of day, so the clock says
    /// what it counts to: "+1 in 14:32". The flame is drawn in the wallet's
    /// 18-point icon box, so it stands the same size as the painted laurel,
    /// crystal and coins beside it; it stays a glyph until an attack token
    /// is painted (no item painting exists for it).
    private var attacksWell: some View {
        let left = record.attacksRemaining
        return HStack(spacing: 5) {
            Image(systemName: "flame.fill")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(left > 0 ? Color(hex: "#F3A55A") : Theme.onGlassDim)
                .frame(width: 18, height: 18)
            Text("\(left)/\(record.maxAttacks)")
                .font(Theme.numeric(12.5))
                .foregroundStyle(Theme.onGlass)
                .lineLimit(1)
                .fixedSize()
            if left < record.maxAttacks {
                let now = Date()
                let next = max(now.addingTimeInterval(1), record.lastRefresh.addingTimeInterval(Self.attackRefill))
                Text("+1 in")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.onGlassDim)
                    .lineLimit(1)
                    .fixedSize()
                Text(timerInterval: now...next, countsDown: true)
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(Theme.onGlassDim)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .shadow(color: .black.opacity(0.6), radius: 1, y: 1)
        .padding(.horizontal, 10)
        .frame(height: ScreenChrome.control)
        .background(BarWell())
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(left) of \(record.maxAttacks) attacks")
    }

    /// The door to the bazaar's laurel exchange, in the strip's one material
    /// (`BarButton`'s well, height and label) but carrying the PAINTED laurel
    /// the wallet beside it draws: `BarButton` takes only an SF glyph, and
    /// `laurel.leading` beside the wallet's painting was two icon languages
    /// in one strip (run 216).
    private var exchangeButton: some View {
        Button {
            showExchange = true
        } label: {
            HStack(spacing: 4) {
                ItemIcon(key: "laurels", size: 18, glow: false)
                Text("Exchange")
                    .font(Theme.body(11).weight(.bold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(Theme.onGlassGold)
            .padding(.leading, 8)
            .padding(.trailing, 11)
            .frame(height: ScreenChrome.control)
            .background(ScreenChrome.well)
            .stripHitTarget()
        }
        .buttonStyle(GamePressStyle(.plate))
        .accessibilityLabel("Laurel exchange")
    }

    // MARK: - The place

    /// The painting under everything, the standing carved on it, the teams
    /// and the challengers on glass. The sizes are solved once from the width
    /// the screen is given (`ArenaLobbyMetrics`) — never a `ViewThatFits`,
    /// which lays out every candidate. The teams and the offence's power are resolved once here
    /// and handed down: a resolve reads every relic, and the old screen asked
    /// for the offence three times a frame.
    private var place: some View {
        GeometryReader { geo in
            let metrics = ArenaLobbyMetrics(width: geo.size.width)
            let defence = store.team(store.player.arenaDefenseTeam)
            let offence = store.team(store.player.arenaOffenseTeam)
            ZStack {
                // A lighter hand than the summon hall's 0.55 / 0.62: the
                // standing is carved on the painting under the top scrim, the
                // teams and the challengers are on glass. The backdrop is the
                // bottom layer of a full-size stack with no padding round it,
                // so it bleeds to both edges of the glass.
                PlaceBackdrop(painting: Self.painting, focus: Self.paintingFocus, topScrim: 0.5, footScrim: 0.5)
                // No `PlaceAmbience` across the whole frame: its motes drifted
                // UNDER the glass plates and photographed as grey specks on
                // their edges (run 216). The dust rises in the open painting
                // of the left column only (`standingColumn`).
                HStack(alignment: .top, spacing: ArenaLobbyMetrics.gap) {
                    standingColumn(metrics, defence: defence, offence: offence)
                        .frame(width: metrics.column)
                        .frame(maxHeight: .infinity)
                    challengerColumn(metrics, offense: offensePower(offence))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.vertical, 6)
            }
        }
    }

    // MARK: - Standing

    /// Your side: the standing on its own glass at the top, the two teams on
    /// glass at the foot, and the painting open between them.
    ///
    /// Run 216 had the standing on a plate that took every spare point, so
    /// 40% of it was empty glass (run 211's "half empty marble" again, in
    /// dark glass) and both columns were wall-to-wall plates over a brown
    /// murk, with Anubis a ghost behind the glass. So the standing came off
    /// its plate and stood carved on the painting — where run 221 found the
    /// meter, "CHAMPION IN 440" and the record running across the jackal's
    /// muzzle and chest, and a mote sitting on the meter's track. The
    /// painting cannot be moved from under it: a square painting across the
    /// whole band shows its full width, so the god stands where he is
    /// whatever the focus, and lower he is the same god's chest. Now the
    /// standing is on glass that hugs it (`standingBlock`), the teams plate
    /// sits on the column's foot level with the challengers' fade, and what
    /// is left between the two is the Arena of Souls itself, with its dust
    /// rising in it. The dust is there and nowhere else, so no mote drifts
    /// under glass.
    private func standingColumn(_ metrics: ArenaLobbyMetrics, defence: [ResolvedUnit], offence: [ResolvedUnit]) -> some View {
        VStack(spacing: 6) {
            standingBlock(metrics)
            // The open painting between the plates, with the dust rising in
            // it, clipped to the gap: no mote drifts under either plate or
            // across the challengers' glass.
            Motes(count: 10, color: Color(hex: "#FFDFA0"), seed: 930)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            teamsPlate(metrics, defence: defence, offence: offence)
        }
    }

    /// The crest and the tier carved in gold, the points, the climb to the
    /// next tier as a meter, and the record, on a plate of glass that hugs
    /// them. Four readings, where run 211 spread six lines of 11-point text
    /// down a 290-point box with two Spacers. The ladder and the full record
    /// are behind the little ?: words come on a tap.
    ///
    /// Glass again since run 221 (`standingColumn` says why): carved on the
    /// painting in a soft pool of shade, the words ran across the painted
    /// Anubis's face. The plate is as tall as the block and no taller, so the
    /// painting stays open below it; the cream and dim lines keep their
    /// close shadow, which the glass does not need and does not mind.
    ///
    /// Run 216's "+110/day" is gone: `ArenaTier.dailyLaurels` is paid by
    /// nothing in the game, so the screen stopped promising it (reported to
    /// the owner as a rule to decide).
    private func standingBlock(_ metrics: ArenaLobbyMetrics) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ArenaCrest(tier: record.tier, size: metrics.crest)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 2) {
                    // 26 points, and it may shrink to 0.7 (18.2, over the
                    // title floor) for CHAMPION in the narrow column.
                    Text(record.tier.displayName.uppercased())
                        .font(Theme.display(26))
                        .tracking(1.2)
                        .carved()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    InfoDot(title: "Arena ranks") { tierLadder }
                }
                HStack(spacing: 4) {
                    ItemIcon(key: "rank_points", size: 18, glow: false)
                    Text(record.points.formatted())
                        .font(Theme.numeric(16))
                        .foregroundStyle(Theme.onGlass)
                        .lineLimit(1)
                        .fixedSize()
                    Text("pts")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.onGlassDim)
                        .lineLimit(1)
                        .fixedSize()
                }
                .shadow(color: .black.opacity(0.85), radius: 1.5, y: 1)
                .padding(.top, 2)
                if let next = nextTier {
                    GlassMeter(
                        value: Double(record.points - record.tier.threshold),
                        maximum: Double(max(1, next.threshold - record.tier.threshold)),
                        tint: record.tier.color,
                        height: 6
                    )
                    .padding(.top, 5)
                    climbLine("\(next.displayName.uppercased()) IN \((next.threshold - record.points).formatted())")
                } else {
                    GlassMeter(value: 1, maximum: 1, tint: record.tier.color, height: 6)
                        .padding(.top, 5)
                    climbLine("THE SUMMIT")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(GlassPlate(radius: 12))
    }

    /// The line under the meter: how far the next tier is, and the record.
    /// Both at their own width; the narrow column's crest is 48 points so the
    /// longest pair ("ACOLYTE IN 1,200", "123W · 45L", 174 points) still fits.
    /// Cream-dim on the painting, so it carries the block's close shadow.
    private func climbLine(_ climb: String) -> some View {
        HStack(spacing: 4) {
            Text(climb)
                .font(Theme.body(11).weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.onGlassDim)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 4)
            Text("\(record.wins)W · \(record.losses)L")
                .font(Theme.numeric(11.5))
                .foregroundStyle(Theme.onGlassDim)
                .lineLimit(1)
                .fixedSize()
        }
        .shadow(color: .black.opacity(0.85), radius: 1.5, y: 1)
        .padding(.top, 4)
    }

    private var nextTier: ArenaTier? {
        ArenaTier.allCases.first { $0.threshold > record.points }
    }

    /// The ? beside the tier: every rank with its crest, its floor and the
    /// laurels a win pays there (`ArenaService.laurelsForWin`, what
    /// `applyResult` actually grants — the column was the day's laurels until
    /// run 216, which nothing pays), the player's own row lit, and the record
    /// in a sentence. It is the cream popover every ? in the game opens, so
    /// it is written in the cream screens' ink.
    private var tierLadder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Each rank's floor, and the laurels a win pays there.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(ArenaTier.allCases) { tier in
                HStack(spacing: 8) {
                    ArenaCrest(tier: tier, size: 22)
                    Text(tier.displayName)
                        .font(Theme.body(12).weight(.bold))
                        .foregroundStyle(tier == record.tier ? Theme.goldDeep : Theme.textPrimary)
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 6)
                    Text("\(tier.threshold.formatted())+")
                        .font(Theme.numeric(11.5))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                    HStack(spacing: 2) {
                        ItemIcon(key: "laurels", size: 14, glow: false)
                        Text("+\(ArenaService.laurelsForWin(tier: tier))")
                            .font(Theme.numeric(11.5))
                            .foregroundStyle(Theme.success)
                            .lineLimit(1)
                    }
                    .fixedSize()
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tier == record.tier ? Theme.gold.opacity(0.16) : Color.clear)
                )
            }
            Text(recordSummary)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    /// The record in words. The defence's own record is left out until it has
    /// one: nothing attacks a defence in the offline game yet, and "held 0 of
    /// 0" says nothing.
    private var recordSummary: String {
        var parts = ["Won \(record.wins), lost \(record.losses)."]
        let defended = record.defenseWins + record.defenseLosses
        if defended > 0 {
            parts.append("Your defence held \(record.defenseWins) of \(defended).")
        }
        parts.append("Best \(record.highestPoints.formatted()) points.")
        parts.append("Points never fall below your tier's floor.")
        return parts.joined(separator: " ")
    }

    // MARK: - Teams

    /// The power of the team that actually attacks. `store.totalPower` is the
    /// sum of the player's best *five* units, and an arena team is four, so
    /// comparing a challenger against it biased every row toward green — an
    /// offence team that is not your top four was reported as an easy fight.
    /// It is summed from the offence `place` resolves once a frame, so no
    /// caller resolves the four again.
    private func offensePower(_ offence: [ResolvedUnit]) -> Int {
        offence.reduce(0) { $0 + $1.power }
    }

    /// Both teams on one plate, four faces each with the leader crowned, the
    /// empty places dashed. Faces rather than `UnitCard`s: the card's cream
    /// name strip cut every name in run 211 and would be a cream slab on glass.
    private func teamsPlate(_ metrics: ArenaLobbyMetrics, defence: [ResolvedUnit], offence: [ResolvedUnit]) -> some View {
        VStack(spacing: 5) {
            teamRow(
                title: "Defence",
                team: defence,
                face: metrics.face,
                detail: defenceDetail(isEmpty: defence.isEmpty)
            ) {
                showDefensePicker = true
            }
            Rectangle()
                .fill(Theme.glassRim.opacity(0.3))
                .frame(height: 1)
            teamRow(
                title: "Offence",
                team: offence,
                face: metrics.face,
                detail: offenceDetail(power: offensePower(offence))
            ) {
                showOffensePicker = true
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(GlassPlate(radius: 12))
    }

    /// One team: its name carved over a reading on the left, and all four
    /// places as faces on the right — the faces are the button that opens the
    /// picker. `detail` is taken as a VALUE, not a builder closure, so each
    /// call carries exactly one trailing closure. The label side takes what
    /// the faces leave (94 points wide, 88 narrow): "Holds 100%" is 86.
    ///
    /// The four-face row replaced a `ViewThatFits` of four card sizes, which
    /// laid out every candidate on every pass; the phone's watchdog once put
    /// the Arena's entry at two seconds of main thread.
    private func teamRow<Detail: View>(
        title: String,
        team: [ResolvedUnit],
        face: CGFloat,
        detail: Detail,
        onTap: @escaping () -> Void
    ) -> some View {
        let shown = Array(team.prefix(ArenaService.teamSize))
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title.uppercased())
                    .font(Theme.title(13))
                    .tracking(1.4)
                    .carved(glow: false)
                    .lineLimit(1)
                    .fixedSize()
                detail
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onTap) {
                HStack(spacing: ArenaLobbyMetrics.faceSpacing) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, unit in
                        UnitPortraitTile(unit: unit, size: face, isLeader: index == 0 && leadsInArena(unit))
                    }
                    ForEach(0..<max(0, ArenaService.teamSize - shown.count), id: \.self) { _ in
                        EmptyUnitSlot(size: face)
                    }
                }
            }
            .buttonStyle(GamePressStyle(.plate))
            .accessibilityLabel("Change the \(title.lowercased()) team")
        }
    }

    /// Under DEFENCE: NOT SET, the rating at work, the rating in its colour,
    /// or the Rate bead — the strip's old Simulate, beside what it rates.
    @ViewBuilder
    private func defenceDetail(isEmpty: Bool) -> some View {
        if isEmpty {
            Text("NOT SET")
                .font(Theme.body(11).weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.onGlassWarning)
                .lineLimit(1)
                .fixedSize()
        } else if isRating {
            HStack(spacing: 4) {
                Image(systemName: "hourglass")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Theme.onGlassGold)
                Text("Rating")
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(Theme.onGlassDim)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(height: 22)
        } else if let defenseRating {
            GlassBead(
                text: "Holds \(Int((defenseRating * 100).rounded()))%",
                tint: ratingTint(defenseRating),
                height: 22,
                action: { rateDefence() }
            )
        } else {
            GlassBead(
                text: "Rate",
                systemImage: "waveform.path.ecg",
                tint: Theme.onGlassGold,
                height: 22,
                action: { rateDefence() }
            )
        }
    }

    /// Under OFFENCE: the four's power, which every challenger's is tinted
    /// against.
    private func offenceDetail(power: Int) -> some View {
        HStack(spacing: 3) {
            Text("POWER")
                .font(Theme.body(11).weight(.heavy))
                .tracking(0.6)
                .foregroundStyle(Theme.onGlassDim)
            Text(power.formatted())
                .font(Theme.numeric(12.5))
                .foregroundStyle(Theme.onGlass)
        }
        .lineLimit(1)
        .fixedSize()
        .frame(height: 22)
    }

    private func ratingTint(_ rating: Double) -> Color {
        if rating >= 0.6 { return Theme.onGlassSuccess }
        if rating >= 0.4 { return Theme.onGlassWarning }
        return Theme.onGlassDanger
    }

    /// The engine's leader is the team's first unit (`BattleEngine.buildSide`),
    /// and its skill counts here only if it applies in the arena — so the
    /// crown means what the fight will do.
    private func leadsInArena(_ unit: ResolvedUnit) -> Bool {
        unit.blueprint.leaderSkill?.appliesInArena ?? false
    }

    // MARK: - Challengers

    /// The laurels a win pays. It depends on YOUR tier alone
    /// (`ArenaService.laurelsForWin`), so run 211 printed the same "12" on
    /// every row; it is said once, on the header. Computed the way
    /// `ArenaService.applyResult` pays it, Thursday's Double Laurels included.
    private var laurelsPerWin: Int {
        Int(Double(ArenaService.laurelsForWin(tier: record.tier)) * EventCalendar.multiplier(for: .arenaLaurelsBoost))
    }

    private var laurelsBoosted: Bool {
        EventCalendar.multiplier(for: .arenaLaurelsBoost) > 1
    }

    /// CHALLENGERS carved over the painting, then the cards on glass: three in
    /// view on a phone, fading into the rest at the foot the way the summon
    /// rail does. The cards may cast their shadows past the list's sides
    /// (`scrollClipDisabled`), and the fade's mask is widened by
    /// `shadowRoom` so it is the one thing that clips them.
    ///
    /// `offense` is the offence's power, summed once in `place`.
    private func challengerColumn(_ metrics: ArenaLobbyMetrics, offense: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            draftDoor(metrics)
            GlassSectionHeader(
                title: "Challengers",
                accessory: "+\(laurelsPerWin) a win",
                accessoryItemKey: "laurels",
                accessoryTint: laurelsBoosted ? Theme.onGlassGold : Theme.onGlassDim
            )
            .frame(height: 18)
            if opponents.isEmpty {
                // An empty list means two completely different things now that
                // the pool is built off the main thread, and saying the wrong
                // one is worse than saying nothing: the CI tour photographed
                // this panel announcing "You have cleared the current pool" on
                // a fresh account that had not fought anybody, because the
                // challengers were still a few milliseconds away. Since the
                // Draft Arena's door stands above the header (2026-09-23), the
                // house `EmptyState` (about 206 points) fits under the two on
                // no phone — about 165 points are left on a 16 Pro, 138 on a
                // mini — so the same words stand in a row (`quietChallengers`).
                quietChallengers
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(opponents) { opponent in
                            challengerCard(opponent, offense: offense, metrics: metrics)
                        }
                        Color.clear.frame(height: 12)
                    }
                }
                .scrollClipDisabled()
                .padding(.horizontal, Self.shadowRoom)
                .mask(
                    LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.93),
                                           .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                )
                .padding(.horizontal, -Self.shadowRoom)
            }
        }
    }

    /// The challengers' empty state as one row on the house's glass: the
    /// icon beside the carved title and the words `EmptyState` said, about
    /// 85 points tall where the column stack left it 165 on a 16 Pro and 138
    /// on a mini under the Draft Arena's door and the header.
    private var quietChallengers: some View {
        let icon = isRefreshing ? "hourglass" : "person.2.slash"
        let title: String = isRefreshing ? "Finding challengers" : "No challengers"
        let message: String = isRefreshing
            ? "Building five defence teams to fight."
            : "You have beaten today's challengers. New ones come as your points move."
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Theme.glassRim)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(Theme.title(14))
                    .tracking(1.2)
                    .carved(glow: false)
                    .lineLimit(1)
                    .fixedSize()
                Text(message)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.onGlassDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(GlassPlate(radius: 12))
    }

    // MARK: - The Draft Arena's door

    /// The door to the Draft Arena (2026-09-23, Docs/DRAFT.md), above the
    /// challengers: its crest, its crown and the rating, a line of what it is
    /// — or that a finished week's chest waits — and the gold DRAFT plate
    /// with the day's paid bouts under it. The same glass and the same plate
    /// as a challenger's card, so the column reads as one list of fights;
    /// pinned above the list rather than in it, so it never scrolls away.
    /// The line is at most 21 characters, and 32 while the box is too small
    /// to draft, which a narrow column (93 points of name block on an SE)
    /// still holds beside the 66-point plate.
    private func draftDoor(_ metrics: ArenaLobbyMetrics) -> some View {
        let record = store.draftRecord
        let open = store.canDraft
        let today = record.dayKey == EventCalendar.dayKey(Date()) ? record.paidToday : 0
        let paidLeft = max(0, DraftService.paidBoutsPerDay - today)
        let chestWaits = record.pendingChest != nil
        let line: String
        if !open {
            line = "Five different monsters to draft"
        } else if chestWaits {
            line = "Last week's chest waits"
        } else {
            line = "Pick five, strike one"
        }
        return Button {
            showDraft = true
        } label: {
            HStack(spacing: 10) {
                DraftCrest(tier: record.tier, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("DRAFT ARENA")
                        .font(Theme.title(14))
                        .tracking(1.2)
                        .carved(glow: false)
                        .lineLimit(1)
                        .fixedSize()
                    HStack(spacing: 4) {
                        Text(record.tier.displayName)
                            .font(Theme.body(11).weight(.bold))
                            .foregroundStyle(record.tier.color)
                            .lineLimit(1)
                            .fixedSize()
                        Text(record.rating.formatted())
                            .font(Theme.numeric(11.5))
                            .foregroundStyle(Theme.onGlassDim)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    Text(line)
                        .font(Theme.body(11))
                        .foregroundStyle(chestWaits ? Theme.onGlassGold : Theme.onGlassDim)
                        .lineLimit(1)
                        .fixedSize()
                }
                .shadow(color: .black.opacity(0.7), radius: 1, y: 1)
                Spacer(minLength: 4)
                VStack(spacing: 0) {
                    Text("DRAFT")
                        .font(Theme.title(13))
                        .tracking(1.2)
                        .lineLimit(1)
                        .fixedSize()
                    Text("\(paidLeft)/\(DraftService.paidBoutsPerDay)")
                        .font(Theme.numeric(11.5))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(open ? Theme.ink : Theme.onGlassDim)
                .frame(width: metrics.fightWidth, height: 40)
                .background(fightPlate(open))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                        .strokeBorder(open ? Color(hex: "#FFE9A8").opacity(0.6) : Theme.glassRim, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
                .shadow(color: open ? Theme.gold.opacity(0.35) : .clear, radius: 6, y: 2)
            }
            .padding(.horizontal, ArenaLobbyMetrics.cardPadding)
            .padding(.vertical, 7)
            .background(GlassPlate(radius: 10))
        }
        .buttonStyle(GamePressStyle(.plate))
        .disabled(!open)
        .accessibilityLabel("Draft Arena, \(record.tier.displayName), rating \(record.rating)")
    }

    /// One challenger: who they are (name, crest and tier, power tinted
    /// against your offence), the four faces you would meet, and the gold
    /// FIGHT plate with the points a win pays, the points a loss costs under
    /// it. The name block is as wide as the width solve gives it
    /// (`ArenaLobbyMetrics.nameWidth`, never under the longest generated name,
    /// "Nikandros", at 84 points), so no card cuts a name; a longer real
    /// display name, once there is a server, takes a second line rather than
    /// an ellipsis. The opponent's points print only where the card has room
    /// for them; the tier already says the neighbourhood.
    private func challengerCard(_ opponent: ArenaOpponent, offense: Int, metrics: ArenaLobbyMetrics) -> some View {
        let win = ArenaService.pointsForWin(playerPoints: record.points, opponentPoints: opponent.points)
        let loss = ArenaService.pointsForLoss(playerPoints: record.points, opponentPoints: opponent.points)
        let canAttack = record.attacksRemaining > 0
        let team = Array(opponent.team.prefix(ArenaService.teamSize))
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(opponent.name)
                    .font(Theme.title(metrics.nameSize))
                    .foregroundStyle(Theme.onGlass)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    ArenaCrest(tier: opponent.tier, size: 12)
                    Text(opponent.tier.displayName)
                        .font(Theme.body(11).weight(.bold))
                        .foregroundStyle(opponent.tier.color)
                        .lineLimit(1)
                        .fixedSize()
                    if metrics.showsPoints {
                        Text(opponent.points.formatted())
                            .font(Theme.numeric(11.5))
                            .foregroundStyle(Theme.onGlassDim)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                HStack(spacing: 4) {
                    Text("Power")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.onGlassDim)
                    Text(opponent.power.formatted())
                        .font(Theme.numeric(11.5))
                        .foregroundStyle(powerTint(opponent.power, against: offense))
                }
                .lineLimit(1)
                .fixedSize()
            }
            .frame(width: metrics.nameWidth, alignment: .leading)

            HStack(spacing: ArenaLobbyMetrics.faceSpacing) {
                ForEach(Array(team.enumerated()), id: \.element.id) { index, unit in
                    UnitPortraitTile(unit: unit, size: metrics.face, isLeader: index == 0 && leadsInArena(unit))
                }
            }

            Spacer(minLength: 4)

            VStack(spacing: 1) {
                Button {
                    attack(opponent)
                } label: {
                    VStack(spacing: 0) {
                        Text("FIGHT")
                            .font(Theme.title(13))
                            .tracking(1.2)
                            .lineLimit(1)
                            .fixedSize()
                        HStack(spacing: 3) {
                            // 15, not 12: at 12 the painted trophy was a
                            // smudge beside the "+9" (run 216).
                            ItemIcon(key: "rank_points", size: 15, glow: false)
                            Text("+\(win)")
                                .font(Theme.numeric(12))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .foregroundStyle(canAttack ? Theme.ink : Theme.onGlassDim)
                    .frame(width: metrics.fightWidth, height: 40)
                    .background(fightPlate(canAttack))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                            .strokeBorder(canAttack ? Color(hex: "#FFE9A8").opacity(0.6) : Theme.glassRim, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
                    .shadow(color: canAttack ? Theme.gold.opacity(0.35) : .clear, radius: 6, y: 2)
                }
                // A gold plate at the card's end: the primary press, though
                // the column scrolls — a drag rarely starts on it.
                .buttonStyle(GamePressStyle(.primary))
                .disabled(!canAttack)
                .accessibilityLabel("Fight \(opponent.name), win \(win) points")
                Text("−\(loss) if lost")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.onGlassDim)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, ArenaLobbyMetrics.cardPadding)
        .padding(.vertical, 7)
        .frame(minHeight: 66)
        .background(GlassPlate(radius: 10))
    }

    /// Gold when there is an attack to spend, glass when there is not. An
    /// if/else, never a `?:` — a LinearGradient and `Theme.glass`, a Color,
    /// in a ternary do not compile.
    ///
    /// The gold is `PrimaryButton`'s drawn gold, lit from above with its top
    /// gloss: the bare `Theme.goldPlate` read as flat khaki beside every
    /// Fight and Claim of phase A (run 216). The ramp stops at `Theme.gold`
    /// rather than the button's dark #7A5B1C foot, because this plate has a
    /// second line ("+9") in its lower half and ink must read on it there.
    @ViewBuilder
    private func fightPlate(_ canAttack: Bool) -> some View {
        if canAttack {
            LinearGradient(
                colors: [Color(hex: "#FFE9A8"), Color(hex: "#E2BF62"), Theme.gold],
                startPoint: .top, endPoint: .bottom
            )
            .overlay(
                LinearGradient(colors: [Color.white.opacity(0.35), Color.clear], startPoint: .top, endPoint: .center)
            )
        } else {
            Theme.glass
        }
    }

    /// A challenger's power against your offence's: rose when they are more
    /// than a tenth stronger, green when more than a tenth weaker, cream in
    /// between. The old rows were red or green with no middle, so an even
    /// fight read as a warning.
    private func powerTint(_ power: Int, against offense: Int) -> Color {
        guard offense > 0 else { return Theme.onGlass }
        let ratio = Double(power) / Double(offense)
        if ratio > 1.10 { return Theme.onGlassDanger }
        if ratio < 0.90 { return Theme.onGlassSuccess }
        return Theme.onGlass
    }

    private func attack(_ opponent: ArenaOpponent) {
        ModelLibrary.shared.warm(forms: opponent.team.map { (spec: $0.blueprint.model, awakened: $0.unit.isAwakened) }, crowded: true)
        guard let engine = store.startArenaBattle(against: opponent) else { return }
        pendingEngines[opponent.id] = engine
        // Straight onto the stage card, with no slide (Docs/FEEL.md W2.24).
        BattleCover.open { battle = .arena(opponent) }
    }
}

// MARK: - The lobby's sizes

/// Every size the Arena lobby uses, solved once from the width it is given
/// (2026-09-22). Two classes: WIDE from 700 points (every Face ID iPhone, the
/// 13 mini's 724 included) and NARROW below it (the iPhone SE's 643). The
/// research's first cut used one set of constants, and on the SE the
/// challenger's name block collapsed to 47 points; the critic ruled out the
/// shrinking and the ellipsis that would have hidden it. So the narrow class
/// takes 32-point faces, a 262-point column, a 48-point crest and a 66-point
/// FIGHT plate, and the name block is whatever the card has left — measured
/// here, not left to the layout: 106 on an iPhone 15 Pro, 96 on a mini, 93 on
/// an SE, where "Nikandros", the longest generated name, is 84 at 14 points
/// and 78 at the narrow 13.
///
/// The heights are budgeted under the tab bar, which since run 216 is laid
/// out under the tab rather than inset over it (run 216 laid this screen out
/// 58 points too tall and put the offence under the bar): a phone gives this
/// screen 402 − 52 strip − 58 bar − 21 home indicator = 271 points (262 on a
/// 15 Pro, 244 on a mini), 12 of it the columns' padding. The left column
/// needs about 205 (the carved standing about 84, the teams about 115), so
/// it fits a mini with room to spare and the rest is open painting between
/// them; the right needs 246 for the header and three 70-point cards, so a
/// 16 Pro shows all three with the fourth's top in the fade, a 15 Pro the
/// third's foot in the fade, and a mini two and most of the third — which
/// is the fade's point.
private struct ArenaLobbyMetrics {
    static let wideFrom: CGFloat = 700
    /// Between the two columns.
    static let gap: CGFloat = 10
    /// Between two faces in a row.
    static let faceSpacing: CGFloat = 4
    /// A challenger card's own inset, left and right.
    static let cardPadding: CGFloat = 10

    let column: CGFloat
    let face: CGFloat
    let crest: CGFloat
    let fightWidth: CGFloat
    let nameSize: CGFloat
    let nameWidth: CGFloat
    let showsPoints: Bool

    init(width: CGFloat) {
        let wide = width >= Self.wideFrom
        column = wide ? 300 : 262
        face = wide ? 40 : 32
        crest = wide ? 72 : 48
        fightWidth = wide ? 74 : 66
        nameSize = wide ? 14 : 13
        // The challenger card's interior, less everything in it that is not
        // the name block: the four faces, three 8-point gaps, the Spacer's 4
        // and the FIGHT plate.
        let list = width - 2 * ScreenChrome.contentPadding - column - Self.gap
        let interior = list - 2 * Self.cardPadding
        let faces = CGFloat(ArenaService.teamSize) * face + CGFloat(ArenaService.teamSize - 1) * Self.faceSpacing
        let room = interior - (faces + 3 * 8 + 4 + fightWidth)
        nameWidth = max(80, min(124, room.rounded(.down)))
        // Crest, tier and points: "Champion 2,301" is 105 points.
        showsPoints = room >= 108
    }
}

// MARK: - The crest

/// An arena tier as an emblem: the painted laurel wreath with a disc of the
/// tier's colour in it and the tier's numeral, I to VI, carved on the disc
/// (2026-09-22). "INITIATE" in grey-blue with no emblem was the weakest thing
/// on run 211's frame, where the genre's ranks are all named emblems.
///
/// It draws in one of three ways:
/// 1. `arena_crest_<tier>` when the bundle has it. Painted crests are the
///    better crest (PLAN.md, *Phase B*, option E: one Meshy picture sheet,
///    about 9 credits) and wait on the owner's word; when they land they draw
///    here with no code change. None is painted today.
/// 2. At 44 points and up, the wreath, the disc and the numeral.
/// 3. Under 44, the disc alone: the numeral would fall under the title floor.
private struct ArenaCrest: View {
    let tier: ArenaTier
    var size: CGFloat = 72

    var body: some View {
        let painted = "arena_crest_\(tier.displayName.lowercased())"
        return Group {
            if BundleImage.exists(painted) {
                BundleImage(name: painted, renderedAt: size)
                    .aspectRatio(contentMode: .fit)
            } else if size >= 44 {
                ZStack {
                    RadialGradient(
                        colors: [tier.color.opacity(0.45), tier.color.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.55
                    )
                    ItemIcon(key: "laurels", size: size, glow: false)
                    // The wreath's ring centres a little above the middle of
                    // `item_laurels` (about 0.44 of its height).
                    disc(size * 0.5)
                        .offset(y: -size * 0.06)
                    Text(numeral)
                        .font(Theme.display(size * 0.22))
                        .carved(glow: false)
                        .lineLimit(1)
                        .fixedSize()
                        .offset(y: -size * 0.06)
                }
            } else {
                disc(size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tier.displayName)
    }

    private func disc(_ diameter: CGFloat) -> some View {
        ZStack {
            Circle().fill(tier.color)
            Circle().fill(
                LinearGradient(colors: [Color.white.opacity(0.38), Color.clear, Color.black.opacity(0.35)],
                               startPoint: .top, endPoint: .bottom)
            )
            Circle().strokeBorder(Theme.goldText, lineWidth: max(1, diameter * 0.07))
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: tier.color.opacity(0.6), radius: diameter * 0.15)
    }

    private var numeral: String {
        switch tier {
        case .initiate: return "I"
        case .acolyte: return "II"
        case .oracle: return "III"
        case .champion: return "IV"
        case .ascendant: return "V"
        case .olympian: return "VI"
        }
    }
}
