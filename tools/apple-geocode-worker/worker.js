// KnoxCanvas address lookup through Apple Maps (free with the Apple Developer Program).
// Cloudflare Worker: GET ?lat=..&lng=.. → Google-Geocoding-shaped JSON, so app.html reads it
// exactly like the Google Worker (which stays as the backup).
//
// Secrets (Cloudflare → Worker → Settings → Variables and Secrets, type "Secret"):
//   APPLE_TEAM_ID      10-character Team ID (developer.apple.com → Membership)
//   APPLE_KEY_ID       Key ID of a key with "MapKit JS" enabled (Certificates, IDs & Profiles → Keys)
//   APPLE_PRIVATE_KEY  the whole contents of that key's .p8 file
// Never put these in the repo; it's public.

const ALLOWED_ORIGINS = [
  'https://knoxcanvas.app', 'https://www.knoxcanvas.app',
  'https://connorsdronepics.com', 'https://www.connorsdronepics.com',
];

let cached = null; // { token, expires } Apple access token, reused until it's nearly expired

export default {
  async fetch(request, env) {
    const origin = request.headers.get('Origin') || '';
    const cors = {
      'Access-Control-Allow-Origin': ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0],
      'Vary': 'Origin',
      'Content-Type': 'application/json',
    };
    if (request.method === 'OPTIONS') return new Response(null, { headers: cors });
    // Browsers on other sites can't use our quota. (No Origin = a direct test, e.g. curl.)
    if (origin && !ALLOWED_ORIGINS.includes(origin)) return json({ status: 'REQUEST_DENIED', error_message: 'origin not allowed' }, cors, 403);

    const url = new URL(request.url);
    const lat = parseFloat(url.searchParams.get('lat')), lng = parseFloat(url.searchParams.get('lng'));
    if (!isFinite(lat) || !isFinite(lng)) return json({ status: 'INVALID_REQUEST', results: [] }, cors, 400);

    try {
      const token = await accessToken(env);
      const r = await fetch(`https://maps-api.apple.com/v1/reverseGeocode?loc=${lat},${lng}&lang=en-US`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (r.status === 401) cached = null; // token revoked or expired early; next call gets a new one
      if (!r.ok) return json({ status: r.status === 429 ? 'OVER_QUERY_LIMIT' : 'UNKNOWN_ERROR', results: [], error_message: `Apple ${r.status}` }, cors, 200);
      const d = await r.json();
      const results = (d.results || []).map(toGoogle).filter(Boolean);
      return json({ status: results.length ? 'OK' : 'ZERO_RESULTS', results }, cors, 200);
    } catch (e) {
      return json({ status: 'UNKNOWN_ERROR', results: [], error_message: String(e && e.message || e) }, cors, 200);
    }
  },
};

function json(body, headers, status = 200) {
  return new Response(JSON.stringify(body), { status, headers });
}

// Apple place → the parts of a Google result that app.html reads.
function toGoogle(p) {
  const a = p.structuredAddress || {};
  const num = a.subThoroughfare || '', road = a.thoroughfare || '';
  const city = a.locality || a.subLocality || '', state = a.administrativeAreaCode || a.administrativeArea || '', zip = a.postCode || '';
  const formatted = num && road
    ? [`${num} ${road}`, city, `${state} ${zip}`.trim()].filter(Boolean).join(', ')
    : (p.formattedAddressLines || []).join(', ');
  if (!formatted) return null;
  const comp = (v, type) => v ? [{ long_name: v, short_name: v, types: [type] }] : [];
  return {
    formatted_address: formatted,
    // A house number means Apple placed it on the house; otherwise it's only the street.
    geometry: {
      location: { lat: p.coordinate?.latitude, lng: p.coordinate?.longitude },
      location_type: num ? 'ROOFTOP' : 'APPROXIMATE',
    },
    types: num ? ['street_address'] : ['route'],
    address_components: [
      ...comp(num, 'street_number'), ...comp(road, 'route'), ...comp(city, 'locality'),
      ...comp(state, 'administrative_area_level_1'), ...comp(zip, 'postal_code'),
    ],
  };
}

// Apple Maps Server API: sign a short JWT with the .p8 key, trade it for a 30-minute access token.
async function accessToken(env) {
  const now = Date.now();
  if (cached && cached.expires - now > 60_000) return cached.token;
  const r = await fetch('https://maps-api.apple.com/v1/token', { headers: { Authorization: `Bearer ${await signedJwt(env)}` } });
  if (!r.ok) throw new Error(`Apple token ${r.status}`);
  const d = await r.json();
  cached = { token: d.accessToken, expires: now + (d.expiresInSeconds || 1800) * 1000 };
  return cached.token;
}

async function signedJwt(env) {
  const iat = Math.floor(Date.now() / 1000);
  const enc = o => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const data = `${enc({ alg: 'ES256', kid: env.APPLE_KEY_ID, typ: 'JWT' })}.${enc({ iss: env.APPLE_TEAM_ID, iat, exp: iat + 1800 })}`;
  const der = Uint8Array.from(atob(env.APPLE_PRIVATE_KEY.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '')), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  // WebCrypto returns the raw r||s signature, which is what ES256 JWTs use.
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(data));
  return `${data}.${b64url(new Uint8Array(sig))}`;
}

function b64url(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
