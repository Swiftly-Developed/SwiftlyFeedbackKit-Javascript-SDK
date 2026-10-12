import { describe, it, expect, vi, beforeEach } from 'vitest';
import {
  FeedbackKit,
  FeedbackCategory,
  FeedbackStatus,
  MetricDimension,
  MetricEventScope,
  MetricGranularity,
  MetricMeasure,
  SDKEvents,
  ValidationError,
  metricValue
} from '../src';
import type {
  MetricBreakdown,
  MetricEventList,
  MetricSeries,
  MetricSummary,
  MetricValues,
  MetricsMeta
} from '../src';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { listSrcFiles, loadCorpus, readSrc, stripComments } from './helpers/source-census';

/**
 * `QA-UNIT10-SDK-PARITY`, JS lane — the metrics API surface (`METRICS03` phase `03`,
 * `G1`–`G7`). Contract of record: `METRICS03` phase `01` §6, `C1`–`C8`.
 *
 * Same house rules as the two suites beside it:
 *
 * - **No wire fixture is hand-written.** Every response byte comes from the committed,
 *   server-generated `tests/fixtures/metrics-wire-corpus.json`.
 * - **Set equality and totals, never `contains`.** A presence oracle cannot see a fifth
 *   operation, a tenth `meta` field, a tenth measure or a seventh export.
 * - **Absence legs are comment-stripped, path-scoped to `src/`, and carry a
 *   denominator.** They never sweep `docs/`, whose prose deliberately names the wrong
 *   spellings in order to warn about them.
 *
 * 🔴 `G1` is the headline. `HttpClient` sends query keys VERBATIM — `camelToSnake` runs
 * on JSON bodies only. An SDK that sent `dateFrom` would get a `200` computed over the
 * server's default window: a wrong answer, right status, no error, no signal. These
 * assertions are the only oracle that exists for that defect.
 */

// ---------------------------------------------------------------------------
// Corpus
// ---------------------------------------------------------------------------

type Json = Record<string, unknown>;

interface MetricsCorpus {
  breakdown_event_name_with_overflow: {
    dimension: string;
    items: Array<{ key: string; is_overflow: boolean; values: Record<string, number> }>;
    meta: Json;
  };
  events_page: { items: Json[]; meta: Json; metrics: Json };
  summary_free_scoped_and_clamped: { meta: Json; values: Record<string, number> };
  summary_team_all_scope: { meta: Json; values: Record<string, number> };
  timeseries_daily: {
    meta: Json;
    series: Array<{ bucket: string; values: Record<string, number> }>;
  };
}

const corpus = loadCorpus<MetricsCorpus>('metrics-wire-corpus.json');
const corpusText = readFileSync(
  fileURLToPath(new URL('./fixtures/metrics-wire-corpus.json', import.meta.url)),
  'utf8'
);

// ---------------------------------------------------------------------------
// The seam: the real FeedbackKit client over a stubbed fetch
// ---------------------------------------------------------------------------

const BASE_URL = 'https://unit.invalid/api/v1';

const mockFetch = vi.fn();
global.fetch = mockFetch;

function makeClient(): FeedbackKit {
  return new FeedbackKit({ apiKey: 'sf_test_key', baseUrl: BASE_URL });
}

interface Captured<T> {
  url: URL;
  method: string;
  decoded: T;
}

/** Run one metrics call against a stubbed fetch; return the URL asked for and the
 *  decoded body — the real mapper and the real `snakeToCamel`, never a re-implementation. */
async function callThrough<T>(
  run: (client: FeedbackKit) => Promise<T>,
  payload: unknown = {}
): Promise<Captured<T>> {
  mockFetch.mockResolvedValueOnce({
    ok: true,
    status: 200,
    headers: { get: () => 'application/json' },
    json: async () => payload
  });
  const decoded = await run(makeClient());
  const call = mockFetch.mock.calls[mockFetch.mock.calls.length - 1];
  return {
    url: new URL(call[0] as string),
    method: (call[1] as { method: string }).method,
    decoded
  };
}

beforeEach(() => {
  mockFetch.mockReset();
});

// ---------------------------------------------------------------------------
// C1–C5, restated as data. Every count below is derived from these.
// ---------------------------------------------------------------------------

