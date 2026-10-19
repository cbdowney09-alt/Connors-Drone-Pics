import SwiftUI
import UIKit

/// Where the app loads KnoxCanvas from. Change this if you host app.html somewhere else.
enum AppConfig {
    static let appURL = URL(string: "https://connorsdronepics.com/app.html")!
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
