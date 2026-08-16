import { describe, it, expect, vi, beforeEach } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import {
  FeedbackKit,
  FeedbackStatus,
  DEFAULT_CONFIG,
  FeedbackKitError,
  AuthenticationError,
  PaymentRequiredError,
  ForbiddenError,
  NotFoundError,
  ConflictError,
  ValidationError
} from '../src';
// Deep import, deliberately: `createErrorFromResponse` is NOT re-exported from the
// barrel (`src/index.ts`) — a case below pins that as shipped, reading the barrel source.
import { createErrorFromResponse } from '../src/models/errors';
import { HttpClient } from '../src/utils/http';

/**
 * `QA-UNIT10-SDK-PARITY`, JS lane — `-05`, `-10`, `-15`, `-17`, `-21`, `-22`
 * (with `-16` noted in the config group's comments).
 *
 * The corpora under `tests/fixtures/` are **not** written here. They are the committed
 * server-generated wire corpus files; hand-writing a wire fixture in a test is exactly
 * the second guess at the contract this suite exists to prevent.
 *
 * The transforms under test (`snakeToCamel` / `camelToSnake`) are module-private inside
 * `src/utils/http.ts`. Re-implementing them here is forbidden — a second definition is
 * the defect class this unit hunts — so every case drives the **exported** seam, the real
 * `HttpClient`, with a stubbed `fetch`: decode cases feed it corpus bytes and read the
 * result; encode cases hand it a camelCase body and read the bytes it put on the wire.
 *
 * `-10` note: the existing `tests/client.test.ts` "error handling" group asserts
 * 401/402/409 by MESSAGE only (`rejects.toThrow('Invalid API key')` etc. — the test
 * names claim classes the assertions never check). This file is where the class/code
 * mapping is actually pinned.
 */

function loadCorpus<T>(name: string): T {
  const path = fileURLToPath(new URL(`./fixtures/${name}`, import.meta.url));
  return JSON.parse(readFileSync(path, 'utf8')) as T;
}

const toleranceCorpus = loadCorpus<Array<Record<string, unknown>>>(
  'feedback-tolerance-corpus.json'
);
const voteCorpus = loadCorpus<Array<Record<string, unknown>>>('vote-wire-corpus.json');
const sdkUserCorpus = loadCorpus<Array<Record<string, unknown>>>(
  'sdk-user-wire-corpus.json'
);
const eventCorpus = loadCorpus<Array<Record<string, unknown>>>('event-wire-corpus.json');
const requestCanon = loadCorpus<Record<string, Record<string, unknown>>>(
  'request-wire-corpus.json'
);

const mockFetch = vi.fn();
global.fetch = mockFetch;

function makeHttp(): HttpClient {
  return new HttpClient({
    baseUrl: 'https://unit.invalid/api/v1',
    apiKey: 'sf_test_key',
    timeout: 5000
  });
}

/** Decode `payload` through the real `HttpClient` — the real, private `snakeToCamel`. */
async function decodeThroughHttp<T>(payload: unknown): Promise<T> {
  mockFetch.mockResolvedValueOnce({
    ok: true,
    status: 200,
    headers: { get: () => 'application/json' },
    json: async () => payload
  });
  return makeHttp().get<T>('/probe');
}

/** Encode `body` through the real `HttpClient` and return the bytes it put on the
 *  wire, parsed — the real, private `camelToSnake` plus `JSON.stringify`. */
async function encodeThroughHttp(body: unknown): Promise<Record<string, unknown>> {
  mockFetch.mockResolvedValueOnce({
    ok: true,
    status: 200,
    headers: { get: () => 'application/json' },
    json: async () => ({})
  });
  await makeHttp().post('/probe', body);
  const init = mockFetch.mock.calls[mockFetch.mock.calls.length - 1][1] as {
    body: string;
  };
  return JSON.parse(init.body) as Record<string, unknown>;
}

beforeEach(() => {
  mockFetch.mockReset();
});

