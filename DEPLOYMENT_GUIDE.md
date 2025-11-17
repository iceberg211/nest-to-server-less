# NestJS Lambda 部署核心问题总结

> 本文档针对 NestJS 部署到 AWS Lambda 时最容易遇到的两个核心问题进行总结

---

## 问题一：Lambda Layer 体积过大

### 问题描述
Lambda Layer 限制 **250MB** (解压后)，如果 Webpack 配置不当，会把所有依赖都打包进 Function 代码，导致：
- 部署包超过大小限制
- 冷启动时间过长
- 部署速度慢

### 解决方案：Webpack Externals 配置

**核心思路**：将依赖分为两部分
- **Layer**：框架依赖（NestJS、Express、RxJS）—— 不常变动，可复用
- **Function**：业务代码 + Prisma Client —— 频繁变动

#### Webpack 配置文件 (`webpack.config.js`)

```javascript
const path = require('path');

// 这些依赖放在 Layer 中，不打包进 Function
const layerDependencies = [
  '@nestjs/common',
  '@nestjs/core',
  '@nestjs/platform-express',
  '@vendia/serverless-express',
  'express',
  'reflect-metadata',
  'rxjs',
];

// Prisma 也标记为 external（后续手动复制到 dist）
const externalDependencies = new Set([
  ...layerDependencies,
  '@prisma/client',
]);

module.exports = {
  entry: {
    lambda: './src/lambda.ts',
  },
  target: 'node',
  mode: 'production',
  output: {
    path: path.resolve(__dirname, 'dist'),
    filename: 'lambda.js',
    libraryTarget: 'commonjs2',
    clean: true,
  },
  resolve: {
    extensions: ['.ts', '.js'],
  },
  // 关键配置：externals
  externals: [
    ({ request }, callback) => {
      if (request && externalDependencies.has(request)) {
        // 标记为外部依赖，不打包
        return callback(null, `commonjs ${request}`);
      }
      // Prisma 的子路径也要排除
      if (request && request.startsWith('@prisma/client/')) {
        return callback(null, `commonjs ${request}`);
      }
      callback();
    },
  ],
  module: {
    rules: [
      {
        test: /\.tsx?$/,
        exclude: [/node_modules/, /\.spec\.ts$/, /test/],
        use: {
          loader: 'ts-loader',
          options: {
            transpileOnly: true,
            experimentalWatchApi: true,
          },
        },
      },
    ],
  },
  optimization: {
    minimize: false,  // Lambda 对体积不如冷启动敏感
  },
  devtool: false,
};
```

### 关键配置说明

#### 1. `externals` 函数
```javascript
externals: [
  ({ request }, callback) => {
    if (externalDependencies.has(request)) {
      // 返回 'commonjs xxx' 表示：运行时从外部加载（Layer）
      return callback(null, `commonjs ${request}`);
    }
    // 不匹配的继续打包进 Function
    callback();
  },
]
```

**效果**：
- ✅ Webpack 不会把 `@nestjs/common` 等打包进 `dist/lambda.js`
- ✅ Lambda 运行时从 Layer 的 `/opt/nodejs/node_modules` 加载
- ✅ Function 代码体积降至 **2-5MB**（vs 50MB+）

#### 2. 为什么 `@prisma/client` 也要 external？
```javascript
// Prisma Client 包含二进制引擎，不能被 Webpack 打包
'@prisma/client'
```

**构建流程中手动复制**（`deploy.sh:98-102`）：
```bash
npx prisma generate
mkdir -p dist/node_modules/@prisma dist/node_modules/.prisma
cp -R node_modules/@prisma/client dist/node_modules/@prisma/
cp -R node_modules/.prisma/client dist/node_modules/.prisma/
```

#### 3. Layer 打包策略（`deploy.sh:49-73`）

```bash
# 1. 创建 layer/nodejs/package.json（只包含框架依赖）
cat > layer/nodejs/package.json <<'JSON'
{
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

# 2. 安装依赖到 layer
cd layer/nodejs
npm install --production

# 3. 裁剪体积（删除测试文件、文档、TS 源码）
find node_modules -type d \
  \( -name 'test' -o -name 'docs' -o -name 'examples' \) \
  -prune -exec rm -rf '{}' +
find node_modules -type f \
  \( -name '*.md' -o -name '*.map' -o -name '*.ts' ! -name '*.d.ts' \) \
  -delete
```

### 体积对比

| 配置 | Function 大小 | Layer 大小 | 冷启动时间 |
|-----|--------------|-----------|-----------|
| ❌ 未配置 externals | ~80MB | 0 | 5-8 秒 |
| ✅ 配置 externals | ~3MB | ~30MB | 2-3 秒 |

