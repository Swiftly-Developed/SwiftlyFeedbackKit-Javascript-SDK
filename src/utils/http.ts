/**
 * HTTP Client for FeedbackKit API
 * Zero dependencies - uses native fetch
 */

import { createErrorFromResponse, NetworkError } from '../models/errors';

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
 * Recursively convert all keys in an object from snake_case to camelCase
 */
function snakeToCamel(data: unknown): unknown {
  if (Array.isArray(data)) {
    return data.map(snakeToCamel);
  }
  if (data !== null && typeof data === 'object') {
    const result: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(data as Record<string, unknown>)) {
      result[snakeToCamelKey(key)] = snakeToCamel(value);
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
      result[camelToSnakeKey(key)] = camelToSnake(value);
    }
    return result;
  }
  return data;
}

export interface HttpClientConfig {
  baseUrl: string;
  apiKey: string;
  userId?: string;
  timeout: number;
}

export interface RequestOptions {
  method: 'GET' | 'POST' | 'DELETE' | 'PATCH' | 'PUT';
  path: string;
  body?: unknown;
  params?: Record<string, string | boolean | undefined>;
}

/**
 * HTTP client wrapper around fetch
 */
export class HttpClient {
  private config: HttpClientConfig;

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
   * Make an HTTP request to the API
   */
  async request<T>(options: RequestOptions): Promise<T> {
    const { method, path, body, params } = options;

    // Build URL with query parameters
    let url = `${this.config.baseUrl}${path}`;
    if (params) {
      const searchParams = new URLSearchParams();
      Object.entries(params).forEach(([key, value]) => {
        if (value !== undefined) {
          searchParams.append(camelToSnakeKey(key), String(value));
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

    if (this.config.userId) {
      headers['X-User-Id'] = this.config.userId;
    }

    // Create abort controller for timeout
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), this.config.timeout);

    try {
      const response = await fetch(url, {
        method,
        headers,
        body: body ? JSON.stringify(camelToSnake(body)) : undefined,
        signal: controller.signal
      });

      clearTimeout(timeoutId);

      // Parse response body
      const contentType = response.headers.get('content-type');
      let responseBody: unknown;

      if (contentType?.includes('application/json')) {
        responseBody = snakeToCamel(await response.json());
      } else {
        responseBody = await response.text();
      }

      // Handle error responses
      if (!response.ok) {
        throw createErrorFromResponse(
          response.status,
          responseBody as { error: boolean; reason: string } | string
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
  get<T>(path: string, params?: Record<string, string | boolean | undefined>): Promise<T> {
    return this.request<T>({ method: 'GET', path, params });
  }

  /**
   * POST request
   */
  post<T>(path: string, body?: unknown): Promise<T> {
    return this.request<T>({ method: 'POST', path, body });
  }

  /**
   * DELETE request
   */
  delete<T>(path: string, body?: unknown): Promise<T> {
    return this.request<T>({ method: 'DELETE', path, body });
  }
}
