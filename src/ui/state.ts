/**
 * Pure state for the feedback list embed: sort and filter options, the session
 * filter, the "Filtered by" summary, and how each row's vote control presents.
 * DOM-free, so every rule is unit-tested on its own and the renderer only reads
 * answers. Mirrors the React Native SDK's `showcase/feedbackListState.ts`.
 */

import { Feedback, FeedbackCategory, FeedbackSort, FeedbackStatus } from '../models/types';
import { FeedbackListStringKey, Translate, formatString } from './strings';

export type FeedbackListStyle = 'showcase' | 'classic';

/** The filter the user picks in the Sort & Filter menu. Session-only. */
export interface FeedbackListUserFilter {
  status?: FeedbackStatus;
  category?: FeedbackCategory;
}

export const SORT_OPTIONS: ReadonlyArray<{ value: FeedbackSort; labelKey: FeedbackListStringKey }> = [
  { value: FeedbackSort.Votes, labelKey: 'sort.votes' },
  { value: FeedbackSort.Newest, labelKey: 'sort.newest' },
  { value: FeedbackSort.Oldest, labelKey: 'sort.oldest' },
  { value: FeedbackSort.Comments, labelKey: 'sort.comments' }
];

export const STATUS_OPTIONS: ReadonlyArray<FeedbackStatus> = [
  FeedbackStatus.Pending,
  FeedbackStatus.Approved,
  FeedbackStatus.InProgress,
  FeedbackStatus.TestFlight,
  FeedbackStatus.Completed,
  FeedbackStatus.Rejected
];

export const CATEGORY_OPTIONS: ReadonlyArray<FeedbackCategory> = [
  FeedbackCategory.FeatureRequest,
  FeedbackCategory.BugReport,
  FeedbackCategory.Improvement,
  FeedbackCategory.Other
];

/** Statuses that still accept votes. Completed and Rejected are closed, as on the server. */
const VOTABLE_STATUSES: ReadonlySet<string> = new Set([
  FeedbackStatus.Pending,
  FeedbackStatus.Approved,
  FeedbackStatus.InProgress,
  FeedbackStatus.TestFlight
]);

export function canVoteOnStatus(status: FeedbackStatus): boolean {
  return VOTABLE_STATUSES.has(status);
}

const STATUS_KEYS: Record<string, FeedbackListStringKey> = {
  [FeedbackStatus.Pending]: 'status.pending',
  [FeedbackStatus.Approved]: 'status.approved',
  [FeedbackStatus.InProgress]: 'status.inProgress',
  [FeedbackStatus.TestFlight]: 'status.testflight',
  [FeedbackStatus.Completed]: 'status.completed',
  [FeedbackStatus.Rejected]: 'status.rejected'
};

const CATEGORY_KEYS: Record<string, FeedbackListStringKey> = {
  [FeedbackCategory.FeatureRequest]: 'category.featureRequest',
  [FeedbackCategory.BugReport]: 'category.bugReport',
  [FeedbackCategory.Improvement]: 'category.improvement',
  [FeedbackCategory.Other]: 'category.other'
};

const CATEGORY_PLURAL_KEYS: Record<string, FeedbackListStringKey> = {
  [FeedbackCategory.FeatureRequest]: 'category.featureRequest.plural',
  [FeedbackCategory.BugReport]: 'category.bugReport.plural',
  [FeedbackCategory.Improvement]: 'category.improvement.plural',
  [FeedbackCategory.Other]: 'category.other.plural'
};

/** Unknown server values (a status added after this build) render as their raw token. */
export function statusName(status: FeedbackStatus, t: Translate): string {
  const key = STATUS_KEYS[status];
  return key ? t(key) : String(status);
}

export function categoryName(category: FeedbackCategory, t: Translate): string {
  const key = CATEGORY_KEYS[category];
  return key ? t(key) : String(category);
}

export function categoryPluralName(category: FeedbackCategory, t: Translate): string {
  const key = CATEGORY_PLURAL_KEYS[category];
  return key ? t(key) : String(category);
}

export function sortLabel(sort: FeedbackSort, t: Translate): string {
  const option = SORT_OPTIONS.find((candidate) => candidate.value === sort);
  return option ? t(option.labelKey) : String(sort);
}

export function isFiltered(filter: FeedbackListUserFilter): boolean {
  return filter.status !== undefined || filter.category !== undefined;
}

export function applyUserFilter(
  feedbacks: ReadonlyArray<Feedback>,
  filter: FeedbackListUserFilter
): Feedback[] {
  if (!isFiltered(filter)) return [...feedbacks];
  return feedbacks.filter(
    (item) =>
      (filter.status === undefined || item.status === filter.status) &&
      (filter.category === undefined || item.category === filter.category)
  );
}

