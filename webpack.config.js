const path = require('path');

// Layer中的依赖，这些会被从函数包中排除
const layerDependencies = [
  '@nestjs/common',
  '@nestjs/core',
  '@nestjs/platform-express',
  '@vendia/serverless-express',
  'express',
  'reflect-metadata',
  'rxjs',
];

// 函数包中保留的依赖
const functionDependencies = [
  '@prisma/client',
  'pg',
  'axios',
  '@supabase/supabase-js',
  '@types/aws-lambda',
  '@types/pg',
];

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
  externals: [
    ({ request }, callback) => {
      // 排除layer中的依赖，让Lambda运行时从layer加载
      if (layerDependencies.includes(request)) {
        return callback(null, `commonjs ${request}`);
      }
      // 对于函数特定的依赖，也排除但稍后会手动复制
      if (functionDependencies.includes(request)) {
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
  plugins: [],
  optimization: {
    minimize: false, // 保持可读性，Lambda冷启动时间影响不大
  },
  devtool: false, // 移除source maps减少包大小
};