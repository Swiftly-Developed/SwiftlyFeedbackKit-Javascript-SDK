/**
 * HTTP Client for FeedbackKit API
 * Zero dependencies - uses native fetch
 */

import { createErrorFromResponse, NetworkError, ValidationError } from '../models/errors';
import type { ApiErrorBody } from '../models/errors';

/**
 * Convert a snake_case string to camelCase
 */
function snakeToCamelKey(key: string): string {
  return key.replace(/_([a-z])/g, (_, letter) => letter.toUpperCase());
}

/**
 * Convert a camelCase string to snake_case
 */
function camelToSnakeKey(key: string): string {
  return key.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);
}

/**
 * Keys whose CONTENTS are data, not field names, and must cross the wire verbatim.
 *
 * - `values`: a metrics measure map, keyed by the server's snake_case measure tokens
 *   (METRICS03 phase 01 §6 C4). Renaming `event_count` to `eventCount` inside it
 *   breaks every lookup against the typed measure tokens this SDK ships.
 * - `properties`: customer-supplied JSON on a view event. The customer chose these
 *   keys; the SDK does not get a vote.
 *
 * The exemption covers BOTH directions. Exempting only the decode side would break
 * an accidental round-trip that the two transforms currently provide for each other:
 * a caller's `planTier` goes out as `plan_tier` and comes back as `planTier`. Fixing
 * one side alone leaves the caller reading back a key it never wrote.
 *
 * The exemption is on the KEY and applies anywhere in the tree; the key itself is
 * still renamed, only its contents are opaque.
 */
const OPAQUE_KEYS = new Set(['values', 'properties']);

/**
 * Recursively convert all keys in an object from snake_case to camelCase
 */
function snakeToCamel(data: unknown): unknown {
  if (Array.isArray(data)) {
    return data.map(snakeToCamel);
  }
  if (data !== null && typeof data === 'object') {
    const result: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(data as Record<string, unknown>)) {
      result[snakeToCamelKey(key)] = OPAQUE_KEYS.has(key) ? value : snakeToCamel(value);
    }
    return result;
  }
  return data;
}

/**
 * Recursively convert all keys in an object from camelCase to snake_case
 */
function camelToSnake(data: unknown): unknown {
  if (Array.isArray(data)) {
    return data.map(camelToSnake);
  }
  if (data !== null && typeof data === 'object') {
    const result: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(data as Record<string, unknown>)) {
      // Matched on the PRE-conversion key. Both opaque names are single words, so the
      // pre- and post-conversion spellings coincide; the tests assert that rather than
      // relying on it.
      result[camelToSnakeKey(key)] = OPAQUE_KEYS.has(key) ? value : camelToSnake(value);
    }
    return result;
  }
  return data;
}

/**
 * The commenter, voter, or submitter named in a JSON body. The server rejects a
 * write when this value and `X-User-Id` trim to different ids.
 */
function bodyUserId(body: unknown): string | undefined {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return undefined;
  }
  const record = body as Record<string, unknown>;
  const raw = record.userId ?? record.user_id;
  return typeof raw === 'string' ? raw : undefined;
}

/**
 * Header identity for this call. A body `userId` that names someone else wins, and
 * the header is omitted so the two cannot disagree. Reads, and writes whose body
 * matches, keep the configured id.
 */
function requestUserId(configured: string | undefined, body: unknown): string | undefined {
  if (!configured) return undefined;
  const written = bodyUserId(body);
  if (written !== undefined && written.trim() !== configured.trim()) {
    return undefined;
  }
  return configured;
}

/**
 * `Retry-After` is either delta-seconds or an HTTP-date. Anything else is absent.
 */
function parseRetryAfter(header: string | null, now = Date.now()): number | undefined {
  if (!header) return undefined;
  const trimmed = header.trim();
  if (/^\d+$/.test(trimmed)) {
    return Number(trimmed);
  }
  const date = Date.parse(trimmed);
  if (Number.isNaN(date)) return undefined;
  return Math.max(0, Math.ceil((date - now) / 1000));
}

export interface HttpClientConfig {
  baseUrl: string;
  apiKey: string;
  userId?: string;
  /** Server-side credential. Sent only when a call opts in, never on end-user writes. */
  bearerToken?: string;
  timeout: number;
}

/**
 * A value a query parameter may carry. `number` is admitted because integer-valued
 * parameters (`days`, `page`, `per_page`) go on the wire as digits; `String(value)`
 * at the append site already handles it.
 */
export type QueryParamValue = string | number | boolean | undefined;

export interface RequestOptions {
  method: 'GET' | 'POST' | 'DELETE' | 'PATCH' | 'PUT';
  path: string;
  body?: unknown;
  params?: Record<string, QueryParamValue>;
  /** Attach `Authorization: Bearer` using the configured server credential. */
  useBearerToken?: boolean;
}

/**
 * HTTP client wrapper around fetch
 */
export class HttpClient {
  private config: HttpClientConfig;
  private identityResolver: (() => string) | undefined;

  constructor(config: HttpClientConfig) {
    this.config = config;
  }

