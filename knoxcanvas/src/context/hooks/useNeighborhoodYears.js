import { useCallback, useEffect, useState } from 'react';
import { doc, getDoc, setDoc } from 'firebase/firestore';
import { db } from '../../firebase';

export function useNeighborhoodYears(companyId) {
  const [neighborhoodYears, setNeighborhoodYears] = useState([]);

  useEffect(() => {
    if (!companyId) { setNeighborhoodYears([]); return; }
    let cancelled = false;
    (async () => {
      const d = await getDoc(doc(db, 'companies', companyId, 'settings', 'neighborhoodYears'));
      if (!cancelled && d.exists()) setNeighborhoodYears(d.data().zones || []);
    })();
    return () => { cancelled = true; };
  }, [companyId]);

  const saveNeighborhoodYears = useCallback(async (zones) => {
    if (!companyId) return;
    await setDoc(doc(db, 'companies', companyId, 'settings', 'neighborhoodYears'), { zones });
  }, [companyId]);

  return { neighborhoodYears, setNeighborhoodYears, saveNeighborhoodYears };
}
