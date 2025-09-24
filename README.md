# NestJS SAM 部署指南（中文）

本指南串联整个 AWS SAM 部署流程，从本地构建、Webpack 打包、Layer 优化到部署脚本编排，帮助你快速复现线上环境。

## 环境准备

1. **安装 AWS SAM CLI**
   ```bash
   # macOS
   brew install aws-sam-cli

   # 其他平台请参考官方文档
   # https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html
   ```
2. **安装项目依赖并拷贝生产环境变量模板**
   ```bash
   pnpm install
   cp .env.production.template .env.production
   # 编辑 .env.production，补全数据库、Supabase 等敏感信息
   ```
3. **配置 AWS 凭证**
   ```bash
   aws configure
   ```

## 构建 Lambda：`pnpm build:lambda`

该命令贯穿整个“构建 → Layer → 依赖复制”流程，是部署前最关键的一步，主要动作如下：

1. **清理历史产物**：删除 `dist/`、`layer/`，保证每次构建干净可复现。
2. **编译 Nest 应用**：执行 `nest build` 输出至 `dist/`，并在存在 `public/` 时复制到 `dist/public` 以支持静态资源。
3. **准备 Layer 目录**：创建 `layer/nodejs`，拷贝 `package.json`、`pnpm-lock.yaml` 以及 `prisma/`。
4. **安装生产依赖**：在 Layer 目录内运行 `pnpm install --prod --frozen-lockfile --dir layer/nodejs`，随后删除临时的 `prisma` 目录降低体积。

执行完成后会生成两个关键目录：

- `dist/`：Lambda Function 实际上传的代码（包含编译后的 Nest、静态资源、Prisma 运行时）。
- `layer/`：被 SAM 模板引用的依赖 Layer，提供运行时通用依赖。

> **提示**：构建失败时，先检查 `.env.production` 是否补全，以及 Prisma 是否成功生成。

## Webpack 在部署中的作用

`deploy.sh` 会在 `pnpm build:lambda` 之后调用 `npx webpack --config webpack.config.js`，它主要负责：

- **打包 Lambda 入口**：将 `src/lambda.ts` 压缩为单文件入口，提升加载速度。
- **Tree Shaking 与按需打包**：移除未使用的 Nest 模块和第三方库，减轻冷启动负担。
- **剔除冗余文件**：结合脚本中的 `find` 命令清理 `.md`、`test`、`docs`、`.map` 等非运行时文件，避免包体超过 Lambda 限制（单函数压缩后 ≤50 MB、解压后 ≤250 MB）。

若新增大型依赖，可视情况在 `webpack.config.js` 中配置 external/alias，确保仅打包必要代码。

## Layer 与部署脚本职责

`template.yaml` 定义了 `DependenciesLayer`，部署脚本会执行以下操作：

1. **写入 Layer package.json**：只保留核心运行时依赖（NestJS、Express、@vendia/serverless-express、rxjs 等）。
2. **安装依赖并裁剪体积**：`npm install --production` 后，使用多轮 `find` 删除测试、示例、文档、源码等调试文件。
3. **复制 Prisma Schema**：将 `prisma/schema.prisma` 放入 Layer 以支持运行时 Prisma。
4. **写入 Prisma Client 至 dist**：把 `node_modules/@prisma/client` 与 `.prisma/client` 拷贝进 `dist/node_modules`，保证 Function 能正常访问数据库。

**控制 Layer 大小的建议**：

- Layer 中只放通用依赖，业务相关包保留在函数代码目录。
- 定期检查 `layer/nodejs/node_modules` 大小，确认无误放的大文件或临时产物。
- 利用脚本中的裁剪步骤，必要时可增加自定义删除规则。

## 部署脚本（`deploy.sh`）流程解析

脚本封装了上线所有动作，核心步骤如下：

