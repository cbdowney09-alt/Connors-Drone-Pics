import { useEffect, useRef, useState } from 'react';
import { useApp } from '../context/AppContext';
import { COLORS } from '../constants';

const STATUS_ORDER = ['none', 'hanger', 'interest', 'no', 'dnr'];
const STATUS_TEXT = {
  none: 'Not visited',
  hanger: 'Door hanger left',
  interest: 'Spoke to someone — interested',
  no: 'Spoke to someone — not interested',
  dnr: 'Do not return / skip',
};

export default function PinSheet() {
  const { pins, updatePinStatus, savePin, removePin, applyYearToRadius, showToast, mapUi } = useApp();
  const { selectedPinId, closeSheet, setRouteStart } = mapUi;
  const p = selectedPinId ? pins[selectedPinId] : null;

  const [note, setNote] = useState('');
  const [year, setYear] = useState('');
  const noteDebounce = useRef(null);
  const yearDebounce = useRef(null);

  useEffect(() => {
    setNote(p?.note || '');
    setYear(p?.yearBuilt || '');
  }, [selectedPinId]); // eslint-disable-line react-hooks/exhaustive-deps

  if (!p) {
    return (
      <>
        <div id="overlay" onClick={closeSheet} />
        <div id="sheet">
          <div id="sheet-handle" />
          <div id="sheet-addr">Select a location</div>
          <div id="sheet-coords" />
        </div>
      </>
    );
  }

  const yearLabel = p.yearBuilt ? ` · Built ${p.yearBuilt}` : '';

  const onNoteChange = (v) => {
    setNote(v);
    clearTimeout(noteDebounce.current);
    noteDebounce.current = setTimeout(() => savePin(selectedPinId, { note: v }), 800);
  };

  const onYearChange = (v) => {
    setYear(v);
    clearTimeout(yearDebounce.current);
    yearDebounce.current = setTimeout(() => savePin(selectedPinId, { yearBuilt: v }), 800);
  };

  const applyToNeighborhood = () => {
    if (!year) { showToast('Enter a year first'); return; }
    applyYearToRadius(selectedPinId, year);
  };

  const setAsRouteStart = () => {
    setRouteStart({ lat: p.lat, lng: p.lng, addr: p.addr || 'Selected pin' });
    closeSheet();
    showToast('Route start set');
  };

  const doDelete = () => {
    showToast('Pin removed');
    closeSheet();
    removePin(selectedPinId);
  };

  return (
    <>
      <div id="overlay" className="visible" onClick={closeSheet} />
      <div id="sheet" className="open">
        <div id="sheet-handle" />
        <div id="sheet-addr">{p.addr || 'Unnamed location'}</div>
        <div id="sheet-coords">{p.lat.toFixed(5)}, {p.lng.toFixed(5)}{yearLabel}</div>
        <a id="zillow-btn" href={`https://www.zillow.com/homes/${encodeURIComponent((p.addr || '').trim())}_rb/`} target="_blank" rel="noopener noreferrer">
          <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6" /><polyline points="15 3 21 3 21 9" /><line x1="10" y1="14" x2="21" y2="3" /></svg>
          View on Zillow
        </a>
        {STATUS_ORDER.map((s) => (
          <button key={s} className={'status-btn' + (p.status === s ? ' active' : '')} onClick={() => updatePinStatus(selectedPinId, s)}>
            <span className="swatch" style={{ background: COLORS[s] }} />{STATUS_TEXT[s]}<span className="check">✓</span>
          </button>
        ))}
        <div id="sheet-note-row"><textarea id="sheet-note" rows={2} placeholder="Add a note (optional)…" value={note} onChange={(e) => onNoteChange(e.target.value)} /></div>
        <div id="sheet-year-row"><input id="sheet-year" type="number" placeholder="Year built (e.g. 1998)" min="1800" max="2025" value={year} onChange={(e) => onYearChange(e.target.value)} /></div>
        <div id="neighborhood-year-row">
          <button id="neighborhood-year-btn" onClick={applyToNeighborhood}>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><rect x="3" y="3" width="18" height="18" rx="2" /><path d="M3 9h18M9 21V9" /></svg>
            Apply year to whole neighborhood
          </button>
        </div>
        <button id="sheet-set-start" onClick={setAsRouteStart}>📍 Set as route start</button>
        <button id="sheet-delete" onClick={doDelete}>Remove this pin</button>
        <button id="sheet-close" onClick={closeSheet}>Done</button>
      </div>
    </>
  );
}
