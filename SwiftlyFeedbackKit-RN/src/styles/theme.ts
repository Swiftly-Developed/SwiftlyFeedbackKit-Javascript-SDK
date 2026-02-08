/**
 * FeedbackKit Theme
 */

import { FeedbackStatus, FeedbackCategory } from '@feedbackkit/js';

/**
 * Status colors mapping
 */
export interface StatusColors {
  pending: string;
  approved: string;
  inProgress: string;
  testflight: string;
  completed: string;
  rejected: string;
}

/**
 * Category colors mapping
 */
export interface CategoryColors {
  featureRequest: string;
  bugReport: string;
  improvement: string;
  other: string;
}

/**
 * Complete theme configuration
 */
export interface Theme {
  /** Primary brand color */
  primaryColor: string;
  /** Background color */
  backgroundColor: string;
  /** Card background color */
  cardBackgroundColor: string;
  /** Primary text color */
  textColor: string;
  /** Secondary text color */
  secondaryTextColor: string;
  /** Border color */
  borderColor: string;
  /** Error color */
  errorColor: string;
  /** Success color */
  successColor: string;
  /** Status colors */
  statusColors: StatusColors;
  /** Category colors */
  categoryColors: CategoryColors;
  /** Border radius */
  borderRadius: number;
  /** Spacing unit */
  spacing: number;
}

/**
 * Default theme
 */
export const defaultTheme: Theme = {
  primaryColor: '#007AFF',
  backgroundColor: '#F2F2F7',
  cardBackgroundColor: '#FFFFFF',
  textColor: '#000000',
  secondaryTextColor: '#8E8E93',
  borderColor: '#C6C6C8',
  errorColor: '#FF3B30',
  successColor: '#34C759',
  statusColors: {
    pending: '#8E8E93',
    approved: '#007AFF',
    inProgress: '#FF9500',
    testflight: '#5AC8FA',
    completed: '#34C759',
    rejected: '#FF3B30'
  },
  categoryColors: {
    featureRequest: '#AF52DE',
    bugReport: '#FF3B30',
    improvement: '#5AC8FA',
    other: '#8E8E93'
  },
  borderRadius: 12,
  spacing: 8
};

/**
 * Dark theme
 */
export const darkTheme: Theme = {
  ...defaultTheme,
  backgroundColor: '#000000',
  cardBackgroundColor: '#1C1C1E',
  textColor: '#FFFFFF',
  secondaryTextColor: '#8E8E93',
  borderColor: '#38383A'
};

/**
 * Merge theme with overrides
 */
export function mergeTheme(base: Theme, overrides?: Partial<Theme>): Theme {
  if (!overrides) return base;

  return {
    ...base,
    ...overrides,
    statusColors: {
      ...base.statusColors,
      ...overrides.statusColors
    },
    categoryColors: {
      ...base.categoryColors,
      ...overrides.categoryColors
    }
  };
}

/**
 * Get color for a feedback status
 */
export function getStatusColor(status: FeedbackStatus, theme: Theme): string {
  const colorMap: Record<FeedbackStatus, keyof StatusColors> = {
    [FeedbackStatus.Pending]: 'pending',
    [FeedbackStatus.Approved]: 'approved',
    [FeedbackStatus.InProgress]: 'inProgress',
    [FeedbackStatus.TestFlight]: 'testflight',
    [FeedbackStatus.Completed]: 'completed',
    [FeedbackStatus.Rejected]: 'rejected'
  };
  return theme.statusColors[colorMap[status]];
}

/**
 * Get color for a feedback category
 */
export function getCategoryColor(category: FeedbackCategory, theme: Theme): string {
  const colorMap: Record<FeedbackCategory, keyof CategoryColors> = {
    [FeedbackCategory.FeatureRequest]: 'featureRequest',
    [FeedbackCategory.BugReport]: 'bugReport',
    [FeedbackCategory.Improvement]: 'improvement',
    [FeedbackCategory.Other]: 'other'
  };
  return theme.categoryColors[colorMap[category]];
}

/**
 * Get display name for a status
 */
export function getStatusDisplayName(status: FeedbackStatus): string {
  const names: Record<FeedbackStatus, string> = {
    [FeedbackStatus.Pending]: 'Pending',
    [FeedbackStatus.Approved]: 'Approved',
    [FeedbackStatus.InProgress]: 'In Progress',
    [FeedbackStatus.TestFlight]: 'TestFlight',
    [FeedbackStatus.Completed]: 'Completed',
    [FeedbackStatus.Rejected]: 'Rejected'
  };
  return names[status];
}

/**
 * Get display name for a category
 */
export function getCategoryDisplayName(category: FeedbackCategory): string {
  const names: Record<FeedbackCategory, string> = {
    [FeedbackCategory.FeatureRequest]: 'Feature Request',
    [FeedbackCategory.BugReport]: 'Bug Report',
    [FeedbackCategory.Improvement]: 'Improvement',
    [FeedbackCategory.Other]: 'Other'
  };
  return names[category];
}
