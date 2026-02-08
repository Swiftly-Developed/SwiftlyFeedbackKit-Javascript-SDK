# FeedbackKit SDK Specifications

Shared specifications, test fixtures, and documentation for FeedbackKit SDKs.

## Contents

- **OpenAPI Specification** - Complete API documentation in OpenAPI 3.0 format
- **Test Fixtures** - Standardized test data for all SDK implementations
- **Test Scenarios** - Expected API behaviors and test cases
- **Scripts** - Validation and documentation generation tools

## Quick Start

### Validate the OpenAPI Spec

```bash
# Install dependencies
npm install -g @apidevtools/swagger-cli

# Validate
./scripts/validate-spec.sh
# or
swagger-cli validate openapi/openapi.yaml
```

### Generate Documentation

```bash
# Install dependencies
npm install -g redoc-cli

# Generate HTML docs
./scripts/generate-docs.sh
# or
redoc-cli bundle openapi/openapi.yaml -o docs/api.html
```

## Directory Structure

```
feedbackkit-sdk-specs/
├── openapi/
│   └── openapi.yaml          # OpenAPI 3.0 specification
├── fixtures/
│   ├── feedback/             # Feedback request/response fixtures
│   ├── votes/                # Vote request/response fixtures
│   ├── comments/             # Comment request/response fixtures
│   ├── users/                # User registration fixtures
│   └── events/               # Event tracking fixtures
├── scenarios/
│   ├── feedback-crud.yaml    # Feedback CRUD test scenarios
│   ├── voting-flow.yaml      # Voting flow test scenarios
│   └── error-handling.yaml   # Error handling test scenarios
├── scripts/
│   ├── validate-spec.sh      # Spec validation script
│   └── generate-docs.sh      # Documentation generation script
├── docs/
│   └── api.html              # Generated API documentation
└── .github/
    └── workflows/
        └── validate.yml      # CI/CD workflow
```

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/feedbacks` | GET | List feedback |
| `/api/v1/feedbacks` | POST | Submit feedback |
| `/api/v1/feedbacks/{id}` | GET | Get feedback by ID |
| `/api/v1/feedbacks/{id}/votes` | POST | Vote for feedback |
| `/api/v1/feedbacks/{id}/votes` | DELETE | Remove vote |
| `/api/v1/feedbacks/{id}/comments` | GET | List comments |
| `/api/v1/feedbacks/{id}/comments` | POST | Add comment |
| `/api/v1/users/register` | POST | Register SDK user |
| `/api/v1/events/track` | POST | Track event |

## Authentication

All SDK endpoints use API key authentication via the `X-API-Key` header:

```
X-API-Key: sf_your_project_api_key
```

Optionally include `X-User-Id` to get personalized `hasVoted` state:

```
X-User-Id: your_user_id
```

## Using Test Fixtures

Fixtures are organized by endpoint and contain both valid and invalid examples:

```json
// fixtures/feedback/create-feedback.json
{
  "valid": {
    "basic": { ... },
    "with_email": { ... }
  },
  "invalid": {
    "missing_title": { ... },
    "empty_description": { ... }
  }
}
```

### In JavaScript/TypeScript

```typescript
import createFeedback from './fixtures/feedback/create-feedback.json';

// Use valid fixture
const response = await sdk.submitFeedback(createFeedback.valid.basic);

// Test invalid input
expect(() => sdk.submitFeedback(createFeedback.invalid.missing_title))
  .toThrow();
```

### In Swift

```swift
let fixture = try JSONDecoder().decode(
    CreateFeedbackFixtures.self,
    from: Data(contentsOf: fixtureURL)
)
let feedback = try await sdk.submit(fixture.valid.basic)
```

## Test Scenarios

Scenarios define expected API behavior in a declarative format:

```yaml
# scenarios/feedback-crud.yaml
tests:
  - name: Create feedback successfully
    request:
      method: POST
      path: /feedbacks
      body:
        title: "Add dark mode"
        description: "Please add dark mode."
        category: "feature_request"
        userId: "user_123"
    response:
      status: 200
      body:
        status: "pending"
        voteCount: 1
```

## Versioning Strategy

All FeedbackKit SDKs follow [Semantic Versioning](https://semver.org/):

```
MAJOR.MINOR.PATCH

MAJOR: Breaking API changes
MINOR: New features (backward-compatible)
PATCH: Bug fixes
```

### Version Alignment

| Component | Version | Notes |
|-----------|---------|-------|
| Server API | v1 | Base path `/api/v1` |
| OpenAPI Spec | 1.x.x | Tracks API version |
| All SDKs | 1.x.x | Aligned with spec |

### Rules

1. **Major version tracks API version** - SDK v1.x.x works with API v1
2. **Coordinated releases** - API changes trigger spec and SDK updates
3. **Independent patches** - Bug fixes can be released per-SDK

## Related Repositories

| Repository | Description | Package |
|------------|-------------|---------|
| [SwiftlyFeedbackKit](https://github.com/Swiftly-Developed/SwiftlyFeedbackKit) | Swift SDK | SPM |
| [SwiftlyFeedbackKit-JS](https://github.com/Swiftly-Developed/SwiftlyFeedbackKit-JS) | JavaScript SDK | npm |
| [SwiftlyFeedbackKit-RN](https://github.com/Swiftly-Developed/SwiftlyFeedbackKit-RN) | React Native SDK | npm |
| [swiftly-feedback-flutter](https://github.com/Swiftly-Developed/swiftly-feedback-flutter) | Flutter SDK | pub.dev |
| [SwiftlyFeedbackKit-Kotlin](https://github.com/Swiftly-Developed/SwiftlyFeedbackKit-Kotlin) | Kotlin SDK | Maven |

## Contributing

1. Fork this repository
2. Make changes to the OpenAPI spec or fixtures
3. Run validation: `./scripts/validate-spec.sh`
4. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) for details.
