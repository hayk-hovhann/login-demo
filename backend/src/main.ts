import { NestFactory } from '@nestjs/core';
import session from 'express-session';
import { createClient } from 'redis';
import RedisStore from 'connect-redis';
import { AppModule } from './app.module';
import { ConfigService } from '@nestjs/config';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const config = app.get(ConfigService);

  // All routes are served under /api (so the ALB / nginx can route /api/* here)
  app.setGlobalPrefix('api');

  const redisClient = createClient({ url: config.getOrThrow<string>('REDIS_URL') });
  redisClient.on('error', (err) => console.error('Redis error:', err));
  await redisClient.connect();

  app.use(
    session({
      store: new RedisStore({ client: redisClient, prefix: 'login-demo:sess:' }),
      secret: config.getOrThrow<string>('SESSION_SECRET'),
      resave: false,
      saveUninitialized: false,
      cookie: {
        httpOnly: true,
        sameSite: 'lax',
        secure: config.get<boolean>('COOKIE_SECURE'),
        maxAge: 1000 * 60 * 60,
      },
    }),
  );

  const port = config.get<number>('PORT')!;
  await app.listen(config.get<number>('PORT')!, '0.0.0.0');
  console.log(`Backend listening on :${port}`);
}
void bootstrap();