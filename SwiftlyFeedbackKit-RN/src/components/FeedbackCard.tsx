/**
 * FeedbackCard Component
 *
 * Card component for displaying a single feedback item.
 */

import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ViewStyle
} from 'react-native';
import { Feedback } from '@feedbackkit/js';
import { useFeedbackKitContext } from '../provider';
import { StatusBadge } from './StatusBadge';
import { CategoryBadge } from './CategoryBadge';
import { VoteButton } from './VoteButton';

export interface FeedbackCardProps {
  /** The feedback item to display */
  feedback: Feedback;
  /** Called when the card is pressed */
  onPress?: (feedback: Feedback) => void;
  /** Called when vote state changes */
  onVoteChange?: (hasVoted: boolean, voteCount: number) => void;
  /** Custom container style */
  style?: ViewStyle;
  /** Whether to show the status badge */
  showStatus?: boolean;
  /** Whether to show the category badge */
  showCategory?: boolean;
  /** Whether to show the vote button */
  showVoteButton?: boolean;
  /** Whether to show the comment count */
  showCommentCount?: boolean;
}

/**
 * Card component for displaying feedback in a list
 *
 * @example
 * ```tsx
 * <FeedbackCard
 *   feedback={feedback}
 *   onPress={(f) => navigation.navigate('Detail', { id: f.id })}
 * />
 * ```
 */
export function FeedbackCard({
  feedback,
  onPress,
  onVoteChange,
  style,
  showStatus = true,
  showCategory = true,
  showVoteButton = true,
  showCommentCount = true
}: FeedbackCardProps) {
  const { theme } = useFeedbackKitContext();

  const handlePress = () => {
    onPress?.(feedback);
  };

  const content = (
    <View
      style={[
        styles.card,
        {
          backgroundColor: theme.cardBackgroundColor,
          borderRadius: theme.borderRadius,
          padding: theme.spacing * 2
        },
        style
      ]}
    >
      <View style={styles.header}>
        <View style={styles.badges}>
          {showStatus && <StatusBadge status={feedback.status} size="small" />}
          {showCategory && (
            <CategoryBadge category={feedback.category} size="small" />
          )}
        </View>
        {showVoteButton && (
          <VoteButton
            feedback={feedback}
            onVoteChange={onVoteChange}
            size="small"
          />
        )}
      </View>

      <Text
        style={[styles.title, { color: theme.textColor }]}
        numberOfLines={2}
      >
        {feedback.title}
      </Text>

      <Text
        style={[styles.description, { color: theme.secondaryTextColor }]}
        numberOfLines={2}
      >
        {feedback.description}
      </Text>

      {showCommentCount && feedback.commentCount > 0 && (
        <View style={styles.footer}>
          <Text style={[styles.commentCount, { color: theme.secondaryTextColor }]}>
            💬 {feedback.commentCount} comment{feedback.commentCount !== 1 ? 's' : ''}
          </Text>
        </View>
      )}
    </View>
  );

  if (onPress) {
    return (
      <TouchableOpacity onPress={handlePress} activeOpacity={0.7}>
        {content}
      </TouchableOpacity>
    );
  }

  return content;
}

const styles = StyleSheet.create({
  card: {
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    marginBottom: 8
  },
  badges: {
    flexDirection: 'row',
    gap: 6,
    flexWrap: 'wrap',
    flex: 1
  },
  title: {
    fontSize: 16,
    fontWeight: '600',
    marginBottom: 4
  },
  description: {
    fontSize: 14,
    lineHeight: 20
  },
  footer: {
    marginTop: 8,
    flexDirection: 'row',
    alignItems: 'center'
  },
  commentCount: {
    fontSize: 12
  }
});