describe('QA-UNIT10 -05 · JS list tolerance', () => {
  // ⚠️ RECORDED AS SHIPPED: the JS SDK has NO runtime validation of enum-typed fields.
  // TypeScript types are erased at compile time and `snakeToCamel` renames keys without
  // ever looking at values, so a status token the enum has never heard of decodes
  // "successfully" and flows to render sites typed `FeedbackStatus`. The oracle here is
  // therefore the EXACT OPPOSITE of the Swift/Kotlin arms: the unknown row is PRESENT.
  // Swift/Kotlin reject or coerce the unknown status; JS passes `"quantum_launch"`
  // through unvalidated, and any switch over the enum falls through on it. There is no
  // validation hook to test — this group pins that the tolerance behavior is
  // "everything survives", so the day validation is added, this reddens and the JS arm
  // joins the reject/coerce census.

  it('all four corpus rows survive the decode — nothing dropped, nothing thrown', async () => {
    const items = await decodeThroughHttp<Array<Record<string, unknown>>>(
      toleranceCorpus
    );

    expect(items).toHaveLength(4);
    expect(items.map((i) => i.title)).toEqual([
      'Tolerance row one',
      'Tolerance row two',
      'Tolerance row three',
      'Tolerance row four'
    ]);
    // The known statuses came through as their wire spellings — the corpus really
    // exercises members of the enum around the unknown one.
    expect(items[0].status).toBe(FeedbackStatus.Pending);
    expect(items[1].status).toBe(FeedbackStatus.TestFlight);
    expect(items[3].status).toBe(FeedbackStatus.Completed);
  });

  it('the unknown-status row is PRESENT, its status the raw token, unvalidated', async () => {
    const items = await decodeThroughHttp<Array<Record<string, unknown>>>(
      toleranceCorpus
    );
    const unknownRow = items[2];

    expect(unknownRow.title).toBe('Tolerance row three');
    expect(unknownRow.status).toBe('quantum_launch');
    // And that token is genuinely NOT a member of the enum — so the row above is the
    // unknown one, not a sixth spelling this file forgot about.
    expect(Object.values(FeedbackStatus).includes('quantum_launch' as FeedbackStatus)).toBe(
      false
    );
  });

  it('an unknown extra key also survives, camelCased, on the row that carries it', async () => {
    // The same erasure that lets an unknown status through lets an unknown KEY through:
    // no interface strips it at runtime. Row 3 is the corpus's forward-compat probe.
    const items = await decodeThroughHttp<Array<Record<string, unknown>>>(
      toleranceCorpus
    );

    expect(items[3].unknownFutureKey).toBe('from-a-newer-server');
    // Paired negative: the fixture really is the only row carrying it.
    expect(items[2].unknownFutureKey).toBeUndefined();
    expect(toleranceCorpus[3].unknown_future_key).toBe('from-a-newer-server');
  });
});

