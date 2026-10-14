/**
 * FeedbackKit TypeScript Types
 *
 * Hand-maintained. There is no code generator configured in this package — edit these
 * declarations directly, and keep them faithful to the contract of record
 * (`docs/specs/METRICS03-PHASE-01-METRICS-CLIENT-CONTRACT-AND-SHARED-WIRE-CORPUS.md` §6
 * for the metrics surface) and to the committed wire corpora under `tests/fixtures/`.
 */

// ============================================================================
// Enums
// ============================================================================

/**
 * Status of a feedback item
 */
export enum FeedbackStatus {
  Pending = 'pending',
  Approved = 'approved',
  InProgress = 'in_progress',
  TestFlight = 'testflight',
  Completed = 'completed',
  Rejected = 'rejected'
}

/**
 * Category of a feedback item
 */
export enum FeedbackCategory {
  FeatureRequest = 'feature_request',
  BugReport = 'bug_report',
  Improvement = 'improvement',
  Other = 'other'
}

// ============================================================================
// Feedback Types
// ============================================================================

/**
 * A feedback item
 */
export interface Feedback {
  /** Unique identifier */
  id: string;
  /** Feedback title */
  title: string;
  /** Detailed description */
  description: string;
  /** Current status */
  status: FeedbackStatus;
  /** Feedback category */
  category: FeedbackCategory;
  /** ID of the user who submitted */
  userId: string;
  /** Email of the submitter (if provided) */
  userEmail?: string | null;
  /** Total number of votes */
  voteCount: number;
  /** Whether the current user has voted */
  hasVoted: boolean;
  /** Total number of comments */
  commentCount: number;
  /** Combined MRR of all voters */
  totalMrr?: number | null;
  /** When the feedback was created */
  createdAt: string;
  /** When the feedback was last updated */
  updatedAt: string;
  /** Explanation for rejection (only for rejected status) */
  rejectionReason?: string | null;
  /** ID of the feedback this was merged into */
  mergedIntoId?: string | null;
  /** When this feedback was merged */
  mergedAt?: string | null;
  /** IDs of feedback items merged into this one */
  mergedFeedbackIds?: string[] | null;
  /** Whether this feedback is hidden over the free-tier limit (only visible to creator) */
  isHiddenOverLimit?: boolean;
}

/**
 * Request to create a new feedback item
 */
export interface CreateFeedbackRequest {
  /** Brief title (1-200 chars) */
  title: string;
  /** Detailed description (1-5000 chars) */
  description: string;
  /** Feedback category */
  category: FeedbackCategory;
  /**
   * Unique identifier of the submitting user.
   * When omitted, the client sends its session id (a generated `local_<uuid>`
   * when the host has not set one).
   */
  userId?: string;
  /** Optional email for status update notifications */
  userEmail?: string;
  /** Whether the user consents to join the project's mailing list */
  subscribeToMailingList?: boolean;
  /** Email preference types (e.g. ["operational", "marketing"]). Defaults to both when omitted. */
  mailingListEmailTypes?: string[];
}

/**
 * Sort order for feedback list
 */
export enum FeedbackSort {
  /** Most votes first (default) */
  Votes = 'votes',
  /** Most recently created first */
  Newest = 'newest',
  /** Oldest first */
  Oldest = 'oldest',
  /** Most comments first */
  Comments = 'comments'
}

/**
 * Options for listing feedback
 */
export interface ListFeedbackOptions {
  /** Filter by status */
  status?: FeedbackStatus;
  /** Filter by category */
  category?: FeedbackCategory;
  /** Include merged feedback items */
  includeMerged?: boolean;
  /** Sort order (defaults to votes descending) */
  sort?: FeedbackSort;
  /** 1-indexed page. Omit to read every page. */
  page?: number;
  /** Page size. The server clamps this to 1–100. */
  perPage?: number;
}

// ============================================================================
// Vote Types
// ============================================================================

/**
 * Request to vote for a feedback item
 */
export interface VoteRequest {
  /**
   * Unique identifier of the voting user.
   * When omitted, the client sends its session id.
   */
  userId?: string;
  /** Email for status change notifications */
  email?: string;
  /** Opt-in to receive email notifications when status changes */
  notifyStatusChange?: boolean;
  /** Whether the user consents to join the project's mailing list */
  subscribeToMailingList?: boolean;
  /** Email preference types (e.g. ["operational", "marketing"]). Defaults to both when omitted. */
  mailingListEmailTypes?: string[];
}

/**
 * Request to remove a vote
 */
export interface UnvoteRequest {
  /**
   * Unique identifier of the user removing their vote.
   * When omitted, the client sends its session id.
   */
  userId?: string;
}

/**
 * Response after voting/unvoting
 */
