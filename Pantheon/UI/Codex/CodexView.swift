import SwiftUI

/// The Codex: the collection book (2026-09-23; Docs/CODEX.md).
///
/// Every family of every live pantheon in its five element forms, the forms
/// the player has ever owned lit and the rest in shadow, a small reward for
/// every new page and a prize at a quarter, a half, three quarters and the
/// whole of a pantheon. The genre's book is Summoners War's Monster
/// Collection (every monster by element, the owned ones lit, the awakened
/// form beside the plain one) and Epic Seven's Hero Collection; Raid's
/// Champion Index files its book by faction, which is what a pantheon is
/// here.
///
/// A PLACE, so the house's glass over art: each pantheon's pages stand in its
/// own realm's painting (`CodexArt.painting(for:)`), the pantheons a glass
/// rail down the left with a meter and a count each, the realm's name carved
/// over its milestone track, and the table on dark glass — a row per family,
/// its five forms in the element order every column keeps (ember, tide,
/// gale, radiance, umbra), so a family's completion reads across a row and
/// an element's down a column. Forms or Awakened in the strip turns the
/// table to the awakened faces. A tap on a form opens its page; a reward is
/// claimed there, or every waiting one at once with the strip's Claim.
///
/// Measured for an iPhone 16 Pro in landscape, a sheet's content box of
/// 750 × 329: the rail 176 (five rows of 50 stand whole, unscrolled, above
/// its fade); the room 574, its header 48 (the carved realm and the track
/// side by side) and the table 259 under it. Four families of 54 points (a
/// 48-point card and 6) with the list's 6 over them and 4 between end at
/// 234, clear of the 16-point foot fade that starts at 243; the fifth rests
/// below the fold with the glass's chevron. An iPhone 16 gives the table
/// 250, and its fade starts at exactly 234.
struct CodexView: View {
    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    @State private var shownPantheon: Pantheon
    @State private var showsAwakened: Bool
    @State private var codexPath: NavigationPath
    /// What the last claim paid, as tiles, for a moment.
    @State private var bookReceipt: [ShopService.Grant] = []
    @State private var bookReceiptID = UUID()
    /// A tier marker's prize and what it still asks, for a moment.
    @State private var tierNote: String?
    @State private var tierNoteID = UUID()
    /// The table (a pantheon and a face) last opened on its waiting row, so
    /// coming back from a page leaves the list where the player left it.
    @State private var tableOpenedOn: String?

    /// `pantheon` opens the book on a pantheon, `awakened` on the awakened
    /// faces, and `page` with a form's page already open over it — the
    /// tour's second frame (`-tour-codex-page anubis_ember`).
    init(opening pantheon: Pantheon? = nil, awakened: Bool = false, page: CodexPageRequest? = nil) {
        let pageRealm = page.flatMap { CodexService.family(key: $0.familyKey)?.pantheon }
        _shownPantheon = State(initialValue: pantheon ?? pageRealm ?? CodexService.pantheons.first ?? .egyptian)
        _showsAwakened = State(initialValue: awakened)
        var path = NavigationPath()
        if let page { path.append(page) }
        _codexPath = State(initialValue: path)
    }

    // MARK: - The room's measures

    private static let railWidth: CGFloat = 176
    /// A form's card in the table: 48, the smallest size at which a face
    /// keeps its large marks (the element badge in its corner and the stars
    /// along its foot — `UnitPortraitTile` switches to its small layout
    /// under 48), and the largest at which four rows rest whole on an
    /// iPhone 16.
    private static let cell: CGFloat = 48
    private static let rowGap: CGFloat = 4
    /// The family's name column: "TERRACOTTA SOLDIER", the roster's widest
    /// name, is 170 points of Cinzel at 13 with its tracking, and the line
    /// under it — the stars, "0/5" and the role — about 140. 190 with the
    /// five cards at 8 apart is 474 of the table's 530, where the first cut
    /// (176 and 6) left 80 points of bare glass at the right.
    private static let nameColumn: CGFloat = 190
    private static let trackWidth: CGFloat = 276

    // MARK: - The screen

