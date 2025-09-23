import { promises as fs } from 'node:fs';
import { join, dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(__dirname, '..');
const layerRoot = join(projectRoot, 'layer');
const layerNodeModulesDir = join(layerRoot, 'nodejs');

const runtimeDependencies = [
  '@nestjs/common',
  '@nestjs/core',
  '@nestjs/platform-express',
  '@vendia/serverless-express',
  '@prisma/client',
  'axios',
  'express',
  'reflect-metadata',
  'rxjs',
];

const packageJsonPath = join(projectRoot, 'package.json');
const nodeModulesDir = join(projectRoot, 'node_modules');
const prismaDir = join(projectRoot, 'prisma');

async function pathExists(path) {
  try {
    await fs.access(path);
    return true;
  } catch (error) {
    return false;
  }
}

async function readJSON(path) {
  const file = await fs.readFile(path, 'utf8');
  return JSON.parse(file);
}

async function resolveDependencyVersions(rootPackageJson) {
  const dependencies = {};

  for (const dependencyName of runtimeDependencies) {
    const specifier = rootPackageJson.dependencies?.[dependencyName];

    if (!specifier) {
      console.warn(`⚠️  Skipping ${dependencyName} because it is not declared in package.json`);
      continue;
    }

    const installedPackageJsonPath = join(nodeModulesDir, dependencyName, 'package.json');
    let resolvedVersion = specifier;

    if (await pathExists(installedPackageJsonPath)) {
      const installedPackageJson = await readJSON(installedPackageJsonPath);
      resolvedVersion = installedPackageJson.version;
    } else if (/^[~^]/.test(resolvedVersion)) {
      resolvedVersion = resolvedVersion.replace(/^[~^]/, '');
    }

    dependencies[dependencyName] = resolvedVersion;
  }

  return dependencies;
}

async function writeLayerPackageJson(dependencies) {
  const layerPackageJson = {
    name: 'nest-lambda-runtime',
    private: true,
    version: '1.0.0',
    dependencies,
  };

  await fs.mkdir(layerNodeModulesDir, { recursive: true });
  await fs.writeFile(
    join(layerNodeModulesDir, 'package.json'),
    `${JSON.stringify(layerPackageJson, null, 2)}\n`,
    'utf8',
  );
}

async function copyPrismaSchema() {
  if (!(await pathExists(prismaDir))) {
    return;
  }

  await fs.cp(prismaDir, join(layerNodeModulesDir, 'prisma'), {
    recursive: true,
  });
}

async function main() {
  await fs.rm(layerRoot, { recursive: true, force: true });

  const rootPackageJson = await readJSON(packageJsonPath);
  const dependencies = await resolveDependencyVersions(rootPackageJson);

  await writeLayerPackageJson(dependencies);
  await copyPrismaSchema();
}

await main();
