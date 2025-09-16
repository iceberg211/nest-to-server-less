# NestJS SAM 部署指南

## 准备工作

1. **安装 AWS SAM CLI**
   ```bash
   # macOS
   brew install aws-sam-cli

   # 其他平台参考: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html
   ```

2. **配置 AWS 凭证**
   ```bash
   aws configure
   ```

3. **配置环境变量**
   ```bash
   cp .env.production.template .env.production
   # 编辑 .env.production 填入你的数据库连接信息
   ```

## 部署步骤

### 1. 构建应用
```bash
pnpm run build:lambda
```

### 2. SAM 构建
```bash
sam build
```

### 3. 首次部署（引导式）
```bash
sam deploy --guided
```

### 4. 后续部署
```bash
sam deploy
```

## 快捷脚本

```bash
# 本地测试
pnpm run sam:local

# 构建和部署
pnpm run sam:build
pnpm run sam:deploy

# 查看日志
pnpm run sam:logs
```

## 关键文件说明

- `src/lambda.ts` - Lambda 处理器（使用 Fastify 适配器，无需 Express 和 serverless-express）
- `template.yaml` - SAM 模板配置
- `samconfig.toml` - SAM 部署配置
- `.env.production.template` - 生产环境变量模板

## 技术选择

使用 **@nestjs/platform-fastify** 而不是 Express + serverless-express：
- 更轻量，性能更好
- 原生支持 Lambda inject 方法
- 减少依赖，避免额外的适配层

## API 访问

部署成功后，你的 NestJS API 将通过以下格式访问：
```
https://{api-id}.execute-api.{region}.amazonaws.com/prod/api/{endpoint}
```