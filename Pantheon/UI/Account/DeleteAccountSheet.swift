import SwiftUI

/// What the deletion sheet is doing.
enum DeletionStage: Equatable {
    case confirming
    /// Apple's own sheet is up (an Apple ID).
    case authorizing
    case deleting
    /// Apple's sheet was closed: nothing was deleted.
    case cancelled
    /// The cloud could not be reached, so nothing was deleted; the sentence
    /// says so.
    case stopped(String)
}

/// Delete account (`Docs/SETTINGS.md` §3; App Review Guideline 5.1.1(v)):
/// exactly what is deleted on the left, in the words of this account — the
/// cloud it uses, whether the build reaches the Allies, whether it is an
/// Apple ID — and on the right the one thing asked of the player, the word
/// DELETE typed, then Apple's own sheet for an Apple ID (it proves the owner
/// is here and gives the code that revokes Sign in with Apple). While it
/// runs the sheet cannot be swiped away. When the cloud cannot be reached it
/// stops with nothing deleted and says so; when it is done, More closes and
/// the sign-in screen follows with the report's sentence.
struct DeleteAccountSheet: View {
    @EnvironmentObject private var store: GameStore
    @EnvironmentObject private var session: AppSession
    @Environment(\.dismiss) private var dismiss

    /// Called once everything is deleted, with the report.
    let onDeleted: (AccountDeletionReport) -> Void

    @State private var typed = ""
    @State private var stage: DeletionStage = .confirming
    /// Held for as long as Apple's sheet is up: its controller's delegate is
    /// weak.
    @State private var reauthorizer = AppleReauthorizer()

    /// The word, as the field and the button read it.
    static let word = "DELETE"

    init(onDeleted: @escaping (AccountDeletionReport) -> Void) {
        self.onDeleted = onDeleted
    }

    var body: some View {
        GameScreen("Delete account", subtitle: subtitle, dismiss: { if !isBusy { dismiss() } }) {
            EmptyView()
        } content: {
            HStack(alignment: .top, spacing: 8) {
                SectionPanel(title: "What is deleted", accessory: nil) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(deletedLines.enumerated()), id: \.offset) { _, line in
                                listRow(glyph: line.glyph, text: line.text)
                            }
                            SettingsCaption(text: "Kept: this iPhone's sound, graphics and reminder settings.")
                            Text("This cannot be undone, by you or by support. Signing in again starts a new game.")
                                .font(Theme.body(12).weight(.bold))
                                .foregroundStyle(Theme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 6)
                        .padding(.bottom, 16)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                SectionPanel(title: "Confirm", accessory: nil) {
                    ScrollView(.vertical, showsIndicators: false) {
                        confirmation
                            .padding(.horizontal, 6)
                            .padding(.bottom, 16)
                    }
                }
                .frame(width: 300)
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, ScreenChrome.contentPadding)
            .padding(.vertical, 8)
        }
        .interactiveDismissDisabled(isBusy)
    }

    // MARK: - The words

    private var isApple: Bool { session.accounts.account?.provider == .apple }

    private var isBusy: Bool { stage == .authorizing || stage == .deleting }

    private var subtitle: String {
        let code = session.accounts.account?.playerCode ?? "—"
        let kind = isApple ? "Apple ID" : "Guest"
        return "Player ID \(code) · \(kind)"
    }

    /// Exactly what this account has, and so exactly what goes.
    private var deletedLines: [(glyph: String, text: String)] {
        var lines: [(glyph: String, text: String)] = [
            (glyph: "person.crop.square.fill",
             text: "\(store.player.displayName)'s save on this iPhone: every unit, relic, clear and scroll, and every copy of it kept aside."),
        ]
        if let cloud = store.cloudSave {
            lines.append((glyph: "icloud.fill", text: "The copy of the save in \(cloud.serviceName)."))
        }
        if BackendConfig.isConfigured {
            lines.append((glyph: "server.rack", text: "Your Pantheon Cloud account and its sign-in."))
        }
        if CloudKitSocialBackend.isEntitled {
            lines.append((glyph: "person.2.fill", text: "Your Allies profile, guild membership, friends, mail and guild board posts."))
        }
        if isApple {
            lines.append((glyph: "applelogo", text: "Pantheon's Sign in with Apple link to your Apple ID."))
        }
        lines.append((glyph: "bell.slash.fill", text: "Your reminders and the offline practice world."))
        return lines
    }

    private func listRow(glyph: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: glyph)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.danger)
                .frame(width: 18)
            Text(text)
                .font(Theme.body(12))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The confirmation

    private var typedMatches: Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == DeleteAccountSheet.word
    }

    @ViewBuilder
    private var confirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch stage {
            case .confirming, .cancelled:
                Text("Type \(DeleteAccountSheet.word) to confirm")
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                TextField(DeleteAccountSheet.word, text: $typed)
                    .font(Theme.body(13).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .padding(.horizontal, 10)
                    .frame(height: ScreenChrome.control)
                    .background(ScreenChrome.controlShape.fill(Theme.surfaceHigh))
                    .overlay(ScreenChrome.controlShape.strokeBorder(Theme.danger.opacity(0.6), lineWidth: 1))
                PrimaryButton(
                    title: isApple ? "Delete with Apple" : "Delete account",
                    systemImage: "trash.fill",
                    tint: Theme.danger,
                    isEnabled: typedMatches
                ) {
                    start()
                }
                if stage == .cancelled {
                    SettingsCaption(text: "Apple's confirmation was closed, so nothing was deleted.")
                } else if isApple {
                    SettingsCaption(text: "Apple asks you to confirm with Face ID or your passcode; that also disconnects Sign in with Apple.")
                }
            case .authorizing:
                working(title: "WAITING FOR APPLE", detail: "Confirm in Apple's sheet.")
            case .deleting:
                working(title: "DELETING", detail: "Keep Pantheon open for a moment.")
            case .stopped(let sentence):
                Text(sentence)
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(Theme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                PrimaryButton(title: "Close", tint: Theme.goldDim) {
                    dismiss()
                }
            }
        }
    }

    private func working(title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            AccountSpinner()
            Text(title)
                .font(Theme.title(13))
                .tracking(2)
                .foregroundStyle(Theme.goldDim)
            Text(detail)
                .font(Theme.body(11))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: - Deleting

    /// The typed word checked, then Apple's sheet for an Apple ID. A closed
    /// sheet deletes nothing; any other failure there (no connection, a
    /// build without the capability) goes on without Apple's token: the
    /// account is deleted when the phone still holds a backend session (the
    /// report's sentence says how to stop using the Apple ID by hand) and
    /// kept whole when it does not (`AccountDeletion.run`, step 0).
    private func start() {
        guard typedMatches, let account = session.accounts.account else { return }
        guard account.provider == .apple else {
            run(nil)
            return
        }
        stage = .authorizing
        Task { @MainActor in
            do {
                let credential = try await reauthorizer.authorize()
                run(credential)
            } catch AppleReauthorizationError.canceled {
                stage = .cancelled
            } catch {
                run(nil)
            }
        }
    }

    private func run(_ credential: AppleCredential?) {
        stage = .deleting
        Task { @MainActor in
            guard let report = await session.deleteAccount(apple: credential) else {
                dismiss()
                return
            }
            if report.stopped {
                stage = .stopped(report.sentence)
            } else {
                onDeleted(report)
            }
        }
    }
}
