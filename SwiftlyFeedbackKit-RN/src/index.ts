/**
 * FeedbackKit React Native SDK
 *
 * A complete React Native SDK for integrating FeedbackKit into your mobile apps.
 */

// Re-export everything from the JS SDK
export * from '@feedbackkit/js';

// Provider
export { FeedbackProvider, type FeedbackProviderProps, type FeedbackKitTheme, useFeedbackKitContext } from './provider';

// Hooks
export {
  useFeedbackKit,
  useFeedbackList,
  useFeedback,
  useVote,
  useComments,
  useSubmitFeedback
} from './hooks';

// Components
export {
  StatusBadge,
  type StatusBadgeProps,
  CategoryBadge,
  type CategoryBadgeProps,
  VoteButton,
  type VoteButtonProps,
  FeedbackCard,
  type FeedbackCardProps,
  FeedbackList,
  type FeedbackListProps
} from './components';

// Theme
export {
  type Theme,
  defaultTheme,
  darkTheme,
  mergeTheme,
  getStatusColor,
  getStatusDisplayName,
  getCategoryColor,
  getCategoryDisplayName
} from './styles/theme';
