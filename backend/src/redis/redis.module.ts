import { Global, Inject, Module, OnApplicationShutdown } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createClient, type RedisClientType } from 'redis';

// Injection token: a Redis client is a plain object, not a class, so there is
// no type Nest can resolve it by. Consumers ask for it with @Inject(REDIS_CLIENT).
export const REDIS_CLIENT = Symbol('REDIS_CLIENT');
export type RedisClient = RedisClientType;

@Global()
@Module({
  providers: [
    {
      provide: REDIS_CLIENT,
      inject: [ConfigService],
      // Async factory: Nest awaits connect() before the app finishes creating,
      // so an unreachable Redis still fails startup (NestFactory.create rejects
      // -> bootstrap().catch -> exit 1), exactly as before the move.
      useFactory: async (config: ConfigService): Promise<RedisClient> => {
        // Two phases need opposite retry policies, and this flag splits them.
        let connectedOnce = false;
        const client = createClient({
          url: config.getOrThrow<string>('REDIS_URL'),
          socket: {
            connectTimeout: 5000,
            // Startup: return an Error to STOP reconnecting -> connect() rejects
            // instead of hanging. Without this, the default strategy retries
            // forever and the await never settles.
            // Runtime: never give up. A client that stops retrying stays dead
            // after Redis comes back — /ready reads down and every login fails
            // until the task is replaced. Keep retrying, capped at 2s apart.
            reconnectStrategy: (retries) =>
              !connectedOnce && retries > 5
                ? new Error('Redis unreachable')
                : Math.min(retries * 200, 2000),
          },
        });
        client.on('error', (err) => console.error('Redis error:', err));
        await client.connect();
        connectedOnce = true;
        return client;
      },
    },
  ],
  exports: [REDIS_CLIENT],
})
export class RedisModule implements OnApplicationShutdown {
  // The factory above returns a plain object, which cannot carry lifecycle
  // hooks — so the module class owns the client's shutdown instead.
  constructor(@Inject(REDIS_CLIENT) private readonly client: RedisClient) {}

  // After the HTTP server has drained, for the same reason as PrismaService.
  // close() lets queued commands finish; destroy() would drop them.
  async onApplicationShutdown() {
    await this.client.close();
    console.log('Redis connection closed');
  }
}