/**
 * Orders a host-supplied array the way the server orders a list request, for
 * embeds fed `items` instead of a client. Stable, so ties keep the host's order.
 */
export function sortFeedback(feedbacks: ReadonlyArray<Feedback>, sort: FeedbackSort): Feedback[] {
  const time = (value: string) => {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? 0 : parsed;
  };
  const compare: Record<string, (a: Feedback, b: Feedback) => number> = {
    [FeedbackSort.Votes]: (a, b) => b.voteCount - a.voteCount,
    [FeedbackSort.Newest]: (a, b) => time(b.createdAt) - time(a.createdAt),
    [FeedbackSort.Oldest]: (a, b) => time(a.createdAt) - time(b.createdAt),
    [FeedbackSort.Comments]: (a, b) => b.commentCount - a.commentCount
  };
  const by = compare[sort];
  return by ? [...feedbacks].sort(by) : [...feedbacks];
}

/**
 * The names the summary row shows in bold: category first, then status, joined by
 * the catalog's join pattern so a translation can reorder or re-punctuate them.
 * Null when nothing is filtered, because the row is not shown then.
 */
export function filterSummaryNames(filter: FeedbackListUserFilter, t: Translate): string | null {
  const category = filter.category !== undefined ? categoryPluralName(filter.category, t) : null;
  const status = filter.status !== undefined ? statusName(filter.status, t) : null;
  if (category && status) return formatString(t('list.filter.join'), category, status);
  return category ?? status;
}

/** "Filtered by Improvements · In Progress", or null when nothing is filtered. */
export function filterSummaryText(filter: FeedbackListUserFilter, t: Translate): string | null {
  const names = filterSummaryNames(filter, t);
  return names === null ? null : formatString(t('list.filter.summary'), names);
}

export function formatCount(value: number, locale?: string): string {
  try {
    return new Intl.NumberFormat(locale).format(value);
  } catch {
    return String(value);
  }
}

export function voteCountText(count: number, t: Translate, locale?: string): string {
  return formatString(t(count === 1 ? 'vote.count.one' : 'vote.count.other'), formatCount(count, locale));
}

export function commentCountText(count: number, t: Translate, locale?: string): string {
  return `${formatCount(count, locale)} ${t(count === 1 ? 'comment.one' : 'comment.other')}`;
}

export type VotePresentationKind = 'hidden' | 'skeleton' | 'closed' | 'votable' | 'voted' | 'votedLocked';

export interface VotePresentationInput {
  status: FeedbackStatus;
  hasVoted: boolean;
  showVoteCount: boolean;
  allowUndoVote: boolean;
  isSkeleton?: boolean;
}

export interface VotePresentation {
  kind: VotePresentationKind;
  /** Whether the control is a button at all. A closed count is plain text. */
  isButton: boolean;
  /** Whether activating it does something. False for a locked vote. */
  isActionable: boolean;
  isFilled: boolean;
  valueKey: FeedbackListStringKey | null;
  hintKey: FeedbackListStringKey | null;
}

export function resolveVotePresentation(input: VotePresentationInput): VotePresentation {
  if (!input.showVoteCount) {
    return { kind: 'hidden', isButton: false, isActionable: false, isFilled: false, valueKey: null, hintKey: null };
  }
  if (input.isSkeleton) {
    return { kind: 'skeleton', isButton: false, isActionable: false, isFilled: false, valueKey: null, hintKey: null };
  }
  if (!canVoteOnStatus(input.status)) {
    return {
      kind: 'closed',
      isButton: false,
      isActionable: false,
      isFilled: false,
      valueKey: 'a11y.vote.closed',
      hintKey: null
    };
  }
  if (!input.hasVoted) {
    return {
      kind: 'votable',
      isButton: true,
      isActionable: true,
      isFilled: false,
      valueKey: 'a11y.vote.notVoted',
      hintKey: 'a11y.vote.hint'
    };
  }
  if (input.allowUndoVote) {
    return {
      kind: 'voted',
      isButton: true,
      isActionable: true,
      isFilled: true,
      valueKey: 'a11y.vote.voted',
      hintKey: 'a11y.vote.unvoteHint'
    };
  }
  return {
    kind: 'votedLocked',
    isButton: true,
    isActionable: false,
    isFilled: true,
    valueKey: 'a11y.vote.voted',
    hintKey: 'a11y.vote.lockedHint'
  };
}
