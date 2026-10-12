import { describe, it, expect, vi, beforeEach } from 'vitest';
// The source-census helpers live in one place: a second copy of `stripComments` could
// drift, and every absence gate below depends on it being the same stripper.
import { readFileSync } from 'node:fs';
import { relative } from 'node:path';
import {
  SRC_ROOT,
  listSrcFiles,
  loadCorpus,
  readSrc,
  stripComments
} from './helpers/source-census';
import {
  FeedbackKitError,
  PaymentRequiredError,
  ForbiddenError,
  ValidationError,
  RateLimitError
} from '../src';
// Deep import, deliberately: `createErrorFromResponse` is NOT re-exported from the
// barrel — `sdk-parity.test.ts` pins that as shipped, reading the barrel source.
import { createErrorFromResponse } from '../src/models/errors';
import { HttpClient } from '../src/utils/http';

/**
 * `QA-UNIT10-SDK-PARITY`, JS lane — the transport half of `-10`, `-21` and `-22`,
 * extended for the metrics wire contract (`METRICS03` phase `01` §6, `C4`/`C6`/`C7`).
 *
 * Same rules as `sdk-parity.test.ts`, and for the same reasons:
 *
 * - **No wire fixture is hand-written here.** Every wire byte comes from a committed,
 *   server-generated corpus under `tests/fixtures/`. The one exception is the shape-B
 *   status vector in the error matrix. The middleware section USED to be the one
 *   exception — bare bodies with no status, paired to statuses by index against the
 *   contract table's prose — and that gap is now closed: every middleware row carries
 *   its own `http_status`, and rows are selected by content, never by position.
 * - **The transforms are never re-implemented.** `snakeToCamel` / `camelToSnake` are
 *   module-private in `src/utils/http.ts`; every case drives the exported `HttpClient`
 *   seam with a stubbed `fetch`, so the transform under test is the shipped one.
 * - **Set equality and totals, never `contains`.** A presence oracle cannot see an
 *   extra key, an extra error class or an extra wire token.
 */

// ---------------------------------------------------------------------------
// Corpora
// ---------------------------------------------------------------------------

type Json = Record<string, unknown>;

interface MetricsCorpus {
  breakdown_event_name_with_overflow: {
    dimension: string;
    items: Array<{ key: string; is_overflow: boolean; values: Record<string, number> }>;
    meta: Json;
  };
  events_page: {
    items: Array<{ id: string; event_name: string; properties?: Record<string, unknown> }>;
    meta: Json;
    metrics: Json;
  };
  summary_free_scoped_and_clamped: { meta: Json; values: Record<string, number> };
  summary_team_all_scope: { meta: Json; values: Record<string, number> };
  timeseries_daily: {
    meta: Json;
    series: Array<{ bucket: string; values: Record<string, number> }>;
  };
}

interface ErrorCorpus {
  enveloped: Array<{
    error: { code: string; message: string; field?: string };
    timestamp: string;
  }>;
  middleware: Array<{
    http_status: number;
    source: string;
    body: { error: boolean; reason: string };
  }>;
  vocabulary: Array<{
    wire_token: string;
    detailed_token: string;
    http_status: number;
  }>;
}

const metricsCorpus = loadCorpus<MetricsCorpus>('metrics-wire-corpus.json');
const errorCorpus = loadCorpus<ErrorCorpus>('metrics-error-wire-corpus.json');
const eventCorpus = loadCorpus<Array<Json>>('event-wire-corpus.json');

// ---------------------------------------------------------------------------
// The seam: the real HttpClient over a stubbed fetch
// ---------------------------------------------------------------------------

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
async function encodeThroughHttp(body: unknown): Promise<Json> {
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
  return JSON.parse(init.body) as Json;
}

/** Issue a GET through the real client and return the URL string it asked fetch for. */
async function urlThroughHttp(
  params: Parameters<HttpClient['get']>[1]
): Promise<string> {
  mockFetch.mockResolvedValueOnce({
    ok: true,
    status: 200,
    headers: { get: () => 'application/json' },
    json: async () => ({})
  });
  await makeHttp().get('/probe', params);
  return mockFetch.mock.calls[mockFetch.mock.calls.length - 1][0] as string;
}

