import SwiftUI

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
        .preferredColorScheme(.dark)
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
                Text(title.uppercased())
                    .font(Theme.body(10).weight(.black))
                    .tracking(1.0)
                    .foregroundStyle(Theme.goldDim)
                Rectangle()
                    .fill(Theme.stroke.opacity(0.7))
                    .frame(height: 1)
                if let accessory {
                    Text(accessory)
                        .font(Theme.numeric(10))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            content()
        }
        .padding(8)
        .background(Theme.panel(Theme.tightCorner))
    }
}
