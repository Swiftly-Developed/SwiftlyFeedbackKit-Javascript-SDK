/**
 * useComments Hook
 *
 * Fetch and manage comments for a feedback item.
 */

import { useState, useEffect, useCallback } from 'react';
import { Comment, FeedbackKitError } from '@feedbackkit/js';
import { useFeedbackKitContext } from '../provider';

export interface UseCommentsResult {
  /** List of comments */
  comments: Comment[];
  /** Loading state for initial fetch */
  isLoading: boolean;
  /** Error if fetch failed */
  error: FeedbackKitError | null;
  /** Refetch the comments */
  refetch: () => Promise<void>;
  /** Add a new comment */
  addComment: (content: string, isAdmin?: boolean) => Promise<Comment>;
  /** Whether a comment is being added */
  isAdding: boolean;
}

/**
 * Hook to fetch and manage comments
 *
 * @param feedbackId - The feedback UUID
 *
 * @example
 * ```tsx
 * function CommentsSection({ feedbackId }) {
 *   const {
 *     comments,
 *     isLoading,
 *     addComment,
 *     isAdding
 *   } = useComments(feedbackId);
 *
 *   const handleSubmit = async (text: string) => {
 *     try {
 *       await addComment(text);
 *     } catch (error) {
 *       Alert.alert('Error', error.message);
 *     }
 *   };
 *
 *   return (
 *     <View>
 *       {comments.map(comment => (
 *         <CommentCard key={comment.id} comment={comment} />
 *       ))}
 *       <CommentInput onSubmit={handleSubmit} isLoading={isAdding} />
 *     </View>
 *   );
 * }
 * ```
 */
export function useComments(feedbackId: string): UseCommentsResult {
  const { client, userId, isInitialized } = useFeedbackKitContext();
  const [comments, setComments] = useState<Comment[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [isAdding, setIsAdding] = useState(false);
  const [error, setError] = useState<FeedbackKitError | null>(null);

  const fetchComments = useCallback(async () => {
    if (!isInitialized || !feedbackId) return;

    setIsLoading(true);
    setError(null);

    try {
      const result = await client.comments.list(feedbackId);
      setComments(result);
    } catch (err) {
      setError(err as FeedbackKitError);
    } finally {
      setIsLoading(false);
    }
  }, [client, feedbackId, isInitialized]);

  useEffect(() => {
    fetchComments();
  }, [fetchComments]);

  const refetch = useCallback(async () => {
    await fetchComments();
  }, [fetchComments]);

  const addComment = useCallback(
    async (content: string, isAdmin = false): Promise<Comment> => {
      if (!userId) {
        throw new Error('User ID is required to comment. Set userId in FeedbackProvider.');
      }

      setIsAdding(true);

      try {
        const newComment = await client.comments.create(feedbackId, {
          content,
          userId,
          isAdmin
        });
        setComments(prev => [...prev, newComment]);
        return newComment;
      } finally {
        setIsAdding(false);
      }
    },
    [client, feedbackId, userId]
  );

  return {
    comments,
    isLoading,
    error,
    refetch,
    addComment,
    isAdding
  };
}
