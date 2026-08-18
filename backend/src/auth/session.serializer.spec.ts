import { AuthService } from './auth.service';
import { SessionSerializer } from './session.serializer';

describe('SessionSerializer', () => {
  const user = { id: 'user-1', username: 'demo' };
  let authService: { findById: jest.Mock };
  let serializer: SessionSerializer;

  beforeEach(() => {
    authService = { findById: jest.fn() };
    serializer = new SessionSerializer(authService as unknown as AuthService);
  });

  it('writes only the id into the session, never the user object', () => {
    const done = jest.fn();

    serializer.serializeUser(user, done);

    expect(done).toHaveBeenCalledWith(null, 'user-1');
  });

  it('resolves the id back to the live user on each request', async () => {
    authService.findById.mockResolvedValue(user);
    const done = jest.fn();

    await serializer.deserializeUser('user-1', done);

    expect(authService.findById).toHaveBeenCalledWith('user-1');
    expect(done).toHaveBeenCalledWith(null, user);
  });

  // The whole reason the id is stored instead of the user: a session has to stop
  // authenticating when the row disappears, not when its TTL happens to expire.
  it('refuses a session whose user no longer exists', async () => {
    authService.findById.mockResolvedValue(null);
    const done = jest.fn();

    await serializer.deserializeUser('deleted-user', done);

    expect(done).toHaveBeenCalledWith(null, false);
  });

  // A database outage must not silently log everyone out — that would look
  // identical to mass session revocation.
  it('reports a lookup failure as an error rather than a missing user', async () => {
    const boom = new Error('connection terminated');
    authService.findById.mockRejectedValue(boom);
    const done = jest.fn();

    await serializer.deserializeUser('user-1', done);

    expect(done).toHaveBeenCalledWith(boom, false);
  });
});
