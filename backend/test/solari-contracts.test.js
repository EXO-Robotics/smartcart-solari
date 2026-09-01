import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { createContractValidator } from '../src/contracts/contract-validator.js';
import {
  SOLARI_DECISION_SCHEMA_ID,
  SOLARI_OBSERVATION_SCHEMA_ID,
  SOLARI_REQUEST_SCHEMA_ID,
  SOLARI_RESULT_SCHEMA_ID
} from '../src/solari/constants.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../contracts');
const fixtureRoot = path.join(root, 'fixtures/v1/solari');

async function fixture(name) {
  return JSON.parse(await readFile(path.join(fixtureRoot, name), 'utf8'));
}

test('Solari v1 contracts compile and canonical request/result fixtures validate', async () => {
  const validator = await createContractValidator({ contractsRoot: root });
  const request = await fixture('chicken-parmesan-walmart-request.json');
  const result = await fixture('chicken-parmesan-walmart-result.json');
  assert.equal(validator.validate(SOLARI_REQUEST_SCHEMA_ID, request).valid, true);
  assert.equal(validator.validate(SOLARI_RESULT_SCHEMA_ID, result).valid, true);
  for (const observation of result.observations) validator.assert(SOLARI_OBSERVATION_SCHEMA_ID, observation);
  for (const decision of result.decisions) validator.assert(SOLARI_DECISION_SCHEMA_ID, decision);
  assert.equal(result.basket.observedSubtotal, 12.79);
  assert.deepEqual(result.decisions.map((item) => item.observationID), [
    'obs-walmart-10414680', 'obs-walmart-10534084', 'obs-walmart-10452414'
  ]);
});

test('contracts preserve unknown price as null and reject unversioned or expansive input', async () => {
  const validator = await createContractValidator({ contractsRoot: root });
  const result = await fixture('chicken-parmesan-walmart-result.json');
  const partial = structuredClone(result);
  partial.status = 'partial';
  partial.observations[0].visiblePrice = null;
  partial.observations[0].currency = null;
  partial.decisions[0].lineTotal = null;
  partial.decisions[0].currency = null;
  partial.basket = {
    completeness: 'partial', observedSubtotal: 3.32, currency: 'USD',
    pricedLineCount: 2, missingPriceLineCount: 1, unmatchedRequirementCount: 0
  };
  assert.equal(validator.validate(SOLARI_RESULT_SCHEMA_ID, partial).valid, true);
  const badCurrency = structuredClone(partial.observations[0]);
  badCurrency.visiblePrice = 9.47;
  badCurrency.currency = null;
  assert.equal(validator.validate(SOLARI_OBSERVATION_SCHEMA_ID, badCurrency).valid, false);

  const unversioned = structuredClone(result.observations[0]);
  delete unversioned.schemaVersion;
  assert.equal(validator.validate(SOLARI_OBSERVATION_SCHEMA_ID, unversioned).valid, false);
  const expansive = await fixture('chicken-parmesan-walmart-request.json');
  expansive.arbitraryURL = 'https://example.com';
  assert.equal(validator.validate(SOLARI_REQUEST_SCHEMA_ID, expansive).valid, false);
});

test('request and output contracts consistently admit uppercase UUID text', async () => {
  const validator = await createContractValidator({ contractsRoot: root });
  const request = await fixture('chicken-parmesan-walmart-request.json');
  const result = await fixture('chicken-parmesan-walmart-result.json');
  const uppercase = 'ABCDEFAB-CDEF-4ABC-8DEF-ABCDEFABCDEF';
  request.requirements[0].id = uppercase;
  result.observations[0].requirementID = uppercase;
  result.decisions[0].requirementID = uppercase;
  assert.equal(validator.validate(SOLARI_REQUEST_SCHEMA_ID, request).valid, true);
  assert.equal(validator.validate(SOLARI_RESULT_SCHEMA_ID, result).valid, true);
});