/** C2, the seven keys every operation accepts, in the order the mapper writes them. */
const BASE_WIRE_KEYS = [
  'measures',
  'status',
  'category',
  'event_name',
  'date_from',
  'date_to',
  'days'
] as const;

/**
 * C2's Operations column. 🔴 `granularity` is on BOTH `timeseries` and `breakdown` —
 * the server reads and echoes it on breakdown too (inert there, but read).
 */
const OPERATION_WIRE_KEYS: Record<string, readonly string[]> = {
  summary: BASE_WIRE_KEYS,
  timeseries: [...BASE_WIRE_KEYS, 'granularity'],
  breakdown: [...BASE_WIRE_KEYS, 'granularity', 'dimension'],
  events: [...BASE_WIRE_KEYS, 'page', 'per_page']
};

/** C1, key family only. No project parameter — the key identifies the project. */
const OPERATION_PATHS: Record<string, string> = {
  summary: '/api/v1/metrics/summary',
  timeseries: '/api/v1/metrics/timeseries',
  breakdown: '/api/v1/metrics/breakdown',
  events: '/api/v1/metrics/events'
};

/** Every option each operation's C2 row allows, all present at once. */
const FULL = {
  measures: [MetricMeasure.EventCount, MetricMeasure.UniqueEventUsers],
  status: [FeedbackStatus.Approved, FeedbackStatus.Completed],
  category: [FeedbackCategory.BugReport],
  eventName: 'checkout_completed',
  dateFrom: '2023-10-16T04:00:00Z',
  dateTo: '2023-11-14T05:00:00Z',
  days: 30
};

const FULL_CALLS: Record<string, (c: FeedbackKit) => Promise<unknown>> = {
  summary: (c) => c.metrics.summary(FULL),
  timeseries: (c) =>
    c.metrics.timeseries({ ...FULL, granularity: MetricGranularity.Week }),
  breakdown: (c) =>
    c.metrics.breakdown({
      ...FULL,
      granularity: MetricGranularity.Week,
      dimension: MetricDimension.EventName
    }),
  events: (c) => c.metrics.events({ ...FULL, page: 2, perPage: 100 })
};

/** C3's nine `meta` fields, camelCased by the decode. */
const META_KEYS_NINE = [
  'measures',
  'granularity',
  'timezone',
  'dateFrom',
  'dateTo',
  'truncated',
  'eventScope',
  'retentionClamped',
  'retentionWindowDays'
];
/** The eight `summary` and the event feed's `metrics` block carry — granularity absent. */
const META_KEYS_EIGHT = META_KEYS_NINE.filter((k) => k !== 'granularity');

// ---------------------------------------------------------------------------

describe('G1 · query keys are snake_case, per operation, as an ORDERED key list', () => {
  for (const [operation, expectedKeys] of Object.entries(OPERATION_WIRE_KEYS)) {
    it(`${operation} sends exactly ${expectedKeys.length} keys, in order, unmangled`, async () => {
      const { url } = await callThrough(FULL_CALLS[operation]);
      // Ordered array equality, not a presence check: a presence oracle cannot see an
      // extra key, and `toEqual` on the key list sees a rename, an omission and an
      // addition all at once.
      expect([...url.searchParams.keys()]).toEqual([...expectedKeys]);
    });
  }

  it('NOT ONE key in ANY of the four URLs is camelCase (with a denominator)', async () => {
    const observed: string[] = [];
    for (const operation of Object.keys(FULL_CALLS)) {
      const { url } = await callThrough(FULL_CALLS[operation]);
      observed.push(...url.searchParams.keys());
    }
    // 🔴 The denominator. "No camelCase keys" over an empty list is the vacuous green,
    // and it is exactly what a broken capture helper would produce.
    const expectedTotal = Object.values(OPERATION_WIRE_KEYS).reduce(
      (n, keys) => n + keys.length,
      0
    );
    expect(observed).toHaveLength(expectedTotal);
    expect(expectedTotal).toBeGreaterThan(0);
    expect(observed.filter((key) => /[A-Z]/.test(key))).toEqual([]);
  });

  it('measures, status and category are ONE comma-joined value each, not repeated keys', async () => {
    const { url } = await callThrough(FULL_CALLS.summary);
    expect(url.searchParams.getAll('measures')).toEqual([
      'event_count,unique_event_users'
    ]);
    expect(url.searchParams.getAll('status')).toEqual(['approved,completed']);
    expect(url.searchParams.getAll('category')).toEqual(['bug_report']);
    // event_name is a SINGLE value, never a list.
    expect(url.searchParams.getAll('event_name')).toEqual(['checkout_completed']);
  });

  it('an omitted option drops its key entirely rather than sending an empty value', async () => {
    const { url } = await callThrough((c) =>
      c.metrics.summary({ measures: [MetricMeasure.FeedbackCount] })
    );
    expect([...url.searchParams.keys()]).toEqual(['measures']);
  });

  it('the mapper is written property-by-property, with no rename loop', () => {
    const source = stripComments(readSrc('api/metrics.ts'));
    expect(source.length).toBeGreaterThan(0);
    // A mechanical camel→snake rename is the defect: it would silently accept a
    // mistyped option and put the mistake on the wire.
    expect(source).not.toContain('Object.entries');
    expect(source).not.toContain('camelToSnake');
    // Every wire key is spelled as a literal in the mapper.
    for (const key of [...BASE_WIRE_KEYS, 'granularity', 'dimension', 'page', 'per_page']) {
      expect(source).toContain(key);
    }
  });
});

