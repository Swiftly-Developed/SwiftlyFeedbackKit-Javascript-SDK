/**
 * Colours for the feedback list embed.
 *
 * The host passes brand colours; everything else (tonal containers, state layers,
 * text that must stay readable on them) is derived here, in the Material 3 manner,
 * and checked against WCAG AA. The result is a set of `--fk-*` custom properties
 * per colour scheme, so `prefers-color-scheme` switches palettes in CSS without a
 * re-render.
 */

import { FeedbackCategory, FeedbackStatus } from '../models/types';
import { ensureContrast, isDark, mix, onColor } from './color';

export type FeedbackListColorScheme = 'auto' | 'light' | 'dark';

export interface FeedbackListThemeColors {
  /** Brand tint: vote control, menu button, links. */
  primaryColor?: string;
  /** Page behind the cards. */
  backgroundColor?: string;
  cardBackgroundColor?: string;
  textColor?: string;
  secondaryTextColor?: string;
  errorColor?: string;
  statusColors?: Partial<Record<FeedbackStatus, string>>;
  /** Used by the Classic style's category badges. Showcase shows categories in neutral text. */
  categoryColors?: Partial<Record<FeedbackCategory, string>>;
}

export interface FeedbackListTheme extends FeedbackListThemeColors {
  /** Overrides applied only when the dark palette is in use. */
  dark?: FeedbackListThemeColors;
  /** CSS `font-family`. Defaults to the host page's font. */
  fontFamily?: string;
}

type ResolvedColors = Required<Omit<FeedbackListThemeColors, 'statusColors' | 'categoryColors'>> & {
  statusColors: Record<string, string>;
  categoryColors: Record<string, string>;
};

/** Status and category tokens that are safe in a custom-property name and a selector. */
const TOKEN = /^[a-z0-9_-]+$/i;

const STATUS_DEFAULTS: Record<string, string> = {
  [FeedbackStatus.Pending]: '#8E8E93',
  [FeedbackStatus.Approved]: '#007AFF',
  [FeedbackStatus.InProgress]: '#FF9500',
  [FeedbackStatus.TestFlight]: '#5AC8FA',
  [FeedbackStatus.Completed]: '#34C759',
  [FeedbackStatus.Rejected]: '#FF3B30'
};

const CATEGORY_DEFAULTS: Record<string, string> = {
  [FeedbackCategory.FeatureRequest]: '#AF52DE',
  [FeedbackCategory.BugReport]: '#FF3B30',
  [FeedbackCategory.Improvement]: '#5AC8FA',
  [FeedbackCategory.Other]: '#8E8E93'
};

export const LIGHT_COLORS: ResolvedColors = {
  primaryColor: '#007AFF',
  backgroundColor: '#F3F4F7',
  cardBackgroundColor: '#FFFFFF',
  textColor: '#1B1B1F',
  secondaryTextColor: '#5D5E66',
  errorColor: '#D32F2F',
  statusColors: STATUS_DEFAULTS,
  categoryColors: CATEGORY_DEFAULTS
};

export const DARK_COLORS: ResolvedColors = {
  ...LIGHT_COLORS,
  primaryColor: '#0A84FF',
  backgroundColor: '#111215',
  cardBackgroundColor: '#1E1F24',
  textColor: '#E4E4E9',
  secondaryTextColor: '#A8A9B2',
  errorColor: '#FF6B6B'
};

function merge(base: ResolvedColors, overrides?: FeedbackListThemeColors): ResolvedColors {
  if (!overrides) return base;
  const defined = Object.fromEntries(
    Object.entries(overrides).filter(([, value]) => value !== undefined)
  ) as FeedbackListThemeColors;
  return {
    ...base,
    ...defined,
    statusColors: { ...base.statusColors, ...overrides.statusColors },
    categoryColors: { ...base.categoryColors, ...overrides.categoryColors }
  } as ResolvedColors;
}

function setsSurfaces(colors?: FeedbackListThemeColors): boolean {
  return Boolean(colors?.backgroundColor || colors?.cardBackgroundColor || colors?.textColor);
}

/**
 * The palettes the embed needs for a scheme preference. Same rule as the React
 * Native provider: an explicit `'dark'` always starts from the dark base. Under
 * `'auto'` the dark palette is added only when the host did not paint its own
 * surfaces, or gave dark ones in `theme.dark`; a host that styled a light card is
 * never switched to a dark one it did not design.
 */
export function resolvePalettes(
  scheme: FeedbackListColorScheme,
  theme: FeedbackListTheme = {}
): { light?: FeedbackListPalette; dark?: FeedbackListPalette } {
  const light = () => resolvePalette(merge(LIGHT_COLORS, theme), 'light');
  const dark = () => resolvePalette(merge(merge(DARK_COLORS, theme), theme.dark), 'dark');
  if (scheme === 'light') return { light: light() };
  if (scheme === 'dark') return { dark: dark() };
  if (setsSurfaces(theme) && !setsSurfaces(theme.dark)) return { light: light() };
  return { light: light(), dark: dark() };
}

export interface FeedbackListPalette {
  scheme: 'light' | 'dark';
  vars: Record<string, string>;
}

