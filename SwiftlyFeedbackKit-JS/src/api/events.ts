/**
 * Events API
 */

import { HttpClient } from '../utils/http';
import { TrackedEvent, TrackEventRequest } from '../models/types';

/**
 * Predefined event names for SDK views
 */
export const SDKEvents = {
  /** User viewed the feedback list */
  FeedbackList: 'feedback_list',
  /** User viewed feedback details */
  FeedbackDetail: 'feedback_detail',
  /** User opened the submit feedback form */
  SubmitFeedback: 'submit_feedback'
} as const;

/**
 * API for event tracking and analytics
 */
export class EventsApi {
  constructor(private http: HttpClient) {}

  /**
   * Track a custom event
   *
   * Use this to measure user engagement with the feedback system.
   *
   * **Common events:**
   * - `feedback_list` - User viewed feedback list
   * - `feedback_detail` - User viewed feedback details
   * - `submit_feedback` - User opened submit form
   * - Custom events for your app
   *
   * @param request - Event details
   * @returns The tracked event
   * @throws ValidationError if eventName or userId is empty
   *
   * @example
   * ```ts
   * // Track a simple event
   * await feedbackKit.events.track({
   *   eventName: 'feedback_list',
   *   userId: 'user_12345'
   * });
   *
   * // Track with properties
   * await feedbackKit.events.track({
   *   eventName: 'feedback_list',
   *   userId: 'user_12345',
   *   properties: {
   *     filter: 'feature_request',
   *     sort: 'votes'
   *   }
   * });
   *
   * // Track a custom event
   * await feedbackKit.events.track({
   *   eventName: 'onboarding_completed',
   *   userId: 'user_12345',
   *   properties: {
   *     step_count: 5,
   *     duration_seconds: 120
   *   }
   * });
   *
   * // Using predefined SDK events
   * await feedbackKit.events.track({
   *   eventName: SDKEvents.FeedbackList,
   *   userId: 'user_12345'
   * });
   * ```
   */
  async track(request: TrackEventRequest): Promise<TrackedEvent> {
    return this.http.post<TrackedEvent>('/events/track', {
      eventName: request.eventName,
      userId: request.userId,
      properties: request.properties
    });
  }
}

// Re-export types for convenience
export { TrackedEvent, TrackEventRequest };