describe('G2 · the four operations, by set equality, with paths pinned', () => {
  it('client.metrics exposes EXACTLY the four key-family operations', () => {
    const api = makeClient().metrics;
    const methods = Object.getOwnPropertyNames(Object.getPrototypeOf(api)).filter(
      (name) => name !== 'constructor'
    );
    // Set equality: a fifth operation — or a stray helper left on the prototype — reds.
    expect(methods.sort()).toEqual(['breakdown', 'events', 'summary', 'timeseries']);
    expect(methods).toHaveLength(Object.keys(OPERATION_PATHS).length);
  });

  for (const [operation, pathname] of Object.entries(OPERATION_PATHS)) {
    it(`${operation} GETs exactly ${pathname}`, async () => {
      const { url, method } = await callThrough(FULL_CALLS[operation]);
      expect(url.pathname).toBe(pathname);
      expect(method).toBe('GET');
    });
  }

  it('no projectId and no /projects/ anywhere in the metrics module', () => {
    const source = stripComments(readSrc('api/metrics.ts'));
    // Denominator: an unreadable file and a clean file are otherwise identical.
    expect(source.length).toBeGreaterThan(0);
    expect(source).not.toContain('projectId');
    expect(source).not.toContain('/projects/');
    // Paired positive: this really is the metrics module.
    expect(source).toContain('/metrics/summary');
  });
});