export function resolvePalette(colors: ResolvedColors, scheme: 'light' | 'dark'): FeedbackListPalette {
  const card = colors.cardBackgroundColor;
  const background = colors.backgroundColor;
  const dark = scheme === 'dark' || isDark(card);
  const primary = colors.primaryColor;
  const tonal = mix(primary, card, dark ? 0.28 : 0.14);
  const chipSelected = mix(primary, card, dark ? 0.36 : 0.2);
  const menu = dark ? mix('#FFFFFF', card, 0.06) : card;
  const vars: Record<string, string> = {
    'color-scheme': scheme,
    '--fk-bg': background,
    '--fk-card': card,
    '--fk-card-border': mix(colors.textColor, card, dark ? 0.2 : 0.12),
    '--fk-title': colors.textColor,
    '--fk-body': ensureContrast(colors.secondaryTextColor, card),
    '--fk-body-on-bg': ensureContrast(colors.secondaryTextColor, background),
    '--fk-title-on-bg': ensureContrast(colors.textColor, background),
    '--fk-primary': primary,
    '--fk-on-primary': onColor(primary),
    '--fk-primary-on-bg': ensureContrast(primary, background),
    '--fk-primary-on-card': ensureContrast(primary, card),
    '--fk-primary-on-menu': ensureContrast(primary, menu),
    '--fk-tonal': tonal,
    '--fk-on-tonal': ensureContrast(primary, tonal),
    '--fk-tonal-on-bg': mix(primary, background, dark ? 0.28 : 0.14),
    '--fk-on-tonal-on-bg': ensureContrast(primary, mix(primary, background, dark ? 0.28 : 0.14)),
    '--fk-state': colors.textColor,
    '--fk-chip-selected': chipSelected,
    '--fk-on-chip-selected': ensureContrast(colors.textColor, chipSelected),
    '--fk-menu': menu,
    '--fk-menu-text': ensureContrast(colors.textColor, menu),
    '--fk-menu-muted': ensureContrast(colors.secondaryTextColor, menu),
    '--fk-placeholder': mix(colors.textColor, card, dark ? 0.16 : 0.08),
    '--fk-danger': ensureContrast(colors.errorColor, background),
    '--fk-focus': ensureContrast(primary, background, 3),
    '--fk-shadow-1': dark
      ? '0 1px 2px rgb(0 0 0 / 0.6), 0 1px 3px 1px rgb(0 0 0 / 0.3)'
      : '0 1px 2px rgb(0 0 0 / 0.12), 0 1px 3px 1px rgb(0 0 0 / 0.08)',
    '--fk-shadow-2': dark
      ? '0 1px 2px rgb(0 0 0 / 0.6), 0 2px 6px 2px rgb(0 0 0 / 0.35)'
      : '0 1px 2px rgb(0 0 0 / 0.18), 0 2px 6px 2px rgb(0 0 0 / 0.1)'
  };
  for (const [status, color] of Object.entries(colors.statusColors)) {
    if (!TOKEN.test(status)) continue;
    vars[`--fk-status-${status}`] = color;
    vars[`--fk-status-${status}-text`] = ensureContrast(color, card);
  }
  for (const [category, color] of Object.entries(colors.categoryColors)) {
    if (!TOKEN.test(category)) continue;
    const pill = mix(color, card, dark ? 0.26 : 0.14);
    vars[`--fk-category-${category}`] = pill;
    vars[`--fk-category-${category}-text`] = ensureContrast(color, pill);
  }
  for (const [status, color] of Object.entries(colors.statusColors)) {
    if (!TOKEN.test(status)) continue;
    const pill = mix(color, card, dark ? 0.26 : 0.14);
    vars[`--fk-status-${status}-pill`] = pill;
    vars[`--fk-status-${status}-pill-text`] = ensureContrast(color, pill);
  }
  return { scheme, vars };
}

function declarations(palette: FeedbackListPalette): string {
  return Object.entries(palette.vars)
    .map(([name, value]) => `${name}: ${value.replace(/[;{}<>]/g, '')};`)
    .join(' ');
}

/**
 * Per-status and per-category colour rules, keyed on `data-status` / `data-category`
 * attributes rather than inline `style`, so the embed works under a CSP that
 * forbids inline styles. Tokens outside `[a-z0-9_-]` are skipped and render in the
 * neutral text colour.
 */
export function tokenCss(theme: FeedbackListTheme = {}, selector = '.fk-root'): string {
  const statuses = new Set([...Object.keys(STATUS_DEFAULTS), ...Object.keys(theme.statusColors ?? {})]);
  const categories = new Set([...Object.keys(CATEGORY_DEFAULTS), ...Object.keys(theme.categoryColors ?? {})]);
  const rules: string[] = [];
  for (const status of statuses) {
    if (!TOKEN.test(status)) continue;
    rules.push(
      `${selector} .fk-eyebrow[data-status="${status}"] { color: var(--fk-status-${status}-text); }`,
      `${selector} .fk-eyebrow[data-status="${status}"] .fk-status-glyph, ${selector} .fk-status-tint[data-status="${status}"] { color: var(--fk-status-${status}); }`,
      `${selector} .fk-badge[data-status="${status}"] { background: var(--fk-status-${status}-pill); color: var(--fk-status-${status}-pill-text); }`
    );
  }
  for (const category of categories) {
    if (!TOKEN.test(category)) continue;
    rules.push(
      `${selector} .fk-badge[data-category="${category}"] { background: var(--fk-category-${category}); color: var(--fk-category-${category}-text); }`
    );
  }
  return rules.join('\n');
}

/** The palette rules for the embed root, with the dark block behind a media query under `'auto'`. */
export function paletteCss(
  scheme: FeedbackListColorScheme,
  theme: FeedbackListTheme = {},
  selector = '.fk-root'
): string {
  const { light, dark } = resolvePalettes(scheme, theme);
  const font = theme.fontFamily ? ` --fk-font: ${theme.fontFamily.replace(/[;{}<>]/g, '')};` : '';
  if (light && dark) {
    return (
      `${selector} { ${declarations(light)}${font} }\n` +
      `@media (prefers-color-scheme: dark) { ${selector} { ${declarations(dark)} } }`
    );
  }
  const only = (light ?? dark) as FeedbackListPalette;
  return `${selector} { ${declarations(only)}${font} }`;
}