// ---------------------------------------------------------------------------
// Source-census helpers
// ---------------------------------------------------------------------------

beforeEach(() => {
  mockFetch.mockReset();
});

// ---------------------------------------------------------------------------

describe('G2 · the query params type admits number', () => {
  // ⚠️ A RUNTIME test cannot see this change. TypeScript types are erased, and
  // `http.get('/x', { days: 7 })` worked at runtime before the widening too. The
  // real oracle for the first leg is `tsc -p tsconfig.test.json` — `tsconfig.json`
  // excludes `tests`, so this file is only type-checked by that second config.
  it('accepts integer-valued params at the type level and on the wire', async () => {
    const numericParams: Parameters<HttpClient['get']>[1] = {
      days: 7,
      page: 1,
      per_page: 200
    };

    const url = await urlThroughHttp(numericParams);
    const query = new URL(url).searchParams;

    // Ordered key equality — an extra or renamed key reds, which `contains` cannot see.
    expect([...query.keys()]).toEqual(['days', 'page', 'per_page']);
    expect(query.get('days')).toBe('7');
    expect(query.get('page')).toBe('1');
    expect(query.get('per_page')).toBe('200');
    // The keys went out verbatim — `per_page` was NOT camelCased or snake_cased by the
    // client. §0.2 of the phase plan: query keys are never case-converted.
    expect(url).toContain('per_page=200');
  });

  it('mixes string, number, boolean and undefined in one params object', async () => {
    const url = await urlThroughHttp({
      event_name: 'checkout_completed',
      days: 30,
      truncated: false,
      omitted: undefined
    });
    const query = new URL(url).searchParams;

    // `undefined` is dropped, not stringified to "undefined".
    expect([...query.keys()]).toEqual(['event_name', 'days', 'truncated']);
    expect(query.get('truncated')).toBe('false');
    expect(query.get('omitted')).toBeNull();
  });
});