describe('G3 · `meta` is exactly C3’s nine fields, and `granularity` is ABSENT where it must be', () => {
  it('timeseries carries all nine', async () => {
    const { decoded } = await callThrough<MetricSeries>(
      (c) => c.metrics.timeseries({ measures: [MetricMeasure.EventCount] }),
      corpus.timeseries_daily
    );
    expect(Object.keys(decoded.meta).sort()).toEqual([...META_KEYS_NINE].sort());
    expect(decoded.meta.granularity).toBe(MetricGranularity.Day);
    // Non-vacuity: this row really is a timeseries.
    expect(decoded.series.length).toBeGreaterThan(0);
  });

  it('🔴 breakdown ALSO carries all nine, granularity `day` by default', async () => {
    const { decoded } = await callThrough<MetricBreakdown>(
      (c) =>
        c.metrics.breakdown({
          measures: [MetricMeasure.EventCount],
          dimension: MetricDimension.EventName
        }),
      corpus.breakdown_event_name_with_overflow
    );
    // Without this leg the split reads as 1-present / 3-absent when it is really 2/2,
    // and a model declaring breakdown's meta like summary's would stay green.
    expect(Object.keys(decoded.meta).sort()).toEqual([...META_KEYS_NINE].sort());
    expect(decoded.meta.granularity).toBe(MetricGranularity.Day);
    expect(decoded.dimension).toBe(MetricDimension.EventName);
  });

  it('summary carries eight, and `granularity` is ABSENT — not null', async () => {
    const { decoded } = await callThrough<MetricSummary>(
      (c) => c.metrics.summary({ measures: [MetricMeasure.FeedbackCount] }),
      corpus.summary_free_scoped_and_clamped
    );
    expect(Object.keys(decoded.meta).sort()).toEqual([...META_KEYS_EIGHT].sort());
    // 🔴 `in`, not `=== undefined`: an explicit `null` is also `undefined`-ish to a
    // careless check, and D1's distinction is exactly absent-vs-null.
    expect('granularity' in decoded.meta).toBe(false);
    // Non-vacuity: this really is a summary row, and the key set is non-empty.
    expect(Object.keys(decoded.meta).length).toBe(8);
    expect(decoded.values).toBeDefined();
    expect('series' in (decoded as unknown as Json)).toBe(false);
  });

  it('🔴 COMPILE-TIME: `MetricsMeta` accepts the eight-field summary shape', () => {
    // Runs under `tsc -p tsconfig.test.json`, not under vitest. The runtime legs above
    // read `decoded.meta`, which arrives through an unchecked `get<T>` cast — so they
    // cannot see a model that declared `granularity` REQUIRED. Nothing in this suite
    // constructs a `MetricsMeta`, and a type nobody constructs is a type nobody checks.
    // This literal is that construction: make `granularity` non-optional and it fails
    // TS2741 (property missing).
    const summaryMeta: MetricsMeta = {
      measures: ['event_count'],
      timezone: 'America/New_York',
      dateFrom: '2023-10-16T04:00:00Z',
      dateTo: '2023-11-14T05:00:00Z',
      truncated: false,
      eventScope: MetricEventScope.All,
      retentionClamped: false,
      retentionWindowDays: 30
    };
    // Non-vacuity, and the tie back to C3: the literal really carries exactly the eight
    // keys a summary carries, so the compile check above is checking the right shape.
    expect(Object.keys(summaryMeta).sort()).toEqual([...META_KEYS_EIGHT].sort());
  });

  it('the event feed’s `metrics` block also carries eight, granularity absent', async () => {
    const { decoded } = await callThrough<MetricEventList>(
      (c) => c.metrics.events({ measures: [MetricMeasure.EventCount] }),
      corpus.events_page
    );
    expect(Object.keys(decoded.metrics).sort()).toEqual([...META_KEYS_EIGHT].sort());
    expect('granularity' in decoded.metrics).toBe(false);
  });

  it('the Free-tier ladder arrives as typed PROPERTIES on a success, not an error', async () => {
    const { decoded } = await callThrough<MetricSummary>(
      (c) => c.metrics.summary({ measures: [MetricMeasure.EventCount] }),
      corpus.summary_free_scoped_and_clamped
    );
    expect(decoded.meta.eventScope).toBe(MetricEventScope.PredefinedOnly);
    expect(decoded.meta.retentionClamped).toBe(true);
    // Never hardcode 30, 90, or 365 — the allowance is a field, and the two corpus rows
    // disagree about it, which is what makes this leg discriminating.
    expect(decoded.meta.retentionWindowDays).toBe(
      (corpus.summary_free_scoped_and_clamped.meta as Json).retention_window_days
    );
    expect(decoded.meta.retentionWindowDays).not.toBe(
      (corpus.summary_team_all_scope.meta as Json).retention_window_days
    );
  });
});

