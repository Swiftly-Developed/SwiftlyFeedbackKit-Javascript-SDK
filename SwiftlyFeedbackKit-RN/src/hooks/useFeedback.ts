/**
 * useFeedback Hook
 *
 * Fetch a single feedback item by ID.
 */

import { useState, useEffect, useCallback } from 'react';
import { Feedback, FeedbackKitError } from '@feedbackkit/js';
import { useFeedbackKitContext } from '../provider';

export interface UseFeedbackResult {
  /** The feedback item */
  feedback: Feedback | null;
  /** Loading state */
  isLoading: boolean;
  /** Error if fetch failed */
  error: FeedbackKitError | null;
  /** Refetch the feedback */
  refetch: () => Promise<void>;
}

/**
 * Hook to fetch a single feedback item
 *
 * @param feedbackId - The feedback UUID
 *
 * @example
 * ```tsx
 * function FeedbackDetailScreen({ route }) {
 *   const { feedbackId } = route.params;
 *   const { feedback, isLoading, error, refetch } = useFeedback(feedbackId);
 *
 *   if (isLoading) return <LoadingSpinner />;
 *   if (error) return <ErrorView error={error} onRetry={refetch} />;
 *   if (!feedback) return <NotFoundView />;
 *
 *   return <FeedbackDetail feedback={feedback} />;
 * }
 * ```
 */
export function useFeedback(feedbackId: string): UseFeedbackResult {
  const { client, isInitialized } = useFeedbackKitContext();
  const [feedback, setFeedback] = useState<Feedback | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<FeedbackKitError | null>(null);

  const fetchFeedback = useCallback(async () => {
    if (!isInitialized || !feedbackId) return;

    setIsLoading(true);
    setError(null);

    try {
      const result = await client.feedback.get(feedbackId);
      setFeedback(result);
    } catch (err) {
      setError(err as FeedbackKitError);
      setFeedback(null);
    } finally {
      setIsLoading(false);
    }
  }, [client, feedbackId, isInitialized]);

  useEffect(() => {
    fetchFeedback();
  }, [fetchFeedback]);

  const refetch = useCallback(async () => {
    await fetchFeedback();
  }, [fetchFeedback]);

  return {
    feedback,
    isLoading,
    error,
    refetch
  };
}