    var body: some View {
        // Read once per pass: the ledger walks the roster and the claims.
        let book = CodexService.ledger(for: store.player)
        let whole = CodexService.progress(of: nil, ledger: book)
        let waiting = CodexService.readyCount(of: nil, ledger: book)

        NavigationStack(path: $codexPath) {
            GameScreen("Codex", subtitle: "\(whole.recorded) of \(whole.total) recorded", dismiss: { dismiss() }) {
                BarSegments(options: [(value: false, title: "Forms"), (value: true, title: "Awakened")],
                            selection: $showsAwakened)
                if waiting > 0 {
                    BarButton(title: "Claim \(waiting)", systemImage: "gift.fill") {
                        claimEverything()
                    }
                }
                BarWallet(wallet: store.player.wallet, shows: [.divinity])
            } content: {
                ZStack(alignment: .topLeading) {
                    PlaceBackdrop(
                        painting: CodexArt.painting(for: shownPantheon),
                        focus: CodexArt.focus(for: shownPantheon),
                        wash: CodexArt.wash(for: shownPantheon)
                    )
                    .animation(.easeInOut(duration: 0.35), value: shownPantheon)
                    // Seed 953: one seed per screen keeps two places from
                    // sharing a sky (`PlaceAmbience`).
                    PlaceAmbience(shafts: [], motes: 14, moteColor: CodexArt.moteColor, seed: 953)
                    HStack(spacing: 0) {
                        pantheonRail(book)
                        room(book)
                    }
                }
                .overlay(alignment: .bottom) {
                    if !bookReceipt.isEmpty {
                        GrantReceipt(title: "Recorded", grants: bookReceipt, onGlass: true)
                            .padding(.bottom, 12)
                    }
                }
            }
            .navigationDestination(for: CodexPageRequest.self) { request in
                CodexPageView(request: request)
            }
        }
        .onAppear { warmCards() }
        .onChange(of: shownPantheon) { _, _ in warmCards() }
        .onChange(of: showsAwakened) { _, _ in warmCards() }
    }

    // MARK: - The rail

    /// The five pantheons, each with its share recorded and the gold mark
    /// while anything of it waits to be claimed.
    private func pantheonRail(_ book: CodexLedger) -> some View {
        PlaceRail(width: Self.railWidth) {
            ForEach(CodexService.pantheons) { pantheon in
                CodexPantheonRow(
                    pantheon: pantheon,
                    progress: CodexService.progress(of: pantheon, ledger: book),
                    waiting: CodexService.readyCount(of: pantheon, ledger: book) > 0,
                    isOn: pantheon == shownPantheon
                ) {
                    withAnimation(.easeOut(duration: 0.2)) { shownPantheon = pantheon }
                    tierNote = nil
                }
                .restingRow(goneBelow: 0.85, wholeFrom: 0.98)
            }
        }
    }

    // MARK: - The room

