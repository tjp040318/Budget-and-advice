import SwiftUI
import AuthenticationServices

/// The account door: the key art the loading screen wears, the wordmark on
/// the summit's base, one sentence, Apple's own button and the guest link
/// under it (`Docs/PLAN.md`, *Accounts — Sign in with Apple*). The root of
/// the app while no account is signed in; the loading screen plays over it on
/// a first launch, and the Restoring… veil sits on it while a sign-in's save
/// comes down from iCloud.
struct SignInView: View {
    /// True from a sign-in until its store exists — the cloud copy is being
    /// fetched — which veils the screen and turns the ring.
    var isOpening: Bool
    /// The last thing worth a sentence: a revoked sign-in, a bind that found
    /// a save already there.
    var notice: String?
    let onApple: (AppleCredential) -> Void
    let onGuest: () -> Void

    @State private var revealed = false
    @State private var failure: String?

    private let cream = Color(hex: "#EBE2CF")

    init(
        isOpening: Bool = false,
        notice: String? = nil,
        onApple: @escaping (AppleCredential) -> Void,
        onGuest: @escaping () -> Void
    ) {
        self.isOpening = isOpening
        self.notice = notice
        self.onApple = onApple
        self.onGuest = onGuest
    }

    /// The loading screen's painting: the key art, or the first banner in a
    /// bundle without it.
    static var artName: String {
        BundleArt.exists(LaunchProgress.keyArt) ? LaunchProgress.keyArt : LaunchProgress.paintings[0]
    }