---

## 问题二：SAM Template 编写

### 问题描述
SAM template.yaml 是 CloudFormation 的简化版，需要理解：
- Lambda Function 与 API Gateway 的关系
- VPC 配置（访问 RDS）
- Layer 的引用方式
- 环境变量传递

### 核心配置解析 (`template.yaml`)

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Description: NestJS Serverless Application

# Globals: 所有 Lambda 函数的公共配置
Globals:
  Function:
    Runtime: nodejs20.x
    Timeout: 30              # API 响应时间一般 < 10s，留 30s 缓冲
    MemorySize: 512          # 内存越大，CPU 越强，建议 512-1024
    Environment:
      Variables:
        NODE_ENV: production
    # VPC 配置（访问 RDS 必须）
    VpcConfig:
      SecurityGroupIds:
        - sg-06148d712037fec50       # 预先创建的 RDS 安全组
        - !Ref LambdaSecurityGroup   # 动态创建的 Lambda 安全组
      SubnetIds:                     # 必须是私有子网（有 NAT Gateway）
        - subnet-007500d7eb02d5a9c
        - subnet-0144f82913769dc0d
        - subnet-08e2157684a078b3b
        - subnet-006a57796b978d0fa
    # 引用 Layer
    Layers:
      - !Ref DependenciesLayer       # 引用下面定义的 Layer

# 参数：可在部署时覆盖
Parameters:
  DatabaseUrl:
    Type: String
    Description: Aurora PostgreSQL connection URL
    NoEcho: true                     # 不在控制台显示
    Default: "postgresql://..."      # 默认值

Resources:
  # 资源 1: Lambda 安全组
  LambdaSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security group for Lambda functions
      VpcId: vpc-0b4bc13cd4ef012cb
      SecurityGroupEgress:
        - IpProtocol: -1             # -1 表示所有协议
          CidrIp: 0.0.0.0/0          # 允许所有出站流量（访问 RDS）

  # 资源 2: Lambda Layer
  DependenciesLayer:
    Type: AWS::Serverless::LayerVersion
    Properties:
      LayerName: nestjs-dependencies
      ContentUri: layer/             # 指向 layer/ 目录
      CompatibleRuntimes:
        - nodejs20.x
      RetentionPolicy: Delete        # 删除 Stack 时删除 Layer

  # 资源 3: NestJS 主函数
  NestJSFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: dist/                 # 指向 dist/ 目录
      Handler: lambda.handler        # 文件名.导出函数名
      # 关键：API Gateway 集成
      Events:
        ApiEvent:
          Type: Api
          Properties:
            Path: /{proxy+}          # 代理所有子路径
            Method: ANY              # 所有 HTTP 方法
            RestApiId: !Ref ApiGateway
        RootEvent:
          Type: Api
          Properties:
            Path: /                  # 根路径也要代理
            Method: ANY
            RestApiId: !Ref ApiGateway
      Environment:
        Variables:
          DATABASE_URL: !Ref DatabaseUrl  # 引用参数

  # 资源 4: 定时预热函数（防止冷启动）
  WarmupFunction:
    Type: AWS::Serverless::Function
    Properties:
      CodeUri: dist/
      Handler: lambda.warmup         # 可以是空函数
      Events:
        WarmupEvent:
          Type: Schedule
          Properties:
            Schedule: rate(5 minutes)  # 每 5 分钟触发一次

  # 资源 5: API Gateway
  ApiGateway:
    Type: AWS::Serverless::Api
    Properties:
      Name: NestJS-API
      StageName: prod
      # CORS 配置
      Cors:
        AllowMethods: "'GET,POST,PUT,DELETE,OPTIONS'"
        AllowHeaders: "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
        AllowOrigin: "'*'"
      # 支持二进制响应（图片、PDF 等）
      BinaryMediaTypes:
        - "*/*"

# 输出：部署后显示的信息
Outputs:
  ApiUrl:
    Description: URL of the API Gateway
    Value: !Sub "https://${ApiGateway}.execute-api.${AWS::Region}.amazonaws.com/prod"
  LambdaSecurityGroupId:
    Description: Security group associated with Lambda functions
    Value: !Ref LambdaSecurityGroup
  DependenciesLayerArn:
    Description: ARN of the shared Lambda layer
    Value: !Ref DependenciesLayer
```

---

## 关键配置项详解

### 1. VPC 配置（最容易出错）

```yaml
VpcConfig:
  SecurityGroupIds:
    - sg-xxx              # RDS 的安全组（入站规则允许 Lambda SG）
    - !Ref LambdaSG       # Lambda 的安全组（出站规则允许所有）
  SubnetIds:
    - subnet-xxx          # 必须是私有子网
    - subnet-yyy          # 建议多可用区（高可用）
