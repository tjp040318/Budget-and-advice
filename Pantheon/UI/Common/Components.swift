import SwiftUI
import UIKit

/// Star grade, drawn as filled pips. Grades above the natural rating are shown
/// in gold so an evolved unit reads differently from a naturally high one.
struct StarRow: View {
    let stars: Int
    var natural: Int? = nil
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<max(1, stars), id: \.self) { index in
                Image(systemName: "star.fill")
                    .font(.system(size: size))
                    .foregroundStyle(isEvolved(index) ? Theme.gold : Theme.goldDim)
            }
        }
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
                .font(.system(size: compact ? 10 : 12, weight: .bold))
            if !compact {
                Text(element.displayName)
                    .font(Theme.body(11).weight(.semibold))
            }
        }
        .foregroundStyle(element.color)
        .padding(.horizontal, compact ? 5 : 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(element.color.opacity(0.16))
        )
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
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.stroke)
                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * fraction)
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
        HStack(spacing: 14) {
            resource(icon: "bolt.fill", value: "\(wallet.energy)/\(wallet.maxEnergy)", tint: Theme.info)
            resource(icon: "sparkles", value: "\(wallet.divinity)", tint: Theme.gold)
            resource(icon: "circle.hexagongrid.fill", value: compact(wallet.drachma), tint: Theme.textSecondary)
            resource(icon: "laurel.leading", value: "\(wallet.laurels)", tint: Theme.success)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(Theme.surface.opacity(0.9)))
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }

    private func resource(icon: String, value: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
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
struct UnitCard: View {
    let unit: ResolvedUnit
    var isSelected: Bool = false
    var showPower: Bool = true
    var size: CGFloat = 92

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                portrait
                VStack(alignment: .leading, spacing: 3) {
                    ElementBadge(element: unit.element, compact: true)
                    if unit.unit.isAwakened {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.gold)
                    }
                }
                .padding(5)

                if unit.unit.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous))

            VStack(spacing: 2) {
                StarRow(stars: unit.stars, natural: unit.blueprint.naturalStars, size: 8)
                Text(unit.name)
                    .font(Theme.body(11).weight(.semibold))
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
                            .foregroundStyle(Theme.goldDim)
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
                .fill(Theme.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .strokeBorder(isSelected ? Theme.gold : Theme.stroke, lineWidth: isSelected ? 2 : 1)
        )
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
                LinearGradient(
                    colors: [unit.element.color.opacity(0.55), Theme.surface],
                    startPoint: .top,
                    endPoint: .bottom
                )
                Text(String(unit.name.prefix(1)))
                    .font(Theme.display(size * 0.42))
                    .foregroundStyle(Theme.textPrimary.opacity(0.85))
            }
        }
    }
}

/// An empty slot in a team lineup.
struct EmptyTeamSlot: View {
    var size: CGFloat = 92
    var label: String = "Empty"

    var body: some View {
        VStack {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(Theme.textSecondary)
            Text(label)
                .font(Theme.body(10))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(width: size, height: size * 1.35)
        .background(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .fill(Theme.surface.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }
}

/// The app's primary button.
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
                        .font(.system(size: 14, weight: .bold))
                }
                Text(title)
                    .font(Theme.title(15))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: Theme.tightCorner, style: .continuous)
                    .fill(isEnabled ? tint : Theme.stroke)
            )
            .foregroundStyle(isEnabled ? Theme.ink : Theme.textSecondary)
        }
        .disabled(!isEnabled)
    }
}

/// Section header with a rule, used down the whole app.
struct SectionHeader: View {
    let title: String
    var accessory: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(Theme.body(11).weight(.bold))
                .tracking(1.4)
                .foregroundStyle(Theme.goldDim)
            Rectangle()
                .fill(Theme.stroke)
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
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.stroke)
            Text(title)
                .font(Theme.title(17))
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