describe('G3 · a `values` map survives the decode verbatim', () => {
  it('breakdown item `values` keys equal the wire keys exactly, per item', async () => {
    const wire = metricsCorpus.breakdown_event_name_with_overflow;
    const decoded = await decodeThroughHttp<{
      items: Array<{ values: Record<string, number>; isOverflow: boolean; key: string }>;
    }>(wire);

    expect(decoded.items).toHaveLength(wire.items.length);
    for (let i = 0; i < wire.items.length; i += 1) {
      // Set equality per item: a converted key AND an invented key both red.
      expect(Object.keys(decoded.items[i].values).sort()).toEqual(
        Object.keys(wire.items[i].values).sort()
      );
    }

    // Non-vacuity of the FIXTURE: at least one measure token is genuinely multi-word.
    // A corpus of single-word tokens would be structurally blind to key mangling here,
    // exactly as the shipped `properties` fixtures are (see G4).
    const allMeasureKeys = wire.items.flatMap((item) => Object.keys(item.values));
    expect(allMeasureKeys.length).toBeGreaterThan(0);
    expect(allMeasureKeys.some((k) => /_/.test(k))).toBe(true);
  });

  it('the sparse overflow item keeps exactly one measure — an absent key is contract', async () => {
    const wire = metricsCorpus.breakdown_event_name_with_overflow;
    const overflowIndex = wire.items.findIndex((item) => item.is_overflow);
    expect(overflowIndex).toBeGreaterThanOrEqual(0);

    const decoded = await decodeThroughHttp<{
      items: Array<{ values: Record<string, number> }>;
    }>(wire);
    const overflow = decoded.items[overflowIndex].values;

    expect(Object.keys(overflow)).toEqual(['event_count']);
    // C4: a distinct-user count is not additive across elided names, so the server
    // omits it. Absent, never null and never zero.
    expect(overflow.unique_event_users).toBeUndefined();
    expect(overflow.event_count).toBe(wire.items[overflowIndex].values.event_count);
  });

  it('PAIRED SIBLING: the keys AROUND `values` are still converted', async () => {
    // Without this leg, a blanket disable of `snakeToCamel` passes every assertion above.
    const wire = metricsCorpus.breakdown_event_name_with_overflow;
    const decoded = await decodeThroughHttp<{
      items: Array<{ isOverflow: boolean; is_overflow?: boolean }>;
      meta: { retentionWindowDays: number; eventScope: string; retention_window_days?: number };
    }>(wire);

    expect(decoded.items[1].isOverflow).toBe(true);
    expect(decoded.items[1].is_overflow).toBeUndefined();
    expect(decoded.meta.retentionWindowDays).toBe(365);
    expect(decoded.meta.retention_window_days).toBeUndefined();
    expect(decoded.meta.eventScope).toBe('all');
  });

  it('summary and timeseries `values` maps are exempt on the same rule', async () => {
    const summaryWire = metricsCorpus.summary_team_all_scope;
    const summary = await decodeThroughHttp<{ values: Record<string, number> }>(
      summaryWire
    );
    expect(Object.keys(summary.values).sort()).toEqual(
      Object.keys(summaryWire.values).sort()
    );
    expect(summary.values.mrr_average).toBe(summaryWire.values.mrr_average);

    const seriesWire = metricsCorpus.timeseries_daily;
    const series = await decodeThroughHttp<{
      series: Array<{ bucket: string; values: Record<string, number> }>;
    }>(seriesWire);
    expect(series.series).toHaveLength(seriesWire.series.length);
    for (let i = 0; i < seriesWire.series.length; i += 1) {
      expect(Object.keys(series.series[i].values).sort()).toEqual(
        Object.keys(seriesWire.series[i].values).sort()
      );
      // The sibling key `bucket` is present and there is no invented `bucket_start`.
      expect(series.series[i].bucket).toBe(seriesWire.series[i].bucket);
    }
    expect(Object.keys(series.series[0])).toEqual(['bucket', 'values']);
  });
});

