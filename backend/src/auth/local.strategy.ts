import { Injectable } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { Strategy } from 'passport-local'; // default fields: username, password — matches your body
import { AuthService } from './auth.service';

@Injectable()
export class LocalStrategy extends PassportStrategy(Strategy) {
  constructor(private readonly authService: AuthService) {
    super();
  }
  // return value becomes req.user; throwing (validateUser does) → 401
  async validate(username: string, password: string) {
    return this.authService.validateUser(username, password);
  }
}
