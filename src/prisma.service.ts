import { Injectable, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit {
  constructor() {
    const supabaseDbUrl = process.env.SUPABASE_DATABASE_URL;
    const awsDbUrl = process.env.AWS_DATABASE_URL ?? process.env.DATABASE_URL;

    const databaseUrl =
      // AWS production database (used when Supabase is disabled)
      awsDbUrl ??
      // Supabase demo database (comment this line to switch to AWS)
      supabaseDbUrl;

    if (!databaseUrl) {
      throw new Error(
        'No database connection string configured. Set SUPABASE_DATABASE_URL or AWS_DATABASE_URL/DATABASE_URL.',
      );
    }

    super({
      datasources: {
        db: {
          url: databaseUrl,
        },
      },
    });
  }

  async onModuleInit() {
    await this.$connect();
  }
}
