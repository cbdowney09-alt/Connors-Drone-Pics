import { useApp } from '../../context/AppContext';
import { formatDuration, formatTime, formatDate } from '../../utils/format';
import { shiftsToCsvLines, downloadCsv } from '../../utils/csv';

export default function ShiftsPanel() {
  const { shifts, clockedIn, clockInTime, elapsedMs, liveHangerCount, clockIn, clockOut, showToast, mapUi } = useApp();
  const open = mapUi.activePanel === 'shifts';

  const exportCsv = () => {
    if (!shifts.length) { showToast('No shifts to export'); return; }
    downloadCsv(`shifts_${new Date().toISOString().slice(0, 10)}.csv`, shiftsToCsvLines(shifts));
    showToast('Shifts CSV downloaded');
  };

  return (
    <div id="shifts-panel" className={'panel' + (open ? ' open' : '')}>
      <div className="panel-header">
        <button className="panel-back" onClick={mapUi.closePanel}><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M19 12H5" /><path d="m12 19-7-7 7-7" /></svg></button>
        <h2>Shifts</h2>
        <button className="panel-action-btn" onClick={exportCsv}>Export CSV</button>
      </div>
      <div id="clock-card">
        <div id="clock-status">{clockedIn ? 'Clocked In' : 'Clocked Out'}</div>
        <div id="clock-timer" className={clockedIn ? 'running' : ''}>{formatDuration(elapsedMs)}</div>
        <div id="clock-date">{clockedIn && clockInTime ? formatDate(clockInTime) : ''}</div>
        {clockedIn && (
          <div id="clock-hangers-live" style={{ display: 'block' }}>This shift: <span id="live-hanger-count">{liveHangerCount}</span> hangers</div>
        )}
        <button id="clock-btn" className={clockedIn ? 'clocked-in' : 'clocked-out'} onClick={() => (clockedIn ? clockOut() : clockIn())}>
          {clockedIn ? 'Clock Out' : 'Clock In'}
        </button>
      </div>
      <div id="shifts-list">
        <div className="shifts-section-title">Shift History</div>
        <div id="shifts-history">
          {!shifts.length ? (
            <div style={{ textAlign: 'center', padding: 24, fontSize: 13, color: 'var(--text2)' }}>No shifts yet</div>
          ) : shifts.map((s, i) => (
            <div className="shift-card" key={s.id || i}>
              <div className="shift-card-header"><div className="shift-date">{formatDate(s.clockIn)}</div><div className="shift-duration">{formatDuration(s.durationMs)}</div></div>
              <div className="shift-times">{formatTime(s.clockIn)} → {formatTime(s.clockOut)}</div>
              <div className="shift-stats">
                <div className="shift-stat highlight"><div className="ss-val">{s.hangers}</div><div className="ss-label">Hangers</div></div>
                <div className="shift-stat"><div className="ss-val">{s.hangersPerHour}</div><div className="ss-label">Per Hour</div></div>
                <div className="shift-stat"><div className="ss-val">{(s.durationMs / 3600000).toFixed(2)}h</div><div className="ss-label">Hours</div></div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
