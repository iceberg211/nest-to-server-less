import { Module } from '@nestjs/common';
import { FormDataService } from './form-data.service';
import { FormDataController } from './form-data.controller';
import { PrismaService } from '../prisma.service';

@Module({
  controllers: [FormDataController],
  providers: [FormDataService, PrismaService],
})
export class FormDataModule {}