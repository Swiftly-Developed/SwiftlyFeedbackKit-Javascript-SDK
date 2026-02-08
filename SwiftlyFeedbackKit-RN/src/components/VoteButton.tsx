/**
 * VoteButton Component
 *
 * Button for voting/unvoting on feedback.
 */

import React, { useState } from 'react';
import {
  TouchableOpacity,
  Text,
  StyleSheet,
  ViewStyle,
  ActivityIndicator,
  View
} from 'react-native';
import { Feedback, FeedbackStatus } from '@feedbackkit/js';
import { useFeedbackKitContext } from '../provider';
import { useVote } from '../hooks/useVote';

export interface VoteButtonProps {
  /** The feedback to vote on */
  feedback: Feedback;
  /** Called when vote state changes */
  onVoteChange?: (hasVoted: boolean, voteCount: number) => void;
  /** Custom container style */
  style?: ViewStyle;
  /** Whether to show the vote count */
  showCount?: boolean;
  /** Size variant */
  size?: 'small' | 'medium' | 'large';
}

/**
 * Button component for voting on feedback
 *
 * @example
 * ```tsx
 * <VoteButton
 *   feedback={feedback}
 *   onVoteChange={(hasVoted, count) => {
 *     // Update local state if needed
 *   }}
 * />
 * ```
 */
export function VoteButton({
  feedback,
  onVoteChange,
  style,
  showCount = true,
  size = 'medium'
}: VoteButtonProps) {
  const { theme } = useFeedbackKitContext();
  const { vote, unvote, isVoting } = useVote();
  const [localHasVoted, setLocalHasVoted] = useState(feedback.hasVoted);
  const [localVoteCount, setLocalVoteCount] = useState(feedback.voteCount);

  // Check if voting is allowed
  const canVote =
    feedback.status !== FeedbackStatus.Completed &&
    feedback.status !== FeedbackStatus.Rejected;

  const handlePress = async () => {
    if (!canVote || isVoting) return;

    try {
      if (localHasVoted) {
        const result = await unvote(feedback.id);
        setLocalHasVoted(result.hasVoted);
        setLocalVoteCount(result.voteCount);
        onVoteChange?.(result.hasVoted, result.voteCount);
      } else {
        const result = await vote(feedback.id);
        setLocalHasVoted(result.hasVoted);
        setLocalVoteCount(result.voteCount);
        onVoteChange?.(result.hasVoted, result.voteCount);
      }
    } catch {
      // Error handling is done in the hook
    }
  };

  const sizeStyles = {
    small: { paddingHorizontal: 8, paddingVertical: 4 },
    medium: { paddingHorizontal: 12, paddingVertical: 8 },
    large: { paddingHorizontal: 16, paddingVertical: 12 }
  };

  const fontSizes = {
    small: 12,
    medium: 14,
    large: 16
  };

  return (
    <TouchableOpacity
      onPress={handlePress}
      disabled={!canVote || isVoting}
      style={[
        styles.button,
        sizeStyles[size],
        {
          backgroundColor: localHasVoted ? theme.primaryColor : theme.primaryColor + '20',
          borderRadius: theme.borderRadius / 2,
          opacity: canVote ? 1 : 0.5
        },
        style
      ]}
      activeOpacity={0.7}
    >
      {isVoting ? (
        <ActivityIndicator
          size="small"
          color={localHasVoted ? '#FFFFFF' : theme.primaryColor}
        />
      ) : (
        <View style={styles.content}>
          <Text
            style={[
              styles.arrow,
              {
                color: localHasVoted ? '#FFFFFF' : theme.primaryColor,
                fontSize: fontSizes[size]
              }
            ]}
          >
            ▲
          </Text>
          {showCount && (
            <Text
              style={[
                styles.count,
                {
                  color: localHasVoted ? '#FFFFFF' : theme.primaryColor,
                  fontSize: fontSizes[size]
                }
              ]}
            >
              {localVoteCount}
            </Text>
          )}
        </View>
      )}
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  button: {
    alignItems: 'center',
    justifyContent: 'center',
    minWidth: 50
  },
  content: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4
  },
  arrow: {
    fontWeight: '700'
  },
  count: {
    fontWeight: '600'
  }
});
