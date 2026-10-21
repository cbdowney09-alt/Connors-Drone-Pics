import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import GoogleSignIn
import AuthenticationServices

/// Mirrors app.html's loadSession / setup flow.
@MainActor @Observable
final class SessionStore {
    enum Phase: Equatable {
        case loading(String)
        case loadError(String)
        case signedOut
        case setup
        /// The company is pending approval, paused or declined.
        case locked(Company.Status)
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
    /// Has an `admins/{uid}` doc: sees the Admin screen (approve, pause, resume companies).
    var isAdmin = false

    private let db = Firestore.firestore()
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var companyListener: ListenerRegistration?

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
            phase = company?.status == .active ? .ready : .locked(company?.status ?? .pending)
            watchCompany(cid)
            Task { await checkAdmin(user.uid) }
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

    /// Approval, pause and resume take effect right away: an approved request opens the map,
    /// a paused company drops back to the locked screen.
    private func watchCompany(_ cid: String) {
        companyListener?.remove()
        companyListener = db.collection("companies").document(cid).addSnapshotListener { [weak self] snap, _ in
            guard let self, let data = snap?.data(), cid == companyId else { return }
            let fallback = company?.name ?? "Your company"
            company = Company(data, fallbackName: fallback)
            let status = company?.status ?? .active
            switch (phase, status) {
            case (.ready, .active): break
            case (_, .active): phase = .ready
            case (.locked(let s), _) where s == status: break
            case (.ready, _), (.locked, _): phase = .locked(status)
            default: break
            }
        }
    }

    private func checkAdmin(_ uid: String) async {
        let snap = try? await db.collection("admins").document(uid).getDocument()
        isAdmin = snap?.exists == true
    }

    private func leave() {
        companyListener?.remove()
        companyListener = nil
        isAdmin = false
        profile = nil
        companyId = nil
        company = nil
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
    }

    /// After the owner saves company settings.
    func applyCompanySettings(name: String, sheetsUrl: String) {
        company?.name = name
        company?.sheetsUrl = sheetsUrl
    }

    /// Like the web's delete-account button. An owner must remove their team first; the
    /// company doc goes with the owner. Checked up front so nothing is deleted when Firebase
    /// would refuse to delete the login (it needs a sign-in in the last few minutes).
    func deleteAccount() async throws {
        guard let user else { return }
        let uid = user.uid
        // Apple accounts confirm with Apple right here: that counts as a fresh sign-in, and the
        // authorization code lets us revoke the Apple login, which App Store rules require.
        var appleCode: String?
        if user.providerData.contains(where: { $0.providerID == "apple.com" }) {
            do {
                let (apple, nonce) = try await AppleSignIn.request()
                try await user.reauthenticate(with: try AppleSignIn.firebaseCredential(apple, nonce: nonce))
                appleCode = apple.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            } catch let e as Friendly { throw e }
            catch {
                if AppleSignIn.isCanceled(error) { throw Friendly("Account not deleted.") }
                throw Friendly("Couldn\u{2019}t confirm with Apple (\(error.localizedDescription))")
            }
        } else if let last = user.metadata.lastSignInDate, Date().timeIntervalSince(last) > 4 * 60 {
            throw Friendly("For security, sign out, sign back in, and then delete your account.")
        }
        // Deleting needs the server: queued deletes could land later and leave half an account.
        do { _ = try await db.collection("users").document(uid).getDocument(source: .server) }
        catch { throw Friendly("You need a connection to delete your account.") }
        do {
            if profile?.isOwner == true, let cid = companyId {
                let members = try await db.collection("users").whereField("companyId", isEqualTo: cid).getDocuments(source: .server).documents
                if members.count > 1 {
                    throw Friendly("Remove your team members first (Account \u{2192} Team and company settings), then delete your account.")
                }
                try await db.collection("companies").document(cid).delete()
            }
            try await db.collection("users").document(uid).delete()
            UserDefaults.standard.removeObject(forKey: "knoxClock_\(uid)")
            UserDefaults.standard.removeObject(forKey: "knoxTrail_\(uid)")
            if let appleCode { try? await Auth.auth().revokeToken(withAuthorizationCode: appleCode) }
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

    /// Finishes Sign in with Apple after the system sheet. Apple shares the name only the
    /// first time, so it becomes the Firebase display name (used to prefill setup).
    func signInWithApple(_ apple: ASAuthorizationAppleIDCredential, nonce: String) async throws {
        let credential = try AppleSignIn.firebaseCredential(apple, nonce: nonce)
        let name = [apple.fullName?.givenName, apple.fullName?.familyName].compactMap { $0 }.joined(separator: " ")
        if !name.isEmpty { pendingName = name }
        do {
            let result = try await Auth.auth().signIn(with: credential)
            if !name.isEmpty, (result.user.displayName ?? "").isEmpty {
                let change = result.user.createProfileChangeRequest()
                change.displayName = name
                try? await change.commitChanges()
            }
        } catch { throw Friendly(friendlyAuthError(error)) }
    }

    // MARK: - Setup (create or join a company)

    /// Requests a new company. It starts `pending`; the admin approves it in the Admin screen
    /// (and gets an email if `AppConfig.requestWebhook` is set).
    func createCompany(name: String, companyName: String, phone: String) async throws {
        guard let user else { return }
        let companyRef = db.collection("companies").document()
        let batch = db.batch()
        batch.setData(["name": companyName, "ownerId": user.uid, "roofCutoff": AppConfig.defaultRoofCutoff,
                       "sheetsUrl": "", "createdAt": FieldValue.serverTimestamp(),
                       "status": Company.Status.pending.rawValue, "ownerName": name, "ownerEmail": user.email ?? "",
                       "phone": phone, "requestedAt": FieldValue.serverTimestamp()], forDocument: companyRef)
        batch.setData(["name": name, "email": user.email ?? "", "role": "owner", "companyId": companyRef.documentID,
                       "companyName": companyName, "createdAt": FieldValue.serverTimestamp()],
                      forDocument: db.collection("users").document(user.uid))
        do { try await batch.commit() }
        catch {
            throw Friendly(firestoreCode(error) == .permissionDenied
                ? "Permission denied \u{2014} the Firestore security rules need to be published."
                : "Couldn\u{2019}t send the request (\(error.localizedDescription)).")
        }
        pendingName = ""
        RequestNotifier.send(company: companyName, companyId: companyRef.documentID, owner: name,
                             email: user.email ?? "", phone: phone)
        await loadSession(user)
    }

    /// After a declined request: clears the profile so the owner can request again or join a team.
    func startOver() async throws {
        guard let user else { return }
        do { try await db.collection("users").document(user.uid).delete() }
        catch { throw Friendly("Couldn\u{2019}t start over (\(error.localizedDescription))") }
        await loadSession(user)
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
