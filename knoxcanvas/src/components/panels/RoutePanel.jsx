import { useState } from 'react';
import L from 'leaflet';
import { useApp } from '../../context/AppContext';
import { fetchHousesFromOSM } from '../../utils/geocode';
import { optimizeRoute, distBetween } from '../../utils/geo';

export default function RoutePanel() {
  const { pins, mapRef, showToast, mapUi } = useApp();
  const {
    routeStart, setRouteStart, routeZonePolygon,
    setRouteStops, clearRoute, startDrawing, activePanel, closePanel,
  } = mapUi;
  const open = activePanel === 'route';

  const [skipVisited, setSkipVisited] = useState(true);
  const [skipDnr, setSkipDnr] = useState(true);
  const [loading, setLoading] = useState(false);
  const [result, setResult] = useState(null); // { route, totalDist }

  const onClear = () => {
    clearRoute();
    setResult(null);
    showToast('Route cleared');
  };

  const onDrawZone = () => {
    closePanel();
    startDrawing(true);
  };

  const generate = async () => {
    let start = routeStart;
    if (!start && routeZonePolygon && routeZonePolygon.length >= 3) {
      const lats = routeZonePolygon.map((p) => p[0]), lngs = routeZonePolygon.map((p) => p[1]);
      start = { lat: (Math.min(...lats) + Math.max(...lats)) / 2, lng: (Math.min(...lngs) + Math.max(...lngs)) / 2, addr: 'Zone center' };
      setRouteStart(start);
    }
    if (!start) { showToast('Draw a zone or tap a pin to set start'); return; }

    setLoading(true);
    setResult(null);
    try {
      const houses = await fetchHousesFromOSM(start.lat, start.lng, routeZonePolygon);
      const stops = houses.filter((h) => {
        const id = h.lat.toFixed(6) + ',' + h.lng.toFixed(6);
        const ex = pins[id];
        if (ex) {
          if (skipVisited && ex.status !== 'none') return false;
          if (skipDnr && ex.status === 'dnr') return false;
        }
        return true;
      });
      if (stops.length === 0) { showToast('No houses found in zone'); return; }
      const route = optimizeRoute(start, stops);
      setRouteStops(route);
      const bounds = L.latLngBounds([[start.lat, start.lng], ...route.map((s) => [s.lat, s.lng])]);
      mapRef.current?.fitBounds(bounds.pad(0.15));
      const totalDist = route.reduce((acc, stop, i) => acc + (i === 0 ? distBetween(start, stop) : distBetween(route[i - 1], stop)), 0);
      setResult({ route, totalDist, start });
      showToast(`Route: ${route.length} houses`);
    } catch (e) {
      showToast('Could not fetch houses — check connection');
    } finally {
      setLoading(false);
    }
  };

  const viewOnMap = () => {
    closePanel();
    if (result) {
      const bounds = L.latLngBounds([[result.start.lat, result.start.lng], ...result.route.map((s) => [s.lat, s.lng])]);
      mapRef.current?.fitBounds(bounds.pad(0.15));
    }
  };

  const fmtDist = (d) => (d < 100 ? Math.round(d) + 'm' : (d / 1000).toFixed(2) + 'km');
  const fmtTotal = (d) => (d < 1000 ? Math.round(d) + 'm' : (d / 1000).toFixed(1) + 'km');

  return (
    <div id="route-panel" className={'panel' + (open ? ' open' : '')}>
      <div className="panel-header">
        <button className="panel-back" onClick={closePanel}><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M19 12H5" /><path d="m12 19-7-7 7-7" /></svg></button>
        <h2>Route Optimizer</h2>
        <button className="panel-action-btn" onClick={onClear}>Clear</button>
      </div>
      <div id="route-body">
        <div id="route-start-label" className={routeStart ? 'ready' : ''}>
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10" /><line x1="12" y1="8" x2="12" y2="12" /><line x1="12" y1="16" x2="12.01" y2="16" /></svg>
          <span id="route-start-text">{routeStart ? `📍 Start: ${routeStart.addr}` : 'Tap a pin → "Set as route start"'}</span>
        </div>
        <div id="route-zone-status" className={routeZonePolygon ? 'ready' : ''}>
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polygon points="12 2 22 8.5 22 15.5 12 22 2 15.5 2 8.5" /></svg>
          <span id="route-zone-text">{routeZonePolygon ? `Zone drawn · ${routeZonePolygon.length} points` : 'No zone drawn'}</span>
        </div>
        <button id="route-draw-zone-btn" onClick={onDrawZone}>
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polygon points="12 2 22 8.5 22 15.5 12 22 2 15.5 2 8.5" /></svg>
          Draw Route Zone on Map
        </button>
        <p className="filter-label">Options</p>
        <div id="route-options">
          <div className="route-option-row"><label>Skip already visited</label><input type="checkbox" checked={skipVisited} onChange={(e) => setSkipVisited(e.target.checked)} /></div>
          <div className="route-option-row"><label>Skip Do Not Return</label><input type="checkbox" checked={skipDnr} onChange={(e) => setSkipDnr(e.target.checked)} /></div>
        </div>
        <button id="route-go-btn" style={{ display: loading ? 'none' : 'flex' }} onClick={generate}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polygon points="5 3 19 12 5 21 5 3" /></svg>
          Generate Route
        </button>
        {loading && <div id="route-loading" style={{ display: 'block' }}><div className="spinner" style={{ margin: '0 auto 8px' }} />Fetching houses…</div>}
        <div id="route-result">
          {result && (
            <>
              <button id="route-view-map-btn" onClick={viewOnMap}>
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polygon points="3 6 9 3 15 6 21 3 21 18 15 21 9 18 3 21" /></svg>
                View Route on Map
              </button>
              <div className="route-stop">
                <div className="route-num" style={{ background: '#fff', color: '#4f6ef7', border: '2px solid #4f6ef7' }}>S</div>
                <div className="route-addr">{result.start.addr} <span style={{ color: 'var(--text2)', fontSize: 11 }}>(Start)</span></div>
              </div>
              {result.route.map((stop, i) => {
                const dist = i === 0 ? distBetween(result.start, stop) : distBetween(result.route[i - 1], stop);
                return (
                  <div className="route-stop" key={i}>
                    <div className="route-num">{i + 1}</div>
                    <div className="route-addr">{stop.addr}</div>
                    <div className="route-dist">{fmtDist(dist)}</div>
                  </div>
                );
              })}
              <div id="route-total">{result.route.length} stops · {fmtTotal(result.totalDist)} total</div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
