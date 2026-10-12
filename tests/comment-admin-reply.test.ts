import { describe, it, expect, vi, beforeEach } from 'vitest';
import { FeedbackKit } from '../src';

const mockFetch = vi.fn();
global.fetch = mockFetch;

const BASE_URL = 'https://api.prod.getfeedbackkit.com/api/v1';

function commentResponse(isAdmin: boolean) {
  return {
    ok: true,
    headers: new Headers({ 'content-type': 'application/json' }),
    json: () =>
      Promise.resolve({
        id: '550e8400-e29b-41d4-a716-446655440000',
        content: 'Thanks for the feedback! We are working on this.',
        user_id: 'js-admin-120',
        is_admin: isAdmin,
        created_at: '2026-10-10T00:00:00.000Z'
      })
  };
}

describe('comments.create admin replies', () => {
  beforeEach(() => {
    mockFetch.mockReset();
  });

  it('refuses isAdmin with only the project API key and does not send the request', async () => {
    const client = new FeedbackKit({ apiKey: 'sf_public_key', userId: 'js-admin-120' });

    await expect(
      client.comments.create('feedback-id', {
        content: 'Thanks for the feedback! We are working on this.',
        userId: 'js-admin-120',
        isAdmin: true
      })
    ).rejects.toThrow(/bearer token/);

    expect(mockFetch).not.toHaveBeenCalled();
  });

  it('sends Authorization when a server-side bearer token is configured', async () => {
    mockFetch.mockResolvedValueOnce(commentResponse(true));
    const client = new FeedbackKit({
      apiKey: 'sf_public_key',
      userId: 'js-admin-120',
      bearerToken: 'server-credential'
    });

    const created = await client.comments.create('feedback-id', {
      content: 'Thanks for the feedback! We are working on this.',
      userId: 'js-admin-120',
      isAdmin: true
    });

    expect(created.isAdmin).toBe(true);
    expect(mockFetch).toHaveBeenCalledWith(
      `${BASE_URL}/feedbacks/feedback-id/comments`,
      expect.objectContaining({
        method: 'POST',
        headers: expect.objectContaining({
          'X-API-Key': 'sf_public_key',
          'X-User-Id': 'js-admin-120',
          Authorization: 'Bearer server-credential'
        }),
        body: JSON.stringify({
          content: 'Thanks for the feedback! We are working on this.',
          user_id: 'js-admin-120',
          is_admin: true
        })
      })
    );
  });

  it('keeps an end-user comment on the API key and sends is_admin false', async () => {
    mockFetch.mockResolvedValueOnce(commentResponse(false));
    const client = new FeedbackKit({
      apiKey: 'sf_public_key',
      userId: 'js-user-120',
      bearerToken: 'server-credential'
    });

    await client.comments.create('feedback-id', {
      content: 'This would be really helpful!',
      userId: 'js-user-120'
    });

    const [, init] = mockFetch.mock.calls[0];
    expect(init.headers.Authorization).toBeUndefined();
    expect(JSON.parse(init.body)).toEqual({
      content: 'This would be really helpful!',
      user_id: 'js-user-120',
      is_admin: false
    });
  });
});
