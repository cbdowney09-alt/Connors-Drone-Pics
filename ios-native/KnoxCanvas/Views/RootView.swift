import SwiftUI

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch session.phase {
            case .loading(let msg): LoadingView(message: msg, failed: false)
            case .loadError(let msg): LoadingView(message: msg, failed: true)
            case .signedOut: AuthView()
            case .setup: SetupView()
            case .locked(let status): LockedView(status: status)
            case .crewWaiting: LockedView(status: .pending, crewWaiting: true)
            case .ready: HomeView()
            }
        }
        .overlay(alignment: .top) {
            if let toast = session.toast {
                Toast(text: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast) {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation { session.toast = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.phase)
        .animation(.easeInOut, value: session.toast)
        .onAppear { session.start() }
    }
}

struct LoadingView: View {
    @Environment(SessionStore.self) private var session
    let message: String
    let failed: Bool

    var body: some View {
        VStack(spacing: 20) {
            Logo()
            if !failed { ProgressView().controlSize(.large).tint(Theme.accent) }
            Text(message).font(.system(size: 16)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            if failed {
                VStack(spacing: 12) {
                    KnoxButton(title: "Try again") { session.retry() }
                    KnoxButton(title: "Sign out", style: .ghost) { session.signOut() }
                }
            }
        }
        .padding(24)
    }
}
