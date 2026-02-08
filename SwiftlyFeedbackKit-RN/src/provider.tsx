/**
 * FeedbackKit Provider
 *
 * Provides FeedbackKit context to the component tree.
 */

import React, { createContext, useContext, useMemo, useEffect, useState } from 'react';
import { FeedbackKit, FeedbackKitConfig } from '@feedbackkit/js';
import { Theme, defaultTheme, mergeTheme } from './styles/theme';
import { getUserId, setUserId as persistUserId } from './utils/storage';

/**
 * Theme configuration for FeedbackKit components
 */
export interface FeedbackKitTheme extends Partial<Theme> {}

/**
 * FeedbackProvider props
 */
export interface FeedbackProviderProps {
  /** Project API key (required) */
  apiKey: string;
  /** Base URL of the FeedbackKit API (optional) */
  baseUrl?: string;
  /** Current user ID (optional, will be persisted) */
  userId?: string;
  /** Theme customization */
  theme?: FeedbackKitTheme;
  /** Children components */
  children: React.ReactNode;
}

/**
 * Context value
 */
export interface FeedbackKitContextValue {
  /** FeedbackKit client instance */
  client: FeedbackKit;
  /** Current user ID */
  userId: string | undefined;
  /** Update the current user ID */
  setUserId: (userId: string | undefined) => void;
  /** Current theme */
  theme: Theme;
  /** Whether the provider is initialized */
  isInitialized: boolean;
}

const FeedbackKitContext = createContext<FeedbackKitContextValue | null>(null);

/**
 * FeedbackKit Provider Component
 *
 * Wrap your app with this provider to enable FeedbackKit hooks and components.
 *
 * @example
 * ```tsx
 * import { FeedbackProvider } from '@feedbackkit/react-native';
 *
 * export default function App() {
 *   return (
 *     <FeedbackProvider
 *       apiKey="sf_your_api_key"
 *       userId={user?.id}
 *       theme={{ primaryColor: '#007AFF' }}
 *     >
 *       <NavigationContainer>
 *         <AppNavigator />
 *       </NavigationContainer>
 *     </FeedbackProvider>
 *   );
 * }
 * ```
 */
export function FeedbackProvider({
  apiKey,
  baseUrl,
  userId: initialUserId,
  theme: themeOverrides,
  children
}: FeedbackProviderProps) {
  const [userId, setUserIdState] = useState<string | undefined>(initialUserId);
  const [isInitialized, setIsInitialized] = useState(false);

  // Create client instance
  const client = useMemo(() => {
    return new FeedbackKit({
      apiKey,
      baseUrl,
      userId
    });
  }, [apiKey, baseUrl]);

  // Merge theme
  const theme = useMemo(() => {
    return mergeTheme(defaultTheme, themeOverrides);
  }, [themeOverrides]);

  // Load persisted user ID on mount
  useEffect(() => {
    async function loadUserId() {
      if (!initialUserId) {
        const persistedUserId = await getUserId();
        if (persistedUserId) {
          setUserIdState(persistedUserId);
          client.setUserId(persistedUserId);
        }
      }
      setIsInitialized(true);
    }
    loadUserId();
  }, []);

  // Update client when userId changes
  useEffect(() => {
    client.setUserId(userId);
  }, [userId, client]);

  // Update userId when prop changes
  useEffect(() => {
    if (initialUserId !== undefined) {
      setUserIdState(initialUserId);
    }
  }, [initialUserId]);

  // Set user ID and persist
  const setUserId = async (newUserId: string | undefined) => {
    setUserIdState(newUserId);
    await persistUserId(newUserId);
    client.setUserId(newUserId);
  };

  const value: FeedbackKitContextValue = {
    client,
    userId,
    setUserId,
    theme,
    isInitialized
  };

  return (
    <FeedbackKitContext.Provider value={value}>
      {children}
    </FeedbackKitContext.Provider>
  );
}

/**
 * Hook to access the FeedbackKit context
 *
 * @throws Error if used outside of FeedbackProvider
 */
export function useFeedbackKitContext(): FeedbackKitContextValue {
  const context = useContext(FeedbackKitContext);
  if (!context) {
    throw new Error('useFeedbackKitContext must be used within a FeedbackProvider');
  }
  return context;
}
