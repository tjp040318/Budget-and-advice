import SwiftUI

/// A unit the player does not own yet, as a face.
///
/// `UnitCard` takes a `ResolvedUnit` — a unit that exists, with a level and
/// relics — and the two screens below are about units that do NOT exist yet,
/// so they draw the blueprint: the portrait in its grade's frame, the element
/// badge and the star row, and nothing that only an owned unit has.
struct BlueprintPortrait: View {
    let blueprint: UnitBlueprint
    var size: CGFloat = 74

    private var rarity: Rarity { Rarity(stars: blueprint.naturalStars) }

    var body: some View {
        VStack(spacing: 3) {
            BundleImage(name: blueprint.model.portraitName(awakened: false), renderedAt: size)
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(alignment: .topLeading) {
                    ElementBadge(element: blueprint.element, compact: true, scale: max(0.6, min(1, size / 80)))
                        .padding(4)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(rarity.frame, lineWidth: rarity.frameWidth)
                )
            StarRow(stars: blueprint.naturalStars, size: max(7, size / 9))
        }
    }
}

/// The mileage exchange: the banner's own pool, priced in points, and a unit
/// the player NAMES.
///
/// It lives inside the banner rather than in the bazaar because the points do:
/// they are earned on this banner and spent on this banner's pool, which is
/// Blue Archive's Recruitment Point shop and the reason that shop reads as a
/// promise rather than a second currency to manage.
struct MileageSheet: View {
    let banner: Banner
    /// The unit handed over, so the summon screen can play the reveal.
    var onRedeem: (SummonResult) -> Void

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss

    /// Four across a landscape phone. A card and its price want about 150
    /// points; the adaptive minimum lets a narrow phone drop to three rather
    /// than clipping the fourth.
    private static let columns = [GridItem(.adaptive(minimum: 138, maximum: 210), spacing: 8)]

    private var points: Int { MileageService.points(on: banner, player: store.player) }
    /// The whole board, dearest first — the catalogue's own order, and what
    /// the header's target is read off.
    private var offers: [MileageService.Offer] { MileageService.catalogue(for: banner) }

    /// What the grid actually draws: **what you can take, first.**
    ///
    /// Run 153's frame is why. The catalogue is sorted dearest-first so the
    /// thing a player is saving for is the headline — and with 122 units in
    /// the Duat's pool that filled the entire first screen with 5★s at 153
    /// points and "35 MORE" under every one of them. A shop whose first
    /// screenful is nothing you can buy reads as a wall, not an offer. The
    /// affordable band comes first now, dearest within it, and the
    /// aspirational tail follows in the catalogue's own order underneath.
    private var sortedOffers: [MileageService.Offer] {
        let all = offers
        return all.filter { points >= $0.price } + all.filter { points < $0.price }
    }

    /// How many are within reach right now, for the band's own header.
    private var affordableCount: Int { offers.filter { points >= $0.price }.count }

    /// The dearest thing on the board, so the header can say how far off it is.
    private var target: MileageService.Offer? { offers.first }

    var body: some View {
        NavigationStack {
            GameScreen(
                "Mileage",
                subtitle: banner.title,
                dismiss: { dismiss() }
            ) {
                BarCount(value: "\(points)", systemImage: "ticket.fill", tint: Theme.gold)
                BarCount(value: "\(offers.count)", systemImage: "person.3.fill")
            } content: {
                VStack(spacing: 6) {
                    explanation
                    ScrollView {
                        LazyVGrid(columns: Self.columns, spacing: 8) {
                            ForEach(sortedOffers) { offer in
                                tile(offer)
                            }
                        }
                        .padding(.horizontal, ScreenChrome.contentPadding)
                        .padding(.bottom, 10)
                    }
                }
            }
        }
    }

    /// One sentence and one number. A points system whose rate is not printed
    /// is a points system the player does not believe in.
    private var explanation: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("One point for every summon on this banner. Points are never lost and never expire.")
                .font(Theme.body(11))
                .foregroundStyle(Theme.textPrimary)
            if let target {
                Text(affordableCount > 0
                     ? "\(affordableCount) within reach, shown first. \(target.price - points) more for \(target.blueprint.name)."
                     : "\(target.price - points) more for \(target.blueprint.name).")
                    .font(Theme.numeric(11))
                    .foregroundStyle(points >= target.price ? Theme.success : Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ScreenChrome.contentPadding)
        .padding(.top, 6)
    }