1. **前置校验**：检测 AWS CLI、SAM CLI 是否安装与授权，确认 `.env.production` 存在并注入环境变量。
2. **清理与 Webpack 打包**：删除旧的 `dist/`、`layer/`、`.aws-sam/`，随后执行 Webpack 打包 Lambda 入口。
3. **构建 Layer**：写入依赖文件、安装生产依赖并裁剪体积，复制 Prisma schema。
4. **生成 Prisma Client 与静态资源**：`npx prisma generate`，将 Prisma 运行时代码与 `public/` 静态资源复制到 `dist/`。
5. **SAM 构建与部署**：依次运行 `sam build`、`sam deploy --parameter-overrides "DatabaseUrl=$DATABASE_URL"`，最后拉取 Stack 输出。

如果你需要自定义脚本，可参考以下伪代码骨架：

```bash
#!/bin/bash
set -euo pipefail

# 1. 校验依赖与环境变量
# 2. 清理 dist / layer / .aws-sam
# 3. nest build + webpack 打包
# 4. 安装 Layer 依赖并裁剪
# 5. prisma generate + 拷贝静态资源
# 6. sam build
# 7. sam deploy --parameter-overrides "DatabaseUrl=$DATABASE_URL"
```

在编写脚本时请确保：

- 以仓库根目录为工作目录（示例脚本使用 `SCRIPT_DIR`）。
- 所有部署参数统一维护在 `.env.production` 中，脚本通过 `set -a`/`source` 暴露。
- 发布前可单独运行 `sam build` 或 `sam validate` 检查模板合法性。

## SAM 部署命令详解

1. **首次部署（推荐 Guided）**
   ```bash
   pnpm build:lambda
   pnpm sam:build      # 可选：提前校验打包
   pnpm sam:deploy     # sam deploy --guided
   ```
   向导中的常见选项：
   - `Confirm changes before deploy`: 选择 `Y`，部署前审查变更。
   - `Allow SAM CLI IAM role creation`: 选择 `Y`，允许自动创建角色。
   - `Disable rollback`: 建议保持 `N`，失败时自动回滚。
   - `Parameter DatabaseUrl`: 可直接回车使用默认值，或输入自定义地址。

2. **后续部署**
   ```bash
   pnpm build:lambda   # 每次部署前都需要运行
   sam deploy          # 使用 samconfig.toml 中的参数
   ```
   如果更新了依赖、Prisma Schema 或基础设施，请再次执行 `pnpm sam:build`、`sam validate` 确认。

3. **一键部署脚本**
   ```bash
   pnpm deploy:aws      # 封装上述全部步骤
   ```

## 常见问题排查

- **S3 存储桶**：`samconfig.toml` 默认使用 `myfisrts3387793809149`；如需替换，可编辑配置或在命令中追加 `--s3-bucket`。
- **缺少 Layer**：报错 `ContentUri ... does not exist` 表示未运行 `pnpm build:lambda`。
- **Stack 进入 ROLLBACK_COMPLETE**：需在 CloudFormation 控制台删除旧 Stack 或更换名称再部署。
- **包体超限**：检查 `layer/nodejs/node_modules`，确认裁剪步骤执行成功，可进一步删除 docs/test/示例目录。

## 常用命令速查

```bash
# 本地调试 API Gateway
pnpm sam:local

# 编译 + 构建 Lambda / Layer
pnpm build
pnpm build:lambda

# SAM 构建与部署
pnpm sam:build
pnpm sam:deploy

# 一键部署脚本
pnpm deploy:aws

# 查看线上日志
pnpm sam:logs
```

## 关键文件速览

- `src/lambda.ts`：Nest 应用 Lambda 入口，适配 `@vendia/serverless-express`。
- `template.yaml`：SAM 模板，声明函数、Layer、VPC、API Gateway 等资源。
- `deploy.sh`：包含构建、裁剪、Prisma 生成与 `sam deploy` 的完整脚本。
- `samconfig.toml`：`sam deploy --guided` 生成的部署参数。
- `.env.production`：生产环境变量文件（基于模板复制），勿提交真实密钥。

## API 访问路径

部署成功后，REST API 访问地址为：

```
https://{api-id}.execute-api.{region}.amazonaws.com/prod/{endpoint}
```

其中 `{endpoint}` 需替换为实际业务路由，如 `api/github/user`。
