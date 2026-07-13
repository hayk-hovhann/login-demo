import { useEffect, useState } from 'react';
import { login, logout, me, type User } from './api';

export function App() {
  const [user, setUser] = useState<User | null>(null);
  const [username, setUsername] = useState('demo');
  const [password, setPassword] = useState('password123');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);

  // On load, ask the backend "am I already logged in?" (reads the cookie)
  useEffect(() => {
    me()
      .then(setUser)
      .finally(() => setLoading(false));
  }, []);

  async function handleLogin() {
    setError(null);
    try {
      setUser(await login(username, password));
    } catch (e) {
      setError((e as Error).message);
    }
  }

  async function handleLogout() {
    await logout();
    setUser(null);
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
            <button onClick={handleLogin}>Log in</button>
          </div>
          {error && <p style={{ color: 'crimson' }}>{error}</p>}
          <p style={{ color: '#888', fontSize: 12 }}>Try demo / password123</p>
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
};
