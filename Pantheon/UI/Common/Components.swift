import SwiftUI
import UIKit

/// Star grade. Grades above the natural rating are shown in bright gold so an
/// evolved unit reads differently from a naturally high one.
///
/// Stars are drawn twice: a dark, slightly larger star behind a gold-gradient
/// one. Without the dark pass they disappear against a pale portrait, which is
/// exactly where they matter most.
struct StarRow: View {
    let stars: Int
    var natural: Int? = nil
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: size * 0.06) {
            ForEach(Array(0..<max(1, stars)), id: \.self) { index in
                star(evolved: isEvolved(index))
            }
        }
    }

    private func star(evolved: Bool) -> some View {
        Image(systemName: "star.fill")
            .font(.system(size: size, weight: .black))
            .foregroundStyle(
                evolved
                    ? LinearGradient(colors: [Color(hex: "#FFF3C4"), Theme.gold,
                                              Color(hex: "#C9992F")],
                                     startPoint: .top, endPoint: .bottom)
                    : LinearGradient(colors: [Theme.goldDim, Theme.goldDeep],
                                     startPoint: .top, endPoint: .bottom)
            )
            .shadow(color: .black.opacity(0.85), radius: 0.5, x: 0, y: 0.5)
            .shadow(color: evolved ? Theme.gold.opacity(0.6) : .clear, radius: 3)
    }

    private func isEvolved(_ index: Int) -> Bool {
        guard let natural else { return true }
        return index >= natural
    }
}

/// Element chip — glyph plus name, tinted.
struct ElementBadge: View {
    let element: Element
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: element.glyph)
                .font(.system(size: compact ? 10 : 12, weight: .black))
            if !compact {
                Text(element.displayName.uppercased())
                    .font(Theme.body(10).weight(.black))
                    .tracking(0.6)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.7), radius: 1, x: 0, y: 0.5)
        .padding(.horizontal, compact ? 5 : 8)
        .padding(.vertical, compact ? 3 : 4)
        .background(
            Capsule().fill(
                LinearGradient(
                    colors: [element.color, element.color.opacity(0.55)],
                    startPoint: .top, endPoint: .bottom
                )
            )
        )
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75)
        )
        .shadow(color: element.color.opacity(0.55), radius: 4)
    }
}

/// Horizontal bar with a label, used for HP, XP and progress.
struct StatBar: View {
    let value: Double
    let maximum: Double
    var tint: Color = Theme.success
    var height: CGFloat = 6
    var label: String? = nil

    private var fraction: Double {
        maximum > 0 ? min(1, max(0, value / maximum)) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let label {
                HStack {
                    Text(label)
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(Int(value)) / \(Int(maximum))")
                        .font(Theme.numeric(11))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // A recessed track: a shade darker than the marble, with a
                    // darker rim. The bar has to look like a channel cut into
                    // the panel, or the fill reads as a floating coloured pill
                    // — and an ink channel on a cream panel read as a black
                    // stripe, the old interface showing through every bar.
                    Capsule().fill(Theme.stroke.opacity(0.7))
                    Capsule().strokeBorder(Theme.goldDeep.opacity(0.35), lineWidth: 1)

                    Capsule()
                        .fill(LinearGradient(
                            colors: [tint.opacity(0.95), tint, tint.opacity(0.65)],
                            startPoint: .top, endPoint: .bottom
                        ))
                        .overlay(
                            // Specular line along the top of the fill.
                            Capsule()
                                .fill(Color.white.opacity(0.4))
                                .frame(height: max(1, height * 0.28))
                                .padding(.horizontal, height * 0.3)
                                .frame(maxHeight: .infinity, alignment: .top)
                                .padding(.top, height * 0.16)
                        )
                        .frame(width: max(0, geometry.size.width * fraction))
                        .shadow(color: tint.opacity(0.7), radius: 3)
                }
            }
            .frame(height: height)
        }
    }
}

