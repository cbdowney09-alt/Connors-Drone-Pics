import { useMemo } from 'react';
import { useApp } from '../context/AppContext';
import { COLORS } from '../constants';

export default function Header() {
  const { pins, currentUserProfile, currentUser, clockedIn, mapUi, logout } = useApp();
  const { roofingMode, toggleRoofingMode, drawingMode, startDrawing, stopDrawing, openPanel, activePanel, setAdminOpen } = mapUi;

  const stats = useMemo(() => {
    const counts = { none: 0, hanger: 0, interest: 0, no: 0, dnr: 0 };
    Object.values(pins).forEach((p) => { if (counts[p.status] !== undefined) counts[p.status]++; });
    const total = Object.values(counts).reduce((a, b) => a + b, 0);
    return { counts, total };
  }, [pins]);

  const isOwner = currentUserProfile?.role === 'owner';

  return (
    <div id="header">
      <div id="header-inner">
        <h1>Knox<span>Canvas</span></h1>
        <div id="user-name-display">{currentUserProfile?.name || currentUser?.email}</div>
        <div id="stats-row">
          {[{ k: 'interest', label: 'Interested' }, { k: 'hanger', label: 'Hangers' }, { k: 'no', label: 'No' }, { k: 'dnr', label: 'DNR' }]
            .filter(({ k }) => stats.counts[k] > 0)
            .map(({ k, label }) => (
              <div key={k} className="stat-pill" style={{ background: COLORS[k] + '22', color: COLORS[k] }}>
                <span className="dot" style={{ background: COLORS[k] }} />{stats.counts[k]} {label}
              </div>
            ))}
          {stats.total > 0 && (
            <div className="stat-pill" style={{ background: 'rgba(255,255,255,0.05)', color: '#8b90b0' }}>{stats.total} total</div>
          )}
        </div>
      </div>
      <div id="header-btns">
        <button className={'hbtn' + (clockedIn ? ' active' : '')} title="Shifts" onClick={() => openPanel('shifts')}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><circle cx="12" cy="12" r="10" /><polyline points="12 6 12 12 16 14" /></svg>
        </button>
        <button className={'hbtn' + (activePanel === 'route' ? ' active' : '')} title="Route" onClick={() => openPanel('route')}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polyline points="22 12 18 12 15 21 9 3 6 12 2 12" /></svg>
        </button>
        <button className={'hbtn' + (roofingMode ? ' active' : '')} title="Roofing mode" onClick={toggleRoofingMode}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z" /><polyline points="9 22 9 12 15 12 15 22" /></svg>
        </button>
        <button className="hbtn" title="Draw zone" onClick={() => (drawingMode ? stopDrawing() : startDrawing(false))}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polygon points="12 2 22 8.5 22 15.5 12 22 2 15.5 2 8.5" /></svg>
        </button>
        <button className="hbtn" title="Export" onClick={() => openPanel('export')}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" /><polyline points="7 10 12 15 17 10" /><line x1="12" y1="15" x2="12" y2="3" /></svg>
        </button>
        <button className="hbtn" title="Metrics" style={{ display: isOwner ? 'flex' : 'none' }} onClick={() => openPanel('metrics')}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><line x1="18" y1="20" x2="18" y2="10" /><line x1="12" y1="20" x2="12" y2="4" /><line x1="6" y1="20" x2="6" y2="14" /></svg>
        </button>
        <button className="hbtn" title="Team admin" style={{ display: isOwner ? 'flex' : 'none' }} onClick={() => setAdminOpen(true)}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" /><path d="M23 21v-2a4 4 0 0 0-3-3.87" /><path d="M16 3.13a4 4 0 0 1 0 7.75" /></svg>
        </button>
        <button className="hbtn" title="Log out" onClick={logout}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" /><polyline points="16 17 21 12 16 7" /><line x1="21" y1="12" x2="9" y2="12" /></svg>
        </button>
      </div>
    </div>
  );
}
