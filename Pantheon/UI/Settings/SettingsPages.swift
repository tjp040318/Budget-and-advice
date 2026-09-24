import SwiftUI
import UIKit

/// The pages More's Settings board leads to (`Docs/SETTINGS.md`), pushed in
/// More's own navigation stack.
enum SettingsPage: Hashable {
    case notifications
    case graphics
}

/// Where More opens: its boards, one of its pages, or the account-deletion
/// sheet — the last three for the CI tour's photographs.
enum SettingsOpening {
    case boards
    case notifications
    case graphics
    case deleteAccount
}

// MARK: - Notifications

/// Settings → Notifications (`Docs/SETTINGS.md` §1): the three reminders on
/// the left, iOS's answer and the rules on the right. Turning a reminder on
/// is the moment iOS is asked; after a "no" there iOS never asks again, so
/// the page offers the iPhone's own Settings instead.
struct NotificationSettingsView: View {
    @ObservedObject private var reminders = NotificationService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GameScreen("Notifications", subtitle: "Reminders from Pantheon, only the ones you turn on", dismiss: { dismiss() }) {
            EmptyView()
        } content: {
            HStack(alignment: .top, spacing: 8) {
                SectionPanel(title: "Reminders", accessory: nil) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(ReminderKind.allCases, id: \.self) { kind in
                                Toggle(isOn: binding(kind)) {
                                    SettingsLabel(title: kind.title, caption: kind.caption)
                                }
                            }
                        }
                        .toggleStyle(GameToggleStyle())
                        .padding(.horizontal, 6)
                        .padding(.bottom, 16)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                SectionPanel(title: "On this iPhone", accessory: nil) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 10) {
                            accessRow
                            if reminders.access == .denied {
                                PrimaryButton(title: "Open iPhone Settings", systemImage: "gearshape.fill", tint: Theme.goldDim) {
                                    reminders.openSystemSettings()
                                }
                            }
                            SettingsCaption(text: "At most one reminder in the morning and one when your energy fills. Nothing arrives between 22:00 and 8:00; a reminder that would is held until the morning.")
                            SettingsCaption(text: "They are planned when you leave the game and cleared the moment you come back.")
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 16)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, ScreenChrome.contentPadding)
            .padding(.vertical, 8)
        }
        .task { await reminders.refreshAccess() }
    }

    private func binding(_ kind: ReminderKind) -> Binding<Bool> {
        Binding(
            get: { reminders.isOn(kind) },
            set: { on in
                Task { @MainActor in await reminders.set(kind, on: on) }
            }
        )
    }

    /// iOS's answer in words, with its glyph.
    private var accessRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: accessGlyph)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accessTint)
            VStack(alignment: .leading, spacing: 2) {
                Text(accessTitle)
                    .font(Theme.body(12).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(accessDetail)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessTitle: String {
        switch reminders.access {
        case .allowed: return "Allowed"
        case .denied: return "Off for Pantheon"
        case .notAsked: return "Not asked yet"
        case .unknown: return "Checking…"
        }
    }

    private var accessDetail: String {
        switch reminders.access {
        case .allowed: return "iOS lets Pantheon remind you. The switches choose which reminders."
        case .denied: return "iOS was told no. Turn notifications on for Pantheon in the iPhone's Settings, then choose here."
        case .notAsked: return "Turning a reminder on asks iOS once, with its own message."
        case .unknown: return "Reading iOS's answer."
        }
    }

    private var accessGlyph: String {
        switch reminders.access {
        case .allowed: return "checkmark.seal.fill"
        case .denied: return "bell.slash.fill"
        case .notAsked, .unknown: return "bell.fill"
        }
    }

    private var accessTint: Color {
        switch reminders.access {
        case .allowed: return Theme.success
        case .denied: return Theme.danger
        case .notAsked, .unknown: return Theme.goldDim
        }
    }
}

// MARK: - Graphics and comfort

/// Settings → Graphics & comfort (`Docs/SETTINGS.md` §2): the frame rate,
/// the effects and the shadows on the left — applied through
/// `GraphicsSettings.configure` — and Reduce Motion and the cinematic
/// camera on the right. The effects and the shadows reach a stage at once;
/// the frame rate from the next fight.
struct GraphicsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage(GraphicsSettings.frameRateKey) private var frameRate: Int = FrameRateChoice.standard.rawValue
    @AppStorage(GraphicsSettings.effectsKey) private var effects: String = EffectsQuality.full.rawValue
    @AppStorage(GraphicsSettings.shadowsKey) private var shadows: Bool = true
    @AppStorage(MotionComfort.key) private var reduceMotion: Bool = false
    @AppStorage(CameraDirector.cinematicKey) private var cinematicCamera: Bool = false
    @AppStorage(UltimateSplash.key) private var ultimateSplash: String = SplashChoice.always.rawValue

    var body: some View {
        GameScreen("Graphics & comfort", subtitle: "How the fight looks, and how much it moves", dismiss: { dismiss() }) {
            EmptyView()
        } content: {
            HStack(alignment: .top, spacing: 8) {
                SectionPanel(title: "Performance", accessory: nil) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            choiceRow(title: "Frame rate", caption: frameRateCaption) {
                                BarSegments(options: frameRateOptions, selection: frameRateSelection)
                            }
                            choiceRow(title: "Effects", caption: effectsCaption) {
                                BarSegments(options: effectsOptions, selection: $effects)
                            }
                            Toggle(isOn: $shadows) {
                                SettingsLabel(title: "Shadows", caption: "The figures' shadows in the fight and on the summoning circle.")
                            }
                        }
                        .toggleStyle(GameToggleStyle())
                        .padding(.horizontal, 6)
                        .padding(.bottom, 16)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                SectionPanel(title: "Comfort", accessory: nil) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $reduceMotion) {
                                SettingsLabel(title: "Reduce motion", caption: "No camera shake, a calmer ultimate (no burst of light, its splash fades in), a gentler skill zoom and no cinematic cuts.")
                            }
                            if systemReduceMotion {
                                SettingsCaption(text: "iOS's Reduce Motion is on, so every fight is calm whatever this switch says.")
                            }
                            Toggle(isOn: $cinematicCamera) {
                                SettingsLabel(title: "Cinematic battle camera", caption: cinematicCaption)
                            }
                            // Docs/FEEL.md W2.1: the ultimate's splash every
                            // time, each unit's first in a fight, or never —
                            // for a player farming on auto.
                            choiceRow(title: "Ultimate splash", caption: splashCaption) {
                                BarSegments(options: splashOptions, selection: $ultimateSplash)
                            }
                        }
                        .toggleStyle(GameToggleStyle())
                        .padding(.horizontal, 6)
                        .padding(.bottom, 16)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, ScreenChrome.contentPadding)
            .padding(.vertical, 8)
        }
    }

    /// A choice's name and its segments on one line, its caption under.
    private func choiceRow<Content: View>(title: String, caption: String, @ViewBuilder control: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 8)
                control()
            }
            SettingsCaption(text: caption)
        }
    }

    private var frameRateOptions: [(value: Int, title: String)] {
        GraphicsSettings.offeredFrameRates.map { (value: $0.rawValue, title: $0.title) }
    }

    /// The stored choice, shown as 60 when it is a 120 this screen cannot
    /// draw.
    private var frameRateSelection: Binding<Int> {
        Binding(
            get: {
                let offered = GraphicsSettings.offeredFrameRates.map { $0.rawValue }
                return offered.contains(frameRate) ? frameRate : FrameRateChoice.standard.rawValue
            },
            set: { frameRate = $0 }
        )
    }

    private var frameRateCaption: String {
        switch FrameRateChoice(rawValue: frameRate) ?? .standard {
        case .battery: return "Every stage at 30 frames a second: the longest battery. From the next fight."
        case .standard: return "The fight and the summons at 60, the island at 30, as designed."
        case .promotion: return "The fight and the summons at 120 on this screen. From the next fight."
        }
    }

    private var effectsOptions: [(value: String, title: String)] {
        [(value: EffectsQuality.full.rawValue, title: "Full"), (value: EffectsQuality.reduced.rawValue, title: "Reduced")]
    }

    private var effectsCaption: String {
        switch EffectsQuality(rawValue: effects) ?? .full {
        case .full: return "Every spark, flame and glow as designed."
        case .reduced: return "No bloom, and half the sparks and motes: cooler, and longer on the battery. The painted effects stay."
        }
    }

    private var cinematicCaption: String {
        if reduceMotion || systemReduceMotion { return "Held off while Reduce Motion is on." }
        return cinematicCamera ? "On: cuts, leans and orbits on skills." : "Off: one fixed view, the genre's way."
    }

    private var splashOptions: [(value: String, title: String)] {
        [
            (value: SplashChoice.always.rawValue, title: "Always"),
            (value: SplashChoice.first.rawValue, title: "First"),
            (value: SplashChoice.off.rawValue, title: "Off"),
        ]
    }

    private var splashCaption: String {
        switch SplashChoice(rawValue: ultimateSplash) ?? .always {
        case .always: return "Every ultimate owns the screen for a moment: the caster's card and the skill's name."
        case .first: return "First each fight: each unit's first ultimate, then straight to the blow."
        case .off: return "Off: the ultimate strikes at once, for farming on auto."
        }
    }
}

