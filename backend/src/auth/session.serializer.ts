import { Injectable } from '@nestjs/common';
import { PassportSerializer } from '@nestjs/passport';

@Injectable()
export class SessionSerializer extends PassportSerializer {
  serializeUser(
    user: { username: string },
    done: (err: Error | null, payload: unknown) => void,
  ) {
    done(null, user); // store the minimal identity in the session
  }
  deserializeUser(
    payload: { username: string },
    done: (err: Error | null, user: unknown) => void,
  ) {
    done(null, payload); // rebuild req.user from what we stored
  }
}
