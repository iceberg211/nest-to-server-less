# NestJS SAM 部署指南

## 准备工作

1. **安装 AWS SAM CLI**
   ```bash
   # macOS
   brew install aws-sam-cli

   # 其他平台参考官方文档
   # https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html
   ```
2. **安装依赖并准备环境变量**
   ```bash
   pnpm install
   cp .env.production.template .env.production
   # 编辑 .env.production，填写数据库等敏感信息
   ```
3. **配置 AWS 凭证**
   ```bash
   aws configure
   ```

## 部署流程

1. **构建 Lambda 代码与 Layer**  
   `layer/` 目录不会提交到仓库，每次部署前都需要重新生成：
   ```bash
   pnpm build:lambda
   ```
2. **SAM 打包**  
   如需单独验证构建可以执行：
   ```bash
   pnpm sam:build   # 等价于 sam build
   ```
3. **首次部署（带向导）**  
   首次运行建议使用 Guided 模式生成 `samconfig.toml`：
   ```bash
   pnpm sam:deploy   # 内部执行 sam deploy --guided
   ```
   向导中的常见问题及建议答案：
   - `Confirm changes before deploy`：输入 `Y`，方便在部署前审查变更。
   - `Allow SAM CLI IAM role creation`：选择 `Y`，允许 SAM 创建 Lambda 所需的 IAM 角色。
   - `Disable rollback`：建议保持默认的 `N`，部署失败时自动回滚。 
   - `Parameter DatabaseUrl`：直接回车使用 `template.yaml`/`samconfig.toml` 中预设的数据库地址，或按需覆盖。
4. **后续部署**  
   向导保存的参数会写入 `samconfig.toml`，之后直接运行：
   ```bash
   sam deploy
   ```
   如果在部署前更新了依赖、Prisma schema 或基础设施，请先重新执行 `pnpm build:lambda` 和 `pnpm sam:build`。

## 常见部署提示

- **S3 存储桶**：`samconfig.toml` 中的 `s3_bucket = "myfisrts3387793809149"`。如需改用自定义桶，可编辑配置或在命令中追加 `--s3-bucket`。
- **DatabaseUrl 写死**：`template.yaml` 的 `Parameters.DatabaseUrl` 已提供默认值，同时 `samconfig.toml` 的 `parameter_overrides` 也写入了相同地址；非 Guided 部署时不会再次询问。
- **缺少 layer/ 报错**：如果看到 `Parameter ContentUri of resource DependenciesLayer refers to a file or folder that does not exist`，说明还没运行 `pnpm build:lambda`。
- **ROLLBACK_COMPLETE**：若上次部署失败导致栈进入该状态，需要在 CloudFormation 控制台删除或更换 stack 名称后再部署。

## 快捷脚本

```bash
# 本地调试 API Gateway
pnpm sam:local

# 构建代码
pnpm build        # 输出至 dist/
pnpm build:lambda # 构建 lambda 及 layer

# 部署流程封装
pnpm sam:build
pnpm sam:deploy

# 查看线上日志
pnpm sam:logs
```

## 关键文件说明

- `src/lambda.ts`：Lambda 入口（Fastify 适配）。
- `template.yaml`：SAM 模板，声明函数、Layer、VPC、API Gateway 等资源。
- `samconfig.toml`：SAM CLI 部署配置（区域、S3、参数覆盖等）。
- `.env.production`：根据模板生成的生产环境变量文件，勿提交真实敏感信息。

## API 访问

部署成功后，API 访问地址格式如下：
```
https://{api-id}.execute-api.{region}.amazonaws.com/prod/{endpoint}
```
请根据业务路由补全 `{endpoint}`。
