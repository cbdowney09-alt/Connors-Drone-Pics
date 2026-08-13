import { useCallback, useRef, useState } from 'react';
import { ZIP_COLORS } from '../../constants';

export function useMapUiState() {
  // Pin sheet
  const [selectedPinId, setSelectedPinId] = useState(null);
  const openSheet = useCallback((id) => setSelectedPinId(id), []);
  const closeSheet = useCallback(() => setSelectedPinId(null), []);

  // Legend filters
  const [hiddenStatuses, setHiddenStatuses] = useState(() => new Set());
  const toggleStatusFilter = useCallback((filter) => {
    setHiddenStatuses((prev) => {
      if (filter === 'all') return new Set();
      const next = new Set(prev);
      next.has(filter) ? next.delete(filter) : next.add(filter);
      return next;
    });
  }, []);

  // Roofing mode
  const [roofingMode, setRoofingMode] = useState(false);
  const toggleRoofingMode = useCallback(() => setRoofingMode((v) => !v), []);

  // Zone drawing
  const [drawingMode, setDrawingMode] = useState(false);
  const [drawingForRoute, setDrawingForRoute] = useState(false);
  const [drawnPoints, setDrawnPoints] = useState([]);

  const startDrawing = useCallback((forRoute) => {
    setDrawingMode(true);
    setDrawingForRoute(!!forRoute);
    setDrawnPoints([]);
  }, []);

  const stopDrawing = useCallback(() => {
    setDrawingMode(false);
    setDrawnPoints([]);
  }, []);

  const addDrawPoint = useCallback((pt) => {
    setDrawnPoints((prev) => [...prev, pt]);
  }, []);

  const undoDrawPoint = useCallback(() => {
    setDrawnPoints((prev) => prev.slice(0, -1));
  }, []);

  // Route
  const [routeStart, setRouteStart] = useState(null);
  const [routeZonePolygon, setRouteZonePolygon] = useState(null);
  const [routeStops, setRouteStops] = useState([]);

  const clearRoute = useCallback(() => {
    setRouteStart(null);
    setRouteZonePolygon(null);
    setRouteStops([]);
  }, []);

  // Zip overlay
  const [zipLayers, setZipLayers] = useState({}); // zip -> {coords, color, visible}
  const zipColorIdx = useRef(0);

  const addZipLayer = useCallback((zip, coords) => {
    const color = ZIP_COLORS[zipColorIdx.current % ZIP_COLORS.length];
    zipColorIdx.current += 1;
    setZipLayers((prev) => ({ ...prev, [zip]: { coords, color, visible: true } }));
  }, []);

  const toggleZipVisible = useCallback((zip) => {
    setZipLayers((prev) => (prev[zip] ? { ...prev, [zip]: { ...prev[zip], visible: !prev[zip].visible } } : prev));
  }, []);

  const removeZipLayer = useCallback((zip) => {
    setZipLayers((prev) => { const next = { ...prev }; delete next[zip]; return next; });
  }, []);

  // Panels
  const [activePanel, setActivePanel] = useState(null); // 'shifts' | 'route' | 'export' | 'metrics' | null
  const openPanel = useCallback((name) => setActivePanel(name), []);
  const closePanel = useCallback(() => setActivePanel(null), []);
  const [adminOpen, setAdminOpen] = useState(false);

  return {
    selectedPinId, openSheet, closeSheet,
    hiddenStatuses, toggleStatusFilter,
    roofingMode, toggleRoofingMode,
    drawingMode, drawingForRoute, drawnPoints, startDrawing, stopDrawing, addDrawPoint, undoDrawPoint,
    routeStart, setRouteStart, routeZonePolygon, setRouteZonePolygon, routeStops, setRouteStops, clearRoute,
    zipLayers, addZipLayer, toggleZipVisible, removeZipLayer,
    activePanel, openPanel, closePanel,
    adminOpen, setAdminOpen,
  };
}
