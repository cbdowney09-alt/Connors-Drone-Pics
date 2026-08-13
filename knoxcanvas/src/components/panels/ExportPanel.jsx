import { useMemo, useState } from 'react';
import { useApp } from '../../context/AppContext';
import { COLORS, LABELS } from '../../constants';
import { pinsToCsvLines, downloadCsv } from '../../utils/csv';

export default function ExportPanel() {
  const { pins, showToast, mapUi } = useApp();
  const open = mapUi.activePanel === 'export';
  const [included, setIncluded] = useState(() => new Set(['none', 'hanger', 'interest', 'no', 'dnr']));

  const counts = useMemo(() => {
    const c = { none: 0, hanger: 0, interest: 0, no: 0, dnr: 0 };
    Object.values(pins).forEach((p) => { if (c[p.status] !== undefined) c[p.status]++; });
    return c;
  }, [pins]);
  const total = Object.values(counts).reduce((a, b) => a + b, 0);

  const rows = useMemo(() => (
    Object.values(pins).filter((p) => included.has(p.status)).sort((a, b) => b.ts - a.ts)
  ), [pins, included]);

  const toggleStatus = (k) => {
    setIncluded((prev) => { const next = new Set(prev); next.has(k) ? next.delete(k) : next.add(k); return next; });
  };

  const exportCsv = () => {
    if (!rows.length) { showToast('No data to export'); return; }
    downloadCsv(`knoxcanvas_${new Date().toISOString().slice(0, 10)}.csv`, pinsToCsvLines(rows));
    showToast('CSV downloaded');
  };

  return (
    <div id="export-panel" className={'panel' + (open ? ' open' : '')}>
      <div className="panel-header">
        <button className="panel-back" onClick={mapUi.closePanel}><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M19 12H5" /><path d="m12 19-7-7 7-7" /></svg></button>
        <h2>Export data</h2>
      </div>
      <div id="export-summary">
        <div className="export-stat"><div className="es-label">Total pins</div><div className="es-val">{total}</div></div>
        <div className="export-stat"><div className="es-label" style={{ color: 'var(--c-interest)' }}>Interested</div><div className="es-val" style={{ color: 'var(--c-interest)' }}>{counts.interest}</div></div>
        <div className="export-stat"><div className="es-label" style={{ color: 'var(--c-hanger)' }}>Door hangers</div><div className="es-val" style={{ color: 'var(--c-hanger)' }}>{counts.hanger}</div></div>
        <div className="export-stat"><div className="es-label" style={{ color: 'var(--c-dnr)' }}>Do not return</div><div className="es-val" style={{ color: 'var(--c-dnr)' }}>{counts.dnr}</div></div>
      </div>
      <div id="export-filters">
        <p className="filter-label">Include statuses</p>
        <div id="export-status-toggles">
          {Object.entries(LABELS).map(([k, label]) => (
            <button key={k} className={'etoggle' + (included.has(k) ? ' on' : '')} onClick={() => toggleStatus(k)}>
              <span className="dot" style={{ background: COLORS[k] }} />{label}
            </button>
          ))}
        </div>
      </div>
      <div id="export-preview-wrap">
        <p className="filter-label">Preview <span id="export-count">({rows.length} rows)</span></p>
        <div id="export-preview">
          {!rows.length ? (
            <div className="ep-empty">No pins match selected filters</div>
          ) : (
            <>
              {rows.slice(0, 50).map((p) => {
                const date = new Date(p.ts).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
                return (
                  <div className="ep-row" key={p.id}>
                    <div>
                      <div className="ep-addr">{p.addr || 'Unknown'}</div>
                      <div className="ep-status" style={{ color: COLORS[p.status] }}>{LABELS[p.status]}</div>
                    </div>
                    <div className="ep-date">{date}</div>
                  </div>
                );
              })}
              {rows.length > 50 && <div className="ep-empty">+ {rows.length - 50} more in CSV</div>}
            </>
          )}
        </div>
      </div>
      <button id="export-csv-btn" onClick={exportCsv}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" /><polyline points="7 10 12 15 17 10" /><line x1="12" y1="15" x2="12" y2="3" /></svg>
        Download CSV
      </button>
    </div>
  );
}
