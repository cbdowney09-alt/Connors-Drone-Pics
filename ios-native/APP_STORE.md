# Shipping the native app

Everything Phase 7 needs that only you can do: your iPhone, your Apple account and App Store Connect.

## 1. Before the first device build

1. **Apple team:** in `project.yml`, set `DEVELOPMENT_TEAM` to your 10-character Team ID
   (developer.apple.com → Membership). Then run `xcodegen generate`.
2. **Bundle ID:** `com.knoxcanvas.app`, the same as the `ios/` wrapper, so the native app replaces
   it on the phone. If Apple says the ID is taken, choose your own (for example `com.jeffwoods.knoxcanvas`). Change it in
   `project.yml`, and register a new iOS app with that ID in Firebase (Project settings → Add app → iOS).
   Then replace `Resources/GoogleService-Info.plist` and update `AppConfig.googleIOSClientID` and the
   reversed client ID URL scheme in `Info.plist`.
3. **Firestore rules:** publish `firestore.rules` from this repo (Firebase console → Firestore Database
   → Rules → paste → Publish). They cover everything both apps do, including company approval.
   54 emulator tests in `rules-test/` check them.
4. **Make yourself admin:** in the Firebase console, go to Authentication and copy your account's User UID. Then go to
   Firestore → Start collection `admins` → Document ID = that UID → add any field (for example `name: Connor`).
   Reopen the app, and Account shows **Admin: companies**.

## 2. Real-iPhone test pass

Use a **test company**, not the real one. Plug the phone in, pick it in Xcode, then Run.

- [ ] Sign in with email, then with Google. Sign out and back in.
- [ ] Drop pins and change statuses. Check that they appear on the website within seconds, and the reverse.
- [ ] Airplane mode: drop 5 pins and change statuses. The pill should say "Offline · saved on device". Turn airplane mode off and check they sync.
- [ ] Clock in, lock the phone and walk 2–3 blocks. The blue location pill should show, and a reminder notification should arrive about every 250 m.
- [ ] Unlock the phone and check the trail, orange rings and the "🏠 N houses passed" banner. Mark the houses, then clock out. The shift should have `trail`, `trailMeters` and `gpsHangers`.
- [ ] Force-quit mid-shift and reopen. The timer and trail should pick back up.
- [ ] Owner tools: generate an invite and join from a second account. Check metrics against the website.
- [ ] Route: draw a zone and generate a route. Zone: draw a neighborhood with a year, then turn on roofing mode.
- [ ] Zip code overlay, CSV export (shifts and pins), delete a throwaway account.
- [ ] **Performance:** sign in to the real company (look only, don't change anything). Pan and zoom around all 1,800+ pins and watch for stutter.

## 3. App Store Connect

**App information**
- Name: `KnoxCanvas`. Subtitle: `Door-to-door canvassing tracker`.
- Category: Business (secondary: Productivity). Age rating: 4+ (answer "None" to everything).
- Privacy Policy URL: `https://connorsdronepics.com/privacy.html`
  (`docs/privacy.html` in this repo). **Deploy it before submitting.**
- Support URL: `https://connorsdronepics.com`

**Description**

> KnoxCanvas is built for door-to-door teams. Drop a pin on every house you knock, mark it in one
> tap (door hanger, interested, not interested, do not return), and your whole team sees it live on
> the same map, even with bad signal.
>
> • Clock in and out of shifts with hangers-per-hour tracking
> • Street sweep: while you're on shift, KnoxCanvas follows your walk and lists the houses you passed,
>   so marking a whole street takes one tap
> • Route optimizer for a neighborhood you outline
> • Neighborhood year-built zones and roofing target mode
> • Team invites, team metrics and CSV export for owners
> • Optional Google Sheets sync

Keywords: `canvassing,door to door,sales,roofing,door hanger,field sales,territory,route,leads,knock`

**App Privacy** (answers for the questionnaire; they match `PrivacyInfo.xcprivacy`):

| Data type | Collected | Linked to user | Tracking | Purpose |
|---|---|---|---|---|
| Name | Yes | Yes | No | App functionality |
| Email address | Yes | Yes | No | App functionality |
| Precise location | Yes | Yes | No | App functionality |
| User ID | Yes | Yes | No | App functionality |
| Other user content (pins, notes) | Yes | Yes | No | App functionality |

Everything else: not collected. There's no analytics, no ads and no tracking.

**Export compliance:** `ITSAppUsesNonExemptEncryption` is already `NO` in Info.plist (only standard HTTPS).

**App Review notes** (they need a working login):

> KnoxCanvas is a work tool for door-to-door sales teams. Companies sign a service agreement with
> us directly and are billed outside the app (enterprise service, guideline 3.1.3(c)); new companies
> are approved by us before their team can use the map. Demo account: <email> / <password>,
> owner of an approved demo company with sample pins. Background location is used only while the user is
> clocked in for a shift (Shift tab → Clock in). It records the walking route, so the app can list
> the houses the canvasser walked past, and attaches the route to the shift record. It stops at clock-out.
> Account deletion: Account tab → Delete account.

Create that demo account and company on the website, approve it in your Admin screen, and add a few dozen
pins before submitting.

**Screenshots:** you need 6.9" iPhone screenshots (1320 × 2868). Take them in the iPhone 17 Pro Max / 18 Pro
Max simulator while signed in to the demo company, so no real customer addresses appear. Good shots: map with pins, the pin
sheet, the clock card, the street sweep banner, team metrics.

## 4. TestFlight

1. Xcode → Product → Archive (pick "Any iOS Device").
2. Organizer → Distribute App → App Store Connect → Upload.
3. In App Store Connect, under TestFlight, add yourself and your canvassers as testers. Internal testers
   can install about 15 minutes after processing.
4. Each new upload needs a higher build number (`CURRENT_PROJECT_VERSION` in `project.yml`).

## 5. Known App Review risk: Sign in with Apple

Guideline 4.8 says an app that offers a third-party login (Google) must also offer a login that keeps
the user's email private. Sign in with Apple is the usual answer. KnoxCanvas's own email/password
login may be accepted instead, but reviewers sometimes reject it. If that happens, add Sign in with Apple.
That means enabling the Apple provider in Firebase, adding the capability, and adding a button on the sign-in
screen. Accounts made that way can't sign in on the website until the website adds Apple sign-in too.

## 6. After launch

Once canvassers are on the native app and the checks above pass, delete `ios/` (NATIVE_PLAN rule 4)
and update CLAUDE.md.
