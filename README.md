# FeedbackKit JavaScript SDK

JavaScript/TypeScript SDK for [FeedbackKit](https://swiftly-developed.com/feedbackkit) - In-app feedback collection.

![npm](https://img.shields.io/npm/v/@feedbackkit/js)
![TypeScript](https://img.shields.io/badge/TypeScript-5.0-blue)
![License](https://img.shields.io/npm/l/@feedbackkit/js)

## Features

- **TypeScript-first** - Full type definitions included
- **Zero dependencies** - Uses native fetch
- **Tree-shakeable** - Only import what you need
- **Universal** - Works in Node.js 18+ and modern browsers

## Installation

```bash
npm install @feedbackkit/js
# or
yarn add @feedbackkit/js
# or
pnpm add @feedbackkit/js
```

## Quick Start

```typescript
import { FeedbackKit, FeedbackCategory } from '@feedbackkit/js';

// Initialize the client
const feedbackKit = new FeedbackKit({
  apiKey: 'sf_your_api_key',
  userId: 'user_12345' // optional, for hasVoted state
});

// List feedback
const feedbacks = await feedbackKit.feedback.list();

// Submit feedback
const newFeedback = await feedbackKit.feedback.create({
  title: 'Add dark mode',
  description: 'Please add dark mode support.',
  category: FeedbackCategory.FeatureRequest,
  userId: 'user_12345'
});

// Vote for feedback
const voteResult = await feedbackKit.votes.vote('feedback-id', {
  userId: 'user_12345'
});
```

## API Reference

### Configuration

```typescript
const feedbackKit = new FeedbackKit({
  apiKey: 'sf_your_api_key',      // Required: Your project API key
  baseUrl: 'https://...',          // Optional: Custom API URL
  userId: 'user_12345',            // Optional: Current user ID
  timeout: 30000                   // Optional: Request timeout (ms)
});
```

### Feedback

```typescript
// List all feedback
const feedbacks = await feedbackKit.feedback.list();

// Filter by status
const pending = await feedbackKit.feedback.list({
  status: FeedbackStatus.Pending
});

// Filter by category
const bugs = await feedbackKit.feedback.list({
  category: FeedbackCategory.BugReport
});

// Get single feedback
const feedback = await feedbackKit.feedback.get('feedback-id');

// Submit feedback
const newFeedback = await feedbackKit.feedback.create({
  title: 'Feature title',
  description: 'Detailed description...',
  category: FeedbackCategory.FeatureRequest,
  userId: 'user_12345',
  userEmail: 'user@example.com' // optional
});
```

### Voting

```typescript
// Vote for feedback
const result = await feedbackKit.votes.vote('feedback-id', {
  userId: 'user_12345'
});

// Vote with email notification opt-in
const result = await feedbackKit.votes.vote('feedback-id', {
  userId: 'user_12345',
  email: 'user@example.com',
  notifyStatusChange: true
});

// Remove vote
const result = await feedbackKit.votes.unvote('feedback-id', {
  userId: 'user_12345'
});
```

### Comments

```typescript
// List comments
const comments = await feedbackKit.comments.list('feedback-id');

// Add comment
const comment = await feedbackKit.comments.create('feedback-id', {
  content: 'Great idea!',
  userId: 'user_12345',
  isAdmin: false
});
```

### User Registration

```typescript
// Register/update user
const user = await feedbackKit.users.register({
  userId: 'user_12345',
  mrr: 9.99 // Monthly Recurring Revenue (optional)
});
```

### Event Tracking

```typescript
// Track custom event
await feedbackKit.events.track({
  eventName: 'feedback_list',
  userId: 'user_12345',
  properties: {
    filter: 'feature_request'
  }
});
```

## Error Handling

```typescript
import {
  FeedbackKit,
  AuthenticationError,
  PaymentRequiredError,
  ForbiddenError,
  NotFoundError,
  ConflictError
} from '@feedbackkit/js';

try {
  await feedbackKit.votes.vote('feedback-id', { userId: 'user_123' });
} catch (error) {
  if (error instanceof AuthenticationError) {
    // Invalid API key (401)
  } else if (error instanceof PaymentRequiredError) {
    // Subscription limit exceeded (402)
  } else if (error instanceof ForbiddenError) {
    // Action not allowed - archived project or voting blocked (403)
  } else if (error instanceof NotFoundError) {
    // Feedback not found (404)
  } else if (error instanceof ConflictError) {
    // Already voted (409)
  }
}
```

## Types

All types are exported for TypeScript users:

```typescript
import type {
  Feedback,
  FeedbackStatus,
  FeedbackCategory,
  Comment,
  VoteResponse,
  SDKUser,
  TrackedEvent
} from '@feedbackkit/js';
```

## Feedback Statuses

| Status | Description | Can Vote |
|--------|-------------|----------|
| `pending` | New, awaiting review | Yes |
| `approved` | Accepted for consideration | Yes |
| `in_progress` | Being worked on | Yes |
| `testflight` | Available in beta | Yes |
| `completed` | Shipped | No |
| `rejected` | Won't implement | No |

## Feedback Categories

| Category | Description |
|----------|-------------|
| `feature_request` | New functionality |
| `bug_report` | Issue or problem |
| `improvement` | Enhancement |
| `other` | General feedback |

## Related Packages

- **Swift SDK**: [SwiftlyFeedbackKit](https://github.com/Swiftly-Developed/SwiftlyFeedbackKit)
- **React Native**: Coming soon
- **Flutter**: Coming soon
- **Kotlin**: Coming soon

## License

MIT License - see [LICENSE](LICENSE) for details.