/// The top-of-screen resource strip.
struct WalletBar: View {
    let wallet: Wallet

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                resource(icon: "bolt.fill", value: "\(wallet.energy)/\(wallet.maxEnergy)", tint: Theme.info)
                if wallet.energy < wallet.maxEnergy {
                    // Minutes and seconds to the next point of energy.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(countdown(at: context.date))
                            .font(Theme.numeric(10))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            divider
            resource(icon: "sparkles", value: "\(wallet.divinity)", tint: Theme.gold)
            divider
            resource(icon: "circle.hexagongrid.fill", value: compact(wallet.drachma), tint: Theme.textPrimary)
            divider
            resource(icon: "laurel.leading", value: "\(wallet.laurels)", tint: Theme.success)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule().fill(
                LinearGradient(colors: [Theme.surfaceHigh, Theme.surface],
                               startPoint: .top, endPoint: .bottom)
            )
        )
        .overlay(Capsule().strokeBorder(Theme.goldPlate, lineWidth: 1))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.6), radius: 6, y: 3)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.stroke.opacity(0.7))
            .frame(width: 1, height: 12)
    }

    private func resource(icon: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(tint)
                .shadow(color: tint.opacity(0.8), radius: 3)
            Text(value)
                .font(Theme.numeric(12))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    /// Time to the next energy: the store restores one every five minutes
    /// from `lastEnergyTick`, so the remainder of the current interval is it.
    private func countdown(at now: Date) -> String {
        let interval: TimeInterval = 5 * 60
        let elapsed = max(0, now.timeIntervalSince(wallet.lastEnergyTick))
        let remaining = interval - elapsed.truncatingRemainder(dividingBy: interval)
        return String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60)
    }

    private func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 10_000...: return "\(value / 1_000)K"
        default: return "\(value)"
        }
    }
}

/// A bundle image by name, resolved through UIKit.
///
/// On device, SwiftUI's `Image("portrait_anubis_ember")` drew nothing and logged
/// "No image named 'portrait_anubis_ember' found in asset catalog", while
/// `UIImage(named:)` on the same name found the file: every portrait in this
/// project is a loose PNG in the bundle rather than an asset-catalogue entry.
/// So every bundle image is looked up here, through UIKit, and handed to
/// SwiftUI already loaded. `resizable()` is applied; add the aspect ratio and
/// frame at the call site.
struct BundleImage: View {
    let name: String
    /// How large this is actually drawn, in POINTS. Given one, the painting is
    /// decoded at that size instead of at its full 1024 pixels.
    ///
    /// This is the Arena's lag. A portrait is a 1024-pixel painting and a
    /// full decode is a four-megabyte bitmap however small it is drawn; the
    /// Arena puts about thirty-five cards on screen at 38 points, which came
    /// to something like a hundred and forty megabytes decoded on the main
    /// thread. Passing the drawn size turns each of those into a 128-pixel
    /// thumbnail — sixty-five kilobytes, sixty-four times less.
    ///
    /// Nil means the whole picture, which is right for a banner, a backdrop
    /// or the summon reveal's card and wrong for anything in a list.
    var renderedAt: CGFloat? = nil

    private var image: UIImage? {
        guard let renderedAt else { return BundleArt.image(name) }
        // Points to pixels on the densest screen the app runs on. Asking for
        // more than the file holds is harmless — the bucket is capped.
        let pixels = Int((renderedAt * UIScreen.main.scale).rounded(.up))
        return BundleArt.thumbnail(name, maxPixel: max(1, pixels))
    }

    var body: some View {
        if let image {
            Image(uiImage: image).resizable()
        }
    }

    static func exists(_ name: String) -> Bool { BundleArt.exists(name) }
}
/// The portrait tile used everywhere a unit appears in a list or a team slot.
///
/// The frame carries the star grade. That is deliberate and it is the main
/// thing this component is for: a player should be able to pick their one
/// 5★ out of a grid of sixty without reading anything.
struct UnitCard: View {
    let unit: ResolvedUnit
    var isSelected: Bool = false
    var showPower: Bool = true
    var size: CGFloat = 76

    private var rarity: Rarity { Rarity(stars: unit.stars) }

    /// The carved frame texture is for the big cards only — the unit sheet's,
    /// the reveal's. On a 76-point grid card its corner scrolls covered a
    /// quarter of the painting and its bottom bar was drawn OVER the star
    /// row, gold on gold: the owner's team screen, 2026-09-12 — "why can I
    /// not see how many stars the mon has. Maybe the borders are excessive if
    /// it blocks the picture + stars." Under this size the card wears the
    /// thin metal stroke of its grade instead.
    static let paintedFrameFrom: CGFloat = 90

