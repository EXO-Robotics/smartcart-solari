import { lookup as dnsLookup } from 'node:dns/promises';
import { request as httpsRequest } from 'node:https';
import { BlockList, isIP } from 'node:net';
import { Readable } from 'node:stream';
import { HttpError } from '../lib/http.js';

const REDIRECT_STATUSES = new Set([301, 302, 303, 307, 308]);
const HTML_MIME_TYPES = new Set(['text/html', 'application/xhtml+xml']);
const BLOCKED_HOST_SUFFIXES = ['.localhost', '.local', '.internal', '.home', '.lan'];
const BLOCKED_ADDRESSES = new BlockList();

for (const [network, prefix] of [
  ['0.0.0.0', 8],
  ['10.0.0.0', 8],
  ['100.64.0.0', 10],
  ['127.0.0.0', 8],
  ['169.254.0.0', 16],
  ['172.16.0.0', 12],
  ['192.0.0.0', 24],
  ['192.0.2.0', 24],
  ['192.88.99.0', 24],
  ['192.168.0.0', 16],
  ['198.18.0.0', 15],
  ['198.51.100.0', 24],
  ['203.0.113.0', 24],
  ['224.0.0.0', 4],
  ['240.0.0.0', 4]
]) {
  BLOCKED_ADDRESSES.addSubnet(network, prefix, 'ipv4');
}

for (const [network, prefix] of [
  ['::', 128],
  ['::1', 128],
  ['64:ff9b::', 96],
  ['100::', 64],
  ['2001::', 32],
  ['2001:2::', 48],
  ['2001:10::', 28],
  ['2001:db8::', 32],
  ['2002::', 16],
  ['fc00::', 7],
  ['fe80::', 10],
  ['fec0::', 10],
  ['ff00::', 8]
]) {
  BLOCKED_ADDRESSES.addSubnet(network, prefix, 'ipv6');
}

export const SMARTCART_RECIPE_USER_AGENT =
  'SmartCartRecipePageFetcher/0.1 (user-requested recipe import)';

export class RecipePageError extends HttpError {
  constructor(status, code, message, details) {
    super(status, code, message, details);
    this.name = 'RecipePageError';
  }
}

function validateUrl(input, { redirect = false } = {}) {
  let url;
  try {
    url = new URL(input);
  } catch {
    throw new RecipePageError(400, 'invalid_recipe_page_url', 'Recipe page URL must be an absolute URL');
  }
  if (url.protocol !== 'https:') {
    throw new RecipePageError(
      400,
      redirect ? 'unsafe_recipe_page_redirect' : 'recipe_page_https_required',
      redirect ? 'Recipe page redirected to a non-HTTPS URL' : 'Recipe page URL must use HTTPS'
    );
  }
  if (url.username || url.password) {
    throw new RecipePageError(400, 'recipe_page_url_credentials', 'Recipe page URL cannot contain credentials');
  }
  return url;
}

function resolveRedirect(location, currentUrl) {
  try {
    return validateUrl(new URL(location, currentUrl), { redirect: true });
  } catch (error) {
    if (error instanceof RecipePageError) throw error;
    throw new RecipePageError(502, 'invalid_recipe_page_redirect', 'Recipe page returned an invalid redirect URL');
  }
}

function hostnameWithoutBrackets(url) {
  return url.hostname.replace(/^\[|\]$/g, '').toLowerCase();
}

function isBlockedHostname(hostname) {
  return hostname === 'localhost' || BLOCKED_HOST_SUFFIXES.some((suffix) => hostname.endsWith(suffix));
}

function isPublicAddress(address, family) {
  const resolvedFamily = Number(family) || isIP(address);
  if (resolvedFamily !== 4 && resolvedFamily !== 6) return false;
  if (resolvedFamily === 6 && address.toLowerCase().startsWith('::ffff:')) return false;
  return !BLOCKED_ADDRESSES.check(address, resolvedFamily === 6 ? 'ipv6' : 'ipv4');
}

function unsafeAddressError({ redirect }) {
  return new RecipePageError(
    redirect ? 502 : 400,
    redirect ? 'unsafe_recipe_page_redirect' : 'recipe_page_private_address',
    redirect
      ? 'Recipe page redirected to a private or reserved network address'
      : 'Recipe page URL cannot use a private or reserved network address'
  );
}

