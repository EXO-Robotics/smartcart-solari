import { randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { isIP } from 'node:net';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { controlledDemoProductURL } from '../src/solari/constants.js';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const canonicalRequestPath = path.resolve(
  scriptDirectory,
  '../../contracts/fixtures/v1/solari/chicken-parmesan-walmart-request.json'
);

export function assertGeneratorBaseURL(value) {
  let url;
  try { url = new URL(value); } catch { throw new Error('--base-url must be a valid public HTTPS URL'); }
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || (url.port && url.port !== '443')) {
    throw new Error('--base-url must be a credential-free public HTTPS origin/path without query or fragment');
  }
  if (isIP(url.hostname) || url.hostname === 'localhost' || !url.hostname.includes('.')) {
    throw new Error('--base-url must use a public hostname, not an IP or local host');
  }
  url.pathname = url.pathname.replace(/\/+$/, '');
  return url.href;
}

export async function buildSolariDemoRequest(baseURL, {
  now = () => new Date(),
  uuid = randomUUID
} = {}) {
  const admittedBaseURL = assertGeneratorBaseURL(baseURL);
  const request = JSON.parse(await readFile(canonicalRequestPath, 'utf8'));
  request.requestID = uuid();
  request.submittedAt = now().toISOString();
  request.retailerID = 'smartcart-demo-grocer';
  request.executionMode = 'live';
  request.storeReference = 'smartcart-demo-grocer-controlled';
  for (const requirement of request.requirements) {
    for (const candidate of requirement.candidates) {
      candidate.sourceURL = controlledDemoProductURL(admittedBaseURL, candidate.retailerProductID);
    }
  }
  return request;
}

async function main(argv) {
  const index = argv.indexOf('--base-url');
  if (index < 0 || !argv[index + 1] || argv.length !== 2) {
    throw new Error('Usage: npm run build:solari-demo-request -- --base-url https://your-host/solari-demo');
  }
  const request = await buildSolariDemoRequest(argv[index + 1]);
  process.stdout.write(`${JSON.stringify(request, null, 2)}\n`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
