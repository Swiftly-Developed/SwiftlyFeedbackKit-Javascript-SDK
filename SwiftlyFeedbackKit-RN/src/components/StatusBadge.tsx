/**
 * StatusBadge Component
 *
 * Displays a feedback status as a colored badge.
 */

import React from 'react';
import { View, Text, StyleSheet, ViewStyle, TextStyle } from 'react-native';
import { FeedbackStatus } from '@feedbackkit/js';
import { useFeedbackKitContext } from '../provider';
import { getStatusColor, getStatusDisplayName } from '../styles/theme';

export interface StatusBadgeProps {
  /** The feedback status */
  status: FeedbackStatus;
  /** Custom container style */
  style?: ViewStyle;
  /** Custom text style */
  textStyle?: TextStyle;
  /** Size variant */
  size?: 'small' | 'medium';
}

/**
 * Badge component for displaying feedback status
 *
 * @example
 * ```tsx
 * <StatusBadge status={FeedbackStatus.InProgress} />
 * <StatusBadge status={feedback.status} size="small" />
 * ```
 */
export function StatusBadge({
  status,
  style,
  textStyle,
  size = 'medium'
}: StatusBadgeProps) {
  const { theme } = useFeedbackKitContext();
  const color = getStatusColor(status, theme);
  const displayName = getStatusDisplayName(status);

  const isSmall = size === 'small';

  return (
    <View
      style={[
        styles.badge,
        {
          backgroundColor: color + '20',
          paddingHorizontal: isSmall ? 6 : 10,
          paddingVertical: isSmall ? 2 : 4,
          borderRadius: isSmall ? 4 : 6
        },
        style
      ]}
    >
      <Text
        style={[
          styles.text,
          {
            color,
            fontSize: isSmall ? 10 : 12
          },
          textStyle
        ]}
      >
        {displayName}
      </Text>
    </View>
  );
}

const styles = StyleSheet.create({
  badge: {
    alignSelf: 'flex-start'
  },
  text: {
    fontWeight: '600'
  }
});
