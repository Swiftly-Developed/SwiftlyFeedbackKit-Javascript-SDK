/**
 * FeedbackKit JavaScript SDK
 *
 * A TypeScript-first SDK for integrating FeedbackKit into web applications.
 *
 * @packageDocumentation
 */

// Main client
export { FeedbackKit } from './client';

// Enums (runtime values)
export { FeedbackStatus, FeedbackCategory } from './models/types';

// Config constant
export { DEFAULT_CONFIG } from './models/types';

// Types (type-only exports)
export type {
  Feedback,
  CreateFeedbackRequest,
  ListFeedbackOptions,
  VoteRequest,
  UnvoteRequest,
  VoteResponse,
  Comment,
  CreateCommentRequest,
  SDKUser,
  RegisterUserRequest,
  TrackedEvent,
  TrackEventRequest,
  FeedbackKitConfig
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
