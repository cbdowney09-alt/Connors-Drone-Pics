import SwiftUI

/// The web's "Team and settings" panel: invite codes, team members, company settings.
struct TeamSheet: View {
    @Environment(SessionStore.self) private var session
    @State private var team: TeamStore
    @State private var toastText: String?

    @State private var invite: (code: String, expires: Date)?
    @State private var generating = false
    @State private var removing: Member?
    @State private var name = ""
    @State private var sheetsUrl = ""
    @State private var saving = false
    @State private var settingsError = ""
    @State private var pickingStates = false

    init(companyId: String, uid: String) {
        _team = State(initialValue: TeamStore(companyId: companyId, uid: uid))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Team and settings").font(.title2.bold()).foregroundStyle(Theme.text)

                section("Invite a team member")
                inviteCard

                section("Team members")
                members

                section("States you work in")
                statesCard

                section("Company settings")
                settings
            }
            .padding(20)
        }
        .background(Theme.bg)
        .scrollDismissesKeyboard(.interactively)
        .overlay(alignment: .bottom) {
            if let toastText { Toast(text: toastText).padding(.bottom, 16).transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.2), value: toastText)
        .task {
            if let c = session.company {
                name = c.name
                sheetsUrl = c.sheetsUrl
            }
            await team.loadMembers()
        }
        .confirmationDialog(removeTitle, isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { m in
            Button("Remove", role: .destructive) {
                Task {
                    do { try await team.remove(m); toast("Removed") }
                    catch { toast(error.localizedDescription) }
                }
            }
        } message: { _ in
            Text("They\u{2019}ll lose access to your company\u{2019}s data.")
        }
    }

    /// The map's toast sits under this sheet, so it gets its own.
    private func toast(_ text: String) {
        toastText = text
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if toastText == text { toastText = nil }
        }
    }

    private var removeTitle: String { "Remove \(removing?.display ?? "") from your team?" }

    private func section(_ title: String) -> some View {
        Text(title.uppercased()).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted).padding(.top, 4)
    }

    // MARK: Invite

    private var inviteCard: some View {
        Card {
            Text("They create an account, choose \u{201C}Join my team\u{201D}, and enter this code. Each code works once and expires in \(AppConfig.inviteDays) days.")
                .font(.system(size: 15)).foregroundStyle(Theme.muted)
            KnoxButton(title: invite == nil ? "Generate invite code" : "Generate another code",
                       busyTitle: "Generating\u{2026}", busy: generating) { generate() }
            if let invite {
                VStack(spacing: 6) {
                    Text(invite.code)
                        .font(.system(size: 34, weight: .heavy, design: .monospaced)).tracking(4)
                        .foregroundStyle(Theme.text).textSelection(.enabled)
                    Text("Expires \(invite.expires.formatted(.dateTime.month(.abbreviated).day())) \u{00B7} works once")
                        .font(.system(size: 14)).foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                HStack(spacing: 8) {
                    KnoxButton(title: "Copy", style: .ghost) {
                        UIPasteboard.general.string = invite.code
                        toast("Code copied")
                    }
                    ShareLink(item: TeamStore.inviteMessage(code: invite.code, companyName: session.company?.name ?? "")) {
                        Text("Share").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: Theme.tapHeight)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.radius))
                    }
                }
            }
        }
    }

    private func generate() {
        generating = true
        Task {
            defer { generating = false }
            do { invite = try await team.createInvite(companyName: session.company?.name ?? "") }
            catch { toast(error.localizedDescription) }
        }
    }

    // MARK: Members

    @ViewBuilder private var members: some View {
        if let err = team.loadError {
            VStack(spacing: 10) {
                Text(err).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                LinkButton(title: "Try again") { Task { await team.loadMembers() } }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
        } else if team.members.isEmpty {
            Text(team.loading ? "Loading team\u{2026}" : "No team members yet")
                .foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 16)
        } else {
            VStack(spacing: 8) {
                ForEach(team.members) { m in memberRow(m) }
            }
        }
    }

    private func memberRow(_ m: Member) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text((m.name.isEmpty ? "Unnamed" : m.name) + (m.uid == team.uid ? " (you)" : ""))
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                Text("\(m.email) \u{00B7} \(m.role)").font(.system(size: 14)).foregroundStyle(Theme.muted)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if m.role == "employee" {
                Button("Remove") { removing = m }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.error)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(minHeight: 64)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border))
    }

    // MARK: States

    private var statesCard: some View {
        let codes = session.company?.states ?? []
        return Card {
            Text(codes.isEmpty ? "None picked yet. Pick your states so your team\u{2019}s phones download their houses."
                               : codes.map { StatePacks.shared.name($0) }.joined(separator: ", "))
                .font(.system(size: 16)).foregroundStyle(codes.isEmpty ? Theme.muted : Theme.text)
            KnoxButton(title: codes.isEmpty ? "Pick states" : "Change states", style: codes.isEmpty ? .primary : .ghost) {
                pickingStates = true
            }
        }
        .sheet(isPresented: $pickingStates) {
            CompanyStatesSheet(initial: codes, title: "States you work in") { picked in
                try await team.saveStates(picked)
                session.applyCompanyStates(picked)
                StatePacks.shared.ensure(picked)
            }
            .presentationDetents([.large])
        }
    }

    // MARK: Settings

    private var settings: some View {
        Card {
            labeled("Company name") { KnoxField(placeholder: "Company name", text: $name, capitalization: .words) }
            labeled("Google Sheets webhook URL (optional)") {
                KnoxField(placeholder: "https://script.google.com/macros/s/\u{2026}/exec", text: $sheetsUrl,
                          content: .URL, keyboard: .URL, capitalization: .never)
            }
            MessageText(error: settingsError, info: "")
            KnoxButton(title: "Save settings", busyTitle: "Saving\u{2026}", busy: saving) { save() }
        }
    }

    private func labeled<F: View>(_ label: String, @ViewBuilder field: () -> F) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.muted)
            field()
        }
    }

    private func save() {
        settingsError = ""
        saving = true
        Task {
            defer { saving = false }
            do {
                let (n, u) = try await team.saveSettings(name: name, sheetsUrl: sheetsUrl)
                session.applyCompanySettings(name: n, sheetsUrl: u)
                name = n; sheetsUrl = u
                toast("Settings saved")
            } catch { settingsError = error.localizedDescription }
        }
    }
}
