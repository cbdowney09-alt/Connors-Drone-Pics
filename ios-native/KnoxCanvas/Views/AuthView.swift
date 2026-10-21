import SwiftUI

struct AuthView: View {
    @Environment(SessionStore.self) private var session
    @State private var registering = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var error = ""
    @State private var info = ""
    @State private var busy: Busy?

    enum Busy { case login, register, google }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Logo().padding(.top, 40)
                Text("Door-to-door sales tracking for your whole team")
                    .font(.system(size: 16)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)

                Card {
                    if registering { registerForm } else { loginForm }
                    divider
                    KnoxButton(title: "Continue with Google", busyTitle: "Opening Google…", style: .google,
                               busy: busy == .google, action: google)
                    MessageText(error: error, info: info)
                }

                Text("Business owners: create an account, then set up your company. Team members: create an account, then join with the invite code from your manager.")
                    .font(.system(size: 14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var loginForm: some View {
        VStack(spacing: 12) {
            Text("Sign in").font(.title2.bold()).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
            KnoxField(placeholder: "Email", text: $email, content: .username, keyboard: .emailAddress, capitalization: .never)
            KnoxField(placeholder: "Password", text: $password, secure: true, content: .password, onSubmit: login)
            KnoxButton(title: "Sign in", busyTitle: "Signing in…", busy: busy == .login, action: login)
            LinkButton(title: "Forgot password?", action: forgot)
            HStack(spacing: 4) {
                Text("New here?").foregroundStyle(Theme.muted)
                LinkButton(title: "Create an account") { switchMode(true) }
            }.font(.system(size: 15))
        }
    }

    private var registerForm: some View {
        VStack(spacing: 12) {
            Text("Create your account").font(.title2.bold()).foregroundStyle(Theme.text).frame(maxWidth: .infinity, alignment: .leading)
            KnoxField(placeholder: "Your full name", text: $name, content: .name, capitalization: .words)
            KnoxField(placeholder: "Email", text: $email, content: .username, keyboard: .emailAddress, capitalization: .never)
            KnoxField(placeholder: "Password (6+ characters)", text: $password, secure: true, content: .newPassword, onSubmit: register)
            KnoxButton(title: "Create account", busyTitle: "Creating account…", busy: busy == .register, action: register)
            HStack(spacing: 4) {
                Text("Already have an account?").foregroundStyle(Theme.muted)
                LinkButton(title: "Sign in") { switchMode(false) }
            }.font(.system(size: 15))
        }
    }

    private var divider: some View {
        HStack {
            Rectangle().fill(Theme.border).frame(height: 1)
            Text("or").font(.system(size: 14)).foregroundStyle(Theme.muted)
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private func switchMode(_ reg: Bool) { registering = reg; error = ""; info = "" }
    private func setError(_ m: String) { error = m; if !m.isEmpty { info = "" } }
    private func setInfo(_ m: String) { info = m; if !m.isEmpty { error = "" } }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func login() {
        guard !trimmedEmail.isEmpty, !password.isEmpty else { return setError("Enter your email and password.") }
        run(.login) { try await session.signIn(email: trimmedEmail, password: password) }
    }

    private func register() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !trimmedEmail.isEmpty, !password.isEmpty else { return setError("Fill in your name, email and password.") }
        guard password.count >= 6 else { return setError("Password must be at least 6 characters.") }
        run(.register) { try await session.register(name: n, email: trimmedEmail, password: password) }
    }

    private func forgot() {
        guard !trimmedEmail.isEmpty else { return setError("Type your email in the box above first, then tap \"Forgot password?\"") }
        Task {
            do {
                try await session.resetPassword(email: trimmedEmail)
                setInfo("Reset link sent to \(trimmedEmail). Check your inbox and spam folder.")
            } catch { setError(error.localizedDescription) }
        }
    }

    private func google() {
        run(.google) { _ = try await session.signInWithGoogle() }
    }

    private func run(_ kind: Busy, _ work: @escaping () async throws -> Void) {
        setError("")
        busy = kind
        Task {
            defer { busy = nil }
            do { try await work() } catch { setError(error.localizedDescription) }
        }
    }
}
