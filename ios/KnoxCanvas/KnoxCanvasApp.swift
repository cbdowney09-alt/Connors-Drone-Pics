import SwiftUI
import UIKit

/// Where the app loads KnoxCanvas from. Change this if you host app.html somewhere else.
enum AppConfig {
    static let appURL = URL(string: "https://connorsdronepics.com/app.html")!
    /// iOS OAuth client ID for Google sign-in. Firebase console → Project settings → Your apps →
    /// add an iOS app (same bundle ID as this target) → download GoogleService-Info.plist and
    /// copy its CLIENT_ID here. Looks like "1234567890-abc123.apps.googleusercontent.com".
    static let googleIOSClientID = "526600169975-dvs2b01apf96c4ae7roste08rd0d17sv.apps.googleusercontent.com"
    /// Background color shown before the page paints (matches --bg in app.html).
    static let background = UIColor(red: 15/255, green: 17/255, blue: 23/255, alpha: 1)
}

@main
struct KnoxCanvasApp: App {
    init() {
        // Create the location bridge at launch so a shift that was being tracked resumes.
        _ = LocationBridge.shared
    }

    var body: some Scene {
        WindowGroup {
            KnoxWebView(url: AppConfig.appURL)
                .ignoresSafeArea()
                .background(Color(AppConfig.background))
                .preferredColorScheme(.dark)
        }
    }
}
