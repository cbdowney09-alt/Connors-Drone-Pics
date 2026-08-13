import { createContext, useCallback, useContext, useEffect, useMemo, useRef } from 'react';
import { useAuth } from './hooks/useAuth';
import { usePins } from './hooks/usePins';
import { useNeighborhoodYears } from './hooks/useNeighborhoodYears';
import { useShifts } from './hooks/useShifts';
import { useMapUiState } from './hooks/useMapUiState';
import { useToast } from './hooks/useToast';
import { reverseGeocode } from '../utils/geocode';
import { getNeighborhoodYearForPoint, distBetween, pointInPolygon } from '../utils/geo';
import { syncToSheets } from '../utils/sheetsSync';
import { migrateFromJSONBin } from '../utils/jsonbinMigration';
import { LABELS } from '../constants';

const AppCtx = createContext(null);

export function AppProvider({ children }) {
  const auth = useAuth();
  const { currentUser, currentUserProfile, companyId } = auth;
  const { toast, showToast } = useToast();
  const { pins, savePin, deletePin, getPinFresh } = usePins(companyId, currentUser);
  const { neighborhoodYears, saveNeighborhoodYears } = useNeighborhoodYears(companyId);
  const mapUi = useMapUiState();

  const hangerCount = useCallback(() => Object.values(pins).filter((p) => p.status === 'hanger').length, [pins]);
  const shiftsApi = useShifts(companyId, currentUser, currentUserProfile, hangerCount);

  const mapRef = useRef(null);

  const migratedRef = useRef(false);
  useEffect(() => {
    if (companyId && currentUser && currentUserProfile && !migratedRef.current) {
      migratedRef.current = true;
      migrateFromJSONBin(currentUser, currentUserProfile, companyId, showToast);
    }
    if (!companyId) migratedRef.current = false;
  }, [companyId, currentUser, currentUserProfile, showToast]);

  // Once the real address comes back, patch it in — and if the pin has since
  // become (or already was) a hanger, re-send the corrected row to Sheets so
  // "Loading address…" never gets stuck there regardless of how fast someone taps.
  const finalizeAddress = useCallback(async (id, lat, lng) => {
    const addr = await reverseGeocode(lat, lng);
    await savePin(id, { addr });
    const fresh = await getPinFresh(id);
    if (fresh && fresh.status === 'hanger') {
      syncToSheets('upsert', { ...fresh, addr }, id);
    }
  }, [savePin, getPinFresh]);

  const ensurePinAt = useCallback(async (lat, lng, presetAddr) => {
    const id = lat.toFixed(6) + ',' + lng.toFixed(6);
    if (!pins[id]) {
      const autoYear = getNeighborhoodYearForPoint(lat, lng, neighborhoodYears);
      const newPin = { lat, lng, addr: presetAddr || 'Loading address…', status: 'none', note: '', yearBuilt: autoYear, ts: Date.now() };
      await savePin(id, newPin);
      if (!presetAddr) {
        finalizeAddress(id, lat, lng);
      }
    }
    return id;
  }, [pins, neighborhoodYears, savePin, finalizeAddress]);

  const quickTapPin = useCallback(async (lat, lng, status) => {
    const id = lat.toFixed(6) + ',' + lng.toFixed(6);
    const autoYear = getNeighborhoodYearForPoint(lat, lng, neighborhoodYears);
    const newPin = { lat, lng, addr: 'Loading address…', status, note: '', yearBuilt: autoYear, ts: Date.now() };
    await savePin(id, newPin);
    finalizeAddress(id, lat, lng);
    showToast('Saved: ' + LABELS[status]);
    syncToSheets('upsert', { ...newPin, id }, id);
    return id;
  }, [neighborhoodYears, savePin, showToast, finalizeAddress]);

  const updatePinStatus = useCallback(async (id, status) => {
    const patch = { status, ts: Date.now() };
    await savePin(id, patch);
    showToast('Saved: ' + LABELS[status]);
    syncToSheets('upsert', { ...pins[id], ...patch, id }, id);
  }, [savePin, pins, showToast]);

  const removePin = useCallback(async (id) => {
    await deletePin(id);
    syncToSheets('delete', null, id);
  }, [deletePin]);

  const applyYearToRadius = useCallback(async (pinId, year) => {
    const p = pins[pinId];
    if (!p) return;
    const radius = 400;
    let count = 0;
    const updates = [];
    Object.keys(pins).forEach((id) => {
      const other = pins[id];
      const dist = distBetween(p, other);
      if (dist <= radius) { count++; updates.push(savePin(id, { ...pins[id], yearBuilt: year })); }
    });
    const filtered = neighborhoodYears.filter((z) => distBetween(z, p) > 200);
    const nextZones = [...filtered, { lat: p.lat, lng: p.lng, year, radius }];
    await Promise.all([...updates, saveNeighborhoodYears(nextZones)]);
    showToast(`Applied ${year} to ${count} pins`);
  }, [pins, neighborhoodYears, savePin, saveNeighborhoodYears, showToast]);

  const applyYearToPolygon = useCallback(async (polygon, year, name) => {
    const updates = [];
    Object.keys(pins).forEach((id) => {
      const p = pins[id];
      if (pointInPolygon(p.lat, p.lng, polygon)) updates.push(savePin(id, { ...pins[id], yearBuilt: year }));
    });
    const zoneName = name || 'Zone ' + (neighborhoodYears.length + 1);
    const nextZones = [...neighborhoodYears, { name: zoneName, year, polygon: polygon.map((p) => [p[0], p[1]]) }];
    await Promise.all([...updates, saveNeighborhoodYears(nextZones)]);
    showToast(`"${zoneName}" zone saved`);
  }, [pins, neighborhoodYears, savePin, saveNeighborhoodYears, showToast]);

  const value = useMemo(() => ({
    ...auth,
    toast, showToast,
    pins, savePin, deletePin, removePin, updatePinStatus, ensurePinAt, quickTapPin,
    neighborhoodYears, saveNeighborhoodYears, applyYearToRadius, applyYearToPolygon,
    hangerCount,
    ...shiftsApi,
    mapUi,
    mapRef,
  }), [auth, toast, showToast, pins, savePin, deletePin, removePin, updatePinStatus, ensurePinAt, quickTapPin, neighborhoodYears, saveNeighborhoodYears, applyYearToRadius, applyYearToPolygon, hangerCount, shiftsApi, mapUi]);

  return <AppCtx.Provider value={value}>{children}</AppCtx.Provider>;
}

export function useApp() {
  const ctx = useContext(AppCtx);
  if (!ctx) throw new Error('useApp must be used within AppProvider');
  return ctx;
}
