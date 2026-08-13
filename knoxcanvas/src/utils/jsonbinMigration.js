import { collection, doc, getDocs, setDoc, updateDoc, serverTimestamp } from 'firebase/firestore';
import { db } from '../firebase';
import { LEGACY_BIN_URL, LEGACY_ACCESS_KEY, LEGACY_OWNER_UID } from '../constants';

export async function migrateFromJSONBin(currentUser, currentUserProfile, companyId, showToast) {
  if (currentUser.uid !== LEGACY_OWNER_UID) return;
  if (currentUserProfile.migrated) return;

  try {
    const pinsSnap = await getDocs(collection(db, 'companies', companyId, 'pins'));
    if (!pinsSnap.empty) {
      await updateDoc(doc(db, 'users', currentUser.uid), { migrated: true });
      return;
    }

    const res = await fetch(LEGACY_BIN_URL, {
      headers: { 'X-Master-Key': LEGACY_ACCESS_KEY, 'X-Access-Key': LEGACY_ACCESS_KEY },
    });
    if (!res.ok) return;
    const data = await res.json();
    if (!data.record || !data.record.pins) return;

    const legacyPins = data.record.pins;
    const pinIds = Object.keys(legacyPins);
    if (!pinIds.length) return;

    const batch = [];
    pinIds.forEach((id) => {
      const p = legacyPins[id];
      batch.push(setDoc(doc(db, 'companies', companyId, 'pins', id), {
        ...p, id,
        migratedFrom: 'jsonbin',
        updatedBy: currentUser.uid,
        updatedAt: serverTimestamp(),
      }));
    });

    if (data.record.neighborhoodYears && data.record.neighborhoodYears.length) {
      batch.push(setDoc(doc(db, 'companies', companyId, 'settings', 'neighborhoodYears'), {
        zones: data.record.neighborhoodYears,
      }));
    }

    await Promise.all(batch);
    await updateDoc(doc(db, 'users', currentUser.uid), { migrated: true });
    showToast(`Migrated ${pinIds.length} pins from your previous data`);
  } catch (e) {
    console.warn('Migration failed:', e);
  }
}
