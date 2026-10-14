import { describe, expect, it } from 'vitest';
import { Feedback, FeedbackCategory, FeedbackSort, FeedbackStatus } from '../src/models/types';
import { contrastRatio } from '../src/ui/color';
import {
  applyUserFilter,
  canVoteOnStatus,
  commentCountText,
  filterSummaryText,
  formatCount,
  resolveVotePresentation,
  sortFeedback,
  voteCountText,
  VotePresentationKind
} from '../src/ui/state';
import { catalogs, createTranslator, en, formatString, localeDirection, resolveCatalog } from '../src/ui/strings';
import { BASE_CSS } from '../src/ui/styles';
import { LIGHT_COLORS, paletteCss, resolvePalettes, tokenCss } from '../src/ui/theme';

/**
 * Feedback list embed (`feedbackkit-js/ui`), pure layer: the FEEDBACK01 vote table,
 * the session filter and its summary, sorting for host-supplied items, the copy
 * catalogs, the derived palettes, and two census gates over the stylesheet (rem
 * sizing for 200% text, logical properties for right-to-left).
 */

const t = createTranslator('en');

function feedback(overrides: Partial<Feedback> = {}): Feedback {
  return {
    id: 'f1',
    title: 'Title',
    description: 'Description',
    status: FeedbackStatus.Pending,
    category: FeedbackCategory.FeatureRequest,
    userId: 'u1',
    voteCount: 1,
    hasVoted: false,
    commentCount: 0,
    createdAt: '2026-10-01T00:00:00Z',
    updatedAt: '2026-10-01T00:00:00Z',
    ...overrides
  };
}

describe('vote presentation (FEEDBACK01 §6.4)', () => {
  it.each([
    [FeedbackStatus.Pending, true],
    [FeedbackStatus.Approved, true],
    [FeedbackStatus.InProgress, true],
    [FeedbackStatus.TestFlight, true],
    [FeedbackStatus.Completed, false],
    [FeedbackStatus.Rejected, false]
  ])('%s accepts votes: %s', (status, votable) => {
    expect(canVoteOnStatus(status)).toBe(votable);
  });

  const cells: Array<[VotePresentationKind, Parameters<typeof resolveVotePresentation>[0], Partial<ReturnType<typeof resolveVotePresentation>>]> = [
    ['hidden', { status: FeedbackStatus.Pending, hasVoted: false, showVoteCount: false, allowUndoVote: true }, { isButton: false }],
    ['skeleton', { status: FeedbackStatus.Pending, hasVoted: false, showVoteCount: true, allowUndoVote: true, isSkeleton: true }, { isButton: false }],
    ['closed', { status: FeedbackStatus.Completed, hasVoted: true, showVoteCount: true, allowUndoVote: true }, { isButton: false, valueKey: 'a11y.vote.closed', hintKey: null }],
    ['votable', { status: FeedbackStatus.Approved, hasVoted: false, showVoteCount: true, allowUndoVote: true }, { isButton: true, isActionable: true, isFilled: false, hintKey: 'a11y.vote.hint' }],
    ['voted', { status: FeedbackStatus.InProgress, hasVoted: true, showVoteCount: true, allowUndoVote: true }, { isButton: true, isActionable: true, isFilled: true, hintKey: 'a11y.vote.unvoteHint' }],
    ['votedLocked', { status: FeedbackStatus.TestFlight, hasVoted: true, showVoteCount: true, allowUndoVote: false }, { isButton: true, isActionable: false, isFilled: true, hintKey: 'a11y.vote.lockedHint' }]
  ];

  it.each(cells)('%s', (kind, input, expected) => {
    const result = resolveVotePresentation(input);
    expect(result.kind).toBe(kind);
    expect(result).toMatchObject(expected);
  });

  it('a hidden count wins over every other condition', () => {
    expect(resolveVotePresentation({ status: FeedbackStatus.Rejected, hasVoted: true, showVoteCount: false, allowUndoVote: false }).kind).toBe('hidden');
  });
});

