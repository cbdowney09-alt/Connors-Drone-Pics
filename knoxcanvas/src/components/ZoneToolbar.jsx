import { useEffect, useState } from 'react';
import { useApp } from '../context/AppContext';

export default function ZoneToolbar() {
  const { showToast, applyYearToPolygon, mapUi } = useApp();
  const {
    drawingMode, drawingForRoute, drawnPoints,
    undoDrawPoint, stopDrawing,
    setRouteStart, routeStart, setRouteZonePolygon, openPanel,
  } = mapUi;

  const [zoneYear, setZoneYear] = useState('');
  const [zoneName, setZoneName] = useState('');

  useEffect(() => {
    if (drawingMode) { setZoneYear(''); setZoneName(''); }
  }, [drawingMode]);

  const finish = async () => {
    if (drawnPoints.length < 3) { showToast('Need at least 3 points'); return; }

    if (drawingForRoute) {
      const polygon = drawnPoints.map((p) => [p[0], p[1]]);
      setRouteZonePolygon(polygon);
      if (!routeStart) {
        const lats = polygon.map((p) => p[0]), lngs = polygon.map((p) => p[1]);
        setRouteStart({ lat: (Math.min(...lats) + Math.max(...lats)) / 2, lng: (Math.min(...lngs) + Math.max(...lngs)) / 2, addr: 'Zone center' });
      }
      stopDrawing();
      openPanel('route');
      showToast('Route zone set');
      return;
    }

    if (!zoneYear) { showToast('Enter a year built first'); return; }
    await applyYearToPolygon(drawnPoints, zoneYear, zoneName);
    stopDrawing();
  };

  const pointCountText = drawnPoints.length === 0
    ? '0 points — tap the map to start'
    : drawnPoints.length < 3
      ? `${drawnPoints.length} point(s) — need at least 3`
      : `${drawnPoints.length} points — ready to save`;

  return (
    <div id="zone-toolbar" className={drawingMode ? 'active' : ''}>
      <div id="zone-toolbar-inner">
        <div id="zone-toolbar-title">{drawingForRoute ? '🗺 Draw ROUTE zone — tap edges' : '📍 Tap map edges to draw zone'}</div>
        <div id="zone-toolbar-fields">
          <input id="zone-year-input" type="number" placeholder="Year built" style={{ display: drawingForRoute ? 'none' : '' }}
            value={zoneYear} onChange={(e) => setZoneYear(e.target.value)} />
          <input id="zone-name-input" type="text" placeholder="Zone name" style={{ display: drawingForRoute ? 'none' : '' }}
            value={zoneName} onChange={(e) => setZoneName(e.target.value)} />
        </div>
        <div id="zone-toolbar-btns">
          <button id="zone-undo-btn" onClick={undoDrawPoint}>↩ Undo</button>
          <button id="zone-finish-btn" onClick={finish}>{drawingForRoute ? '✓ Set Route Zone' : '✓ Save Zone'}</button>
          <button id="zone-cancel-btn" onClick={stopDrawing}>✕ Cancel</button>
        </div>
        <div id="zone-point-count">{pointCountText}</div>
      </div>
    </div>
  );
}
