/**
 * Votes API
 */

import { HttpClient } from '../utils/http';
import { VoteRequest, UnvoteRequest, VoteResponse } from '../models/types';

/**
 * API for voting on feedback items
 */
export class VotesApi {
  constructor(private http: HttpClient) {}

  /**
   * Vote for a feedback item
   *
   * Each user can only vote once per feedback item.
   *
   * **Restrictions:**
   * - Cannot vote on archived projects (403 Forbidden)
   * - Cannot vote on completed or rejected feedback (403 Forbidden)
   * - Cannot vote twice (409 Conflict)
   *
   * **Notifications:**
   * - Set `notifyStatusChange: true` with an email to receive status update emails
   * - Voter notifications require Team tier subscription
   *
   * @param feedbackId - The feedback UUID to vote for
   * @param request - Vote details including userId and optional email
   * @returns Updated vote count and hasVoted state
   * @throws NotFoundError if feedback doesn't exist
   * @throws ForbiddenError if voting is not allowed
   * @throws ConflictError if user has already voted
   *
   * @example
   * ```ts
   * // Simple vote
   * const result = await feedbackKit.votes.vote('feedback-id', {
   *   userId: 'user_12345'
   * });
   *
   * // Vote with email notification opt-in
   * const result = await feedbackKit.votes.vote('feedback-id', {
   *   userId: 'user_12345',
   *   email: 'user@example.com',
   *   notifyStatusChange: true
   * });
   * ```
   */
  async vote(feedbackId: string, request: VoteRequest): Promise<VoteResponse> {
    return this.http.post<VoteResponse>(`/feedbacks/${feedbackId}/votes`, {
      userId: request.userId,
      email: request.email,
      notifyStatusChange: request.notifyStatusChange ?? false
    });
  }

  /**
   * Remove a vote from a feedback item
   *
   * @param feedbackId - The feedback UUID to remove vote from
   * @param request - Unvote details including userId
   * @returns Updated vote count and hasVoted state
   * @throws NotFoundError if feedback doesn't exist
   *
   * @example
   * ```ts
   * const result = await feedbackKit.votes.unvote('feedback-id', {
   *   userId: 'user_12345'
   * });
   * console.log(result.hasVoted); // false
   * ```
   */
  async unvote(feedbackId: string, request: UnvoteRequest): Promise<VoteResponse> {
    return this.http.delete<VoteResponse>(`/feedbacks/${feedbackId}/votes`, {
      userId: request.userId
    });
  }
}

// Re-export types for convenience
export type { VoteRequest, UnvoteRequest, VoteResponse };