describe('G4 · `values` is sparse, keyed snake_case, and the accessor is optional-returning', () => {
  it('every item’s `values` keys equal the WIRE keys exactly, per item', async () => {
    const { decoded } = await callThrough<MetricBreakdown>(
      (c) =>
        c.metrics.breakdown({
          measures: [MetricMeasure.EventCount],
          dimension: MetricDimension.EventName
        }),
      corpus.breakdown_event_name_with_overflow
    );
    const wireItems = corpus.breakdown_event_name_with_overflow.items;
    expect(decoded.items).toHaveLength(wireItems.length);
    expect(wireItems.length).toBeGreaterThan(0);
    decoded.items.forEach((item, i) => {
      expect(Object.keys(item.values).sort()).toEqual(
        Object.keys(wireItems[i].values).sort()
      );
    });
  });

  it('PAIRED SIBLING: the keys AROUND `values` are still camelCased', async () => {
    const { decoded } = await callThrough<MetricBreakdown>(
      (c) =>
        c.metrics.breakdown({
          measures: [MetricMeasure.EventCount],
          dimension: MetricDimension.EventName
        }),
      corpus.breakdown_event_name_with_overflow
    );
    // `is_overflow` → `isOverflow` proves the opacity is scoped to `values` and is not
    // a disabled transform.
    expect(Object.keys(decoded.items[0]).sort()).toEqual(['isOverflow', 'key', 'values']);
    expect(decoded.items[1].isOverflow).toBe(true);
  });

  it('🔴 the overflow item OMITS `unique_event_users` — an absent key is contract', async () => {
    const { decoded } = await callThrough<MetricBreakdown>(
      (c) =>
        c.metrics.breakdown({
          measures: [MetricMeasure.EventCount, MetricMeasure.UniqueEventUsers],
          dimension: MetricDimension.EventName
        }),
      corpus.breakdown_event_name_with_overflow
    );
    const overflow = decoded.items.find((item) => item.isOverflow);
    expect(overflow).toBeDefined();
    expect(MetricMeasure.UniqueEventUsers in overflow!.values).toBe(false);
    expect(Object.keys(overflow!.values)).toHaveLength(1);
    // Discriminating denominator: the NON-overflow sibling does carry it.
    const normal = decoded.items.find((item) => !item.isOverflow);
    expect(MetricMeasure.UniqueEventUsers in normal!.values).toBe(true);
  });

  it('metricValue returns undefined for an omitted measure, and `number | undefined` for a present one', async () => {
    const { decoded } = await callThrough<MetricBreakdown>(
      (c) =>
        c.metrics.breakdown({
          measures: [MetricMeasure.EventCount, MetricMeasure.UniqueEventUsers],
          dimension: MetricDimension.EventName
        }),
      corpus.breakdown_event_name_with_overflow
    );
    const overflow = decoded.items.find((item) => item.isOverflow)!;

    // Runtime half.
    expect(metricValue(overflow.values, MetricMeasure.UniqueEventUsers)).toBeUndefined();
    expect(metricValue(overflow.values, MetricMeasure.EventCount)).toBe(
      corpus.breakdown_event_name_with_overflow.items[1].values.event_count
    );

    // 🔴 COMPILE-TIME half. Runs under `tsc -p tsconfig.test.json`, not under vitest —
    // esbuild erases types. Without it this gate is green on a `Record<string, number>`
    // that lies: `noUncheckedIndexedAccess` is OFF in this repo, so under plain
    // `--strict` a `Record<string, number>` lookup types as `number` and the sparsity
    // is invisible to the compiler.
    const sparse: MetricValues = overflow.values;
    // @ts-expect-error — a RAW lookup into the sparse map is `number | undefined`.
    // 🔴 This is the leg that gates `MetricValues` itself. Measured: swapping the type
    // for `Record<string, number>` leaves the `metricValue(...)` leg below still red
    // (its RETURN type is annotated `number | undefined` independently), so that leg
    // alone is green on the type that lies. This one is not: with
    // `Record<string, number>` the lookup types as `number`, the directive goes unused,
    // and `tsc` fails with TS2578.
    const rawMustNotCompile: number = sparse[MetricMeasure.UniqueEventUsers];
    void rawMustNotCompile;
    // @ts-expect-error — and the accessor's signature says the same thing. If this ever
    // DOES compile, tsc reports an unused '@ts-expect-error' directive and the static
    // gate fails, which is the whole point.
    const mustNotCompile: number = metricValue(sparse, MetricMeasure.UniqueEventUsers);
    void mustNotCompile;
    // The positive twin, and the denominator for the directive above: the honest
    // annotation compiles clean.
    const honest: number | undefined = metricValue(sparse, MetricMeasure.EventCount);
    expect(honest).toBeGreaterThan(0);
  });
});

