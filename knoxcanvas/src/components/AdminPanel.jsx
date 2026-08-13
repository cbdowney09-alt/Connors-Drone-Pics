import { useEffect, useState } from 'react';
import { collection, doc, getDoc, getDocs, query, serverTimestamp, setDoc, where } from 'firebase/firestore';
import { db } from '../firebase';
import { useApp } from '../context/AppContext';

export default function AdminPanel() {
  const { currentUser, currentUserProfile, companyId, showToast, mapUi } = useApp();
  const open = mapUi.adminOpen;
  const isOwner = currentUserProfile?.role === 'owner';

  const [companyName, setCompanyName] = useState('Your Company');
  const [employees, setEmployees] = useState([]);
  const [inviteCode, setInviteCode] = useState('');
  const [inviteBoxVisible, setInviteBoxVisible] = useState(false);

  const load = async () => {
    if (!isOwner || !companyId) return;
    const companyDoc = await getDoc(doc(db, 'companies', companyId));
    setCompanyName(companyDoc.data()?.name || 'Your Company');

    const empSnap = await getDocs(query(collection(db, 'users'), where('companyId', '==', companyId)));
    const list = []; empSnap.forEach((d) => list.push(d.data()));
    setEmployees(list);
  };

  useEffect(() => { if (open) load(); }, [open]); // eslint-disable-line react-hooks/exhaustive-deps

  const genInvite = async () => {
    if (!isOwner) return;
    const code = Math.random().toString(36).substring(2, 10).toUpperCase();
    await setDoc(doc(db, 'invites', code), {
      companyId, companyName: currentUserProfile.companyName,
      createdBy: currentUser.uid, createdAt: serverTimestamp(),
    });
    setInviteCode(code);
    setInviteBoxVisible(true);
    showToast('Invite code generated — share it with your employee');
  };

  const copyInvite = () => {
    navigator.clipboard.writeText(inviteCode).then(() => showToast('Copied!'));
  };

  if (!open) return null;

  return (
    <div id="admin-panel" style={{ display: 'flex' }}>
      <div id="admin-box">
        <div id="admin-header">
          <h2>Team Admin</h2>
          <button id="admin-close" onClick={() => mapUi.setAdminOpen(false)}>Close</button>
        </div>
        <div id="admin-company-name">{companyName}</div>
        <div className="admin-section-title">Invite Employee</div>
        <button id="gen-invite-btn" onClick={genInvite}>Generate Invite Code</button>
        {inviteBoxVisible && (
          <div id="invite-code-box" style={{ display: 'block' }}>
            <div style={{ fontSize: 12, color: 'var(--text2)', marginBottom: 8 }}>Share this code with your employee</div>
            <div id="invite-code-display">{inviteCode}</div>
            <button id="copy-invite-btn" onClick={copyInvite}>Copy Code</button>
          </div>
        )}
        <div className="admin-section-title">Team Members</div>
        <div id="admin-emp-list">
          {employees.map((u, i) => (
            <div className="admin-emp-row" key={i}>
              <div><div className="emp-name">{u.name}</div><div className="emp-email">{u.email} · <span style={{ color: 'var(--c-hanger)' }}>{u.role}</span></div></div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
