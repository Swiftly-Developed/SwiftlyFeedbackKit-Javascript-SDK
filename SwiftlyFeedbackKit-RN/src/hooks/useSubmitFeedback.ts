/**
 * useSubmitFeedback Hook
 *
 * Submit new feedback items.
 */

import { useState, useCallback } from 'react';
import { Feedback, FeedbackCategory, FeedbackKitError } from '@feedbackkit/js';
import { useFeedbackKitContext } from '../provider';

export interface SubmitFeedbackData {
  /** Feedback title */
  title: string;
  /** Feedback description */
  description: string;
  /** Feedback category */
  category: FeedbackCategory;
  /** Optional email for notifications */
  userEmail?: string;
}

export interface UseSubmitFeedbackResult {
  /** Submit new feedback */
  submit: (data: SubmitFeedbackData) => Promise<Feedback>;
  /** Whether submission is in progress */
  isSubmitting: boolean;
  /** Error from last submission */
  error: FeedbackKitError | null;
  /** Clear the error */
  clearError: () => void;
}

/**
 * Hook to submit new feedback
 *
 * @example
 * ```tsx
 * function FeedbackForm() {
 *   const { submit, isSubmitting, error } = useSubmitFeedback();
 *   const [title, setTitle] = useState('');
 *   const [description, setDescription] = useState('');
 *   const [category, setCategory] = useState(FeedbackCategory.FeatureRequest);
 *
 *   const handleSubmit = async () => {
 *     try {
 *       const feedback = await submit({
 *         title,
 *         description,
 *         category
 *       });
 *       navigation.goBack();
 *       Alert.alert('Success', 'Feedback submitted!');
 *     } catch (error) {
 *       // Error is also available in the hook
 *       Alert.alert('Error', error.message);
 *     }
 *   };
 *
 *   return (
 *     <View>
 *       <TextInput value={title} onChangeText={setTitle} placeholder="Title" />
 *       <TextInput value={description} onChangeText={setDescription} placeholder="Description" />
 *       <Button onPress={handleSubmit} disabled={isSubmitting} title="Submit" />
 *       {error && <Text style={{ color: 'red' }}>{error.message}</Text>}
 *     </View>
 *   );
 * }
 * ```
 */
export function useSubmitFeedback(): UseSubmitFeedbackResult {
  const { client, userId } = useFeedbackKitContext();
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<FeedbackKitError | null>(null);

  const submit = useCallback(
    async (data: SubmitFeedbackData): Promise<Feedback> => {
      if (!userId) {
        throw new Error('User ID is required to submit feedback. Set userId in FeedbackProvider.');
      }

      setIsSubmitting(true);
      setError(null);

      try {
        const feedback = await client.feedback.create({
          title: data.title,
          description: data.description,
          category: data.category,
          userId,
          userEmail: data.userEmail
        });
        return feedback;
      } catch (err) {
        const feedbackError = err as FeedbackKitError;
        setError(feedbackError);
        throw feedbackError;
      } finally {
        setIsSubmitting(false);
      }
    },
    [client, userId]
  );

  const clearError = useCallback(() => {
    setError(null);
  }, []);

  return {
    submit,
    isSubmitting,
    error,
    clearError
  };
}
