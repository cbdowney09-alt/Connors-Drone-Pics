import { SHEETS_URL } from '../constants';
import { formatDuration, formatTime, formatDate } from './format';

export async function syncToSheets(action, pin, id) {
  if (action === 'upsert' && pin.status !== 'hanger') return;
  try {
    await fetch(SHEETS_URL, {
      method: 'POST', mode: 'no-cors', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(action === 'upsert'
        ? { action: 'upsert', pin: { ...pin, id: id || pin.id, yearBuilt: pin.yearBuilt || '' } }
        : { action: 'delete', id }),
    });
  } catch (e) {}
}

export async function syncShiftToSheets(shift) {
  try {
    await fetch(SHEETS_URL, {
      method: 'POST', mode: 'no-cors', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'shift', shift: { date: formatDate(shift.clockIn), clockIn: formatTime(shift.clockIn), clockOut: formatTime(shift.clockOut), duration: formatDuration(shift.durationMs), hangers: shift.hangers, hangersPerHour: shift.hangersPerHour } }),
    });
  } catch (e) {}
}