    private func tile(_ offer: MileageService.Offer) -> some View {
        let affordable = points >= offer.price
        return VStack(spacing: 5) {
            BlueprintPortrait(blueprint: offer.blueprint, size: 74)
            Text(offer.blueprint.name)
                .font(Theme.body(11).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Button { redeem(offer) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "ticket.fill")
                        .font(.system(size: 10, weight: .black))
                    Text("\(offer.price)")
                        .font(Theme.numeric(11))
                    Spacer(minLength: 4)
                    Text(affordable ? "TAKE" : "\(offer.price - points) MORE")
                        .font(Theme.body(9).weight(.black))
                        .tracking(0.7)
                        .lineLimit(1)
                }
                .foregroundStyle(affordable ? Theme.ink : Theme.textSecondary)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 24)
                .background(
                    // Gradient or colour: a Group, never a ternary.
                    Group {
                        if affordable {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.goldPlate)
                        } else {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.surface)
                        }
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(affordable ? Color.clear : Theme.stroke, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .disabled(!affordable)
        }
        .padding(8)
        .panelBackground(radius: Theme.tightCorner)
        .opacity(affordable ? 1 : 0.8)
    }

    private func redeem(_ offer: MileageService.Offer) {
        guard let result = store.redeemMileage(offer, on: banner) else { return }
        AudioLibrary.shared.play(.uiConfirm)
        Juice.haptic(.medium)
        dismiss()
        onRedeem(result)
    }
}

/// The opening selector: five faces, one choice, before the dice get a vote.
///
/// Epic Seven's Selective Summon is credited as one of its biggest free-to-play
/// improvements, and the point of it is not the unit — it is that the first
/// thing a player does in a gacha is a CHOICE, so the first real face in his
/// collection is one he wanted rather than one he was dealt.
struct SelectorSheet: View {
    var onChoose: (SummonResult) -> Void

    @EnvironmentObject private var store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var picked: String?

    private var candidates: [UnitBlueprint] { SelectorService.candidates() }
    private var chosen: UnitBlueprint? { candidates.first { $0.id == picked } }

    var body: some View {
        NavigationStack {
            GameScreen(
                "Choose your first",
                subtitle: "One 4★ of the Duat, yours to name",
                dismiss: { dismiss() }
            ) {
                BarCount(value: "\(candidates.count)", systemImage: "person.3.fill", tint: Theme.gold)
            } content: {
                VStack(spacing: 8) {
                    Text("The circle owes every demigod one soul it did not choose for him. Pick the one you want; the rest of the roster is still out there.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, ScreenChrome.contentPadding)
                        .padding(.top, 6)

                    HStack(spacing: 10) {
                        ForEach(candidates) { blueprint in
                            card(blueprint)
                        }
                    }
                    .padding(.horizontal, ScreenChrome.contentPadding)

                    Spacer(minLength: 0)

                    PrimaryButton(
                        title: chosen.map { "Take \($0.name)" } ?? "Pick one",
                        systemImage: "hand.tap.fill",
                        isEnabled: chosen != nil
                    ) {
                        take()
                    }
                    .frame(width: 280)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    private func card(_ blueprint: UnitBlueprint) -> some View {
        let isPicked = picked == blueprint.id
        return Button {
            Juice.haptic(.light)
            picked = blueprint.id
        } label: {
            VStack(spacing: 5) {
                BlueprintPortrait(blueprint: blueprint, size: 108)
                Text(blueprint.name)
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(isPicked ? Theme.surfaceHigh : Theme.surface.opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .strokeBorder(isPicked ? Theme.gold : Theme.stroke, lineWidth: isPicked ? 2 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private func take() {
        guard let chosen, let result = store.claimSelector(chosen) else { return }
        AudioLibrary.shared.play(.uiConfirm)
        Juice.haptic(.medium)
        dismiss()
        onChoose(result)
    }
}
