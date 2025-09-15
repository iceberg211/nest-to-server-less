import { Module } from '@nestjs/common';
import { GitHubService } from './github.service';
import { GitHubController } from './github.controller';

@Module({
  controllers: [GitHubController],
  providers: [GitHubService],
})
export class GitHubModule {}