/**
 * HTML for the feedback list embed. Pure string builders over already-resolved
 * state; every interpolated value passes through `escapeHtml`. Interactive
 * elements carry `data-fk-action` (what a click does) and `data-fk-key` (a stable
 * identity, so focus survives a re-render).
 */

import { Feedback, FeedbackSort } from '../models/types';
import { categoryIconName, icon, statusGlyph } from './icons';
import {
  CATEGORY_OPTIONS,
  FeedbackListUserFilter,
  SORT_OPTIONS,
  STATUS_OPTIONS,
  categoryName,
  categoryPluralName,
  commentCountText,
  filterSummaryNames,
  filterSummaryText,
  formatCount,
  isFiltered,
  resolveVotePresentation,
  sortLabel,
  statusName,
  voteCountText
} from './state';
import { Translate } from './strings';

export interface RenderFlags {
  showStatusBadge: boolean;
  showCategoryBadge: boolean;
  showCommentCount: boolean;
  showVoteCount: boolean;
  allowUndoVote: boolean;
}

export interface RenderContext {
  /** Unique per mounted list, so ids never collide between two embeds on a page. */
  id: string;
  t: Translate;
  locale?: string;
  flags: RenderFlags;
  selectable: boolean;
  headingLevel: number;
}

export function escapeHtml(value: unknown): string {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/** An id fragment from a server id: anything outside `[A-Za-z0-9_-]` is dropped. */
function idPart(value: string): string {
  return value.replace(/[^A-Za-z0-9_-]/g, '');
}

function heading(level: number, className: string, id: string, inner: string): string {
  const tag = `h${Math.min(6, Math.max(1, Math.round(level)))}`;
  return `<${tag} class="${className}"${id ? ` id="${id}"` : ''}>${inner}</${tag}>`;
}

// ---------------------------------------------------------------------------
// Header and the Sort & Filter menu
// ---------------------------------------------------------------------------

export interface MenuModel {
  open: boolean;
  sort: FeedbackSort;
  filter: FeedbackListUserFilter;
  offerStatus: boolean;
  offerCategory: boolean;
}

export function renderHeader(ctx: RenderContext, title: string | null, menu: MenuModel | null): string {
  if (title === null && menu === null) return '';
  const titleHtml = title === null ? '' : heading(ctx.headingLevel, 'fk-heading', `${ctx.id}-heading`, escapeHtml(title));
  return `<div class="fk-header">${titleHtml}${menu ? renderMenuButton(ctx, menu) : ''}</div>`;
}

function renderMenuButton(ctx: RenderContext, menu: MenuModel): string {
  const { t } = ctx;
  const active = isFiltered(menu.filter);
  const value = filterSummaryText(menu.filter, t) ?? sortLabel(menu.sort, t);
  return (
    `<div class="fk-menu-anchor">` +
    `<button type="button" class="fk-btn ${active ? 'fk-btn-filled' : 'fk-btn-tonal'}" part="menu-button" ` +
    `id="${ctx.id}-menu-button" aria-haspopup="menu" aria-expanded="${menu.open}" aria-controls="${ctx.id}-menu" ` +
    `aria-describedby="${ctx.id}-menu-value" data-fk-action="menu-toggle" data-fk-key="menu-button" ` +
    `data-active="${active}">` +
    `${icon(active ? 'filterActive' : 'filter')}<span>${escapeHtml(t('list.sortAndFilter'))}</span></button>` +
    `<span class="fk-sr-only" id="${ctx.id}-menu-value">${escapeHtml(value)}</span>` +
    renderMenu(ctx, menu) +
    `</div>`
  );
}

function menuItem(
  key: string,
  action: string,
  value: string,
  label: string,
  checked: boolean,
  lead = ''
): string {
  return (
    `<button type="button" role="menuitemradio" class="fk-menu-item" tabindex="-1" aria-checked="${checked}" ` +
    `data-fk-action="${action}" data-fk-value="${escapeHtml(value)}" data-fk-key="${escapeHtml(key)}">` +
    `<span class="fk-menu-check">${icon('check')}</span>${lead}<span class="fk-menu-label">${escapeHtml(label)}</span></button>`
  );
}

function menuGroup(heading: string, items: string): string {
  return (
    `<div class="fk-menu-heading" aria-hidden="true">${escapeHtml(heading)}</div>` +
    `<div role="group" class="fk-menu-group" aria-label="${escapeHtml(heading)}">${items}</div>`
  );
}

/**
 * One flat menu with labelled sections instead of nested submenus: nested menus
 * are hard to reach by keyboard and on touch, and at 200% text the sections
 * simply scroll.
 */
export function renderMenu(ctx: RenderContext, menu: MenuModel): string {
  const { t } = ctx;
  const sections: string[] = [];
  sections.push(
    menuGroup(
      t('list.sortBy'),
      SORT_OPTIONS.map((option) =>
        menuItem(`sort:${option.value}`, 'sort', option.value, t(option.labelKey), option.value === menu.sort)
      ).join('')
    )
  );
  if (menu.offerStatus) {
    const items = [
      menuItem('status:all', 'status', '', t('list.filter.allStatuses'), menu.filter.status === undefined),
      ...STATUS_OPTIONS.map((status) =>
        menuItem(
          `status:${status}`,
          'status',
          status,
          statusName(status, t),
          menu.filter.status === status,
          `<span class="fk-menu-lead fk-status-tint" data-status="${status}">${statusGlyph(status)}</span>`
        )
      )
    ];
    sections.push(menuGroup(t('list.filter.status'), items.join('')));
  }
  if (menu.offerCategory) {
    const items = [
      menuItem('category:all', 'category', '', t('list.filter.allCategories'), menu.filter.category === undefined),
      ...CATEGORY_OPTIONS.map((category) =>
        menuItem(
          `category:${category}`,
          'category',
          category,
          categoryPluralName(category, t),
          menu.filter.category === category,
          `<span class="fk-menu-lead">${icon(categoryIconName(category))}</span>`
        )
      )
    ];
    sections.push(menuGroup(t('list.filter.category'), items.join('')));
  }
  if (isFiltered(menu.filter)) {
    sections.push(
      `<button type="button" role="menuitem" class="fk-menu-item fk-menu-item-danger" tabindex="-1" ` +
        `data-fk-action="clear-filters" data-fk-key="menu-clear">` +
        `<span class="fk-menu-check">${icon('close')}</span><span class="fk-menu-label">${escapeHtml(t('list.filter.clearAll'))}</span></button>`
    );
  }
  return (
    `<div role="menu" class="fk-menu" id="${ctx.id}-menu" aria-labelledby="${ctx.id}-menu-button" part="menu"` +
    `${menu.open ? '' : ' hidden'}>` +
    sections.join('<div role="separator" class="fk-menu-separator"></div>') +
    `</div>`
  );
}

// ---------------------------------------------------------------------------
// "Filtered by … Clear"
// ---------------------------------------------------------------------------

export function renderFilterRow(ctx: RenderContext, filter: FeedbackListUserFilter): string {
  const names = filterSummaryNames(filter, ctx.t);
  if (names === null) return '';
  const [before, after = ''] = ctx.t('list.filter.summary').split('%@');
  const sentence = `${escapeHtml(before)}<strong>${escapeHtml(names)}</strong>${escapeHtml(after)}`;
  return (
    `${icon('filterActive')}<span class="fk-filter-text">${sentence}</span>` +
    `<button type="button" class="fk-btn fk-btn-text" data-fk-action="clear-filters" data-fk-key="filter-clear" ` +
    `aria-label="${escapeHtml(ctx.t('a11y.filter.clearAction'))}">${escapeHtml(ctx.t('list.filter.clear'))}</button>`
  );
}

// ---------------------------------------------------------------------------
// Vote control
// ---------------------------------------------------------------------------

export function renderVote(ctx: RenderContext, feedback: Feedback, busy: boolean, stacked = false): string {
  const presentation = resolveVotePresentation({
    status: feedback.status,
    hasVoted: feedback.hasVoted,
    showVoteCount: ctx.flags.showVoteCount,
    allowUndoVote: ctx.flags.allowUndoVote
  });
  if (presentation.kind === 'hidden' || presentation.kind === 'skeleton') return '';
  const { t } = ctx;
  const count = formatCount(feedback.voteCount, ctx.locale);
  const label = voteCountText(feedback.voteCount, t, ctx.locale);
  const stack = stacked ? ' fk-vote-stack' : '';
  if (!presentation.isButton) {
    const value = presentation.valueKey ? t(presentation.valueKey) : '';
    return (
      `<span class="fk-vote-closed${stack}" data-fk-vote="${presentation.kind}" part="vote">` +
      `${icon('arrowUp')}<span aria-hidden="true">${escapeHtml(count)}</span>` +
      `<span class="fk-sr-only">${escapeHtml(label)}, ${escapeHtml(value)}</span></span>`
    );
  }
  const hintId = `${ctx.id}-vote-hint-${idPart(feedback.id)}`;
  const disabled = presentation.isActionable ? '' : ' aria-disabled="true"';
  return (
    `<button type="button" class="fk-vote${stack}" part="vote" aria-pressed="${presentation.isFilled}"${disabled} ` +
    `aria-label="${escapeHtml(label)}" aria-describedby="${hintId}"${busy ? ' aria-busy="true"' : ''} ` +
    `data-fk-vote="${presentation.kind}" data-fk-action="vote" data-fk-id="${escapeHtml(feedback.id)}" ` +
    `data-fk-key="vote:${escapeHtml(feedback.id)}">` +
    `${icon('arrowUp')}<span aria-hidden="true">${escapeHtml(count)}</span></button>` +
    `<span class="fk-sr-only" id="${hintId}">${escapeHtml(presentation.hintKey ? t(presentation.hintKey) : '')}</span>`
  );
}

// ---------------------------------------------------------------------------
// Showcase card
// ---------------------------------------------------------------------------

function renderFacts(ctx: RenderContext, feedback: Feedback): string {
  const facts: string[] = [];
  if (ctx.flags.showCategoryBadge) {
    facts.push(
      `<span class="fk-fact" data-fk-fact="category">${icon(categoryIconName(feedback.category))}` +
        `<span>${escapeHtml(categoryName(feedback.category, ctx.t))}</span></span>`
    );
  }
  if (ctx.flags.showCommentCount && feedback.commentCount > 0) {
    facts.push(
      `<span class="fk-fact" data-fk-fact="comments">${icon('comment')}` +
        `<span aria-hidden="true">${escapeHtml(formatCount(feedback.commentCount, ctx.locale))}</span>` +
        `<span class="fk-sr-only">${escapeHtml(commentCountText(feedback.commentCount, ctx.t, ctx.locale))}</span></span>`
    );
  }
  return facts.length ? `<div class="fk-facts">${facts.join('')}</div>` : '';
}

function safeToken(value: string): string {
  return /^[a-z0-9_-]+$/i.test(value) ? value : 'unknown';
}

export function renderShowcaseCard(ctx: RenderContext, feedback: Feedback, busy: boolean): string {
  const id = escapeHtml(feedback.id);
  const titleId = `${ctx.id}-title-${idPart(feedback.id)}`;
  const eyebrow = ctx.flags.showStatusBadge
    ? `<p class="fk-eyebrow" data-status="${safeToken(feedback.status)}">${statusGlyph(feedback.status)}` +
      `<span>${escapeHtml(statusName(feedback.status, ctx.t))}</span></p>`
    : '';
  const titleInner = ctx.selectable
    ? `<button type="button" class="fk-card-link" data-fk-action="select" data-fk-id="${id}" data-fk-key="select:${id}">` +
      `${escapeHtml(feedback.title)}</button>`
    : escapeHtml(feedback.title);
  const facts = renderFacts(ctx, feedback);
  const vote = renderVote(ctx, feedback, busy);
  const footer = facts || vote ? `<div class="fk-footer">${facts || '<span></span>'}${vote}</div>` : '';
  return (
    `<li class="fk-item" data-fk-item="${id}">` +
    `<article class="fk-card${ctx.selectable ? ' fk-card-selectable' : ''}" part="card" aria-labelledby="${titleId}">` +
    eyebrow +
    heading(ctx.headingLevel + 1, 'fk-title', titleId, titleInner) +
    (feedback.description ? `<p class="fk-description">${escapeHtml(feedback.description)}</p>` : '') +
    footer +
    `</article></li>`
  );
}

// ---------------------------------------------------------------------------
// Classic row
// ---------------------------------------------------------------------------

export function renderClassicRow(ctx: RenderContext, feedback: Feedback, busy: boolean): string {
  const id = escapeHtml(feedback.id);
  const titleId = `${ctx.id}-title-${idPart(feedback.id)}`;
  const titleInner = ctx.selectable
    ? `<button type="button" class="fk-card-link" data-fk-action="select" data-fk-id="${id}" data-fk-key="select:${id}">` +
      `${escapeHtml(feedback.title)}</button>`
    : escapeHtml(feedback.title);
  const badges: string[] = [];
  if (ctx.flags.showStatusBadge) {
    badges.push(
      `<span class="fk-badge" data-status="${safeToken(feedback.status)}">${escapeHtml(statusName(feedback.status, ctx.t))}</span>`
    );
  }
  if (ctx.flags.showCategoryBadge) {
    badges.push(
      `<span class="fk-badge" data-category="${safeToken(feedback.category)}">` +
        `${escapeHtml(categoryName(feedback.category, ctx.t))}</span>`
    );
  }
  if (ctx.flags.showCommentCount && feedback.commentCount > 0) {
    badges.push(
      `<span class="fk-classic-comments">${icon('comment')}` +
        `<span>${escapeHtml(commentCountText(feedback.commentCount, ctx.t, ctx.locale))}</span></span>`
    );
  }
  return (
    `<li class="fk-item" data-fk-item="${id}">` +
    `<article class="fk-card fk-classic-row${ctx.selectable ? ' fk-card-selectable' : ''}" part="card" ` +
    `aria-labelledby="${titleId}"><div>` +
    heading(ctx.headingLevel + 1, 'fk-classic-title', titleId, titleInner) +
    (feedback.description ? `<p class="fk-classic-description">${escapeHtml(feedback.description)}</p>` : '') +
    (badges.length ? `<div class="fk-badges">${badges.join('')}</div>` : '') +
    `</div>${renderVote(ctx, feedback, busy, true)}</article></li>`
  );
}

export function renderClassicSortRow(ctx: RenderContext, sort: FeedbackSort): string {
  const chips = SORT_OPTIONS.map((option) => {
    const selected = option.value === sort;
    return (
      `<button type="button" class="fk-chip" aria-pressed="${selected}" data-fk-action="sort" ` +
      `data-fk-value="${option.value}" data-fk-key="chip:${option.value}">` +
      `${selected ? icon('check') : ''}<span>${escapeHtml(ctx.t(option.labelKey))}</span></button>`
    );
  }).join('');
  return (
    `<div class="fk-sort-row" role="group" aria-labelledby="${ctx.id}-sort-label">` +
    `<span class="fk-sort-label" id="${ctx.id}-sort-label">${escapeHtml(ctx.t('sort.label'))}</span>${chips}</div>`
  );
}

// ---------------------------------------------------------------------------
// Loading, empty and error states
// ---------------------------------------------------------------------------

/** Placeholder cards with the real card's anatomy, so nothing shifts when data arrives. */
export function renderSkeleton(ctx: RenderContext, count = 3): string {
  const card =
    `<li class="fk-item"><div class="fk-card fk-skeleton">` +
    `<span class="fk-bone fk-bone-eyebrow"></span><span class="fk-bone fk-bone-title"></span>` +
    `<span class="fk-bone fk-bone-line"></span><span class="fk-bone fk-bone-line fk-bone-line-short"></span>` +
    `<div class="fk-footer"><span class="fk-bone fk-bone-fact"></span><span class="fk-bone fk-bone-vote"></span></div>` +
    `</div></li>`;
  return (
    `<div role="status" data-fk-state="loading"><span class="fk-sr-only">${escapeHtml(ctx.t('list.loading'))}</span>` +
    `<ul class="fk-list" aria-hidden="true">${card.repeat(count)}</ul></div>`
  );
}

function stateBlock(ctx: RenderContext, kind: string, iconName: 'filter' | 'lightbulb' | 'close', title: string, text: string, action?: { name: string; label: string }): string {
  return (
    `<div class="fk-state" data-fk-state="${kind}">${icon(iconName, 'fk-icon fk-state-icon')}` +
    heading(ctx.headingLevel + 1, 'fk-state-title', '', escapeHtml(title)) +
    `<p class="fk-state-text">${escapeHtml(text)}</p>` +
    (action
      ? `<button type="button" class="fk-btn fk-btn-tonal" data-fk-action="${action.name}" data-fk-key="state-${action.name}">` +
        `${escapeHtml(action.label)}</button>`
      : '') +
    `</div>`
  );
}

export function renderFilteredEmpty(ctx: RenderContext): string {
  return stateBlock(ctx, 'filtered-empty', 'filter', ctx.t('list.filter.empty.title'), ctx.t('list.filter.empty.description'), {
    name: 'clear-filters',
    label: ctx.t('list.filter.clearAll')
  });
}

export function renderProjectEmpty(ctx: RenderContext): string {
  return stateBlock(ctx, 'empty', 'lightbulb', ctx.t('feedback.list.empty'), ctx.t('feedback.list.empty.description'));
}

export function renderErrorState(ctx: RenderContext, message: string): string {
  return stateBlock(ctx, 'error', 'close', ctx.t('feedback.list.error.generic'), message, {
    name: 'retry',
    label: ctx.t('list.retry')
  });
}

export function renderInlineError(ctx: RenderContext): string {
  return (
    `<div class="fk-inline-error" role="alert" data-fk-state="inline-error"><span>${escapeHtml(ctx.t('feedback.list.error.generic'))}</span>` +
    `<button type="button" class="fk-btn fk-btn-text" data-fk-action="retry" data-fk-key="inline-retry">` +
    `${escapeHtml(ctx.t('list.retry'))}</button></div>`
  );
}
