import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import session from 'express-session';
import RedisStore from 'connect-redis';
import { AppModule } from './app.module';
import { REDIS_CLIENT, type RedisClient } from './redis/redis.module';
import { ConfigService } from '@nestjs/config';
import { ValidationPipe } from '@nestjs/common';
import passport from 'passport';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule);
  const config = app.get(ConfigService);

  // Without this Nest ignores SIGTERM, Node's default kicks in, and the process
  // dies mid-request with its Postgres/Redis sockets left dangling. With it, a
  // SIGTERM stops new requests, drains in-flight ones, then runs every
  // onApplicationShutdown hook — all inside the orchestrator's grace period
  // (compose 10s, ECS 30s) before SIGKILL.
  //
  // useProcessExit: by default Nest ends by re-sending the signal to itself, but
  // in a container Node is PID 1 and the kernel drops signals PID 1 has no
  // handler for — so exit would hinge on every handle having closed, and one
  // stray timer means SIGKILL (137). process.exit(0) after cleanup is certain.
  // [] = the default signal set (SIGTERM, SIGINT, ...).
  app.enableShutdownHooks([], { useProcessExit: true });

  // LOAD-BEARING once TLS terminates at the ALB. The ALB speaks HTTPS to the
  // browser but plain HTTP to the task, so Express sees an insecure connection
  // and express-session will silently DECLINE to send a `secure` cookie — login
  // returns 201 with no Set-Cookie and /me is 403 forever, which reads like a
  // Passport bug. `1` = trust exactly one proxy hop (the ALB), so X-Forwarded-Proto
  // is believed but a client-supplied one cannot be spoofed through it.
  // Inert locally: compose's nginx forwards Host/X-Real-IP/Cookie and no
  // X-Forwarded-Proto, so req.protocol stays http and COOKIE_SECURE stays false.
  app.set('trust proxy', 1);

  // All routes are served under /api (so the ALB / nginx can route /api/* here)
  app.setGlobalPrefix('api');
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  // Built and connected by RedisModule; the same client backs /api/ready.
  const redisClient = app.get<RedisClient>(REDIS_CLIENT);

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
