#!/bin/bash

set -e

ENVIRONMENT=${1:-production}
VALID_ENVIRONMENTS=("development" "production" "test")

if [[ ! " ${VALID_ENVIRONMENTS[@]} " =~ " ${ENVIRONMENT} " ]]; then
    echo "Error: Invalid environment '${ENVIRONMENT}'. Valid options are: ${VALID_ENVIRONMENTS[*]}"
    exit 1
fi

ENV_FILE=".env.${ENVIRONMENT}"
if [[ ! -f "$ENV_FILE" ]]; then
    echo "Error: Environment file '$ENV_FILE' not found"
    exit 1
fi

echo "🔨 Building for environment: ${ENVIRONMENT}"

echo "🧹 Cleaning previous build..."
rm -rf dist/
rm -rf .aws-sam/
rm -rf layer/

echo "📦 Building application with webpack..."
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
# 删除测试和文档目录
find node_modules -type d \( -name "test" -o -name "tests" -o -name "__tests__" -o -name "spec" -o -name "specs" \) -exec rm -rf {} + 2>/dev/null || true
find node_modules -type d \( -name "example" -o -name "examples" -o -name "docs" -o -name "doc" -o -name "demo" \) -exec rm -rf {} + 2>/dev/null || true
find node_modules -type d \( -name "benchmark" -o -name "coverage" -o -name ".github" -o -name ".vscode" \) -exec rm -rf {} + 2>/dev/null || true

# 删除不必要的文件
find node_modules -type f \( -name "*.map" -o -name "*.ts" ! -name "*.d.ts" \) -delete 2>/dev/null || true
find node_modules -type f \( -name "*.md" -o -name "*.txt" -o -name "*.yml" -o -name "*.yaml" \) -delete 2>/dev/null || true
find node_modules -type f \( -name "LICENSE*" -o -name "CHANGELOG*" -o -name "HISTORY*" -o -name "AUTHORS*" \) -delete 2>/dev/null || true
find node_modules -type f \( -name ".eslint*" -o -name ".prettier*" -o -name ".editorconfig" \) -delete 2>/dev/null || true
find node_modules -type f \( -name "tsconfig*.json" -o -name "webpack*.js" -o -name "rollup*.js" \) -delete 2>/dev/null || true

# 删除大型非必需文件
find node_modules -name "*.min.js.map" -delete 2>/dev/null || true
find node_modules -name "bower.json" -delete 2>/dev/null || true
find node_modules -name "component.json" -delete 2>/dev/null || true

echo "📊 Layer size after optimization:"
du -sh node_modules/
cd ../..

echo "⚙️ Copying environment configuration..."
cp "$ENV_FILE" dist/.env

echo "🔧 Generating Prisma client..."
npx prisma generate

echo "📦 Installing function-specific dependencies in dist..."
# 只安装函数包需要的依赖（不在layer中的）
mkdir -p dist/node_modules
cd dist
npm init -y
npm install --production --no-package-lock --no-fund --no-audit \
  @prisma/client \
  pg \
  axios \
  @supabase/supabase-js \
  @types/aws-lambda \
  @types/pg

# 复制Prisma生成的客户端
if [ -d "../node_modules/.prisma" ]; then
    cp -r ../node_modules/.prisma node_modules/
fi

cd ..

echo "📊 Final package sizes:"
echo "Layer size: $(du -sh layer/ | cut -f1)"
echo "Function size: $(du -sh dist/ | cut -f1)"

if [[ "$ENVIRONMENT" == "development" ]]; then
    echo "🚀 Local development options:"
    echo "1. SAM Local (requires Docker): sam local start-api --port 3001"
    echo "2. Direct Node.js: npm run start:dev"
    echo ""
    echo "Choose option:"
    echo "[1] SAM Local with Docker"
    echo "[2] Direct Node.js development server"
    echo "[3] Just build and exit"

    read -p "Enter your choice (1-3): " choice

    case $choice in
        1)
            echo "🚀 Starting SAM local server..."
            sam local start-api --port 3001
            ;;
        2)
            echo "🚀 Starting Node.js development server..."
            npm run start:dev
            ;;
        3)
            echo "✅ Build completed. Use 'npm run start:dev' for local development."
            ;;
        *)
            echo "Invalid choice. Build completed."
            ;;
    esac
elif [[ "$ENVIRONMENT" == "production" ]]; then
    echo "🚀 Building SAM application..."
    sam build

    if [ $? -eq 0 ]; then
        echo "🚀 Deploying to AWS..."
        sam deploy
    else
        echo "❌ Sam build failed!"
        exit 1
    fi
else
    echo "✅ Build completed for ${ENVIRONMENT} environment"
fi