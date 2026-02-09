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
import { FeedbackKitConfig, DEFAULT_CONFIG } from './models/types';

/**
 * FeedbackKit SDK Client
 *
 * @example
 * ```ts
 * import { FeedbackKit, FeedbackCategory } from '@feedbackkit/js';
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
 * ```
 */
export class FeedbackKit {
  private http: HttpClient;
  private config: Required<FeedbackKitConfig>;

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

  /**
   * Create a new FeedbackKit client
   *
   * @param config - Client configuration
   * @param config.apiKey - Your project API key (required)
   * @param config.baseUrl - API base URL (optional, defaults to production)
   * @param config.userId - Current user ID for hasVoted state (optional)
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
   *   baseUrl: 'https://feedbackkit.swiftly-workspace.com/api/v1',
   *   userId: 'user_12345',
   *   timeout: 10000
   * });
   * ```
   */
  constructor(config: FeedbackKitConfig) {
    if (!config.apiKey) {
      throw new Error('FeedbackKit: apiKey is required');
    }

    this.config = {
      apiKey: config.apiKey,
      baseUrl: config.baseUrl || DEFAULT_CONFIG.baseUrl,
      userId: config.userId || '',
      timeout: config.timeout || DEFAULT_CONFIG.timeout
    };

    this.http = new HttpClient({
      baseUrl: this.config.baseUrl,
      apiKey: this.config.apiKey,
      userId: this.config.userId || undefined,
      timeout: this.config.timeout
    });

    // Initialize API modules
    this.feedback = new FeedbackApi(this.http);
    this.votes = new VotesApi(this.http);
    this.comments = new CommentsApi(this.http);
    this.users = new UsersApi(this.http);
    this.events = new EventsApi(this.http);
  }

  /**
   * Update the current user ID
   *
   * This affects the `hasVoted` state in feedback responses.
   *
   * @param userId - The user ID to set, or undefined to clear
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
    this.config.userId = userId || '';
    this.http.setUserId(userId);
  }

  /**
   * Get the current user ID
   */
  getUserId(): string | undefined {
    return this.config.userId || undefined;
  }

  /**
   * Get the current API base URL
   */
  getBaseUrl(): string {
    return this.config.baseUrl;
  }
}
