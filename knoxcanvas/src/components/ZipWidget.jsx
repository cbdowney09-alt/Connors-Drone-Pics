import { useRef, useState } from 'react';
import L from 'leaflet';
import { useApp } from '../context/AppContext';
import { fetchZipBoundary } from '../utils/geocode';

export default function ZipWidget() {
  const { mapRef, showToast, mapUi } = useApp();
  const { zipLayers, addZipLayer, toggleZipVisible, removeZipLayer } = mapUi;
  const [inputOpen, setInputOpen] = useState(false);
  const [zipInput, setZipInput] = useState('');
  const [loadingZips, setLoadingZips] = useState([]);
  const inputRef = useRef(null);

  const toggleInput = () => {
    setInputOpen((v) => {
      const next = !v;
      if (next) setTimeout(() => inputRef.current?.focus(), 0);
      return next;
    });
  };

  const addZip = async () => {
    const zip = zipInput.trim();
    if (zip.length !== 5 || isNaN(zip)) { showToast('Enter a valid 5-digit zip'); return; }
    if (zipLayers[zip]) { showToast('Already added'); return; }

    setZipInput('');
    setInputOpen(false);
    setLoadingZips((prev) => [...prev, zip]);

    try {
      const coords = await fetchZipBoundary(zip);
      setLoadingZips((prev) => prev.filter((z) => z !== zip));
      if (!coords || coords.length === 0) { showToast(`No boundary found for ${zip}`); return; }
      addZipLayer(zip, coords);
      const bounds = L.latLngBounds(coords);
      mapRef.current?.fitBounds(bounds.pad(0.05));
      showToast(`${zip} added`);
    } catch (e) {
      setLoadingZips((prev) => prev.filter((z) => z !== zip));
      showToast(`Could not load ${zip}`);
      console.error(e);
    }
  };

  return (
    <div id="zip-widget">
      <div id="zip-header">
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z" /><circle cx="12" cy="10" r="3" /></svg>
        <span>Zip Codes</span>
        <button id="zip-add-toggle" onClick={toggleInput}>+</button>
      </div>
      {inputOpen && (
        <div id="zip-input-row" style={{ display: 'flex' }}>
          <input id="zip-input" ref={inputRef} type="number" placeholder="e.g. 37923" maxLength={5}
            value={zipInput} onChange={(e) => setZipInput(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') addZip(); }} />
          <button id="zip-add-btn" onClick={addZip}>Add</button>
        </div>
      )}
      <div id="zip-list">
        {loadingZips.map((zip) => <div className="zip-loading" key={zip}>Loading {zip}…</div>)}
        {Object.entries(zipLayers).map(([zip, info]) => (
          <div key={zip} className={'zip-tag' + (info.visible ? ' active' : '')}
            style={{ color: info.color, background: info.color + '18' }}
            onClick={() => toggleZipVisible(zip)}>
            <span>{zip}</span>
            <span className="zip-tag-remove" onClick={(e) => { e.stopPropagation(); removeZipLayer(zip); }}>✕</span>
          </div>
        ))}
      </div>
    </div>
  );
}