    var body: some View {
        // The painting and its shade run to every edge of the glass; the
        // words and the door stand INSIDE the safe area. Until run 217 the
        // whole stack ignored it, padded 28 points off the glass: the P of
        // PANTHEON began under the Dynamic Island and every line of the left
        // column sat in the 62-point landscape inset.
        ZStack {
            GeometryReader { geo in
                ZStack {
                    Theme.ink
                    // Anchored to its top so the five figures stay in frame,
                    // as the loading screen has it; a fixed frame off the
                    // GeometryReader, never a fill image under a flexible one.
                    BundleImage(name: SignInView.artName)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                        .clipped()
                        .allowsHitTesting(false)
                        .opacity(revealed ? 1 : 0)
                    LinearGradient(
                        stops: [
                            .init(color: Theme.ink.opacity(0.25), location: 0),
                            .init(color: .clear, location: 0.18),
                            .init(color: .clear, location: 0.40),
                            .init(color: Theme.ink.opacity(0.92), location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                    .allowsHitTesting(false)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()

            // The safe area is the margin: 62 points either side on a
            // landscape 16 Pro and the home indicator's 21 under, so the
            // padding is only a little air inside it.
            HStack(alignment: .bottom, spacing: 0) {
                wordmark
                Spacer(minLength: 24)
                door
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

            if isOpening {
                veil
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) { revealed = true }
        }
    }

    /// The name and the five pantheons, as the loading screen sets them,
    /// with the one sentence the screen exists for.
    private var wordmark: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PANTHEON")
                .font(Theme.display(40))
                .tracking(8)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: "#FFF0C2"), Color(hex: "#F3D27A"), Color(hex: "#B08A2E")],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .shadow(color: .black.opacity(0.7), radius: 6, y: 3)
            HStack(spacing: 10) {
                RelicSetEmblem(set: .fates, size: 14, tint: Theme.gold, lineSeal: true)
                LinearGradient(colors: [Theme.gold, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 160, height: 1)
            }
            Text("EGYPT  ·  GREECE  ·  NORSE  ·  ROME  ·  THE JADE COURT")
                .font(Theme.body(10).weight(.bold))
                .tracking(2.2)
                .foregroundStyle(cream.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("Your gods, your progress, on every iPhone you own.")
                .font(Theme.body(12))
                .foregroundStyle(cream.opacity(0.92))
                .padding(.top, 4)
        }
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 12)
        .animation(.easeOut(duration: 1.0).delay(0.4), value: revealed)
    }

    /// Apple's button, the guest link and its warning, and any sentence
    /// worth reading above them.
    private var door: some View {
        VStack(alignment: .trailing, spacing: 8) {
            if let line = notice ?? failure {
                Text(line)
                    .font(Theme.body(11))
                    .foregroundStyle(Color(hex: "#FFD678"))
                    .multilineTextAlignment(.trailing)
                    .lineLimit(6)
                    // The door's own width (the guest note's 300): at 340 a
                    // notice widened the column past what the safe width
                    // leaves beside the wordmark's widest line.
                    .frame(maxWidth: 300, alignment: .trailing)
                    .padding(.bottom, 2)
            }
            AppleSignInButton(
                onCredential: { credential in
                    failure = nil
                    onApple(credential)
                },
                onFailure: { failure = $0 }
            )
            .frame(width: 280)
            Button {
                onGuest()
            } label: {
                Text("Continue without an account")
                    .font(Theme.body(12).weight(.semibold))
                    .underline()
                    .foregroundStyle(cream)
            }
            .buttonStyle(GamePressStyle(.plate))
            .padding(.top, 2)
            Text("A guest's progress lives on this phone only; bind it to your Apple ID later from More → Account.")
                .font(Theme.body(10))
                .foregroundStyle(cream.opacity(0.7))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 300, alignment: .trailing)
        }
        .opacity(revealed ? 1 : 0)
        .animation(.easeOut(duration: 0.8).delay(0.6), value: revealed)
    }

    /// Over everything while the save comes down from iCloud.
    private var veil: some View {
        ZStack {
            Theme.ink.opacity(0.62)
            VStack(spacing: 12) {
                AccountSpinner()
                Text("RESTORING")
                    .font(Theme.title(13))
                    .tracking(3)
                    .foregroundStyle(Theme.gold)
                Text("Your island is coming down from iCloud.")
                    .font(Theme.body(11))
                    .foregroundStyle(cream.opacity(0.85))
            }
        }
        .transition(.opacity)
    }
}

/// A gold ring turning: the game's own spinner, so the veil is not a grey
/// system wheel on the key art.
struct AccountSpinner: View {
    @State private var turning = false

    var body: some View {
        Circle()
            .trim(from: 0.12, to: 0.88)
            .stroke(Theme.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .shadow(color: Color(hex: "#FFE49B").opacity(0.6), radius: 4)
            .frame(width: 34, height: 34)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { turning = true }
            }
    }
}

/// Apple's own button — the only one Apple accepts — wrapped so the rest of
/// the app speaks `AppleCredential` and never the framework's types. A
/// cancel is silent; error 1000 is worded as the capability switch it is.
struct AppleSignInButton: View {
    let onCredential: (AppleCredential) -> Void
    let onFailure: (String) -> Void

    init(onCredential: @escaping (AppleCredential) -> Void, onFailure: @escaping (String) -> Void) {
        self.onCredential = onCredential
        self.onFailure = onFailure
    }

    var body: some View {
        SignInWithAppleButton(
            .signIn,
            onRequest: { request in
                request.requestedScopes = [.fullName, .email]
            },
            onCompletion: { result in
                switch result {
                case .success(let authorization):
                    if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                        onCredential(AppleCredential.from(credential))
                    } else {
                        onFailure("That was not an Apple ID credential.")
                    }
                case .failure(let error):
                    if let sentence = AppleSignInButton.sentence(for: error) {
                        onFailure(sentence)
                    }
                }
            }
        )
        .signInWithAppleButtonStyle(.black)
        .frame(height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Apple's error as a sentence the owner can act on, or nil for a cancel.
    static func sentence(for error: Error) -> String? {
        guard let appleError = error as? ASAuthorizationError else { return error.localizedDescription }
        switch appleError.code {
        case .canceled:
            return nil
        case .unknown:
            return "Sign in with Apple is not switched on for this build (error 1000): tick the capability under Signing & Capabilities in Xcode, and on a Simulator sign in to an Apple ID in Settings."
        case .notInteractive:
            return "Sign in with Apple needs the screen: try again from the foreground."
        default:
            return appleError.localizedDescription
        }
    }
}

/// The Account panel's sheet for a guest: what binding does, Apple's button,
/// Not now.
struct BindAppleSheet: View {
    let onCredential: (AppleCredential) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var failure: String?

    init(onCredential: @escaping (AppleCredential) -> Void) {
        self.onCredential = onCredential
    }

    var body: some View {
        VStack(spacing: 14) {
            Text("BIND TO APPLE ID")
                .font(Theme.title(16))
                .tracking(2)
                .foregroundStyle(Theme.goldDim)
            Text("This phone's progress becomes your Apple ID's: it comes back on a new iPhone, it is safe if this one is lost, and support can find it by your Player ID.")
                .font(Theme.body(12))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            AppleSignInButton(
                onCredential: { credential in
                    dismiss()
                    onCredential(credential)
                },
                onFailure: { failure = $0 }
            )
            .frame(width: 280)
            if let failure {
                Text(failure)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.danger)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            Button {
                dismiss()
            } label: {
                Text("Not now")
                    .font(Theme.body(12).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(GamePressStyle(.plate))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}
