import {
  Controller,
  Get,
  Inject,
  ServiceUnavailableException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { REDIS_CLIENT, type RedisClient } from '../redis/redis.module';

// A probe must answer, not hang: pg has no default connect timeout, and a Redis
// command issued while disconnected sits in the offline queue. Cap each check.
const CHECK_TIMEOUT_MS = 2000;

function withTimeout<T>(work: Promise<T>): Promise<T> {
  return Promise.race([
    work,
    new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error('timeout')), CHECK_TIMEOUT_MS),
    ),
  ]);
}

// Readiness: can THIS instance serve a login right now? Unlike /health, it
// touches every dependency a request needs. Deliberately NOT the ALB health
// check — on ECS any failing check replaces the task, and replacing tasks
// during a DB outage is a restart storm that fixes nothing. Callers today are
// humans and CD smoke tests; on EKS it becomes the pod's readinessProbe.
@Controller('ready')
export class ReadyController {
  constructor(
    private readonly prisma: PrismaService,
    @Inject(REDIS_CLIENT) private readonly redis: RedisClient,
  ) {}

  @Get()
  async check() {
    const [postgres, redis] = await Promise.all([
      probe(() => this.prisma.$queryRaw`SELECT 1`),
      probe(() => this.pingRedis()),
    ]);
    const checks = { postgres, redis };

    if (postgres === 'down' || redis === 'down') {
      throw new ServiceUnavailableException({ status: 'unavailable', checks });
    }
    return { status: 'ok', checks };
  }

  private async pingRedis() {
    // isReady short-circuits the offline queue: no socket, no PING.
    if (!this.redis.isReady) throw new Error('not ready');
    return this.redis.ping();
  }
}

function probe(check: () => Promise<unknown>): Promise<'up' | 'down'> {
  return withTimeout(check()).then(
    () => 'up',
    () => 'down',
  );
}
