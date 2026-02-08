/**
 * FeedbackKit JavaScript SDK
 *
 * A TypeScript-first SDK for integrating FeedbackKit into web applications.
 *
 * @packageDocumentation
 */

// Main client
export { FeedbackKit } from './client';

// Types
export {
  // Enums
  FeedbackStatus,
  FeedbackCategory,

  // Feedback types
  Feedback,
  CreateFeedbackRequest,
  ListFeedbackOptions,

  // Vote types
  VoteRequest,
  UnvoteRequest,
  VoteResponse,

  // Comment types
  Comment,
  CreateCommentRequest,

  // User types
  SDKUser,
  RegisterUserRequest,

  // Event types
  TrackedEvent,
  TrackEventRequest,

  // Config types
  FeedbackKitConfig,
  DEFAULT_CONFIG
} from './models/types';

// Errors
export {
  FeedbackKitError,
  AuthenticationError,
  PaymentRequiredError,
  ForbiddenError,
  NotFoundError,
  ConflictError,
  ValidationError,
  NetworkError
} from './models/errors';

// Event constants
export { SDKEvents } from './api/events';
