/**
 * Copy for the feedback list embed.
 *
 * The keys and English values are the React Native SDK's (`src/i18n/strings.ts`),
 * so the two SDKs read the same catalog and a translation fixed in one is fixed in
 * both. Only the keys the list renders are carried here.
 */

import { ar } from './locales/ar';
import { de } from './locales/de';
import { es } from './locales/es';
import { fr } from './locales/fr';
import { it } from './locales/it';
import { ja } from './locales/ja';
import { ko } from './locales/ko';
import { ptBR } from './locales/pt-BR';
import { ru } from './locales/ru';
import { zhHans } from './locales/zh-Hans';

export const en = {
  'feedback.list.title': 'Feedback',
  'feedback.list.empty': 'No feedback yet',
  'feedback.list.empty.description': 'Be the first to share your ideas!',
  'feedback.list.error.generic': 'Something went wrong',

  'comment.one': 'comment',
  'comment.other': 'comments',

  'status.pending': 'Pending',
  'status.approved': 'Approved',
  'status.inProgress': 'In Progress',
  'status.testflight': 'TestFlight',
  'status.completed': 'Completed',
  'status.rejected': 'Rejected',

  'category.featureRequest': 'Feature Request',
  'category.bugReport': 'Bug Report',
  'category.improvement': 'Improvement',
  'category.other': 'Other',
  'category.featureRequest.plural': 'Feature Requests',
  'category.bugReport.plural': 'Bug Reports',
  'category.improvement.plural': 'Improvements',
  'category.other.plural': 'Other',

  'sort.label': 'Sort',
  'sort.votes': 'Most Votes',
  'sort.newest': 'Newest',
  'sort.oldest': 'Oldest',
  'sort.comments': 'Most Comments',

  'list.sortAndFilter': 'Sort & Filter',
  'list.sortBy': 'Sort By',
  'list.filter.status': 'Status',
  'list.filter.category': 'Category',
  'list.filter.allStatuses': 'All Statuses',
  'list.filter.allCategories': 'All Categories',
  'list.filter.clearAll': 'Clear Filters',
  'list.filter.clear': 'Clear',
  'list.filter.summary': 'Filtered by %@',
  'list.filter.join': '%1$@ · %2$@',
  'list.filter.empty.title': 'No Matching Requests',
  'list.filter.empty.description': 'No requests match the selected filters.',
  'list.loading': 'Loading feedback',
  'list.retry': 'Try Again',

  'vote.count.one': '%d vote',
  'vote.count.other': '%d votes',
  'a11y.vote.voted': 'Voted',
  'a11y.vote.notVoted': 'Not voted',
  'a11y.vote.closed': 'Voting is closed',
  'a11y.vote.hint': 'Adds your vote',
  'a11y.vote.unvoteHint': 'Removes your vote',
  'a11y.vote.lockedHint': "You've voted. Votes can't be removed",
  'a11y.filter.clearAction': 'Clear filters'
} as const;

export type FeedbackListStringKey = keyof typeof en;
export type FeedbackListStrings = Partial<Record<FeedbackListStringKey, string>>;

/** Shipped catalogs, keyed by BCP 47 language (and script/region where it matters). */
export const catalogs: Readonly<Record<string, FeedbackListStrings>> = {
  en,
  ar,
  de,
  es,
  fr,
  it,
  ja,
  ko,
  'pt-BR': ptBR,
  ru,
  'zh-Hans': zhHans
};

/**
 * The shipped catalog for `locale`: an exact tag first, then the Chinese script
 * mapping, then the bare language. Unknown locales get English.
 */
export function resolveCatalog(locale: string | undefined): FeedbackListStrings {
  if (!locale) return en;
  const tag = locale.replace(/_/g, '-');
  const exact = Object.keys(catalogs).find((key) => key.toLowerCase() === tag.toLowerCase());
  if (exact) return catalogs[exact];
  const lower = tag.toLowerCase();
  if (lower.startsWith('zh')) return catalogs['zh-Hans'];
  if (lower.startsWith('pt')) return catalogs['pt-BR'];
  const language = lower.split('-')[0];
  return catalogs[language] ?? en;
}

/** Text direction for a locale's script, for the embed's `dir` attribute. */
export function localeDirection(locale: string | undefined): 'ltr' | 'rtl' {
  if (!locale) return 'ltr';
  const language = locale.replace(/_/g, '-').toLowerCase().split('-')[0];
  return ['ar', 'he', 'fa', 'ur', 'ps', 'yi'].includes(language) ? 'rtl' : 'ltr';
}

/**
 * Fills `%@`, `%d` and positional `%1$@` / `%2$d` placeholders, as the Swift and
 * React Native catalogs write them.
 */
export function formatString(template: string, ...args: Array<string | number>): string {
  let next = 0;
  return template.replace(/%(?:(\d+)\$)?([@d])/g, (_match, position: string | undefined) => {
    const index = position !== undefined ? Number(position) - 1 : next++;
    const value = args[index];
    return value === undefined ? '' : String(value);
  });
}

export type Translate = (key: FeedbackListStringKey) => string;

/** Host overrides, then the locale's catalog, then English. */
export function createTranslator(locale: string | undefined, overrides?: FeedbackListStrings): Translate {
  const catalog = resolveCatalog(locale);
  return (key) => overrides?.[key] ?? catalog[key] ?? en[key];
}
