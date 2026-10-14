/**
 * FeedbackKit feedback list embed — `feedbackkit-js/ui`.
 *
 * An opt-in entry point: the core `feedbackkit-js` import stays headless and
 * DOM-free, and only hosts that render the list pull this module in.
 *
 * @packageDocumentation
 */

export { mountFeedbackList } from './mount';
export type { FeedbackListHandle, FeedbackListOptions } from './mount';
export type { FeedbackListColorScheme, FeedbackListTheme, FeedbackListThemeColors } from './theme';
export type { FeedbackListStyle, FeedbackListUserFilter, VotePresentation, VotePresentationKind } from './state';
export { canVoteOnStatus, resolveVotePresentation } from './state';
export type { FeedbackListStringKey, FeedbackListStrings } from './strings';
export { formatString } from './strings';
