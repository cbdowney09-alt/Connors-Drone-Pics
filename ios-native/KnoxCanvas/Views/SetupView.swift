import SwiftUI

struct SetupView: View {
    @Environment(SessionStore.self) private var session
    @State private var joining = false
    @State private var name = ""
    @State private var companyName = ""
    @State private var code = ""
    @State private var phone = ""
    @State private var error = ""
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Logo().padding(.top, 40)
                Text("One more step").font(.system(size: 16)).foregroundStyle(Theme.muted)

                Card {
                    Text("Set up your account").font(.title2.bold()).foregroundStyle(Theme.text)
                    KnoxField(placeholder: "Your full name", text: $name, content: .name, capitalization: .words)

                    Picker("", selection: $joining) {
                        Text("I'm the owner").tag(false)
                        Text("Join my team").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)

                    if joining {
                        KnoxField(placeholder: "Invite code (e.g. AB12CD34)", text: $code, capitalization: .characters)
                            .font(.system(size: 17, design: .monospaced))
                            .onChange(of: code) { _, v in
                                let clean = v.uppercased().filter { ("A"..."Z").contains($0) || ("0"..."9").contains($0) }
                                if clean != v { code = clean }
                            }
                        hint("Ask your manager for a code. Codes expire after 7 days and work once.")
                        KnoxButton(title: "Join team", busyTitle: "Joining…", busy: busy, action: join)
                    } else {
                        KnoxField(placeholder: "Company name", text: $companyName, capitalization: .words)
                        KnoxField(placeholder: "Your phone number", text: $phone, content: .telephoneNumber, keyboard: .phonePad)
                        hint("New companies are approved by KnoxCanvas. We\u{2019}ll call or text you to get set up. Once you\u{2019}re approved, you can invite your canvassers.")
                        KnoxButton(title: "Request access", busyTitle: "Sending…", busy: busy, action: create)
                    }

                    MessageText(error: error, info: "")
                    LinkButton(title: "Sign out") { session.signOut() }.frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            name = session.pendingName.isEmpty ? (session.user?.displayName ?? "") : session.pendingName
            error = ""
        }
    }

    private func hint(_ s: String) -> some View {
        Text(s).font(.system(size: 14)).foregroundStyle(Theme.muted)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func create() {
        let c = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !c.isEmpty else { error = "Enter your name and your company name."; return }
        guard p.filter(\.isNumber).count >= 10 else { error = "Enter a phone number so we can reach you."; return }
        run { try await session.createCompany(name: trimmedName, companyName: c, phone: p) }
    }

    private func join() {
        guard !trimmedName.isEmpty, !code.isEmpty else { error = "Enter your name and the invite code."; return }
        run { try await session.joinCompany(name: trimmedName, code: code) }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        error = ""
        busy = true
        Task {
            defer { busy = false }
            do { try await work() } catch { self.error = error.localizedDescription }
        }
    }
}