describe('G5 · the event feed’s TWO meta blocks, and `bucket_start` nowhere', () => {
  it('the feed has exactly `items`, `meta` and `metrics` — not a collapsed pair', async () => {
    const { decoded } = await callThrough<MetricEventList>(
      (c) => c.metrics.events({ measures: [MetricMeasure.EventCount] }),
      corpus.events_page
    );
    expect(Object.keys(decoded).sort()).toEqual(['items', 'meta', 'metrics']);
  });

  it('`meta` is the PAGINATION block, camelCased', async () => {
    const { decoded } = await callThrough<MetricEventList>(
      (c) => c.metrics.events({ measures: [MetricMeasure.EventCount] }),
      corpus.events_page
    );
    expect(Object.keys(decoded.meta).sort()).toEqual([
      'page',
      'perPage',
      'total',
      'totalPages'
    ]);
    expect(decoded.meta.perPage).toBe((corpus.events_page.meta as Json).per_page);
    expect(decoded.items.length).toBeGreaterThan(0);
  });

  it('an event row may omit `created_at` — the widened model decodes it', async () => {
    const { decoded } = await callThrough<MetricEventList>(
      (c) => c.metrics.events({ measures: [MetricMeasure.EventCount] }),
      corpus.events_page
    );
    // The corpus's second row genuinely has no timestamp; a required `createdAt` was a
    // promise the wire does not keep.
    expect(decoded.items[1].createdAt).toBeUndefined();
    expect(decoded.items[0].createdAt).toBeDefined();
    // `properties` keys survive verbatim, on the same OPAQUE_KEYS rule as `values`.
    expect(Object.keys(decoded.items[0].properties ?? {}).sort()).toEqual([
      'checkout_step',
      'utm_source'
    ]);
  });

  it('🔴 every series point is exactly `{ bucket, values }` — there is no bucket_start', async () => {
    const { decoded } = await callThrough<MetricSeries>(
      (c) => c.metrics.timeseries({ measures: [MetricMeasure.EventCount] }),
      corpus.timeseries_daily
    );
    expect(decoded.series.length).toBeGreaterThan(0);
    for (const point of decoded.series) {
      expect(Object.keys(point).sort()).toEqual(['bucket', 'values']);
    }
    // Asserted over the CORPUS, which has no comments and so cannot self-trip the way
    // a grep of `types.ts` would on the TSDoc that explains the absence.
    expect(corpusText.length).toBeGreaterThan(0);
    expect(corpusText).not.toContain('bucket_start');
    expect(corpusText).not.toContain('bucketStart');
    expect(corpusText).toContain('bucket');
  });

  it('empty buckets are PRESENT and zero-valued, not omitted', async () => {
    const { decoded } = await callThrough<MetricSeries>(
      (c) => c.metrics.timeseries({ measures: [MetricMeasure.EventCount] }),
      corpus.timeseries_daily
    );
    const zeroed = decoded.series.filter(
      (p) => metricValue(p.values, MetricMeasure.EventCount) === 0
    );
    // `series.length === 0` is a branch that never fires; the empty day is a row.
    expect(zeroed.length).toBeGreaterThan(0);
  });
});

