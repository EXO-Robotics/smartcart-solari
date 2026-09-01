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

test('all authoritative versioned schemas compile', async () => {
  const validator = await createContractValidator({ contractsRoot });
  assert.equal(validator.schemaIds.length, 39);
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

test('handoff creation result requires HTTPS /t with a fragment bearer and no query', async () => {
  const validator = await createContractValidator({ contractsRoot });
  const schemaId = 'https://schemas.smartcart.app/v1/handoff/smartcart-handoff-create-result.schema.json';
  const result = {
    schemaVersion: '1.0',
    resolverVersion: 'smartcart-handoff-v1',
    requestId: '30000000-0000-4000-8000-000000000001',
    data: {
      claimUrl: 'https://smartcart.example/t#v1.ABC_def-123',
      expiresAt: '2026-08-19T12:10:00.000Z'
    }
  };

  assert.equal(validator.validate(schemaId, result).valid, true);
  for (const claimUrl of [
    'http://smartcart.example/t#v1.ABC_def-123',
    'https://user@smartcart.example/t#v1.ABC_def-123',
    'https://smartcart.example/other#v1.ABC_def-123',
    'https://smartcart.example/t?token=v1.ABC_def-123',
    'https://smartcart.example/t?source=gpt#v1.ABC_def-123',
    'https://smartcart.example/t',
    'https://smartcart.example/t#ABC_def-123'
  ]) {
    const invalid = structuredClone(result);
    invalid.data.claimUrl = claimUrl;
    assert.equal(
      validator.validate(schemaId, invalid).valid,
      false,
      `Expected the handoff contract to reject ${claimUrl}`
    );
  }
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
