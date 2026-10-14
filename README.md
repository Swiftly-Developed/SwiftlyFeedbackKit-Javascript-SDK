# FeedbackKit JavaScript SDK

This README matches the source in this repository (`package.json` version **2.1.0**, not published to npm). A first integration is in [docs/getting-started.md](docs/getting-started.md).

`npm install feedbackkit-js` installs **feedbackkit-js@1.0.1** (9 February 2026). Nothing from 1.1.0 through 2.1.0 is on npm.

| | npm 1.0.1 | GitHub tags 1.1.1 and 1.2.0 | this source 2.1.0 |
|---|---|---|---|
| `feedback.list` / `create`, `votes.vote` / `unvote`, `comments`, `users.register`, `events.track`, `setUserId` | yes | yes | yes |
| `FeedbackSort`, mailing-list fields, `isHiddenOverLimit` | no | yes | yes |
| Response keys camelCased (`voteCount`) | no — the JSON is returned as sent (`vote_count`) | yes | yes |
| Anonymous `local_<uuid>`, optional `userId` on create / vote / comment | no — `userId` is required on those writes | no | yes |
| `https` only, redirects refused, 429 `Retry-After`, string event properties | no | no | yes |
| `RateLimitError`, `ServerError` | no — 429 and 5xx are `FeedbackKitError` / `SERVER_ERROR` | no | yes |
| `bearerToken` required before `isAdmin: true` | no | no | yes |
| `client.metrics` | no | no | yes |

The default base URL here is `https://api.prod.getfeedbackkit.com/api/v1`. On 1.0.1 it is `https://feedbackkit.swiftly-workspace.com/api/v1`.

