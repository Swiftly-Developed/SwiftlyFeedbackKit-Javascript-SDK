/**
 * Users API
 */

import { HttpClient } from '../utils/http';
import { SDKUser, RegisterUserRequest } from '../models/types';

/**
 * API for SDK user registration and tracking
 */
export class UsersApi {
  constructor(private http: HttpClient) {}

  /**
   * Register or update an SDK user
   *
   * Use this to track user activity and associate MRR (Monthly Recurring Revenue).
   * If the user already exists, their `lastSeenAt` timestamp and MRR will be updated.
   *
   * @param request - User registration details
   * @returns The registered/updated user
   * @throws ValidationError if userId is empty
   *
   * @example
   * ```ts
   * // Register a free user
   * const user = await feedbackKit.users.register({
   *   userId: 'user_12345'
   * });
   *
   * // Register a paying user with MRR
   * const payingUser = await feedbackKit.users.register({
   *   userId: 'user_67890',
   *   mrr: 9.99  // Monthly subscription price
   * });
   *
   * // Update MRR when subscription changes
   * const upgraded = await feedbackKit.users.register({
   *   userId: 'user_67890',
   *   mrr: 19.99  // New subscription price
   * });
   * ```
   */
  async register(request: RegisterUserRequest): Promise<SDKUser> {
    return this.http.post<SDKUser>('/users/register', {
      userId: request.userId,
      mrr: request.mrr
    });
  }
}

// Re-export types for convenience
export type { SDKUser, RegisterUserRequest };
