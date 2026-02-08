import React from 'react';
import { render, waitFor } from '@testing-library/react-native';
import { Text } from 'react-native';
import { FeedbackKitProvider, useFeedbackKitContext } from '../provider';

// Test component that uses the context
function TestConsumer() {
  const { client, theme, isInitialized } = useFeedbackKitContext();
  return (
    <Text testID="status">
      {isInitialized ? 'initialized' : 'loading'}
      {client ? '-has-client' : '-no-client'}
      {theme ? '-has-theme' : '-no-theme'}
    </Text>
  );
}

describe('FeedbackKitProvider', () => {
  it('provides context to children', async () => {
    const { getByTestId } = render(
      <FeedbackKitProvider apiKey="test-key" projectId="test-project">
        <TestConsumer />
      </FeedbackKitProvider>
    );

    await waitFor(() => {
      const status = getByTestId('status');
      expect(status.props.children.join('')).toContain('initialized');
      expect(status.props.children.join('')).toContain('has-client');
      expect(status.props.children.join('')).toContain('has-theme');
    });
  });

  it('renders loading component while initializing', () => {
    const { getByTestId } = render(
      <FeedbackKitProvider
        apiKey="test-key"
        projectId="test-project"
        loadingComponent={<Text testID="loading">Loading...</Text>}
      >
        <TestConsumer />
      </FeedbackKitProvider>
    );

    // Initially should show loading
    expect(getByTestId('loading')).toBeTruthy();
  });

  it('throws error when context is used outside provider', () => {
    // Suppress console.error for this test
    const consoleSpy = jest.spyOn(console, 'error').mockImplementation();

    expect(() => {
      render(<TestConsumer />);
    }).toThrow('useFeedbackKitContext must be used within a FeedbackKitProvider');

    consoleSpy.mockRestore();
  });
});
