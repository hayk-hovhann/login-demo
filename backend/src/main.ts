import { NestFactory } from '@nestjs/core';
import session from 'express-session';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // All routes are served under /api  (so the ALB / nginx can route /api/* here)
  app.setGlobalPrefix('api');

  // Session middleware. Default store is in-memory (fine for now, see README caveats).
  app.use(
    session({
      secret: process.env.SESSION_SECRET ?? 'dev-secret-change-me',
      resave: false,
      saveUninitialized: false,
      cookie: {
        httpOnly: true, // JS can't read the cookie
        secure: process.env.COOKIE_SECURE === 'true', // true only behind HTTPS
        maxAge: 1000 * 60 * 60, // 1 hour
      },
    }),
  );

  const port = process.env.PORT ? Number(process.env.PORT) : 3000;
  await app.listen(port, '0.0.0.0');
  console.log(`Backend listening on :${port}`);
}
void bootstrap();
