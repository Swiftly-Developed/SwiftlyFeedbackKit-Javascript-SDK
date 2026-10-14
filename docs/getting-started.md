# Getting started with feedbackkit-js

This guide matches the source in this repository (`package.json` version **2.1.0**). It is a typed API client for web and Node apps. It does not render UI.

`npm install feedbackkit-js` still installs **1.0.1** (published 9 February 2026). Nothing from 1.1.0 through 2.1.0 is on npm. Snippets below are written for 2.1.0. Where 1.0.1 disagrees, the section says so.

Tags `1.1.1` and `1.2.0` on [SwiftlyFeedbackKit-Javascript-SDK](https://github.com/Swiftly-Developed/SwiftlyFeedbackKit-Javascript-SDK) have no metrics API, no `RateLimitError`, no `ServerError`, no anonymous ids, and no https-only client. Do not treat either tag as 2.1.0.

## Install

The package name is `feedbackkit-js`. It has no runtime dependencies. Node.js 18 or newer is required because the client uses global `fetch`. Browsers need the same `fetch` support. TypeScript definitions ship in the package. There is no separate `@types` package, and there is no UMD or IIFE build and no `window.FeedbackKit` global.

```bash
npm install feedbackkit-js
```

Yarn and pnpm use the same package name: `yarn add feedbackkit-js`, `pnpm add feedbackkit-js`.

That command installs 1.0.1. 2.1.0 is not on npm. It exists only as tag `2.1.0` on GitHub, and that tag does not commit `dist/` and has no `prepare` script, so a git dependency on it has to be built before it can be imported.

## Create a client

```typescript
import { FeedbackKit, FeedbackCategory } from 'feedbackkit-js';

const client = new FeedbackKit({
  apiKey: 'sf_your_api_key',
  userId: 'user_12345'
});

const items = await client.feedback.list();

const created = await client.feedback.create({
  title: 'Add dark mode',
  description: 'Please add dark mode support.',
  category: FeedbackCategory.FeatureRequest,
  userId: 'user_12345'
});

void items;
void created;
```

`apiKey` is required. A missing or blank key throws `ValidationError` before any request. `timeout` defaults to 30000 milliseconds.

`baseUrl` defaults to `https://api.prod.getfeedbackkit.com/api/v1`. It must be `https`, except `http://localhost`, `http://127.0.0.1`, and `http://[::1]`. Any other `http://` URL throws `ValidationError`. The client calls `fetch` with `redirect: 'error'`, so a 3xx does not carry `X-API-Key` to another origin.

On **1.0.1** the default base URL is `https://feedbackkit.swiftly-workspace.com/api/v1`, `http://` is accepted for any host, and redirects are followed.

## User id and anonymous ids

Pass `userId` when you know who the person is. The client sends it as `X-User-Id`. The server uses that header for `hasVoted`, and to decide whether the caller may see their own over-limit feedback.

Omit `userId` and 2.1.0 generates `local_<uuid>` (lowercase UUID v4). A browser stores it in `localStorage` under `feedbackkit_user_id`. In Node, during server rendering, and when `localStorage` throws, the id stays in memory for that client. Construction does not throw.

```typescript
import { FeedbackKit } from 'feedbackkit-js';

const client = new FeedbackKit({ apiKey: 'sf_your_api_key' });

const anonymousId = client.getUserId();

client.setUserId('user_12345');
client.setUserId(undefined);

void anonymousId;
```

`getUserId()` returns the explicit id, or the generated one. It is `undefined` only after `setUserId(undefined)`, until the next request. Any later call through the client (`feedback`, `votes`, `comments`, `users`, `events`, or `metrics`) generates a fresh `local_<uuid>` first.

`feedback.create`, `votes.vote`, `votes.unvote`, and `comments.create` copy that session id into `user_id` when you omit `userId` on the call. A `userId` on the call is sent as the body id and does not replace the session id. When the two trim to different strings, the client omits `X-User-Id` for that call, because the server rejects the pair with 400.

`users.register` and `events.track` still require their own `userId`. They do not borrow the session id for the body.

On **1.0.1** there is no generated id. Omitting `userId` sends no `X-User-Id`, `hasVoted` is false on every row, and `userId` is required on create, vote, unvote, and comment types. `setUserId(undefined)` clears the header and leaves it clear.

## List and submit feedback

```typescript
import {
  FeedbackKit,
  FeedbackCategory,
  FeedbackSort,
  FeedbackStatus
} from 'feedbackkit-js';

const client = new FeedbackKit({
  apiKey: 'sf_your_api_key',
  userId: 'user_12345'
});

const pending = await client.feedback.list({
  status: FeedbackStatus.Pending,
  sort: FeedbackSort.Newest
});

const bugs = await client.feedback.list({
  category: FeedbackCategory.BugReport
});

const one = await client.feedback.get(pending[0]?.id ?? 'feedback-id');

const created = await client.feedback.create({
  title: 'Add dark mode',
  description: 'Please add a dark mode option.',
  category: FeedbackCategory.FeatureRequest,
  userEmail: 'user@example.com'
});

void bugs;
void one;
void created;
```

`sort` accepts `FeedbackSort.Votes` (the default), `Newest`, `Oldest`, and `Comments`. `includeMerged: true` is sent as the query key `includeMerged`.

The creator's own vote is counted, so a new item comes back with `voteCount` 1.

On the Free tier the 10-item cap does not return 402. The write succeeds and the item has `isHiddenOverLimit: true`. Later list and get calls hide it from everyone except the submitter whose `X-User-Id` matches `userId`. Other callers get it omitted from the list, and get returns 404.

On **1.0.1** there is no `FeedbackSort`, no `sort` field, and no `isHiddenOverLimit` on the type. `includeMerged` is also sent under a different query spelling in builds before the 1.2.0 query-key fix, so the flag was ignored. 1.0.1 returns the JSON body unchanged. This server encodes `vote_count`. Code that reads `voteCount` needs 1.1.0 or later, which renames response keys to camelCase. `values` and event `properties` are left as the server sent them.

`subscribeToMailingList` and `mailingListEmailTypes` exist on create in 2.1.0. They are absent from 1.0.1.

## Votes

```typescript
import { FeedbackKit } from 'feedbackkit-js';

const client = new FeedbackKit({
  apiKey: 'sf_your_api_key',
  userId: 'user_12345'
});

const voted = await client.votes.vote('feedback-id', {
  email: 'user@example.com',
  notifyStatusChange: true
});

const cleared = await client.votes.unvote('feedback-id');

void voted;
void cleared;
```

`notifyStatusChange: true` asks for an email when the status changes. The server stores that only when `email` is non-empty and the project owner is on the Team tier. Below Team the vote still succeeds and the preference is dropped. There is no 402.

Voting is forbidden on `completed` and `rejected` items and on an archived project (`ForbiddenError`, 403). A second vote is `ConflictError` (409).

The second argument is optional in 2.1.0. On **1.0.1** it is required, and `userId` inside it is required. `notifyStatusChange` and `email` exist in 1.0.1.

## Comments

```typescript
import { FeedbackKit } from 'feedbackkit-js';

const client = new FeedbackKit({ apiKey: 'sf_your_api_key' });

const comments = await client.comments.list('feedback-id');

const comment = await client.comments.create('feedback-id', {
  content: 'Great idea!'
});

void comments;
void comment;
```

An admin reply needs a server credential. Do not put `bearerToken` in a browser bundle.

```typescript
import { FeedbackKit } from 'feedbackkit-js';

const server = new FeedbackKit({
  apiKey: 'sf_your_api_key',
  bearerToken: 'server-bearer-token'
});

const adminComment = await server.comments.create('feedback-id', {
  content: 'Thanks. We are working on this.',
  userId: 'admin_user',
  isAdmin: true
});

void adminComment;
```

Without `bearerToken`, `isAdmin: true` throws `ValidationError` and sends nothing. On **1.0.1** the same call sends `is_admin` with only the project API key.

## Events

```typescript
import { FeedbackKit, SDKEvents } from 'feedbackkit-js';

const client = new FeedbackKit({ apiKey: 'sf_your_api_key' });

const tracked = await client.events.track({
  eventName: SDKEvents.FeedbackList,
  userId: 'user_12345',
  properties: {
    filter: 'feature_request',
    step_count: 5,
    completed: true
  }
});

void tracked;
```

`userId` on `events.track` is required. The session id is not copied into the body.

`SDKEvents` is `feedback_list`, `feedback_detail`, and `submit_feedback`. Any other name is a custom event.

Property values must be strings, finite numbers, or booleans. Numbers and booleans are sent as strings, because the server stores a string map. An object, array, `null`, or non-finite number throws `ValidationError` and no request is sent. Keys are sent exactly as you write them.

On **1.0.1** numbers and booleans are sent as JSON numbers and booleans, which this server rejects. `TrackedEvent.createdAt` is required on 1.0.1 and optional on 2.1.0.

## Errors and 429

```typescript
import {
  AuthenticationError,
  ConflictError,
  FeedbackKit,
  ForbiddenError,
  NetworkError,
  NotFoundError,
  PaymentRequiredError,
  RateLimitError,
  ServerError,
  ValidationError
} from 'feedbackkit-js';

const client = new FeedbackKit({ apiKey: 'sf_your_api_key' });

try {
  await client.votes.vote('feedback-id');
} catch (error) {
  if (error instanceof RateLimitError) {
    console.log(error.retryAfterSeconds);
  } else if (error instanceof ValidationError) {
    console.log(error.statusCode, error.code);
  } else if (error instanceof ServerError) {
    console.log(error.statusCode);
  } else if (
    error instanceof AuthenticationError ||
    error instanceof PaymentRequiredError ||
    error instanceof ForbiddenError ||
    error instanceof NotFoundError ||
    error instanceof ConflictError ||
    error instanceof NetworkError
  ) {
    console.log(error.statusCode, error.code);
  }
}
```

| Class | Status | When |
|---|---|---|
| `ValidationError` | 400, or 422 | Bad input. 422 uses code `UNPROCESSABLE_ENTITY` unless the body has its own code. A missing `apiKey` throws this before the request. |
| `AuthenticationError` | 401 | Unknown API key. |
| `PaymentRequiredError` | 402 | A subscription gate that has no narrower answer. The Free feedback cap is not one of these. |
| `ForbiddenError` | 403 | Archived project, voting blocked, or a Bearer-only metrics measure (`METRICS_MEASURE_REQUIRES_BEARER`). |
| `NotFoundError` | 404 | Missing feedback, including hidden-over-limit feedback read by someone else. |
| `ConflictError` | 409 | Already voted. |
| `RateLimitError` | 429 | `retryAfterSeconds` is set when `Retry-After` was a delta-seconds value or an HTTP date. |
| `ServerError` | 5xx | Code `SERVER_ERROR`, or the server's code when the body has one. |
| `NetworkError` | 0 | Timeout, DNS, or a redirect the client refused. |

The client does not retry and does not sleep on 429. You read `retryAfterSeconds` and decide.

On **1.0.1** a 429, a 422, and a 5xx are all the base `FeedbackKitError` with code `SERVER_ERROR`. `RateLimitError` and `ServerError` do not exist. A 429 body without a JSON content type is left as raw text, and `Retry-After` is ignored.

## Browser and Node

The same class runs in both places.

In a browser the project API key is in the bundle. It identifies a project. It can list and create feedback, vote, comment, register SDK users, and track events. It cannot change status, delete, merge, or read admin settings. Those routes want a Bearer token. `userId` is whatever string you send. It is not proof of identity. A `userEmail` stored on an item comes back to anyone who holds the key.

Browser calls also have to pass CORS. The API allowlist is FeedbackKit's own origins plus a few localhost ports. A customer origin is not on it, and there is no project setting that adds one. A `fetch` from your production site fails in the browser before you see a status. Call the SDK from your own server (Node 18+), or iframe the hosted pages at `/embed/<apiKey>/kanban`, `/embed/<apiKey>/roadmap`, and `/embed/<apiKey>/form`.

A module script can load ESM from a CDN that serves the npm package (`import { FeedbackKit } from 'https://esm.sh/feedbackkit-js'`). That CDN serves whatever version is published, which today is 1.0.1. FeedbackKit does not host that bundle.

In Node there is no `localStorage`, so the anonymous id is per process. Keep one `FeedbackKit` instance if you want that id to stay stable. `bearerToken` belongs here, not in the browser.

## Plan limits the client can hit

| Limit | What the client sees |
|---|---|
| Free: 10 feedback items per project | The create call returns 2xx and `isHiddenOverLimit: true`. Reads hide the row from everyone except that submitter. |
| Voter status emails | Team only. `notifyStatusChange: true` with an email is stored on Team. On Free and Pro the vote succeeds and the flag is not stored. |
| Metrics window | Free 30 days, Pro 90, Team 365. A wider request returns 200 with `meta.retentionClamped`. Read `meta.retentionWindowDays` from the response. |
| Custom event names in metrics | Below Pro the events are stored, and a metrics read returns `meta.eventScope === 'predefined_only'`. Breakdown by `event_name`, a custom `event_name` filter, and the raw event feed return 402 `METRICS_CUSTOM_EVENTS_REQUIRE_PRO`. |
| Metrics rate limit | 60 requests per 60 seconds for `summary`, `timeseries`, `breakdown`, and `events` together. 429, no SDK retry. |
| Bearer-only measures | `sdk_user_count`, `mrr_sum`, `mrr_average`, and `users_with_mrr` return 403 `METRICS_MEASURE_REQUIRES_BEARER` on an API key. |

`client.metrics` first ships in 2.1.0. It is not in npm 1.0.1 or in tags 1.1.1 and 1.2.0. The metrics routes themselves are not deployed to every API environment: on 14 October 2026 the production API answered 404 for `/api/v1/metrics/summary`, and the dev and testflight APIs answered 401 (the route exists). See the metrics section of [the README](../README.md) for `metricValue`, sparse `values` keys, and the event feed's two meta blocks.

## What to read next

Method-by-method detail is in [the README](../README.md). The website copy of this surface is `/docs/javascript`. The narrative build guide is the blog post "How to Add a Feedback Widget to a JavaScript Web App".
