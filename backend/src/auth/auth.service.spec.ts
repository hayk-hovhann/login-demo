import { UnauthorizedException } from '@nestjs/common';
import * as bcrypt from 'bcryptjs';
import { AuthService } from './auth.service';
import { PrismaService } from '../prisma/prisma.service';

describe('AuthService', () => {
  let prisma: { user: { findUnique: jest.Mock } };
  let service: AuthService;
  let passwordHash: string;

  // Hashed once: bcrypt at cost 10 is deliberately slow, and every case reuses it.
  beforeAll(async () => {
    passwordHash = await bcrypt.hash('password123', 10);
  });

  beforeEach(() => {
    prisma = { user: { findUnique: jest.fn() } };
    service = new AuthService(prisma as unknown as PrismaService);
  });

  describe('validateUser', () => {
    it('returns the id, not just the username', async () => {
      prisma.user.findUnique.mockResolvedValue({
        id: 'user-1',
        username: 'demo',
        passwordHash,
      });

      await expect(
        service.validateUser('demo', 'password123'),
      ).resolves.toEqual({ id: 'user-1', username: 'demo' });
    });

    it('never returns the password hash', async () => {
      prisma.user.findUnique.mockResolvedValue({
        id: 'user-1',
        username: 'demo',
        passwordHash,
      });

      const result = await service.validateUser('demo', 'password123');

      expect(result).not.toHaveProperty('passwordHash');
    });

    it('rejects a wrong password', async () => {
      prisma.user.findUnique.mockResolvedValue({
        id: 'user-1',
        username: 'demo',
        passwordHash,
      });

      await expect(
        service.validateUser('demo', 'wrong-password'),
      ).rejects.toThrow(UnauthorizedException);
    });

    // Same error for both branches, so the response can't be used to discover
    // which usernames exist.
    it('rejects an unknown username with the same message as a wrong password', async () => {
      prisma.user.findUnique.mockResolvedValue(null);

      await expect(
        service.validateUser('nobody', 'password123'),
      ).rejects.toThrow('Invalid username or password');
    });
  });

  describe('findById', () => {
    it('selects only the session fields, keeping the hash out of req.user', async () => {
      prisma.user.findUnique.mockResolvedValue({
        id: 'user-1',
        username: 'demo',
      });

      await service.findById('user-1');

      expect(prisma.user.findUnique).toHaveBeenCalledWith({
        where: { id: 'user-1' },
        select: { id: true, username: true },
      });
    });

    it('returns null for a user that has been deleted', async () => {
      prisma.user.findUnique.mockResolvedValue(null);

      await expect(service.findById('deleted-user')).resolves.toBeNull();
    });
  });
});
