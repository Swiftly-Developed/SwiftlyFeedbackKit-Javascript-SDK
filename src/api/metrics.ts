/**
 * Metrics API
 *
 * The four key-family metrics operations. Contract of record: METRICS03 phase 01 §6.
 */

import { HttpClient } from '../utils/http';
import type { QueryParamValue } from '../utils/http';
import { ValidationError } from '../models/errors';
import type {
  MetricBreakdown,
  MetricBreakdownItem,
  MetricEventList,
  MetricSeries,
  MetricSeriesPoint,
  MetricSummary,
  MetricValues,
  MetricsBreakdownOptions,
  MetricsEventsOptions,
  MetricsMeta,
  MetricsQueryOptions,
  MetricsSeriesOptions,
  PaginationMeta
} from '../models/types';

/** The server's accepted range for `per_page`. */
const PER_PAGE_MIN = 1;
const PER_PAGE_MAX = 200;

/**
 * Map the options every operation shares onto their LITERAL wire keys.
 *
 * ⚠️⚠️ These keys go on the wire VERBATIM. `HttpClient` does not case-convert query
 * keys — it only converts JSON request bodies. A camelCase spelling here (`dateFrom`
 * instead of `date_from`) is not rejected by anything: the server simply does not find
 * the parameter, computes over its DEFAULT window, and returns 200. A wrong answer,
 * with the right status, and no signal anywhere.
 *
 * That is why this is written out one property at a time and not as a rename loop over
 * `Object.entries`. A mechanical mapper is precisely the thing that would silently
 * accept a mistyped option. See METRICS03 phase 01 §6 C2, and the ordered key-list
 * assertions in `tests/metrics-api.test.ts`.
 *
 * `undefined` values are dropped by `HttpClient` and never reach the URL.
 */
function baseQuery(o: MetricsQueryOptions): Record<string, QueryParamValue> {
  return {
    measures: o.measures.join(','),
    status: o.status && o.status.length > 0 ? o.status.join(',') : undefined,
    category: o.category && o.category.length > 0 ? o.category.join(',') : undefined,
    event_name: o.eventName,
    date_from: o.dateFrom,
    date_to: o.dateTo,
    days: o.days
  };
}

/**
 * The two mistakes worth catching before a round trip. Everything else — a conflicting
 * `days` + `date_from`, an out-of-range `per_page`, an unimplemented measure × endpoint
 * combination — is a typed 400 from the server, and duplicating those checks here would
 * build a second allow-list that goes stale the day the server's changes.
 */
function validate(o: MetricsQueryOptions): void {
  if (o.measures.length === 0) {
    throw new ValidationError('measures must contain at least one measure');
  }
  if (o.dateFrom !== undefined && o.dateTo !== undefined && o.dateFrom > o.dateTo) {
    throw new ValidationError('dateFrom must not be later than dateTo');
  }
}

/** Fail-fast convenience only — the server returns a 400 rather than clamping. */
function clampPerPage(perPage: number | undefined): number | undefined {
  if (perPage === undefined) return undefined;
  return Math.min(PER_PAGE_MAX, Math.max(PER_PAGE_MIN, Math.trunc(perPage)));
}

/**
 * API for reading project metrics.
 *
 * All four operations are rate limited to 60 requests per 60 seconds, shared across the
 * family. The SDK does not retry or back off — hiding the cap behind a retry loop makes
 * it invisible.
 *
 * A Free-tier project gets a **success**, not an error: the response is narrowed and
 * says so, via `meta.eventScope` and `meta.retentionClamped`. The single 402
 * (`METRICS_CUSTOM_EVENTS_REQUIRE_PRO`) is reserved for the three requests that have no
 * honest narrower answer.
 */
export class MetricsApi {
  constructor(private http: HttpClient) {}

