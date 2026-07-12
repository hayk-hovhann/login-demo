export interface User {
  username: string;
}

// credentials: 'include' -> browser sends & stores the session cookie
const base: RequestInit = {
  credentials: 'include',
  headers: { 'Content-Type': 'application/json' },
};

export async function login(username: string, password: string): Promise<User> {
  const res = await fetch('/api/auth/login', {
    ...base,
    method: 'POST',
    body: JSON.stringify({ username, password }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.message ?? 'Login failed');
  }
  const data = await res.json();
  return data.user as User;
}

export async function me(): Promise<User | null> {
  const res = await fetch('/api/auth/me', base);
  if (!res.ok) return null;
  const data = await res.json();
  return (data.user as User) ?? null;
}

export async function logout(): Promise<void> {
  await fetch('/api/auth/logout', { ...base, method: 'POST' });
}
