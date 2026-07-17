import { HttpError } from '../lib/http.js';

const REDIRECT_STATUSES = new Set([301, 302, 303, 307, 308]);
const HTML_MIME_TYPES = new Set(['text/html', 'application/xhtml+xml']);

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
    fetchImpl = globalThis.fetch,
    timeoutMs = 10_000,
    maxBytes = 2_097_152,
    maxRedirects = 5,
    userAgent = SMARTCART_RECIPE_USER_AGENT
  } = {}) {
    this.fetchImpl = fetchImpl;
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
          response = await this.fetchImpl(currentUrl, {
            method: 'GET',
            redirect: 'manual',
            signal: controller.signal,
            headers: {
              accept: 'text/html,application/xhtml+xml;q=0.9',
              'user-agent': this.userAgent
            }
          });
        } catch (error) {
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