```

**常见问题**：
- ❌ 使用公有子网 → Lambda 无法访问 RDS（RDS 在私有子网）
- ❌ 安全组规则未配置 → 超时错误
- ✅ 确保 RDS 安全组允许来自 Lambda 安全组的 5432 端口入站

**验证方法**：
```bash
# 在 RDS 安全组中添加入站规则
Type: PostgreSQL
Protocol: TCP
Port: 5432
Source: sg-{lambda-security-group-id}
```

### 2. API Gateway 代理配置

```yaml
Events:
  ApiEvent:
    Type: Api
    Properties:
      Path: /{proxy+}     # {proxy+} 匹配所有子路径
      Method: ANY         # 支持 GET/POST/PUT/DELETE 等
      RestApiId: !Ref ApiGateway
```

**路由示例**：
- `GET /api/form-data` → Lambda (`event.path = '/api/form-data'`)
- `POST /api/github/user` → Lambda (`event.path = '/api/github/user'`)
- Express 在 Lambda 内部处理路由逻辑

### 3. Layer 引用

```yaml
Layers:
  - !Ref DependenciesLayer   # CloudFormation 引用
```

**运行时加载路径**：
- Layer 内容会被解压到 `/opt/`
- Node.js 自动从 `/opt/nodejs/node_modules` 加载依赖

**验证方法**：
```javascript
// Lambda 中可以直接 require
const { Injectable } = require('@nestjs/common');  // 从 Layer 加载
```

### 4. 环境变量传递

```yaml
Parameters:
  DatabaseUrl:
    Type: String
    NoEcho: true
    Default: "postgresql://..."

Resources:
  NestJSFunction:
    Environment:
      Variables:
        DATABASE_URL: !Ref DatabaseUrl  # 引用参数
```

**部署时覆盖**：
```bash
sam deploy --parameter-overrides "DatabaseUrl=postgresql://new-url"
```

---

## 部署流程总结

```bash
# 1. Webpack 打包（排除 Layer 依赖）
npx webpack --config webpack.config.js
# 输出：dist/lambda.js (~3MB)

# 2. 构建 Layer（只包含框架依赖）
mkdir -p layer/nodejs
cd layer/nodejs && npm install @nestjs/common @nestjs/core ...
# 输出：layer/nodejs/node_modules/ (~30MB)

# 3. 手动复制 Prisma Client
npx prisma generate
cp -R node_modules/@prisma/client dist/node_modules/@prisma/

# 4. SAM 构建（打包 ZIP）
sam build
# 输出：.aws-sam/build/NestJSFunction/（Function 代码）
#       .aws-sam/build/DependenciesLayer/（Layer 代码）

# 5. SAM 部署（上传 S3 + CloudFormation 部署）
sam deploy --parameter-overrides "DatabaseUrl=xxx"
```

---

## 常见错误排查

| 错误 | 原因 | 解决方法 |
|-----|------|---------|
| `Cannot find module '@nestjs/common'` | Webpack 未配置 externals | 检查 `webpack.config.js` |
| `Task timed out after 30 seconds` | VPC 配置错误 | 检查安全组规则和子网路由表 |
| `Unzipped size must be smaller than 262144000 bytes` | Layer 体积过大 | 裁剪 `node_modules`（删除测试文件） |
| `PrismaClientInitializationError` | Binary target 不匹配 | 添加 `binaryTargets: ["rhel-openssl-3.0.x"]` |

---

## 最佳实践

1. **Webpack Externals**：将不常变的依赖放 Layer，业务代码放 Function
2. **Layer 裁剪**：删除 `.md`、`test/`、`examples/`，减少 50% 体积
3. **VPC 配置**：Lambda 使用私有子网 + NAT Gateway
4. **安全组规则**：RDS 入站允许 Lambda SG 的 5432 端口
5. **Warmup Function**：每 5 分钟触发，保持实例热启动
6. **环境变量**：敏感信息使用 `NoEcho: true` 和 Parameter Overrides

---

## 快速部署命令

```bash
# 一键部署（自动完成上述所有步骤）
pnpm run deploy:aws

# 或分步执行
pnpm build:lambda     # 构建 Lambda 包
sam build             # SAM 打包
sam deploy            # 部署到 AWS
```

---

**总结**：Lambda Layer 体积问题的核心是 Webpack Externals 配置，SAM Template 的核心是理解 VPC/Layer/API Gateway 的集成关系。掌握这两点，NestJS 部署到 Lambda 就会很顺利。
