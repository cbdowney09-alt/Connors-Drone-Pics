import { GEO_PROXY } from '../constants';
import { pointInPolygon } from './geo';

export async function reverseGeocode(lat, lng) {
  let addr = '';
  try {
    const r = await fetch(`${GEO_PROXY}?lat=${lat}&lng=${lng}`);
    const d = await r.json();
    if (d.status === 'OK' && d.results && d.results.length > 0) {
      const best = d.results.find((r) => r.geometry.location_type === 'ROOFTOP' || r.geometry.location_type === 'RANGE_INTERPOLATED') || d.results[0];
      addr = best.formatted_address || '';
    }
  } catch (e) {}
  if (!addr) {
    try {
      const r = await fetch(`https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lng}&format=json&addressdetails=1&zoom=18`);
      const d = await r.json();
      if (d.address) {
        const a = d.address; const num = a.house_number || '', road = a.road || '';
        const city = a.city || a.town || a.village || 'Knoxville'; const state = a.state_code || 'TN', zip = a.postcode || '';
        if (num && road) addr = `${num} ${road}, ${city}, ${state} ${zip}`.trim();
      }
    } catch (e) {}
  }
  if (!addr) addr = `${lat.toFixed(4)}, ${lng.toFixed(4)}`;
  return addr;
}

export async function searchAddress(q) {
  const r = await fetch(`https://nominatim.openstreetmap.org/search?q=${encodeURIComponent(q + ' Knoxville Tennessee')}&format=json&limit=5`);
  return r.json();
}

export async function fetchHousesFromOSM(lat, lng, polygon) {
  const bbox = polygon && polygon.length >= 3
    ? (() => { const lats = polygon.map((p) => p[0]), lngs = polygon.map((p) => p[1]); return `(${Math.min(...lats)},${Math.min(...lngs)},${Math.max(...lats)},${Math.max(...lngs)})`; })()
    : `(around:800,${lat},${lng})`;
  const query = `[out:json][timeout:25];(node["addr:housenumber"]${bbox};way["addr:housenumber"]${bbox};);out center;`;
  const endpoints = ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter', 'https://maps.mail.ru/osm/tools/overpass/api/interpreter', 'https://overpass.openstreetmap.ru/api/interpreter'];
  for (const ep of endpoints) {
    for (const method of ['GET', 'POST']) {
      try {
        const controller = new AbortController(); const timer = setTimeout(() => controller.abort(), 25000);
        const url = method === 'GET' ? `${ep}?data=${encodeURIComponent(query)}` : ep;
        const opts = method === 'GET' ? { signal: controller.signal } : { method: 'POST', body: 'data=' + encodeURIComponent(query), signal: controller.signal };
        const r = await fetch(url, opts); clearTimeout(timer);
        if (!r.ok) continue; const d = await r.json(); if (!d.elements) continue;
        return d.elements.map((el) => {
          const elLat = el.lat || el.center?.lat, elLng = el.lon || el.center?.lon;
          if (!elLat || !elLng) return null;
          if (polygon && polygon.length >= 3 && !pointInPolygon(elLat, elLng, polygon)) return null;
          const num = el.tags?.['addr:housenumber'] || '', street = el.tags?.['addr:street'] || '';
          return { lat: elLat, lng: elLng, addr: num && street ? `${num} ${street}` : `${elLat.toFixed(4)},${elLng.toFixed(4)}` };
        }).filter(Boolean);
      } catch (e) { continue; }
    }
  }
  throw new Error('All Overpass endpoints failed');
}

function geojsonToLatLng(geometry) {
  if (geometry.type === 'Polygon') {
    return geometry.coordinates[0].map((c) => [c[1], c[0]]);
  }
  if (geometry.type === 'MultiPolygon') {
    const rings = geometry.coordinates.map((poly) => poly[0].map((c) => [c[1], c[0]]));
    return rings.reduce((a, b) => (a.length > b.length ? a : b), []);
  }
  return null;
}

async function fetchZipViaOverpass(zip) {
  const query = `[out:json][timeout:20];relation["postal_code"="${zip}"]["boundary"="postal_code"];out geom;`;
  const endpoints = ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter'];
  for (const ep of endpoints) {
    try {
      const r = await fetch(`${ep}?data=${encodeURIComponent(query)}`);
      if (!r.ok) continue;
      const d = await r.json();
      if (!d.elements || !d.elements.length) continue;
      const el = d.elements[0];
      if (el.members) {
        const coords = [];
        el.members.filter((m) => m.type === 'way' && m.geometry).forEach((m) => {
          m.geometry.forEach((pt) => coords.push([pt.lat, pt.lon]));
        });
        if (coords.length) return coords;
      }
    } catch (e) { continue; }
  }
  return null;
}

export async function fetchZipBoundary(zip) {
  const searchUrl = `https://nominatim.openstreetmap.org/search?q=${zip}&format=json&limit=1&addressdetails=1&countrycodes=us`;
  const searchRes = await fetch(searchUrl);
  const searchData = await searchRes.json();
  if (!searchData.length) return null;

  const osmId = searchData[0].osm_id;
  const osmType = searchData[0].osm_type;

  const detailUrl = `https://nominatim.openstreetmap.org/details?osmtype=${osmType === 'relation' ? 'R' : osmType === 'way' ? 'W' : 'N'}&osmid=${osmId}&format=json&polygon_geojson=1`;
  const detailRes = await fetch(detailUrl);
  const detail = await detailRes.json();

  if (detail.geometry && detail.geometry.coordinates) {
    return geojsonToLatLng(detail.geometry);
  }

  return await fetchZipViaOverpass(zip);
}
