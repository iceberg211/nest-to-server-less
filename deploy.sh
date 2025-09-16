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

# Build the application for Lambda
echo "🔨 Building application for Lambda..."
pnpm run build:lambda

# Update samconfig.toml with environment variables
echo "📝 Updating SAM configuration with environment variables..."

# Build and deploy with SAM
echo "🏗️  Building SAM application..."
sam build

echo "🚀 Deploying to AWS..."
sam deploy \
  --parameter-overrides \
    "DatabaseUrl=${DATABASE_URL}" \
    "DirectUrl=${DIRECT_URL:-}" \
    "SupabaseUrl=${SUPABASE_URL:-}" \
    "SupabaseKey=${SUPABASE_KEY:-}"

echo "✅ Deployment completed successfully!"

# Get the API endpoint
echo "🔗 Getting API endpoint..."
sam list stack-outputs --stack-name nest-serverless --region us-east-1

echo "📋 Next steps:"
echo "   1. Test your API endpoints"
echo "   2. Set up custom domain (if needed)"
echo "   3. Configure monitoring and logging"
echo "   4. Run database migrations if needed: sam logs -n NestJSFunction --stack-name nest-serverless --tail"