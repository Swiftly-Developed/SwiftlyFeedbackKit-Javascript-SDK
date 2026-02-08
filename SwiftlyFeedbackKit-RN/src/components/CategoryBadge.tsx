/**
 * CategoryBadge Component
 *
 * Displays a feedback category as a colored badge.
 */

import React from 'react';
import { View, Text, StyleSheet, ViewStyle, TextStyle } from 'react-native';
import { FeedbackCategory } from '@feedbackkit/js';
import { useFeedbackKitContext } from '../provider';
import { getCategoryColor, getCategoryDisplayName } from '../styles/theme';

export interface CategoryBadgeProps {
  /** The feedback category */
  category: FeedbackCategory;
  /** Custom container style */
  style?: ViewStyle;
  /** Custom text style */
  textStyle?: TextStyle;
  /** Size variant */
  size?: 'small' | 'medium';
}

/**
 * Badge component for displaying feedback category
 *
 * @example
 * ```tsx
 * <CategoryBadge category={FeedbackCategory.FeatureRequest} />
 * <CategoryBadge category={feedback.category} size="small" />
 * ```
 */
export function CategoryBadge({
  category,
  style,
  textStyle,
  size = 'medium'
}: CategoryBadgeProps) {
  const { theme } = useFeedbackKitContext();
  const color = getCategoryColor(category, theme);
  const displayName = getCategoryDisplayName(category);

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
