/**
 * FeedbackKit React Native SDK
 *
 * A complete React Native SDK for integrating FeedbackKit into your mobile apps.
 */

// Re-export everything from the JS SDK
export * from '@feedbackkit/js';

// Provider
export { FeedbackKitProvider, type FeedbackKitProviderProps } from './provider';

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
  type FeedbackKitTheme,
  defaultTheme,
  darkTheme,
  createTheme,
  getStatusColor,
  getStatusDisplayName,
  getCategoryColor,
  getCategoryDisplayName
} from './styles/theme';