export interface VoteResponse {
  /** ID of the feedback item */
  feedbackId: string;
  /** Updated vote count */
  voteCount: number;
  /** Whether the user has voted after this action */
  hasVoted: boolean;
}

// ============================================================================
// Comment Types
// ============================================================================

/**
 * A comment on a feedback item
 */
export interface Comment {
  /** Unique identifier */
  id: string;
  /** Comment text */
  content: string;
  /** ID of the commenting user */
  userId: string;
  /** Whether this is an admin comment */
  isAdmin: boolean;
  /** When the comment was created */
  createdAt: string;
}

/**
 * Request to create a comment
 */
export interface CreateCommentRequest {
  /** Comment text (1-2000 chars) */
  content: string;
  /**
   * Unique identifier of the commenting user.
   * When omitted, the client sends its session id.
   */
  userId?: string;
  /** Whether this comment is from an admin/developer */
  isAdmin?: boolean;
}

// ============================================================================
// User Types
// ============================================================================

/**
 * An SDK user
 */
export interface SDKUser {
  /** Internal unique identifier */
  id: string;
  /** SDK user identifier */
  userId: string;
  /** Monthly Recurring Revenue */
  mrr?: number | null;
  /** When the user was first registered */
  firstSeenAt: string;
  /** When the user was last seen */
  lastSeenAt: string;
}

/**
 * Request to register/update an SDK user
 */
export interface RegisterUserRequest {
  /** Unique identifier of the SDK user */
  userId: string;
  /** Monthly Recurring Revenue (optional) */
  mrr?: number;
}

// ============================================================================
// Event Types
// ============================================================================

/**
 * A tracked event
 */
export interface TrackedEvent {
  /** Unique identifier */
  id: string;
  /** Name of the tracked event */
  eventName: string;
  /** User who triggered the event */
  userId: string;
  /** Event properties */
  properties?: Record<string, unknown> | null;
  /**
   * When the event was tracked.
   *
   * OPTIONAL on the wire: `ViewEventResponseDTO` declares it optional and the raw event
   * feed really does omit it on rows that carry no timestamp (see the second item of
   * `events_page` in `tests/fixtures/metrics-wire-corpus.json`). Declaring it required
   * told every caller a value would always be there.
   */
  createdAt?: string;
}

/**
 * Request to track an event
 */
export interface TrackEventRequest {
  /** Name of the event to track */
  eventName: string;
  /** Unique identifier of the user */
  userId: string;
  /** Optional key-value properties for the event */
  properties?: Record<string, unknown>;
}

// ============================================================================
// Configuration Types
// ============================================================================

/**
 * FeedbackKit client configuration
 */
export interface FeedbackKitConfig {
  /** Project API key (starts with sf_) */
  apiKey: string;
  /** Base URL of the FeedbackKit API */
  baseUrl?: string;
  /** Current user ID (for hasVoted state in responses) */
  userId?: string;
  /**
   * Server-side credential for admin replies.
   *
   * An end-user app must leave this unset. `comments.create` with `isAdmin: true`
   * sends it as `Authorization: Bearer` and refuses to mark a reply as admin
   * when only the project API key is configured.
   */
  bearerToken?: string;
  /** Request timeout in milliseconds */
  timeout?: number;
}

/**
 * Default configuration values
 */
export const DEFAULT_CONFIG = {
  baseUrl: 'https://api.prod.getfeedbackkit.com/api/v1',
  timeout: 30000
} as const;

// ============================================================================
// Metrics Types
// ============================================================================
// Contract of record: METRICS03 phase 01 §6, C1–C8. Every declaration below this
// banner is part of the metrics surface, and the export-list gate in
// `tests/metrics-api.test.ts` censuses exactly this region.

/**
 * A measure token. These are the values the API reads and writes; they are NOT
 * camelCased anywhere — not in the `measures` query parameter, and not as keys inside
 * a `values` map (see {@link MetricValues}).
 *
 * Five are readable with an `X-API-Key`, which is the only credential this SDK sends:
 * `feedback_count`, `vote_count`, `comment_count`, `event_count`, `unique_event_users`.
 * The other four are Bearer-only and requesting one here is a **403** carrying
 * `METRICS_MEASURE_REQUIRES_BEARER`. They ship in this vocabulary anyway, because the
 * vocabulary documents the server's measure set and the server owns the boundary.
 */
