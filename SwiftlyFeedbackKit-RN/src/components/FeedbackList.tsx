/**
 * FeedbackList Component
 *
 * Scrollable list of feedback items.
 */

import React from 'react';
import {
  FlatList,
  View,
  Text,
  StyleSheet,
  RefreshControl,
  TouchableOpacity,
  ActivityIndicator,
  ViewStyle
} from 'react-native';
import { Feedback, FeedbackStatus, FeedbackCategory } from '@feedbackkit/js';
import { useFeedbackKitContext } from '../provider';
import { useFeedbackList } from '../hooks/useFeedbackList';
import { FeedbackCard } from './FeedbackCard';

export interface FeedbackListProps {
  /** Called when a feedback item is pressed */
  onFeedbackPress?: (feedback: Feedback) => void;
  /** Filter by status */
  filterByStatus?: FeedbackStatus;
  /** Filter by category */
  filterByCategory?: FeedbackCategory;
  /** Whether to show the add button */
  showAddButton?: boolean;
  /** Called when add button is pressed */
  onAddPress?: () => void;
  /** Custom empty component */
  emptyComponent?: React.ReactElement;
  /** List header component */
  ListHeaderComponent?: React.ComponentType | React.ReactElement;
  /** Custom container style */
  style?: ViewStyle;
  /** Custom content container style */
  contentContainerStyle?: ViewStyle;
}

/**
 * List component for displaying feedback items
 *
 * @example
 * ```tsx
 * <FeedbackList
 *   onFeedbackPress={(f) => navigation.navigate('Detail', { id: f.id })}
 *   filterByStatus={FeedbackStatus.Approved}
 *   showAddButton
 *   onAddPress={() => navigation.navigate('Submit')}
 * />
 * ```
 */
export function FeedbackList({
  onFeedbackPress,
  filterByStatus,
  filterByCategory,
  showAddButton = false,
  onAddPress,
  emptyComponent,
  ListHeaderComponent,
  style,
  contentContainerStyle
}: FeedbackListProps) {
  const { theme } = useFeedbackKitContext();
  const { feedbacks, isLoading, error, refetch } = useFeedbackList({
    status: filterByStatus,
    category: filterByCategory
  });

  const renderItem = ({ item }: { item: Feedback }) => (
    <FeedbackCard
      feedback={item}
      onPress={onFeedbackPress}
      style={{ marginBottom: theme.spacing * 2 }}
    />
  );

  const renderEmpty = () => {
    if (isLoading) {
      return (
        <View style={styles.centerContainer}>
          <ActivityIndicator size="large" color={theme.primaryColor} />
        </View>
      );
    }

    if (error) {
      return (
        <View style={styles.centerContainer}>
          <Text style={[styles.errorText, { color: theme.errorColor }]}>
            {error.message}
          </Text>
          <TouchableOpacity onPress={refetch} style={styles.retryButton}>
            <Text style={[styles.retryText, { color: theme.primaryColor }]}>
              Tap to retry
            </Text>
          </TouchableOpacity>
        </View>
      );
    }

    if (emptyComponent) {
      return emptyComponent;
    }

    return (
      <View style={styles.centerContainer}>
        <Text style={[styles.emptyTitle, { color: theme.textColor }]}>
          No feedback yet
        </Text>
        <Text style={[styles.emptySubtitle, { color: theme.secondaryTextColor }]}>
          Be the first to share your ideas!
        </Text>
        {showAddButton && onAddPress && (
          <TouchableOpacity
            onPress={onAddPress}
            style={[
              styles.addButtonEmpty,
              { backgroundColor: theme.primaryColor, borderRadius: theme.borderRadius }
            ]}
          >
            <Text style={styles.addButtonText}>Submit Feedback</Text>
          </TouchableOpacity>
        )}
      </View>
    );
  };

  return (
    <View style={[styles.container, { backgroundColor: theme.backgroundColor }, style]}>
      <FlatList
        data={feedbacks}
        renderItem={renderItem}
        keyExtractor={(item) => item.id}
        contentContainerStyle={[
          styles.listContent,
          { padding: theme.spacing * 2 },
          feedbacks.length === 0 && styles.emptyListContent,
          contentContainerStyle
        ]}
        ListHeaderComponent={ListHeaderComponent}
        ListEmptyComponent={renderEmpty}
        refreshControl={
          <RefreshControl
            refreshing={isLoading && feedbacks.length > 0}
            onRefresh={refetch}
            tintColor={theme.primaryColor}
            colors={[theme.primaryColor]}
          />
        }
        showsVerticalScrollIndicator={false}
      />

      {showAddButton && onAddPress && feedbacks.length > 0 && (
        <TouchableOpacity
          onPress={onAddPress}
          style={[
            styles.fab,
            {
              backgroundColor: theme.primaryColor,
              borderRadius: 28,
              bottom: theme.spacing * 2,
              right: theme.spacing * 2
            }
          ]}
          activeOpacity={0.8}
        >
          <Text style={styles.fabText}>+</Text>
        </TouchableOpacity>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1
  },
  listContent: {
    flexGrow: 1
  },
  emptyListContent: {
    flex: 1,
    justifyContent: 'center'
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20
  },
  errorText: {
    fontSize: 16,
    textAlign: 'center',
    marginBottom: 12
  },
  retryButton: {
    padding: 12
  },
  retryText: {
    fontSize: 16,
    fontWeight: '600'
  },
  emptyTitle: {
    fontSize: 20,
    fontWeight: '600',
    marginBottom: 8
  },
  emptySubtitle: {
    fontSize: 16,
    textAlign: 'center',
    marginBottom: 20
  },
  addButtonEmpty: {
    paddingHorizontal: 24,
    paddingVertical: 12
  },
  addButtonText: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '600'
  },
  fab: {
    position: 'absolute',
    width: 56,
    height: 56,
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.25,
    shadowRadius: 4,
    elevation: 5
  },
  fabText: {
    color: '#FFFFFF',
    fontSize: 28,
    fontWeight: '400',
    marginTop: -2
  }
});
