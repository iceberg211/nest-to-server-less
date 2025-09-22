# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a NestJS application configured for serverless deployment on AWS Lambda using AWS SAM (Serverless Application Model). The application integrates with both Supabase and AWS RDS PostgreSQL databases, with flexible database switching capabilities.

## Development Commands

### Building and Development
- `pnpm run build` - Standard NestJS build
- `pnpm run build:lambda` - Build for Lambda deployment (copies dependencies to dist/)
- `pnpm start:dev` - Start development server with hot reload
- `pnpm start:debug` - Start with debugging enabled

### Code Quality
- `pnpm run lint` - Run ESLint with auto-fix
- `pnpm run format` - Format code with Prettier

### Testing
- `pnpm run test` - Run unit tests
- `pnpm run test:watch` - Run tests in watch mode
- `pnpm run test:cov` - Run tests with coverage
- `pnpm run test:e2e` - Run end-to-end tests

### AWS SAM Deployment
- `pnpm run sam:build` - Build Lambda package and SAM template
- `pnpm run sam:deploy` - Deploy to AWS (use `--guided` for first deployment)
- `pnpm run sam:local` - Start local API Gateway simulation
- `pnpm run sam:logs` - View Lambda function logs

## Architecture

### Core Structure
- **NestJS Application**: Standard modular architecture with controllers, services, and modules
- **Lambda Handler**: `src/lambda.ts` - Express adapter for AWS Lambda using @vendia/serverless-express
- **Database Layer**: Prisma ORM with dual database support (Supabase/AWS RDS)
- **Modules**:
  - `FormDataModule` - Handles form data operations
  - `GitHubModule` - GitHub integration features

### Database Configuration
The application supports flexible database switching via environment variables:
- **Supabase**: Uses `SUPABASE_DATABASE_URL`
- **AWS Aurora**: Uses `DATABASE_URL` (Aurora PostgreSQL cluster)
- Priority: DATABASE_URL → SUPABASE_DATABASE_URL
- Configuration handled in `src/prisma.service.ts`

### Deployment Architecture
- **Template**: `template.yaml` - SAM CloudFormation template with hardcoded VPC configuration
- **Configuration**: `samconfig.toml` - Simplified deployment parameters
- **VPC Integration**: Lambda functions deployed in specific private subnets (hardcoded)
- **Security Group**: Uses existing RDS security group (sg-06148d712037fec50) and Lambda security group
- **API Gateway**: RESTful API with CORS enabled, binary media type support
- **Warmup Function**: Scheduled Lambda to prevent cold starts

## Key Files and Patterns

### Entry Points
- `src/main.ts` - Local development server
- `src/lambda.ts` - AWS Lambda handler with server caching

### Database
- `prisma/schema.prisma` - Database schema (currently has FormData model)
- `src/prisma.service.ts` - Database service with multi-environment support

### Environment Configuration
Database connection priority in PrismaService:
1. `AWS_DATABASE_URL` or `DATABASE_URL` (production)
2. `SUPABASE_DATABASE_URL` (development/demo)

### SAM Configuration Notes
- Runtime: Node.js 20.x
- Memory: 512MB, Timeout: 30s
- VPC-enabled with security groups
- API Gateway with proxy integration for all routes
- Warmup function runs every 5 minutes

## Development Workflow

1. **Local Development**: Use `pnpm start:dev` with database configured via environment variables
2. **Testing**: Run `pnpm test` before deployment
3. **Lambda Build**: Use `pnpm run build:lambda` to prepare for deployment
4. **SAM Deployment**: Use `pnpm run sam:build` then `pnpm run sam:deploy`
5. **Local Lambda Testing**: Use `pnpm run sam:local` to test Lambda locally

## Database Operations

Prisma commands should be run with the correct environment:
- `pnpm exec prisma generate` - Generate Prisma client
- `pnpm exec prisma db push` - Push schema changes
- `pnpm exec prisma studio` - Open Prisma Studio

## Important Notes

- The application uses Express adapter for Lambda compatibility
- Database switching is automatic based on environment variables
- SAM template includes VPC configuration for secure database access
- API routes are prefixed with `/api` in Lambda environment
- CORS is enabled for cross-origin requests