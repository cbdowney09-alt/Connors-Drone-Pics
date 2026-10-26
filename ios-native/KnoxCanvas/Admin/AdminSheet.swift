import SwiftUI

/// KnoxCanvas admin: company requests, active teams and paused teams. Doorline clients also
/// list the admin's own team, to choose who hangs for them.
struct AdminSheet: View {
    @State private var admin: AdminStore
    @State private var confirm: (AdminStore.Row, Company.Status)?
    @State private var toastText: String?
    @State private var team: [Member] = []
    @State private var savingCrew = Set<String>()
    @State private var crewCode: (code: String, expires: Date)?
    @State private var makingCode = false
    @State private var confirmRemove: Member?
    private let homeCompanyId: String
    @Environment(\.openURL) private var openURL

    init(uid: String, homeCompanyId: String) {
        _admin = State(initialValue: AdminStore(uid: uid))
        self.homeCompanyId = homeCompanyId
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Admin").font(.title2.bold()).foregroundStyle(Theme.text)
                Text("Approve new companies once they\u{2019}ve paid. Pause a team to lock them out; nothing is deleted, and Resume brings everything back.")
                    .font(.system(size: 14)).foregroundStyle(Theme.muted)

                if let err = admin.loadError {
                    Text(err).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 20)
                } else if !admin.loaded {
                    ProgressView().tint(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 30)
                } else {
                    crewSection
                    section("Requests", .pending, empty: "No new requests")
                    section("Active", .active, empty: "No active companies")
                    section("Paused", .paused, empty: nil)
                    section("Declined", .declined, empty: nil)
                }
            }
            .padding(20)
        }
        .background(Theme.bg)
        .overlay(alignment: .bottom) {
            if let toastText { Toast(text: toastText).padding(.bottom, 16).transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.2), value: toastText)
        .onAppear { admin.start() }
        .task {
            guard !homeCompanyId.isEmpty else { return }
            team = (try? await TeamStore.fetchMembers(companyId: homeCompanyId)) ?? []
        }
        .onDisappear { admin.stop() }
        .confirmationDialog("Remove \(confirmRemove?.display ?? "") from the Doorline crew?",
                            isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }),
                            titleVisibility: .visible, presenting: confirmRemove) { m in
            Button("Remove", role: .destructive) {
                Task {
                    do { try await admin.removeCrew(m); toast("Removed") } catch { toast(error.localizedDescription) }
                }
            }
        } message: { _ in
            Text("They lose access to every business.")
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible, presenting: confirm) { c in
            Button(actionLabel(c.1, from: c.0.company.status), role: c.1 == .active ? nil : .destructive) { apply(c.0, c.1) }
        } message: { c in
            Text(confirmMessage(c.1))
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ status: Company.Status, empty: String?) -> some View {
        let list = admin.rows(status)
        if !list.isEmpty || empty != nil {
            Text("\(title.uppercased()) \u{00B7} \(list.count)")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted).padding(.top, 10)
            if list.isEmpty, let empty {
                Text(empty).foregroundStyle(Theme.muted).frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            ForEach(list) { row($0) }
        }
    }

    private func row(_ r: AdminStore.Row) -> some View {
        let c = r.company
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(c.name).font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.text)
                if c.doorline {
                    Text("Doorline").font(.system(size: 12, weight: .bold)).foregroundStyle(PinStatus.hanger.color)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(PinStatus.hanger.color.opacity(0.15), in: Capsule())
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                if !c.ownerName.isEmpty || !c.ownerEmail.isEmpty {
                    Text([c.ownerName, c.ownerEmail].filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
                }
                HStack(spacing: 10) {
                    if let d = c.requestedAt { Text(d.formatted(.dateTime.month(.abbreviated).day().year())) }
                    if let m = r.members { Text("\(m) member\(m == 1 ? "" : "s")") }
                    if let p = r.pins { Text("\(p) pins") }
                }
            }
            .font(.system(size: 14)).foregroundStyle(Theme.muted)

            HStack(spacing: 8) {
                if !c.phone.isEmpty {
                    small("Call", "phone.fill", Theme.field) { dial(c.phone) }
                }
                if !c.ownerEmail.isEmpty, let mail = URL(string: "mailto:\(c.ownerEmail)") {
                    small("Email", "envelope.fill", Theme.field) { openURL(mail) }
                }
            }
            HStack(spacing: 8) {
                switch c.status {
                case .pending:
                    small("Approve", "checkmark", PinStatus.interest.color) { confirm = (r, .active) }
                    small("Decline", "xmark", Theme.field) { confirm = (r, .declined) }
                case .active:
                    small("Pause", "pause.fill", Theme.field) { confirm = (r, .paused) }
                case .paused, .declined:
                    small(c.status == .paused ? "Resume" : "Approve", "play.fill", PinStatus.interest.color) { confirm = (r, .active) }
                }
            }
            if c.doorline { crew(r) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(c.status == .pending ? PinStatus.hanger.color.opacity(0.7) : Theme.border))
    }

    /// Crew invites and the crew who joined with one.
    @ViewBuilder
    private var crewSection: some View {
        Text("DOORLINE CREW").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted).padding(.top, 10)
        VStack(alignment: .leading, spacing: 10) {
            Text("A crew invite puts someone on your Doorline crew without joining any company. They create an account, choose \u{201C}Join my team\u{201D} and enter the code. Then pick the businesses they hang for below.")
                .font(.system(size: 14)).foregroundStyle(Theme.muted)
            KnoxButton(title: "Invite to Doorline crew", busyTitle: "Generating\u{2026}", busy: makingCode) {
                makingCode = true
                Task {
                    defer { makingCode = false }
                    do { crewCode = try await admin.createCrewInvite() } catch { toast(error.localizedDescription) }
                }
            }
            if let crewCode {
                VStack(spacing: 6) {
                    Text(crewCode.code).font(.system(size: 30, weight: .heavy, design: .monospaced)).tracking(4).foregroundStyle(Theme.accent)
                        .textSelection(.enabled)
                    Text("Expires \(crewCode.expires.formatted(.dateTime.month(.abbreviated).day())) \u{00B7} works once")
                        .font(.system(size: 14)).foregroundStyle(Theme.muted)
                    ShareLink(item: AdminStore.crewInviteMessage(code: crewCode.code)) {
                        Label("Share code", systemImage: "square.and.arrow.up").font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(Theme.field, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .foregroundStyle(Theme.text)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        ForEach(admin.crewOnly) { m in
            let n = admin.rows.filter { $0.company.crew.contains(m.uid) }.count
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.display).font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(n == 0 ? "Not assigned yet" : "Hangs for \(n) business\(n == 1 ? "" : "es")")
                        .font(.system(size: 14)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Remove") { confirmRemove = m }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.error).frame(minHeight: 44)
            }
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    /// Tap a name to have them hang for this business (they see it under "Hanging for").
    @ViewBuilder
    private func crew(_ r: AdminStore.Row) -> some View {
        Text("HANGS FOR THEM").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted).padding(.top, 4)
        let people = team + admin.crewOnly
        if people.isEmpty {
            Text("Invite your crew first (Invite to Doorline crew, above).").font(.system(size: 14)).foregroundStyle(Theme.muted)
        } else {
            FlowLayout(spacing: 8) {
                ForEach(people) { m in
                    let on = r.company.crew.contains(m.uid), key = r.id + m.uid
                    Button {
                        savingCrew.insert(key)
                        Task {
                            defer { savingCrew.remove(key) }
                            do { try await admin.setCrew(r.id, member: m.uid, on: !on) } catch { toast(error.localizedDescription) }
                        }
                    } label: {
                        Text(m.display).font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(on ? .white : Theme.muted)
                            .padding(.horizontal, 14).frame(minHeight: 40)
                            .background(on ? Theme.accent : Theme.field, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(savingCrew.contains(key))
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private func small(_ title: String, _ icon: String, _ bg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(bg, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dial(_ phone: String) {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        if let url = URL(string: "tel:\(digits)") { openURL(url) }
    }

    private var confirmTitle: String {
        guard let (r, s) = confirm else { return "" }
        return "\(actionLabel(s, from: r.company.status)) \(r.company.name)?"
    }

    private func actionLabel(_ s: Company.Status, from current: Company.Status) -> String {
        switch s {
        case .active: current == .paused ? "Resume" : "Approve"
        case .paused: "Pause"
        case .declined: "Decline"
        case .pending: "Mark pending"
        }
    }

    private func confirmMessage(_ s: Company.Status) -> String {
        switch s {
        case .active: "Their team gets access to the map right away."
        case .paused: "Their whole team is locked out until you resume. Nothing is deleted."
        case .declined: "The owner sees that the request wasn\u{2019}t approved."
        case .pending: ""
        }
    }

    private func apply(_ r: AdminStore.Row, _ s: Company.Status) {
        let done = switch s {
        case .active: r.company.status == .paused ? "resumed" : "approved"
        case .paused: "paused"
        case .declined: "declined"
        case .pending: "pending"
        }
        Task {
            do {
                try await admin.set(r.id, s)
                toast("\(r.company.name): \(done)")
            } catch { toast(error.localizedDescription) }
        }
    }

    private func toast(_ text: String) {
        toastText = text
        Task {
            try? await Task.sleep(for: .seconds(2.6))
            if toastText == text { toastText = nil }
        }
    }
}
