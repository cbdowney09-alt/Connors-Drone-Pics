# KnoxCanvas for Android

A native shell around `https://connorsdronepics.com/app.html`, the Android version of `ios/`.
The web page runs unchanged: `BridgeScript.kt` defines the same `window.webkit.messageHandlers.knox`
handler the iPhone app has, so `IS_NATIVE` is true and every bridge command works.

| File | What it does |
|---|---|
| `MainActivity.kt` | WebView, bridge messages, external links, alert/confirm/prompt, share sheet, offline page |
| `BridgeScript.kt` | Injected at document start: the `knox` handler, native `navigator.geolocation`, Google credential hook |
| `LocationBridge.kt` | The app's GPS: shift tracking buffer → `KnoxNative.onLocations`, the locate button, walking reminders |
| `TrackingService.kt` | Foreground service with the "Recording your route" notification while clocked in, so GPS keeps running with the screen locked |
| `GoogleSignIn.kt` | Native Google sign-in (Credential Manager) → `window.__knoxGoogleCredential` |
| `AppConfig.kt` | Site URL, allowed origins, Google Web client ID |

Location uses only **"While using the app"** plus a location foreground service. There's no
`ACCESS_BACKGROUND_LOCATION`, which Google reviews much more strictly.

## Build it (Windows or Mac)

1. Install **Android Studio** (it includes Java and the Android SDK).
2. **File → Open** and pick this `android` folder (not the repo root). Let Gradle sync.
   If it asks to create the Gradle wrapper or upgrade the Android Gradle plugin, say yes.
3. **Device Manager → Create virtual device**: a Pixel with a **Google Play** system image
   (needed for Google sign-in). Run ▶.

### Fake GPS in the emulator

Emulator toolbar **⋯ → Location**:
- **Single points:** search an address and click *Set location*. This is enough for the locate button.
- **Routes:** pick a start and end, choose *walking*, set playback speed 1×, then press *Play route*. Clock in
  first to test the street sweep and trail.

Lock the emulator screen (power button) during a route to check that points keep arriving: the trail
should have no gap when you unlock.

### Debugging the page

Debug builds allow `chrome://inspect` in Chrome on the same PC, which gives you a console for the page inside the app.

## Google sign-in setup

Until this is done, the Google button says "isn't set up yet". Email/password works either way.

1. Get the app's SHA-1: Android Studio **Gradle panel → app → Tasks → android → signingReport**
   (copy the `SHA1` of the `debug` variant). After the first Play upload, also add the **App signing key**
   SHA-1 from Play Console → Setup → App signing.
2. Firebase console → Project settings → **Add app → Android**, package `com.knoxcanvas.app`, paste the SHA-1.
   (No need to download `google-services.json`; this app doesn't use the Firebase Android SDK.)
3. Firebase console → Authentication → Sign-in method → Google → **Web SDK configuration → Web client ID**.
   Paste it into `AppConfig.GOOGLE_WEB_CLIENT_ID`.

## Play Store checklist

- **Account:** register as an **organization** (needs a free D-U-N-S number). A new personal account must run a
  closed test with 12 testers for 14 days before going public.
- **Package name:** `com.knoxcanvas.app` is permanent after the first upload. Change `applicationId` in
  `app/build.gradle.kts` first if you want something else.
- **Signing:** Build → Generate Signed App Bundle → create an upload key. Keep the `.jks` file and password
  somewhere safe and **out of this repo** (it's public). Play App Signing holds the real key.
- **Foreground service declaration** (App content → Foreground service permissions): type *Location*, reason
  "records the canvasser's walking route during a clocked-in shift to find the houses they visited", plus a short
  video: clock in, walk (emulator route is fine), lock the screen, show the notification, unlock, see the trail.
- **Location permission declaration** and **Data safety:** precise location (collected while clocked in, stored
  in the company's Firestore, not sold or shared), name, email. Privacy policy:
  `https://connorsdronepics.com/privacy.html`.
- **No prices or payment links in the app**, same as iOS.
- Before launch, do one real walk on a real Android phone. Samsung and other brands stop background apps more
  aggressively than the emulator does.
