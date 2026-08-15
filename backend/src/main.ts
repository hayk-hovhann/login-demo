import { NestFactory } from '@nestjs/core';
import session from 'express-session';
import { createClient } from 'redis';
import RedisStore from 'connect-redis';
import { AppModule } from './app.module';
import { ConfigService } from '@nestjs/config';
import { ValidationPipe } from '@nestjs/common';
import passport from 'passport';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const config = app.get(ConfigService);

  // All routes are served under /api (so the ALB / nginx can route /api/* here)
  app.setGlobalPrefix('api');
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  const redisClient = createClient({
    url: config.getOrThrow<string>('REDIS_URL'),
    socket: {
      connectTimeout: 5000,
      // Return an Error to STOP reconnecting -> connect() rejects instead of
      // hanging. Without this, the default strategy retries forever and the
      // await never settles.
      reconnectStrategy: (retries) =>
        retries > 5
          ? new Error('Redis unreachable')
          : Math.min(retries * 200, 2000),
    },
  });
  redisClient.on('error', (err) => console.error('Redis error:', err));
  await redisClient.connect();

  app.use(
    session({
      store: new RedisStore({
        client: redisClient,
        prefix: 'login-demo:sess:',
      }),
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
  app.use(passport.initialize());
  app.use(passport.session());

  const port = config.get<number>('PORT')!;
  await app.listen(config.get<number>('PORT')!, '0.0.0.0');
  console.log(`Backend listening on :${port}`);
}
void bootstrap().catch((err) => {
  console.error('Fatal: failed to start —', err);
  process.exit(1);
});
