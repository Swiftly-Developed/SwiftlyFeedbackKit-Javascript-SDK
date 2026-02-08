/**
 * useFeedbackKit Hook
 *
 * Access the FeedbackKit client from context.
 */

import { useFeedbackKitContext } from '../provider';
import { FeedbackKit } from '@feedbackkit/js';

/**
 * Hook to access the FeedbackKit client
 *
 * @returns The FeedbackKit client instance
 *
 * @example
 * ```tsx
 * function MyComponent() {
 *   const feedbackKit = useFeedbackKit();
 *
 *   const handleSubmit = async () => {
 *     await feedbackKit.feedback.create({
 *       title: 'My feedback',
 *       description: 'Details...',
 *       category: FeedbackCategory.FeatureRequest,
 *       userId: 'user_123'
 *     });
 *   };
 * }
 * ```
 */
export function useFeedbackKit(): FeedbackKit {
  const { client } = useFeedbackKitContext();
  return client;
}
