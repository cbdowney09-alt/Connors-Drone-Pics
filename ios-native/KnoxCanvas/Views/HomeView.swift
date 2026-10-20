import SwiftUI
import MapKit

/// Phase 1 placeholder for the map screen: an empty map plus the account basics.
/// Pins, filters and the tab bar arrive in Phase 2.
struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @State private var showAccount = false

    var body: some View {
        ZStack(alignment: .top) {
            CanvasMapView().ignoresSafeArea()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.profile?.name.isEmpty == false ? session.profile!.name : (session.user?.email ?? ""))
                        .font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(session.company?.name ?? "").font(.system(size: 14)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button { showAccount = true } label: {
                    Image(systemName: "person.crop.circle").font(.system(size: 26)).foregroundStyle(Theme.text)
                        .frame(width: 48, height: 48)
                }
                .accessibilityLabel("Account")
            }
            .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 6)
            .background(Theme.card.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.border))
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .sheet(isPresented: $showAccount) { AccountSheet().presentationDetents([.medium]) }
    }
}

struct AccountSheet: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Account").font(.title2.bold()).foregroundStyle(Theme.text)
            row("Name", session.profile?.name)
            row("Email", session.user?.email)
            row("Company", session.company?.name)
            row("Role", session.profile?.role)
            Spacer()
            KnoxButton(title: "Sign out", style: .ghost) { session.signOut() }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
    }

    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.muted)
            Spacer()
            Text(value ?? "").foregroundStyle(Theme.text)
        }
        .font(.system(size: 17))
    }
}

/// MKMapView wrapper. SwiftUI's Map can't cluster thousands of pins, so Phase 2 builds on this.
struct CanvasMapView: UIViewRepresentable {
    static let knoxville = CLLocationCoordinate2D(latitude: 35.9606, longitude: -83.9207)

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        let config = MKStandardMapConfiguration()
        config.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = config
        map.overrideUserInterfaceStyle = .dark
        map.setRegion(MKCoordinateRegion(center: Self.knoxville, latitudinalMeters: 8000, longitudinalMeters: 8000), animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {}
}
