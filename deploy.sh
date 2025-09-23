#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$SCRIPT_DIR"

ENV_FILE=".env.production"

printf '🚀 Starting production deployment...\n'

if ! command -v aws >/dev/null 2>&1; then
  printf '❌ AWS CLI is not installed. Install it before deploying.\n'
  exit 1
fi

if ! aws sts get-caller-identity >/dev/null 2>&1; then
  printf "❌ AWS CLI is not configured. Run 'aws configure' first.\n"
  exit 1
fi

if ! command -v sam >/dev/null 2>&1; then
  printf '❌ AWS SAM CLI is not installed.\n'
  printf '   https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html\n'
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  printf "❌ %s file not found.\n" "$ENV_FILE"
  printf "   Copy .env.production.template to %s and fill in the values.\n" "$ENV_FILE"
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

if [[ -z "${DATABASE_URL:-}" ]]; then
  printf "❌ DATABASE_URL is required in %s.\n" "$ENV_FILE"
  exit 1
fi

printf '🧹 Cleaning previous build artifacts...\n'
rm -rf dist .aws-sam layer

printf '📦 Building Lambda bundle with webpack...\n'
npx webpack --config webpack.config.js

printf '📦 Preparing Lambda layer...\n'
LAYER_DIR="layer/nodejs"
mkdir -p "$LAYER_DIR"

cat <<'JSON' > "$LAYER_DIR/package.json"
{
  "name": "nest-dependencies",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "@nestjs/common": "11.0.1",
    "@nestjs/core": "11.0.1",
    "@nestjs/platform-express": "11.0.1",
    "@vendia/serverless-express": "4.12.6",
    "express": "5.1.0",
    "reflect-metadata": "0.2.2",
    "rxjs": "7.8.1"
  }
}
JSON

(
  cd "$LAYER_DIR"
  npm install --production --no-package-lock --no-fund --no-audit
)

LAYER_NODE_MODULES="$LAYER_DIR/node_modules"

printf '🧹 Trimming Lambda layer size...\n'
find "$LAYER_NODE_MODULES" -type d \
  \( -name 'test' -o -name 'tests' -o -name '__tests__' -o -name 'example' -o -name 'examples' -o -name 'docs' -o -name 'doc' -o -name 'demo' \) \
  -prune -exec rm -rf '{}' + 2>/dev/null || true
find "$LAYER_NODE_MODULES" -type f \
  \( -name '*.md' -o -name '*.txt' -o -name '*.map' -o \( -name '*.ts' ! -name '*.d.ts' \) \) \
  -delete 2>/dev/null || true
find "$LAYER_NODE_MODULES" -type f \
  \( -name 'LICENSE*' -o -name 'CHANGELOG*' -o -name 'HISTORY*' -o -name '.eslintrc*' -o -name '.prettier*' \) \
  -delete 2>/dev/null || true

printf '🔧 Copying Prisma schema to layer...\n'
cp prisma/schema.prisma "$LAYER_DIR/"

printf '⚙️ Writing production environment for runtime...\n'
cp "$ENV_FILE" dist/.env

printf '🔧 Generating Prisma client...\n'
npx prisma generate

printf '📦 Copying Prisma runtime to function bundle...\n'
mkdir -p dist/node_modules/@prisma dist/node_modules/.prisma
cp -R node_modules/@prisma/client dist/node_modules/@prisma/
if [[ -d node_modules/.prisma/client ]]; then
  cp -R node_modules/.prisma/client dist/node_modules/.prisma/
fi

if [[ -d public ]]; then
  printf '📂 Copying static assets...\n'
  cp -R public dist/
fi

printf '🏗️  Building SAM application...\n'
sam build

printf '🚀 Deploying to AWS...\n'
sam deploy --parameter-overrides "DatabaseUrl=${DATABASE_URL}"

printf '🔗 Fetching stack outputs...\n'
sam list stack-outputs --stack-name nest-serverless

printf '✅ Deployment completed successfully.\n'