    private var showsPaintedFrame: Bool { size >= Self.paintedFrameFrom && rarity.hasPaintedFrame }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                // Bounds the stack to the card whatever the art's aspect. An
                // `.aspectRatio(.fill)` image reports the size it needs to
                // cover the square, so a 3:4 portrait would make this ZStack
                // 127 points tall inside a 76-point card and carry the element
                // badge and the star row out of the clip with it. Every
                // portrait_<id> in the bundle is 1024² today, so it changes
                // nothing now; it is what keeps this component art-proof.
                portrait
                    .frame(width: size, height: size)

                // Darkens the lower third so the star row and name always have
                // something to sit on, whatever the art behind them is doing.
                LinearGradient(
                    colors: [.clear, .clear, Theme.ink.opacity(0.85)],
                    startPoint: .top, endPoint: .bottom
                )

                // The carved frame, UNDER the badges and the stars: as an
                // overlay on the whole card it hid the star row.
                if showsPaintedFrame {
                    paintedFrame
                }

                VStack(alignment: .leading, spacing: 3) {
                    ElementBadge(element: unit.element, compact: true)
                    if unit.unit.isAwakened {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(Theme.gold)
                            .shadow(color: Theme.gold.opacity(0.9), radius: 4)
                    }
                }
                .padding(5)

                VStack(alignment: .trailing, spacing: 3) {
                    if unit.unit.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.textPrimary.opacity(0.9))
                            .shadow(color: .black, radius: 2)
                    }
                    // A unit with a leader skill wears a crown, the genre's
                    // mark for it, so the leader is picked off the grid
                    // rather than found by tapping every card ("how do I
                    // know leader skills if there's no symbol for it on the
                    // character?", the owner, 2026-09-12).
                    if unit.blueprint.leaderSkill != nil {
                        Image(systemName: "crown.fill")
                            .font(.system(size: max(8, size * 0.13), weight: .black))
                            .foregroundStyle(Theme.gold)
                            .shadow(color: .black.opacity(0.9), radius: 2)
                    }
                }
                .padding(5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)

                // The grade, the way the genre shows it: a row of stars big
                // enough to count, on a dark band, at the foot of the card.
                // They were 8-point gold stars laid straight on the art over
                // the gold frame, and the owner could not read a grade off
                // his collection.
                StarRow(stars: unit.stars, natural: unit.blueprint.naturalStars,
                        size: max(9, size * 0.135))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.ink.opacity(0.74)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 4)

                // The sheen is a repeating animation, and a repeating
                // animation is a card that never stops re-rendering: the
                // Arena draws thirty-five cards at 38 points, a dozen of
                // them 5★, and the phone's watchdog measured two seconds
                // of main thread on the way in. At that size the sheen is
                // not visible anyway; it stays on the cards big enough to
                // show it.
                if rarity.hasSheen, size >= 60 {
                    Sheen(cornerRadius: Theme.tightCorner)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))

            VStack(spacing: 0) {
                Text(unit.name)
                    .font(Theme.body(10).weight(.heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 4) {
                    Text("Lv.\(unit.level)")
                        .font(Theme.numeric(9))
                        .foregroundStyle(Theme.textSecondary)
                    if showPower {
                        Text("\(unit.power)")
                            .font(Theme.numeric(9))
                            .foregroundStyle(Theme.gold)
                    }
                }
            }
            .padding(.top, 3)
            .padding(.horizontal, 3)
            .padding(.bottom, 4)
            .frame(width: size)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(LinearGradient(colors: [Theme.surfaceRaised, Theme.surface],
                                     startPoint: .top, endPoint: .bottom))
        )
        .rarityFrame(rarity, radius: Theme.tightCorner, painted: showsPaintedFrame)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .strokeBorder(Theme.gold, lineWidth: isSelected ? 2.5 : 0)
        )
        .shadow(color: isSelected ? Theme.gold.opacity(0.75) : .clear, radius: 10)
        .scaleEffect(isSelected ? 1.04 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isSelected)
        // The other half of that guard. A `.fill` portrait that is not square
        // draws past its frame, and `.clipShape` above hides an overhang
        // without clipping its hit-testing (the project's own rule), so in a
        // grid the later-declared card would swallow taps meant for its
        // neighbour. Nothing overhangs while every card is 1024², but the
        // hit region costs nothing to bound and the art is data, not code.
        .contentShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
    }

    /// The carved frame for this grade. Square, transparent centre, sits over
    /// the portrait so its corner ornament overlaps the art the way a real
    /// gacha card's does — on the big cards (`paintedFrameFrom`). Nothing
    /// when the texture has not shipped — the code-drawn stroke in
    /// `rarityFrame` covers that case.
    @ViewBuilder
    private var paintedFrame: some View {
        if let frame = Chrome.image(rarity.frameImageName) {
            Image(uiImage: frame)
                .resizable()
                .frame(width: size, height: size)
                .allowsHitTesting(false)
        }
    }

    /// Uses the portrait art when it exists; otherwise an element-tinted plate
    /// with the unit's initial, which keeps every screen usable pre-art.
    @ViewBuilder
    private var portrait: some View {
        if BundleImage.exists(unit.blueprint.model.portraitName(awakened: unit.unit.isAwakened)) {
            // Decoded at the card's own size. This one line is most of the
            // Arena's lag: `UnitCard` is what a challenger row, a team slot,
            // a grid cell and a picker candidate are all made of, so every
            // list in the game was decoding full 1024-pixel paintings.
            BundleImage(name: unit.blueprint.model.portraitName(awakened: unit.unit.isAwakened),
                        renderedAt: size)
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                RadialGradient(
                    colors: [unit.element.color.opacity(0.75),
                             unit.element.color.opacity(0.25),
                             Theme.surface],
                    center: .init(x: 0.5, y: 0.38),
                    startRadius: 0,
                    endRadius: size * 0.85
                )
                Text(String(unit.name.prefix(1)))
                    .font(Theme.display(size * 0.46))
                    .foregroundStyle(
                        LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.35)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .shadow(color: .black.opacity(0.6), radius: 4, y: 2)
            }
        }
    }
}

