import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn

/// Mirrors app.html's loadSession / setup flow.
@MainActor @Observable
final class SessionStore {
    enum Phase: Equatable {
        case loading(String)
        case loadError(String)
        case signedOut
        case setup
        case ready
    }

    var phase: Phase = .loading("Loading…")
    var user: User?
    var profile: UserProfile?
    var companyId: String?
    var company: Company?
    /// Name typed on the register form, used to prefill setup.
    var pendingName = ""
    var toast: String?

    private let db = Firestore.firestore()
    private var authHandle: AuthStateDidChangeListenerHandle?

    func start() {
        guard authHandle == nil else { return }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in await self?.loadSession(user) }
        }
    }

    func retry() { Task { await loadSession(Auth.auth().currentUser) } }

    func loadSession(_ user: User?) async {
        self.user = user
        guard let user else { leave(); phase = .signedOut; return }
        phase = .loading("Loading your account…")
        do {
            let snap = try await db.collection("users").document(user.uid).getDocument()
            let p = snap.data().map(UserProfile.init)
            guard let p, let cid = p.companyId else { phase = .setup; return }
            profile = p
            companyId = cid
            do {
                let c = try await db.collection("companies").document(cid).getDocument()
                company = Company(c.data() ?? [:], fallbackName: p.companyName.isEmpty ? "Your company" : p.companyName)
            } catch {
                company = Company([:], fallbackName: p.companyName.isEmpty ? "Your company" : p.companyName)
            }
            phase = .ready
        } catch {
            switch firestoreCode(error) {
            case .permissionDenied:
                phase = .loadError("Your account couldn\u{2019}t be loaded (permission denied). The Firestore security rules need to be published \u{2014} see the setup notes.")
            case .unavailable:
                phase = .loadError("You\u{2019}re offline and this device hasn\u{2019}t loaded your account before. Connect to the internet and try again.")
            default:
                phase = .loadError("Couldn\u{2019}t load your account (\(error.localizedDescription)).")
            }
        }
    }

    private func leave() {
        profile = nil
        companyId = nil
        company = nil
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
    }

    /// After the owner saves company settings.
    func applyCompanySettings(name: String, roofCutoff: Int, sheetsUrl: String) {
        company?.name = name
        company?.roofCutoff = roofCutoff
        company?.sheetsUrl = sheetsUrl
    }

    /// Like the web's delete-account button. An owner must remove their team first; the
    /// company doc goes with the owner. Checked up front so nothing is deleted when Firebase
    /// would refuse to delete the login (it needs a sign-in in the last few minutes).
    func deleteAccount() async throws {
        guard let user else { return }
        let uid = user.uid
        if let last = user.metadata.lastSignInDate, Date().timeIntervalSince(last) > 4 * 60 {
            throw Friendly("For security, sign out, sign back in, and then delete your account.")
        }
        do {
            if profile?.isOwner == true, let cid = companyId {
                let members = try await TeamStore.fetchMembers(companyId: cid)
                if members.count > 1 {
                    throw Friendly("Remove your team members first (Account \u{2192} Team and company settings), then delete your account.")
                }
                try await db.collection("companies").document(cid).delete()
            }
            try await db.collection("users").document(uid).delete()
            UserDefaults.standard.removeObject(forKey: "knoxClock_\(uid)")
            UserDefaults.standard.removeObject(forKey: "knoxTrail_\(uid)")
            try await user.delete()
        } catch let e as Friendly {
            throw e
        } catch {
            if (error as NSError).code == AuthErrorCode.requiresRecentLogin.rawValue {
                throw Friendly("For security, sign out, sign back in, and then delete your account.")
            }
            throw Friendly("Couldn\u{2019}t delete account (\(error.localizedDescription))")
        }
        GIDSignIn.sharedInstance.signOut()
    }

    // MARK: - Auth actions (throw friendly messages)

    func signIn(email: String, password: String) async throws {
        do { try await Auth.auth().signIn(withEmail: email, password: password) }
        catch { throw Friendly(friendlyAuthError(error)) }
    }

    func register(name: String, email: String, password: String) async throws {
        pendingName = name
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let change = result.user.createProfileChangeRequest()
            change.displayName = name
            try? await change.commitChanges()
        } catch { throw Friendly(friendlyAuthError(error)) }
    }

    func resetPassword(email: String) async throws {
        do { try await Auth.auth().sendPasswordReset(withEmail: email) }
        catch { throw Friendly(friendlyAuthError(error)) }
    }

    /// Returns false if the user cancelled.
    func signInWithGoogle() async throws -> Bool {
        guard let presenter = UIApplication.shared.topViewController else { return false }
        let result: GIDSignInResult
        do {
            result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
        } catch {
            let ns = error as NSError
            if ns.domain == kGIDSignInErrorDomain && ns.code == GIDSignInError.canceled.rawValue { return false }
            throw Friendly(error.localizedDescription)
        }
        guard let idToken = result.user.idToken?.tokenString else {
            throw Friendly("Google didn\u{2019}t return a sign-in token. Try again.")
        }
        let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                       accessToken: result.user.accessToken.tokenString)
        do { try await Auth.auth().signIn(with: credential) }
        catch { throw Friendly(friendlyAuthError(error)) }
        return true
    }

    // MARK: - Setup (create or join a company)

    func createCompany(name: String, companyName: String) async throws {
        guard let user else { return }
        let companyRef = db.collection("companies").document()
        let batch = db.batch()
        batch.setData(["name": companyName, "ownerId": user.uid, "roofCutoff": AppConfig.defaultRoofCutoff,
                       "sheetsUrl": "", "createdAt": FieldValue.serverTimestamp()], forDocument: companyRef)
        batch.setData(["name": name, "email": user.email ?? "", "role": "owner", "companyId": companyRef.documentID,
                       "companyName": companyName, "createdAt": FieldValue.serverTimestamp()],
                      forDocument: db.collection("users").document(user.uid))
        do { try await batch.commit() }
        catch {
            throw Friendly(firestoreCode(error) == .permissionDenied
                ? "Permission denied \u{2014} the Firestore security rules need to be published."
                : "Couldn\u{2019}t create the company (\(error.localizedDescription)).")
        }
        pendingName = ""
        await loadSession(user)
        toast = "Welcome! \(companyName) is set up."
    }

    func joinCompany(name: String, code: String) async throws {
        guard let user else { return }
        let joinedName: String
        do {
            let inv = try await db.collection("invites").document(code).getDocument()
            guard inv.exists, let d = inv.data() else {
                throw Friendly("That code isn\u{2019}t valid. Ask your manager for a new one.")
            }
            guard let expires = d["expiresAt"] as? Timestamp, expires.dateValue() >= Date() else {
                throw Friendly("That code has expired. Ask your manager for a new one.")
            }
            joinedName = d["companyName"] as? String ?? ""
            let batch = db.batch()
            batch.setData(["name": name, "email": user.email ?? "", "role": "employee",
                           "companyId": d["companyId"] as? String ?? "", "companyName": joinedName,
                           "inviteCode": code, "createdAt": FieldValue.serverTimestamp()],
                          forDocument: db.collection("users").document(user.uid))
            batch.deleteDocument(db.collection("invites").document(code))
            try await batch.commit()
        } catch let e as Friendly {
            throw e
        } catch {
            throw Friendly(firestoreCode(error) == .permissionDenied
                ? "That code couldn\u{2019}t be used. It may have expired or already been used."
                : "Couldn\u{2019}t join (\(error.localizedDescription)).")
        }
        pendingName = ""
        await loadSession(user)
        toast = "You joined \(joinedName.isEmpty ? "the team" : joinedName)"
    }
}

/// An error whose message is already worded for the canvasser.
struct Friendly: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

extension UIApplication {
    var topViewController: UIViewController? {
        let window = connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
