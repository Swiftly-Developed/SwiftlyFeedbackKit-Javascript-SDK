import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { FeedbackCategory, FeedbackKit } from '../src';

/**
 * Flutter persists under this key. The id itself is `local_` plus a UUID v4,
 * the same shape Flutter generates and Swift stores as `local_<UUID>`.
 */
const STORAGE_KEY = 'feedbackkit_user_id';

const LOCAL_USER_ID =
  /^local_[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

const BASE_URL = 'https://api.prod.getfeedbackkit.com/api/v1';

const mockFetch = vi.fn();

function installLocalStorage(): Map<string, string> {
  const data = new Map<string, string>();
  const storage: Storage = {
    get length() {
      return data.size;
    },
    clear() {
      data.clear();
    },
    getItem(key: string) {
      return data.has(key) ? data.get(key)! : null;
    },
    key(index: number) {
      return [...data.keys()][index] ?? null;
    },
    removeItem(key: string) {
      data.delete(key);
    },
    setItem(key: string, value: string) {
      data.set(key, String(value));
    }
  };
  Object.defineProperty(globalThis, 'localStorage', {
    configurable: true,
    writable: true,
    value: storage
  });
  return data;
}

function removeLocalStorage(): void {
  delete (globalThis as { localStorage?: Storage }).localStorage;
}

function jsonOk(body: unknown) {
  return {
    ok: true,
    headers: new Headers({ 'content-type': 'application/json' }),
    json: () => Promise.resolve(body)
  };
}

describe('anonymous user id', () => {
  beforeEach(() => {
    mockFetch.mockReset();
    vi.stubGlobal('fetch', mockFetch);
    removeLocalStorage();
  });

  afterEach(() => {
    removeLocalStorage();
    vi.unstubAllGlobals();
  });

  it('generates one persisted local_ uuid when the host has not set an id', () => {
    const data = installLocalStorage();
    const first = new FeedbackKit({ apiKey: 'sf_test_key' });
    const id = first.getUserId();

    expect(id).toMatch(LOCAL_USER_ID);
    expect(data.get(STORAGE_KEY)).toBe(id);

    const second = new FeedbackKit({ apiKey: 'sf_test_key' });
    expect(second.getUserId()).toBe(id);
  });

  it('lets an explicit id win over a stored one and persists the override', () => {
    const data = installLocalStorage();
    data.set(STORAGE_KEY, 'stored-user');

    const client = new FeedbackKit({ apiKey: 'sf_test_key', userId: 'explicit-user' });
    expect(client.getUserId()).toBe('explicit-user');
    expect(data.get(STORAGE_KEY)).toBe('explicit-user');

    client.setUserId('user_123');
    expect(client.getUserId()).toBe('user_123');
    expect(data.get(STORAGE_KEY)).toBe('user_123');
    expect(new FeedbackKit({ apiKey: 'sf_test_key' }).getUserId()).toBe('user_123');
  });

  it('keeps the id in memory when localStorage is missing, and does not throw', () => {
    const client = new FeedbackKit({ apiKey: 'sf_test_key' });
    expect(client.getUserId()).toMatch(LOCAL_USER_ID);
    expect(new FeedbackKit({ apiKey: 'sf_test_key' }).getUserId()).toMatch(LOCAL_USER_ID);
  });

  it('keeps working when localStorage throws, as it does during SSR', () => {
    Object.defineProperty(globalThis, 'localStorage', {
      configurable: true,
      get() {
        throw new Error('localStorage is not available');
      }
    });

    const client = new FeedbackKit({ apiKey: 'sf_test_key' });
    const id = client.getUserId();
    expect(id).toMatch(LOCAL_USER_ID);
    expect(client.getUserId()).toBe(id);
  });

  it('falls back when crypto.randomUUID is missing', () => {
    const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'crypto');
    Object.defineProperty(globalThis, 'crypto', {
      configurable: true,
      writable: true,
      value: {
        getRandomValues(bytes: Uint8Array) {
          bytes.fill(7);
          return bytes;
        }
      }
    });

    try {
      const client = new FeedbackKit({ apiKey: 'sf_test_key' });
      expect(client.getUserId()).toMatch(LOCAL_USER_ID);
    } finally {
      if (descriptor) {
        Object.defineProperty(globalThis, 'crypto', descriptor);
      }
    }
  });

  it('sends the anonymous id on list, submit, vote, and comment when the caller omits one', async () => {
    installLocalStorage();
    const client = new FeedbackKit({ apiKey: 'sf_test_key' });
    const id = client.getUserId();
    expect(id).toMatch(LOCAL_USER_ID);

    mockFetch.mockResolvedValue(jsonOk([]));
    await client.feedback.list();
    await client.comments.list('feedback-id');

    mockFetch.mockResolvedValueOnce(
      jsonOk({
        id: '550e8400-e29b-41d4-a716-446655440000',
        title: 'Dark mode',
        status: 'pending',
        vote_count: 1
      })
    );
    await client.feedback.create({
      title: 'Dark mode',
      description: 'Please add it.',
      category: FeedbackCategory.FeatureRequest
    });

    mockFetch.mockResolvedValueOnce(
      jsonOk({ feedback_id: 'feedback-id', vote_count: 2, has_voted: true })
    );
    await client.votes.vote('feedback-id', {});

    mockFetch.mockResolvedValueOnce(
      jsonOk({ feedback_id: 'feedback-id', vote_count: 1, has_voted: false })
    );
    await client.votes.unvote('feedback-id', {});

    mockFetch.mockResolvedValueOnce(
      jsonOk({
        id: '550e8400-e29b-41d4-a716-446655440001',
        content: 'Yes',
        user_id: id,
        is_admin: false,
        created_at: '2026-10-11T00:00:00.000Z'
      })
    );
    await client.comments.create('feedback-id', { content: 'Yes' });

    const calls = mockFetch.mock.calls;
    expect(calls[0][0]).toBe(`${BASE_URL}/feedbacks?paged=1`);
    expect(calls[0][1].headers['X-User-Id']).toBe(id);
    expect(calls[1][1].headers['X-User-Id']).toBe(id);

    expect(JSON.parse(calls[2][1].body).user_id).toBe(id);
    expect(calls[2][1].headers['X-User-Id']).toBe(id);

    expect(JSON.parse(calls[3][1].body).user_id).toBe(id);
    expect(JSON.parse(calls[4][1].body).user_id).toBe(id);
    expect(JSON.parse(calls[5][1].body).user_id).toBe(id);
  });

  it('keeps a caller-supplied id on the write and still lets setUserId replace the session', async () => {
    installLocalStorage();
    const client = new FeedbackKit({ apiKey: 'sf_test_key', userId: 'alice' });

    mockFetch.mockResolvedValueOnce(
      jsonOk({
        id: '550e8400-e29b-41d4-a716-446655440000',
        title: 'Dark mode',
        status: 'pending',
        vote_count: 1
      })
    );
    await client.feedback.create({
      title: 'Dark mode',
      description: 'Please add it.',
      category: FeedbackCategory.FeatureRequest,
      userId: 'bob'
    });

    const headers = mockFetch.mock.calls[0][1].headers as Record<string, string>;
    expect(JSON.parse(mockFetch.mock.calls[0][1].body as string).user_id).toBe('bob');
    expect(headers['X-User-Id']).toBeUndefined();
    expect(client.getUserId()).toBe('alice');

    client.setUserId(undefined);
    expect(client.getUserId()).toBeUndefined();

    mockFetch.mockResolvedValueOnce(
      jsonOk({ feedback_id: 'feedback-id', vote_count: 1, has_voted: true })
    );
    await client.votes.vote('feedback-id', {});
    const generated = JSON.parse(mockFetch.mock.calls[1][1].body as string).user_id as string;
    expect(generated).toMatch(LOCAL_USER_ID);
    expect(client.getUserId()).toBe(generated);
  });
});
