#!/bin/bash

# NestJS SAM Deployment Script

set -e

echo "🚀 Starting NestJS SAM deployment..."

# Check if AWS CLI is configured
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo "❌ AWS CLI is not configured. Please run 'aws configure' first."
    exit 1
fi

# Check if SAM CLI is installed
if ! command -v sam &> /dev/null; then
    echo "❌ AWS SAM CLI is not installed. Please install it first:"
    echo "   https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html"
    exit 1
fi

# Check if environment variables file exists
if [[ ! -f ".env.production" ]]; then
    echo "❌ .env.production file not found."
    echo "   Please copy .env.production.template to .env.production and fill in your values."
    exit 1
fi

# Load environment variables from .env.production
set -a
source .env.production
set +a

echo "✅ Environment variables loaded"

# Build the application for Lambda with optimization
echo "🔨 Building application for Lambda (optimized)..."
npx webpack --config webpack.config.js

echo "📦 Preparing Lambda layer..."
mkdir -p layer/nodejs
echo '{
  "name": "nest-dependencies",
  "dependencies": {
    "@nestjs/common": "^11.0.1",
    "@nestjs/core": "^11.0.1",
    "@nestjs/platform-express": "^11.0.1",
    "@vendia/serverless-express": "^4.12.6",
    "express": "^5.1.0",
    "reflect-metadata": "^0.2.2",
    "rxjs": "^7.8.1"
  }
}' > layer/nodejs/package.json

echo "📦 Installing layer dependencies..."
cd layer/nodejs
npm install --production --no-package-lock --no-fund --no-audit

echo "🧹 Optimizing layer size..."
find node_modules -type d \( -name "test" -o -name "tests" -o -name "__tests__" -o -name "spec" -o -name "specs" \) -exec rm -rf {} + 2>/dev/null || true
find node_modules -type d \( -name "example" -o -name "examples" -o -name "docs" -o -name "doc" -o -name "demo" \) -exec rm -rf {} + 2>/dev/null || true
find node_modules -type f \( -name "*.map" -o -name "*.ts" ! -name "*.d.ts" \) -delete 2>/dev/null || true
find node_modules -type f \( -name "*.md" -o -name "*.txt" -o -name "*.yml" -o -name "*.yaml" \) -delete 2>/dev/null || true

echo "📊 Package sizes:"
echo "Layer size: $(du -sh . | cut -f1)"
cd ../..
echo "Function size: $(du -sh dist/ | cut -f1)"

echo "⚙️ Copying environment configuration..."
cp .env.production dist/.env

echo "🔧 Generating Prisma client..."
npx prisma generate

echo "📦 Installing function-specific dependencies..."
cd dist
npm init -y
npm install --production --no-package-lock --no-fund --no-audit \
  @prisma/client \
  pg \
  axios \
  @supabase/supabase-js \
  @types/aws-lambda \
  @types/pg
cd ..

echo "📦 Copying generated Prisma client to function directory..."

# 查找实际的Prisma客户端路径
PRISMA_CLIENT_PATH=$(find node_modules -path "*/@prisma/client" -type d | head -1)
PRISMA_GENERATED_PATH=$(find node_modules -path "*/.prisma/client" -type d | head -1)

echo "Found Prisma paths:"
echo "  @prisma/client: $PRISMA_CLIENT_PATH"
echo "  .prisma/client: $PRISMA_GENERATED_PATH"

mkdir -p dist/node_modules/@prisma
mkdir -p dist/node_modules/.prisma

if [ -d "$PRISMA_CLIENT_PATH" ]; then
    mkdir -p dist/node_modules/@prisma/client
    cp -r "$PRISMA_CLIENT_PATH/"* dist/node_modules/@prisma/client/
fi

if [ -d "$PRISMA_GENERATED_PATH" ]; then
    mkdir -p dist/node_modules/.prisma/client
    cp -r "$PRISMA_GENERATED_PATH/"* dist/node_modules/.prisma/client/
fi

echo "📂 Copying static files..."
cp -r public dist/

# Update samconfig.toml with environment variables
echo "📝 Updating SAM configuration with environment variables..."

# Build and deploy with SAM
echo "🏗️  Building SAM application..."
sam build

echo "🚀 Deploying to AWS..."
sam deploy \
  --parameter-overrides \
    "DatabaseUrl=${DATABASE_URL}"

echo "✅ Deployment completed successfully!"

# Get the API endpoint
echo "🔗 Getting API endpoint..."
sam list stack-outputs --stack-name nest-serverless --region ap-northeast-1

echo "📋 Next steps:"
echo "   1. Test your API endpoints"
echo "   2. Set up custom domain (if needed)"
echo "   3. Configure monitoring and logging"
echo "   4. Run database migrations if needed: sam logs -n NestJSFunction --stack-name nest-serverless --tail"
