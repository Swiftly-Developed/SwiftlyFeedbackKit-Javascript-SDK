import React from 'react';
import { renderHook, waitFor } from '@testing-library/react-native';
import { FeedbackKitProvider } from '../provider';
import { useFeedbackList } from '../hooks/useFeedbackList';
import { useVote } from '../hooks/useVote';
import { FeedbackStatus, FeedbackCategory } from '@feedbackkit/js';

// Wrapper component for hooks
const wrapper = ({ children }: { children: React.ReactNode }) => (
  <FeedbackKitProvider apiKey="test-key" projectId="test-project">
    {children}
  </FeedbackKitProvider>
);

describe('useFeedbackList', () => {
  it('returns feedbacks array', async () => {
    const { result } = renderHook(() => useFeedbackList(), { wrapper });

    await waitFor(() => {
      expect(Array.isArray(result.current.feedbacks)).toBe(true);
    });
  });

  it('accepts filter options', async () => {
    const { result } = renderHook(
      () =>
        useFeedbackList({
          status: FeedbackStatus.Approved,
          category: FeedbackCategory.FeatureRequest,
          limit: 10,
        }),
      { wrapper }
    );

    await waitFor(() => {
      expect(result.current.isLoading).toBe(false);
    });
  });
});

describe('useVote', () => {
  it('provides vote and unvote functions', async () => {
    const { result } = renderHook(() => useVote(), { wrapper });

    await waitFor(() => {
      expect(typeof result.current.vote).toBe('function');
      expect(typeof result.current.unvote).toBe('function');
      expect(result.current.isVoting).toBe(false);
    });
  });
});
