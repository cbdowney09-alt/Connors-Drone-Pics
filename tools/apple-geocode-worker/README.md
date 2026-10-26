# Apple address lookup Worker

`worker.js` turns GPS coordinates into a street address using Apple Maps (free with the Apple
Developer Program, about 25,000 lookups a day). `app.html` tries it first for pin addresses
(`APPLE_GEO_PROXY`), then the Google Worker (`GEO_PROXY`, billed), then OpenStreetMap. It answers in
Google's JSON shape, so the page reads both the same way. Only knoxcanvas.app and connorsdronepics.com
may call it from a browser.

## Set up

1. **Apple key** (developer.apple.com → Certificates, Identifiers & Profiles):
   - **Identifiers → +** → **Maps IDs** → description "KnoxCanvas", identifier `maps.app.knoxcanvas` → Register.
   - **Keys → +** → name "KnoxCanvas Maps", tick **MapKit JS** → Configure → pick the Maps ID → Save → Continue → Register.
   - **Download** the `.p8` file (only possible once) and note the **Key ID**. Your **Team ID** is under Membership.
2. **Cloudflare** (dash.cloudflare.com → Workers & Pages → Create → Worker): name it `knox-apple-geocode`,
   Deploy, then **Edit code**, paste `worker.js`, Deploy.
3. **Settings → Variables and Secrets → Add**, type **Secret**, three times:
   `APPLE_TEAM_ID`, `APPLE_KEY_ID`, and `APPLE_PRIVATE_KEY` (paste the whole `.p8` file, including the BEGIN/END lines).
4. Test: open `https://knox-apple-geocode.<you>.workers.dev/?lat=35.9606&lng=-83.9207`. It should say `"status":"OK"`.
5. Put that URL in `APPLE_GEO_PROXY` in `app.html`, copy to `docs/app.html`, deploy.

Never commit the `.p8` file or the IDs' secrets; the repo is public.