  /**
   * Update the user ID for subsequent requests
   */
  setUserId(userId: string | undefined): void {
    this.config.userId = userId;
  }

  /**
   * Supplies the session id when the client does not already have one.
   * FeedbackKit uses this so a cleared id is regenerated before a request.
   */
  setIdentityResolver(resolve: () => string): void {
    this.identityResolver = resolve;
  }

  /**
   * The session id, generating one when the host has not set one.
   */
  ensureUserId(): string {
    const resolved = (this.identityResolver?.() ?? this.config.userId ?? '').trim();
    if (resolved) {
      this.config.userId = resolved;
    }
    return resolved;
  }

  /**
   * A non-blank id on this call wins. Otherwise the session id is used, which
   * is generated when the host has not set one.
   */
  resolveRequestUserId(requested?: string): string {
    const explicit = requested?.trim();
    if (explicit) return explicit;
    return this.ensureUserId();
  }

  /**
   * Make an HTTP request to the API
   */
  async request<T>(options: RequestOptions): Promise<T> {
    const { method, path, body, params, useBearerToken } = options;
    this.ensureUserId();

    // Build URL with query parameters.
    // Query keys are sent verbatim: the API reads them literally (e.g. `includeMerged`),
    // unlike JSON bodies, which it decodes with a snake_case strategy.
    let url = `${this.config.baseUrl}${path}`;
    if (params) {
      const searchParams = new URLSearchParams();
      Object.entries(params).forEach(([key, value]) => {
        if (value !== undefined) {
          searchParams.append(key, String(value));
        }
      });
      const queryString = searchParams.toString();
      if (queryString) {
        url += `?${queryString}`;
      }
    }

    // Build headers
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'X-API-Key': this.config.apiKey
    };

    const userId = requestUserId(this.config.userId, body);
    if (userId) {
      headers['X-User-Id'] = userId;
    }

    if (useBearerToken) {
      if (!this.config.bearerToken) {
        throw new ValidationError(
          'FeedbackKit: admin replies require a bearer token. Pass bearerToken, a server-side credential, when creating the client. The project API key cannot mark a reply as admin.'
        );
      }
      headers['Authorization'] = `Bearer ${this.config.bearerToken}`;
    }

    // Create abort controller for timeout
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), this.config.timeout);

    try {
      const response = await fetch(url, {
        method,
        headers,
        body: body ? JSON.stringify(camelToSnake(body)) : undefined,
        signal: controller.signal,
        // A 3xx must not be followed. The API key is on this request, and a redirect
        // to another origin would send it there.
        redirect: 'error'
      });

      clearTimeout(timeoutId);

      // Parse response body. A JSON content type is authoritative. The rate limiter
      // writes a JSON object and sets no content type, so a body that starts with
      // `{` or `[` is parsed the same way. Anything else stays text.
      const contentType = response.headers.get('content-type');
      let parsed: unknown;

      if (contentType?.includes('application/json') || contentType?.includes('+json')) {
        parsed = await response.json();
      } else {
        const text = await response.text();
        const trimmed = text.trim();
        if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
          try {
            parsed = JSON.parse(trimmed);
          } catch {
            parsed = text;
          }
        } else {
          parsed = text;
        }
      }

      const responseBody = snakeToCamel(parsed);

      // Handle error responses.
      // NOTE: `snakeToCamel` has already run over the parsed body above. Every key in
      // both error shapes is a single word today — `error`, `timestamp`, `reason`, and
      // inside the envelope `code`, `message`, `field` — so all are invariant under the
      // transform and the factory sees the wire spellings. That is a property of today's
      // error vocabulary, not of this design: a future `retry_after` would reach the
      // factory as `retryAfter`. The wait interval travels in the `Retry-After` header,
      // not in the body.
      if (!response.ok) {
        throw createErrorFromResponse(
          response.status,
          responseBody as ApiErrorBody | string,
          parseRetryAfter(response.headers.get('retry-after'))
        );
      }

      return responseBody as T;
    } catch (error) {
      clearTimeout(timeoutId);

      // Re-throw FeedbackKit errors
      if (error instanceof Error && error.name.includes('Error') && 'statusCode' in error) {
        throw error;
      }

      // Handle abort/timeout
      if (error instanceof Error && error.name === 'AbortError') {
        throw new NetworkError('Request timeout');
      }

      // Handle network errors
      throw new NetworkError(
        error instanceof Error ? error.message : 'Network error'
      );
    }
  }

  /**
   * GET request
   */
  get<T>(path: string, params?: Record<string, QueryParamValue>): Promise<T> {
    return this.request<T>({ method: 'GET', path, params });
  }

  /**
   * POST request
   */
  post<T>(path: string, body?: unknown, useBearerToken = false): Promise<T> {
    return this.request<T>({ method: 'POST', path, body, useBearerToken });
  }

  /**
   * DELETE request
   */
  delete<T>(path: string, body?: unknown): Promise<T> {
    return this.request<T>({ method: 'DELETE', path, body });
  }
}
