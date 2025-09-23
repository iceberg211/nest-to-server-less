const path = require('path');

// 这些依赖会随 Lambda Layer 部署，避免被打包进函数代码
const layerDependencies = [
  '@nestjs/common',
  '@nestjs/core',
  '@nestjs/platform-express',
  '@vendia/serverless-express',
  'express',
  'reflect-metadata',
  'rxjs',
];

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
  externals: [
    ({ request }, callback) => {
      if (request && externalDependencies.has(request)) {
        return callback(null, `commonjs ${request}`);
      }
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
  plugins: [],
  optimization: {
    minimize: false, // 保持可读性，Lambda冷启动时间影响不大
  },
  devtool: false, // 移除source maps减少包大小
};