describe('G4 · `properties` survives verbatim in BOTH directions', () => {
  /**
   * A deliberately DISCRIMINATING probe. The shipped corpora's `properties` objects
   * carry `{ source: 'fixture-tab' }` — `source` is a single word, invariant under
   * both key transforms, so those fixtures cannot see this defect at all.
   *
   * `planTier` is red when only the ENCODE side descends; `step_count` is red when
   * only the DECODE side does. One of each is what makes the round-trip leg red both
   * before this change and after a half-fix.
   */
  const probe = { planTier: 'pro', step_count: 5 };

  it('the probe is actually discriminating (the shipped fixtures are not)', () => {
    expect(Object.keys(probe).some((k) => /[_A-Z]/.test(k))).toBe(true);
    // Both wrong states are reachable from this one probe: a camelCase key and a
    // snake_case key.
    expect(Object.keys(probe).some((k) => /[A-Z]/.test(k))).toBe(true);
    expect(Object.keys(probe).some((k) => /_/.test(k))).toBe(true);
    // And the shipped corpus really is blind — recorded, not assumed.
    const shipped = eventCorpus[0].properties as Record<string, unknown>;
    expect(Object.keys(shipped).some((k) => /[_A-Z]/.test(k))).toBe(false);
  });

  it('DECODE · an event row keeps its wire property keys exactly', async () => {
    const wire = metricsCorpus.events_page;
    const decoded = await decodeThroughHttp<{
      items: Array<{ properties?: Record<string, unknown>; eventName: string }>;
    }>(wire);

    const wireProps = wire.items[0].properties as Record<string, unknown>;
    // The event feed's own fixture is multi-word (`checkout_step`, `utm_source`), so
    // this leg discriminates without a hand-written probe.
    expect(Object.keys(wireProps).some((k) => /_/.test(k))).toBe(true);
    expect(Object.keys(decoded.items[0].properties ?? {}).sort()).toEqual(
      Object.keys(wireProps).sort()
    );
    // PAIRED SIBLING: keys around `properties` are still converted.
    expect(decoded.items[0].eventName).toBe(wire.items[0].event_name);
    // The sparse row carries no `properties` at all — absent, not an empty object.
    expect(decoded.items[1].properties).toBeUndefined();
  });

  it('ENCODE · `properties` goes on the wire verbatim while its siblings are snake_cased', async () => {
    const sent = await encodeThroughHttp({
      eventName: 'checkout_completed',
      userId: 'fixture-end-user',
      properties: probe
    });

    // The exempted KEY is still renamed by the same rule as any other — `properties`
    // is single-word, so its pre- and post-conversion spellings coincide. Asserted
    // rather than relied upon.
    expect(Object.keys(sent).sort()).toEqual(
      ['event_name', 'user_id', 'properties'].sort()
    );
    // The contents crossed byte-identical.
    expect(sent.properties).toEqual(probe);
    expect(Object.keys(sent.properties as Json)).toEqual(Object.keys(probe));
    // PAIRED SIBLING: this is an exemption, not a disabled transform.
    expect(sent.event_name).toBe('checkout_completed');
    expect(sent.user_id).toBe('fixture-end-user');
  });

  it('ROUND-TRIP · encode then decode returns the probe key-for-key', async () => {
    // 🔴 Red on arrival on `step_count` (wire `step_count` → back `stepCount`), and
    // STILL red after a decode-only half-fix on `planTier` (wire `plan_tier` → back
    // `plan_tier`). Before this change the two transforms cancelled and the camelCase
    // key round-tripped by accident; fixing one side alone breaks that accident.
    const sent = await encodeThroughHttp({
      eventName: 'checkout_completed',
      userId: 'fixture-end-user',
      properties: probe
    });
    const back = await decodeThroughHttp<{ properties: Record<string, unknown> }>(sent);

    expect(back.properties).toEqual(probe);
    expect(Object.keys(back.properties).sort()).toEqual(Object.keys(probe).sort());
  });

  it('the shipped single-word corpus stays green — behaviour is unchanged there', async () => {
    const rows = await decodeThroughHttp<Array<Json>>(eventCorpus);
    expect(rows[0].properties).toEqual({ source: 'fixture-tab' });
  });
});

