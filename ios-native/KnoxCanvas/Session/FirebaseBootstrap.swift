import FirebaseCore
import FirebaseFirestore
import GoogleSignIn

enum FirebaseBootstrap {
    static func configure() {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        } else {
            // No plist bundled: build the same options from AppConfig (values from the
            // project's GoogleService-Info.plist, which is public by design).
            let c = AppConfig.Firebase.self
            let options = FirebaseOptions(googleAppID: c.iosAppID, gcmSenderID: c.gcmSenderID)
            options.apiKey = c.apiKey
            options.projectID = c.projectID
            options.storageBucket = c.storageBucket
            FirebaseApp.configure(options: options)
        }

        // Offline persistence is the default; set it explicitly so it never silently changes.
        let settings = FirestoreSettings()
        settings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = settings

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: AppConfig.googleIOSClientID)
    }
}
