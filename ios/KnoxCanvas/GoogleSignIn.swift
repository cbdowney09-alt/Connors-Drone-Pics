import AuthenticationServices
import CryptoKit
import UIKit

/// Google sign-in for the iOS app.
///
/// Google refuses to show its login page inside a WKWebView ("disallowed_useragent"), so the
/// page's popup/redirect flow can't work in the app. Instead we run Google's OAuth flow in
/// ASWebAuthenticationSession (the system browser sheet Google allows), exchange the code for
/// tokens, and hand the ID token to the page, which signs in to Firebase with
/// `signInWithCredential`. No SDK needed.
///
/// Setup: add an iOS app to the Firebase project and copy its CLIENT_ID into
/// `AppConfig.googleIOSClientID` (see CLAUDE.md → iOS app).
final class GoogleSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleSignIn()

    struct Tokens { let idToken: String; let accessToken: String? }

    enum SignInError: LocalizedError {
        case notConfigured, cancelled, failed(String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: return "Google sign-in isn't set up in the iPhone app yet. Use email and password for now."
            case .cancelled: return nil
            case .failed(let m): return m
            }
        }
    }

    private var session: ASWebAuthenticationSession?

    func signIn(completion: @escaping (Result<Tokens, SignInError>) -> Void) {
        guard session == nil else { return }   // already showing (popup + redirect can both trigger it)
        let clientID = AppConfig.googleIOSClientID
        guard clientID.hasSuffix(".apps.googleusercontent.com"), !clientID.hasPrefix("PASTE") else {
            return completion(.failure(.notConfigured))
        }
        // iOS OAuth clients use the "reversed client ID" as their redirect scheme.
        let scheme = clientID.components(separatedBy: ".").reversed().joined(separator: ".")
        let redirectURI = "\(scheme):/oauth2redirect"
        let verifier = Self.randomString(64)
        let state = Self.randomString(24)

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: Self.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "prompt", value: "select_account")
        ]

        let session = ASWebAuthenticationSession(url: comps.url!, callbackURLScheme: scheme) { [weak self] url, error in
            self?.session = nil
            if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                return DispatchQueue.main.async { completion(.failure(.cancelled)) }
            }
            guard let url,
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  items.first(where: { $0.name == "state" })?.value == state,
                  let code = items.first(where: { $0.name == "code" })?.value else {
                let reason = error?.localizedDescription ?? "Google didn't return a sign-in code."
                return DispatchQueue.main.async { completion(.failure(.failed(reason))) }
            }
            Self.exchange(code: code, clientID: clientID, redirectURI: redirectURI, verifier: verifier) { result in
                DispatchQueue.main.async { completion(result) }
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false   // remembers the Google account in Safari
        self.session = session
        if !session.start() { completion(.failure(.failed("Couldn't open Google sign-in."))) }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }

    // MARK: - Helpers

    private static func exchange(code: String, clientID: String, redirectURI: String, verifier: String,
                                 completion: @escaping (Result<Tokens, SignInError>) -> Void) {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "code": code, "client_id": clientID, "redirect_uri": redirectURI,
            "grant_type": "authorization_code", "code_verifier": verifier
        ]
        req.httpBody = form.map { "\($0.key)=\(formEncode($0.value))" }.joined(separator: "&").data(using: .utf8)
        URLSession.shared.dataTask(with: req) { data, _, error in
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return completion(.failure(.failed(error?.localizedDescription ?? "No connection. Try again.")))
            }
            guard let idToken = json["id_token"] as? String else {
                let msg = (json["error_description"] as? String) ?? (json["error"] as? String) ?? "Google sign-in failed."
                return completion(.failure(.failed(msg)))
            }
            completion(.success(Tokens(idToken: idToken, accessToken: json["access_token"] as? String)))
        }.resume()
    }

    private static func formEncode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private static func randomString(_ length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    private static func challenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
