import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { createContractValidator } from '../src/contracts/contract-validator.js';

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const contractsRoot = path.resolve(testDirectory, '../../contracts');
const fixtureRoot = path.join(contractsRoot, 'fixtures/v1');

async function readJson(file) {
  return JSON.parse(await readFile(file, 'utf8'));
}

test('all authoritative v1 schemas compile', async () => {
  const validator = await createContractValidator({ contractsRoot });
  assert.equal(validator.schemaIds.length, 14);
  assert.equal(new Set(validator.schemaIds).size, validator.schemaIds.length);
});

test('every golden fixture satisfies its authoritative contract', async () => {
  const validator = await createContractValidator({ contractsRoot });
  const index = await readJson(path.join(fixtureRoot, 'fixture-index.json'));

  for (const entry of index) {
    const value = await readJson(path.join(fixtureRoot, entry.path));
    const result = validator.validate(entry.schemaId, value);
    assert.equal(result.valid, true, `${entry.path}: ${JSON.stringify(result.errors)}`);
  }
});

test('numeric estimate ordering is enforced beyond basic JSON shape', async () => {
  const validator = await createContractValidator({ contractsRoot });
  const result = validator.validate(
    'https://schemas.smartcart.app/v1/common/numeric-estimate.schema.json',
    { preferred: 20, minimum: 30, maximum: 10 }
  );

  assert.equal(result.valid, false);
});

test('retailer query is emitted only for a safe canonical identity', async () => {
  const validator = await createContractValidator({ contractsRoot });
  const identity = await readJson(path.join(fixtureRoot, 'chicken-parmesan/identity-output.json'));

  const unsafeWithQuery = structuredClone(identity);
  unsafeWithQuery.data.safeForRetailerQuery = false;
  assert.equal(
    validator.validate(
      'https://schemas.smartcart.app/v1/ingredient/ingredient-identity.schema.json',
      unsafeWithQuery
    ).valid,
    false
  );

  const safeWithoutCanonicalName = structuredClone(identity);
  safeWithoutCanonicalName.data.canonicalName = null;
  assert.equal(
    validator.validate(
      'https://schemas.smartcart.app/v1/ingredient/ingredient-identity.schema.json',
      safeWithoutCanonicalName
    ).valid,
    false
  );
});

test('semantic quantity remains nonnumeric and contract-valid', async () => {
  const validator = await createContractValidator({ contractsRoot });
  const ingredient = await readJson(
    path.join(fixtureRoot, 'semantic-quantity/ingredient-input.json')
  );

  assert.deepEqual(ingredient.quantity, { kind: 'semantic', text: 'as needed' });
  assert.equal('value' in ingredient.quantity, false);
  validator.assert(
    'https://schemas.smartcart.app/v1/ingredient/ingredient-input.schema.json',
    ingredient
  );
});