describe('G5 · both error body shapes, as a total matrix', () => {
  /**
   * Shape-A statuses are DERIVED from the corpus: the vocabulary section pairs every
   * wire token with the status it is served at, so an enveloped row's status is a
   * lookup, never a literal typed here.
   */
  function statusForToken(token: string): number {
    const statuses = new Set(
      errorCorpus.vocabulary
        .filter((row) => row.wire_token === token)
        .map((row) => row.http_status)
    );
    expect(statuses.size).toBe(1);
    return [...statuses][0];
  }

  const CLASS_FOR_STATUS: Record<number, new (...args: never[]) => FeedbackKitError> = {
    400: ValidationError,
    402: PaymentRequiredError,
    403: ForbiddenError
  };

  /**
   * Shape-B statuses are DERIVED too, as of the phase-`02` corpus reshape: every
   * middleware row now carries its own `http_status`, read by the generator off the
   * same server source line the `reason` literal occurs on. There is no hand-written
   * status vector in this file any more.
   *
   * Rows are selected BY CONTENT, never by index. The previous revision paired
   * `middleware[i]` to a literal `[401, 403, 403, 404, 429, 500]` typed from the
   * contract table's C6 prose; four more SDKs were about to repeat that pairing, and
   * inserting or reordering a single row would then have re-paired the matrix in all
   * five at once with every suite still internally consistent and nothing able to red.
   */
  function middlewareRow(reasonFragment: string) {
    const matches = errorCorpus.middleware.filter((row) =>
      row.body.reason.includes(reasonFragment)
    );
    // Exactly one, so a fragment that stops discriminating reds here rather than
    // silently selecting whichever row happens to sort first.
    expect(matches).toHaveLength(1);
    return matches[0];
  }

  it('the corpus really carries TWO shapes — cardinality, not presence', () => {
    const bodies: unknown[] = [
      ...errorCorpus.enveloped,
      ...errorCorpus.middleware.map((row) => row.body)
    ];
    const shapes = new Set(
      bodies.map((b) => typeof (b as { error: unknown }).error)
    );

    // Derived from the corpus, never seeded: a one-shape corpus (or a decoder gate
    // written against one) collapses this to 1 and reds.
    expect(shapes.size).toBe(2);
    expect([...shapes].sort()).toEqual(['boolean', 'object']);
    expect(bodies.length).toBe(
      errorCorpus.enveloped.length + errorCorpus.middleware.length
    );
    expect(bodies.length).toBeGreaterThan(0);
  });

  it('SHAPE A · the server message and the server token both reach the error', () => {
    const rows = errorCorpus.enveloped.map((body) => {
      const status = statusForToken(body.error.code);
      return { body, status, cls: CLASS_FOR_STATUS[status] };
    });

    for (const { body, status, cls } of rows) {
      expect(cls).toBeDefined();
      const error = createErrorFromResponse(status, body);

      expect(error.constructor).toBe(cls);
      expect(error.statusCode).toBe(status);
      // The server's TOKEN, not the class default.
      expect(error.code).toBe(body.error.code);
      // The server's MESSAGE, not the class default. Before this phase this was lost
      // entirely — `body.reason` is undefined on shape A, so the class default won.
      expect(error.message).toBe(body.error.message);
    }

    // Non-vacuity, derived from the corpus row count rather than typed in.
    expect(rows).toHaveLength(errorCorpus.enveloped.length);
    expect(rows.length).toBeGreaterThan(0);
    // And the corpus really exercises more than one status on this shape.
    expect(new Set(rows.map((r) => r.status)).size).toBeGreaterThan(1);
  });

  it('SHAPE B · the class default code survives byte-for-byte, message is the reason', () => {
    expect(errorCorpus.middleware).toHaveLength(6);
    // The six reasons are pairwise distinct, so `middlewareRow` is well-defined.
    // NOTE: the six STATUSES are not distinct — 403 legitimately repeats — so
    // distinctness may only ever be asserted on the reason.
    expect(new Set(errorCorpus.middleware.map((r) => r.body.reason)).size).toBe(
      errorCorpus.middleware.length
    );

    // Each row drives the decoder with ITS OWN status, straight off the row.
    const observed = errorCorpus.middleware.map((row) => {
      const error = createErrorFromResponse(row.http_status, row.body);
      return {
        status: error.statusCode,
        code: error.code,
        message: error.message,
        name: error.constructor.name
      };
    });

    // Asserted as ONE vector, not per-iteration: a per-iteration assert stops at the
    // first failure and under-reports how many rows are actually wrong.
    //
    // The expectation is built by CONTENT lookup, so it describes the six failures
    // rather than six positions. Reordering the corpus permutes both sides together
    // and this stays green — which is the point; the old index pairing would have
    // gone green on a WRONG pairing instead.
    const expected = (
      [
        ['Invalid API key', 'UNAUTHORIZED', 'AuthenticationError'],
        ['This project is suspended.', 'FORBIDDEN', 'ForbiddenError'],
        ["You don't have access", 'FORBIDDEN', 'ForbiddenError'],
        ['Project not found', 'NOT_FOUND', 'NotFoundError'],
        ['Too many requests', 'RATE_LIMITED', 'RateLimitError'],
        ['metrics_invalid_reporting_timezone', 'SERVER_ERROR', 'ServerError']
      ] as const
    ).map(([fragment, code, name]) => {
      const row = middlewareRow(fragment);
      return { status: row.http_status, code, message: row.body.reason, name };
    });

    // Same order on both sides, so `toEqual` compares row-for-row.
    expect(observed).toEqual(
      errorCorpus.middleware.map(
        (row) => expected.find((e) => e.message === row.body.reason)!
      )
    );
    // And the statuses really are the six the server serves. This is the one place
    // this file states them, and it is an assertion ABOUT the corpus rather than an
    // input to the pairing above — a canary for the server moving a status under this
    // SDK. Compared as a SORTED MULTISET, not a sequence: 403 legitimately repeats,
    // and coupling this leg to row order would re-introduce exactly the positional
    // dependency the rest of this change removes.
    expect(
      errorCorpus.middleware.map((r) => r.http_status).sort((a, b) => a - b)
    ).toEqual([401, 403, 403, 404, 429, 500]);
  });

  it('the two 403s share a class and a status but NOT a code', () => {
    const envelopedForbidden = errorCorpus.enveloped.find(
      (body) => statusForToken(body.error.code) === 403
    );
    expect(envelopedForbidden).toBeDefined();
    const middlewareForbidden = middlewareRow("You don't have access").body;

    const measure403 = createErrorFromResponse(403, envelopedForbidden!);
    const role403 = createErrorFromResponse(403, middlewareForbidden);

    expect(measure403.constructor).toBe(ForbiddenError);
    expect(role403.constructor).toBe(ForbiddenError);
    expect(measure403.statusCode).toBe(role403.statusCode);
    // The whole point: a status-code-only decoder cannot tell these apart.
    expect(measure403.code).not.toBe(role403.code);
    expect(measure403.code).toBe(envelopedForbidden!.error.code);
    expect(role403.code).toBe('FORBIDDEN');
  });
});

