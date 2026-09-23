import Foundation
import UIKit
import AuthenticationServices

/// Why a fresh Apple authorization did not come back.
enum AppleReauthorizationError: Error, Equatable {
    /// The player closed Apple's sheet: nothing is deleted.
    case canceled
    /// Anything else, worded; the deletion goes ahead without revoking, and
    /// the player is told how to stop using the Apple ID by hand.
    case failed(String)
}

/// A fresh Sign in with Apple authorization at the moment an account is
/// deleted (`Docs/SETTINGS.md` §3): Apple's own sheet (Face ID or the
/// passcode) with no scopes asked, which proves the person deleting is the
/// Apple ID's owner and hands over a one-time authorization code — the thing
/// the `apple-revoke` Edge Function exchanges for a refresh token and
/// revokes, as Apple requires of an app that offers Sign in with Apple — and
/// a fresh identity token, which signs the backend back in if its session
/// had lapsed.
///
/// A plain `ASAuthorizationController`, not the system button: the button is
/// for signing IN, and here the player has already pressed Delete account.
/// Keep a strong reference while it runs; the controller's delegate is weak.
final class AppleReauthorizer: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    /// Resumes the waiting `authorize()` — once.
    private var resume: ((Result<AppleCredential, Error>) -> Void)?
    private var controller: ASAuthorizationController?

    /// Presents Apple's sheet and returns the credential, or throws
    /// `AppleReauthorizationError`.
    @MainActor
    func authorize() async throws -> AppleCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = []
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        return try await withCheckedThrowingContinuation { continuation in
            self.resume = { result in continuation.resume(with: result) }
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            finish(.failure(AppleReauthorizationError.failed("That was not an Apple ID credential.")))
            return
        }
        finish(.success(AppleCredential.from(credential)))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let apple = error as? ASAuthorizationError, apple.code == .canceled {
            finish(.failure(AppleReauthorizationError.canceled))
        } else {
            finish(.failure(AppleReauthorizationError.failed(error.localizedDescription)))
        }
    }

    /// The window Apple's sheet stands over: the key window of the game's
    /// scene.
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        return windows.first { $0.isKeyWindow } ?? windows.first ?? ASPresentationAnchor()
    }

    /// Once: Apple answers exactly once per request, and the continuation
    /// must be resumed exactly once.
    private func finish(_ result: Result<AppleCredential, Error>) {
        guard let resume else { return }
        self.resume = nil
        controller = nil
        resume(result)
    }
}