/// An empty slot in a team lineup.
struct EmptyTeamSlot: View {
    var size: CGFloat = 76
    var label: String = "Empty"

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Theme.goldDim)
            Text(label.uppercased())
                .font(Theme.body(10).weight(.bold))
                .tracking(0.8)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(width: size, height: size * 1.35)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(Theme.plate.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
    }
}

/// An unfilled place in the collection grid.
///
/// The CI tour photographed the Collection on a new save as nine cards in the
/// top row and four fifths of the screen bare black, which is the single least
/// premium thing an interface can do — a screen that is mostly nothing reads
/// as unfinished whatever colour it is. The genre never shows a void: it shows
/// the shape of what you do not have yet, which is a goal rather than a gap.
///
/// Deliberately quieter than `EmptyTeamSlot`: no plus, no word, no dashes. A
/// team slot is a thing to TAP and says so; this is scenery, and eighty of
/// them shouting "Empty" would be worse than the void it replaces. A recessed
/// well with a faint bronze rim and the ghost of a card's star row.
struct EmptyCollectionSlot: View {
    var size: CGFloat = 76

    var body: some View {
        RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
            .fill(Theme.plate.opacity(0.45))
            .overlay(
                // Inset shadow at the top: the well is BELOW the surface, the
                // opposite of every panel, which is what tells the eye it is a
                // hole and not an object.
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .strokeBorder(
                        LinearGradient(colors: [Color.black.opacity(0.75), Color.clear,
                                                Theme.goldDeep.opacity(0.30)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1.5
                    )
            )
            .overlay(
                Image(systemName: "star.fill")
                    .font(.system(size: size * 0.16, weight: .bold))
                    .foregroundStyle(Theme.goldDeep.opacity(0.5))
                    .offset(y: size * 0.38)
            )
            .frame(width: size, height: size * 1.35)
    }
}

/// Press feedback for anything built to look like a physical plate.
struct PlateButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The app's primary button — a struck metal plate, not a coloured rectangle.
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = Theme.gold
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            AudioLibrary.shared.play(.uiConfirm, volume: 0.7)
            action()
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .black))
                }
                Text(title.uppercased())
                    .font(Theme.title(13))
                    .tracking(1.0)
            }
            // A bar, not a billboard: full width up to a hand's span, and
            // centred, so a landscape screen keeps its edges.
            .frame(maxWidth: 380)
            .padding(.vertical, 10)
            .background(plate)
            .overlay(
                // A light plate — the summon screen's ×1 beside the painted
                // gold ×10 — gets a gold edge, because a white highlight on
                // cream is no edge at all; every other plate keeps its lit rim.
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .strokeBorder(
                        isLightPlate ? Theme.goldDim.opacity(0.8) : Color.white.opacity(isEnabled ? 0.4 : 0.12),
                        lineWidth: 1
                    )
                    .blendMode(isLightPlate ? .normal : .plusLighter)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
            .foregroundStyle(labelColor)
            .shadow(color: isEnabled ? tint.opacity(0.35) : .clear, radius: 6, y: 2)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlateButtonStyle())
        .disabled(!isEnabled)
    }

    private var usesGoldPlate: Bool { tint == Theme.gold }

    /// A DRAWN plate pale enough that ink is its label — cream, marble, the
    /// high surface. It wears a gold edge instead of the white highlight,
    /// which is invisible on cream. Never true once the painted plate is back,
    /// since that brings its own frame.
    private var isLightPlate: Bool {
        isEnabled && !usesGoldPlate && Theme.isLight(tint)
            && Chrome.slice("ui_button_dark", Chrome.darkButtonInsets) == nil
    }

    private var labelColor: Color {
        guard isEnabled else { return Theme.textSecondary }
        // The painted plain plate is cream marble with a gold border since the
        // night-3 repaint (2026-09-12), so ink is the only label that reads on
        // it — the first frames of the repaint had the summon screen's ×1 as
        // cream on cream, because this rule still put the TINT on the label,
        // which carried the meaning on the slate plate it was written for.
        // On gold (painted or drawn) ink is the only thing that reads. On the
        // DRAWN plate of any other tint — the painted one never shipped — the
        // plate is the tint itself, so the label is whichever of ink and
        // cream reads on it: the ×1 button was once ink on an ink plate.
        if !usesGoldPlate {
            return Chrome.slice("ui_button_dark", Chrome.darkButtonInsets) != nil ? Theme.ink : Theme.readableText(on: tint)
        }
        return Theme.ink
    }

    @ViewBuilder
    private var plate: some View {
        if isEnabled, usesGoldPlate,
           let painted = Chrome.slice("ui_button_gold", Chrome.goldButtonInsets) {
            painted
        } else if isEnabled, !usesGoldPlate,
                  let painted = Chrome.slice("ui_button_dark", Chrome.darkButtonInsets) {
            painted
        } else if isEnabled {
            LinearGradient(
                colors: [tint.opacity(0.55), tint, tint.opacity(0.72)],
                startPoint: .top, endPoint: .bottom
            )
            .overlay(
                // Gloss across the top half only — a plate lit from above.
                LinearGradient(colors: [.white.opacity(0.45), .clear],
                               startPoint: .top, endPoint: .center)
            )
        } else {
            LinearGradient(colors: [Theme.surfaceHigh, Theme.surface],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Section header with a rule, used down the whole app.
struct SectionHeader: View {
    let title: String
    var accessory: String? = nil

    var body: some View {
        if let ribbon = Chrome.slice("ui_ribbon", Chrome.ribbonInsets) {
            HStack(alignment: .center, spacing: 8) {
                Text(title.uppercased())
                    .font(Theme.title(12))
                    .tracking(1.6)
                    .foregroundStyle(Theme.ink)
                    .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                Spacer(minLength: 8)
                if let accessory {
                    Text(accessory)
                        .font(Theme.numeric(11))
                        .foregroundStyle(Theme.ink.opacity(0.72))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(ribbon)
        } else {
            drawn
        }
    }

    private var drawn: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title.uppercased())
                .font(Theme.title(12))
                .tracking(1.6)
                .foregroundStyle(
                    LinearGradient(colors: [Theme.gold, Theme.goldDim],
                                   startPoint: .top, endPoint: .bottom)
                )
            Rectangle()
                .fill(LinearGradient(colors: [Theme.goldDim.opacity(0.8), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(height: 1)
            if let accessory {
                Text(accessory)
                    .font(Theme.numeric(11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// Shown wherever a list has nothing in it yet.
struct EmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(Theme.stroke)
            Text(title.uppercased())
                .font(Theme.title(16))
                .tracking(1.2)
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(Theme.body(13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 28)
    }
}


// MARK: - Screen chrome
//
// These types lived in their own file, Pantheon/UI/Common/GameScreen.swift,
// until 2026-09-10. The project has no explicit list of source files — it
// uses a synchronized folder group (objectVersion 77), so Xcode compiles
// whatever it finds under Pantheon/ — and on the owner's machine Xcode did
// not pick the new file up: it built every reference to GameScreen and then
// reported "Cannot find 'GameScreen' in scope" eleven times, while the same
// commit built clean on the macOS runner. Rather than have him fight his
// project navigator, the chrome moved in here, beside the other shared
// components. The lesson is worth keeping: a NEW FILE is the one change this
// project cannot verify from CI alone, because CI checks out the folder
// fresh and always sees it.

/// The chrome a menu wears, in the genre's shape rather than the platform's.
///
/// What this replaces, and why. Every menu used to be a `NavigationStack` with
/// `.screen(title)`: a UIKit navigation bar, then a row of capsule filter
/// pills, then a full-width segmented control, and only then the content. On a
/// landscape iPhone that is a 44-point bar, a 34-point pill row and a 32-point
/// picker — 110 of the 430 points of height, a quarter of the screen, spent
/// before a single card is drawn. The collection showed **one row of eight
/// cards** with a third of the frame left black underneath. The owner's words
/// were "every menu with a big top bar and pills as options is super ugly. I
/// want something more like Summoners War where all space is utilised nicely".
///
/// The genre's answer, and this file's: **one slim strip, then content to the
/// edges**. The strip is 34 points and carries everything the bar and both
/// control rows used to — a back control, the title, the filters as square
/// glyph tiles, sort as a dropdown, the screen's actions, and the wallet — and
/// the content below it gets the whole remaining frame. The collection now
/// fits three rows of ten.
///
/// Rules for anything that lives in the strip:
/// - It is 26 points tall inside a 34-point strip. Nothing taller goes there.
/// - A control is a rounded rectangle of `Theme.surfaceRaised` with a hairline
///   in its own tint, so every tappable thing on every screen reads the same.
/// - Text in the strip is 9–11 point and tracked; the strip is a label rail,
///   not a place for sentences.
/// - A filter that has a glyph shows the glyph, not its name. `ALL` is the one
///   word, because no glyph means "no filter".
///
/// `.toolbar(.hidden, for: .navigationBar)` is what removes the platform bar,
/// so a screen that adopts `GameScreen` must move its `ToolbarItem`s into the
/// strip's `bar` — they would otherwise vanish. That is the whole conversion.
struct GameScreen<Bar: View, Content: View>: View {
    let title: String
    var subtitle: String?
    /// Shows a back chevron at the leading edge when set. A sheet passes its
    /// `dismiss`; a tab root passes nil.
    var dismiss: (() -> Void)?
    /// Controls for the right of the strip: filters, sort, actions, wallet.
    @ViewBuilder var bar: () -> Bar
    @ViewBuilder var content: () -> Content

    init(
        _ title: String,
        subtitle: String? = nil,
        dismiss: (() -> Void)? = nil,
        @ViewBuilder bar: @escaping () -> Bar,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.dismiss = dismiss
        self.bar = bar
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            strip
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.backdrop)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.light)
    }

    private var strip: some View {
        HStack(spacing: 8) {
            if let dismiss {
                Button {
                    Juice.haptic(.light)
                    AudioLibrary.shared.play(.uiTap)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(Theme.gold)
                        .frame(width: ScreenChrome.control + 2, height: ScreenChrome.control)
                        .background(ScreenChrome.controlShape.fill(Theme.surfaceRaised))
                        .overlay(ScreenChrome.controlShape.strokeBorder(Theme.goldDim.opacity(0.55), lineWidth: 0.5))
                        .stripHitTarget()
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 0) {
                Text(title.uppercased())
                    .font(Theme.title(13))
                    .tracking(1.4)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.body(9))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 6)

            bar()
        }
        .padding(.horizontal, 10)
        .frame(height: ScreenChrome.height)
        .background(ScreenChrome.stripBackground)
    }
}

/// The strip's measurements, in one place so every control matches.
enum ScreenChrome {
    /// The whole strip. 34 points against the navigation bar's 44 plus two
    /// control rows: the change hands roughly 80 points back to the content.
    static let height: CGFloat = 34
    /// Every control inside the strip.
    static let control: CGFloat = 26
    static let corner: CGFloat = 6
    /// The padding content below the strip should use, so screens agree.
    static let contentPadding: CGFloat = 10

    static var controlShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
    }

    static var stripBackground: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [Theme.surfaceHigh, Theme.surface],
                startPoint: .top,
                endPoint: .bottom
            )
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Theme.goldDeep.opacity(0.0), Theme.goldDim.opacity(0.75), Theme.goldDeep.opacity(0.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
    }
}

extension View {
    /// The tap area of a control in the strip.
    ///
    /// A strip control draws at `ScreenChrome.control` — 26 points — inside a
    /// 34-point strip, so the 4 points above and below its plate belonged to
    /// nothing: a thumb that clipped the top of a glyph tile hit the screen
    /// behind it. The plate keeps its size and the strip keeps its height;
    /// only the hit region grows, so no layout moves. It is still short of the
    /// 44 points the HIG asks for, which is what a 34-point strip costs.
    func stripHitTarget() -> some View {
        frame(height: ScreenChrome.height)
            .contentShape(Rectangle())
    }
}

// MARK: - Strip controls

/// An action in the strip: a glyph, and a word when there is room for one.
struct BarButton: View {
    let title: String
    var systemImage: String?
    var tint: Color = Theme.gold
    var showsTitle: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            Juice.haptic(.light)
            AudioLibrary.shared.play(.uiTap)
            action()
        } label: {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .black))
                }
                if showsTitle {
                    Text(title)
                        .font(Theme.body(11).weight(.bold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, showsTitle ? 9 : 0)
            .frame(minWidth: ScreenChrome.control, minHeight: ScreenChrome.control)
            .background(ScreenChrome.controlShape.fill(Theme.surfaceRaised))
            .overlay(ScreenChrome.controlShape.strokeBorder(tint.opacity(0.4), lineWidth: 0.5))
            .stripHitTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// The element filter, as six square glyph tiles instead of six capsules of
/// text. Six tiles are 186 points wide against 330 for the pills they replace,
/// which is what lets them sit in the strip beside everything else.
struct ElementFilterTiles: View {
    @Binding var selection: Element?

    var body: some View {
        HStack(spacing: 3) {
            tile(nil)
            ForEach(Element.allCases) { element in
                tile(element)
            }
        }
    }

    private func tile(_ element: Element?) -> some View {
        let isOn = selection == element
        let tint = element?.color ?? Theme.gold
        return Button {
            Juice.haptic(.light)
            selection = (element != nil && selection == element) ? nil : element
        } label: {
            Group {
                if let element {
                    Image(systemName: element.glyph)
                        .font(.system(size: 11, weight: .black))
                } else {
                    Text("ALL")
                        .font(Theme.body(9).weight(.black))
                        .tracking(0.4)
                }
            }
            .foregroundStyle(isOn ? Theme.ink : tint.opacity(0.85))
            .frame(width: element == nil ? 32 : 28, height: ScreenChrome.control)
            .background(ScreenChrome.controlShape.fill(isOn ? tint : Theme.surfaceRaised))
            .overlay(
                ScreenChrome.controlShape
                    .strokeBorder(tint.opacity(isOn ? 0.0 : 0.35), lineWidth: 0.5)
            )
            .shadow(color: isOn ? tint.opacity(0.6) : .clear, radius: 4)
            .stripHitTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(element?.displayName ?? "All elements")
    }
}

/// Sort, mode, or any other one-of-N choice: a dropdown that costs 90 points
/// of the strip instead of a segmented control that costs the whole width.
struct BarMenu<Content: View>: View {
    let label: String
    let value: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 4) {
                Text(label.uppercased())
                    .font(Theme.body(9).weight(.black))
                    .tracking(0.5)
                    .foregroundStyle(Theme.textSecondary)
                Text(value)
                    .font(Theme.body(11).weight(.bold))
                    .foregroundStyle(Theme.gold)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Theme.goldDim)
            }
            .padding(.horizontal, 9)
            .frame(height: ScreenChrome.control)
            .background(ScreenChrome.controlShape.fill(Theme.surfaceRaised))
            .overlay(ScreenChrome.controlShape.strokeBorder(Theme.goldDim.opacity(0.4), lineWidth: 0.5))
        }
        .menuStyle(.borderlessButton)
    }
}

/// A count or a status, read-only: "12 relics", "3/8 done".
struct BarCount: View {
    let value: String
    var systemImage: String?
    var tint: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(Theme.numeric(11))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 8)
        .frame(height: ScreenChrome.control)
        .background(ScreenChrome.controlShape.fill(Theme.surface.opacity(0.8)))
        .overlay(ScreenChrome.controlShape.strokeBorder(Theme.stroke.opacity(0.8), lineWidth: 0.5))
    }
}

/// A segmented choice small enough for the strip, for the two- and three-way
/// switches a dropdown would over-serve (Chapters/Halls, Buy/Sell).
struct BarSegments<T: Hashable>: View {
    let options: [(value: T, title: String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isOn = selection == option.value
                Button {
                    Juice.haptic(.light)
                    AudioLibrary.shared.play(.uiTap)
                    selection = option.value
                } label: {
                    Text(option.title)
                        .font(Theme.body(11).weight(.bold))
                        .foregroundStyle(isOn ? Theme.ink : Theme.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: ScreenChrome.control - 4)
                        .background(
                            RoundedRectangle(cornerRadius: ScreenChrome.corner - 2, style: .continuous)
                                .fill(isOn ? Theme.gold : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(ScreenChrome.controlShape.fill(Theme.surfaceRaised))
        .overlay(ScreenChrome.controlShape.strokeBorder(Theme.stroke, lineWidth: 0.5))
    }
}

/// The wallet, drawn flat for the strip: the capsule `WalletBar` is 36 points
/// tall with its shadow and belongs on the island, over a painting.
struct BarWallet: View {
    let wallet: Wallet
    var shows: [Kind] = [.energy, .divinity, .drachma]

    enum Kind { case energy, divinity, drachma, laurels }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(shows.enumerated()), id: \.offset) { _, kind in
                HStack(spacing: 3) {
                    Image(systemName: icon(kind))
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(tint(kind))
                    Text(value(kind))
                        .font(Theme.numeric(11))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
        }
        .padding(.horizontal, 9)
        .frame(height: ScreenChrome.control)
        .background(ScreenChrome.controlShape.fill(Theme.surface.opacity(0.85)))
        .overlay(ScreenChrome.controlShape.strokeBorder(Theme.goldDim.opacity(0.45), lineWidth: 0.5))
    }

    private func icon(_ kind: Kind) -> String {
        switch kind {
        case .energy: return "bolt.fill"
        case .divinity: return "sparkles"
        case .drachma: return "circle.hexagongrid.fill"
        case .laurels: return "laurel.leading"
        }
    }

    private func tint(_ kind: Kind) -> Color {
        switch kind {
        case .energy: return Theme.info
        case .divinity: return Theme.gold
        case .drachma: return Theme.textPrimary
        case .laurels: return Theme.success
        }
    }

    private func value(_ kind: Kind) -> String {
        switch kind {
        case .energy: return "\(wallet.energy)/\(wallet.maxEnergy)"
        case .divinity: return "\(wallet.divinity)"
        case .drachma: return BarWallet.compact(wallet.drachma)
        case .laurels: return "\(wallet.laurels)"
        }
    }

    /// 1,240,000 in a strip is noise; 1.2M is a number.
    static func compact(_ amount: Int) -> String {
        if amount >= 1_000_000 { return String(format: "%.1fM", Double(amount) / 1_000_000) }
        if amount >= 10_000 { return "\(amount / 1000)K" }
        return "\(amount)"
    }
}

// MARK: - Content helpers

/// A titled block inside a screen's content, replacing the ad-hoc
/// `Text(...).font(Theme.title(13))` + `VStack` every screen wrote for itself.
struct SectionPanel<Content: View>: View {
    let title: String
    var accessory: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // Both ends of this row take the width they need and the rule
                // between them takes what is left. Without that the title
                // wraps: the CI tour photographed the arena's Offence panel as
                // "OFFENC / E" on 2026-09-10, because "Power 3812" beside it
                // left the title less room than its own tracking needed, and
                // the header is the one thing on a panel that must never wrap.
                Text(title.uppercased())
                    .font(Theme.body(10).weight(.black))
                    .tracking(1.0)
                    .foregroundStyle(Theme.goldDim)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Rectangle()
                    .fill(Theme.stroke.opacity(0.7))
                    .frame(height: 1)
                if let accessory {
                    Text(accessory)
                        .font(Theme.numeric(10))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            content()
        }
        .padding(8)
        .background(Theme.panel(Theme.tightCorner))
    }
}