describe('G6 · the 429 arm', () => {
  /**
   * The 429 row, selected by ITS OWN `http_status` rather than by index. The message
   * is NEVER typed here, and neither is the pairing: `429` is the status the corpus
   * row carries, derived by the generator from `RateLimitMiddleware`'s own source.
   */
  const rateLimitRow = (() => {
    const matches = errorCorpus.middleware.filter((row) => row.http_status === 429);
    expect(matches).toHaveLength(1);
    return matches[0];
  })();
  const rateLimitBody = rateLimitRow.body;

  it('a 429 is a RateLimitError carrying the body reason and RATE_LIMITED', () => {
    const error = createErrorFromResponse(rateLimitRow.http_status, rateLimitBody);

    expect(error.constructor).toBe(RateLimitError);
    expect(error.statusCode).toBe(429);
    expect(error.code).toBe('RATE_LIMITED');
    expect(error.message).toBe(rateLimitBody.reason);
    // The corpus's reason is genuinely not the class default — so the leg above is a
    // real body read and not a default leaking through.
    expect(rateLimitBody.reason).not.toBe('Rate limit exceeded');
    expect(new RateLimitError().message).toBe('Rate limit exceeded');
  });

  it('RateLimitError is not an instance of any other subclass', () => {
    const error = createErrorFromResponse(429, rateLimitBody);

    expect(error).toBeInstanceOf(FeedbackKitError);
    expect(error).not.toBeInstanceOf(ValidationError);
    expect(error).not.toBeInstanceOf(ForbiddenError);
    expect(error).not.toBeInstanceOf(PaymentRequiredError);
  });

  it('422 and 5xx are distinct classes, and 429 is neither', () => {
    const collapsed = [422, 500, 503].map((status) => {
      const error = createErrorFromResponse(status, { error: true, reason: `probe ${status}` });
      return { status, name: error.constructor.name, code: error.code };
    });

    expect(collapsed).toEqual([
      { status: 422, name: 'ValidationError', code: 'UNPROCESSABLE_ENTITY' },
      { status: 500, name: 'ServerError', code: 'SERVER_ERROR' },
      { status: 503, name: 'ServerError', code: 'SERVER_ERROR' }
    ]);
    // …but 429 is out of that set now.
    expect(createErrorFromResponse(429, rateLimitBody).constructor).not.toBe(
      FeedbackKitError
    );
  });

  it('a shape-B body with no code leaves every class default byte-for-byte intact', () => {
    // The regression guard for the `code` parameter added to every subclass: a body
    // that carries no code must produce exactly the shipped literals.
    const defaults = [400, 401, 402, 403, 404, 409, 429].map((status) => {
      const error = createErrorFromResponse(status, { error: true, reason: 'r' });
      return [status, error.code];
    });

    expect(defaults).toEqual([
      [400, 'BAD_REQUEST'],
      [401, 'UNAUTHORIZED'],
      [402, 'PAYMENT_REQUIRED'],
      [403, 'FORBIDDEN'],
      [404, 'NOT_FOUND'],
      [409, 'CONFLICT'],
      [429, 'RATE_LIMITED']
    ]);
  });
});

