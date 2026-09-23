import SwiftUI

/// The week's events: what the calendar doubles today, what it doubles next,
/// and the Festival's gift when it is a festival week. Opens from the island
/// and from More, the way Missions does.
///
/// A DATA screen, and a cream one, the Missions board's kin (2026-09-22,
/// phase B; the critic's note on run 211's frame 45): the five cards were
/// paragraphs cut with ellipses — "HALF-ENERGY CA…", "NECROPOLIS OF THE
/// UNW…", "…twice the experience f…" — and the Festival's day tiles were
/// 30-point boxes beside an 11-point Claim. Now:
///
/// - the Festival is one marble band: its name with the rules behind a ?,
///   the seven days as the login gift's own pips (`GiftDayPip`), today's
///   gift as its painting (`RewardTile`) and a real claim (`ClaimPlate`);
/// - the week is five marble cards, Monday to Thursday and the weekend's
///   headline, each its day, its name on as many lines as it needs (the
///   Necropolis weekend takes three), ONE short line of what it touches, its
///   multiplier and its clock; the whole sentence is behind the ?; the one
///   on now is lit gold with a TODAY tag on its top edge;
/// - one line under them says what next weekend brings and when the next
///   Festival is.
///
/// Nothing here writes the save: the one claim goes through `onClaim`, which
/// the store owns.
struct EventsView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    /// The moment the screen is read at. Nil is now; the CI tour pins a
    /// Festival Monday so one frame shows the gift band and a TODAY card.
    private let pinned: Date?
    /// Claims the day's Festival gift and returns what it paid, or nil when
    /// the store refused. `GameStore.claimEventGift` is the closure the
    /// island and More pass.
    private let onClaim: (GameEvent) -> [ShopService.Grant]?
    /// What the claim paid, as tiles, and which claim showed them.
    @State private var receipt: [ShopService.Grant] = []
    @State private var receiptID = UUID()
    @State private var opened = Date()

    init(now: Date? = nil, onClaim: @escaping (GameEvent) -> [ShopService.Grant]? = { _ in nil }) {
        pinned = now
        self.onClaim = onClaim
    }

    private var now: Date { pinned ?? opened }
    private var events: [GameEvent] { EventCalendar.events(at: now) }
    private var festival: GameEvent? { events.first(where: { $0.kind == .loginGift }) }
    private var cards: [GameEvent] { events.filter { $0.kind != .loginGift } }

    var body: some View {
        NavigationStack {
            GameScreen("Events", subtitle: subtitle, dismiss: { dismiss() }) {
                BarCount(value: weekLabel, systemImage: "calendar", tint: Theme.gold)
                BarWallet(wallet: store.player.wallet)
            } content: {
                VStack(spacing: 10) {
                    if let festival {
                        festivalBand(festival)
                    } else {
                        festivalNotice
                    }
                    weekRow
                    nextLine
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .overlay(alignment: .bottom) {
                    receiptOverlay
                }
            }
        }
        .onAppear { opened = Date() }
    }

    // MARK: - Strip

    /// "Today: Double Drachma" — the events on now, by name.
    private var subtitle: String {
        let names = EventCalendar.active(at: now).filter { $0.kind != .loginGift }.map(\.title)
        return names.isEmpty ? "The week's calendar" : "Today: " + names.joined(separator: " · ")
    }

    /// "Sep 28 – Oct 4", "Oct 5 – 11": the week the cards show, as the
    /// locale writes a span of days. It printed "28 – Oct 4" — the first
    /// date's month dropped — because the day-first pattern it assumed is
    /// month-first in en_US (runs 211 and 216). The interval style puts the
    /// month where the locale wants it and drops a repeated one itself.
    private var weekLabel: String {
        let monday = EventCalendar.weekStart(at: now)
        let sunday = EventCalendar.day(6, after: monday)
        let week = monday..<max(sunday, monday)
        return week.formatted(.interval.month(.abbreviated).day())
    }

    // MARK: - The Festival

    /// The Festival's gift, the login gift's own shape: the name (the rules
    /// behind the ?), the seven days as pips, today's gift painted, the claim.
    /// About 630 of the 726 points an iPhone 16 Pro gives it, 60 tall.
    private func festivalBand(_ festival: GameEvent) -> some View {
        let player = store.player
        let day = EventCalendar.dayIndex(at: now)
        let gifts = EventCalendar.festivalGifts
        let today = EventCalendar.gift(at: now)
        let claimed = EventCalendar.isGiftClaimed(player: player, at: now)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 2) {
                    Text(festival.title.uppercased())
                        .font(Theme.title(13))
                        .tracking(1.2)
                        .foregroundStyle(Theme.goldDim)
                        .lineLimit(1)
                        .fixedSize()
                    InfoDot(title: festival.title) {
                        detailText(festival.blurb)
                    }
                }
                Text("Day \(day + 1) of \(gifts.count)")
                    .font(Theme.numeric(11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            HStack(spacing: 4) {
                ForEach(gifts.indices, id: \.self) { index in
                    let taken = EventCalendar.isGiftClaimed(player: player, at: EventCalendar.day(index, after: festival.start))
                    GiftDayPip(
                        key: ItemArt.key(for: gifts[index]),
                        taken: taken,
                        isToday: index == day,
                        isLast: index == gifts.count - 1,
                        faded: index < day && !taken
                    )
                }
            }
            Spacer(minLength: 8)
            if let today {
                RewardTile(grant: today, size: 44, showsTitle: false)
            }
            ClaimPlate(status: giftStatus(available: today != nil, claimed: claimed)) {
                if let grants = onClaim(festival) { paid(grants) }
            }
            .frame(width: 110)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(MarbleRowPlate(isLit: today != nil && !claimed, radius: Theme.cornerRadius))
    }

    private func giftStatus(available: Bool, claimed: Bool) -> ClaimStatus {
        if claimed { return .done }
        return available ? .ready : .waiting
    }

    /// Outside a Festival week: when the next one is, and its seven gifts as
    /// dim pips — the band's own shape, so the gift is the same object in
    /// both weeks.
    private var festivalNotice: some View {
        let next = EventCalendar.nextFestival(after: now)
        let gifts = EventCalendar.festivalGifts
        return HStack(spacing: 12) {
            // The Festival's painted gift, not its SF glyph (run 216).
            MedallionIcon(key: "", glyph: next.glyph, size: 36, itemKey: "bundle")
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 2) {
                    Text(next.title.uppercased())
                        .font(Theme.title(13))
                        .tracking(1.2)
                        .foregroundStyle(Theme.goldDim)
                        .lineLimit(1)
                        .fixedSize()
                    InfoDot(title: next.title) {
                        detailText(next.blurb)
                    }
                }
                Text("Begins \(next.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))) · in \(span(next.start.timeIntervalSince(now)))")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                ForEach(gifts.indices, id: \.self) { index in
                    GiftDayPip(
                        key: ItemArt.key(for: gifts[index]),
                        taken: false,
                        isToday: false,
                        isLast: index == gifts.count - 1
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(MarbleRowPlate(radius: Theme.cornerRadius))
    }

    // MARK: - The week

    /// Monday to Thursday and the weekend, as one row of cards of one
    /// height that takes the board down to its foot: the Spacer under the
    /// row left 40–55 points of bare cream (run 216). The tallest card (the
    /// Necropolis weekend's four-line name) needs about 180 of the 190 or so
    /// it is given on an iPhone 16 Pro.
    private var weekRow: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(cards) { event in
                eventCard(event)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// One day of the week. Its name at the title floor with no shrink, on
    /// as many lines as it needs — a word never breaks: "HALF-ENERGY" is 104
    /// points and a card's inside is 123 on an iPhone 16 Pro — then one short
    /// line of what it touches; at the foot its multiplier over its clock,
    /// and beside them what it doubles as its painting in a socket (the
    /// drachma, the codex, the energy, the laurels, the Hall's essence, the
    /// relic box) — a faint SF glyph in the corner was the card's only art.
    /// The whole sentence is behind the ?.
    private func eventCard(_ event: GameEvent) -> some View {
        let active = event.isActive(at: now)
        let over = event.end <= now
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Chip(text: event.when.uppercased(), tint: active ? event.color : Theme.goldDim, filled: active)
                    .fixedSize()
                Spacer(minLength: 0)
                InfoDot(title: event.title) {
                    detailText(event.blurb)
                }
                .frame(width: 22, height: 18)
            }
            Text(event.title.uppercased())
                .font(Theme.title(13))
                .tracking(0.6)
                .foregroundStyle(over ? Theme.textSecondary : Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(Self.effect(event.kind))
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            HStack(alignment: .bottom, spacing: 4) {
                // "Ends in 12h" is 57 points and the socket 44: with the
                // spacing they are 105 of the 123 a card has inside.
                VStack(alignment: .leading, spacing: 4) {
                    EventBadge(event: event, compact: true)
                        .opacity(over ? 0.5 : 1)
                    Text(timing(event))
                        .font(Theme.body(11))
                        .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
                Spacer(minLength: 0)
                RewardTile(key: Self.itemKey(event.kind), size: 44, showsTitle: false)
                    .opacity(over ? 0.5 : 1)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(MarbleRowPlate(isLit: active, radius: Theme.tightCorner))
        .overlay(alignment: .top) {
            if active {
                todayTag
                    .offset(y: -9)
            }
        }
        .opacity(over ? 0.72 : 1)
    }

    /// TODAY as a gold tag on the card's top edge. It was a second chip in
    /// the card's first row, which a Wednesday would have cut ("WEDNESDAY"
    /// and "TODAY" are 136 points; the row has 123).
    private var todayTag: some View {
        Text("TODAY")
            .font(Theme.body(11).weight(.heavy))
            .tracking(1.2)
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 18)
            .background(Capsule().fill(Theme.goldPlate))
            .overlay(Capsule().strokeBorder(Color(hex: "#FFE9A8").opacity(0.6), lineWidth: 0.8))
            .shadow(color: Theme.gold.opacity(0.4), radius: 4)
    }

    /// The one line a card keeps: what the event touches, which its name
    /// does not say (the multiplier is the badge under it). Every line is
    /// under the 123 points a card's inside has on an iPhone 16 Pro, measured
    /// in Manrope at 11 (the longest, "Campaign stages only", is 114).
    private static func effect(_ kind: EventKind) -> String {
        switch kind {
        case .doubleDrachma: return "Every stage clear"
        case .doubleExperience: return "Units and your level"
        case .halfEnergyCampaign: return "Campaign stages only"
        case .arenaLaurelsBoost: return "Won or lost"
        case .doubleEssence: return "Every Hall floor"
        case .doubleRelics: return "Two relics a level"
        case .loginGift: return "One gift a day"
        }
    }

    /// The painted thing an event doubles, for its card's socket.
    private static func itemKey(_ kind: EventKind) -> String {
        switch kind {
        case .doubleDrachma: return "drachma"
        case .doubleExperience: return "unit_exp"
        case .halfEnergyCampaign: return "energy"
        case .arenaLaurelsBoost: return "laurels"
        case .doubleEssence(let element): return "essence_\(element.rawValue)_mid"
        case .doubleRelics: return "relic_cache"
        case .loginGift: return "bundle"
        }
    }

    /// Next weekend's headline, so the week can be planned. The Festival's
    /// date is the notice band's above it (a second "Festival in 20 days"
    /// here repeated it, run 216), and in a Festival week the band is the
    /// Festival itself.
    private var nextLine: some View {
        let headline = EventCalendar.nextHeadline(after: now)
        return HStack(spacing: 8) {
            Text("NEXT WEEKEND")
                .font(Theme.title(13))
                .tracking(1.2)
                .foregroundStyle(Theme.goldDim)
                .lineLimit(1)
                .fixedSize()
            EventBadge(event: headline, compact: true)
            Text(headline.title)
                .font(Theme.body(12).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 6)
            Text(timing(headline))
                .font(Theme.body(12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(MarbleRowPlate(radius: Theme.tightCorner))
    }

    // MARK: - Parts

    /// The words behind a ?: the event's whole sentence, in the popover's
    /// ink.
    private func detailText(_ text: String) -> some View {
        Text(text)
            .font(Theme.body(12))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "Ends in 5h", "In 2 days", "Over".
    private func timing(_ event: GameEvent) -> String {
        if event.isActive(at: now) { return "Ends in " + span(event.end.timeIntervalSince(now)) }
        if event.start > now { return "In " + span(event.start.timeIntervalSince(now)) }
        return "Over"
    }

    private func span(_ seconds: TimeInterval) -> String {
        let hours = Int(max(0, seconds) / 3_600)
        if hours >= 48 { return "\(hours / 24) days" }
        if hours >= 1 { return "\(hours)h" }
        return "\(max(1, Int(max(0, seconds) / 60)))m"
    }

    @ViewBuilder
    private var receiptOverlay: some View {
        if !receipt.isEmpty {
            GrantReceipt(title: "Received", grants: receipt, onGlass: false)
                .padding(.bottom, 10)
        }
    }

    /// `ClaimPlate` has already played the confirm and the haptic; this shows
    /// what the gift paid for 2.8 seconds.
    private func paid(_ grants: [ShopService.Grant]) {
        let id = UUID()
        withAnimation(.easeOut(duration: 0.2)) {
            receipt = grants
            receiptID = id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            guard receiptID == id else { return }
            withAnimation(.easeIn(duration: 0.25)) { receipt = [] }
        }
    }
}

extension GameEvent {
    var color: Color { Color(hex: accentHex) }
}

/// An event, small enough for a header or a map's corner: the glyph on the
/// event's colour and its multiplier — "2×", "½", a gift. The island and the
/// chapter map wear one per active event (`EventCalendar.active()`).
struct EventBadge: View {
    let event: GameEvent
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: event.glyph)
                .font(.system(size: compact ? 9 : 11, weight: .black))
            Text(event.multiplierLabel)
                .font(Theme.numeric(compact ? 10.5 : 12))
                .lineLimit(1)
        }
        .foregroundStyle(Theme.readableText(on: event.color))
        .padding(.horizontal, compact ? 5 : 7)
        .frame(height: compact ? Theme.chipHeight : 20)
        .background(
            Capsule().fill(
                LinearGradient(colors: [event.color, event.color.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            )
        )
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
        .shadow(color: event.color.opacity(0.45), radius: 3)
    }
}

/// Every event on now as a row of badges, for a header that has room for
/// more than one — a Festival week runs the day's event and the gift at once.
struct EventBadgeRow: View {
    var at: Date = Date()
    var compact: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            ForEach(EventCalendar.active(at: at)) { event in
                EventBadge(event: event, compact: compact)
            }
        }
    }
}
