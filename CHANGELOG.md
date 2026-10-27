# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

1.2.0 and 2.1.0 are git tags on the public mirror (SwiftlyFeedbackKit-Javascript-SDK) and are not published to npm.
`npm install feedbackkit-js` still resolves to 1.0.1 (9 February 2026).

## [Unreleased]

## [2.2.0] - 2026-10-27

All FeedbackKit SDKs (Swift, JS, React Native, Kotlin, Flutter) now share one version number. The Vapor SDK keeps its own versioning.

### Changed

- The contact addresses in the repository docs are now getfeedbackkit.com aliases: security@ in `SECURITY.md`, support@ in `SUPPORT.md`, hello@ in `CODE_OF_CONDUCT.md` and developers@ in `CONTRIBUTING.md`.
- The package `author` email in `package.json` is now developers@getfeedbackkit.com.

## [2.1.0] - 2026-10-14

### Added

- **`feedbackkit-js/ui`: an opt-in feedback list for the web** ([FEEDBACK01](../docs/specs/FEEDBACK01.md)).
  `mountFeedbackList(element, { client })` renders the Showcase card list:
  - a status eyebrow whose glyph shape encodes the status
  - the full title and description
  - the category and comment count
  - a tonal vote capsule that is filled once voted and plain text on closed items
  - a Sort & Filter menu
  - a "Filtered by … Clear" row, and "No Matching Requests" when a filter has no results

  `listStyle: 'classic'` renders a compact row list instead.

  The embed has no framework dependency. It renders in a shadow root by default and exposes the `card`, `vote`, `menu-button` and `menu` parts. It sets no inline styles, so a strict CSP works. Text and spacing are sized in `rem`, so browser zoom and text size up to 200% reflow without clipping. It follows `prefers-color-scheme` (or `colorScheme: 'light' | 'dark'`), and it honours reduced motion, increased contrast and forced colours. It lays out right to left for Arabic. Keyboard and screen-reader support: a WAI-ARIA menu button with arrow keys, Home/End and typeahead; the vote button is a toggle (`aria-pressed`); a live region announces failures. Copy ships in 11 locales and can be overridden per key. Votes are optimistic and roll back on error.
- `dist/feedbackkit-ui.global.js` exposes `window.FeedbackKitUI` (client plus embed) for a plain `<script>` tag, and is also the `unpkg` / `jsdelivr` entry.
- The root `feedbackkit-js` entry is unchanged, and does not load the UI.

Also first shipped in 2.1.0 (drafted earlier under the untagged 1.2.0, 1.2.1 and 1.2.2 headings):

> ⚠️ **Release precondition for the metrics API.** The metrics endpoints are **not yet deployed to
> every environment**. Measured 2026-10-14: the development and testflight APIs serve
> `/api/v1/metrics/summary` (`401` without a key); the **production API answers `404`** to it while
> its `/api/v1/feedbacks` answers `401`, so the route is genuinely absent rather than the service
> being down. Until that deploy lands, a metrics call against production fails. Every other change
> in this release is unaffected.

#### Added

- **Metrics API — `client.metrics`.** Four operations against the API-key metrics
  family: `summary`, `timeseries`, `breakdown` and `events`. All four are rate limited
  by the server to 60 requests per 60 seconds; the SDK does not retry or back off.
- Typed vocabularies for the metrics wire tokens: `MetricMeasure` (9 measures),
  `MetricGranularity` (`hour`, `day`, `week`, `month`), `MetricDimension` and
  `MetricEventScope`. Exported as runtime values with matching union types.
- `metricValue(values, measure)` — an optional-returning accessor for a measure map.
  It returns `number | undefined` because the map is **sparse**: a breakdown's overflow
  item omits `unique_event_users`, deliberately, since a distinct-user count is not
  additive across the names the cardinality ceiling elided.
- Response and option types: `MetricSummary`, `MetricSeries`, `MetricSeriesPoint`,
  `MetricBreakdown`, `MetricBreakdownItem`, `MetricEventList`, `MetricsMeta`,
  `MetricValues`, `PaginationMeta`, and the four `Metrics*Options` interfaces.
- `RateLimitError` — a typed error for HTTP 429, exported from the package root.

#### Changed

