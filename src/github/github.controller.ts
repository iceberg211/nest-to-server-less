import { Controller, Get, Headers, HttpException, HttpStatus } from '@nestjs/common';
import { GitHubService } from './github.service';

@Controller('github')
export class GitHubController {
  constructor(private readonly githubService: GitHubService) {}

  @Get('user')
  async getUserInfo(@Headers('authorization') authorization: string) {
    if (!authorization) {
      throw new HttpException(
        'Authorization header is required',
        HttpStatus.BAD_REQUEST,
      );
    }

    const token = authorization.replace('Bearer ', '').replace('token ', '');

    if (!token) {
      throw new HttpException(
        'GitHub token is required',
        HttpStatus.BAD_REQUEST,
      );
    }

    return this.githubService.getUserInfo(token);
  }
}