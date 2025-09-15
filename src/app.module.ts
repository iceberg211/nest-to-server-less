import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { FormDataModule } from './form-data/form-data.module';
import { GitHubModule } from './github/github.module';

@Module({
  imports: [FormDataModule, GitHubModule],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
