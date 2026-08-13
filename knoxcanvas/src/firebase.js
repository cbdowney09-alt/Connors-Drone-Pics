import { initializeApp } from 'firebase/app';
import { getAuth, GoogleAuthProvider } from 'firebase/auth';
import { initializeFirestore, persistentLocalCache, persistentSingleTabManager } from 'firebase/firestore';

const firebaseConfig = {
  apiKey: 'AIzaSyCicUN1axUGBgFuznmQjX-9D6yf3R2HU88',
  authDomain: 'knoxcanvas-a7bfe.firebaseapp.com',
  projectId: 'knoxcanvas-a7bfe',
  storageBucket: 'knoxcanvas-a7bfe.firebasestorage.app',
  messagingSenderId: '526600169975',
  appId: '1:526600169975:web:5d8d4896717377029026f2',
};

export const app = initializeApp(firebaseConfig);
export const auth = getAuth(app);
// Offline persistence: pins/zones/shifts stay usable while walking a
// neighborhood with no signal, and queued writes sync once back online.
export const db = initializeFirestore(app, {
  localCache: persistentLocalCache({ tabManager: persistentSingleTabManager() }),
});
export const googleProvider = new GoogleAuthProvider();
googleProvider.setCustomParameters({ prompt: 'select_account' });
