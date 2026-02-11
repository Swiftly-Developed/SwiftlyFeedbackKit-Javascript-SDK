/**
 * FeedbackKit TypeScript Types
 * Generated from OpenAPI specification
 */

// ============================================================================
// Enums
// ============================================================================

/**
 * Status of a feedback item
 */
export enum FeedbackStatus {
  Pending = 'pending',
  Approved = 'approved',
  InProgress = 'in_progress',
  TestFlight = 'testflight',
  Completed = 'completed',
  Rejected = 'rejected'
}

/**
 * Category of a feedback item
 */
export enum FeedbackCategory {
  FeatureRequest = 'feature_request',
  BugReport = 'bug_report',
  Improvement = 'improvement',
  Other = 'other'
}

// ============================================================================
// Feedback Types
// ============================================================================

/**
 * A feedback item
 */
export interface Feedback {
  /** Unique identifier */
  id: string;
  /** Feedback title */
  title: string;
  /** Detailed description */
  description: string;
  /** Current status */
  status: FeedbackStatus;
  /** Feedback category */
  category: FeedbackCategory;
  /** ID of the user who submitted */
  userId: string;
  /** Email of the submitter (if provided) */
  userEmail?: string | null;
  /** Total number of votes */
  voteCount: number;
  /** Whether the current user has voted */
  hasVoted: boolean;
  /** Total number of comments */
  commentCount: number;
  /** Combined MRR of all voters */
  totalMrr?: number | null;
  /** When the feedback was created */
  createdAt: string;
  /** When the feedback was last updated */
  updatedAt: string;
  /** Explanation for rejection (only for rejected status) */
  rejectionReason?: string | null;
  /** ID of the feedback this was merged into */
  mergedIntoId?: string | null;
  /** When this feedback was merged */
  mergedAt?: string | null;
  /** IDs of feedback items merged into this one */
  mergedFeedbackIds?: string[] | null;
}

/**
 * Request to create a new feedback item
 */
export interface CreateFeedbackRequest {
  /** Brief title (1-200 chars) */
  title: string;
  /** Detailed description (1-5000 chars) */
  description: string;
  /** Feedback category */
  category: FeedbackCategory;
  /** Unique identifier of the submitting user */
  userId: string;
  /** Optional email for status update notifications */
  userEmail?: string;
  /** Whether the user consents to join the project's mailing list */
  subscribeToMailingList?: boolean;
  /** Email preference types (e.g. ["operational", "marketing"]). Defaults to both when omitted. */
  mailingListEmailTypes?: string[];
}

/**
 * Options for listing feedback
 */
export interface ListFeedbackOptions {
  /** Filter by status */
  status?: FeedbackStatus;
  /** Filter by category */
  category?: FeedbackCategory;
  /** Include merged feedback items */
  includeMerged?: boolean;
}

// ============================================================================
// Vote Types
// ============================================================================

/**
 * Request to vote for a feedback item
 */
export interface VoteRequest {
  /** Unique identifier of the voting user */
  userId: string;
  /** Email for status change notifications */
  email?: string;
  /** Opt-in to receive email notifications when status changes */
  notifyStatusChange?: boolean;
  /** Whether the user consents to join the project's mailing list */
  subscribeToMailingList?: boolean;
  /** Email preference types (e.g. ["operational", "marketing"]). Defaults to both when omitted. */
  mailingListEmailTypes?: string[];
}

/**
 * Request to remove a vote
 */
export interface UnvoteRequest {
  /** Unique identifier of the user removing their vote */
  userId: string;
}

/**
 * Response after voting/unvoting
 */
export interface VoteResponse {
  /** ID of the feedback item */
  feedbackId: string;
  /** Updated vote count */
  voteCount: number;
  /** Whether the user has voted after this action */
  hasVoted: boolean;
}

// ============================================================================
// Comment Types
// ============================================================================

/**
 * A comment on a feedback item
 */
export interface Comment {
  /** Unique identifier */
  id: string;
  /** Comment text */
  content: string;
  /** ID of the commenting user */
  userId: string;
  /** Whether this is an admin comment */
  isAdmin: boolean;
  /** When the comment was created */
  createdAt: string;
}

/**
 * Request to create a comment
 */
export interface CreateCommentRequest {
  /** Comment text (1-2000 chars) */
  content: string;
  /** Unique identifier of the commenting user */
  userId: string;
  /** Whether this comment is from an admin/developer */
  isAdmin?: boolean;
}

// ============================================================================
// User Types
// ============================================================================

/**
 * An SDK user
 */
export interface SDKUser {
  /** Internal unique identifier */
  id: string;
  /** SDK user identifier */
  userId: string;
  /** Monthly Recurring Revenue */
  mrr?: number | null;
  /** When the user was first registered */
  firstSeenAt: string;
  /** When the user was last seen */
  lastSeenAt: string;
}

/**
 * Request to register/update an SDK user
 */
export interface RegisterUserRequest {
  /** Unique identifier of the SDK user */
  userId: string;
  /** Monthly Recurring Revenue (optional) */
  mrr?: number;
}

// ============================================================================
// Event Types
// ============================================================================

/**
 * A tracked event
 */
export interface TrackedEvent {
  /** Unique identifier */
  id: string;
  /** Name of the tracked event */
  eventName: string;
  /** User who triggered the event */
  userId: string;
  /** Event properties */
  properties?: Record<string, unknown> | null;
  /** When the event was tracked */
  createdAt: string;
}

/**
 * Request to track an event
 */
export interface TrackEventRequest {
  /** Name of the event to track */
  eventName: string;
  /** Unique identifier of the user */
  userId: string;
  /** Optional key-value properties for the event */
  properties?: Record<string, unknown>;
}

// ============================================================================
// Configuration Types
// ============================================================================

/**
 * FeedbackKit client configuration
 */
export interface FeedbackKitConfig {
  /** Project API key (starts with sf_) */
  apiKey: string;
  /** Base URL of the FeedbackKit API */
  baseUrl?: string;
  /** Current user ID (for hasVoted state in responses) */
  userId?: string;
  /** Request timeout in milliseconds */
  timeout?: number;
}

/**
 * Default configuration values
 */
export const DEFAULT_CONFIG = {
  baseUrl: 'https://feedbackkit.swiftly-workspace.com/api/v1',
  timeout: 30000
} as const;