describe('QA-UNIT10 -10 · JS error map by class and code', () => {
  /** The mapping `src/models/errors.ts` ships, pinned per status:
   *  [status, exact constructor, code]. */
  const ERROR_MAP: ReadonlyArray<
    readonly [number, new (...args: never[]) => FeedbackKitError, string]
  > = [
    [400, ValidationError, 'BAD_REQUEST'],
    [401, AuthenticationError, 'UNAUTHORIZED'],
    [402, PaymentRequiredError, 'PAYMENT_REQUIRED'],
    [403, ForbiddenError, 'FORBIDDEN'],
    [404, NotFoundError, 'NOT_FOUND'],
    [409, ConflictError, 'CONFLICT'],
    // ⚠️ RECORDED AS SHIPPED: nobody maps 422. A Vapor validation failure that arrives
    // as 422 Unprocessable Entity falls into the default arm and surfaces as a generic
    // `FeedbackKitError` with code SERVER_ERROR — an integrator branching on
    // `ValidationError` never sees it.
    [422, FeedbackKitError, 'SERVER_ERROR'],
    [429, FeedbackKitError, 'SERVER_ERROR'],
    // ⚠️ RECORDED AS SHIPPED: no `ServerError` class exists in the JS SDK, while
    // Flutter and Kotlin each ship one. 5xx collapses into the base class with the
    // catch-all SERVER_ERROR code, indistinguishable (by class) from 422 and 429.
    [500, FeedbackKitError, 'SERVER_ERROR'],
    [503, FeedbackKitError, 'SERVER_ERROR']
  ];

  it('maps every status to the pinned class, code and statusCode', () => {
    for (const [status, cls, code] of ERROR_MAP) {
      const error = createErrorFromResponse(status, {
        error: true,
        reason: `probe ${status}`
      });

      expect(error).toBeInstanceOf(cls);
      // Exact constructor, not just instanceof: every subclass IS an instance of the
      // base, so `toBeInstanceOf(FeedbackKitError)` alone would be green for a 500
      // that suddenly returned `ValidationError`. The identity check cannot be.
      expect(error.constructor).toBe(cls);
      expect(error.code).toBe(code);
      expect(error.statusCode).toBe(status);
      // The server's `reason` is the message — the plumbing client.test.ts checks by
      // message is the same plumbing, asserted here per status.
      expect(error.message).toBe(`probe ${status}`);
    }
    // Non-vacuity: the table covers the six mapped statuses plus four default-arm ones.
    expect(ERROR_MAP).toHaveLength(10);
  });

  it('the default arm is the BASE class exactly — no subclass leaks in', () => {
    const error = createErrorFromResponse(500, 'plain text body');
    expect(error.constructor).toBe(FeedbackKitError);
    expect(error).not.toBeInstanceOf(ValidationError);
    expect(error).not.toBeInstanceOf(AuthenticationError);
    // A string body is the message verbatim (non-JSON error responses).
    expect(error.message).toBe('plain text body');
  });

  it('createErrorFromResponse is NOT exported from the barrel — deep import only', () => {
    // ⚠️ RECORDED AS SHIPPED: `src/index.ts` re-exports all eight error CLASSES but not
    // the factory, so an integrator (or a test) can only reach it by deep-importing
    // `src/models/errors` — which is what this file does, and why. The day the barrel
    // gains the export, this reddens and the deep import above should move to '../src'.
    const barrel = readFileSync(
      fileURLToPath(new URL('../src/index.ts', import.meta.url)),
      'utf8'
    );
    expect(barrel).not.toContain('createErrorFromResponse');
    // Paired positive: this really is the barrel that exports the error surface, not an
    // empty or wrong file read green.
    expect(barrel).toContain('FeedbackKitError');
    expect(barrel).toContain("from './models/errors'");
  });
});

describe('QA-UNIT10 -15/-17 · JS config defaults and missing-key throw', () => {
  it('-15 · DEFAULT_CONFIG pins the production URL and timeout', () => {
    // NOTE (-16): the JS default INCLUDES the `/api/v1` path suffix — as do Swift and
    // Flutter — while Kotlin and Vapor store the bare origin and append the path per
    // request. Same wire result, but a 4-vs-2 semantic split: an integrator moving
    // between SDKs and copying a `baseUrl` override gets a doubled or missing prefix.
    expect(DEFAULT_CONFIG.baseUrl).toBe('https://api.prod.getfeedbackkit.com/api/v1');
    expect(DEFAULT_CONFIG.timeout).toBe(30000);
  });

  it('-17 · missing apiKey throws a BARE Error, not a FeedbackKitError', () => {
    // ⚠️ RECORDED AS SHIPPED: `client.ts` throws `new Error('FeedbackKit: apiKey is
    // required')` — the one SDK-authored throw that is NOT a `FeedbackKitError`. An
    // integrator's `catch (e) { if (e instanceof FeedbackKitError) ... }` misses the
    // very first error the SDK can produce. Asserted verbatim, both halves.
    let thrown: unknown;
    try {
      new FeedbackKit({} as never);
    } catch (error) {
      thrown = error;
    }

    expect(thrown).toBeInstanceOf(Error);
    expect(thrown).not.toBeInstanceOf(FeedbackKitError);
    expect((thrown as Error).message).toBe('FeedbackKit: apiKey is required');
  });
});

