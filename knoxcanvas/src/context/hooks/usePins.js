import { useCallback, useEffect, useState } from 'react';
import { collection, doc, setDoc, deleteDoc, onSnapshot, serverTimestamp } from 'firebase/firestore';
import { db } from '../../firebase';

export function usePins(companyId, currentUser) {
  const [pins, setPins] = useState({});

  useEffect(() => {
    if (!companyId) { setPins({}); return; }
    const pinsRef = collection(db, 'companies', companyId, 'pins');
    const unsub = onSnapshot(pinsRef, (snap) => {
      const next = {};
      snap.forEach((d) => { next[d.id] = { ...d.data(), id: d.id }; });
      setPins(next);
    });
    return unsub;
  }, [companyId]);

  const savePin = useCallback(async (id, pinData) => {
    if (!companyId || !currentUser) return;
    await setDoc(doc(db, 'companies', companyId, 'pins', id), {
      ...pinData,
      updatedBy: currentUser.uid,
      updatedAt: serverTimestamp(),
    }, { merge: true });
  }, [companyId, currentUser]);

  const deletePin = useCallback(async (id) => {
    if (!companyId) return;
    await deleteDoc(doc(db, 'companies', companyId, 'pins', id));
  }, [companyId]);

  return { pins, savePin, deletePin };
}
