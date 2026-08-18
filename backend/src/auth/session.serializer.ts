import { Injectable } from '@nestjs/common';
import { PassportSerializer } from '@nestjs/passport';
import { AuthService, SessionUser } from './auth.service';

// Bridges `req.user` and what actually lives in the Redis session.
//
// Only the id crosses that boundary. Storing the whole user would make the
// session a frozen copy of the row at login time: nothing would ever re-read
// it, so a deleted or renamed account would keep authenticating until the TTL
// ran out. Storing the id and resolving it per request costs one indexed
// lookup and buys revocation — the tradeoff that separates sessions from
// self-contained tokens, and the reason this project uses them.
@Injectable()
export class SessionSerializer extends PassportSerializer {
  constructor(private readonly authService: AuthService) {
    super();
  }

  // Runs once, at login (via super.logIn in LocalAuthGuard).
  serializeUser(
    user: SessionUser,
    done: (err: Error | null, payload: unknown) => void,
  ) {
    done(null, user.id);
  }

  // Runs on EVERY authenticated request. Passing `false` tells passport the
  // session names nobody: it drops the user from the session and leaves
  // req.user unset, so AuthenticatedGuard's isAuthenticated() returns false and
  // the caller gets 403 — the stale session is cleaned up as a side effect.
  async deserializeUser(
    id: string,
    done: (err: Error | null, user: SessionUser | false) => void,
  ) {
    try {
      const user = await this.authService.findById(id);
      done(null, user ?? false);
    } catch (err) {
      // A DB outage must not read as "this session is invalid" — that would log
      // everyone out. Surface the error and let the request fail instead.
      done(err as Error, false);
    }
  }
}
