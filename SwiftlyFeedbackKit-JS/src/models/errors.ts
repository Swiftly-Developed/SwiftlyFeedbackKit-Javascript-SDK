/**
 * FeedbackKit Error Types
 */

/**
 * Base error class for all FeedbackKit errors
 */
export class FeedbackKitError extends Error {
  public readonly statusCode: number;
  public readonly code: string;

  constructor(message: string, statusCode: number, code: string) {
    super(message);
    this.name = 'FeedbackKitError';
    this.statusCode = statusCode;
    this.code = code;

    // Maintains proper stack trace for where our error was thrown (only available on V8)
    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, this.constructor);
    }
  }
}

/**
 * Thrown when the API key is missing or invalid (401)
 */
export class AuthenticationError extends FeedbackKitError {
  constructor(message = 'Invalid or missing API key') {
    super(message, 401, 'UNAUTHORIZED');
    this.name = 'AuthenticationError';
  }
}

/**
 * Thrown when a subscription tier limit is exceeded (402)
 */
export class PaymentRequiredError extends FeedbackKitError {
  constructor(message = 'Subscription limit exceeded. Please upgrade your plan.') {
    super(message, 402, 'PAYMENT_REQUIRED');
    this.name = 'PaymentRequiredError';
  }
}

/**
 * Thrown when an action is not allowed (403)
 * - Archived projects block write operations
 * - Voting on completed/rejected feedback is blocked
 */
export class ForbiddenError extends FeedbackKitError {
  constructor(message = 'Action not allowed') {
    super(message, 403, 'FORBIDDEN');
    this.name = 'ForbiddenError';
  }
}

/**
 * Thrown when a resource is not found (404)
 */
export class NotFoundError extends FeedbackKitError {
  constructor(message = 'Resource not found') {
    super(message, 404, 'NOT_FOUND');
    this.name = 'NotFoundError';
  }
}

/**
 * Thrown when there's a conflict, such as duplicate vote (409)
 */
export class ConflictError extends FeedbackKitError {
  constructor(message = 'Conflict: action already performed') {
    super(message, 409, 'CONFLICT');
    this.name = 'ConflictError';
  }
}

/**
 * Thrown when request validation fails (400)
 */
export class ValidationError extends FeedbackKitError {
  constructor(message = 'Validation error') {
    super(message, 400, 'BAD_REQUEST');
    this.name = 'ValidationError';
  }
}

/**
 * Thrown when a network error occurs
 */
export class NetworkError extends FeedbackKitError {
  constructor(message = 'Network error') {
    super(message, 0, 'NETWORK_ERROR');
    this.name = 'NetworkError';
  }
}

/**
 * API error response structure
 */
interface ApiErrorResponse {
  error: boolean;
  reason: string;
}

/**
 * Creates the appropriate error based on HTTP status code
 */
export function createErrorFromResponse(
  statusCode: number,
  body?: ApiErrorResponse | string
): FeedbackKitError {
  const message = typeof body === 'object' ? body.reason : body || 'Unknown error';

  switch (statusCode) {
    case 400:
      return new ValidationError(message);
    case 401:
      return new AuthenticationError(message);
    case 402:
      return new PaymentRequiredError(message);
    case 403:
      return new ForbiddenError(message);
    case 404:
      return new NotFoundError(message);
    case 409:
      return new ConflictError(message);
    default:
      return new FeedbackKitError(message, statusCode, 'SERVER_ERROR');
  }
}
