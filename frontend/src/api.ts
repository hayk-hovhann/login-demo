export interface User {
  username: string;
}

// credentials: 'include' -> browser sends & stores the session cookie
const base: RequestInit = {
  credentials: 'include',
  headers: { 'Content-Type': 'application/json' },
};

// Nest's ValidationPipe returns `message` as a string[]; everything else as a string.
async function errorMessage(res: Response, fallback: string): Promise<string> {
  const body = await res.json().catch(() => ({}));
  if (Array.isArray(body.message)) return body.message.join(', ');
  return typeof body.message === 'string' ? body.message : fallback;
}

export async function login(username: string, password: string): Promise<User> {
  const res = await fetch('/api/auth/login', {
    ...base,
    method: 'POST',
    body: JSON.stringify({ username, password }),
  });
  if (!res.ok) throw new Error(await errorMessage(res, 'Login failed'));
  const data = await res.json();
  return data.user as User;
}

// Creates the user but does NOT start a session — the caller logs in afterwards.
export async function register(username: string, password: string): Promise<User> {
  const res = await fetch('/api/auth/register', {
    ...base,
    method: 'POST',
    body: JSON.stringify({ username, password }),
  });
  if (!res.ok) throw new Error(await errorMessage(res, 'Registration failed'));
  return (await res.json()) as User;
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