describe('G7 · the barrel exports exactly the module\'s error classes', () => {
  it('set equality between `errors.ts` classes and `index.ts` error exports', () => {
    const errorsSource = stripComments(readSrc('models/errors.ts'));
    const barrelSource = stripComments(readSrc('index.ts'));

    const declared = new Set(
      [...errorsSource.matchAll(/export\s+class\s+([A-Za-z0-9_]+)/g)].map((m) => m[1])
    );

    const block = barrelSource.match(
      /export\s*\{([^}]*)\}\s*from\s*'\.\/models\/errors'/
    );
    expect(block).not.toBeNull();
    const exported = new Set(
      block![1]
        .split(',')
        .map((name) => name.trim())
        .filter((name) => name.length > 0)
    );

    // Set equality, not presence: a tenth class nobody exported is exactly the defect
    // this catches, and `expect(exported).toContain('RateLimitError')` cannot see it.
    expect([...declared].sort()).toEqual([...exported].sort());
    // Non-vacuity: both sides really were read.
    expect(declared.size).toBeGreaterThanOrEqual(9);
    expect(exported.size).toBe(declared.size);
    expect(declared.has('RateLimitError')).toBe(true);
  });
});

describe('G8 · query encoding survives hostile values (regression guard)', () => {
  /**
   * JS's encoding is already correct — this guards it, it does not fix it.
   *
   * The split matters: pushed through a naive `` `?${key}=${value}` `` concatenation,
   * the first four values below still round-trip, so a test whose only hostile input
   * is a space, a `%`, an `=` or a `?` is GREEN against a builder that has been
   * replaced with string concatenation. Only the last four discriminate. The
   * non-discriminating rows are kept as the measured evidence that this gate's
   * falsifiability was checked rather than assumed.
   */
  const NON_DISCRIMINATING = ['a b', 'a%b', 'a=b', 'a?b'];
  const DISCRIMINATING = ['a&b', 'a#b', 'a+b', 'my event & more · ünïcode'];

  it('every hostile event_name round-trips through the built URL', async () => {
    const observed: Array<[string, string | null]> = [];
    for (const value of [...NON_DISCRIMINATING, ...DISCRIMINATING]) {
      const url = await urlThroughHttp({ event_name: value });
      // Non-vacuity: a URL was actually built and it carries a query string.
      expect(url.length).toBeGreaterThan(0);
      expect(url).toContain('?');
      observed.push([value, new URL(url).searchParams.get('event_name')]);
    }

    // One vector, asserted once — a per-iteration assert would stop at the first
    // failure and hide how many of the eight are really broken.
    expect(observed).toEqual(
      [...NON_DISCRIMINATING, ...DISCRIMINATING].map((v) => [v, v])
    );
    expect(observed).toHaveLength(8);
    expect(DISCRIMINATING).toHaveLength(4);
    expect(NON_DISCRIMINATING).toHaveLength(4);
  });
});

