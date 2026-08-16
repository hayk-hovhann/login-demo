import { useEffect, useState } from 'react';
import { login, logout, me, register, type User } from './api';

type Mode = 'login' | 'register';

export function App() {
  const [user, setUser] = useState<User | null>(null);
  const [mode, setMode] = useState<Mode>('login');
  const [username, setUsername] = useState('demo');
  const [password, setPassword] = useState('password123');
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);

  // On load, ask the backend "am I already logged in?" (reads the cookie)
  useEffect(() => {
    me()
      .then(setUser)
      .finally(() => setLoading(false));
  }, []);

  function switchMode(next: Mode) {
    setMode(next);
    setError(null);
    setNotice(null);
  }

  async function handleSubmit() {
    setError(null);
    setNotice(null);
    setBusy(true);
    try {
      // register() only creates the row, so log in afterwards to get the session cookie
      if (mode === 'register') await register(username, password);
      setUser(await login(username, password));
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setBusy(false);
    }
  }

  async function handleLogout() {
    await logout();
    setUser(null);
    setNotice('Logged out — the session was destroyed server-side.');
  }

  if (loading) return <p style={S.wrap}>Loading…</p>;

  return (
    <div style={S.wrap}>
      <h1>Login demo</h1>
      <p style={S.badge}>🚀 Stage 4 complete — auto-deployed via CI/CD · v3</p>
      {user ? (
        <>
          <p>
            ✅ Logged in as <strong>{user.username}</strong>
          </p>
          <button onClick={handleLogout}>Log out</button>
        </>
      ) : (
        <>
          <div style={S.tabs}>
            <button
              onClick={() => switchMode('login')}
              style={mode === 'login' ? S.tabActive : S.tab}
            >
              Log in
            </button>
            <button
              onClick={() => switchMode('register')}
              style={mode === 'register' ? S.tabActive : S.tab}
            >
              Register
            </button>
          </div>
          <div style={{ display: 'grid', gap: 8 }}>
            <input
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              placeholder="username"
            />
            <input
              value={password}
              type="password"
              onChange={(e) => setPassword(e.target.value)}
              placeholder="password"
            />
            <button onClick={handleSubmit} disabled={busy}>
              {busy ? 'Working…' : mode === 'login' ? 'Log in' : 'Create account'}
            </button>
          </div>
          {error && <p style={{ color: 'crimson' }}>{error}</p>}
          {notice && <p style={{ color: '#1a4b8c' }}>{notice}</p>}
          <p style={{ color: '#888', fontSize: 12 }}>
            {mode === 'login'
              ? 'Try demo / password123'
              : 'Username 3–32 chars, password at least 8'}
          </p>
        </>
      )}
    </div>
  );
}

const S = {
  wrap: {
    fontFamily: 'system-ui, sans-serif',
    maxWidth: 320,
    margin: '4rem auto',
  } as React.CSSProperties,
  badge: {
    background: '#eef6ff',
    border: '1px solid #cfe4ff',
    borderRadius: 6,
    padding: '6px 10px',
    fontSize: 13,
    color: '#1a4b8c',
  } as React.CSSProperties,
  tabs: {
    display: 'flex',
    gap: 4,
    marginBottom: 12,
  } as React.CSSProperties,
  tab: {
    flex: 1,
    padding: '6px 0',
    background: 'transparent',
    border: '1px solid #cfe4ff',
    borderRadius: 6,
    color: '#1a4b8c',
    cursor: 'pointer',
  } as React.CSSProperties,
  tabActive: {
    flex: 1,
    padding: '6px 0',
    background: '#1a4b8c',
    border: '1px solid #1a4b8c',
    borderRadius: 6,
    color: '#fff',
    cursor: 'pointer',
  } as React.CSSProperties,
};