describe('G6 · the closed vocabularies, by set equality against C1–C5', () => {
  const VOCABULARIES: Array<[string, Record<string, string>, string[]]> = [
    [
      'measures',
      MetricMeasure,
      [
        'feedback_count',
        'vote_count',
        'comment_count',
        'event_count',
        'unique_event_users',
        'sdk_user_count',
        'mrr_sum',
        'mrr_average',
        'users_with_mrr'
      ]
    ],
    ['granularities', MetricGranularity, ['hour', 'day', 'week', 'month']],
    ['dimensions', MetricDimension, ['status', 'category', 'event_name']],
    ['event scopes', MetricEventScope, ['all', 'predefined_only']],
    [
      'predefined event names',
      SDKEvents,
      ['feedback_list', 'feedback_detail', 'submit_feedback']
    ]
  ];

  for (const [name, vocabulary, expected] of VOCABULARIES) {
    it(`${name}: ${expected.length} members, set-equal to C5`, () => {
      const values = Object.values(vocabulary);
      expect(new Set(values)).toEqual(new Set(expected));
      // A Set drops duplicates; the length assertion is what sees a duplicated token.
      expect(values).toHaveLength(expected.length);
    });
  }

  it('operations count matches C1’s key family', () => {
    expect(Object.keys(OPERATION_PATHS)).toHaveLength(4);
    expect(Object.keys(OPERATION_WIRE_KEYS).sort()).toEqual(
      Object.keys(OPERATION_PATHS).sort()
    );
  });

  it('🔴 the Swift case name `hourly` appears nowhere in src/', () => {
    const files = listSrcFiles();
    expect(files.length).toBeGreaterThan(0);
    const hits = files.filter((file) =>
      /\bhourly\b/.test(stripComments(readFileSync(file, 'utf8')))
    );
    expect(hits).toEqual([]);
    // Denominator: the wire token IS there, so the census can see this vocabulary.
    expect(stripComments(readSrc('models/types.ts'))).toContain("'hour'");
  });

  it('there is EXACTLY ONE predefined-event-names object in src/', () => {
    const files = listSrcFiles();
    expect(files.length).toBeGreaterThan(0);
    const occurrences = files.flatMap((file) => {
      const stripped = stripComments(readFileSync(file, 'utf8'));
      return (stripped.match(/'feedback_list'/g) ?? []).map(() => file);
    });
    // A second constant set is the drift QA-UNIT10 exists to catch; `SDKEvents` already
    // ships C5's three names and this phase adds no twin.
    expect(occurrences).toHaveLength(1);
    expect(occurrences[0]).toContain('events.ts');
  });
});

describe('G7 · both export lists agree with the module, by set equality', () => {
  const barrel = stripComments(readSrc('index.ts'));
  const typesSource = readSrc('models/types.ts');

  /** Every name re-exported from `./models/types`, across every export form. */
  function barrelExportsFromTypes(): Set<string> {
    const names = new Set<string>();
    for (const match of barrel.matchAll(
      /export\s+(?:type\s+)?\{([^}]*)\}\s*from\s*'\.\/models\/types'/g
    )) {
      for (const raw of match[1].split(',')) {
        const name = raw.trim();
        if (name.length > 0) names.add(name);
      }
    }
    return names;
  }

  function declaredIn(source: string): Set<string> {
    return new Set(
      [
        ...source.matchAll(
          /export\s+(?:interface|type|const|function|enum)\s+([A-Za-z0-9_]+)/g
        )
      ].map((m) => m[1])
    );
  }

  it('the barrel re-exports EXACTLY what `models/types.ts` declares', () => {
    const declared = declaredIn(stripComments(typesSource));
    const exported = barrelExportsFromTypes();
    // Total set equality — a declared-but-unexported `MetricAnomaly` reds naming itself,
    // which a presence check for the expected names could not do.
    expect([...declared].sort()).toEqual([...exported].sort());
    expect(declared.size).toBeGreaterThan(0);
  });

  it('the metrics region of `types.ts` is entirely exported, and is non-empty', () => {
    // Region-scoped so the leg names the metrics surface specifically. The banner is a
    // comment, so the slice is taken BEFORE stripping.
    const bannerAt = typesSource.indexOf('// Metrics Types');
    expect(bannerAt).toBeGreaterThan(0);
    const metricsRegion = declaredIn(stripComments(typesSource.slice(bannerAt)));
    // 4 vocabularies + MetricValues + metricValue + 7 response interfaces
    // + PaginationMeta + 4 option interfaces = 18.
    expect(metricsRegion.size).toBe(18);
    const exported = barrelExportsFromTypes();
    expect([...metricsRegion].filter((name) => !exported.has(name))).toEqual([]);
  });

  it('the five RUNTIME values ride a value-export line, not the `export type` block', () => {
    const typeBlock = barrel.match(
      /export\s+type\s*\{([^}]*)\}\s*from\s*'\.\/models\/types'/
    );
    expect(typeBlock).not.toBeNull();
    const runtimeNames = [
      'MetricMeasure',
      'MetricGranularity',
      'MetricDimension',
      'MetricEventScope',
      'metricValue'
    ];
    for (const name of runtimeNames) {
      expect(typeBlock![1]).not.toContain(name);
    }
    // And they really are values at runtime, imported from the barrel at the top of
    // this file — `export type` would make each of these `undefined`.
    expect(MetricMeasure).toBeDefined();
    expect(MetricGranularity).toBeDefined();
    expect(MetricDimension).toBeDefined();
    expect(MetricEventScope).toBeDefined();
    expect(typeof metricValue).toBe('function');
  });

  it('`api/metrics.ts` carries the re-export footer `api/events.ts` established', () => {
    const metricsSource = stripComments(readSrc('api/metrics.ts'));
    const eventsSource = stripComments(readSrc('api/events.ts'));
    const footer = metricsSource.match(/export type \{([^}]*)\};\s*$/);
    expect(eventsSource).toMatch(/export type \{[^}]*\};\s*$/);
    expect(footer).not.toBeNull();
    const footerNames = footer![1]
      .split(',')
      .map((n) => n.trim())
      .filter((n) => n.length > 0);
    expect(footerNames.length).toBeGreaterThan(0);
    const exported = barrelExportsFromTypes();
    expect(footerNames.filter((name) => !exported.has(name))).toEqual([]);
  });

  it('`MetricsApi` is NOT exported from the barrel — the API classes never are', () => {
    // Matches every other API group: `FeedbackApi`, `EventsApi` and friends are reached
    // through `client.<group>`, not imported.
    expect(barrel).not.toContain('MetricsApi');
    expect(barrel).not.toContain('FeedbackApi');
    // Paired positive: the barrel really is the one that exports the client.
    expect(barrel).toContain('FeedbackKit');
  });
});

