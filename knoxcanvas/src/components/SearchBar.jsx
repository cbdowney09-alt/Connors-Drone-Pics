import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { useApp } from '../context/AppContext';
import { searchAddress } from '../utils/geocode';

export default function SearchBar() {
  const { mapRef, ensurePinAt, mapUi, headerHeight, setTopChromeBottom } = useApp();
  const [query, setQuery] = useState('');
  const [results, setResults] = useState([]);
  const [open, setOpen] = useState(false);
  const [resultsTop, setResultsTop] = useState(0);
  const timeoutRef = useRef(null);
  const wrapRef = useRef(null);

  // Sits right below the header; report our own bottom edge so QuickTapBanner
  // (which stacks below us) stays positioned correctly no matter how tall
  // the header renders.
  useLayoutEffect(() => {
    if (wrapRef.current) {
      setTopChromeBottom(wrapRef.current.getBoundingClientRect().bottom + 8);
    }
  }, [headerHeight, setTopChromeBottom]);

  useEffect(() => {
    clearTimeout(timeoutRef.current);
    const q = query.trim();
    if (q.length < 3) { setOpen(false); return; }
    timeoutRef.current = setTimeout(async () => {
      try {
        const data = await searchAddress(q);
        setResults(data);
        if (data.length && wrapRef.current) {
          const rect = wrapRef.current.getBoundingClientRect();
          setResultsTop(rect.bottom + 6);
        }
        setOpen(data.length > 0);
      } catch (e) { setOpen(false); }
    }, 400);
    return () => clearTimeout(timeoutRef.current);
  }, [query]);

  useEffect(() => {
    const onDocClick = (e) => {
      if (!e.target.closest('#search-bar') && !e.target.closest('#search-results')) setOpen(false);
    };
    document.addEventListener('click', onDocClick);
    return () => document.removeEventListener('click', onDocClick);
  }, []);

  const selectResult = async (item) => {
    const lat = parseFloat(item.lat), lng = parseFloat(item.lon);
    mapRef.current?.setView([lat, lng], 17);
    setOpen(false); setQuery('');
    const presetAddr = item.display_name.split(',').slice(0, 3).join(',');
    const id = await ensurePinAt(lat, lng, presetAddr);
    setTimeout(() => mapUi.openSheet(id), 300);
  };

  return (
    <div id="search-wrap">
      <div id="search-bar" ref={wrapRef} style={{ marginTop: headerHeight + 10 }}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="11" cy="11" r="8" /><path d="m21 21-4.35-4.35" /></svg>
        <input id="search-input" type="text" placeholder="Search Knoxville address…" autoComplete="off" autoCorrect="off" spellCheck="false"
          value={query} onChange={(e) => setQuery(e.target.value)} />
      </div>
      <div id="search-results" style={{ display: open ? 'block' : 'none', top: resultsTop }}>
        {results.map((item, i) => {
          const parts = item.display_name.split(',');
          return (
            <div className="search-result" key={item.place_id || i} onClick={() => selectResult(item)}>
              <strong>{parts[0]}</strong>, {parts.slice(1, 3).join(',')}
            </div>
          );
        })}
      </div>
    </div>
  );
}