    /// The realm's name carved over its track, then its table.
    private func room(_ book: CodexLedger) -> some View {
        let reading = CodexService.progress(of: shownPantheon, ledger: book)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                PlaceTitle(eyebrow: "\(shownPantheon.displayName) · \(reading.percent)%",
                           title: shownPantheon.realmName, size: 22)
                Spacer(minLength: 6)
                CodexTierTrack(progress: reading, standings: tierStandings(book)) { tier in
                    tapTier(tier, book: book)
                }
                .frame(width: Self.trackWidth)
            }
            table(book)
                .overlay(alignment: .top) { noteOverlay }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// The pantheon's families, the rarest first, on dark glass; in Awakened,
    /// the families with an awakened face. Rests on whole rows
    /// (`RestingList`), and opens — on every new pantheon or face — on the
    /// first family with a page waiting (`openingRow`).
    private func table(_ book: CodexLedger) -> some View {
        let kind: CodexFormKind = showsAwakened ? .awakened : .base
        let rows = CodexService.familyRows(of: shownPantheon).filter { kind == .base || $0.awakenable }
        let opening = Self.openingRow(rows, kind: kind, book: book)
        let identity = shownPantheon.rawValue + (showsAwakened ? "_awakened" : "_forms")
        return ScrollViewReader { proxy in
            RestingList(onGlass: true) {
                LazyVStack(alignment: .leading, spacing: Self.rowGap) {
                    ForEach(rows) { family in
                        CodexFamilyRow(family: family, kind: kind, ledger: book,
                                       cell: Self.cell, nameWidth: Self.nameColumn) { element in
                            codexPath.append(CodexPageRequest(familyKey: family.key, element: element, kind: kind))
                        }
                        .id(family.key)
                        .restingRow()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, RowRest.footFade + 4)
            }
            .onAppear {
                // Once per table: a page popped off the stack brings the
                // book back into view, and it must not jump.
                guard tableOpenedOn != identity else { return }
                tableOpenedOn = identity
                if let opening { proxy.scrollTo(opening, anchor: .top) }
            }
        }
        .id(identity)
        .background(GlassPlate(radius: Theme.tightCorner + 4, opacity: 0.72))
    }

    /// The row the table opens on: the first family with a page waiting to
    /// be claimed, else the first with anything recorded, else the top. The
    /// book files the rarest first, so a young save's Egypt opened on four
    /// rows of 5★ shadows with every face it owned below the fold (the
    /// mock of 2026-09-23); now it opens on what the player has.
    private static func openingRow(_ rows: [CodexFamily], kind: CodexFormKind, book: CodexLedger) -> String? {
        let waiting = rows.first { family in
            Element.allCases.contains { element in
                family.entry(element, kind).map { book.standing($0) == .ready } ?? false
            }
        }
        if let waiting { return waiting.key }
        let held = rows.first { family in
            Element.allCases.contains { element in
                family.entry(element, kind).map { book.isRecorded($0) } ?? false
            }
        }
        return held?.key
    }

    /// A tier marker's words, over the table's head.
    @ViewBuilder
    private var noteOverlay: some View {
        if let tierNote {
            GlassCapsule {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Theme.onGlassGold)
                Text(tierNote)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.onGlass)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.top, 6)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Claims

    private func tierStandings(_ book: CodexLedger) -> [CodexTier: CodexStanding] {
        var standings: [CodexTier: CodexStanding] = [:]
        for tier in CodexTier.allCases {
            standings[tier] = CodexService.tierStanding(tier, of: shownPantheon, ledger: book)
        }
        return standings
    }

    /// A reached marker pays; any other says what it holds and what it asks.
    private func tapTier(_ tier: CodexTier, book: CodexLedger) {
        let standing = CodexService.tierStanding(tier, of: shownPantheon, ledger: book)
        if standing == .ready {
            guard let paid = store.claimCodexTier(tier, of: shownPantheon) else { return }
            Juice.haptic(.medium)
            AudioLibrary.shared.play(.uiConfirm)
            showReceipt(CodexService.merged(paid))
            return
        }
        Juice.haptic(.light)
        AudioLibrary.shared.play(.uiTap)
        let prize = CodexService.prizeWords(for: tier)
        if standing == .claimed {
            showNote("\(tier.rawValue)%: \(prize) · claimed")
        } else {
            let needed = CodexService.recordsNeeded(for: tier, of: shownPantheon, ledger: book)
            showNote("\(tier.rawValue)%: \(prize) · \(needed) more to record")
        }
    }

    /// The strip's Claim: every waiting page and tier in the book at once.
    private func claimEverything() {
        let paid = store.claimAllCodexRewards()
        guard !paid.isEmpty else { return }
        Juice.haptic(.medium)
        AudioLibrary.shared.play(.uiConfirm)
        showReceipt(paid)
    }

    /// What a claim paid, as the genre's strip of tiles for 2.8 seconds.
    private func showReceipt(_ grants: [ShopService.Grant]) {
        let id = UUID()
        withAnimation(.easeOut(duration: 0.2)) {
            bookReceipt = grants
            bookReceiptID = id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            guard bookReceiptID == id else { return }
            withAnimation(.easeIn(duration: 0.25)) { bookReceipt = [] }
        }
    }

    private func showNote(_ words: String) {
        let id = UUID()
        withAnimation(.easeOut(duration: 0.2)) {
            tierNote = words
            tierNoteID = id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            guard tierNoteID == id else { return }
            withAnimation(.easeIn(duration: 0.25)) { tierNote = nil }
        }
    }

    // MARK: - Warming

    /// Decodes the pantheon's cards at the table's size off the main thread,
    /// so the first pass over a pantheon's hundred-odd faces draws from the
    /// cache (`BundleArt.warmThumbnails`, the Arena's cure). A whole-figure
    /// card is decoded at its zoom (`PortraitPainting.zoom`), as it is drawn.
    private func warmCards() {
        let kind: CodexFormKind = showsAwakened ? .awakened : .base
        var names: [String] = []
        for family in CodexService.familyRows(of: shownPantheon) {
            for element in Element.allCases {
                if let page = family.entry(element, kind), let name = CodexArt.portrait(for: page) {
                    names.append(name)
                }
            }
        }
        let figures = names.filter { PortraitPainting.isFullFigure($0) }
        let busts = names.filter { !PortraitPainting.isFullFigure($0) }
        let scale = UIScreen.main.scale
        let bustPixels = Int((Self.cell * scale).rounded(.up))
        let figurePixels = Int((Self.cell * PortraitPainting.zoom * scale).rounded(.up))
        Task.detached(priority: .userInitiated) {
            BundleArt.warmThumbnails(busts, maxPixel: bustPixels)
            BundleArt.warmThumbnails(figures, maxPixel: figurePixels)
        }
    }
}