export const MetricMeasure = {
  /** Feedback items created in the window. */
  FeedbackCount: 'feedback_count',
  /** Votes cast in the window. */
  VoteCount: 'vote_count',
  /** Comments posted in the window. */
  CommentCount: 'comment_count',
  /** View events recorded in the window. */
  EventCount: 'event_count',
  /** Distinct users who produced a view event. NOT additive — see {@link MetricValues}. */
  UniqueEventUsers: 'unique_event_users',
  /** Bearer-only. On this SDK's key surface: 403 `METRICS_MEASURE_REQUIRES_BEARER`. */
  SdkUserCount: 'sdk_user_count',
  /** Bearer-only. On this SDK's key surface: 403 `METRICS_MEASURE_REQUIRES_BEARER`. */
  MrrSum: 'mrr_sum',
  /** Bearer-only. On this SDK's key surface: 403 `METRICS_MEASURE_REQUIRES_BEARER`. */
  MrrAverage: 'mrr_average',
  /** Bearer-only. On this SDK's key surface: 403 `METRICS_MEASURE_REQUIRES_BEARER`. */
  UsersWithMrr: 'users_with_mrr'
} as const;
export type MetricMeasure = (typeof MetricMeasure)[keyof typeof MetricMeasure];

/**
 * A bucket width. These are the WIRE tokens. The server's own Swift case names
 * (`hourly`, `daily`, …) are not the wire spelling and must never be sent.
 */
export const MetricGranularity = {
  Hour: 'hour',
  Day: 'day',
  Week: 'week',
  Month: 'month'
} as const;
export type MetricGranularity = (typeof MetricGranularity)[keyof typeof MetricGranularity];

/** A breakdown dimension. */
export const MetricDimension = {
  Status: 'status',
  Category: 'category',
  EventName: 'event_name'
} as const;
export type MetricDimension = (typeof MetricDimension)[keyof typeof MetricDimension];

/**
 * Which events the response counted.
 *
 * `predefined_only` is what a Free-tier project gets: a **success**, not an error. The
 * customer's own event names are still ingested and retained; they simply are not read
 * back until the plan allows it, and they become readable on upgrade with no
 * re-tracking. Read this off {@link MetricsMeta.eventScope} rather than inferring it
 * from the plan.
 */
export const MetricEventScope = {
  All: 'all',
  PredefinedOnly: 'predefined_only'
} as const;
export type MetricEventScope = (typeof MetricEventScope)[keyof typeof MetricEventScope];

/**
 * Measure token → value.
 *
 * Two things about this map surprise every first integrator, and both are contract:
 *
 * 1. **The keys are the server's snake_case tokens.** `values.event_count`, never
 *    `values.eventCount`. The SDK camelCases every other response key; this map and an
 *    event's `properties` are exempt, because their keys are data rather than field
 *    names.
 * 2. **The map is SPARSE.** A breakdown's overflow item omits `unique_event_users`
 *    entirely — a distinct-user count is not additive across the names the cardinality
 *    ceiling elided, so no honest number exists. That is why the index signature is
 *    `number | undefined` and why {@link metricValue} returns an optional. A non-null
 *    assertion here is reachable in production, not theoretical.
 */
export type MetricValues = { readonly [measure: string]: number | undefined };

/**
 * The value recorded for `measure`, or `undefined` when the server omitted it.
 *
 * A free function rather than a method: the same sparse map hangs off
 * {@link MetricSummary}, {@link MetricSeriesPoint} and {@link MetricBreakdownItem}.
 *
 * @example
 * ```ts
 * const users = metricValue(item.values, MetricMeasure.UniqueEventUsers);
 * // `number | undefined` — an overflow item legitimately has no value here.
 * ```
 */
export function metricValue(
  values: MetricValues,
  measure: MetricMeasure
): number | undefined {
  return values[measure];
}

/**
 * The `meta` block every metrics response carries. Exactly nine fields, of which one is
 * optional.
 */
export interface MetricsMeta {
  /** The resolved measure list, in first-seen order. */
  measures: string[];
  /**
   * The resolved bucket width.
   *
   * ABSENT — omitted from the JSON, never `null` — on `summary` and on the event feed's
   * `metrics` block. PRESENT on `timeseries` **and** on `breakdown`, defaulting to
   * `'day'`. Its presence therefore does not mean "this is a timeseries", and a caller
   * that branches on `=== null` never fires.
   */
  granularity?: MetricGranularity;
  /** The reporting zone actually applied. */
  timezone: string;
  /** ISO-8601 INSTANT — not `yyyy-MM-dd`. The INCLUSIVE first day of the window. */
  dateFrom: string;
  /** ISO-8601 instant. The INCLUSIVE last day — never an exclusive end. */
  dateTo: string;
  /** True only when a breakdown's cardinality ceiling elided names. */
  truncated: boolean;
  /** Which events were counted. See {@link MetricEventScope}. */
  eventScope: MetricEventScope;
  /**
   * True when the plan narrowed the requested window.
   *
   * NOT idempotent: re-requesting an already-clamped window returns the same window with
   * this flag `false`, because the second request genuinely asks for something inside
   * the allowance. Never derive it by comparing what you asked for against what arrived.
   */
  retentionClamped: boolean;
  /** The plan's window allowance, in days (Free 30, Pro 90, Team 365). Never hardcode those — read this. */
  retentionWindowDays: number;
}

