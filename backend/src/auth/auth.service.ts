import {
  Injectable,
  ConflictException,
  UnauthorizedException,
} from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { Prisma } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';

// What `req.user` holds, and the shape the session resolves back to. The id is
// the durable handle; the username is display only and may change.
export type SessionUser = { id: string; username: string };

@Injectable()
export class AuthService {
  constructor(private readonly prisma: PrismaService) {}

  async register(username: string, password: string) {
    const passwordHash = await bcrypt.hash(password, 10);
    try {
      return await this.prisma.user.create({
        data: { username, passwordHash },
        select: { id: true, username: true, createdAt: true },
      });
    } catch (e) {
      if (
        e instanceof Prisma.PrismaClientKnownRequestError &&
        e.code === 'P2002'
      )
        throw new ConflictException('username already taken');
      throw e;
    }
  }

  // One error for both "no such user" and "wrong password", on purpose: a
  // distinct message would let an anonymous caller enumerate usernames.
  async validateUser(username: string, password: string): Promise<SessionUser> {
    const user = await this.prisma.user.findUnique({ where: { username } });
    if (!user || !(await bcrypt.compare(password, user.passwordHash)))
      throw new UnauthorizedException('Invalid username or password');
    return { id: user.id, username: user.username };
  }

  // Resolves the id held in the session back to the live row, on every
  // authenticated request. Returning null is what makes a session revocable:
  // delete the user and their session stops authenticating on the next request
  // instead of surviving until the Redis TTL expires. `select` keeps the
  // password hash out of the object that becomes `req.user`.
  async findById(id: string): Promise<SessionUser | null> {
    return this.prisma.user.findUnique({
      where: { id },
      select: { id: true, username: true },
    });
  }
}
