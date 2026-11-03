import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { FeedbackKit } from '../src';

/**
 * RESILIENCE01 §9.1. A paged list stops following when the server's page number
 * cannot be trusted, and always stops within 100 follow-up requests.
 */

const API_KEY = 'sf_test_stub_key_not_a_credential';
const USER_ID = 'user-under-test';
const FEEDBACK_ID = '11111111-1111-4111-8111-111111111111';
const CALL_LIMIT = 300;

type Meta = { page?: number; per_page?: number; total_pages?: number };

function requestedPage(url: string): number {
  return Number(new URL(url).searchParams.get('page') ?? '1');
}

const spyOnWarn = () => vi.spyOn(console, 'warn').mockImplementation(() => undefined);

function stubServer(metaFor: (requested: number) => Meta) {
  const fetchMock = vi.fn(async (url: string) => {
    if (fetchMock.mock.calls.length > CALL_LIMIT) {
      throw new Error(`still following after ${CALL_LIMIT} requests`);
    }
    const requested = requestedPage(url);
    const body = {
      items: [
        {
          id: `row-${requested}`,
          title: `row content ${requested}`,
          content: `row content ${requested}`,
          status: 'pending',
          vote_count: 1,
          user_id: USER_ID
        }
      ],
      meta: metaFor(requested)
    };
    return {
      ok: true,
      headers: new Headers({ 'content-type': 'application/json' }),
      json: () => Promise.resolve(body)
    };
  });
  global.fetch = fetchMock as unknown as typeof fetch;
  return fetchMock;
}

const lists = [
  {
    name: 'feedback',
    path: '/feedbacks',
    list: (client: FeedbackKit, options?: { page?: number }) => client.feedback.list(options)
  },
  {
    name: 'comments',
    path: `/feedbacks/${FEEDBACK_ID}/comments`,
    list: (client: FeedbackKit, options?: { page?: number }) =>
      client.comments.list(FEEDBACK_ID, options)
  }
];

describe.each(lists)('following $name pages', ({ path, list }) => {
  let warn: ReturnType<typeof spyOnWarn>;
  let client: FeedbackKit;

  beforeEach(() => {
    warn = spyOnWarn();
    client = new FeedbackKit({ apiKey: API_KEY, userId: USER_ID });
  });

  afterEach(() => {
    warn.mockRestore();
  });

  function ids(rows: Array<{ id: string }>): string[] {
    return rows.map((row) => row.id);
  }

  it('stops on a stale echo and keeps only the first page', async () => {
    const server = stubServer(() => ({ page: 1, per_page: 1, total_pages: 3 }));
    const rows = await list(client);
    expect(server).toHaveBeenCalledTimes(2);
    expect(ids(rows)).toEqual(['row-1']);
    expect(warn).toHaveBeenCalledTimes(1);
    const line = String(warn.mock.calls[0][0]);
    expect(line).toContain(path);
    expect(line).toContain('requested page 2');
    expect(line).toContain('received page 1');
    expect(line).not.toContain(API_KEY);
    expect(line).not.toContain(USER_ID);
    expect(line).not.toContain('row content');
  });

  it('stops when a follow-up leaves out meta.page', async () => {
    const server = stubServer((requested) =>
      requested === 1
        ? { page: 1, per_page: 1, total_pages: 3 }
        : { per_page: 1, total_pages: 3 }
    );
    const rows = await list(client);
    expect(server).toHaveBeenCalledTimes(2);
    expect(ids(rows)).toEqual(['row-1']);
    expect(warn).toHaveBeenCalledTimes(1);
    const line = String(warn.mock.calls[0][0]);
    expect(line).toContain('requested page 2');
    expect(line).toContain('received page missing');
  });

  it('stops after 100 follow-ups when total_pages keeps growing', async () => {
    const server = stubServer((requested) => ({
      page: requested,
      per_page: 1,
      total_pages: requested + 1
    }));
    const rows = await list(client);
    expect(server).toHaveBeenCalledTimes(101);
    expect(rows).toHaveLength(101);
    expect(warn).toHaveBeenCalledTimes(1);
    const line = String(warn.mock.calls[0][0]);
    expect(line).toContain('requested page 102');
    expect(line).toContain('received page 101');
  });

  it('reads every page of a correct server without logging', async () => {
    const server = stubServer((requested) => ({ page: requested, per_page: 1, total_pages: 3 }));
    const rows = await list(client);
    expect(server).toHaveBeenCalledTimes(3);
    expect(ids(rows)).toEqual(['row-1', 'row-2', 'row-3']);
    expect(warn).not.toHaveBeenCalled();
  });

  it('does not log when the last allowed follow-up is the last page', async () => {
    const server = stubServer((requested) => ({ page: requested, per_page: 1, total_pages: 101 }));
    const rows = await list(client);
    expect(server).toHaveBeenCalledTimes(101);
    expect(rows).toHaveLength(101);
    expect(warn).not.toHaveBeenCalled();
  });

  it('does not follow when the caller names a page', async () => {
    const server = stubServer((requested) => ({ page: requested, per_page: 1, total_pages: 3 }));
    const rows = await list(client, { page: 2 });
    expect(server).toHaveBeenCalledTimes(1);
    expect(ids(rows)).toEqual(['row-2']);
    expect(warn).not.toHaveBeenCalled();
  });

  it('reads a first response without meta.page as page 1', async () => {
    const server = stubServer((requested) =>
      requested === 1
        ? { per_page: 1, total_pages: 2 }
        : { page: requested, per_page: 1, total_pages: 2 }
    );
    const rows = await list(client);
    expect(server).toHaveBeenCalledTimes(2);
    expect(ids(rows)).toEqual(['row-1', 'row-2']);
    expect(warn).not.toHaveBeenCalled();
  });
});
