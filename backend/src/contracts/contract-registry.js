import { readFile, readdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const moduleDirectory = path.dirname(fileURLToPath(import.meta.url));

export const defaultContractsRoot = path.resolve(
  moduleDirectory,
  '../../../contracts'
);

async function jsonFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = [];

  for (const entry of entries.sort((lhs, rhs) => lhs.name.localeCompare(rhs.name))) {
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...await jsonFiles(entryPath));
    } else if (entry.isFile() && entry.name.endsWith('.schema.json')) {
      files.push(entryPath);
    }
  }

  return files;
}

export async function loadContractSchemas({ contractsRoot = defaultContractsRoot } = {}) {
  const versions = (await readdir(contractsRoot, { withFileTypes: true }))
    .filter((entry) => entry.isDirectory() && /^v\d+$/.test(entry.name))
    .map((entry) => entry.name)
    .sort();
  const files = (await Promise.all(versions.map((version) => jsonFiles(path.join(contractsRoot, version))))).flat();
  const schemas = [];

  for (const file of files) {
    const schema = JSON.parse(await readFile(file, 'utf8'));
    if (typeof schema.$id !== 'string' || schema.$id.length === 0) {
      throw new Error(`Contract schema is missing a stable $id: ${file}`);
    }
    schemas.push({ file, schema });
  }

  return schemas;
}
