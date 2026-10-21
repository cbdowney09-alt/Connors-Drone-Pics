import SwiftUI
import GoogleSignIn

@main
struct KnoxCanvasApp: App {
    @State private var session: SessionStore

    init() {
        FirebaseBootstrap.configure()
        _session = State(initialValue: SessionStore())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
        }
    }
}
