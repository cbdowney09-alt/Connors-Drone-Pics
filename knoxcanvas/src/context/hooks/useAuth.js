import { useEffect, useState, useCallback } from 'react';
import {
  signInWithEmailAndPassword, createUserWithEmailAndPassword, signInWithPopup,
  signInWithRedirect, getRedirectResult, signOut, onAuthStateChanged,
} from 'firebase/auth';
import { doc, setDoc, getDoc, addDoc, collection, deleteDoc, serverTimestamp } from 'firebase/firestore';
import { auth, db, googleProvider } from '../../firebase';

function friendlyAuthError(code) {
  if (code === 'auth/user-not-found' || code === 'auth/wrong-password' || code === 'auth/invalid-credential') return 'Incorrect email or password.';
  if (code === 'auth/email-already-in-use') return 'Email already in use.';
  if (code === 'auth/invalid-email') return 'Invalid email address.';
  if (code === 'auth/weak-password') return 'Password too weak.';
  if (code === 'auth/popup-closed-by-user') return '';
  return 'Something went wrong. Try again.';
}

export function useAuth() {
  const [currentUser, setCurrentUser] = useState(null);
  const [currentUserProfile, setCurrentUserProfile] = useState(null);
  const [companyId, setCompanyId] = useState(null);
  const [authReady, setAuthReady] = useState(false);
  const [authErr, setAuthErr] = useState('');
  const [setupErr, setSetupErr] = useState('');

  const loadUserProfile = useCallback(async (user) => {
    const userDoc = await getDoc(doc(db, 'users', user.uid));
    if (userDoc.exists()) {
      const profile = userDoc.data();
      setCurrentUserProfile(profile);
      setCompanyId(profile.companyId);
    } else {
      setCurrentUserProfile(null);
      setCompanyId(null);
    }
  }, []);

  useEffect(() => {
    getRedirectResult(auth).catch((e) => {
      if (e && e.code) {
        const msg = e.code === 'auth/popup-closed-by-user' ? '' : 'Google sign-in failed. Try again.';
        if (msg) setAuthErr(msg);
      }
    });
  }, []);

  useEffect(() => {
    const unsub = onAuthStateChanged(auth, async (user) => {
      if (user) {
        setCurrentUser(user);
        await loadUserProfile(user);
      } else {
        setCurrentUser(null);
        setCurrentUserProfile(null);
        setCompanyId(null);
      }
      setAuthReady(true);
    });
    return unsub;
  }, [loadUserProfile]);

  const login = useCallback(async (email, pass) => {
    setAuthErr('');
    try {
      await signInWithEmailAndPassword(auth, email, pass);
    } catch (e) {
      setAuthErr(friendlyAuthError(e.code));
    }
  }, []);

  const register = useCallback(async (name, email, pass, companyName) => {
    setAuthErr('');
    if (!name || !email || !pass || !companyName) { setAuthErr('All fields required'); return; }
    if (pass.length < 6) { setAuthErr('Password must be at least 6 characters'); return; }
    try {
      const cred = await createUserWithEmailAndPassword(auth, email, pass);
      const companyRef = await addDoc(collection(db, 'companies'), {
        name: companyName, ownerId: cred.user.uid, createdAt: serverTimestamp(),
      });
      await setDoc(doc(db, 'users', cred.user.uid), {
        name, email, role: 'owner', companyId: companyRef.id, companyName, createdAt: serverTimestamp(),
      });
    } catch (e) {
      setAuthErr(friendlyAuthError(e.code));
    }
  }, []);

  const googleLogin = useCallback(async () => {
    setAuthErr('');
    try {
      await signInWithPopup(auth, googleProvider).catch(async (err) => {
        if (err.code === 'auth/popup-blocked' || err.code === 'auth/cancelled-popup-request' || err.message?.includes('Cross-Origin')) {
          await signInWithRedirect(auth, googleProvider);
          return null;
        }
        throw err;
      });
    } catch (e) {
      if (e && e.code !== 'auth/popup-closed-by-user') {
        setAuthErr(friendlyAuthError(e.code));
      }
    }
  }, []);

  const logout = useCallback(async () => {
    await signOut(auth);
  }, []);

  const setupCreateCompany = useCallback(async (name, companyName) => {
    setSetupErr('');
    if (!name || !companyName) { setSetupErr('Fill in all fields'); return; }
    try {
      const companyRef = await addDoc(collection(db, 'companies'), {
        name: companyName, ownerId: currentUser.uid, createdAt: serverTimestamp(),
      });
      await setDoc(doc(db, 'users', currentUser.uid), {
        name, email: currentUser.email, role: 'owner', companyId: companyRef.id, companyName, createdAt: serverTimestamp(),
      });
      await loadUserProfile(currentUser);
    } catch (e) {
      setSetupErr(e.message);
    }
  }, [currentUser, loadUserProfile]);

  const setupJoinCompany = useCallback(async (name, code) => {
    setSetupErr('');
    if (!name || !code) { setSetupErr('Fill in all fields'); return; }
    try {
      const inviteDoc = await getDoc(doc(db, 'invites', code));
      if (!inviteDoc.exists()) { setSetupErr('Invalid invite code'); return; }
      const invite = inviteDoc.data();
      await setDoc(doc(db, 'users', currentUser.uid), {
        name, email: currentUser.email, role: 'employee', companyId: invite.companyId, companyName: invite.companyName, createdAt: serverTimestamp(),
      });
      await deleteDoc(doc(db, 'invites', code));
      await loadUserProfile(currentUser);
    } catch (e) {
      setSetupErr(e.message);
    }
  }, [currentUser, loadUserProfile]);

  return {
    currentUser, currentUserProfile, companyId, authReady,
    authErr, setAuthErr, setupErr, setSetupErr,
    login, register, googleLogin, logout, setupCreateCompany, setupJoinCompany,
  };
}
