import AuthenticationServices
import CryptoKit
import FirebaseAuth

/// Sign in with Apple for Firebase. Apple returns the ID token for a hashed nonce; Firebase
/// checks it against the raw nonce. Apple only sends the person's name on the very first
/// sign-in, so it's saved as the display name then.
enum AppleSignIn {
    /// The raw nonce for a request; its SHA-256 goes in `request.nonce`.
    static func makeNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: length)
        if SecRandomCopyBytes(kSecRandomDefault, length, &bytes) != errSecSuccess {
            bytes = bytes.map { _ in UInt8.random(in: 0...255) }
        }
        return String(bytes.map { chars[Int($0) % chars.count] })
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func firebaseCredential(_ apple: ASAuthorizationAppleIDCredential, nonce: String) throws -> AuthCredential {
        guard let token = apple.identityToken, let idToken = String(data: token, encoding: .utf8) else {
            throw Friendly("Apple didn\u{2019}t return a sign-in token. Try again.")
        }
        return OAuthProvider.appleCredential(withIDToken: idToken, rawNonce: nonce, fullName: apple.fullName)
    }

    static func isCanceled(_ error: Error) -> Bool {
        (error as? ASAuthorizationError)?.code == .canceled
    }

    /// Runs the Apple sheet without the SwiftUI button (used to re-confirm before deleting an
    /// account, which also gives the authorization code Apple requires to revoke the login).
    @MainActor
    static func request(scopes: [ASAuthorization.Scope] = []) async throws -> (ASAuthorizationAppleIDCredential, String) {
        let nonce = makeNonce()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = scopes
        request.nonce = sha256(nonce)
        let runner = Runner()
        let credential = try await runner.run(request)
        return (credential, nonce)
    }

    @MainActor
    private final class Runner: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
        private var controller: ASAuthorizationController?

        func run(_ request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorizationAppleIDCredential {
            try await withCheckedThrowingContinuation { c in
                continuation = c
                let controller = ASAuthorizationController(authorizationRequests: [request])
                controller.delegate = self
                controller.presentationContextProvider = self
                self.controller = controller // kept alive until Apple answers
                controller.performRequests()
            }
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            if let cred = authorization.credential as? ASAuthorizationAppleIDCredential {
                continuation?.resume(returning: cred)
            } else {
                continuation?.resume(throwing: Friendly("Apple sign-in didn\u{2019}t return an Apple ID."))
            }
            continuation = nil
            self.controller = nil
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            continuation?.resume(throwing: error)
            continuation = nil
            self.controller = nil
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