/** Pagination block on the raw event feed. */
export interface PaginationMeta {
  /** Total matching rows across all pages. */
  total: number;
  /** The 1-based page returned. */
  page: number;
  /** Rows per page. */
  perPage: number;
  /** Total number of pages. */
  totalPages: number;
}

/** `GET /metrics/summary` — one aggregate per requested measure. */
export interface MetricSummary {
  meta: MetricsMeta;
  values: MetricValues;
}

/**
 * One bucket of a timeseries.
 *
 * The bucket is identified by its `bucket` key, whose format follows the resolved
 * granularity. There is no separate start-instant field: the key IS the identifier.
 */
export interface MetricSeriesPoint {
  /** The bucket identifier, formatted for the resolved granularity. */
  bucket: string;
  /** Sparse measure map — see {@link MetricValues}. */
  values: MetricValues;
}

/**
 * `GET /metrics/timeseries`.
 *
 * Empty buckets are PRESENT and zero-valued, not omitted, so `series.length === 0` is a
 * branch that never fires for a valid window.
 */
export interface MetricSeries {
  meta: MetricsMeta;
  series: MetricSeriesPoint[];
}

/** One row of a breakdown. */
export interface MetricBreakdownItem {
  /** The dimension value — a status, a category, or an event name. */
  key: string;
  /**
   * Sparse measure map. THIS is where the sparsity bites: when `isOverflow` is true the
   * map omits `unique_event_users`. See {@link MetricValues}.
   */
  values: MetricValues;
  /** True on the single synthetic row aggregating the names the ceiling elided. */
  isOverflow: boolean;
}

/**
 * `GET /metrics/breakdown`.
 *
 * `items` arrives ordered by the first requested measure, descending. Do not re-sort
 * unless you mean to. `meta.granularity` is populated here (`'day'` by default) even
 * though it does not bucket anything on this surface.
 */
export interface MetricBreakdown {
  meta: MetricsMeta;
  dimension: MetricDimension;
  items: MetricBreakdownItem[];
}

/**
 * `GET /metrics/events` — the raw event feed.
 *
 * TWO meta blocks, and they are not interchangeable: `meta` is the pagination block and
 * `metrics` is the {@link MetricsMeta} every other operation puts under `meta`.
 */
export interface MetricEventList {
  items: TrackedEvent[];
  /** Pagination. */
  meta: PaginationMeta;
  /** The metrics window/scope block — NOT under `meta` on this operation. */
  metrics: MetricsMeta;
}

/**
 * Options common to every metrics operation.
 *
 * These property names are idiomatic camelCase; the SDK maps each one BY HAND to its
 * literal snake_case wire key at the call site. See `src/api/metrics.ts`.
 */
export interface MetricsQueryOptions {
  /** Required, at least one. An empty list throws `ValidationError` before the request. */
  measures: MetricMeasure[];
  /** Restrict feedback-derived measures to these statuses. */
  status?: FeedbackStatus[];
  /** Restrict feedback-derived measures to these categories. */
  category?: FeedbackCategory[];
  /**
   * A SINGLE event name — the wire takes one value, not a list. Free-form: any custom
   * name you track is valid here, and `SDKEvents` carries the three predefined ones.
   * Capped at 200 characters by the server.
   */
  eventName?: string;
  /**
   * ISO-8601 instant, inclusive. Mutually exclusive with {@link days} — sending both is
   * a 400 (`METRICS_CONFLICTING_WINDOW_PARAMS`) from the server, which owns that check.
   */
  dateFrom?: string;
  /** ISO-8601 instant, inclusive. */
  dateTo?: string;
  /** A trailing window in days. Mutually exclusive with {@link dateFrom}/{@link dateTo}. */
  days?: number;
}

/** Options for `metrics.timeseries`. */
export interface MetricsSeriesOptions extends MetricsQueryOptions {
  /** Bucket width. Defaults to `'day'` server-side. */
  granularity?: MetricGranularity;
}

/** Options for `metrics.breakdown`. */
export interface MetricsBreakdownOptions extends MetricsQueryOptions {
  /** Required. Which dimension to group by. */
  dimension: MetricDimension;
  /**
   * Accepted and sent, because the server reads it on this operation too — but it is
   * INERT here: it is echoed into `meta.granularity` and buckets nothing. An
   * unparseable value is still a 400.
   */
  granularity?: MetricGranularity;
}

/** Options for `metrics.events`. */
export interface MetricsEventsOptions extends MetricsQueryOptions {
  /** 1-based page number. */
  page?: number;
  /**
   * Rows per page, server default 50. Clamped client-side to 1…200 as a fail-fast
   * convenience; the server is the authority and returns a 400 rather than clamping.
   */
  perPage?: number;
}
