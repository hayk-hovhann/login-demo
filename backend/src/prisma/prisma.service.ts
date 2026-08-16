import { Injectable, OnModuleInit, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PrismaClient } from '../generated/prisma/client';
import { PrismaPg } from '@prisma/adapter-pg';

// Module-scope on purpose: in a derived class `super()` must be the first
// statement, so this cannot be built inline from a parameter property.
function buildAdapter(config: ConfigService): PrismaPg {
  const url = config.get<string>('DATABASE_URL');
  if (url) return new PrismaPg({ connectionString: url });

  // Discrete params take the password as an opaque string — no URL escaping,
  // which matters because RDS-managed passwords may contain # ? % : &.
  return new PrismaPg({
    host: config.getOrThrow<string>('DB_HOST'),
    port: config.getOrThrow<number>('DB_PORT'),
    database: config.getOrThrow<string>('DB_NAME'),
    user: config.getOrThrow<string>('DB_USER'),
    password: config.getOrThrow<string>('DB_PASSWORD'),
  });
}

@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  constructor(config: ConfigService) {
    super({ adapter: buildAdapter(config) });
  }
  async onModuleInit() {
    await this.$connect();
  }
  async onModuleDestroy() {
    await this.$disconnect();
  }
}