describe('session filter and summary (FEEDBACK01 §6.5)', () => {
  const items = [
    feedback({ id: 'a', status: FeedbackStatus.InProgress, category: FeedbackCategory.Improvement }),
    feedback({ id: 'b', status: FeedbackStatus.Pending, category: FeedbackCategory.Improvement }),
    feedback({ id: 'c', status: FeedbackStatus.InProgress, category: FeedbackCategory.BugReport })
  ];

  it('filters by status, category, or both', () => {
    expect(applyUserFilter(items, {}).map((f) => f.id)).toEqual(['a', 'b', 'c']);
    expect(applyUserFilter(items, { status: FeedbackStatus.InProgress }).map((f) => f.id)).toEqual(['a', 'c']);
    expect(applyUserFilter(items, { category: FeedbackCategory.Improvement }).map((f) => f.id)).toEqual(['a', 'b']);
    expect(applyUserFilter(items, { status: FeedbackStatus.InProgress, category: FeedbackCategory.Improvement }).map((f) => f.id)).toEqual(['a']);
  });

  it('names category first, in its plural, then status', () => {
    expect(filterSummaryText({}, t)).toBeNull();
    expect(filterSummaryText({ status: FeedbackStatus.InProgress }, t)).toBe('Filtered by In Progress');
    expect(filterSummaryText({ category: FeedbackCategory.BugReport }, t)).toBe('Filtered by Bug Reports');
    expect(filterSummaryText({ status: FeedbackStatus.InProgress, category: FeedbackCategory.Improvement }, t)).toBe(
      'Filtered by Improvements · In Progress'
    );
  });

  it("takes order and separator from the catalog's join pattern", () => {
    const reversed = createTranslator('en', { 'list.filter.join': '%2$@ / %1$@' });
    expect(filterSummaryText({ status: FeedbackStatus.Approved, category: FeedbackCategory.Other }, reversed)).toBe(
      'Filtered by Approved / Other'
    );
  });
});

describe('sorting host-supplied items', () => {
  const items = [
    feedback({ id: 'old', voteCount: 5, commentCount: 1, createdAt: '2026-01-01T00:00:00Z' }),
    feedback({ id: 'new', voteCount: 2, commentCount: 9, createdAt: '2026-09-01T00:00:00Z' }),
    feedback({ id: 'mid', voteCount: 5, commentCount: 3, createdAt: '2026-05-01T00:00:00Z' })
  ];

  it.each([
    [FeedbackSort.Votes, ['old', 'mid', 'new']],
    [FeedbackSort.Newest, ['new', 'mid', 'old']],
    [FeedbackSort.Oldest, ['old', 'mid', 'new']],
    [FeedbackSort.Comments, ['new', 'mid', 'old']]
  ])('%s', (sort, order) => {
    expect(sortFeedback(items, sort).map((f) => f.id)).toEqual(order);
  });

  it('does not mutate the input', () => {
    const copy = [...items];
    sortFeedback(items, FeedbackSort.Newest);
    expect(items).toEqual(copy);
  });
});

describe('copy', () => {
  it('fills sequential and positional placeholders', () => {
    expect(formatString('%d votes', 3)).toBe('3 votes');
    expect(formatString('%@ and %@', 'a', 'b')).toBe('a and b');
    expect(formatString('%2$@ · %1$@', 'a', 'b')).toBe('b · a');
  });

  it('formats counts with the locale and picks one/other', () => {
    expect(formatCount(1234, 'de')).toBe('1.234');
    expect(voteCountText(1, t)).toBe('1 vote');
    expect(voteCountText(1234, t, 'en')).toBe('1,234 votes');
    expect(commentCountText(3, t)).toBe('3 comments');
    expect(commentCountText(1, t)).toBe('1 comment');
  });

  it('resolves locales by tag, script and language, falling back to English', () => {
    expect(resolveCatalog('de-AT')).toBe(catalogs.de);
    expect(resolveCatalog('pt-PT')).toBe(catalogs['pt-BR']);
    expect(resolveCatalog('zh-CN')).toBe(catalogs['zh-Hans']);
    expect(resolveCatalog('nl')).toBe(en);
    expect(resolveCatalog(undefined)).toBe(en);
    expect(localeDirection('ar-EG')).toBe('rtl');
    expect(localeDirection('en')).toBe('ltr');
  });

  it('prefers host overrides, then the catalog, then English', () => {
    const translate = createTranslator('fr', { 'list.retry': 'Encore' });
    expect(translate('list.retry')).toBe('Encore');
    expect(translate('status.testflight')).toBe('TestFlight');
  });

  const placeholders = (value: string) => (value.match(/%(?:\d+\$)?[@d]/g) ?? []).sort();

  it.each(Object.keys(catalogs).filter((locale) => locale !== 'en'))('%s carries every key with the same placeholders', (locale) => {
    const catalog = catalogs[locale] as Record<string, string>;
    expect(Object.keys(catalog).sort()).toEqual(Object.keys(en).sort());
    for (const [key, value] of Object.entries(en)) {
      expect({ key, placeholders: placeholders(catalog[key]) }).toEqual({ key, placeholders: placeholders(value) });
    }
    expect(catalog['status.testflight']).toBe('TestFlight');
  });
});

