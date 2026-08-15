import {
  Injectable,
  ConflictException,
  UnauthorizedException,
} from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { Prisma } from '../generated/prisma/client';
import { PrismaService } from '../prisma/prisma.service';

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

  async validateUser(
    username: string,
    password: string,
  ): Promise<{ username: string }> {
    const user = await this.prisma.user.findUnique({ where: { username } });
    if (!user || !(await bcrypt.compare(password, user.passwordHash)))
      throw new UnauthorizedException('Invalid username or password');
    return { username: user.username };
  }
}
