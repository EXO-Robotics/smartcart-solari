import {
  CANONICAL_REQUIREMENTS,
  controlledDemoProductURL,
  WALMART_PRODUCT_URLS
} from './constants.js';
import { SolariResearchError } from './errors.js';
import { lookup as dnsLookup } from 'node:dns/promises';
import { isIP } from 'node:net';

function normalizedURL(value) {
  let url;
  try { url = new URL(value); } catch {
    throw new SolariResearchError('candidate_url_not_allowed', 'Candidate URL is not valid.', { status: 400 });
  }
  if (url.username || url.password || url.search || url.hash) {
    throw new SolariResearchError('candidate_url_not_allowed', 'Candidate URL contains disallowed components.', { status: 400 });
  }
  return url.href;
}

export function assertAllowedCandidateURL({ retailerID, productID, sourceURL, demoRetailerBaseURL }) {
  const supplied = normalizedURL(sourceURL);
  let expected;
  if (retailerID === 'walmart') {
    expected = WALMART_PRODUCT_URLS[productID];
  } else if (retailerID === 'smartcart-demo-grocer' && demoRetailerBaseURL) {
    expected = controlledDemoProductURL(demoRetailerBaseURL, productID);
  }
  if (!expected || supplied !== normalizedURL(expected)) {
    throw new SolariResearchError(
      'candidate_url_not_allowed',
      'Candidate URL is outside the exact retailer/product allowlist.',
      { status: 400 }
    );
  }
  return supplied;
}

function isPrivateAddress(address) {
  const lower = address.toLowerCase();
  if (lower === '::' || lower === '::1' || lower.startsWith('fc') || lower.startsWith('fd') || lower.startsWith('fe8') || lower.startsWith('fe9') || lower.startsWith('fea') || lower.startsWith('feb')) return true;
  const mapped = /^::ffff:(\d+\.\d+\.\d+\.\d+)$/.exec(lower);
  const ipv4 = mapped?.[1] ?? (isIP(address) === 4 ? address : null);
  if (!ipv4) return false;
  const [a, b] = ipv4.split('.').map(Number);
  return a === 0 || a === 10 || a === 127 || (a === 100 && b >= 64 && b <= 127)
    || (a === 169 && b === 254) || (a === 172 && b >= 16 && b <= 31)
    || (a === 192 && (b === 0 || b === 168)) || (a === 198 && (b === 18 || b === 19 || b === 51))
    || (a === 203 && b === 0) || a >= 224;
}

export async function assertPublicDemoBaseURL(baseURL, { lookup = dnsLookup } = {}) {
  let url;
  try { url = new URL(baseURL); } catch {
    throw new SolariResearchError('controlled_demo_url_invalid', 'Controlled Demo Grocer base URL is invalid.', { status: 503 });
  }
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || (url.port && url.port !== '443')) {
    throw new SolariResearchError('controlled_demo_url_invalid', 'Controlled Demo Grocer must use a credential-free public HTTPS origin.', { status: 503 });
  }
  if (isIP(url.hostname) || url.hostname === 'localhost' || !url.hostname.includes('.')) {
    throw new SolariResearchError('controlled_demo_url_private', 'Controlled Demo Grocer cannot target an IP, localhost, or private host.', { status: 503 });
  }
  let addresses;
  try { addresses = await lookup(url.hostname, { all: true, verbatim: true }); } catch {
    throw new SolariResearchError('controlled_demo_dns_failed', 'Controlled Demo Grocer hostname could not be resolved.', { status: 503, retryable: true });
  }
  if (!addresses.length || addresses.some(({ address }) => isPrivateAddress(address))) {
    throw new SolariResearchError('controlled_demo_url_private', 'Controlled Demo Grocer resolved to a non-public address.', { status: 503 });
  }
  return url.href;
}

function approximatelyEqual(lhs, rhs) {
  return Math.abs(lhs - rhs) <= 0.0001 * Math.max(1, Math.abs(lhs), Math.abs(rhs));
}

export function assertCanonicalDemoRequest(request, { demoRetailerBaseURL } = {}) {
  if (request.demoID !== 'chicken-parmesan-pasta-v1' || request.requirements.length !== 3) {
    throw new SolariResearchError('demo_scope_not_allowed', 'Only the bounded Chicken Parmesan Pasta demo is supported.', { status: 400 });
  }
  const requirementIDs = request.requirements.map(({ id }) => id.toLowerCase());
  const ingredientIDs = request.requirements.map(({ ingredientID }) => ingredientID.toLowerCase());
  if (new Set(requirementIDs).size !== request.requirements.length || new Set(ingredientIDs).size !== request.requirements.length) {
    throw new SolariResearchError('duplicate_requirement_identity', 'Requirement and ingredient IDs must be unique.', { status: 400 });
  }
  const seenProducts = new Set();
  for (const canonical of CANONICAL_REQUIREMENTS) {
    const requirement = request.requirements.find((item) => {
      const normalized = item.name.toLowerCase();
      return canonical.key === 'chicken' ? normalized.includes('chicken')
        : canonical.key === 'penne' ? normalized.includes('penne') || normalized.includes('pasta')
          : normalized.includes('parmesan');
    });
    if (!requirement || !approximatelyEqual(requirement.requiredQuantity, canonical.requiredQuantity) || requirement.unit !== canonical.unit) {
      throw new SolariResearchError('demo_requirements_mismatch', 'Requirements do not match the reviewed post-pantry demo quantities.', { status: 400 });
    }
    const submittedIDs = requirement.candidates.map((candidate) => candidate.retailerProductID).sort();
    const expectedIDs = [...canonical.productIDs].sort();
    if (JSON.stringify(submittedIDs) !== JSON.stringify(expectedIDs)) {
      throw new SolariResearchError('demo_candidates_mismatch', 'Candidates do not match the reviewed demo allowlist.', { status: 400 });
    }
    for (const candidate of requirement.candidates) {
      if (seenProducts.has(candidate.retailerProductID)) {
        throw new SolariResearchError('duplicate_candidate', 'Candidate product IDs must be unique.', { status: 400 });
      }
      seenProducts.add(candidate.retailerProductID);
      assertAllowedCandidateURL({
        retailerID: request.retailerID,
        productID: candidate.retailerProductID,
        sourceURL: candidate.sourceURL,
        demoRetailerBaseURL
      });
    }
  }
  return request;
}
