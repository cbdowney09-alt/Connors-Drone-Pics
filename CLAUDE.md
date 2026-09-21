# KnoxCanvas

Door-to-door sales canvassing web app (Knoxville, TN): a Leaflet map of pins with visit statuses, zones, shifts, routes, metrics and CSV/Sheets export, backed by Firebase Auth + Firestore. The GitHub repo is named `Connors-Drone-Pics` and its README says "website for drone pics", but the code is KnoxCanvas.

## Layout

- `knoxcanvas/` — **the source** for the current app (React 18 + Vite 5, plain JS/JSX, no TypeScript, no tests, no linter).
  - `src/components/` UI (`panels/` holds Route, Export, Metrics, Shifts; several are lazy-loaded in `App.jsx`)
  - `src/context/AppContext.jsx` + `src/context/hooks/` all app state (auth, pins, shifts, map UI, toasts)
  - `src/utils/` geo, geocoding, csv, Google Sheets sync, legacy JSONBin migration
  - `src/constants.js` status colors/labels, map center, proxy and Sheets URLs
  - `src/firebase.js` Firebase init (offline persistence enabled)
  - `src/styles.css` all styling, one file
- `docs/` — **what Vercel serves** (`vercel.json` sets `outputDirectory: docs`; there is no build command on Vercel).
  - `docs/knoxcanvas/` is the **committed build output** of `knoxcanvas/`. Never hand-edit it.
  - `docs/index.html` landing page, `docs/app.html` and `docs/test_2.html` are older single-file versions of the app (inline JS/CSS, Firebase via CDN).
- Repo root `app.html`, `test_2.html` are byte-identical copies of the `docs/` versions. If you edit one, edit the other (or ask the user before deleting the duplicates).

## Commands (run from `knoxcanvas/`)

```bash
npm install        # first time only
npm run dev        # Vite dev server with hot reload (default http://localhost:5173)
npm run build      # writes to ../docs/knoxcanvas (emptyOutDir: true), which is what gets deployed
```

## Making and shipping a change

1. Edit files in `knoxcanvas/src/` (or the standalone `docs/*.html` if the change is to those pages).
2. Check it in the dev server / preview.
3. Run `npm run build` so `docs/knoxcanvas/` matches the source. Commit the source **and** the rebuilt `docs/knoxcanvas/` together, because deploys serve the committed files as-is.
4. Do not push or open a PR unless the user asks. Work on a branch, not `main`.

## Gotchas

- `docs/index.html` links to `app.html` (the legacy app) and `docs/test.html` (that file doesn't exist; the real file is `test_2.html`). The React app lives at `/knoxcanvas/`. Ask which version the user means when they say "the website".
- `knoxcanvas/.npmrc` sets `cache=D:/npm-cache`, a machine-specific path.
- `src/constants.js` contains a JSONBin access key and other hard-coded URLs. Firebase web config in `firebase.js` is public by design; do not treat it as a secret, but do not add new secrets to the repo.
- Data lives in the production Firestore project `knoxcanvas-a7bfe`; running the app locally talks to real data. Don't write test pins/zones/shifts while testing unless the user says so.
- The default branch is `main`.