  /**
   * Aggregate totals over the window — one number per requested measure.
   *
   * @param options - Measures, filters, and window
   * @returns `meta` plus a sparse `values` map keyed by the server's measure tokens
   * @throws ValidationError if `measures` is empty or the date range is inverted
   * @throws PaymentRequiredError (402) `METRICS_CUSTOM_EVENTS_REQUIRE_PRO`
   * @throws ForbiddenError (403) `METRICS_MEASURE_REQUIRES_BEARER` for a Bearer-only measure
   * @throws RateLimitError (429) past 60 requests / 60s
   *
   * @example
   * ```ts
   * const summary = await feedbackKit.metrics.summary({
   *   measures: [MetricMeasure.FeedbackCount, MetricMeasure.EventCount],
   *   days: 7
   * });
   * console.log(metricValue(summary.values, MetricMeasure.FeedbackCount));
   * ```
   *
   * Note `summary.meta.granularity` is ABSENT on this operation — omitted, not null.
   */
  async summary(options: MetricsQueryOptions): Promise<MetricSummary> {
    validate(options);
    return this.http.get<MetricSummary>('/metrics/summary', baseQuery(options));
  }

  /**
   * Bucketed totals over the window.
   *
   * Empty buckets are PRESENT and zero-valued, so `series.length === 0` is a branch that
   * never fires for a valid window.
   *
   * @param options - Measures, filters, window, and bucket width
   * @returns `meta` (with `granularity` populated) plus the ordered bucket list
   * @throws ValidationError if `measures` is empty or the date range is inverted
   *
   * @example
   * ```ts
   * const series = await feedbackKit.metrics.timeseries({
   *   measures: [MetricMeasure.EventCount],
   *   granularity: MetricGranularity.Day,
   *   days: 7
   * });
   * for (const point of series.series) {
   *   console.log(point.bucket, metricValue(point.values, MetricMeasure.EventCount));
   * }
   * ```
   */
  async timeseries(options: MetricsSeriesOptions): Promise<MetricSeries> {
    validate(options);
    return this.http.get<MetricSeries>('/metrics/timeseries', {
      ...baseQuery(options),
      granularity: options.granularity
    });
  }

  /**
   * Totals grouped by a dimension, ordered by the first requested measure descending.
   *
   * Past the server's cardinality ceiling the tail collapses into a single item with
   * `isOverflow: true`, `meta.truncated` goes true, and that item's `values` OMITS
   * `unique_event_users`. Use `metricValue()`; do not assert non-null.
   *
   * `granularity` is accepted because the server reads it here, but it is inert: it is
   * echoed into `meta.granularity` (`'day'` by default) and buckets nothing.
   *
   * @param options - Measures, filters, window, and the required dimension
   * @throws ValidationError if `measures` is empty or the date range is inverted
   *
   * @example
   * ```ts
   * const byEvent = await feedbackKit.metrics.breakdown({
   *   measures: [MetricMeasure.EventCount, MetricMeasure.UniqueEventUsers],
   *   dimension: MetricDimension.EventName,
   *   days: 30
   * });
   * ```
   */
  async breakdown(options: MetricsBreakdownOptions): Promise<MetricBreakdown> {
    validate(options);
    return this.http.get<MetricBreakdown>('/metrics/breakdown', {
      ...baseQuery(options),
      granularity: options.granularity,
      dimension: options.dimension
    });
  }

  /**
   * The raw event feed, paginated.
   *
   * The response carries TWO meta blocks: `meta` is pagination, `metrics` is the window
   * and scope block every other operation puts under `meta`.
   *
   * @param options - Measures, filters, window, and pagination
   * @throws ValidationError if `measures` is empty or the date range is inverted
   * @throws PaymentRequiredError (402) `METRICS_CUSTOM_EVENTS_REQUIRE_PRO` — the raw
   *   feed is one of the three exclusively-custom requests
   *
   * @example
   * ```ts
   * let page = 1;
   * for (;;) {
   *   const feed = await feedbackKit.metrics.events({
   *     measures: [MetricMeasure.EventCount],
   *     days: 7,
   *     page,
   *     perPage: 100
   *   });
   *   if (page >= feed.meta.totalPages) break;
   *   page += 1;
   * }
   * ```
   */
  async events(options: MetricsEventsOptions): Promise<MetricEventList> {
    validate(options);
    return this.http.get<MetricEventList>('/metrics/events', {
      ...baseQuery(options),
      page: options.page,
      per_page: clampPerPage(options.perPage)
    });
  }
}

// Re-export types for convenience
export type {
  MetricBreakdown,
  MetricBreakdownItem,
  MetricEventList,
  MetricSeries,
  MetricSeriesPoint,
  MetricSummary,
  MetricValues,
  MetricsBreakdownOptions,
  MetricsEventsOptions,
  MetricsMeta,
  MetricsQueryOptions,
  MetricsSeriesOptions,
  PaginationMeta
};
