import { useState } from 'react';
import { useApp } from '../context/AppContext';

export default function AuthScreen() {
  const { login, register, googleLogin, authErr, setAuthErr } = useApp();
  const [mode, setMode] = useState('login'); // 'login' | 'register'

  const [loginEmail, setLoginEmail] = useState('');
  const [loginPass, setLoginPass] = useState('');

  const [regName, setRegName] = useState('');
  const [regEmail, setRegEmail] = useState('');
  const [regPass, setRegPass] = useState('');
  const [regCompany, setRegCompany] = useState('');

  const switchTo = (m) => { setAuthErr(''); setMode(m); };

  return (
    <div id="auth-screen">
      <div id="auth-logo">Knox<span>Canvas</span></div>
      <div id="auth-tagline">Door-to-door sales tracking</div>
      <div id="auth-box">
        {mode === 'login' ? (
          <div id="login-form">
            <h2>Sign in</h2>
            <input className="auth-input" type="email" placeholder="Email" autoComplete="email"
              value={loginEmail} onChange={(e) => setLoginEmail(e.target.value)} />
            <input className="auth-input" type="password" placeholder="Password" autoComplete="current-password"
              value={loginPass} onChange={(e) => setLoginPass(e.target.value)} />
            <button className="auth-btn primary" onClick={() => login(loginEmail.trim(), loginPass)}>Sign In</button>
            <div className="auth-divider">or</div>
            <button className="auth-btn google" onClick={googleLogin}>
              <svg width="18" height="18" viewBox="0 0 24 24"><path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" /><path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" /><path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l3.66-2.84z" /><path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" /></svg>
              Continue with Google
            </button>
            <div id="auth-err">{authErr}</div>
            <div className="auth-switch">Don't have an account? <span onClick={() => switchTo('register')}>Create one</span></div>
          </div>
        ) : (
          <div id="register-form" style={{ display: 'block' }}>
            <h2>Create account</h2>
            <input className="auth-input" type="text" placeholder="Your name" autoComplete="name"
              value={regName} onChange={(e) => setRegName(e.target.value)} />
            <input className="auth-input" type="email" placeholder="Email" autoComplete="email"
              value={regEmail} onChange={(e) => setRegEmail(e.target.value)} />
            <input className="auth-input" type="password" placeholder="Password (min 6 chars)" autoComplete="new-password"
              value={regPass} onChange={(e) => setRegPass(e.target.value)} />
            <input className="auth-input" type="text" placeholder="Company name"
              value={regCompany} onChange={(e) => setRegCompany(e.target.value)} />
            <button className="auth-btn primary" onClick={() => register(regName.trim(), regEmail.trim(), regPass, regCompany.trim())}>Create Account</button>
            <div id="auth-err">{authErr}</div>
            <div className="auth-switch">Already have an account? <span onClick={() => switchTo('login')}>Sign in</span></div>
          </div>
        )}
      </div>
    </div>
  );
}
