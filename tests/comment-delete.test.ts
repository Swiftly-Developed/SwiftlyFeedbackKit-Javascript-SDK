import { describe, it, expect, vi, beforeEach } from 'vitest';
import { FeedbackKit, ForbiddenError, ValidationError } from '../src';
import { HttpClient } from '../src/utils/http';
import { CommentsApi } from '../src/api/comments';

const mockFetch = vi.fn();
global.fetch = mockFetch;

const BASE_URL = 'https://api.prod.getfeedbackkit.com/api/v1';

describe('comments.delete', () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  it('sends the route, the key and the user id, and resolves on an empty 204', async () => {
    mockFetch.mockResolvedValueOnce({
      ok: true,
      status: 204,
      headers: new Headers(),
      text: () => Promise.resolve('')
    });
    const client = new FeedbackKit({ apiKey: 'sf_public_key', userId: 'comment-owner' });

    await expect(client.comments.delete('feedback-id', 'comment-id')).resolves.toBeUndefined();

    expect(mockFetch).toHaveBeenCalledTimes(1);
    const [url, init] = mockFetch.mock.calls[0];
    expect(url).toBe(`${BASE_URL}/feedbacks/feedback-id/comments/comment-id`);
    expect(init.method).toBe('DELETE');
    expect(init.headers['X-API-Key']).toBe('sf_public_key');
    expect(init.headers['X-User-Id']).toBe('comment-owner');
    expect(init.body).toBeUndefined();
  });

  it('surfaces the server reason when the comment is not the caller\'s', async () => {
    mockFetch.mockResolvedValueOnce({
      ok: false,
      status: 403,
      headers: new Headers({ 'content-type': 'application/json' }),
      json: () => Promise.resolve({ error: true, reason: 'You can only delete your own comments' })
    });
    const client = new FeedbackKit({ apiKey: 'sf_public_key', userId: 'someone-else' });

    const failure = client.comments.delete('feedback-id', 'comment-id');
    await expect(failure).rejects.toBeInstanceOf(ForbiddenError);
    await expect(failure).rejects.toThrow('You can only delete your own comments');
  });

  it('never sends a key-only delete when no user id can be resolved', async () => {
    const http = new HttpClient({ apiKey: 'sf_public_key', baseUrl: BASE_URL, timeout: 1000 });
    const api = new CommentsApi(http);

    await expect(api.delete('feedback-id', 'comment-id')).rejects.toBeInstanceOf(ValidationError);
    expect(mockFetch).not.toHaveBeenCalled();
  });
});