describe('G9 · the stale `types.ts` header is gone, and says what replaced it', () => {
  it('the generator claim is absent and the hand-maintained line is present', () => {
    const source = readSrc('models/types.ts');
    // Denominator: a bare absence check is green on a file that failed to read.
    expect(source.length).toBeGreaterThan(0);
    // Scoped to this ONE file, and an exact string: no generator is configured in this
    // package, and the claim misled every contributor editing these declarations.
    expect(source).not.toContain('Generated from OpenAPI specification');
    // Paired positive.
    expect(source).toContain('Hand-maintained');
  });
});

describe('the two client-side validations, and only two', () => {
  it('an empty `measures` throws before any request is made', async () => {
    const client = makeClient();
    await expect(client.metrics.summary({ measures: [] })).rejects.toBeInstanceOf(
      ValidationError
    );
    expect(mockFetch).not.toHaveBeenCalled();
  });

  it('an inverted date range throws before any request is made', async () => {
    const client = makeClient();
    await expect(
      client.metrics.summary({
        measures: [MetricMeasure.EventCount],
        dateFrom: '2023-11-14T05:00:00Z',
        dateTo: '2023-10-16T04:00:00Z'
      })
    ).rejects.toBeInstanceOf(ValidationError);
    expect(mockFetch).not.toHaveBeenCalled();
  });

  it('`days` together with `date_from` is NOT rejected client-side — the server owns it', async () => {
    const { url } = await callThrough((c) =>
      c.metrics.summary({
        measures: [MetricMeasure.EventCount],
        days: 7,
        dateFrom: '2023-10-16T04:00:00Z'
      })
    );
    // A typed 400 (`METRICS_CONFLICTING_WINDOW_PARAMS`) is the server's answer; a
    // client-side twin is a second allow-list that goes stale.
    expect(url.searchParams.get('days')).toBe('7');
    expect(url.searchParams.get('date_from')).toBe('2023-10-16T04:00:00Z');
  });

  it('`perPage` is clamped to 1…200 as a convenience, and the server stays the authority', async () => {
    const high = await callThrough((c) =>
      c.metrics.events({ measures: [MetricMeasure.EventCount], perPage: 5000 })
    );
    expect(high.url.searchParams.get('per_page')).toBe('200');
    const low = await callThrough((c) =>
      c.metrics.events({ measures: [MetricMeasure.EventCount], perPage: 0 })
    );
    expect(low.url.searchParams.get('per_page')).toBe('1');
    const untouched = await callThrough((c) =>
      c.metrics.events({ measures: [MetricMeasure.EventCount], perPage: 50 })
    );
    expect(untouched.url.searchParams.get('per_page')).toBe('50');
  });
});
