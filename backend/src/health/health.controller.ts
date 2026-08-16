import { Controller, Get } from '@nestjs/common';

// Liveness only — deliberately does NOT touch Postgres. That is what lets the
// ECS stack go healthy BEFORE the migration task has ever run, so the
// deploy-then-migrate ordering works.
@Controller('health')
export class HealthController {
  @Get()
  check() {
    return { status: 'ok' };
  }
}
