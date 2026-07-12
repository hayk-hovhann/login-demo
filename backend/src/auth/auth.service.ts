import { Injectable, UnauthorizedException } from '@nestjs/common';

@Injectable()
export class AuthService {
  // In-memory user store (no DB yet). Seeded with one demo user.
  // CAVEAT: memory-only — resets on restart, and is NOT shared across replicas.
  // A real store (Postgres / Redis) is the next lesson this sets up.
  private readonly users = new Map<string, string>([['demo', 'password123']]);

  validate(username: string, password: string): { username: string } {
    const stored = this.users.get(username);
    if (!stored || stored !== password) {
      throw new UnauthorizedException('Invalid username or password');
    }
    return { username };
  }
}
