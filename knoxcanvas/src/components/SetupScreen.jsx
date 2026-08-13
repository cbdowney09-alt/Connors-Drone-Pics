import { useState } from 'react';
import { useApp } from '../context/AppContext';

export default function SetupScreen() {
  const { setupCreateCompany, setupJoinCompany, setupErr } = useApp();
  const [tab, setTab] = useState('create'); // 'create' | 'join'
  const [name, setName] = useState('');
  const [companyName, setCompanyName] = useState('');
  const [inviteCode, setInviteCode] = useState('');

  return (
    <div id="setup-screen" style={{ display: 'flex' }}>
      <div id="auth-logo" style={{ marginBottom: 4 }}>Knox<span style={{ color: 'var(--accent)' }}>Canvas</span></div>
      <div style={{ fontSize: 13, color: 'var(--text2)', marginBottom: 24 }}>One more step</div>
      <div id="setup-box">
        <h2>Set up your account</h2>
        <input className="auth-input" type="text" placeholder="Your name" value={name} onChange={(e) => setName(e.target.value)} />
        <div id="setup-tabs">
          <div className={'setup-tab' + (tab === 'create' ? ' active' : '')} onClick={() => setTab('create')}>Create Company</div>
          <div className={'setup-tab' + (tab === 'join' ? ' active' : '')} onClick={() => setTab('join')}>Join with Code</div>
        </div>
        {tab === 'create' ? (
          <div id="setup-create-section" style={{ display: 'flex' }}>
            <input className="auth-input" type="text" placeholder="Company name" value={companyName} onChange={(e) => setCompanyName(e.target.value)} />
            <button className="auth-btn primary" onClick={() => setupCreateCompany(name.trim(), companyName.trim())}>Create Company</button>
          </div>
        ) : (
          <div id="setup-join-section" style={{ display: 'flex' }}>
            <input className="auth-input" type="text" placeholder="Invite code (e.g. AB12CD34)"
              style={{ textTransform: 'uppercase', letterSpacing: 2 }}
              value={inviteCode} onChange={(e) => setInviteCode(e.target.value.toUpperCase())} />
            <button className="auth-btn primary" onClick={() => setupJoinCompany(name.trim(), inviteCode.trim())}>Join Company</button>
          </div>
        )}
        <div id="setup-err">{setupErr}</div>
      </div>
    </div>
  );
}