- Documented metrics windows are Free 30 days, Pro 90 days and Team 365 days. The client still reads `retentionWindowDays` from the response and does not hardcode them.
- Query parameters may now be numbers as well as strings and booleans
  (`QueryParamValue` in `utils/http`). A widening; no existing call changes.
- **`TrackedEvent.createdAt` is now optional.** The field is optional on the server's
  `ViewEventResponseDTO` and the raw event feed really does return rows without it, so
  declaring it required was a promise the wire does not keep. Type-level only — no
  runtime behaviour changes — but code that read `event.createdAt` as a `string` will
  now need to handle `undefined`.
- The `src/models/types.ts` header no longer claims the file is generated from an
  OpenAPI specification. No generator is configured in this package; the file is
  hand-maintained, and the stale claim told contributors their edits would be
  overwritten.

#### Fixed

- **Anonymous users now have a persistent id.** 1.0.0 promised this, and a submit
  with no `user_id` is a 400. When `userId` is omitted, the client generates
  `local_<uuid>` (`crypto.randomUUID`, or a UUID v4 built from
  `crypto.getRandomValues` / `Math.random` when that is missing), stores it in
  `localStorage` under `feedbackkit_user_id` when storage is available, and
  otherwise keeps it in memory. Node and SSR do not throw when `localStorage`
  is missing or throws. An id passed to the constructor or to `setUserId`
  replaces the generated one and is what gets stored. `feedback.list`,
  `feedback.create`, `votes.vote`, `votes.unvote`, and `comments.list` /
  `comments.create` use that id. A `userId` on a single write still wins for
  that call. `userId` on create, vote, unvote, and comment requests is optional.
- **429 bodies without a JSON content type.** The rate limiter returns
  `{"error":true,"reason":"Too many requests. Try again later."}` and a
  `Retry-After` header, and it sets no content type. The client treated that body
  as plain text, so the error message was the raw JSON and the wait was
  dropped. The reason is now the message, and `RateLimitError.retryAfterSeconds`
  is set from `Retry-After` (delta-seconds or an HTTP-date). Affected:
  published `feedbackkit-js@1.0.1` and the `1.2.0` tag.
- A 429 response produced a generic `FeedbackKitError` with code `SERVER_ERROR`,
  indistinguishable from 422 and 5xx. It now produces `RateLimitError` with code
  `RATE_LIMITED`.
- **Event properties are sent as strings.** The server stores `properties` as
  `[String: String]`. Numbers and booleans were forwarded as JSON numbers and
  booleans, which the server rejects. They are stringified before the request.
  Objects, arrays, null, and non-finite numbers throw `ValidationError` and
  nothing is sent. Affected: `feedbackkit-js@1.0.1` and the `1.2.0` tag.
- **`events.track` properties are now sent and returned verbatim.** The keys inside a
  view event's `properties` object were being case-converted in both directions: the
  SDK snake_cased them on the way out and camelCased them on the way back. The two
  conversions cancelled for a camelCase key, so `{ planTier: 'pro' }` appeared to
  round-trip while the server stored `plan_tier` — and a key the caller deliberately
  wrote in snake_case, such as `step_count`, came back as `stepCount`, a key it never
  sent. `properties` is customer-supplied data, not SDK field names, so it now crosses
  the wire untouched in both directions. A host app that typed a camelCase property key
  now sees that key stored and returned; a host app that typed a snake_case key finally
  gets that key back.
- **The API key stays on https, and redirects are not followed.** A non-loopback
  `http://` base URL is rejected. `http` is still accepted for `localhost`,
  `127.0.0.1`, and `::1`. `fetch` is called with `redirect: 'error'` so a 3xx
  cannot carry `X-API-Key` to another origin. Affected: `feedbackkit-js@1.0.1`
  and the `1.2.0` tag.
- **422 and 5xx have their own classes.** 422 is `ValidationError` with status
  422 and code `UNPROCESSABLE_ENTITY` (or the server's code when the body has
  one). 5xx is `ServerError` with code `SERVER_ERROR`. A missing `apiKey`, and
  an admin reply without `bearerToken`, throw `ValidationError` instead of a
  bare `Error`. Affected: `feedbackkit-js@1.0.1` and the `1.2.0` tag.
