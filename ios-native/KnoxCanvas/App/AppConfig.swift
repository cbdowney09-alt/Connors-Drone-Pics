import Foundation

enum AppConfig {
    /// iOS OAuth client for Google sign-in (same one the ios/ wrapper uses).
    /// Its reversed form is the URL scheme in Info.plist.
    static let googleIOSClientID = "526600169975-dvs2b01apf96c4ae7roste08rd0d17sv.apps.googleusercontent.com"

    /// Firebase project `knoxcanvas-a7bfe`. Public by design (same values as app.html);
    /// access is enforced by Firestore security rules. Used only when no
    /// GoogleService-Info.plist is bundled.
    enum Firebase {
        static let apiKey = "AIzaSyCicUN1axUGBgFuznmQjX-9D6yf3R2HU88"
        static let projectID = "knoxcanvas-a7bfe"
        static let storageBucket = "knoxcanvas-a7bfe.firebasestorage.app"
        static let gcmSenderID = "526600169975"
        static let iosAppID = "1:526600169975:ios:b7850114064486969026f2"
    }

    static let geocodeWorker = URL(string: "https://broken-tree-befb.connorbdowney48.workers.dev")!
    static let inviteDays = 7
    static let defaultRoofCutoff = 2012
}
