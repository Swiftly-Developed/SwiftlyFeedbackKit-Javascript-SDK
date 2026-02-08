/**
 * useFeedbackList Hook
 *
 * Fetch and manage a list of feedback items.
 */

import { useState, useEffect, useCallback } from 'react';
import {
  Feedback,
  FeedbackStatus,
  FeedbackCategory,
  FeedbackKitError
} from '@feedbackkit/js';
import { useFeedbackKitContext } from '../provider';

export interface FeedbackListFilter {
  status?: FeedbackStatus;
  category?: FeedbackCategory;
  includeMerged?: boolean;
}

export interface UseFeedbackListResult {
  /** List of feedback items */
  feedbacks: Feedback[];
  /** Loading state */
  isLoading: boolean;
  /** Error if fetch failed */
  error: FeedbackKitError | null;
  /** Refetch the list */
  refetch: () => Promise<void>;
  /** Current filter */
  filter: FeedbackListFilter;
  /** Update the filter */
  setFilter: (filter: FeedbackListFilter) => void;
}

/**
 * Hook to fetch and manage feedback list
 *
 * @param initialFilter - Initial filter options
 *
 * @example
 * ```tsx
 * function FeedbackScreen() {
 *   const {
 *     feedbacks,
 *     isLoading,
 *     error,
 *     refetch,
 *     filter,
 *     setFilter
 *   } = useFeedbackList({ status: FeedbackStatus.Approved });
 *
 *   if (isLoading) return <LoadingSpinner />;
 *   if (error) return <ErrorView error={error} onRetry={refetch} />;
 *
 *   return (
 *     <FlatList
 *       data={feedbacks}
 *       renderItem={({ item }) => <FeedbackCard feedback={item} />}
 *       onRefresh={refetch}
 *       refreshing={isLoading}
 *     />
 *   );
 * }
 * ```
 */
export function useFeedbackList(
  initialFilter: FeedbackListFilter = {}
): UseFeedbackListResult {
  const { client, isInitialized } = useFeedbackKitContext();
  const [feedbacks, setFeedbacks] = useState<Feedback[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [error, setError] = useState<FeedbackKitError | null>(null);
  const [filter, setFilter] = useState<FeedbackListFilter>(initialFilter);

  const fetchFeedbacks = useCallback(async () => {
    if (!isInitialized) return;

    setIsLoading(true);
    setError(null);

    try {
      const result = await client.feedback.list({
        status: filter.status,
        category: filter.category,
        includeMerged: filter.includeMerged
      });
      setFeedbacks(result);
    } catch (err) {
      setError(err as FeedbackKitError);
    } finally {
      setIsLoading(false);
    }
  }, [client, filter, isInitialized]);

  // Fetch on mount and when filter changes
  useEffect(() => {
    fetchFeedbacks();
  }, [fetchFeedbacks]);

  const refetch = useCallback(async () => {
    await fetchFeedbacks();
  }, [fetchFeedbacks]);

  return {
    feedbacks,
    isLoading,
    error,
    refetch,
    filter,
    setFilter
  };
}
