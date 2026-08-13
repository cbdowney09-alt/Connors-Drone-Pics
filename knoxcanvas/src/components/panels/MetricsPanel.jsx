import { useEffect, useMemo, useState } from 'react';
import { collection, getDocs, query, where } from 'firebase/firestore';
import { db } from '../../firebase';
import { useApp } from '../../context/AppContext';
import { formatDuration } from '../../utils/format';

function getRangeMs(range) {
  const d = new Date(); d.setHours(0, 0, 0, 0);
  if (range === 'today') return d.getTime();
  if (range === 'week') { d.setDate(d.getDate() - d.getDay()); return d.getTime(); }
  if (range === 'month') { d.setDate(1); return d.getTime(); }
  return 0;
}

export default function MetricsPanel() {
  const { pins, companyId, currentUserProfile, mapUi } = useApp();
  const open = mapUi.activePanel === 'metrics';
  const isOwner = currentUserProfile?.role === 'owner';

  const [range, setRange] = useState('today');
  const [uid, setUid] = useState('all');
  const [employees, setEmployees] = useState([]);
  const [allShifts, setAllShifts] = useState([]);

  const loadMetrics = async () => {
    if (!isOwner || !companyId) return;
    const empSnap = await getDocs(query(collection(db, 'users'), where('companyId', '==', companyId)));
    const emps = []; empSnap.forEach((d) => emps.push({ uid: d.id, ...d.data() }));
    setEmployees(emps);

    const shiftsSnap = await getDocs(collection(db, 'companies', companyId, 'shifts'));
    const list = []; shiftsSnap.forEach((d) => list.push({ id: d.id, ...d.data() }));
    list.sort((a, b) => b.clockIn - a.clockIn);
    setAllShifts(list);
  };

  useEffect(() => { if (open) loadMetrics(); }, [open]); // eslint-disable-line react-hooks/exhaustive-deps

  const since = getRangeMs(range);

  const filtered = useMemo(() => allShifts.filter((s) => {
    if (s.clockIn < since) return false;
    if (uid !== 'all' && s.userId !== uid) return false;
    return true;
  }), [allShifts, since, uid]);

  const filteredPins = useMemo(() => Object.values(pins).filter((p) => {
    if (p.ts < since) return false;
    if (uid !== 'all' && p.updatedBy !== uid) return false;
    return true;
  }), [pins, since, uid]);

  const totalHangers = range === 'all' && uid === 'all'
    ? Object.values(pins).filter((p) => p.status === 'hanger').length
    : filteredPins.filter((p) => p.status === 'hanger').length;
  const interested = range === 'all' && uid === 'all'
    ? Object.values(pins).filter((p) => p.status === 'interest').length
    : filteredPins.filter((p) => p.status === 'interest').length;
  const totalHours = filtered.reduce((a, s) => a + (s.durationMs || 0), 0) / 3600000;
  const totalShifts = filtered.length;
  const avgRate = totalHours > 0 ? (totalHangers / totalHours).toFixed(1) : '—';

  const recentShifts = filtered.slice(0, 20);

  return (
    <div id="metrics-panel" className={'panel' + (open ? ' open' : '')}>
      <div className="panel-header">
        <button className="panel-back" onClick={mapUi.closePanel}><svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><path d="M19 12H5" /><path d="m12 19-7-7 7-7" /></svg></button>
        <h2>Team Metrics</h2>
        <button className="panel-action-btn" onClick={loadMetrics}>↻ Refresh</button>
      </div>

      <div id="metrics-time-filters">
        {[['today', 'Today'], ['week', 'This Week'], ['month', 'This Month'], ['all', 'All Time']].map(([k, label]) => (
          <button key={k} className={'mtime-btn' + (range === k ? ' active' : '')} onClick={() => setRange(k)}>{label}</button>
        ))}
      </div>

      <div id="metrics-emp-selector">
        <button className={'memp-btn' + (uid === 'all' ? ' active' : '')} onClick={() => setUid('all')}>All Employees</button>
        {employees.map((emp) => (
          <button key={emp.uid} className={'memp-btn' + (uid === emp.uid ? ' active' : '')} onClick={() => setUid(emp.uid)}>{emp.name || emp.email}</button>
        ))}
      </div>

      <div id="metrics-summary">
        <div className="metric-card accent"><div className="mc-val">{totalHangers}</div><div className="mc-label">Hangers</div></div>
        <div className="metric-card accent" style={{ '--c-hanger': '#10b981' }}><div className="mc-val" style={{ color: 'var(--c-interest)' }}>{interested}</div><div className="mc-label">Interested</div></div>
        <div className="metric-card"><div className="mc-val">{avgRate}</div><div className="mc-label">Hangers/hr</div></div>
        <div className="metric-card"><div className="mc-val">{totalHours.toFixed(1)}h</div><div className="mc-label">Hours</div></div>
        <div className="metric-card"><div className="mc-val">{totalShifts}</div><div className="mc-label">Shifts</div></div>
        <div className="metric-card"><div className="mc-val">{Math.round(totalHangers / (totalShifts || 1))}</div><div className="mc-label">Hangers/shift</div></div>
      </div>

      {uid === 'all' && (
        <div id="metrics-breakdown-wrap">
          <div className="metrics-section-title">Employee Breakdown</div>
          <div id="metrics-breakdown">
            {!employees.length ? (
              <div style={{ padding: 16, color: 'var(--text2)', fontSize: 13, textAlign: 'center' }}>No employee data yet</div>
            ) : employees.map((emp) => {
              const empShifts = filtered.filter((s) => s.userId === emp.uid);
              const empHangers = range === 'all'
                ? Object.values(pins).filter((p) => p.status === 'hanger' && p.updatedBy === emp.uid).length
                : Object.values(pins).filter((p) => p.status === 'hanger' && p.updatedBy === emp.uid && p.ts >= since).length;
              const empHours = empShifts.reduce((a, s) => a + (s.durationMs || 0), 0) / 3600000;
              const empRate = empHours > 0 ? (empHangers / empHours).toFixed(1) : '—';
              return (
                <div className="breakdown-row" key={emp.uid}>
                  <div className="breakdown-name">{emp.name || emp.email}</div>
                  <div className="breakdown-stats">
                    <div className="breakdown-stat hi"><div className="bs-val">{empHangers}</div><div className="bs-label">Hangers</div></div>
                    <div className="breakdown-stat"><div className="bs-val">{empRate}</div><div className="bs-label">Per Hour</div></div>
                    <div className="breakdown-stat"><div className="bs-val">{empHours.toFixed(1)}h</div><div className="bs-label">Hours</div></div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      <div id="metrics-shifts-wrap">
        <div className="metrics-section-title">Recent Shifts</div>
        <div id="metrics-shifts">
          {!recentShifts.length ? (
            <div style={{ padding: 16, color: 'var(--text2)', fontSize: 13, textAlign: 'center' }}>No shifts in this period</div>
          ) : recentShifts.map((s) => {
            const emp = employees.find((e) => e.uid === s.userId);
            const name = emp ? (emp.name || emp.email) : 'Unknown';
            const date = new Date(s.clockIn).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
            return (
              <div className="mshift-row" key={s.id}>
                <div className="mshift-left"><div className="mshift-name">{name}</div><div className="mshift-date">{date} · {formatDuration(s.durationMs)}</div></div>
                <div className="mshift-right"><div className="mshift-hangers">{s.hangers || 0}</div><div className="mshift-rate">{s.hangersPerHour || 0}/hr</div></div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}
