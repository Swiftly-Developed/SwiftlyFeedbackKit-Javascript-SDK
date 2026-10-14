/**
 * FeedbackKit Client
 *
 * Main entry point for the FeedbackKit JavaScript SDK.
 */

import { HttpClient } from './utils/http';
import { FeedbackApi } from './api/feedback';
import { VotesApi } from './api/votes';
import { CommentsApi } from './api/comments';
import { UsersApi } from './api/users';
import { EventsApi } from './api/events';
import { MetricsApi } from './api/metrics';
import { FeedbackKitConfig, DEFAULT_CONFIG } from './models/types';
import { ValidationError } from './models/errors';
import {
  createUserIdStore,
  generateLocalUserId,
  initialUserId,
  type UserIdStore
} from './identity/anonymousUserId';

/**
 * FeedbackKit SDK Client
 *
 * @example
 * ```ts
 * import { FeedbackKit, FeedbackCategory, MetricGranularity, MetricMeasure } from 'feedbackkit-js';
 *
 * // Initialize the client
 * const feedbackKit = new FeedbackKit({
 *   apiKey: 'sf_your_api_key',
 *   userId: 'user_12345' // optional
 * });
 *
 * // List feedback
 * const feedbacks = await feedbackKit.feedback.list();
 *
 * // Submit feedback
 * const newFeedback = await feedbackKit.feedback.create({
 *   title: 'Add dark mode',
 *   description: 'Please add dark mode support.',
 *   category: FeedbackCategory.FeatureRequest,
 *   userId: 'user_12345'
 * });
 *
 * // Vote for feedback
 * const voteResult = await feedbackKit.votes.vote('feedback-id', {
 *   userId: 'user_12345'
 * });
 *
 * // Add a comment
 * const comment = await feedbackKit.comments.create('feedback-id', {
 *   content: 'Great idea!',
 *   userId: 'user_12345'
 * });
 *
 * // Register user with MRR
 * await feedbackKit.users.register({
 *   userId: 'user_12345',
 *   mrr: 9.99
 * });
 *
 * // Track an event
 * await feedbackKit.events.track({
 *   eventName: 'feedback_list',
 *   userId: 'user_12345'
 * });
 *
 * // Fetch a 7-day series
 * const series = await feedbackKit.metrics.timeseries({
 *   measures: [MetricMeasure.EventCount],
 *   granularity: MetricGranularity.Day,
 *   days: 7
 * });
 * ```
 */
export class FeedbackKit {
  private http: HttpClient;
  private config: Required<Omit<FeedbackKitConfig, 'bearerToken'>>;
  private sessionUserId: string | undefined;
  private readonly userIdStore: UserIdStore;

  /** Feedback management API */
  public readonly feedback: FeedbackApi;

  /** Voting API */
  public readonly votes: VotesApi;

  /** Comments API */
  public readonly comments: CommentsApi;

  /** User registration API */
  public readonly users: UsersApi;

  /** Event tracking API */
  public readonly events: EventsApi;

  /** Metrics and analytics API */
  public readonly metrics: MetricsApi;

  /**
   * Create a new FeedbackKit client
   *
   * @param config - Client configuration
   * @param config.apiKey - Your project API key (required)
   * @param config.baseUrl - API base URL (optional, defaults to production)
   * @param config.userId - Current user ID for hasVoted state (optional).
   *   When omitted, a `local_<uuid>` is generated and reused. An explicit id
   *   replaces that generated id.
   * @param config.bearerToken - Server-side credential for admin replies (optional).
   *   Leave unset in an end-user app. Required before `comments.create` can set `isAdmin`.
   * @param config.timeout - Request timeout in ms (optional, defaults to 30000)
   *
   * @example
   * ```ts
   * // Minimal configuration
   * const feedbackKit = new FeedbackKit({
   *   apiKey: 'sf_your_api_key'
   * });
   *
   * // Full configuration
   * const feedbackKit = new FeedbackKit({
   *   apiKey: 'sf_your_api_key',
   *   baseUrl: 'https://api.prod.getfeedbackkit.com/api/v1',
   *   userId: 'user_12345',
   *   timeout: 10000
   * });
   * ```
   */
  constructor(config: FeedbackKitConfig) {
    const apiKey = config.apiKey?.trim();
    if (!apiKey) {
      throw new ValidationError('FeedbackKit: apiKey is required');
    }

    this.userIdStore = createUserIdStore();
    this.sessionUserId = initialUserId(config.userId, this.userIdStore);

    this.config = {
      apiKey,
      baseUrl: resolveBaseUrl(config.baseUrl || DEFAULT_CONFIG.baseUrl),
      userId: this.sessionUserId,
      timeout: config.timeout || DEFAULT_CONFIG.timeout
    };

    this.http = new HttpClient({
      baseUrl: this.config.baseUrl,
      apiKey: this.config.apiKey,
      userId: this.sessionUserId,
      bearerToken: config.bearerToken,
      timeout: this.config.timeout
    });
    this.http.setIdentityResolver(() => this.ensureSessionUserId());

    // Initialize API modules
    this.feedback = new FeedbackApi(this.http);
    this.votes = new VotesApi(this.http);
    this.comments = new CommentsApi(this.http);
    this.users = new UsersApi(this.http);
    this.events = new EventsApi(this.http);
    this.metrics = new MetricsApi(this.http);
  }

  /**
   * Update the current user ID
   *
   * This affects the `hasVoted` state in feedback responses.
   *
   * @param userId - The user ID to set, or undefined to clear. The value is
   *   persisted. Clearing it makes the next request generate a new anonymous id.
   *
   * @example
   * ```ts
   * // Set user ID after login
   * feedbackKit.setUserId('user_12345');
   *
   * // Clear user ID after logout
   * feedbackKit.setUserId(undefined);
   * ```
   */
  setUserId(userId: string | undefined): void {
    const trimmed = userId?.trim() || undefined;
    this.sessionUserId = trimmed;
    this.config.userId = trimmed || '';
    this.userIdStore.set(trimmed);
    this.http.setUserId(trimmed);
  }

  /**
   * Get the current user ID.
   *
   * This is the explicit id when one was set, otherwise the persisted
   * anonymous id. It is undefined only after `setUserId(undefined)`, until
   * the next request.
   */
  getUserId(): string | undefined {
    return this.sessionUserId?.trim() || undefined;
  }

  /**
   * Session id for a request. A cleared id is replaced with a new `local_<uuid>`.
   */
  private ensureSessionUserId(): string {
    const current = this.sessionUserId?.trim();
    if (current) return current;

    const generated = generateLocalUserId();
    this.sessionUserId = generated;
    this.config.userId = generated;
    this.userIdStore.set(generated);
    return generated;
  }

  /**
   * Get the current API base URL
   */
  getBaseUrl(): string {
    return this.config.baseUrl;
  }
}

/**
 * https is required. http is limited to loopback so local tests keep working and a
 * project key is not sent in cleartext to any other host.
 */
function resolveBaseUrl(baseUrl: string): string {
  let url: URL;
  try {
    url = new URL(baseUrl);
  } catch {
    throw new ValidationError('FeedbackKit: baseUrl must be an absolute URL');
  }

  if (url.protocol === 'https:') return baseUrl;
  if (url.protocol === 'http:' && isLoopbackHost(url.hostname)) return baseUrl;

  throw new ValidationError(
    'FeedbackKit: baseUrl must use https. http is only allowed for localhost.'
  );
}

function isLoopbackHost(hostname: string): boolean {
  const host = hostname.replace(/^\[|\]$/g, '').toLowerCase();
  return host === 'localhost' || host === '127.0.0.1' || host === '::1';
}
