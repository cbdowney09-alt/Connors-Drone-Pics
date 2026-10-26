import SwiftUI

/// Shown instead of the map while the company is pending approval, paused or declined.
/// It updates on its own: SessionStore watches the company doc.
struct LockedView: View {
    @Environment(SessionStore.self) private var session
    let status: Company.Status
    /// Doorline crew not assigned to a business yet.
    var crewWaiting = false
    @State private var busy = false
    @State private var error = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Logo().padding(.top, 60)
                Card {
                    Image(systemName: icon).font(.system(size: 34)).foregroundStyle(color)
                    Text(title).font(.title2.bold()).foregroundStyle(Theme.text)
                    Text(message).font(.system(size: 16)).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let mail = URL(string: "mailto:\(AppConfig.supportEmail)") {
                        Link(destination: mail) {
                            Label(AppConfig.supportEmail, systemImage: "envelope")
                                .font(.system(size: 16, weight: .semibold)).frame(minHeight: 44)
                        }
                        .foregroundStyle(Theme.accent)
                    }
                    if status == .declined {
                        KnoxButton(title: "Start over", busyTitle: "Starting over\u{2026}", busy: busy) {
                            busy = true
                            Task {
                                defer { busy = false }
                                do { try await session.startOver() } catch { self.error = error.localizedDescription }
                            }
                        }
                    }
                    MessageText(error: error, info: "")
                    KnoxButton(title: "Sign out", style: .ghost) { session.signOut() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
    }

    private var company: String { session.company?.name ?? "Your company" }

    private var icon: String {
        if crewWaiting { return "door.left.hand.open" }
        return switch status {
        case .pending: "hourglass"
        case .paused: "pause.circle.fill"
        default: "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .pending: PinStatus.hanger.color
        case .paused: Theme.muted
        default: Theme.error
        }
    }

    private var title: String {
        if crewWaiting { return "You\u{2019}re on the Doorline crew" }
        return switch status {
        case .pending: "Request sent"
        case .paused: "\(company) is paused"
        default: "Request not approved"
        }
    }

    private var message: String {
        if crewWaiting { return "As soon as you\u{2019}re assigned to a business, its map opens here on its own. Nothing to do until then." }
        switch status {
        case .pending:
            let phone = session.company?.phone ?? ""
            return "\(company) is waiting for approval. We\u{2019}ll reach out\(phone.isEmpty ? "" : " at \(phone)") to finish getting you set up. This screen opens the map on its own once you\u{2019}re approved."
        case .paused:
            return "Your team\u{2019}s account is paused. Your pins and shifts are saved and will all be here when it\u{2019}s turned back on. Contact KnoxCanvas to get it running again."
        default:
            return "This company request wasn\u{2019}t approved. Contact KnoxCanvas with any questions, or start over to join a team with an invite code."
        }
    }
}
