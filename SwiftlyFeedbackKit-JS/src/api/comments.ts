/**
 * Comments API
 */

import { HttpClient } from '../utils/http';
import { Comment, CreateCommentRequest } from '../models/types';

/**
 * API for managing comments on feedback items
 */
export class CommentsApi {
  constructor(private http: HttpClient) {}

  /**
   * List all comments for a feedback item
   *
   * Comments are sorted by creation time (ascending - oldest first).
   *
   * @param feedbackId - The feedback UUID
   * @returns Array of comments
   * @throws NotFoundError if feedback doesn't exist
   *
   * @example
   * ```ts
   * const comments = await feedbackKit.comments.list('feedback-id');
   * for (const comment of comments) {
   *   console.log(`${comment.userId}: ${comment.content}`);
   *   if (comment.isAdmin) console.log('(Admin response)');
   * }
   * ```
   */
  async list(feedbackId: string): Promise<Comment[]> {
    return this.http.get<Comment[]>(`/feedbacks/${feedbackId}/comments`);
  }

  /**
   * Add a comment to a feedback item
   *
   * @param feedbackId - The feedback UUID
   * @param request - Comment details
   * @returns The created comment
   * @throws NotFoundError if feedback doesn't exist
   * @throws ValidationError if content is empty
   * @throws ForbiddenError if project is archived
   *
   * @example
   * ```ts
   * // User comment
   * const comment = await feedbackKit.comments.create('feedback-id', {
   *   content: 'This would be really helpful!',
   *   userId: 'user_12345'
   * });
   *
   * // Admin response
   * const adminComment = await feedbackKit.comments.create('feedback-id', {
   *   content: 'Thanks for the feedback! We are working on this.',
   *   userId: 'admin_user',
   *   isAdmin: true
   * });
   * ```
   */
  async create(feedbackId: string, request: CreateCommentRequest): Promise<Comment> {
    return this.http.post<Comment>(`/feedbacks/${feedbackId}/comments`, {
      content: request.content,
      userId: request.userId,
      isAdmin: request.isAdmin ?? false
    });
  }
}

// Re-export types for convenience
export { Comment, CreateCommentRequest };
