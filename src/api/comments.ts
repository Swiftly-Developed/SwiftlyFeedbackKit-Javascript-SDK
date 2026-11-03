/**
 * Comments API
 */

import { HttpClient } from '../utils/http';
import { Comment, CreateCommentRequest } from '../models/types';
import { ValidationError } from '../models/errors';
import { collectList } from './listPages';

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
  async list(feedbackId: string, options?: { page?: number; perPage?: number }): Promise<Comment[]> {
    const path = `/feedbacks/${feedbackId}/comments`;
    return collectList<Comment>(path, async (page, perPage) => {
      return this.http.get<unknown>(path, {
        paged: 1,
        page,
        per_page: perPage
      });
    }, options?.page, options?.perPage);
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
   * // Admin response. The client must have been created with `bearerToken`
   * // (a server-side credential). The project API key alone cannot mark a
   * // reply as admin.
   * const adminComment = await feedbackKit.comments.create('feedback-id', {
   *   content: 'Thanks for the feedback! We are working on this.',
   *   userId: 'admin_user',
   *   isAdmin: true
   * });
   * ```
   */
  async create(feedbackId: string, request: CreateCommentRequest): Promise<Comment> {
    const isAdmin = request.isAdmin ?? false;
    return this.http.post<Comment>(
      `/feedbacks/${feedbackId}/comments`,
      {
        content: request.content,
        userId: this.http.resolveRequestUserId(request.userId),
        isAdmin
      },
      isAdmin
    );
  }

  /**
   * Delete the current user's own comment
   *
   * The request carries `X-API-Key` and `X-User-Id`. With no user id this throws
   * before sending anything, because a key alone does not name who is deleting.
   *
   * @param feedbackId - The feedback UUID
   * @param commentId - The comment UUID
   * @throws ValidationError if no user id is available
   * @throws ForbiddenError if the comment is another user's or a staff reply, or the project is archived
   * @throws NotFoundError if the feedback or comment doesn't exist
   *
   * @example
   * ```ts
   * await feedbackKit.comments.delete('feedback-id', 'comment-id');
   * ```
   */
  async delete(feedbackId: string, commentId: string): Promise<void> {
    if (!this.http.ensureUserId()) {
      throw new ValidationError('A user id is required to delete a comment.');
    }
    await this.http.delete<unknown>(`/feedbacks/${feedbackId}/comments/${commentId}`);
  }
}

// Re-export types for convenience
export type { Comment, CreateCommentRequest };