describe('G9 · the transforms keep exactly one external call site each', () => {
  it('`camelToSnake` runs on the request BODY only, never on query keys', () => {
    const lines = stripComments(readSrc('utils/http.ts')).split('\n');

    for (const name of ['camelToSnake', 'snakeToCamel']) {
      const hits = lines
        .map((line, index) => ({ line, number: index + 1 }))
        // Exclude the DECLARATION …
        .filter(({ line }) => !new RegExp(`^\\s*function\\s+${name}\\s*\\(`).test(line))
        // … and the RECURSIVE SELF-CALL, which survives the OPAQUE_KEYS ternary.
        .filter(({ line }) => !line.includes(`result[${name}Key(key)] =`))
        .filter(({ line }) => line.includes(`${name}(`));

      expect(
        hits.map((h) => h.line.trim()),
        `${name} external call sites`
      ).toHaveLength(1);
    }

    const stripped = stripComments(readSrc('utils/http.ts'));
    // Identity, not just count: the one encode site is the JSON request body, and the
    // one decode site is the parsed response.
    expect(stripped).toContain('JSON.stringify(camelToSnake(body))');
    expect(stripped).toContain('snakeToCamel(parsed)');
    expect(stripped).toContain('await response.json()');
    // And the query builder does NOT touch either transform.
    const queryBlock = stripped.slice(
      stripped.indexOf('new URLSearchParams()'),
      stripped.indexOf('const headers')
    );
    expect(queryBlock.length).toBeGreaterThan(0);
    expect(queryBlock).not.toContain('camelToSnake');
    expect(queryBlock).not.toContain('snakeToCamelKey');
  });
});

describe('G10 · the metrics surface is confined to its own module', () => {
  /**
   * RE-ANCHORED by METRICS03 phase `03`, deliberately and with the reason recorded.
   *
   * Phase `02` shipped this gate as "zero `metrics` identifiers across every src file",
   * which was the correct assertion for a phase whose whole job was the transport and
   * which was explicitly forbidden from adding the API. Phase `03` adds
   * `src/api/metrics.ts` and `client.metrics`, so the zero is no longer the truth and
   * widening the gate to a `toBeGreaterThanOrEqual` would retire it.
   *
   * It is re-anchored, not relaxed: the assertion is still a SET EQUALITY, now over the
   * set of files allowed to carry the identifier. A stray `metrics` in `http.ts`,
   * `feedback.ts` or anywhere else still reds, which is the containment this gate was
   * always really about.
   */
  it('the `metrics` identifier appears in exactly the expected src files', () => {
    const files = listSrcFiles();
    // Non-vacuity: a path typo makes "zero hits" and "zero files read" identical.
    expect(files.length).toBeGreaterThan(0);

    const hits = new Map<string, number>();
    for (const file of files) {
      const stripped = stripComments(readFileSync(file, 'utf8'));
      // Case-SENSITIVE and in identifier position: `METRICS03` in a spec reference is
      // not a metrics surface, and the doc comment that carries it is stripped above.
      const found = stripped.match(/\bmetrics\b/g);
      if (found) hits.set(relative(SRC_ROOT, file), found.length);
    }

    expect([...hits.keys()].sort()).toEqual([
      'api/metrics.ts', // the four operations and their paths
      'client.ts', // `public readonly metrics`
      'models/types.ts' // `MetricEventList.metrics`, the feed's second meta block
    ]);
    // A denominator: the census really counted occurrences, not just files.
    expect([...hits.values()].reduce((a, b) => a + b, 0)).toBeGreaterThan(0);
    // And `utils/http.ts` carries the word ONLY in a doc comment — the one file whose
    // pre-phase-02 state this gate was written against.
    expect(hits.has('utils/http.ts')).toBe(false);
    expect(readSrc('utils/http.ts')).toContain('metrics');
  });

  it('the comment stripper is what makes the leg above honest', () => {
    // The falsifiability pair, inline: identifier position reds, comment position does
    // not. A naive `grep -ric metrics src/` cannot tell these apart and would be red
    // on this phase's own `OPAQUE_KEYS` doc comment.
    expect(stripComments('export const metrics = {};').match(/\bmetrics\b/g)).toEqual([
      'metrics'
    ]);
    expect(stripComments('/** export const metrics = {}; */').match(/\bmetrics\b/g)).toBeNull();
    expect(stripComments('// export const metrics = {};').match(/\bmetrics\b/g)).toBeNull();
    // And a `https://` literal is not mistaken for a line comment.
    expect(stripComments("const u = 'https://x/metrics';")).toContain('https://x/metrics');
  });
});
