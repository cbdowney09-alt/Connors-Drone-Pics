import { useEffect, useRef } from 'react';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { useApp } from '../context/AppContext';
import { COLORS, ROOF_CUTOFF, KNOXVILLE_CENTER } from '../constants';

function makeIcon(status) {
  const c = COLORS[status] || COLORS.none;
  return L.divIcon({
    html: `<svg xmlns="http://www.w3.org/2000/svg" width="28" height="36" viewBox="0 0 28 36"><path d="M14 2C8.48 2 4 6.48 4 12c0 7 10 22 10 22S24 19 24 12c0-5.52-4.48-10-10-10z" fill="${c}"/><circle cx="14" cy="12" r="5" fill="rgba(255,255,255,0.35)"/></svg>`,
    iconSize: [28, 36], iconAnchor: [14, 36], className: '',
  });
}

export default function MapView() {
  const { pins, mapUi, ensurePinAt, mapRef, companyId, neighborhoodYears } = useApp();
  const {
    hiddenStatuses, openSheet,
    roofingMode,
    drawingMode, drawnPoints, addDrawPoint,
    routeStart, routeStops, routeZonePolygon,
    zipLayers,
  } = mapUi;

  const containerRef = useRef(null);
  const markersRef = useRef({});
  const zoneLayersRef = useRef([]);
  const drawLayersRef = useRef({ dots: [], polyline: null, polygon: null });
  const routeLayersRef = useRef({ markers: [], polylines: [] });
  const routeZoneLayerRef = useRef(null);
  const zipLayerObjsRef = useRef({});

  // ── Init map (once) ──────────────────────────────────────
  useEffect(() => {
    const map = L.map(containerRef.current, { center: KNOXVILLE_CENTER, zoom: 17, zoomControl: false, attributionControl: false });
    L.tileLayer('https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}', { maxZoom: 22, subdomains: '0123', attribution: '© Google Maps' }).addTo(map);
    L.control.attribution({ position: 'bottomleft', prefix: false }).addTo(map);
    mapRef.current = map;
    requestAnimationFrame(() => map.invalidateSize());
    return () => { map.remove(); mapRef.current = null; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ── Markers ───────────────────────────────────────────────
  useEffect(() => {
    const map = mapRef.current; if (!map) return;
    Object.values(markersRef.current).forEach((m) => map.removeLayer(m));
    markersRef.current = {};
    Object.keys(pins).forEach((id) => {
      const p = pins[id];
      if (hiddenStatuses.has(p.status)) return;
      const m = L.marker([p.lat, p.lng], { icon: makeIcon(p.status) });
      m.on('click', () => openSheet(id));
      m.addTo(map);
      markersRef.current[id] = m;
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pins, hiddenStatuses]);

  // ── Zone polygons (roofing mode) ─────────────────────────
  useEffect(() => {
    const map = mapRef.current; if (!map) return;
    zoneLayersRef.current.forEach((l) => map.removeLayer(l));
    zoneLayersRef.current = [];
    if (!roofingMode) return;
    neighborhoodYears.forEach((zone) => {
      if (!zone.polygon || zone.polygon.length < 3) return;
      const isTarget = parseInt(zone.year) <= ROOF_CUTOFF;
      const color = isTarget ? '#10b981' : '#6b7280';
      const layer = L.polygon(zone.polygon, { color, weight: 2.5, fillColor: color, fillOpacity: isTarget ? 0.18 : 0.06, dashArray: isTarget ? null : '6,4' }).addTo(map);
      const label = L.divIcon({ html: `<div style="background:${color};color:#fff;padding:3px 8px;border-radius:10px;font-size:11px;font-weight:700;white-space:nowrap;box-shadow:0 2px 8px rgba(0,0,0,0.3)">${zone.name || 'Zone'} · ${zone.year}</div>`, className: '', iconAnchor: [0, 0] });
      zoneLayersRef.current.push(layer);
      zoneLayersRef.current.push(L.marker(layer.getBounds().getCenter(), { icon: label, interactive: false }).addTo(map));
    });
  }, [roofingMode, neighborhoodYears]);

  // ── Drawing preview (points + polyline/polygon) ──────────
  useEffect(() => {
    const map = mapRef.current; if (!map) return;
    const cur = drawLayersRef.current;
    cur.dots.forEach((d) => map.removeLayer(d));
    cur.dots = [];
    if (cur.polyline) { map.removeLayer(cur.polyline); cur.polyline = null; }
    if (cur.polygon) { map.removeLayer(cur.polygon); cur.polygon = null; }
    if (!drawingMode) return;
    drawnPoints.forEach(([lat, lng]) => {
      const dot = L.circleMarker([lat, lng], { radius: 5, color: '#4f6ef7', fillColor: '#4f6ef7', fillOpacity: 1, weight: 2 }).addTo(map);
      cur.dots.push(dot);
    });
    if (drawnPoints.length >= 2) cur.polyline = L.polyline(drawnPoints, { color: '#4f6ef7', weight: 2, dashArray: '6,4' }).addTo(map);
    if (drawnPoints.length >= 3) cur.polygon = L.polygon(drawnPoints, { color: '#4f6ef7', weight: 2, fillColor: '#4f6ef7', fillOpacity: 0.1 }).addTo(map);
    map.getContainer().style.cursor = 'crosshair';
    return () => { map.getContainer().style.cursor = ''; };
  }, [drawingMode, drawnPoints]);

  // ── Route zone polygon (amber preview while configuring route) ──
  useEffect(() => {
    const map = mapRef.current; if (!map) return;
    if (routeZoneLayerRef.current) { map.removeLayer(routeZoneLayerRef.current); routeZoneLayerRef.current = null; }
    if (routeZonePolygon && routeZonePolygon.length >= 3) {
      routeZoneLayerRef.current = L.polygon(routeZonePolygon, { color: '#f59e0b', weight: 2, fillColor: '#f59e0b', fillOpacity: 0.1, dashArray: '6,4' }).addTo(map);
    }
  }, [routeZonePolygon]);

  // ── Route markers/lines ───────────────────────────────────
  useEffect(() => {
    const map = mapRef.current; if (!map) return;
    const cur = routeLayersRef.current;
    cur.markers.forEach((m) => map.removeLayer(m));
    cur.polylines.forEach((l) => map.removeLayer(l));
    cur.markers = []; cur.polylines = [];
    if (!routeStart || !routeStops || !routeStops.length) return;
    cur.markers.push(L.marker([routeStart.lat, routeStart.lng], { icon: L.divIcon({ html: `<div style="background:#fff;border:3px solid #4f6ef7;border-radius:50%;width:24px;height:24px;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:800;color:#4f6ef7;box-shadow:0 2px 8px rgba(0,0,0,0.3)">S</div>`, iconSize: [24, 24], iconAnchor: [12, 12], className: '' }) }).addTo(map));
    let prev = routeStart;
    routeStops.forEach((stop, i) => {
      cur.markers.push(L.marker([stop.lat, stop.lng], { icon: L.divIcon({ html: `<div style="background:#f59e0b;border-radius:50%;width:26px;height:26px;display:flex;align-items:center;justify-content:center;font-size:12px;font-weight:700;color:#fff;box-shadow:0 2px 8px rgba(0,0,0,0.3)">${i + 1}</div>`, iconSize: [26, 26], iconAnchor: [13, 13], className: '' }) }).addTo(map));
      cur.polylines.push(L.polyline([[prev.lat, prev.lng], [stop.lat, stop.lng]], { color: '#f59e0b', weight: 2, opacity: 0.7, dashArray: '6,4' }).addTo(map));
      prev = stop;
    });
  }, [routeStart, routeStops]);

  // ── Zip overlay polygons ─────────────────────────────────
  useEffect(() => {
    const map = mapRef.current; if (!map) return;
    Object.values(zipLayerObjsRef.current).forEach(({ layer, labelMarker }) => { map.removeLayer(layer); map.removeLayer(labelMarker); });
    zipLayerObjsRef.current = {};
    Object.entries(zipLayers).forEach(([zip, info]) => {
      if (!info.visible) return;
      const layer = L.polygon(info.coords, { color: info.color, weight: 2, fillColor: info.color, fillOpacity: 0.08, dashArray: '6,4' }).addTo(map);
      const label = L.divIcon({ html: `<div style="background:${info.color};color:#fff;padding:2px 8px;border-radius:10px;font-size:11px;font-weight:700;opacity:0.85">${zip}</div>`, className: '', iconAnchor: [0, 0] });
      const labelMarker = L.marker(layer.getBounds().getCenter(), { icon: label, interactive: false }).addTo(map);
      zipLayerObjsRef.current[zip] = { layer, labelMarker };
    });
  }, [zipLayers]);

  // ── Map click handling ────────────────────────────────────
  useEffect(() => {
    const map = mapRef.current; if (!map) return;
    const handler = async (e) => {
      const { lat, lng } = e.latlng;
      if (drawingMode) {
        addDrawPoint([lat, lng]);
        return;
      }
      if (!companyId) return;
      const id = await ensurePinAt(lat, lng);
      openSheet(id);
    };
    map.on('click', handler);
    return () => map.off('click', handler);
  }, [drawingMode, addDrawPoint, companyId, ensurePinAt, openSheet]);

  return <div id="map" ref={containerRef} />;
}
