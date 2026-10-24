# KnoxCanvas — notes for Claude Code

KnoxCanvas is a door-to-door canvassing tracker for Jeff Woods Construction & Roofing
(Tennessee). Canvassers drop color-coded pins on houses, clock in and out of shifts, and owners
see team metrics. It is also being pitched to other door-to-door companies, so anyone can sign
up, create a company and invite their team.

## Repo layout

| Path | What it is |
|---|---|
| `app.html` | **Current app.** One self-contained HTML file (Leaflet + Firebase v10 from CDN). Newest work happens here. |
| `docs/` | **What Vercel actually serves** (`vercel.json` → `outputDirectory: docs`). `docs/app.html` is a copy of `app.html` (synced Oct 2026). `docs/index.html` is the landing page. |
| `ios/` | Native iPhone app: SwiftUI + WKWebView wrapper that loads `https://connorsdronepics.com/app.html`, plus native GPS. |
| `knoxcanvas/` | Abandoned-for-now React/Vite migration (built output in `docs/knoxcanvas/`). Don't touch unless asked. |
| `test_2.html` | Scratch file. |

**Deploying:** the live site is `knoxcanvas.app` on Vercel (Oct 2026; DNS at GoDaddy → Vercel), served from `docs/`. `connorsdronepics.com`
serves the same files and must keep working: older iPhone builds load its `app.html` and `/addr/v1/` tiles, and the old `ios/`
wrapper opens any other domain in Safari, so never redirect it. Browser storage (login, clock-in) is per domain. `docs/index.html` is the landing page. Editing
root `app.html` does NOT change the live site. To ship, copy `app.html` → `docs/app.html`.
Keep the two identical. They were synced in Oct 2026, after confirming both use the same Firestore
paths and fields. The old one-time JSONBin migration for the original owner account was dropped;
it had already run. The iOS app loads the live URL, so it only picks up changes once they're deployed.

## Stack

- Map: Leaflet 1.9.4 with Google tiles.
- Data: Firebase project `knoxcanvas-a7bfe`. Firestore uses an offline persistent cache; auth is
  email/password plus Google (in the iOS app, Google sign-in runs natively; see GoogleSignIn.swift).
  - `users/{uid}` → `{ name, email, role: owner|employee, companyId, companyName }`
  - `companies/{id}` → `{ name, ownerId, roofCutoff, sheetsUrl, status?, ownerName?, ownerEmail?, phone?, requestedAt?, statusAt?, statusBy? }`
    - `status`: `pending` (new request) · `active` · `paused` · `declined`. **Missing means active**
      (companies made before approvals). Only an admin can change it.
  - `admins/{uid}` → exists = KnoxCanvas admin (approves, pauses, resumes companies). Added by hand in the console.
  - `companies/{id}/pins/{lat6,lng6}` → `{ lat, lng, addr, status, note, yearBuilt, ts, createdBy, statusBy, statusAt, hangerBy, hangerAt, source? }`
  - `companies/{id}/shifts/{auto}` → `{ clockIn, clockOut, durationMs, hangers, hangersPerHour, userId, userName, trail?, trailMeters?, gpsHangers? }`
  - `companies/{id}/settings/neighborhoodYears` → `{ zones: [...] }`
  - `invites/{code}` → one-time join codes, expire in 7 days
- Geocoding: Google Geocoding API behind the Cloudflare Worker
  `https://broken-tree-befb.connorbdowney48.workers.dev` (`?lat=&lng=`). Nominatim is the fallback.
- Houses / route optimizer: OSM Overpass, with 4 fallback endpoints (`OVERPASS` constant). The
  public servers are often down or "at capacity", so the **iPhone app** reads our own address tiles first.
  Tennessee and North Carolina ship **inside the app** (`ios-native/KnoxCanvas/Resources/addresses.knxa`, 73 MB,
  made by `tools/address-tiles/pack.py --states TN,NC`) and work with no signal. Tiles on a state line hold both
  states (`cs` = state per city). Other states can be served as tiles from the website:
  `docs/addr/v1/` (served at `/addr/v1/`). They hold 3.35M Tennessee + 5.23M North Carolina houses from Overture Maps / the National
  Address Database, built by `tools/address-tiles/build.py`; run it again to refresh or add a state. The sweep
  matches tile houses to the walked street names that Apple's reverse geocoder gives for trail points.
