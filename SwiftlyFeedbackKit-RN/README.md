# FeedbackKit React Native SDK

A complete React Native SDK for integrating FeedbackKit into your mobile apps. Built with TypeScript, providing ready-to-use components and hooks for collecting user feedback.

## Features

- **Ready-to-use Components**: `FeedbackList`, `FeedbackCard`, `VoteButton`, and more
- **React Hooks**: `useFeedbackList`, `useVote`, `useSubmitFeedback`, etc.
- **Theming**: Light and dark themes with full customization
- **TypeScript**: Full type safety
- **Optimistic Updates**: Instant UI feedback for voting
- **Pull-to-Refresh**: Built-in refresh support

## Installation

```bash
npm install @feedbackkit/react-native @feedbackkit/js @react-native-async-storage/async-storage
```

### Peer Dependencies

This package requires the following peer dependencies:

```json
{
  "@feedbackkit/js": "^1.0.0",
  "react": ">=18.0.0",
  "react-native": ">=0.70.0",
  "@react-native-async-storage/async-storage": ">=1.17.0"
}
```

## Quick Start

### 1. Wrap your app with the provider

```tsx
import { FeedbackKitProvider } from '@feedbackkit/react-native';

function App() {
  return (
    <FeedbackKitProvider
      apiKey="your-api-key"
      projectId="your-project-id"
    >
      <YourApp />
    </FeedbackKitProvider>
  );
}
```

### 2. Display the feedback list

```tsx
import { FeedbackList } from '@feedbackkit/react-native';

function FeedbackScreen({ navigation }) {
  return (
    <FeedbackList
      onFeedbackPress={(feedback) =>
        navigation.navigate('FeedbackDetail', { id: feedback.id })
      }
      showAddButton
      onAddPress={() => navigation.navigate('SubmitFeedback')}
    />
  );
}
```

## Components

### FeedbackList

Scrollable list of feedback items with pull-to-refresh.

```tsx
<FeedbackList
  onFeedbackPress={(feedback) => console.log(feedback)}
  filterByStatus={FeedbackStatus.Approved}
  filterByCategory={FeedbackCategory.FeatureRequest}
  showAddButton
  onAddPress={() => {}}
  emptyComponent={<CustomEmptyView />}
  ListHeaderComponent={<Header />}
/>
```

### FeedbackCard

Card component for displaying a single feedback item.

```tsx
<FeedbackCard
  feedback={feedback}
  onPress={(f) => console.log(f)}
  showStatus
  showCategory
  showVoteButton
  showCommentCount
/>
```

### VoteButton

Button for voting/unvoting on feedback.

```tsx
<VoteButton
  feedback={feedback}
  onVoteChange={(hasVoted, voteCount) => console.log(hasVoted, voteCount)}
  showCount
  size="medium" // 'small' | 'medium' | 'large'
/>
```

### StatusBadge

Displays feedback status with appropriate color.

```tsx
<StatusBadge status={FeedbackStatus.Approved} size="medium" />
```

### CategoryBadge

Displays feedback category with appropriate color.

```tsx
<CategoryBadge category={FeedbackCategory.FeatureRequest} size="medium" />
```

## Hooks

### useFeedbackList

Fetch a list of feedback items.

```tsx
const { feedbacks, isLoading, error, refetch } = useFeedbackList({
  status: FeedbackStatus.Approved,
  category: FeedbackCategory.FeatureRequest,
  limit: 20
});
```

### useFeedback

Fetch a single feedback item.

```tsx
const { feedback, isLoading, error, refetch } = useFeedback(feedbackId);
```

### useVote

Vote or unvote on feedback.

```tsx
const { vote, unvote, isVoting, error } = useVote();

// Vote
await vote(feedbackId);

// Unvote
await unvote(feedbackId);
```

### useComments

Fetch and add comments.

```tsx
const { comments, isLoading, error, addComment, isAddingComment, refetch } = useComments(feedbackId);

// Add a comment
await addComment('Great idea!');
```

### useSubmitFeedback

Submit new feedback.

```tsx
const { submitFeedback, isSubmitting, error } = useSubmitFeedback();

await submitFeedback({
  title: 'New Feature',
  description: 'Description here',
  category: FeedbackCategory.FeatureRequest
});
```

### useFeedbackKit

Access the FeedbackKit client directly.

```tsx
const client = useFeedbackKit();

// Use client methods directly
const feedbacks = await client.feedback.list();
```

## Theming

### Using built-in themes

```tsx
import { FeedbackKitProvider, darkTheme } from '@feedbackkit/react-native';

<FeedbackKitProvider
  apiKey="..."
  projectId="..."
  theme={darkTheme}
>
```

### Custom theme

```tsx
import { FeedbackKitProvider, createTheme } from '@feedbackkit/react-native';

const customTheme = createTheme({
  primaryColor: '#6366F1',
  backgroundColor: '#F8FAFC',
  // ... other overrides
});

<FeedbackKitProvider
  apiKey="..."
  projectId="..."
  theme={customTheme}
>
```

### Theme properties

| Property | Description | Default (Light) |
|----------|-------------|-----------------|
| `primaryColor` | Primary accent color | `#007AFF` |
| `backgroundColor` | Screen background | `#F2F2F7` |
| `cardBackgroundColor` | Card background | `#FFFFFF` |
| `textColor` | Primary text | `#000000` |
| `secondaryTextColor` | Secondary text | `#8E8E93` |
| `borderColor` | Border color | `#C6C6C8` |
| `successColor` | Success/completed | `#34C759` |
| `warningColor` | Warning/in progress | `#FF9500` |
| `errorColor` | Error/rejected | `#FF3B30` |
| `spacing` | Base spacing unit | `8` |
| `borderRadius` | Default border radius | `12` |

## Anonymous Users

The SDK automatically generates and persists an anonymous user ID using AsyncStorage. This ID is used for:

- Tracking votes
- Associating feedback submissions
- Managing user-specific state

The ID persists across app sessions.

## Error Handling

All hooks provide error states:

```tsx
const { feedbacks, error, isLoading } = useFeedbackList();

if (error) {
  // Handle specific error types
  if (error instanceof AuthenticationError) {
    // Invalid API key
  } else if (error instanceof PaymentRequiredError) {
    // Subscription limit reached
  }
}
```

## TypeScript

All components and hooks are fully typed. Import types from the SDK:

```tsx
import type {
  Feedback,
  FeedbackStatus,
  FeedbackCategory,
  FeedbackKitTheme,
  FeedbackListProps
} from '@feedbackkit/react-native';
```

## License

MIT