async function resolvePublicTarget(url, { lookupImpl, redirect, signal }) {
  if (signal?.aborted) {
    const error = new Error('aborted');
    error.name = 'AbortError';
    throw error;
  }
  const hostname = hostnameWithoutBrackets(url);
  if (isBlockedHostname(hostname)) throw unsafeAddressError({ redirect });

  const literalFamily = isIP(hostname);
  if (literalFamily) {
    if (!isPublicAddress(hostname, literalFamily)) throw unsafeAddressError({ redirect });
    return { address: hostname, family: literalFamily };
  }

  let abortHandler;
  try {
    const aborted = new Promise((_, reject) => {
      abortHandler = () => {
        const error = new Error('aborted');
        error.name = 'AbortError';
        reject(error);
      };
      signal?.addEventListener('abort', abortHandler, { once: true });
    });
    const records = await Promise.race([
      lookupImpl(hostname, { all: true, verbatim: true }),
      aborted
    ]);
    const addresses = Array.isArray(records) ? records : [records];
    if (addresses.length === 0 || addresses.some(({ address, family }) => !isPublicAddress(address, family))) {
      throw unsafeAddressError({ redirect });
    }
    return addresses[0];
  } catch (error) {
    if (error instanceof RecipePageError || error?.name === 'AbortError') throw error;
    throw new RecipePageError(502, 'recipe_page_dns_error', 'Recipe page hostname could not be resolved');
  } finally {
    if (abortHandler) signal?.removeEventListener('abort', abortHandler);
  }
}

function pinnedHTTPSFetch(url, options) {
  const target = options.smartcartPinnedAddress;
  if (!target || !isPublicAddress(target.address, target.family)) {
    throw new RecipePageError(502, 'recipe_page_network_error', 'Recipe page request was not pinned to a public address');
  }

  return new Promise((resolve, reject) => {
    const hostname = hostnameWithoutBrackets(url);
    const request = httpsRequest(url, {
      method: options.method,
      headers: options.headers,
      signal: options.signal,
      servername: isIP(hostname) ? undefined : hostname,
      lookup: (_requestedHostname, _lookupOptions, callback) => {
        callback(null, target.address, target.family);
      }
    }, (response) => {
      const headers = new Headers();
      for (const [name, value] of Object.entries(response.headers)) {
        if (Array.isArray(value)) {
          for (const item of value) headers.append(name, item);
        } else if (value != null) {
          headers.set(name, String(value));
        }
      }
      const status = response.statusCode ?? 502;
      const body = [204, 205, 304].includes(status) ? null : Readable.toWeb(response);
      resolve(new Response(body, { status, headers }));
    });
    request.once('error', reject);
    request.end();
  });
}

function parseContentType(value) {
  if (!value) return { mimeType: '', charset: undefined };
  const [rawMime, ...parameters] = value.split(';');
  let charset;
  for (const parameter of parameters) {
    const match = /^\s*charset\s*=\s*["']?([^\s"';]+)["']?\s*$/i.exec(parameter);
    if (match) charset = match[1];
  }
  return { mimeType: rawMime.trim().toLowerCase(), charset };
}

function sniffCharset(bytes) {
  if (bytes.length >= 3 && bytes[0] === 0xef && bytes[1] === 0xbb && bytes[2] === 0xbf) return 'utf-8';
  if (bytes.length >= 2 && bytes[0] === 0xff && bytes[1] === 0xfe) return 'utf-16le';
  if (bytes.length >= 2 && bytes[0] === 0xfe && bytes[1] === 0xff) return 'utf-16be';
  const prefix = Buffer.from(bytes.subarray(0, 4096)).toString('latin1');
  return /<meta\s+[^>]*charset\s*=\s*["']?\s*([^\s"'/>;]+)/i.exec(prefix)?.[1]
    ?? /<meta\s+[^>]*content\s*=\s*["'][^"']*charset\s*=\s*([^\s"';>]+)/i.exec(prefix)?.[1];
}

function decodeHtml(bytes, declaredCharset) {
  const charset = declaredCharset ?? sniffCharset(bytes) ?? 'utf-8';
  try {
    const decoder = new TextDecoder(charset, { fatal: false });
    return { html: decoder.decode(bytes), charset: decoder.encoding };
  } catch {
    throw new RecipePageError(415, 'unsupported_recipe_page_charset', 'Recipe page uses an unsupported character encoding', {
      charset
    });
  }
}

function upstreamFailure(response, url) {
  const details = { upstreamStatus: response.status, url: url.href };
  if (response.status === 401 || response.status === 403) {
    return new RecipePageError(502, 'recipe_page_access_denied', 'Recipe page denied SmartCart access', details);
  }
  if (response.status === 404 || response.status === 410) {
    return new RecipePageError(502, 'recipe_page_not_found', 'Recipe page was not found', details);
  }
  if (response.status === 429) {
    return new RecipePageError(502, 'recipe_page_rate_limited', 'Recipe page rate-limited SmartCart', details);
  }
  return new RecipePageError(502, 'recipe_page_http_error', 'Recipe page returned an unsuccessful HTTP status', details);
}

