import { describe, it, expect, vi, beforeEach } from 'vitest';
import {
  FeedbackKit,
  FeedbackKitError,
  RateLimitError,
  ValidationError
} from '../src';

const mockFetch = vi.fn();
global.fetch = mockFetch;

const BASE_URL = 'https://api.prod.getfeedbackkit.com/api/v1';

function jsonOk(body: unknown) {
  return {
    ok: true,
    status: 200,
    headers: new Headers({ 'content-type': 'application/json' }),
    json: () => Promise.resolve(body)
  };
}

describe('transport hardening', () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  describe('rate limit bodies without a JSON content type', () => {
    it('reads the reason and Retry-After when the limiter sends a raw JSON string', async () => {
      // RateLimitMiddleware writes a JSON object and sets no content type.
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 429,
        headers: new Headers({ 'retry-after': '7' }),
        text: () =>
          Promise.resolve(
            '{"error":true,"reason":"Too many requests. Try again later."}'
          )
      });

      const client = new FeedbackKit({ apiKey: 'sf_test_key' });
      const error = await client.feedback.list().then(
        () => {
          throw new Error('expected a rate limit error');
        },
        (caught: unknown) => caught
      );

      expect(error).toBeInstanceOf(RateLimitError);
      const rateLimit = error as RateLimitError;
      expect(rateLimit.message).toBe('Too many requests. Try again later.');
      expect(rateLimit.code).toBe('RATE_LIMITED');
      expect(rateLimit.statusCode).toBe(429);
      expect(rateLimit.retryAfterSeconds).toBe(7);
    });

    it('turns an HTTP-date Retry-After into whole seconds and ignores a garbage value', async () => {
      const future = new Date(Date.now() + 10_000);
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 429,
        headers: new Headers({ 'retry-after': future.toUTCString() }),
        text: () => Promise.resolve('{"error":true,"reason":"Too many requests."}')
      });
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 429,
        headers: new Headers({ 'retry-after': 'soon' }),
        text: () => Promise.resolve('{"error":true,"reason":"Too many requests."}')
      });

      const client = new FeedbackKit({ apiKey: 'sf_test_key' });
      const dated = await client.feedback.list().then(
        () => {
          throw new Error('expected a rate limit error');
        },
        (caught: unknown) => caught as RateLimitError
      );
      const garbage = await client.feedback.list().then(
        () => {
          throw new Error('expected a rate limit error');
        },
        (caught: unknown) => caught as RateLimitError
      );

      expect(dated).toBeInstanceOf(RateLimitError);
      expect(dated.retryAfterSeconds).toBeGreaterThanOrEqual(9);
      expect(dated.retryAfterSeconds).toBeLessThanOrEqual(11);
      expect(garbage).toBeInstanceOf(RateLimitError);
      expect(garbage.retryAfterSeconds).toBeUndefined();
    });
  });

  describe('base URL and redirects', () => {
    it('rejects a non-loopback http base URL', () => {
      expect(
        () =>
          new FeedbackKit({
            apiKey: 'sf_test_key',
            baseUrl: 'http://example.com/api/v1'
          })
      ).toThrow(ValidationError);
    });

    it('allows https and loopback http, including IPv6 localhost', () => {
      expect(
        new FeedbackKit({
          apiKey: 'sf_test_key',
          baseUrl: 'https://api.prod.getfeedbackkit.com/api/v1'
        }).getBaseUrl()
      ).toBe('https://api.prod.getfeedbackkit.com/api/v1');
      expect(
        new FeedbackKit({
          apiKey: 'sf_test_key',
          baseUrl: 'http://localhost:8080/api/v1'
        }).getBaseUrl()
      ).toBe('http://localhost:8080/api/v1');
      expect(
        new FeedbackKit({
          apiKey: 'sf_test_key',
          baseUrl: 'http://127.0.0.1:8080/api/v1'
        }).getBaseUrl()
      ).toBe('http://127.0.0.1:8080/api/v1');
      expect(
        new FeedbackKit({
          apiKey: 'sf_test_key',
          baseUrl: 'http://[::1]:8080/api/v1'
        }).getBaseUrl()
      ).toBe('http://[::1]:8080/api/v1');
    });

    it('does not follow redirects, so the API key cannot leave the host', async () => {
      mockFetch.mockResolvedValueOnce(jsonOk([]));
      const client = new FeedbackKit({ apiKey: 'sf_test_key' });
      await client.feedback.list();

      expect(mockFetch).toHaveBeenCalledWith(
        `${BASE_URL}/feedbacks`,
        expect.objectContaining({ redirect: 'error' })
      );
    });
  });

  describe('event properties match the server string map', () => {
    it('stringifies numbers and booleans and leaves string values unchanged', async () => {
      mockFetch.mockResolvedValueOnce(
        jsonOk({
          id: '550e8400-e29b-41d4-a716-446655440000',
          event_name: 'onboarding_completed',
          user_id: 'user_12345',
          properties: { step_count: '5', duration_seconds: '120.5', done: 'true' }
        })
      );

      const client = new FeedbackKit({ apiKey: 'sf_test_key' });
      await client.events.track({
        eventName: 'onboarding_completed',
        userId: 'user_12345',
        properties: {
          step_count: 5,
          duration_seconds: 120.5,
          done: true,
          filter: 'feature_request'
        }
      });

      const body = JSON.parse(mockFetch.mock.calls[0][1].body as string);
      expect(body.properties).toEqual({
        step_count: '5',
        duration_seconds: '120.5',
        done: 'true',
        filter: 'feature_request'
      });
    });

    it('refuses values the server cannot store as strings', async () => {
      const client = new FeedbackKit({ apiKey: 'sf_test_key' });

      await expect(
        client.events.track({
          eventName: 'onboarding_completed',
          userId: 'user_12345',
          properties: { nested: { step: 1 } }
        })
      ).rejects.toBeInstanceOf(ValidationError);
      await expect(
        client.events.track({
          eventName: 'onboarding_completed',
          userId: 'user_12345',
          properties: { missing: null as unknown as string }
        })
      ).rejects.toBeInstanceOf(ValidationError);
      await expect(
        client.events.track({
          eventName: 'onboarding_completed',
          userId: 'user_12345',
          properties: { bad: Number.NaN }
        })
      ).rejects.toBeInstanceOf(ValidationError);

      expect(mockFetch).not.toHaveBeenCalled();
    });
  });

  describe('comment identity does not contradict the header', () => {
    it('omits X-User-Id when the comment body names a different user', async () => {
      mockFetch.mockResolvedValueOnce(
        jsonOk({
          id: '550e8400-e29b-41d4-a716-446655440000',
          content: 'hello',
          user_id: 'bob',
          is_admin: false,
          created_at: '2026-10-11T00:00:00.000Z'
        })
      );

      const client = new FeedbackKit({ apiKey: 'sf_test_key', userId: 'alice' });
      await client.comments.create('feedback-id', {
        content: 'hello',
        userId: 'bob'
      });

      const headers = mockFetch.mock.calls[0][1].headers as Record<string, string>;
      expect(headers['X-User-Id']).toBeUndefined();
      expect(JSON.parse(mockFetch.mock.calls[0][1].body as string).user_id).toBe('bob');
    });

    it('still sends X-User-Id when the body user matches, and on reads', async () => {
      mockFetch.mockResolvedValueOnce(
        jsonOk({
          id: '550e8400-e29b-41d4-a716-446655440000',
          content: 'hello',
          user_id: 'alice',
          is_admin: false,
          created_at: '2026-10-11T00:00:00.000Z'
        })
      );
      mockFetch.mockResolvedValueOnce(jsonOk([]));

      const client = new FeedbackKit({ apiKey: 'sf_test_key', userId: 'alice' });
      await client.comments.create('feedback-id', {
        content: 'hello',
        userId: 'alice'
      });
      await client.feedback.list();

      expect(mockFetch.mock.calls[0][1].headers['X-User-Id']).toBe('alice');
      expect(mockFetch.mock.calls[1][1].headers['X-User-Id']).toBe('alice');
    });
  });

  describe('SDK-authored failures are FeedbackKit errors', () => {
    it('a missing api key is a ValidationError', () => {
      let thrown: unknown;
      try {
        new FeedbackKit({} as never);
      } catch (error) {
        thrown = error;
      }

      expect(thrown).toBeInstanceOf(ValidationError);
      expect(thrown).toBeInstanceOf(FeedbackKitError);
      expect((thrown as Error).message).toBe('FeedbackKit: apiKey is required');
    });

    it('an admin reply without a bearer token is a ValidationError and sends nothing', async () => {
      const client = new FeedbackKit({ apiKey: 'sf_public_key' });

      await expect(
        client.comments.create('feedback-id', {
          content: 'Thanks',
          userId: 'admin',
          isAdmin: true
        })
      ).rejects.toBeInstanceOf(ValidationError);
      expect(mockFetch).not.toHaveBeenCalled();
    });
  });
});
