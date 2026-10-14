import { describe, expect, it } from 'vitest';
import { FeedbackKit } from '../src';
import { collectList } from '../src/api/listPages';

const base = process.env.FEEDBACKKIT_LIVE_BASE_URL;
const apiKey = process.env.FEEDBACKKIT_LIVE_API_KEY;
const visibleCount = Number(process.env.FEEDBACKKIT_LIVE_FEEDBACK_COUNT ?? '0');
const commentFeedbackId = process.env.FEEDBACKKIT_LIVE_COMMENT_FEEDBACK_ID;
const commentCount = Number(process.env.FEEDBACKKIT_LIVE_COMMENT_COUNT ?? '0');

const live = base && apiKey ? describe : describe.skip;

live('REL-05 live server', () => {
  // Vitest runs a skipped suite's factory. Build the client inside each test
  // so a missing key does not throw while the suite is being registered.
  function client(): FeedbackKit {
    return new FeedbackKit({ apiKey: apiKey!, baseUrl: base });
  }

  it('walks the opted-in envelope and stops after one legacy array', async () => {
    const all = await client().feedback.list();
    expect(all).toHaveLength(visibleCount);
    expect(new Set(all.map((item) => item.id)).size).toBe(visibleCount);

    const page = await client().feedback.list({ page: 1, perPage: 5 });
    expect(page).toHaveLength(5);
    expect(page.map((item) => item.id)).toEqual(all.slice(0, 5).map((item) => item.id));

    let calls = 0;
    const legacy = await collectList<{ id: string }>(async () => {
      calls += 1;
      const response = await fetch(`${base}/feedbacks?page=2&per_page=1`, {
        headers: { 'X-API-Key': apiKey! }
      });
      expect(response.ok).toBe(true);
      return response.json();
    });
    expect(calls).toBe(1);
    expect(legacy).toHaveLength(visibleCount);
  });

  it('walks comments and reads one opted-in page', async () => {
    expect(commentFeedbackId).toBeTruthy();
    const all = await client().comments.list(commentFeedbackId!);
    expect(all).toHaveLength(commentCount);

    const page = await client().comments.list(commentFeedbackId!, { page: 2, perPage: 5 });
    expect(page).toHaveLength(5);
    expect(page.map((item) => item.id)).toEqual(all.slice(5, 10).map((item) => item.id));
  });
});
