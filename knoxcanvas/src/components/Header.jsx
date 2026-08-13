import { useMemo, useRef, useState, useEffect } from 'react';
import { useApp } from '../context/AppContext';
import { COLORS } from '../constants';

const QUICK_TAP_OPTIONS = [
  { key: null, label: 'Off' },
  { key: 'none', label: 'Not visited' },
  { key: 'hanger', label: 'Door hanger' },
  { key: 'interest', label: 'Interested' },
  { key: 'no', label: 'Not interested' },
  { key: 'dnr', label: 'Do not return' },
];

function useIsTouchDevice() {
  const [isTouch, setIsTouch] = useState(() => window.matchMedia('(hover: none) and (pointer: coarse)').matches);
  useEffect(() => {
    const mq = window.matchMedia('(hover: none) and (pointer: coarse)');
    const onChange = (e) => setIsTouch(e.matches);
    mq.addEventListener('change', onChange);
    return () => mq.removeEventListener('change', onChange);
  }, []);
  return isTouch;
}

export default function Header() {
  const { pins, currentUserProfile, currentUser, clockedIn, mapUi, logout } = useApp();
  const { roofingMode, toggleRoofingMode, quickTapStatus, setQuickTapStatus, drawingMode, startDrawing, stopDrawing, openPanel, activePanel, setAdminOpen } = mapUi;

  const stats = useMemo(() => {
    const counts = { none: 0, hanger: 0, interest: 0, no: 0, dnr: 0 };
    Object.values(pins).forEach((p) => { if (counts[p.status] !== undefined) counts[p.status]++; });
    const total = Object.values(counts).reduce((a, b) => a + b, 0);
    return { counts, total };
  }, [pins]);

  const isOwner = currentUserProfile?.role === 'owner';

  const [quickTapMenuOpen, setQuickTapMenuOpen] = useState(false);
  const [quickTapMenuPos, setQuickTapMenuPos] = useState({ top: 0, right: 0 });
  const quickTapBtnRef = useRef(null);

  const openQuickTapMenu = () => {
    const rect = quickTapBtnRef.current?.getBoundingClientRect();
    if (rect) setQuickTapMenuPos({ top: rect.bottom + 6, right: window.innerWidth - rect.right });
    setQuickTapMenuOpen((v) => !v);
  };

  useEffect(() => {
    if (!quickTapMenuOpen) return;
    const onDocClick = (e) => {
      if (!e.target.closest('#quicktap-menu') && !e.target.closest('#quicktap-btn')) setQuickTapMenuOpen(false);
    };
    document.addEventListener('click', onDocClick);
    return () => document.removeEventListener('click', onDocClick);
  }, [quickTapMenuOpen]);

  const isTouch = useIsTouchDevice();
  const [moreMenuOpen, setMoreMenuOpen] = useState(false);
  const [moreMenuPos, setMoreMenuPos] = useState({ top: 0, right: 0 });
  const moreBtnRef = useRef(null);

  const openMoreMenu = () => {
    const rect = moreBtnRef.current?.getBoundingClientRect();
    if (rect) setMoreMenuPos({ top: rect.bottom + 6, right: window.innerWidth - rect.right });
    setMoreMenuOpen((v) => !v);
  };

  useEffect(() => {
    if (!moreMenuOpen) return;
    const onDocClick = (e) => {
      if (!e.target.closest('#more-menu') && !e.target.closest('#more-btn')) setMoreMenuOpen(false);
    };
    document.addEventListener('click', onDocClick);
    return () => document.removeEventListener('click', onDocClick);
  }, [moreMenuOpen]);

  const MORE_OPTIONS = [
    { label: 'Draw Zone', onClick: () => (drawingMode ? stopDrawing() : startDrawing(false)), show: true,
      icon: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polygon points="12 2 22 8.5 22 15.5 12 22 2 15.5 2 8.5" /></svg> },
    { label: 'Export', onClick: () => openPanel('export'), show: true,
      icon: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" /><polyline points="7 10 12 15 17 10" /><line x1="12" y1="15" x2="12" y2="3" /></svg> },
    { label: 'Metrics', onClick: () => openPanel('metrics'), show: isOwner,
      icon: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><line x1="18" y1="20" x2="18" y2="10" /><line x1="12" y1="20" x2="12" y2="4" /><line x1="6" y1="20" x2="6" y2="14" /></svg> },
    { label: 'Team Admin', onClick: () => setAdminOpen(true), show: isOwner,
      icon: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" /><circle cx="9" cy="7" r="4" /><path d="M23 21v-2a4 4 0 0 0-3-3.87" /><path d="M16 3.13a4 4 0 0 1 0 7.75" /></svg> },
    { label: 'Log Out', onClick: logout, show: true,
      icon: <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4" /><polyline points="16 17 21 12 16 7" /><line x1="21" y1="12" x2="9" y2="12" /></svg> },
  ];

  const quickTapBtnStyle = quickTapStatus
    ? { background: COLORS[quickTapStatus], borderColor: COLORS[quickTapStatus], color: '#fff' }
    : undefined;

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
        <button id="quicktap-btn" ref={quickTapBtnRef} className={'hbtn' + (quickTapStatus ? ' active' : '')} style={quickTapBtnStyle} title="Quick tap mode" onClick={openQuickTapMenu}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2" /></svg>
        </button>
        {isTouch ? (
          <button id="more-btn" ref={moreBtnRef} className={'hbtn' + (moreMenuOpen ? ' active' : '')} title="More" onClick={openMoreMenu}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="2" /><circle cx="12" cy="12" r="2" /><circle cx="19" cy="12" r="2" /></svg>
          </button>
        ) : (
          <>
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
          </>
        )}
      </div>
      {moreMenuOpen && (
        <div id="more-menu" style={{ top: moreMenuPos.top, right: moreMenuPos.right }}>
          {MORE_OPTIONS.filter((o) => o.show).map(({ label, onClick, icon }) => (
            <div key={label} className="more-option" onClick={() => { onClick(); setMoreMenuOpen(false); }}>
              {icon}{label}
            </div>
          ))}
        </div>
      )}
      {quickTapMenuOpen && (
        <div id="quicktap-menu" style={{ top: quickTapMenuPos.top, right: quickTapMenuPos.right }}>
          {QUICK_TAP_OPTIONS.map(({ key, label }) => (
            <div key={label} className={'quicktap-option' + (quickTapStatus === key ? ' active' : '')}
              onClick={() => { setQuickTapStatus(key); setQuickTapMenuOpen(false); }}>
              <span className="dot" style={{ background: key ? COLORS[key] : 'rgba(255,255,255,0.2)' }} />
              {label}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
