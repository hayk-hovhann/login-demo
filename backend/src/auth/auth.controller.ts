import { Body, Controller, Get, Post, Req } from '@nestjs/common';
import type { Request } from 'express';
import { AuthService } from './auth.service';

interface LoginDto {
  username: string;
  password: string;
}

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  // POST /api/auth/login  -> validate creds, store user on the session
  @Post('login')
  login(@Body() body: LoginDto, @Req() req: Request) {
    const user = this.authService.validate(body?.username, body?.password);
    req.session.user = user;
    return { ok: true, user };
  }

  // GET /api/auth/me  -> who am I? (reads the session cookie)
  @Get('me')
  me(@Req() req: Request) {
    return { user: req.session.user ?? null };
  }

  // POST /api/auth/logout  -> clear the session
  @Post('logout')
  logout(@Req() req: Request) {
    req.session.destroy(() => undefined);
    return { ok: true };
  }
}
