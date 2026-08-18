import { randomUUID } from 'node:crypto';

export class HttpError extends Error {
  constructor(status, code, message, details) {
    super(message);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

export function requestId(request) {
  const supplied = request.headers['x-request-id'];
  return typeof supplied === 'string' && /^[A-Za-z0-9._-]{1,100}$/.test(supplied)
    ? supplied
    : randomUUID();
}

export function sendJson(response, status, payload, headers = {}) {
  const body = JSON.stringify(payload);
  response.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    'x-frame-options': 'DENY',
    'referrer-policy': 'no-referrer',
    'x-smartcart-data-mode': 'local-demo',
    ...headers
  });
  response.end(body);
}

export async function readJson(request, maxBytes) {
  const contentType = request.headers['content-type'] ?? '';
  if (!contentType.toLowerCase().startsWith('application/json')) {
    throw new HttpError(415, 'unsupported_media_type', 'Content-Type must be application/json');
  }

  let size = 0;
  const chunks = [];
  for await (const chunk of request) {
    size += chunk.length;
    if (size > maxBytes) throw new HttpError(413, 'payload_too_large', 'JSON body is too large');
    chunks.push(chunk);
  }
  if (chunks.length === 0) throw new HttpError(400, 'empty_body', 'A JSON body is required');
  try {
    const parsed = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error('object required');
    }
    return parsed;
  } catch {
    throw new HttpError(400, 'invalid_json', 'Body must be a valid JSON object');
  }
}

export function validatePreparsedJsonBody(request, body, maxBytes) {
  const contentType = request.headers['content-type'] ?? '';
  if (!contentType.toLowerCase().startsWith('application/json')) {
    throw new HttpError(415, 'unsupported_media_type', 'Content-Type must be application/json');
  }
  if (!body || typeof body !== 'object' || Array.isArray(body)) {
    throw new HttpError(400, 'invalid_json', 'Body must be a valid JSON object');
  }

  const declaredBytes = Number(request.headers['content-length']);
  const normalizedBytes = Buffer.byteLength(JSON.stringify(body));
  if (
    (Number.isFinite(declaredBytes) && declaredBytes > maxBytes)
    || normalizedBytes > maxBytes
  ) {
    throw new HttpError(413, 'payload_too_large', 'JSON body is too large');
  }
  return body;
}

export function assertString(value, name, { min = 1, max = 500 } = {}) {
  if (typeof value !== 'string' || value.trim().length < min || value.length > max) {
    throw new HttpError(400, 'validation_error', `${name} must be a string from ${min} to ${max} characters`);
  }
  return value.trim();
}

export function localDemoMeta(extra = {}) {
  return {
    dataMode: 'local-demo',
    persistence: 'ephemeral-in-memory',
    auth: 'mock-local-demo',
    catalog: 'local-demo-or-client-supplied-never-live',
    ...extra
  };
}
