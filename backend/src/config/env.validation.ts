import { z } from 'zod';

const envSchema = z
  .object({
    PORT: z.coerce.number().int().positive().default(3000),
    REDIS_URL: z.url(),
    SESSION_SECRET: z
      .string()
      .min(16, 'SESSION_SECRET must be at least 16 chars'),
    COOKIE_SECURE: z
      .enum(['true', 'false'])
      .default('false')
      .transform((v) => v === 'true'),
    REGISTRATION_ENABLED: z
      .enum(['true', 'false'])
      .default('false')
      .transform((v) => v === 'true'),

    // Two accepted shapes for the database. DATABASE_URL wins when set (local
    // host-run dev, and an escape hatch); otherwise the discrete quintet, which
    // is what ECS injects — DB_PASSWORD/DB_USER arrive from Secrets Manager at
    // task start and so can never be interpolated into a URL at template time.
    DATABASE_URL: z.url().optional(),
    DB_HOST: z.string().min(1).optional(),
    DB_PORT: z.coerce.number().int().positive().default(5432),
    DB_NAME: z.string().min(1).optional(),
    DB_USER: z.string().min(1).optional(),
    DB_PASSWORD: z.string().min(1).optional(),
  })
  .refine(
    (e) =>
      !!e.DATABASE_URL ||
      (!!e.DB_HOST && !!e.DB_NAME && !!e.DB_USER && !!e.DB_PASSWORD),
    {
      // `path` is load-bearing: without it the issue path is empty and the
      // formatter below prints a bare "  : message" with nothing before the colon.
      path: ['DATABASE_URL'],
      message:
        'set DATABASE_URL, or all of DB_HOST / DB_NAME / DB_USER / DB_PASSWORD',
    },
  );

export type Env = z.infer<typeof envSchema>;

export function validateEnv(raw: Record<string, unknown>): Env {
  const parsed = envSchema.safeParse(raw);
  if (!parsed.success) {
    const issues = parsed.error.issues
      .map((i) => `  ${i.path.join('.')}: ${i.message}`)
      .join('\n');
    throw new Error(`Invalid environment:\n${issues}`);
  }
  return parsed.data;
}
