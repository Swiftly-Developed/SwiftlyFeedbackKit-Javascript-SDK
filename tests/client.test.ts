import { describe, it, expect, vi, beforeEach } from 'vitest';
import { FeedbackKit, FeedbackCategory, FeedbackSort, FeedbackStatus } from '../src';

// Mock fetch globally
const mockFetch = vi.fn();
global.fetch = mockFetch;

// The SDK's default baseUrl. Kept in one place so a future URL migration
// updates every expectation at once.
const BASE_URL = 'https://api.prod.getfeedbackkit.com/api/v1';

describe('FeedbackKit', () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  describe('constructor', () => {
    it('should create a client with required apiKey', () => {
      const client = new FeedbackKit({ apiKey: 'sf_test_key' });
      expect(client).toBeInstanceOf(FeedbackKit);
    });

    it('should throw if apiKey is not provided', () => {
      expect(() => new FeedbackKit({ apiKey: '' })).toThrow('apiKey is required');
    });

    it('should use default baseUrl if not provided', () => {
      const client = new FeedbackKit({ apiKey: 'sf_test_key' });
      expect(client.getBaseUrl()).toBe(BASE_URL);
    });

    it('should use custom baseUrl if provided', () => {
      const client = new FeedbackKit({
        apiKey: 'sf_test_key',
        baseUrl: 'http://localhost:8080/api/v1'
      });
      expect(client.getBaseUrl()).toBe('http://localhost:8080/api/v1');
    });
  });

  describe('setUserId', () => {
    it('should set and get userId', () => {
      const client = new FeedbackKit({ apiKey: 'sf_test_key' });
      expect(client.getUserId()).toBeUndefined();

      client.setUserId('user_123');
      expect(client.getUserId()).toBe('user_123');

      client.setUserId(undefined);
      expect(client.getUserId()).toBeUndefined();
    });
  });

  describe('feedback.list', () => {
    it('should fetch feedback list', async () => {
      const mockFeedback = [
        {
          id: '550e8400-e29b-41d4-a716-446655440000',
          title: 'Test Feedback',
          status: 'pending',
          voteCount: 1
        }
      ];

      mockFetch.mockResolvedValueOnce({
        ok: true,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: () => Promise.resolve(mockFeedback)
      });

      const client = new FeedbackKit({ apiKey: 'sf_test_key' });
      const result = await client.feedback.list();

      expect(result).toEqual(mockFeedback);
      expect(mockFetch).toHaveBeenCalledWith(
        `${BASE_URL}/feedbacks`,
        expect.objectContaining({
          method: 'GET',
          headers: expect.objectContaining({
            'X-API-Key': 'sf_test_key'
          })
        })
      );
    });

    it('should filter by status', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: true,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: () => Promise.resolve([])
      });

      const client = new FeedbackKit({ apiKey: 'sf_test_key' });
      await client.feedback.list({ status: FeedbackStatus.Pending });

      expect(mockFetch).toHaveBeenCalledWith(
        `${BASE_URL}/feedbacks?status=pending`,
        expect.any(Object)
      );
    });

    it('should filter by category', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: true,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: () => Promise.resolve([])
      });

      const client = new FeedbackKit({ apiKey: 'sf_test_key' });
      await client.feedback.list({ category: FeedbackCategory.BugReport });

      expect(mockFetch).toHaveBeenCalledWith(
        `${BASE_URL}/feedbacks?category=bug_report`,
        expect.any(Object)
      );
    });

    it('should send includeMerged as a camelCase query key', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: true,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: () => Promise.resolve([])
      });

      const client = new FeedbackKit({ apiKey: 'sf_test_key' });
      await client.feedback.list({ includeMerged: true });

      // The API reads this key literally. A snake_cased `include_merged` is
      // silently ignored and the server falls back to `false`.
      expect(mockFetch).toHaveBeenCalledWith(
        `${BASE_URL}/feedbacks?includeMerged=true`,
        expect.any(Object)
      );
    });

    it('should send every query key unmangled', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: true,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: () => Promise.resolve([])
      });

      const client = new FeedbackKit({ apiKey: 'sf_test_key' });
      await client.feedback.list({
        status: FeedbackStatus.Approved,
        category: FeedbackCategory.FeatureRequest,
        includeMerged: true,
        sort: FeedbackSort.Newest
      });

      const [requestedUrl] = mockFetch.mock.calls[0];
      const query = new URL(requestedUrl as string).searchParams;
      expect([...query.keys()]).toEqual([
        'status',
        'category',
        'includeMerged',
        'sort'
      ]);
      expect(query.get('includeMerged')).toBe('true');
      expect(query.get('sort')).toBe('newest');
    });
  });

  describe('feedback.create', () => {
    it('should create feedback', async () => {
      const mockResponse = {
        id: '550e8400-e29b-41d4-a716-446655440000',
        title: 'New Feature',
        status: 'pending',
        voteCount: 1,
        hasVoted: true
      };

      mockFetch.mockResolvedValueOnce({
        ok: true,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: () => Promise.resolve(mockResponse)
      });

      const client = new FeedbackKit({ apiKey: 'sf_test_key' });
      const result = await client.feedback.create({
        title: 'New Feature',
        description: 'Please add this feature',
        category: FeedbackCategory.FeatureRequest,
        userId: 'user_123'
      });

      expect(result).toEqual(mockResponse);
      expect(mockFetch).toHaveBeenCalledWith(
        `${BASE_URL}/feedbacks`,
        expect.objectContaining({
          method: 'POST',
          // Request bodies are snake_cased on the wire; the API decodes them
          // with a convertFromSnakeCase strategy. Query keys are not (see above).
          body: JSON.stringify({
            title: 'New Feature',
            description: 'Please add this feature',
            category: 'feature_request',
            user_id: 'user_123',
            user_email: undefined
          })
        })
      );
    });
  });

  describe('votes.vote', () => {
    it('should vote for feedback', async () => {
      const mockResponse = {
        feedbackId: '550e8400-e29b-41d4-a716-446655440000',
        voteCount: 5,
        hasVoted: true
      };

      mockFetch.mockResolvedValueOnce({
        ok: true,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: () => Promise.resolve(mockResponse)
      });

      const client = new FeedbackKit({ apiKey: 'sf_test_key' });
      const result = await client.votes.vote('550e8400-e29b-41d4-a716-446655440000', {
        userId: 'user_123'
      });

      expect(result).toEqual(mockResponse);
      expect(result.hasVoted).toBe(true);
    });
  });

  describe('error handling', () => {
    it('should throw AuthenticationError for 401', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 401,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: () => Promise.resolve({ error: true, reason: 'Invalid API key' })
      });

      const client = new FeedbackKit({ apiKey: 'invalid_key' });
      await expect(client.feedback.list()).rejects.toThrow('Invalid API key');
    });

    it('should throw PaymentRequiredError for 402', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 402,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: () => Promise.resolve({ error: true, reason: 'Feedback limit reached' })
      });

      const client = new FeedbackKit({ apiKey: 'sf_test_key' });
      await expect(client.feedback.create({
        title: 'Test',
        description: 'Test',
        category: FeedbackCategory.Other,
        userId: 'user_123'
      })).rejects.toThrow('Feedback limit reached');
    });

    it('should throw ConflictError for 409', async () => {
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 409,
        headers: new Headers({ 'content-type': 'application/json' }),
        json: () => Promise.resolve({ error: true, reason: 'Already voted' })
      });

      const client = new FeedbackKit({ apiKey: 'sf_test_key' });
      await expect(client.votes.vote('feedback-id', { userId: 'user_123' }))
        .rejects.toThrow('Already voted');
    });
  });
});
