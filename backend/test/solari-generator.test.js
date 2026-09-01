import assert from 'node:assert/strict';
import test from 'node:test';
import { createContractValidator } from '../src/contracts/contract-validator.js';
import { SOLARI_REQUEST_SCHEMA_ID } from '../src/solari/constants.js';
import { assertGeneratorBaseURL, buildSolariDemoRequest } from '../scripts/build-solari-demo-request.mjs';

test('Demo Grocer live request generator emits the exact bounded v1 contract', async () => {
  const request = await buildSolariDemoRequest('https://submission.example/solari-demo/', {
    now: () => new Date('2026-09-01T12:00:00Z'),
    uuid: () => '40000000-0000-4000-8000-000000000001'
  });
  const validator = await createContractValidator();
  assert.equal(validator.validate(SOLARI_REQUEST_SCHEMA_ID, request).valid, true);
  assert.equal(request.executionMode, 'live');
  assert.equal(request.retailerID, 'smartcart-demo-grocer');
  assert.equal(request.requirements.flatMap((item) => item.candidates).length, 6);
  assert.ok(request.requirements.flatMap((item) => item.candidates).every((candidate) =>
    candidate.sourceURL === `https://submission.example/solari-demo/retailer/product/${candidate.retailerProductID}.html`
  ));
});

test('Demo Grocer generator rejects credentials, non-HTTPS, private hosts, query, and fragment', () => {
  for (const value of [
    'http://submission.example/solari-demo',
    'https://user:secret@submission.example/solari-demo',
    'https://127.0.0.1/solari-demo',
    'https://localhost/solari-demo',
    'https://submission.example/solari-demo?redirect=evil',
    'https://submission.example/solari-demo#fragment'
  ]) assert.throws(() => assertGeneratorBaseURL(value));
});