// MARK: - Shared parts

/// A setting's name and the sentence under it.
struct SettingsLabel: View {
    let title: String
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.body(12).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(caption)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A sentence at the caption size, wrapping.
struct SettingsCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.body(11))
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - The energy reminder's offer

/// The card the game shows once, the first time energy runs out
/// (`NotificationService.noteEnergy`, `Docs/SETTINGS.md` §1): what the
/// reminder is, before iOS's own question — which follows "Remind me" at
/// once and is only ever put to a player who has already said yes here. Dark
/// glass over the game, as every card over art is.
struct EnergyReminderCard: View {
    let maxEnergy: Int
    let onAnswer: (Bool) -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                MedallionIcon(key: "", glyph: "bolt.fill", size: 44, glyphTint: Theme.onGlassGold, itemKey: "energy")
                Text("YOUR ENERGY IS SPENT")
                    .font(Theme.title(15))
                    .tracking(1.6)
                    .carved(glow: false)
                    .lineLimit(1)
                    .fixedSize()
                Text(message)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.onGlass)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    PrimaryButton(title: "Remind me", systemImage: "bell.fill") {
                        onAnswer(true)
                    }
                    PrimaryButton(title: "Not now", style: .glass) {
                        onAnswer(false)
                    }
                }
                Text("Change it any time in More → Settings → Notifications.")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.onGlassDim)
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: 460)
            .background(GlassPlate(opacity: 0.88))
            .padding(24)
        }
        .accessibilityElement(children: .contain)
    }

    private var message: String {
        let hours = Int((Double(maxEnergy) * NotificationPlanner.energyInterval / 3600).rounded(.up))
        return "Pantheon can tell you when all \(maxEnergy) is back — a full refill takes about \(hours) hours. One reminder, never at night."
    }
}

// MARK: - The legal links

/// The privacy policy and the terms the Support board links to
/// (`Docs/SETTINGS.md` §4), read from `LegalLinks.plist` in the bundle; an
/// empty value hides its row. App Review 5.1.1(i) requires the privacy
/// policy's link inside the app, so it must be filled before submitting.
struct LegalLinks: Equatable {
    var privacyPolicy: URL?
    var terms: URL?

    static let filename = "LegalLinks"
    static let shared: LegalLinks = load()

    static func load(bundle: Bundle = .main) -> LegalLinks {
        guard let url = bundle.url(forResource: filename, withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return LegalLinks(privacyPolicy: nil, terms: nil)
        }
        return from(dictionary: plist)
    }

    static func from(dictionary plist: [String: Any]) -> LegalLinks {
        LegalLinks(privacyPolicy: link(plist["PrivacyPolicyURL"]), terms: link(plist["TermsOfUseURL"]))
    }

    /// An https address, or nil for an empty or malformed value.
    static func link(_ value: Any?) -> URL? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let url = URL(string: text), url.scheme == "https", url.host != nil else { return nil }
        return url
    }
}
