import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Same wording as app.html's friendlyAuthError.
func friendlyAuthError(_ error: Error) -> String {
    let ns = error as NSError
    if ns.domain == AuthErrors.domain, let code = AuthErrorCode(rawValue: ns.code) {
        switch code {
        case .invalidCredential, .wrongPassword: return "Incorrect email or password."
        case .userNotFound: return "No account with that email. Create one below."
        case .emailAlreadyInUse: return "That email already has an account. Sign in instead."
        case .invalidEmail: return "That email address doesn\u{2019}t look right."
        case .weakPassword: return "Password must be at least 6 characters."
        case .tooManyRequests: return "Too many attempts. Wait a minute and try again."
        case .networkError: return "No connection. Check your signal and try again."
        case .userDisabled: return "This account has been disabled."
        case .operationNotAllowed:
            return "This sign-in method isn\u{2019}t enabled in Firebase (Authentication \u{2192} Sign-in method)."
        default: break
        }
    }
    let name = ns.userInfo[AuthErrors.userInfoNameKey] as? String ?? "\(ns.domain) \(ns.code)"
    return "Something went wrong (\(name)). Try again."
}

func firestoreCode(_ error: Error) -> FirestoreErrorCode.Code? {
    let ns = error as NSError
    return ns.domain == FirestoreErrorDomain ? FirestoreErrorCode.Code(rawValue: ns.code) : nil
}