describe('QA-UNIT10 -21 · JS decode census (immune by construction)', () => {
  // JS is the census's positive arm: `snakeToCamel` renames every key mechanically, so
  // the decoded key set is exactly the wire key set camelCased — there is no per-field
  // decoder to omit a field in (the defect class the census hunts in the other SDKs).
  // Asserted as key-set EQUALITIES: a per-key presence check cannot see an extra.

  it('vote corpus row 0 decodes to exactly the VoteResponse key set', async () => {
    const rows = await decodeThroughHttp<Array<Record<string, unknown>>>(voteCorpus);

    expect(Object.keys(rows[0]).sort()).toEqual(
      ['feedbackId', 'voteCount', 'hasVoted'].sort()
    );
    expect(rows[0].feedbackId).toBe(voteCorpus[0].feedback_id);
    expect(rows[0].voteCount).toBe(8);
    expect(rows[0].hasVoted).toBe(true);
    // Row 1 is the falsy row — so the values above are not truthiness accidents — and
    // the wire has no `success` key for any SDK to have invented a field from.
    expect(rows[1].hasVoted).toBe(false);
    expect(rows[1].voteCount).toBe(0);
    expect(Object.keys(voteCorpus[0])).not.toContain('success');
  });

  it('sdk-user corpus row 0 decodes to exactly the SDKUser key set', async () => {
    const rows = await decodeThroughHttp<Array<Record<string, unknown>>>(sdkUserCorpus);

    expect(Object.keys(rows[0]).sort()).toEqual(
      ['id', 'userId', 'mrr', 'firstSeenAt', 'lastSeenAt'].sort()
    );
    expect(rows[0].userId).toBe(sdkUserCorpus[0].user_id);
    expect(rows[0].mrr).toBe(42.5);
    // The sparse row carries only the two required keys — optionals are absent, not null.
    expect(Object.keys(rows[1]).sort()).toEqual(['id', 'userId'].sort());
  });

  it('event corpus row 0 decodes to exactly the TrackedEvent key set', async () => {
    const rows = await decodeThroughHttp<Array<Record<string, unknown>>>(eventCorpus);

    expect(Object.keys(rows[0]).sort()).toEqual(
      ['id', 'eventName', 'userId', 'properties', 'createdAt'].sort()
    );
    expect(rows[0].eventName).toBe(eventCorpus[0].event_name);
    // The nested properties object survives (recursion), keys intact.
    expect(rows[0].properties).toEqual({ source: 'fixture-tab' });
    expect(Object.keys(rows[1]).sort()).toEqual(
      ['id', 'eventName', 'userId', 'createdAt'].sort()
    );
  });
});

describe('QA-UNIT10 -22 · JS encode census (immune by construction)', () => {
  // Same immunity, outbound: `camelToSnake` runs over whatever the caller passes, so
  // the wire key set is exactly the request object's keys snake_cased. The expected
  // sets are loaded from `request-wire-corpus.json` — the canon is never retyped here.

  it('a full CreateFeedbackRequest encodes to exactly the create_feedback canon keys', async () => {
    const sent = await encodeThroughHttp({
      title: 'Add a dark theme',
      description: 'The list is hard to read at night.',
      category: 'feature_request',
      userId: 'fixture-end-user',
      userEmail: 'fixture-user@example.invalid',
      subscribeToMailingList: true,
      mailingListEmailTypes: ['status_change']
    });

    expect(Object.keys(sent).sort()).toEqual(
      Object.keys(requestCanon.create_feedback).sort()
    );
    // Values rode along under the renamed keys — a key-set check alone would be green
    // over a transform that renamed keys and dropped every value.
    expect(sent.user_id).toBe('fixture-end-user');
    expect(sent.subscribe_to_mailing_list).toBe(true);
    expect(sent.mailing_list_email_types).toEqual(['status_change']);
    // Non-vacuity of the canon itself: seven keys, not an emptied fixture.
    expect(Object.keys(requestCanon.create_feedback)).toHaveLength(7);
  });

  it('a full VoteRequest encodes to exactly the create_vote canon keys', async () => {
    const sent = await encodeThroughHttp({
      userId: 'fixture-end-user',
      email: 'fixture-user@example.invalid',
      notifyStatusChange: true,
      subscribeToMailingList: true,
      mailingListEmailTypes: ['status_change']
    });

    expect(Object.keys(sent).sort()).toEqual(
      Object.keys(requestCanon.create_vote).sort()
    );
    expect(sent.notify_status_change).toBe(true);
    expect(sent.email).toBe('fixture-user@example.invalid');
    expect(Object.keys(requestCanon.create_vote)).toHaveLength(5);
  });
});