describe('palettes', () => {
  it("'auto' adds a dark palette only when the host left the surfaces alone", () => {
    expect(Object.keys(resolvePalettes('auto'))).toEqual(['light', 'dark']);
    expect(Object.keys(resolvePalettes('auto', { cardBackgroundColor: '#FFF8E1' }))).toEqual(['light']);
    expect(Object.keys(resolvePalettes('auto', { cardBackgroundColor: '#FFF8E1', dark: { cardBackgroundColor: '#2B2410' } }))).toEqual([
      'light',
      'dark'
    ]);
    expect(Object.keys(resolvePalettes('auto', { primaryColor: '#6750A4' }))).toEqual(['light', 'dark']);
    expect(Object.keys(resolvePalettes('dark', { cardBackgroundColor: '#FFF8E1' }))).toEqual(['dark']);
    expect(Object.keys(resolvePalettes('light'))).toEqual(['light']);
  });

  const pairs: Array<[string, string]> = [
    ['--fk-title', '--fk-card'],
    ['--fk-body', '--fk-card'],
    ['--fk-on-tonal', '--fk-tonal'],
    ['--fk-on-tonal-on-bg', '--fk-tonal-on-bg'],
    ['--fk-primary-on-bg', '--fk-bg'],
    ['--fk-menu-text', '--fk-menu'],
    ['--fk-menu-muted', '--fk-menu'],
    ['--fk-on-chip-selected', '--fk-chip-selected'],
    ['--fk-status-in_progress-text', '--fk-card'],
    ['--fk-status-testflight-text', '--fk-card'],
    ['--fk-category-improvement-text', '--fk-category-improvement']
  ];

  it.each([
    ['default', {}],
    ['yellow tint', { primaryColor: '#FFD60A' }],
    ['pale grey text', { secondaryTextColor: '#C7C7CC', primaryColor: '#5AC8FA' }]
  ])('text meets AA on its surface in both schemes (%s)', (_name, theme) => {
    const { light, dark } = resolvePalettes('auto', theme);
    for (const palette of [light, dark]) {
      for (const [fg, bg] of pairs) {
        const ratio = contrastRatio(palette!.vars[fg], palette!.vars[bg]) ?? 0;
        expect({ scheme: palette!.scheme, fg, ratio: ratio >= 4.5 }).toEqual({ scheme: palette!.scheme, fg, ratio: true });
      }
    }
  });

  it('a filled vote label stays at least 3:1 on the host tint', () => {
    for (const primary of [LIGHT_COLORS.primaryColor, '#FFD60A', '#34C759', '#6750A4']) {
      const vars = resolvePalettes('light', { primaryColor: primary }).light!.vars;
      expect(contrastRatio(vars['--fk-on-primary'], vars['--fk-primary'])).toBeGreaterThanOrEqual(3);
    }
  });

  it('cannot be used to inject CSS through a theme value', () => {
    const css = paletteCss('light', { primaryColor: 'red; } body { display: none', fontFamily: 'x; } * {' });
    expect(css).not.toContain('body {');
    expect(css.match(/\{/g)).toHaveLength(1);
  });

  it('skips status tokens that are unsafe in a selector', () => {
    const css = tokenCss({ statusColors: { ['bad"] *{' as FeedbackStatus]: '#000' } });
    expect(css).not.toContain('bad"');
    expect(css).toContain('[data-status="in_progress"]');
  });
});

describe('stylesheet census', () => {
  const declarations = (property: RegExp) => [...BASE_CSS.matchAll(property)].map((match) => match[1].trim());

  it('sizes text in rem/em only, so browser text size and zoom reach every label', () => {
    const sizes = declarations(/font-size:\s*([^;]+);/g);
    expect(sizes.length).toBeGreaterThan(10);
    expect(sizes.filter((value) => !/^[\d.]+r?em$/.test(value) && value !== '100%')).toEqual([]);
  });

  it('uses no fixed px dimensions except hairlines', () => {
    const px = [...BASE_CSS.matchAll(/(\d*\.?\d+)px/g)].map((match) => Number(match[1]));
    expect(px.filter((value) => value > 3)).toEqual([]);
  });

  it('uses logical properties, so right-to-left mirrors without a second sheet', () => {
    expect(BASE_CSS).not.toMatch(/(?:margin|padding|border)-(?:left|right)\s*:/);
    expect(BASE_CSS).not.toMatch(/[\s;{](?:left|right)\s*:/);
    expect(BASE_CSS).not.toMatch(/text-align:\s*(?:left|right)/);
  });

  it('gives the vote control and menu items a 3rem (48px at default size) target', () => {
    expect(BASE_CSS).toMatch(/\.fk-vote::before \{[^}]*inset: -0\.25rem/);
    expect(BASE_CSS).toMatch(/\.fk-vote \{[^}]*min-block-size: 2\.5rem/);
    expect(BASE_CSS).toMatch(/\.fk-menu-item \{[^}]*min-block-size: 3rem/);
  });

  it('honours reduced motion, increased contrast and forced colours', () => {
    expect(BASE_CSS).toContain('@media (prefers-reduced-motion: reduce)');
    expect(BASE_CSS).toContain('@media (prefers-contrast: more)');
    expect(BASE_CSS).toContain('@media (forced-colors: active)');
  });
});