- Zip overlays: Census TIGERweb, with Overpass as the fallback.
- Google Sheets: an Apps Script webhook (company setting `sheetsUrl`) receives hanger pins and shifts.

Pin statuses (keep these five; exports and Sheets depend on them):
`none` Not visited · `hanger` Door hanger · `interest` Interested · `no` Not interested · `dnr` Do not return.

## Rules for every change

1. **Single file.** All HTML/CSS/JS stays inline in `app.html`. Libraries come only from a CDN. No build step.
2. **No secrets in the repo** (it's public). The Firebase web config is public by design. Any
   other API key goes behind the Cloudflare Worker. If a change needs one, say what Worker route to add.
3. **Don't break saved data.** Add fields with defaults; never rename or remove them. Upgrade old
   records in `normalizePin`. Keep the CSV column order
   (`Address,Status,Date Added,Note,Year Built,Latitude,Longitude`).
4. **Plan for bad signal.** Firestore's offline cache queues writes. Show sync state in `#sync-pill`.
   Never silently drop a canvasser's work.
5. **Built for the field.** One-handed on a phone, outdoors: big tap targets, high contrast, few taps per door.
6. **The route optimizer must degrade:** Overpass fallbacks plus a timeout, then saved pins, then straight-line nearest neighbor.
7. After editing, run `node --check` on the extracted `<script type="module">`, confirm that old
   records without the new fields still load, and check the layout at phone width.

## Map screen layout (redesigned Oct 2026)

- **Top:** a floating search card with a locate button. Below it, horizontally scrolling status
  filter chips (`#legend .legend-row`, which also show counts), then a status row (sync problems,
  GPS off, and the "On shift" chip).
- **Bottom tab bar (`#tabbar`):** Shift (shows the live timer), Route, Zone, Layers, Account. Floating
  banners sit above it using `--tabbar-h` + `--safe-b`.
- **Layers panel:** street/satellite basemap (saved in localStorage as `knoxBasemap`), the roofing
  target mode switch, and zip boundaries.
- **Pins:** `L.circleMarker` dots on a shared canvas renderer (`pinRenderer`), sized by zoom.
  Use `setStyle`, not `setIcon`.
- **Preview harness:** render with Playwright using stubbed Firebase modules. Check at 390×844
  before shipping UI changes.

## Street sweep (GPS auto-pinning) — added Oct 2026

While a canvasser is **clocked in**, GPS builds a walking trail. Code is in the
`// ── Street sweep` section of `app.html`.

- Points with accuracy >35 m or movement <6 m are dropped. Movement faster than 3.5 m/s counts as driving and splits the trail.
- About every 120 m walked (or 90 s with ≥40 m walked), that stretch goes to Overpass in one query:
  named `highway` ways within 25 m (the streets actually walked) plus `addr:housenumber` nodes
  and ways within 45 m. Houses are kept only if their `addr:street` matches a walked street,
  which filters out houses that back onto the street. Houses with no street tag must be within 32 m.
- If OSM returns no addresses along a named street, the fallback is Google reverse geocoding
  through the Worker (5 samples at 40 m apart, ROOFTOP street addresses only).
- Results become **candidates**: dashed orange rings on the map and a bottom banner,
  "🏠 N houses passed · Street" → **Mark N as hangers** / **Review** / ✕. Tapping a ring
  toggles that house. Accepted houses become `hanger` pins with `source: 'gps-sweep'` (one
  `writeBatch`) and are synced to Sheets. Anything shown and then skipped goes into `sweepSeen`
  and isn't offered again during that shift.
- The trail, seen keys and open candidates are saved to `localStorage` under `knoxTrail_<uid>`
  so a reload mid-shift picks back up. On clock-out, the shift gets `trail`
  (`"lat,lng,secondsSinceClockIn;..."` string, because Firestore can't store nested arrays),
  `trailMeters` and `gpsHangers`.
- Tuning knobs are in the `SWEEP` constant.
- **iPhone app, with address tiles (Tennessee):** detection is by distance instead. On every GPS step, any tile house
  within `SWEEP.doorRadius` (default 20 m, set in the Shift screen: 15/20/30/45 m) becomes a candidate right away.
  The 120 m stretch lookups still run and catch anything missed offline. The first field test (Oct 2026) found
  nothing with the old method, because Overpass was down and the tiles weren't deployed yet.
- **Website, same as the iPhone (Oct 2026):** `app.html` reads the same `/addr/v1/` tiles (TN + NC) and lights up
  houses within `SWEEP.doorRadius` on every walking step (`sweepCheckNear`, `tileHousesNear`). It saves the tiles in Cache Storage
  (`knox-addr-v1`) for offline use, and has the Shift-panel radius picker (`knoxDoorRadius` in localStorage) and the iPhone 2.0.1 driving
  checks (`sweepIsDriving`). Outside tile areas it falls back to Overpass/Google as before. In a browser, a Wake Lock keeps the screen on
  while clocked in (browsers stop GPS when the screen sleeps). `docs/manifest.webmanifest` lets Android Chrome install it (Account → Install).
- **Not yet field-tested against real OSM data.** It was tested only with simulated data. First real
  walks should check how many houses get found in Knoxville and Tennessee Ridge, and whether the
  Google fallback fills the gaps.

## iOS app (`ios/`)

Open `ios/KnoxCanvas.xcodeproj` in Xcode 15+. Set the Team and change the bundle ID from the
placeholder `com.knoxcanvas.app`. iOS 16+, iPhone only, portrait. Built but **never compiled
yet**. Expect to fix small Swift errors on the first build.

- `KnoxCanvasApp.swift`: entry point; `AppConfig.appURL` is the page it loads.
- `WebView.swift`: WKWebView setup. Handles `alert`/`confirm`/`prompt` (WKWebView ignores them
  otherwise), sends external links (Zillow) to Safari, shares CSV exports through the iOS share
  sheet, falls back to the cached page when offline, and reloads if the page process gets killed.
- `LocationBridge.swift`: the single CLLocationManager. Background location (`UIBackgroundModes: location`,
  When-In-Use plus the blue pill) keeps recording with the screen locked. Points are buffered in
  UserDefaults and flushed to the page when it's visible. While the app is in the background, it
  sends a silent notification about every 250 m walked, reminding the canvasser to open the app and mark houses.
- `GoogleSignIn.swift`: Google blocks its login page inside WKWebView (`disallowed_useragent`),
  so the page's popup/redirect flow can't work in the app. In the app, the Google button sends
  `googleSignIn` to native code. Native runs Google OAuth (PKCE) in `ASWebAuthenticationSession`,
  exchanges the code for an ID token and calls `KnoxNative.onGoogleCredential(idToken, accessToken)`.
  The native code also catches the page's own Google popup or redirect (Firebase's `/__/auth/` handler or
  `accounts.google.com`) and runs the native flow instead. Before this, older page versions sent
  users to Safari. The tokens go to `window.__knoxGoogleCredential` (defined in `BridgeScript`).
  That function dynamic-imports the same Firebase 10.12.0 URLs the page uses, so it signs in the
  page's own Firebase instance and works with any page version. Keep that version in sync with `app.html`. **Setup:** Firebase console → Project settings →
  Add app → iOS, using the same bundle ID as the Xcode target. Download `GoogleService-Info.plist`
  and paste its `CLIENT_ID` into `AppConfig.googleIOSClientID`. Until that's done, the button
  shows "isn't set up yet". Both `app.html` and `docs/app.html` have this hook.
- `BridgeScript.swift`: injected at document start. It replaces `navigator.geolocation` with
  the native one, so there's only one permission prompt and the locate button uses native GPS.

**Bridge contract** (page ↔ native):

- Page → native: `window.webkit.messageHandlers.knox.postMessage({cmd})`, where `cmd` is one of
  `startTracking`, `stopTracking`, `geoStart`, `geoStop`, `googleSignIn`, `haptic`, or `share` (sent as `{filename, text}`).
- Native → page:
  - `window.KnoxNative.onLocations([{lat,lng,acc,spd,t}])`
  - `KnoxNative.onTrackingError(msg)`
  - `KnoxNative.onTrackingOk()`
  - `KnoxNative.onGoogleCredential(idToken, accessToken)` / `KnoxNative.onGoogleError(msg)`
  - `window.__knoxGeoDeliver(coords)` / `__knoxGeoError(code,msg)`
- `IS_NATIVE` in `app.html` is true when the `knox` handler exists.

## Company approval (added Oct 2026)

Anyone can download the app and make a login, but **new companies are requests**:
- Setup's owner path saves the company with `status: 'pending'` and the owner's name, email and phone, then
  shows a "Request sent" screen. `REQUEST_WEBHOOK` (`admin/request-email.gs`, a Google Apps Script) emails the admin.
- The admin approves, declines, pauses or resumes companies in the iPhone app (Account → Admin: companies).
  Payment happens outside the app: no prices or payment links in the app (App Store guideline 3.1.3(c)).
- Both apps watch the company doc. Approval opens the map right away, and a pause drops the team to the locked screen.
  Paused data stays. The rules block pins, shifts and settings unless the company is active.

## Known open issues

- Google login on the web (popup vs. redirect). The iOS app uses the native flow in `GoogleSignIn.swift` instead.
- Zip boundary overlays sometimes don't load.
- The clock-in state lives in `localStorage` only, so it's lost if the device storage is cleared. It should move to Firestore.
- Firestore rules live in `firestore.rules` (publish them in the Firebase console). After editing,
  run the emulator tests: `cd rules-test && npm install && npm test` (needs Java 11+). Never use a bare
  `{sub=**}` under `companies/{cid}`: it also matches the company doc and lets members edit `status`.

## Native rewrite

A full SwiftUI rewrite following `NATIVE_PLAN.md` lives in `ios-native/`. Phases 0–6 are done
(feature parity with `app.html`). Phase 7 (real-iPhone testing, App Store, TestFlight) is
described in `ios-native/APP_STORE.md` and needs the owner's device and Apple account. `ios/` stays
as the fallback until that passes.

- Project file is generated: edit `ios-native/project.yml`, then run `xcodegen generate`. Never hand-edit the pbxproj.
- Build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project ios-native/KnoxCanvas.xcodeproj -scheme KnoxCanvas -destination 'platform=iOS Simulator,name=<sim>' build`
- Code by area: `Session/` (auth, setup), `Pins/` (store, map, sheet), `Shifts/`, `Sweep/` (GPS street
  sweep, Overpass), `Owner/` (team, invites, settings, metrics), `MapTools/` (route, zones, roofing, zips, pin CSV).
- Differences from the web:
  - The active shift is also stored in `users/{uid}.activeClockIn`.
  - Drawn zone polygons are saved as `[{lat,lng}]`. The web's `[[lat,lng]]` form is rejected by Firestore, and the web's `pointInPolygon` doesn't read the object form yet.
  - A Google geocode refusal is treated as a failure, not "no houses".
- Privacy policy for the App Store: `docs/privacy.html`.

## Next steps

1. Build the iOS app on a real iPhone and fix any compile errors.
2. Push `docs/app.html` live, then do a test walk while clocked in.
3. Tune `SWEEP` radii from real walks. Then consider a shift-review map for owners that shows `trail` (the planned hanger-verification feature).
