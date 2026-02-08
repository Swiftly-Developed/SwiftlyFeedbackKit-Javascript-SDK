/**
 * Feedback API
 */

import { HttpClient } from '../utils/http';
import {
  Feedback,
  CreateFeedbackRequest,
  ListFeedbackOptions,
  FeedbackStatus,
  FeedbackCategory
} from '../models/types';

/**
 * API for managing feedback items
 */
export class FeedbackApi {
  constructor(private http: HttpClient) {}

  /**
   * List all feedback for the project
   *
   * @param options - Filter and pagination options
   * @returns Array of feedback items sorted by vote count (descending)
   *
   * @example
   * ```ts
   * // Get all feedback
   * const all = await feedbackKit.feedback.list();
   *
   * // Filter by status
   * const pending = await feedbackKit.feedback.list({ status: FeedbackStatus.Pending });
   *
   * // Filter by category
   * const bugs = await feedbackKit.feedback.list({ category: FeedbackCategory.BugReport });
   *
   * // Include merged items
   * const withMerged = await feedbackKit.feedback.list({ includeMerged: true });
   * ```
   */
  async list(options?: ListFeedbackOptions): Promise<Feedback[]> {
    return this.http.get<Feedback[]>('/feedbacks', {
      status: options?.status,
      category: options?.category,
      includeMerged: options?.includeMerged
    });
  }

  /**
   * Get a single feedback item by ID
   *
   * @param feedbackId - The feedback UUID
   * @returns The feedback item
   * @throws NotFoundError if feedback doesn't exist
   *
   * @example
   * ```ts
   * const feedback = await feedbackKit.feedback.get('550e8400-e29b-41d4-a716-446655440000');
   * console.log(feedback.title, feedback.voteCount);
   * ```
   */
  async get(feedbackId: string): Promise<Feedback> {
    return this.http.get<Feedback>(`/feedbacks/${feedbackId}`);
  }

  /**
   * Submit new feedback
   *
   * The creator automatically receives a vote (voteCount starts at 1).
   * Triggers notifications to project members and configured integrations.
   *
   * @param request - The feedback to create
   * @returns The created feedback item
   * @throws ValidationError if required fields are missing
   * @throws PaymentRequiredError if feedback limit is exceeded (Free tier)
   * @throws ForbiddenError if project is archived
   *
   * @example
   * ```ts
   * const feedback = await feedbackKit.feedback.create({
   *   title: 'Add dark mode',
   *   description: 'Please add a dark mode option for night time use.',
   *   category: FeedbackCategory.FeatureRequest,
   *   userId: 'user_12345',
   *   userEmail: 'user@example.com' // optional
   * });
   * ```
   */
  async create(request: CreateFeedbackRequest): Promise<Feedback> {
    return this.http.post<Feedback>('/feedbacks', {
      title: request.title,
      description: request.description,
      category: request.category,
      userId: request.userId,
      userEmail: request.userEmail
    });
  }
}

// Re-export types for convenience
export type { Feedback, CreateFeedbackRequest, ListFeedbackOptions };
export { FeedbackStatus, FeedbackCategory };
