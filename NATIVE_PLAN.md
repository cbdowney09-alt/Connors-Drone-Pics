# KnoxCanvas native iOS rewrite: plan

Goal: replace the WKWebView wrapper (`ios/`) with a real SwiftUI app that does everything
`app.html` does. It reads and writes **the same Firestore data**, so the website and the native
app work side by side on the same company.

Work in phases. Finish each phase with a clean build and a run in the simulator before starting
the next. Commit after every phase.

## Ground rules

1. **Same data.** Use the schema in CLAUDE.md exactly: same collections, field names, pin ID
   format (`lat.toFixed(6),lng.toFixed(6)`), status keys (`none hanger interest no dnr`) and
   timestamps (epoch ms numbers for `ts`, `statusAt`, `hangerAt`, `clockIn`, `clockOut`).
   Never rename or remove a field. A pin saved by the iPhone app must look identical to one
   saved by the website.
2. **Don't develop against the real company.** Create a test owner account and a test company
   (sign up on the website with a second email) and use it for all development. The real company
   has more than 1,800 live pins.
3. **Keep the website working.** `app.html` / `docs/app.html` stay the source of truth for web
   users. Don't change them as part of this rewrite unless asked.
4. **Keep the old wrapper.** Leave `ios/` in place until the native app reaches feature parity.
   The new app goes in `ios-native/`.
5. **Build it yourself.** After every change, run the build and fix errors before reporting back:
   ```
   xcodebuild -project ios-native/KnoxCanvas.xcodeproj -scheme KnoxCanvas \
     -destination 'platform=iOS Simulator,name=iPhone 16' build
   ```
   Use whichever simulator `xcrun simctl list devices available` shows.
6. **Field-first UI.** One-handed, outdoors, big tap targets, dark theme matching the web app
   (`#0f1117` background, `#4f6ef7` accent, status colors below). No more than 2 taps to mark a door.

Status colors: none `#6b7280` · hanger `#f59e0b` · interest `#10b981` · no `#ef4444` · dnr `#7c3aed`.

## Stack

- SwiftUI, iOS 17+, Swift 5.9+. Project generated with **XcodeGen** (`project.yml`), so the
  project file is never hand-edited. Install it with `brew install xcodegen`.
- Swift Package Manager:
  - `firebase-ios-sdk`: FirebaseAuth and FirebaseFirestore. Turn on offline persistence (it's on by default).
  - `GoogleSignIn-iOS` for Google login. It replaces the hand-rolled `GoogleSignIn.swift`.
- `GoogleService-Info.plist` for project `knoxcanvas-a7bfe`. The iOS app is already registered;
  the client ID is in `ios/KnoxCanvas/KnoxCanvasApp.swift`. Download the plist from Firebase →
  Project settings → Your apps → iOS. The Firebase config is public by design.
- Map: **MapKit** through a `UIViewRepresentable` around `MKMapView`. SwiftUI's `Map` doesn't
  cluster, and there are thousands of pins. Use annotation clustering, standard/satellite-hybrid
  map types, and hide points of interest.
- Geocoding: the existing Cloudflare Worker `https://broken-tree-befb.connorbdowney48.workers.dev?lat=&lng=`
  (same as the web), with `CLGeocoder` as the fallback. Search: `MKLocalSearch`.
- Houses for the street sweep and routes: OSM Overpass with the same 4 fallback endpoints as `app.html`.

## Phases

### Phase 0: project skeleton
- `ios-native/project.yml`, app target `KnoxCanvas`, same bundle ID as the current wrapper (so it
  replaces it on the phone), with Firebase and GoogleSignIn packages.
- Info.plist: location usage strings, `UIBackgroundModes: location`, the Google URL scheme
  (reversed client ID), and the `PrivacyInfo.xcprivacy` privacy manifest.
- App icon from `knoxcanvas/public/icon-512.png`, launch color `#0f1117`.
- **Done when:** it builds and launches to a placeholder screen in the simulator.

### Phase 1: sign-in and company setup
- Email/password sign-in, sign-up, password reset. Google sign-in.
- After sign-in, read `users/{uid}`. With no `companyId`, show setup:
  - **Create company:** batch-write `companies/{new}` and `users/{uid}` with role `owner`.
  - **Join with invite code:** read `invites/{CODE}`, check `expiresAt`, write `users/{uid}`
    with role `employee`, delete the invite.
- Same friendly error messages as `app.html`'s `friendlyAuthError`.
- **Done when:** you can sign in to the test account and land on an empty map screen.

### Phase 2: map and pins (the core)
- Live listener on `companies/{cid}/pins`. Show clustered, colored annotations.
- Floating search bar, status filter chips with counts, locate-me button, bottom tab bar
  (Shift · Route · Zone · Layers · Account). Same layout as the redesigned web app.
- Tap the map to drop a `none` pin and reverse-geocode its address.
- Tap a pin to open a bottom sheet with:
  - address, a Zillow link, and the 5 status buttons
  - note and year built (debounced saves)
  - "apply year to pins within 400 m", "set as route start", delete
- Status writes set `status, ts, statusBy, statusAt` (plus `hangerBy, hangerAt` for hangers),
  and `updatedBy, updatedAt`. If `company.sheetsUrl` is set, POST the same JSON as `syncToSheets`.
- **Done when:** a pin added on the phone appears on the website within seconds, and the reverse works too.

### Phase 3: shifts
- Clock in/out, a live timer, and the hanger count for the current shift.
- **Fix the known bug:** store the active shift in Firestore (`users/{uid}.activeClockIn`) as
  well as locally, so it survives reinstall or sign-out. The web can adopt the same field later.
- On clock-out, write the `companies/{cid}/shifts` doc in the same format, sync it to Sheets,
  and show history with a CSV export through the share sheet.

### Phase 4: GPS street sweep
- Port the `// ── Street sweep` section of `app.html` faithfully: same `SWEEP` constants, the
  driving cutoff, the Overpass query that matches houses to walked streets, the Google fallback
  through the Worker, candidates with a banner and review list, a batch write with
  `source: 'gps-sweep'`, and the shift summary (`trail`, `trailMeters`, `gpsHangers`).
- Background location with `CLLocationManager` (`allowsBackgroundLocationUpdates`, the blue
  pill, `activityType .fitness`). Keep the walking-reminder notification.
- **Done when:** a simulated walk (an Xcode GPX file along a Knoxville street) produces candidates.

### Phase 5: owner tools
- Team list, removing members, generating invite codes (8 characters, 7-day expiry, share sheet).
- Company settings: name, roofing cutoff year, Sheets URL.
- Metrics: time ranges, per-employee breakdown, recent shifts. Same math as `renderMetrics`.

### Phase 6: map tools
- Route optimizer (Overpass houses inside a zone, nearest-neighbor, skip visited/do-not-return).
- Drawing neighborhood zones with a year built, plus roofing target mode.
- Zip boundary overlays (Census TIGERweb, then Overpass), satellite toggle, CSV export of pins.

### Phase 7: ship
- Test on a real iPhone, check performance with 2,000+ pins, try offline.
- App Store assets, privacy details (location used for app functionality, linked to user), TestFlight.
- Then retire `ios/`.

## Kickoff prompt for Claude Code

> Read CLAUDE.md and NATIVE_PLAN.md. We're building the native iOS app described in
> NATIVE_PLAN.md in `ios-native/`. Start with Phase 0 and Phase 1. Build with xcodebuild after
> every change and fix all errors yourself. When Phase 1 builds and runs in the simulator, stop
> and tell me what to test.