async function readLimitedBody(response, maxBytes) {
  const length = Number(response.headers.get('content-length'));
  if (Number.isFinite(length) && length > maxBytes) {
    await response.body?.cancel();
    throw new RecipePageError(413, 'recipe_page_too_large', 'Recipe page exceeds the configured size limit', {
      maxBytes,
      contentLength: length
    });
  }
  if (!response.body) {
    throw new RecipePageError(502, 'recipe_page_empty_body', 'Recipe page returned no response body');
  }

  const reader = response.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) {
        await reader.cancel();
        throw new RecipePageError(413, 'recipe_page_too_large', 'Recipe page exceeds the configured size limit', {
          maxBytes
        });
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }

  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

export class RecipePageFetcher {
  constructor({
    fetchImpl = pinnedHTTPSFetch,
    lookupImpl = dnsLookup,
    timeoutMs = 10_000,
    maxBytes = 2_097_152,
    maxRedirects = 5,
    userAgent = SMARTCART_RECIPE_USER_AGENT
  } = {}) {
    this.fetchImpl = fetchImpl;
    this.lookupImpl = lookupImpl;
    this.timeoutMs = timeoutMs;
    this.maxBytes = maxBytes;
    this.maxRedirects = maxRedirects;
    this.userAgent = userAgent;
  }

  async fetch(input) {
    const originalUrl = validateUrl(input);
    let currentUrl = originalUrl;
    let redirectCount = 0;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);

    try {
      while (true) {
        let response;
        try {
          const pinnedAddress = await resolvePublicTarget(currentUrl, {
            lookupImpl: this.lookupImpl,
            redirect: redirectCount > 0,
            signal: controller.signal
          });
          response = await this.fetchImpl(currentUrl, {
            method: 'GET',
            redirect: 'manual',
            signal: controller.signal,
            smartcartPinnedAddress: pinnedAddress,
            headers: {
              accept: 'text/html,application/xhtml+xml;q=0.9',
              'user-agent': this.userAgent
            }
          });
        } catch (error) {
          if (error instanceof RecipePageError) throw error;
          if (controller.signal.aborted || error?.name === 'AbortError' || error?.name === 'TimeoutError') {
            throw new RecipePageError(504, 'recipe_page_timeout', 'Recipe page request timed out', {
              timeoutMs: this.timeoutMs
            });
          }
          throw new RecipePageError(502, 'recipe_page_network_error', 'Recipe page request failed', {
            cause: error instanceof Error ? error.message : String(error)
          });
        }

        if (REDIRECT_STATUSES.has(response.status)) {
          const location = response.headers.get('location');
          await response.body?.cancel();
          if (!location) {
            throw new RecipePageError(502, 'recipe_page_redirect_missing_location', 'Recipe page redirect omitted Location');
          }
          if (redirectCount >= this.maxRedirects) {
            throw new RecipePageError(502, 'recipe_page_redirect_limit', 'Recipe page exceeded the redirect limit', {
              maxRedirects: this.maxRedirects
            });
          }
          currentUrl = resolveRedirect(location, currentUrl);
          redirectCount += 1;
          continue;
        }

        if (!response.ok) {
          await response.body?.cancel();
          throw upstreamFailure(response, currentUrl);
        }

        const { mimeType, charset: declaredCharset } = parseContentType(response.headers.get('content-type'));
        if (!HTML_MIME_TYPES.has(mimeType)) {
          await response.body?.cancel();
          throw new RecipePageError(415, 'unsupported_recipe_page_mime', 'Recipe page must return HTML', {
            mimeType: mimeType || null
          });
        }

        let bytes;
        try {
          bytes = await readLimitedBody(response, this.maxBytes);
        } catch (error) {
          if (controller.signal.aborted || error?.name === 'AbortError' || error?.name === 'TimeoutError') {
            throw new RecipePageError(504, 'recipe_page_timeout', 'Recipe page request timed out', {
              timeoutMs: this.timeoutMs
            });
          }
          throw error;
        }
        const decoded = decodeHtml(bytes, declaredCharset);
        return {
          originalUrl: originalUrl.href,
          finalUrl: currentUrl.href,
          redirectCount,
          status: response.status,
          contentType: mimeType,
          charset: decoded.charset,
          byteLength: bytes.byteLength,
          html: decoded.html
        };
      }
    } finally {
      clearTimeout(timeout);
    }
  }
}