- The API's typed error bodies were being discarded. When the server returns an error
  envelope carrying a machine-readable `code` and a specific message, the SDK ignored
  both and surfaced its own generic class default — so, for example, a 403 raised
  because the requested data needs a different auth surface was indistinguishable from
  a 403 raised because the caller has no access to the project. `createErrorFromResponse`
  now branches on the body shape, reads `error.code` into `FeedbackKitError.code`, and
  uses the server's message. Bodies in the older `{ error: true, reason }` shape are
  unchanged, down to the exact code literal per status.
- **Admin replies require a server-side bearer token.** `comments.create` with
  `isAdmin: true` used to send `is_admin: true` authenticated only by the project
  API key, so any end-user app could mark its own reply as an admin response.
  Pass `bearerToken` (a server credential, not a value you ship in an end-user
  app) when constructing the client. Without it, the call throws before the
  request is sent. End-user comments still send `is_admin: false` with the API key.
- **A comment body user id no longer fights `X-User-Id`.** When `setUserId` (or
  the config user id) and `comments.create({ userId })` trim to different ids,
  the client omits the header. The server rejects that pair with 400. Matching
  ids, and reads such as `feedback.list`, still send the header. Affected:
  `feedbackkit-js@1.0.1` and the `1.2.0` tag.
- **`feedback.create` no longer documents a 402 for the Free-tier cap.** The
  write succeeds and the item comes back with `isHiddenOverLimit: true`. The
  published JSDoc on `FeedbackKit` imported `@feedbackkit/js`; the package name
  is `feedbackkit-js`.
- A measure map (`values`) in an analytics response was having its keys camelCased.
  Those keys are the server's own measure tokens and are now left verbatim.

## [1.2.0] - 2026-10-14

### Added

- Cross-SDK parity tests against server-generated wire corpora (feedback, comments, votes, events, SDK users, requests) and a status/category decoding suite.

### Fixed

- `feedback.list({ includeMerged: true })` was silently ignored. Query parameter
  keys were converted to snake_case before being appended to the URL, so the SDK
  sent `include_merged`, which the API does not read — every call behaved as
  `includeMerged: false`. Query keys are now sent verbatim; JSON request bodies
  are still snake_cased, which is unchanged and correct.

## [1.1.1] - 2026-04-24

### Changed

- Version alignment with Swift SDK 1.1.1 hotfix (Xcode 26 / Swift 6.2 compatibility). No functional changes to this SDK.

## [1.1.0] - 2026-04-15

### Added

- CHANGELOG.md following Keep a Changelog format
- CONTRIBUTING.md with contribution guidelines
- SECURITY.md with vulnerability reporting policy
- CODE_OF_CONDUCT.md (Contributor Covenant v2.1)
- SUPPORT.md with support channels

### Changed

- Migrated API URLs to getfeedbackkit.com
- Updated SDK availability section in README (Flutter and Kotlin now available)
- Standardized LICENSE copyright year to 2025
- Standardized documentation across all FeedbackKit SDKs

## [1.0.1] - 2026-02-09

### Changed

- Renamed scoped package to unscoped `feedbackkit-js` for npm publishing
- Updated production URLs

## [1.0.0] - 2026-02-08

### Added

- Initial release of FeedbackKit JavaScript SDK
- TypeScript-first with full type definitions
- Zero runtime dependencies
- Tree-shakeable ESM and CJS builds
- **Core Features**
  - Feedback: list, get, submit with sorting and filtering
  - Voting: vote and unvote
  - Comments: list and create
  - User management with persistent anonymous IDs
  - Event tracking
- Typed error handling with FeedbackKitError
- Node.js 18+ and modern browser support

[2.1.0]: https://github.com/Swiftly-Developed/SwiftlyFeedbackKit-Javascript-SDK/releases/tag/2.1.0
[1.2.0]: https://github.com/Swiftly-Developed/SwiftlyFeedbackKit-Javascript-SDK/releases/tag/1.2.0
[1.1.1]: https://github.com/Swiftly-Developed/SwiftlyFeedbackKit-Javascript-SDK/releases/tag/1.1.1
[1.1.0]: https://github.com/Swiftly-Developed/SwiftlyFeedbackKit-Javascript-SDK/releases/tag/1.1.0
[1.0.1]: https://github.com/Swiftly-Developed/SwiftlyFeedbackKit-Javascript-SDK/releases/tag/1.0.1
[1.0.0]: https://github.com/Swiftly-Developed/SwiftlyFeedbackKit-Javascript-SDK/releases/tag/1.0.0
