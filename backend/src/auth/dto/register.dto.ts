// register.dto.ts
import { IsString, MinLength, MaxLength } from 'class-validator';

export class RegisterDto {
  @IsString() @MinLength(3) @MaxLength(32) username: string;
  @IsString() @MinLength(8) @MaxLength(128) password: string;
}
