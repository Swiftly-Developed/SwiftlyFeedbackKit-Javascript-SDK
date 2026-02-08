/**
 * AsyncStorage utilities for FeedbackKit
 */

import AsyncStorage from '@react-native-async-storage/async-storage';

const STORAGE_KEYS = {
  USER_ID: '@feedbackkit/userId',
  CACHED_FEEDBACK: '@feedbackkit/cachedFeedback'
} as const;

/**
 * Get the persisted user ID
 */
export async function getUserId(): Promise<string | null> {
  try {
    return await AsyncStorage.getItem(STORAGE_KEYS.USER_ID);
  } catch {
    return null;
  }
}

/**
 * Persist the user ID
 */
export async function setUserId(userId: string | undefined): Promise<void> {
  try {
    if (userId) {
      await AsyncStorage.setItem(STORAGE_KEYS.USER_ID, userId);
    } else {
      await AsyncStorage.removeItem(STORAGE_KEYS.USER_ID);
    }
  } catch {
    // Silently fail
  }
}

/**
 * Clear all FeedbackKit storage
 */
export async function clearStorage(): Promise<void> {
  try {
    const keys = Object.values(STORAGE_KEYS);
    await AsyncStorage.multiRemove(keys);
  } catch {
    // Silently fail
  }
}
