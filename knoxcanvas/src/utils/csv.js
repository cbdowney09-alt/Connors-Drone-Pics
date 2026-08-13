import { LABELS } from '../constants';
import { formatDuration, formatTime, formatDate } from './format';

const esc = (v) => `"${String(v).replace(/"/g, '""')}"`;

export function downloadCsv(filename, lines) {
  const blob = new Blob([lines.join('\n')], { type: 'text/csv' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url; a.download = filename; a.click();
  URL.revokeObjectURL(url);
}

export function pinsToCsvLines(rows) {
  const lines = ['Address,Status,Date Added,Note,Year Built,Latitude,Longitude'];
  rows.forEach((p) => {
    const date = new Date(p.ts).toLocaleDateString('en-US', { month: '2-digit', day: '2-digit', year: 'numeric' });
    lines.push([esc(p.addr || ''), esc(LABELS[p.status] || p.status), esc(date), esc(p.note || ''), esc(p.yearBuilt || ''), esc(p.lat.toFixed(6)), esc(p.lng.toFixed(6))].join(','));
  });
  return lines;
}

export function shiftsToCsvLines(shifts) {
  const lines = ['Date,Clock In,Clock Out,Duration,Hangers,Hangers Per Hour'];
  shifts.forEach((s) => {
    lines.push([esc(formatDate(s.clockIn)), esc(formatTime(s.clockIn)), esc(formatTime(s.clockOut)), esc(formatDuration(s.durationMs)), esc(s.hangers), esc(s.hangersPerHour)].join(','));
  });
  return lines;
}
