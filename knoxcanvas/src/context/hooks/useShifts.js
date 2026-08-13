import { useCallback, useEffect, useRef, useState } from 'react';
import { addDoc, collection, getDocs, query, where } from 'firebase/firestore';
import { db } from '../../firebase';
import { syncShiftToSheets } from '../../utils/sheetsSync';

export function useShifts(companyId, currentUser, currentUserProfile, hangerCount) {
  const [shifts, setShifts] = useState([]);
  const [clockedIn, setClockedIn] = useState(false);
  const [clockInTime, setClockInTime] = useState(null);
  const [now, setNow] = useState(() => Date.now());
  const shiftHangersAtClockIn = useRef(0);
  const timerRef = useRef(null);

  const loadShifts = useCallback(async () => {
    if (!companyId || !currentUser) return;
    const q = query(collection(db, 'companies', companyId, 'shifts'), where('userId', '==', currentUser.uid));
    const snap = await getDocs(q);
    const list = [];
    snap.forEach((d) => list.push({ ...d.data(), id: d.id }));
    list.sort((a, b) => b.clockIn - a.clockIn);
    setShifts(list);
  }, [companyId, currentUser]);

  useEffect(() => { loadShifts(); }, [loadShifts]);

  useEffect(() => {
    if (!clockedIn) { clearInterval(timerRef.current); return; }
    timerRef.current = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timerRef.current);
  }, [clockedIn]);

  const clockIn = useCallback(() => {
    setClockedIn(true);
    const t = Date.now();
    setClockInTime(t);
    setNow(t);
    shiftHangersAtClockIn.current = hangerCount();
    localStorage.setItem('knoxClockIn', JSON.stringify({ time: t, hangersAtStart: shiftHangersAtClockIn.current }));
  }, [hangerCount]);

  const clockOut = useCallback(async () => {
    if (!clockedIn || !clockInTime) return null;
    const clockOutTime = Date.now();
    const durationMs = clockOutTime - clockInTime;
    const hangersThisShift = Math.max(0, hangerCount() - shiftHangersAtClockIn.current);
    const hoursWorked = durationMs / 3600000;
    const hangersPerHour = hoursWorked > 0 ? parseFloat((hangersThisShift / hoursWorked).toFixed(1)) : 0;
    const shift = { clockIn: clockInTime, clockOut: clockOutTime, durationMs, hangers: hangersThisShift, hangersPerHour };
    setShifts((prev) => [shift, ...prev]);
    localStorage.removeItem('knoxClockIn');
    setClockedIn(false);
    setClockInTime(null);
    shiftHangersAtClockIn.current = 0;

    const ref = await addDoc(collection(db, 'companies', companyId, 'shifts'), {
      ...shift, userId: currentUser.uid, userName: currentUserProfile.name,
    });
    setShifts((prev) => prev.map((s) => (s === shift ? { ...s, id: ref.id } : s)));
    syncShiftToSheets(shift);
    return shift;
  }, [clockedIn, clockInTime, hangerCount, companyId, currentUser, currentUserProfile]);

  const elapsedMs = clockedIn && clockInTime ? now - clockInTime : 0;
  const liveHangerCount = clockedIn ? Math.max(0, hangerCount() - shiftHangersAtClockIn.current) : 0;

  return { shifts, clockedIn, clockInTime, elapsedMs, liveHangerCount, clockIn, clockOut };
}
