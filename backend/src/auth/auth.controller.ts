import {
  Body,
  Controller,
  Get,
  Post,
  Req,
  UseGuards,
  ForbiddenException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Request } from 'express';
import { AuthService } from './auth.service';
import { RegisterDto } from './dto/register.dto';
import { LocalAuthGuard } from './guards/local-auth.guard';
import { AuthenticatedGuard } from './guards/authenticated.guard';

@Controller('auth')
export class AuthController {
  constructor(
    private readonly authService: AuthService,
    private readonly config: ConfigService,
  ) {}

  @Post('register')
  async register(@Body() body: RegisterDto) {
    if (!this.config.get<boolean>('REGISTRATION_ENABLED'))
      throw new ForbiddenException('registration disabled');
    return this.authService.register(body.username, body.password);
  }

  @UseGuards(LocalAuthGuard) // guard validates creds + logs in; body consumed by passport
  @Post('login')
  login(@Req() req: Request) {
    return { ok: true, user: req.user };
  }

  @UseGuards(AuthenticatedGuard) // 403 if no valid session
  @Get('me')
  me(@Req() req: Request) {
    return { user: req.user };
  }

  @Post('logout')
  logout(@Req() req: Request) {
    req.logout((err) => {
      if (err) return;
      req.session.destroy(() => undefined);
    });
    return { ok: true };
  }
}
