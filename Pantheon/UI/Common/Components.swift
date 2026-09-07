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
                    // A recessed track: dark fill, dark top edge. The bar has to
                    // look like a channel cut into the panel, or the fill reads
                    // as a floating coloured pill.
                    Capsule().fill(Theme.ink.opacity(0.85))
                    Capsule().strokeBorder(Color.black.opacity(0.6), lineWidth: 1)

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
            resource(icon: "bolt.fill", value: "\(wallet.energy)/\(wallet.maxEnergy)", tint: Theme.info)
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

    private func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 10_000...: return "\(value / 1_000)K"
        default: return "\(value)"
        }
    }
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
    var size: CGFloat = 92

    private var rarity: Rarity { Rarity(stars: unit.stars) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                portrait

                // Darkens the lower third so the star row and name always have
                // something to sit on, whatever the art behind them is doing.
                LinearGradient(
                    colors: [.clear, .clear, Theme.ink.opacity(0.85)],
                    startPoint: .top, endPoint: .bottom
                )

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

                if unit.unit.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.textPrimary.opacity(0.9))
                        .shadow(color: .black, radius: 2)
                        .padding(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }

                StarRow(stars: unit.stars, natural: unit.blueprint.naturalStars,
                        size: max(7, size * 0.105))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 4)

                if rarity.hasSheen {
                    Sheen(cornerRadius: Theme.tightCorner)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
            .overlay(paintedFrame)

            VStack(spacing: 1) {
                Text(unit.name)
                    .font(Theme.body(11).weight(.heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 5) {
                    Text("Lv.\(unit.level)")
                        .font(Theme.numeric(10))
                        .foregroundStyle(Theme.textSecondary)
                    if showPower {
                        Text("\(unit.power)")
                            .font(Theme.numeric(10))
                            .foregroundStyle(Theme.gold)
                    }
                }
            }
            .padding(.top, 4)
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
            .frame(width: size)
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(LinearGradient(colors: [Theme.surfaceRaised, Theme.surface],
                                     startPoint: .top, endPoint: .bottom))
        )
        .rarityFrame(rarity, radius: Theme.tightCorner)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .strokeBorder(Theme.gold, lineWidth: isSelected ? 2.5 : 0)
        )
        .shadow(color: isSelected ? Theme.gold.opacity(0.75) : .clear, radius: 10)
        .scaleEffect(isSelected ? 1.04 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isSelected)
    }

    /// The carved frame for this grade. Square, transparent centre, sits over
    /// the portrait so its corner ornament overlaps the art the way a real
    /// gacha card's does. Nothing when the texture has not shipped — the
    /// code-drawn stroke in `rarityFrame` covers that case.
    @ViewBuilder
    private var paintedFrame: some View {
        if let frame = Chrome.image(rarity.frameImageName) {
            Image(uiImage: frame)
                .resizable()
                .allowsHitTesting(false)
        }
    }

    /// Uses the portrait art when it exists; otherwise an element-tinted plate
    /// with the unit's initial, which keeps every screen usable pre-art.
    @ViewBuilder
    private var portrait: some View {
        if UIImage(named: unit.blueprint.model.portraitName) != nil {
            Image(unit.blueprint.model.portraitName)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                RadialGradient(
                    colors: [unit.element.color.opacity(0.75),
                             unit.element.color.opacity(0.25),
                             Theme.ink],
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
    var size: CGFloat = 92
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
                .fill(Theme.ink.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
        )
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
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .black))
                }
                Text(title.uppercased())
                    .font(Theme.title(14))
                    .tracking(1.1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(plate)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .strokeBorder(Color.white.opacity(isEnabled ? 0.4 : 0.12), lineWidth: 1)
                    .blendMode(.plusLighter)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))
            .foregroundStyle(labelColor)
            .shadow(color: isEnabled ? tint.opacity(0.45) : .clear, radius: 10, y: 3)
            .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
        }
        .buttonStyle(PlateButtonStyle())
        .disabled(!isEnabled)
    }

    private var usesGoldPlate: Bool { tint == Theme.gold }

    private var labelColor: Color {
        guard isEnabled else { return Theme.textSecondary }
        // On the painted dark plate the tint carries the meaning, so it goes on
        // the label; on gold (painted or drawn) ink is the only thing that reads.
        if !usesGoldPlate, Chrome.image("ui_button_dark") != nil { return tint }
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
                    .foregroundStyle(Theme.gold)
                    .shadow(color: .black.opacity(0.8), radius: 1, y: 1)
                Spacer(minLength: 8)
                if let accessory {
                    Text(accessory)
                        .font(Theme.numeric(11))
                        .foregroundStyle(Theme.textPrimary)
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