JavaScript/TypeScript SDK for [FeedbackKit](https://swiftly-developed.com/feedbackkit) - In-app feedback collection.

![npm](https://img.shields.io/npm/v/feedbackkit-js)
![TypeScript](https://img.shields.io/badge/TypeScript-5.0-blue)
![License](https://img.shields.io/npm/l/feedbackkit-js)

## Features

- **TypeScript-first** - Full type definitions included
- **Zero dependencies** - Uses native fetch
- **Tree-shakeable** - Only import what you need
- **Universal** - Works in Node.js 18+ and modern browsers
- **Optional web UI** - `feedbackkit-js/ui` mounts an accessible feedback list into any page (new in 2.1.0; not on npm)

## Installation

Node.js 18+ (global `fetch`). The same build runs in modern browsers. Definitions are included. The root entry has no UMD build and no global; the only script-tag build is the optional web list, `dist/feedbackkit-ui.global.js` (see [Feedback list for the web](#feedback-list-for-the-web-feedbackkit-jsui)).

```bash
npm install feedbackkit-js
# or
yarn add feedbackkit-js
# or
pnpm add feedbackkit-js
```

That installs 1.0.1. 2.1.0 is not on npm. See the table above before copying a snippet from this file into a project that resolved the registry.

## Quick Start

```typescript
import { FeedbackKit, FeedbackCategory } from 'feedbackkit-js';

// Initialize the client
const feedbackKit = new FeedbackKit({
  apiKey: 'sf_your_api_key',
  userId: 'user_12345' // optional; omit it and the SDK keeps an anonymous id
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

## Feedback list for the web (`feedbackkit-js/ui`)

New in 2.1.0, which is not on npm. `feedbackkit-js/ui` is a separate entry point. Importing `feedbackkit-js` alone does not pull it in.

`mountFeedbackList` renders the **Showcase** list from [FEEDBACK01](../docs/specs/FEEDBACK01.md) into any element. Each card has:

- a status eyebrow
- the full title and description
- the category and comment count
- a vote capsule: tonal when you can vote, filled once you have voted, plain text on completed and rejected items

A **Sort & Filter** menu, a "Filtered by … Clear" row, and a "No Matching Requests" state complete it. It has no framework dependency and works the same in React, Vue, Svelte or plain HTML.

```typescript
import { FeedbackKit } from 'feedbackkit-js';
import { mountFeedbackList } from 'feedbackkit-js/ui';

const client = new FeedbackKit({ apiKey: 'sf_your_api_key' });
const list = mountFeedbackList(document.getElementById('feedback')!, {
  client,
  onSelect: (feedback) => router.push(`/feedback/${feedback.id}`)
});

// later
list.update({ colorScheme: 'dark' });
list.destroy();
```

Without a bundler:

```html
<div id="feedback"></div>
<script src="https://unpkg.com/feedbackkit-js/dist/feedbackkit-ui.global.js"></script>
<script>
  const { FeedbackKit, mountFeedbackList } = window.FeedbackKitUI;
  mountFeedbackList(document.getElementById('feedback'), {
    client: new FeedbackKit({ apiKey: 'sf_your_api_key' })
  });
</script>
```

| Option | Default | |
|---|---|---|
| `client` / `items` | | Load from a `FeedbackKit` client, or render host-supplied `Feedback[]`. With `items`, votes go to `onVote` |
| `listStyle` | `'showcase'` | `'classic'` renders compact rows with sort chips and coloured badges |
| `colorScheme` | `'auto'` | Follows `prefers-color-scheme`; `'light'` / `'dark'` pin it |
| `theme` | | `primaryColor`, `backgroundColor`, `cardBackgroundColor`, `textColor`, `secondaryTextColor`, `errorColor`, `statusColors`, `categoryColors`, `fontFamily`, and `dark` (colours for dark mode) |
| `locale` / `dir` / `strings` | browser locale | 11 locales are built in; `strings` overrides single keys; `dir` defaults to the locale's script direction |
| `title` / `headingLevel` | `'Feedback'` / `2` | `title: null` hides the heading; card titles are one level below |
| `sort`, `filterByStatus`, `filterByCategory` | votes | A fixed filter applies to every load and hides its menu section |
| `showSortMenu`, `showStatusFilter`, `showCategoryFilter`, `showStatusBadge`, `showCategoryBadge`, `showCommentCount`, `showVoteCount`, `allowUndoVote` | `true` | |
| `onSelect`, `onVote`, `onSortChange`, `onFilterChange`, `onError` | | Cards are only interactive when `onSelect` is set |
| `shadow` | `true` | Render into a shadow root. `false` renders into the light DOM |

**Styling.** The list renders in a shadow root, so page CSS does not leak in. Style it through `theme` or the `::part()` hooks: `card`, `vote`, `menu-button`, `menu`. It sets no inline styles, so it works under a strict Content-Security-Policy.

**Accessibility.**

- Every size is in `rem`, so browser zoom and text size up to 200% reflow without clipping or horizontal scrolling. At large sizes the vote capsule wraps under the facts.
- Hit areas are at least 48px.
- Spacing uses logical properties, so Arabic lays out right to left.
- Colours meet WCAG AA in both schemes.
- Reduced motion, increased contrast and forced colours are honoured.
- The vote control is a toggle button (`aria-pressed`) with a hint. Closed items read "N votes, Voting is closed".
- Sort & Filter is a WAI-ARIA menu button: arrow keys, Home/End, typeahead, Escape returns focus to the button.
- A polite live region announces vote failures.

Screenshots at 100%, 150% and 200% text, light and dark, are in [`docs/design/feedback01-showcase-web-2026-10/`](../docs/design/feedback01-showcase-web-2026-10/). Regenerate them with `npm run build && npm run screenshots:ui`.

## API Reference

### Configuration

```typescript
import { FeedbackKit } from 'feedbackkit-js';

const feedbackKit = new FeedbackKit({
  apiKey: 'sf_your_api_key',      // Required: Your project API key
  userId: 'user_12345',            // Optional. Omit it and a local_<uuid> is generated
  baseUrl: 'https://api.prod.getfeedbackkit.com/api/v1', // Optional. https, or http on localhost
  timeout: 30000,                  // Optional: Request timeout (ms)
  bearerToken: undefined           // Optional. Server only. Required before isAdmin: true
});
```

`baseUrl` must be `https`, except `http://localhost`, `http://127.0.0.1`, and `http://[::1]`. Any other `http://` URL throws `ValidationError`. `fetch` is called with `redirect: 'error'`. A blank `apiKey` throws `ValidationError` before a request. `bearerToken` is a server credential for admin replies. Leave it unset in an end-user app.

On 1.0.1, `http://` is accepted for any host and redirects are followed.

### Anonymous user id

Leave `userId` unset and the client generates one id in the form `local_<uuid>` (a lowercase UUID v4, the same shape Flutter stores and the same `local_` prefix Swift uses). A browser keeps it in `localStorage` under `feedbackkit_user_id`, so the next page load reuses it. In Node, and when `localStorage` throws during server rendering, the id stays in memory for that client and construction does not throw.

`setUserId('user_12345')` replaces it and stores the new value. An id you pass to the constructor does the same, and it wins over whatever was already stored. `setUserId(undefined)` clears it. The next request on this client generates a fresh `local_<uuid>` before it talks to the API. That includes `users.register`, `events.track`, and `metrics`, not only feedback, votes, and comments.

The session id is sent as `X-User-Id`. Submit, vote, unvote, and comment also send it as `user_id` when you omit `userId` on that call. A `userId` on the call is sent as the body id and does not replace the session id. When the two trim to different strings, `X-User-Id` is omitted for that call. The server rejects the mismatched pair with 400.

`users.register` and `events.track` still require `userId` on the request. They do not copy the session id into the body.

1.0.1 does not generate an id. With no `userId`, no `X-User-Id` is sent and every row comes back `hasVoted: false`. `userId` is required on create, vote, unvote, and comment.

### Feedback

```typescript
import {
  FeedbackKit,
  FeedbackCategory,
  FeedbackSort,
  FeedbackStatus
} from 'feedbackkit-js';

const feedbackKit = new FeedbackKit({ apiKey: 'sf_your_api_key' });

// List all feedback
const feedbacks = await feedbackKit.feedback.list();

// Filter by status
const pending = await feedbackKit.feedback.list({
  status: FeedbackStatus.Pending
});

// Filter by category and sort
const bugs = await feedbackKit.feedback.list({
  category: FeedbackCategory.BugReport,
  sort: FeedbackSort.Newest
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

The Free-tier cap of 10 feedback items per project does not return 402. The item is saved and the response sets `isHiddenOverLimit: true`. Later list calls omit it for everyone except the submitter whose `X-User-Id` matches that item's `userId`. `get` returns 404 for everyone else.

1.0.1 returns response JSON unchanged, so the wire key is `vote_count`. This source renames response keys to camelCase. `values` and event `properties` stay as sent. `FeedbackSort` is not in 1.0.1.

### Voting

```typescript
import { FeedbackKit } from 'feedbackkit-js';

const feedbackKit = new FeedbackKit({ apiKey: 'sf_your_api_key' });

const voted = await feedbackKit.votes.vote('feedback-id', {
  userId: 'user_12345'
});

const notified = await feedbackKit.votes.vote('feedback-id', {
  userId: 'user_12345',
  email: 'user@example.com',
  notifyStatusChange: true
});

const removed = await feedbackKit.votes.unvote('feedback-id', {
  userId: 'user_12345'
});

void voted;
void notified;
void removed;
```

`notifyStatusChange: true` is stored only when `email` is non-empty and the project owner is on the Team tier. On Free and Pro the vote still returns 200 and the preference is dropped. There is no 402. The second argument is optional here. On 1.0.1 it is required, and so is `userId`.

### Comments

```typescript
import { FeedbackKit } from 'feedbackkit-js';

const feedbackKit = new FeedbackKit({ apiKey: 'sf_your_api_key' });

const comments = await feedbackKit.comments.list('feedback-id');

const comment = await feedbackKit.comments.create('feedback-id', {
  content: 'Great idea!',
  userId: 'user_12345',
  isAdmin: false
});

void comments;
void comment;
```

`isAdmin: true` requires `bearerToken` on the client (a server credential). Without it the call throws `ValidationError` and sends nothing. 1.0.1 sends the admin flag with only the project API key.

### User Registration

```typescript
import { FeedbackKit } from 'feedbackkit-js';

const feedbackKit = new FeedbackKit({ apiKey: 'sf_your_api_key' });

const user = await feedbackKit.users.register({
  userId: 'user_12345',
  mrr: 9.99 // Monthly Recurring Revenue (optional)
});

void user;
```

`userId` here is required. The anonymous session id is not copied into this body.

### Event Tracking

```typescript
import { FeedbackKit } from 'feedbackkit-js';

const feedbackKit = new FeedbackKit({ apiKey: 'sf_your_api_key' });

await feedbackKit.events.track({
  eventName: 'feedback_list',
  userId: 'user_12345',
  properties: {
    filter: 'feature_request',
    step_count: 5 // numbers and booleans are sent as strings
  }
});
```

`userId` is required on this call. 1.0.1 forwards numbers and booleans as JSON numbers and booleans. This server stores a string map and rejects those. This source stringifies them first.

Property values must be strings, finite numbers, or booleans. The server stores them as strings. An object, array, null, or non-finite number throws `ValidationError` and no request is sent. Property **keys** are sent exactly as you write them.

### Metrics

Read aggregate analytics for the project the API key identifies. Four operations —
`summary`, `timeseries`, `breakdown` and `events` — all rate limited to **60 requests
per 60 seconds**, shared across the family. The SDK does not retry or back off.

```typescript
import { FeedbackKit, MetricMeasure, MetricGranularity, metricValue } from 'feedbackkit-js';

const feedbackKit = new FeedbackKit({ apiKey: 'sf_your_api_key' });

const series = await feedbackKit.metrics.timeseries({
  measures: [MetricMeasure.FeedbackCount, MetricMeasure.EventCount],
  granularity: MetricGranularity.Day,
  days: 7
});

for (const point of series.series) {
  console.log(point.bucket, metricValue(point.values, MetricMeasure.EventCount));
}
```

#### `values` keys are the server's tokens, and the map is sparse

Every other response key is camelCased for you. The keys **inside** a `values` map are
not: they are the server's own snake_case measure tokens, because they are data rather
than field names. `values.eventCount` is `undefined`; `values.event_count` is the number.

The map is also **sparse**. A breakdown past the cardinality ceiling collapses its tail
into one item with `isOverflow: true`, and that item **omits `unique_event_users`** — a
distinct-user count is not additive across the names that were elided, so no honest
number exists. Use `metricValue()`, which returns `number | undefined`; never assert
non-null.

```typescript
import {
  FeedbackKit,
  MetricDimension,
  MetricMeasure,
  metricValue
} from 'feedbackkit-js';

const feedbackKit = new FeedbackKit({ apiKey: 'sf_your_api_key' });

const byEvent = await feedbackKit.metrics.breakdown({
  measures: [MetricMeasure.EventCount, MetricMeasure.UniqueEventUsers],
  dimension: MetricDimension.EventName,
  days: 30
});

for (const item of byEvent.items) {
  const users = metricValue(item.values, MetricMeasure.UniqueEventUsers);
  console.log(item.key, users ?? '—'); // `—` on the overflow row, by design
}
```

#### Empty buckets are rows, not gaps

A timeseries returns every bucket in the window, zero-valued where nothing happened. So
`series.length === 0` is a branch that never fires for a valid window — check the values,
not the length.

#### A narrowed plan is a `200`, not an error

On the Free tier the metrics API answers **more narrowly** rather than refusing, and
says so in `meta`:

- `meta.eventScope === 'predefined_only'` — only FeedbackKit's own three event names
  (`SDKEvents`) were counted. Your custom events are still **ingested and retained**;
  they simply are not readable yet, and they become readable on upgrade **with no
  re-tracking**.
- `meta.retentionClamped === true` — the requested window was narrowed to the plan's
  allowance. Note this flag is **not idempotent**: re-requesting the already-narrowed
  window returns the same window with the flag `false`. Never derive it by comparing
  what you asked for against what came back.
- `meta.retentionWindowDays` — the allowance itself (Free 30, Pro 90, Team 365). **Never hardcode 30, 90, or 365.**

The one request that does fail is the exclusively-custom one — a breakdown by
`event_name`, a custom `event_name` filter, or the raw event feed — which raises a
`PaymentRequiredError` with `code === 'METRICS_CUSTOM_EVENTS_REQUIRE_PRO'`.

#### The raw event feed paginates

`metrics.events` returns **two** meta blocks: `meta` is pagination
(`total`, `page`, `perPage`, `totalPages`) and `metrics` is the window/scope block the
other three operations put under `meta`.

```typescript
import { FeedbackKit, MetricMeasure, type MetricEventList } from 'feedbackkit-js';

const feedbackKit = new FeedbackKit({ apiKey: 'sf_your_api_key' });

let page = 1;
const rows: MetricEventList['items'] = [];
for (;;) {
  const feed = await feedbackKit.metrics.events({
    measures: [MetricMeasure.EventCount],
    days: 7,
    page,
    perPage: 100 // clamped client-side to 1…200; the server returns 400 rather than clamping
  });
  rows.push(...feed.items);
  if (page >= feed.meta.totalPages) break;
  page += 1;
}
```

#### Notes

- **Windows.** `dateFrom` / `dateTo` are ISO-8601 **instants**, both bounds inclusive.
  They are mutually exclusive with `days`; sending both is a `400`.
- **Measures.** Nine exist. Five are readable with an API key; `sdk_user_count`,
  `mrr_sum`, `mrr_average` and `users_with_mrr` need a Bearer token and raise a
  `ForbiddenError` with `code === 'METRICS_MEASURE_REQUIRES_BEARER'` here.
- **Event names.** `eventName` takes a **single** free-form name. `SDKEvents` carries
  the three predefined ones (`feedback_list`, `feedback_detail`, `submit_feedback`);
  anything else you track is a custom event.

## Error Handling

The client does not retry any response. A 429 is returned as `RateLimitError` and the call stops. `retryAfterSeconds` is set when `Retry-After` was delta-seconds or an HTTP date. 1.0.1 maps 429, 422, and 5xx onto `FeedbackKitError` with code `SERVER_ERROR` and drops `Retry-After`.

```typescript
import {
  AuthenticationError,
  ConflictError,
  FeedbackKit,
  ForbiddenError,
  NotFoundError,
  PaymentRequiredError,
  RateLimitError
} from 'feedbackkit-js';

const feedbackKit = new FeedbackKit({ apiKey: 'sf_your_api_key' });

try {
  await feedbackKit.votes.vote('feedback-id', { userId: 'user_123' });
} catch (error) {
  if (error instanceof AuthenticationError) {
    // Invalid API key (401)
  } else if (error instanceof PaymentRequiredError) {
    // A subscription gate (402). The Free feedback cap is not one of these.
  } else if (error instanceof ForbiddenError) {
    // Action not allowed - archived project or voting blocked (403)
  } else if (error instanceof NotFoundError) {
    // Feedback not found (404)
  } else if (error instanceof ConflictError) {
    // Already voted (409)
  } else if (error instanceof RateLimitError) {
    console.log(error.retryAfterSeconds);
  }
}
```

The metrics API returns machine-readable codes on `error.code`. Two of them need
distinguishing by code rather than by class, because the class alone does not separate
them:

| Error | Status | `code` | Means |
|---|---|---|---|
| `PaymentRequiredError` | 402 | `METRICS_CUSTOM_EVENTS_REQUIRE_PRO` | the request is exclusively about custom events — breakdown by `event_name`, a custom `event_name` filter, or the raw feed |
| `ForbiddenError` | 403 | `METRICS_MEASURE_REQUIRES_BEARER` | a Bearer-only measure was requested on an API key |
| `ForbiddenError` | 403 | `FORBIDDEN` | the caller has no access, or the project is archived |
| `RateLimitError` | 429 | `RATE_LIMITED` | past the server rate limit. `retryAfterSeconds` is set when `Retry-After` was sent. The metrics family allows 60 requests / 60s. The SDK does not retry this or any other status. |
| `ValidationError` | 400 | `METRICS_*` | a typed parameter error; `error.code` names which |
| `ValidationError` | 422 | `UNPROCESSABLE_ENTITY` | validation failed and the body carried no machine code |
| `ServerError` | 5xx | `SERVER_ERROR` | the server failed. A server-supplied `error.code` replaces `SERVER_ERROR` |

```typescript
import {
  FeedbackKit,
  ForbiddenError,
  MetricDimension,
  MetricMeasure,
  PaymentRequiredError
} from 'feedbackkit-js';

const feedbackKit = new FeedbackKit({ apiKey: 'sf_your_api_key' });

try {
  await feedbackKit.metrics.breakdown({
    measures: [MetricMeasure.EventCount],
    dimension: MetricDimension.EventName
  });
} catch (error) {
  if (error instanceof PaymentRequiredError &&
      error.code === 'METRICS_CUSTOM_EVENTS_REQUIRE_PRO') {
    // Prompt an upgrade — the events are already being recorded.
  } else if (error instanceof ForbiddenError &&
             error.code === 'METRICS_MEASURE_REQUIRES_BEARER') {
    // Drop the MRR/SDK-user measures from the request.
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
  TrackedEvent,
  // Metrics
  MetricSummary,
  MetricSeries,
  MetricSeriesPoint,
  MetricBreakdown,
  MetricBreakdownItem,
  MetricEventList,
  MetricsMeta,
  MetricValues,
  PaginationMeta,
  MetricsQueryOptions,
  MetricsSeriesOptions,
  MetricsBreakdownOptions,
  MetricsEventsOptions
} from 'feedbackkit-js';
```

The metrics vocabularies and the measure accessor are runtime values, so they are
imported normally rather than as types:

```typescript
import {
  MetricMeasure,
  MetricGranularity,
  MetricDimension,
  MetricEventScope,
  metricValue,
  SDKEvents
} from 'feedbackkit-js';
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

## Browser and Node

Both use the same `FeedbackKit` class. Node keeps the anonymous id in memory. A browser stores it in `localStorage` when that storage works.

A browser bundle contains the project API key. The key can read and write that project's feedback, votes, comments, SDK users, and events. Status changes, deletes, merges, and admin settings need a Bearer token. `userId` is a string you assert. It is not checked against an account.

The API's CORS allowlist is FeedbackKit's own origins plus a few localhost ports. A customer origin is not on it. `fetch` from your production site fails in the browser before a status code. Call this package from Node 18+ on your server, or iframe `/embed/<apiKey>/kanban`, `/roadmap`, and `/form`.

A CDN that serves the npm package serves 1.0.1 today. There is no UMD build.

## Privacy

Data this client sends is collected on your behalf. FeedbackKit is the processor. Store-form answers: [App Store privacy](../docs/privacy/APP-STORE-PRIVACY.md) (Swift SDK), [Google Play Data safety](../docs/privacy/GOOGLE-PLAY-DATA-SAFETY.md) (Kotlin, Flutter, and React Native, which calls this package).

## Related Packages

- **Swift SDK**: [SwiftlyFeedbackKit](https://github.com/Swiftly-Developed/SwiftlyFeedbackKit)
- **React Native**: [feedbackkit-react-native](https://www.npmjs.com/package/feedbackkit-react-native)
- **Flutter**: [feedbackkit_flutter](https://pub.dev/packages/feedbackkit_flutter)
- **Kotlin**: [feedbackkit](https://central.sonatype.com/artifact/com.getfeedbackkit/feedbackkit)

## License

MIT License - see [LICENSE](LICENSE) for details.
