import SwiftUI

/// The week's events: what the calendar doubles today, what it doubles next,
/// and the Festival's gift when it is a festival week. Opens from the island
/// and from More, the way Missions does.
///
/// Landscape shape: the strip carries the week's dates and the wallet; the
/// Festival is one band across the top (seven tiles, the day's gift, Claim —
/// the login gift's own band, so the two read as kin); the week is a row of
/// cards, Monday to Thursday and the weekend's headline, the one that is on
/// now lit and stamped TODAY; and one line under it says what next weekend
/// brings and when the Festival is. Nothing here writes the save: the one
/// claim goes through `onClaim`, which the store owns.
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
    @State private var receipt: String?
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
                VStack(spacing: 8) {
                    if let festival {
                        festivalBand(festival)
                    } else {
                        festivalNotice
                    }
                    if let receipt {
                        receiptBanner(receipt)
                    }
                    weekRow
                    nextLine
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, ScreenChrome.contentPadding)
                .padding(.vertical, 8)
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

    /// "21 – 27 Sep": the week the cards show.
    private var weekLabel: String {
        let monday = EventCalendar.weekStart(at: now)
        let sunday = EventCalendar.day(6, after: monday)
        let first = monday.formatted(.dateTime.day())
        let last = sunday.formatted(.dateTime.day().month(.abbreviated))
        return "\(first) – \(last)"
    }

    // MARK: - The Festival

    /// Seven day tiles, the day's gift and the claim, in the login gift's own
    /// band, so the two gifts read as one family.
    private func festivalBand(_ festival: GameEvent) -> some View {
        let player = store.player
        let day = EventCalendar.dayIndex(at: now)
        let gifts = EventCalendar.festivalGifts
        let today = EventCalendar.gift(at: now)
        let claimed = EventCalendar.isGiftClaimed(player: player, at: now)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(festival.title.uppercased())
                    .font(Theme.body(10).weight(.black))
                    .tracking(1.0)
                    .foregroundStyle(Theme.goldDim)
                    .lineLimit(1)
                Text("Day \(day + 1) of \(gifts.count)")
                    .font(Theme.numeric(10.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 4) {
                ForEach(gifts.indices, id: \.self) { index in
                    giftTile(index: index, today: day, festival: festival, gifts: gifts, player: player)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text(today.map(ShopService.describe) ?? "—")
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("A missed day is missed.")
                    .font(Theme.body(10))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            claimButton(title: claimed ? "Claimed" : "Claim", enabled: today != nil && !claimed) {
                if let grants = onClaim(festival) { paid(grants) }
            }
        }
        .padding(8)
        .panelBackground()
    }

    private func giftTile(index: Int, today: Int, festival: GameEvent, gifts: [ShopService.Grant], player: Player) -> some View {
        let number = index + 1
        let date = EventCalendar.day(index, after: festival.start)
        let taken = EventCalendar.isGiftClaimed(player: player, at: date)
        let isToday = index == today
        return VStack(spacing: 2) {
            ItemIcon(key: ItemArt.key(for: gifts[index]), size: 16,
                     tint: taken ? Theme.ink : (isToday ? Theme.gold : Theme.textSecondary), glow: false)
            Text("\(number)")
                .font(Theme.numeric(10.5))
                .foregroundStyle(taken ? Theme.ink : Theme.textSecondary)
        }
        .frame(width: 34, height: 36)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(taken ? Theme.gold : (isToday ? Theme.surfaceHigh : Theme.surface))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(isToday ? Theme.gold : Theme.stroke, lineWidth: 1)
        )
    }

    /// Outside a Festival week: when the next one is, and its seven gifts dim.
    private var festivalNotice: some View {
        let next = EventCalendar.nextFestival(after: now)
        return HStack(spacing: 10) {
            Image(systemName: next.glyph)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(Theme.gold)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(next.title.uppercased())
                    .font(Theme.body(10).weight(.black))
                    .tracking(1.0)
                    .foregroundStyle(Theme.goldDim)
                    .lineLimit(1)
                Text("A gift every day, from \(next.start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))) — in \(span(next.start.timeIntervalSince(now))).")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 6)
            HStack(spacing: 4) {
                ForEach(EventCalendar.festivalGifts.indices, id: \.self) { index in
                    ItemIcon(key: ItemArt.key(for: EventCalendar.festivalGifts[index]), size: 16,
                             tint: Theme.textSecondary, glow: false)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.surface))
                }
            }
        }
        .padding(8)
        .panelBackground()
    }

    // MARK: - The week

    /// Monday to Thursday and the weekend, as one row of cards.
    private var weekRow: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(cards) { event in
                eventCard(event)
            }
        }
    }

    private func eventCard(_ event: GameEvent) -> some View {
        let active = event.isActive(at: now)
        let over = event.end <= now
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Chip(text: event.when.uppercased(), tint: active ? event.color : Theme.goldDim, filled: active)
                Spacer(minLength: 0)
                if active {
                    Chip(text: "TODAY", tint: Theme.gold, filled: true)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: event.glyph)
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(over ? Theme.textSecondary : event.color)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(event.color.opacity(over ? 0.08 : 0.16)))
                Text(event.title.uppercased())
                    .font(Theme.title(12))
                    .tracking(0.6)
                    .foregroundStyle(over ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(event.blurb)
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                EventBadge(event: event, compact: true)
                    .opacity(over ? 0.5 : 1)
                Text(timing(event))
                    .font(Theme.body(10))
                    .foregroundStyle(active ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(active ? Theme.surfaceHigh : Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .strokeBorder(active ? Theme.gold : Theme.stroke, lineWidth: active ? 1.5 : 0.5)
        )
        .opacity(over ? 0.72 : 1)
    }

    /// Next weekend's headline and the Festival, so the week can be planned.
    private var nextLine: some View {
        let headline = EventCalendar.nextHeadline(after: now)
        let festival = EventCalendar.nextFestival(after: now)
        return HStack(spacing: 8) {
            Text("NEXT WEEKEND")
                .font(Theme.body(10).weight(.black))
                .tracking(1.0)
                .foregroundStyle(Theme.goldDim)
            EventBadge(event: headline, compact: true)
            Text(headline.title)
                .font(Theme.body(11).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if !festival.isActive(at: now) {
                Image(systemName: festival.glyph)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Theme.gold)
                Text("Festival in \(span(festival.start.timeIntervalSince(now)))")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(Theme.surface)
        )
    }

    // MARK: - Parts

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

    private func receiptBanner(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.success)
            Text(text)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(Theme.success.opacity(0.12))
        )
    }

    private func claimButton(title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(11).weight(.bold))
                .foregroundStyle(enabled ? Theme.ink : Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(enabled ? Theme.gold : Theme.surface))
        }
        .disabled(!enabled)
    }

    private func paid(_ grants: [ShopService.Grant]) {
        AudioLibrary.shared.play(.uiConfirm)
        Juice.haptic(.light)
        receipt = "Received " + grants.map(ShopService.describe).joined(separator: ", ") + "."
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
