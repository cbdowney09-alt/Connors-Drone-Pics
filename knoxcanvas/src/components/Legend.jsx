import { useMemo } from 'react';
import { useApp } from '../context/AppContext';

const ROWS = [
  { filter: 'none', label: 'Not visited', color: 'var(--c-none)' },
  { filter: 'hanger', label: 'Door hanger', color: 'var(--c-hanger)' },
  { filter: 'interest', label: 'Interested', color: 'var(--c-interest)' },
  { filter: 'no', label: 'Not interested', color: 'var(--c-no)' },
  { filter: 'dnr', label: 'Do not return', color: 'var(--c-dnr)' },
];

export default function Legend() {
  const { pins, mapUi } = useApp();
  const { hiddenStatuses, toggleStatusFilter } = mapUi;

  const counts = useMemo(() => {
    const c = { none: 0, hanger: 0, interest: 0, no: 0, dnr: 0 };
    Object.values(pins).forEach((p) => { if (c[p.status] !== undefined) c[p.status]++; });
    return c;
  }, [pins]);
  const total = Object.values(counts).reduce((a, b) => a + b, 0);

  const allActive = hiddenStatuses.size === 0;

  return (
    <div id="legend">
      <div className={'legend-row' + (allActive ? ' active' : '')} onClick={() => toggleStatusFilter('all')}>
        <div className="dot" style={{ background: 'rgba(255,255,255,0.2)' }} /><span>All pins</span><span className="label-count">{total}</span>
      </div>
      {ROWS.map(({ filter, label, color }) => (
        <div key={filter} className={'legend-row' + (!hiddenStatuses.has(filter) ? ' active' : '')} onClick={() => toggleStatusFilter(filter)}>
          <div className="dot" style={{ background: color }} /><span>{label}</span><span className="label-count">{counts[filter]}</span>
        </div>
      ))}
    </div>
  );
}
