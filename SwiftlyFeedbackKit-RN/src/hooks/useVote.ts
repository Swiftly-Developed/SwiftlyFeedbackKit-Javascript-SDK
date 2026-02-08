/**
 * useVote Hook
 *
 * Vote and unvote on feedback items.
 */

import { useState, useCallback } from 'react';
import { VoteResponse, FeedbackKitError } from '@feedbackkit/js';
import { useFeedbackKitContext } from '../provider';

export interface UseVoteOptions {
  /** Email for status change notifications */
  email?: string;
  /** Opt-in to receive notifications when status changes */
  notifyStatusChange?: boolean;
}

export interface UseVoteResult {
  /** Vote for a feedback item */
  vote: (feedbackId: string, options?: UseVoteOptions) => Promise<VoteResponse>;
  /** Remove vote from a feedback item */
  unvote: (feedbackId: string) => Promise<VoteResponse>;
  /** Whether a vote operation is in progress */
  isVoting: boolean;
  /** Error from last vote operation */
  error: FeedbackKitError | null;
}

/**
 * Hook to vote and unvote on feedback
 *
 * @example
 * ```tsx
 * function VoteButton({ feedback }) {
 *   const { vote, unvote, isVoting } = useVote();
 *
 *   const handlePress = async () => {
 *     try {
 *       if (feedback.hasVoted) {
 *         await unvote(feedback.id);
 *       } else {
 *         await vote(feedback.id, {
 *           email: user.email,
 *           notifyStatusChange: true
 *         });
 *       }
 *     } catch (error) {
 *       Alert.alert('Error', error.message);
 *     }
 *   };
 *
 *   return (
 *     <TouchableOpacity onPress={handlePress} disabled={isVoting}>
 *       <Text>{feedback.hasVoted ? 'Voted' : 'Vote'}</Text>
 *       <Text>{feedback.voteCount}</Text>
 *     </TouchableOpacity>
 *   );
 * }
 * ```
 */
export function useVote(): UseVoteResult {
  const { client, userId } = useFeedbackKitContext();
  const [isVoting, setIsVoting] = useState(false);
  const [error, setError] = useState<FeedbackKitError | null>(null);

  const vote = useCallback(
    async (feedbackId: string, options?: UseVoteOptions): Promise<VoteResponse> => {
      if (!userId) {
        throw new Error('User ID is required to vote. Set userId in FeedbackProvider.');
      }

      setIsVoting(true);
      setError(null);

      try {
        const result = await client.votes.vote(feedbackId, {
          userId,
          email: options?.email,
          notifyStatusChange: options?.notifyStatusChange
        });
        return result;
      } catch (err) {
        const feedbackError = err as FeedbackKitError;
        setError(feedbackError);
        throw feedbackError;
      } finally {
        setIsVoting(false);
      }
    },
    [client, userId]
  );

  const unvote = useCallback(
    async (feedbackId: string): Promise<VoteResponse> => {
      if (!userId) {
        throw new Error('User ID is required to unvote. Set userId in FeedbackProvider.');
      }

      setIsVoting(true);
      setError(null);

      try {
        const result = await client.votes.unvote(feedbackId, { userId });
        return result;
      } catch (err) {
        const feedbackError = err as FeedbackKitError;
        setError(feedbackError);
        throw feedbackError;
      } finally {
        setIsVoting(false);
      }
    },
    [client, userId]
  );

  return {
    vote,
    unvote,
    isVoting,
    error
  };
}
