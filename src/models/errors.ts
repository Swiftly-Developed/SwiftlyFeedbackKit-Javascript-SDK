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
  constructor(message = 'Invalid or missing API key', code = 'UNAUTHORIZED') {
    super(message, 401, code);
    this.name = 'AuthenticationError';
  }
}

/**
 * Thrown when a subscription tier limit is exceeded (402)
 */
export class PaymentRequiredError extends FeedbackKitError {
  constructor(
    message = 'Subscription limit exceeded. Please upgrade your plan.',
    code = 'PAYMENT_REQUIRED'
  ) {
    super(message, 402, code);
    this.name = 'PaymentRequiredError';
  }
}

/**
 * Thrown when an action is not allowed (403)
 * - Archived projects block write operations
 * - Voting on completed/rejected feedback is blocked
 */
export class ForbiddenError extends FeedbackKitError {
  constructor(message = 'Action not allowed', code = 'FORBIDDEN') {
    super(message, 403, code);
    this.name = 'ForbiddenError';
  }
}

/**
 * Thrown when a resource is not found (404)
 */
export class NotFoundError extends FeedbackKitError {
  constructor(message = 'Resource not found', code = 'NOT_FOUND') {
    super(message, 404, code);
    this.name = 'NotFoundError';
  }
}

/**
 * Thrown when there's a conflict, such as duplicate vote (409)
 */
export class ConflictError extends FeedbackKitError {
  constructor(message = 'Conflict: action already performed', code = 'CONFLICT') {
    super(message, 409, code);
    this.name = 'ConflictError';
  }
}

/**
 * Thrown when request validation fails (400)
 */
export class ValidationError extends FeedbackKitError {
  constructor(message = 'Validation error', code = 'BAD_REQUEST', statusCode = 400) {
    super(message, statusCode, code);
    this.name = 'ValidationError';
  }
}

/**
 * Thrown when the request was rate limited (429)
 *
 * The default message is a CLASS default, used only when the response body carries
 * no `reason`. On a real 429 the body's own reason wins, so the two strings differing
 * is correct and is not a drift to reconcile.
 */
export class RateLimitError extends FeedbackKitError {
  /** Seconds to wait, taken from the `Retry-After` header when the server sent one. */
  public readonly retryAfterSeconds?: number;

  constructor(
    message = 'Rate limit exceeded',
    code = 'RATE_LIMITED',
    retryAfterSeconds?: number
  ) {
    super(message, 429, code);
    this.name = 'RateLimitError';
    this.retryAfterSeconds = retryAfterSeconds;
  }
}

/**
 * Thrown when the server fails (HTTP 5xx).
 *
 * Distinct from the base class so a validation failure and an outage are not the
 * same object. `instanceof FeedbackKitError` still holds.
 */
export class ServerError extends FeedbackKitError {
  constructor(message = 'Server error', statusCode = 500, code = 'SERVER_ERROR') {
    super(message, statusCode, code);
    this.name = 'ServerError';
  }
}

/**
 * Thrown when a network error occurs
 */
export class NetworkError extends FeedbackKitError {
  constructor(message = 'Network error', code = 'NETWORK_ERROR') {
    super(message, 0, code);
    this.name = 'NetworkError';
  }
}

/**
 * Shape A — the typed API envelope. `error` is an OBJECT carrying a machine-readable
 * code, an optional human message, and optionally the wire spelling of the parameter
 * at fault.
 */
export interface ApiErrorEnvelope {
  error: { code: string; message?: string; field?: string };
  timestamp?: string;
}

/**
 * Shape B — the shared middleware body (Vapor's `ErrorMiddleware.default` and the
 * rate limiter). `error` is a BOOLEAN, always `true`, and there is no code at all.
 */
export interface ApiErrorReason {
  error: boolean;
  reason: string;
}

/** Either error body the API can return. */
export type ApiErrorBody = ApiErrorEnvelope | ApiErrorReason;

/**
 * Branch on the JSON TYPE of `error`, never on the status code: 403 arrives in both
 * shapes — the role-denial 403 is shape B with no code, while a measure rejection is
 * shape A carrying one — and only the body distinguishes them.
 */
function isEnvelope(body: unknown): body is ApiErrorEnvelope {
  return (
    typeof body === 'object' &&
    body !== null &&
    typeof (body as ApiErrorEnvelope).error === 'object' &&
    (body as ApiErrorEnvelope).error !== null
  );
}

/**
 * Creates the appropriate error based on HTTP status code
 *
 * `message` and `code` are resolved from the body first; the status then selects the
 * class. A shape-A body overrides the class-default code with the server's token; a
 * shape-B body leaves the class default in place, byte-for-byte as shipped.
 */
export function createErrorFromResponse(
  statusCode: number,
  body?: ApiErrorBody | string,
  retryAfterSeconds?: number
): FeedbackKitError {
  let message: string | undefined;
  let code: string | undefined;

  if (isEnvelope(body)) {
    message = body.error.message;
    code = body.error.code;
  } else if (typeof body === 'object' && body !== null) {
    message = (body as ApiErrorReason).reason;
  } else {
    message = body || 'Unknown error';
  }

  switch (statusCode) {
    case 400:
      return new ValidationError(message, code);
    case 401:
      return new AuthenticationError(message, code);
    case 402:
      return new PaymentRequiredError(message, code);
    case 403:
      return new ForbiddenError(message, code);
    case 404:
      return new NotFoundError(message, code);
    case 409:
      return new ConflictError(message, code);
    case 422:
      return new ValidationError(message, code ?? 'UNPROCESSABLE_ENTITY', 422);
    case 429:
      return new RateLimitError(message, code, retryAfterSeconds);
    default:
      if (statusCode >= 500 && statusCode <= 599) {
        return new ServerError(
          message ?? 'Unknown error',
          statusCode,
          code ?? 'SERVER_ERROR'
        );
      }
      return new FeedbackKitError(
        message ?? 'Unknown error',
        statusCode,
        code ?? 'SERVER_ERROR'
      );
  }
}
