/**
 * `mountFeedbackList`: renders a FeedbackKit feedback list into any element.
 *
 * Framework-free. The list lives in a shadow root by default, so host styles do
 * not leak in and the embed's styles do not leak out; `::part()` names (`card`,
 * `vote`, `menu-button`, `menu`) are the styling hooks. Data comes from a
 * `FeedbackKit` client or from host-supplied `items`.
 */

import type { FeedbackKit } from '../client';
import { Feedback, FeedbackCategory, FeedbackSort, FeedbackStatus, VoteResponse } from '../models/types';
import { MenuModel, RenderContext, renderClassicRow, renderClassicSortRow, renderErrorState, renderFilterRow, renderFilteredEmpty, renderHeader, renderInlineError, renderProjectEmpty, renderShowcaseCard, renderSkeleton } from './render';
import {
  FeedbackListStyle,
  FeedbackListUserFilter,
  applyUserFilter,
  canVoteOnStatus,
  filterSummaryText,
  isFiltered,
  sortFeedback
} from './state';
import { FeedbackListStrings, createTranslator, localeDirection } from './strings';
import { BASE_CSS } from './styles';
import { FeedbackListColorScheme, FeedbackListTheme, paletteCss, tokenCss } from './theme';
import { focusMenuItem, menuItems, typeaheadIndex } from './menu';

export interface FeedbackListOptions {
  /** Loads the list and sends votes. Omit it to render `items` instead. */
  client?: FeedbackKit;
  /** Host-supplied feedback, used when there is no `client`. */
  items?: Feedback[];
  /** `'showcase'` (default) is the FEEDBACK01 card list; `'classic'` is the compact legacy row. */
  listStyle?: FeedbackListStyle;
  /** `'auto'` (default) follows `prefers-color-scheme`. */
  colorScheme?: FeedbackListColorScheme;
  theme?: FeedbackListTheme;
  /** BCP 47 locale for copy and number formatting. Defaults to the browser's. */
  locale?: string;
  /** Text direction. Defaults to the locale's script direction. */
  dir?: 'ltr' | 'rtl';
  /** Per-key copy overrides. */
  strings?: FeedbackListStrings;
  /** List heading. `null` hides it, for hosts that title the page themselves. */
  title?: string | null;
  /** Level of the list heading; card titles are one level below. Default 2. */
  headingLevel?: number;
  /** Initial sort. Default `FeedbackSort.Votes`. */
  sort?: FeedbackSort;
  /** Host-fixed filters. A fixed filter is applied to every load and its menu section is hidden. */
  filterByStatus?: FeedbackStatus;
  filterByCategory?: FeedbackCategory;
  /** Show the Sort & Filter menu (Showcase) or sort chips (Classic). Default true. */
  showSortMenu?: boolean;
  showStatusFilter?: boolean;
  showCategoryFilter?: boolean;
  showStatusBadge?: boolean;
  showCategoryBadge?: boolean;
  showCommentCount?: boolean;
  showVoteCount?: boolean;
  allowUndoVote?: boolean;
  /** Called when a card is activated. Cards are only interactive when this is set. */
  onSelect?: (feedback: Feedback) => void;
  /**
   * Called for a vote or unvote. With a `client` the vote is sent for you and this
   * is a notification; without one, return the server's `VoteResponse` (or nothing
   * to keep the optimistic count). A rejection rolls the vote back.
   */
  onVote?: (feedback: Feedback, vote: boolean) => Promise<VoteResponse | void> | VoteResponse | void;
  onSortChange?: (sort: FeedbackSort) => void;
  onFilterChange?: (filter: FeedbackListUserFilter) => void;
  onError?: (error: unknown) => void;
  /** Render into a shadow root (default). `false` renders into the light DOM. */
  shadow?: boolean;
}

export interface FeedbackListHandle {
  /** The element the list renders into (the shadow host when `shadow` is on). */
  readonly element: HTMLElement;
  /** Merge new options and re-render. Changing `client`, `items` or fixed filters reloads. */
  update(options: Partial<FeedbackListOptions>): void;
  /** Reload from the client. A no-op for `items`. */
  refresh(): Promise<void>;
  /** The current session filter. */
  getFilter(): FeedbackListUserFilter;
  destroy(): void;
}

interface State {
  items: Feedback[];
  loading: boolean;
  loaded: boolean;
  error: unknown;
  sort: FeedbackSort;
  filter: FeedbackListUserFilter;
  menuOpen: boolean;
  busy: Set<string>;
}

let instanceCount = 0;

function errorMessage(error: unknown): string {
  return error instanceof Error && error.message ? error.message : String(error ?? '');
}

export function mountFeedbackList(container: HTMLElement, initial: FeedbackListOptions = {}): FeedbackListHandle {
  if (!container || typeof container.appendChild !== 'function') {
    throw new TypeError('mountFeedbackList: container must be an element');
  }
  instanceCount += 1;
  const id = `fk${instanceCount}`;
  let options: FeedbackListOptions = { ...initial };
  const doc = container.ownerDocument;

  const host = doc.createElement('div');
  host.className = 'feedbackkit-list';
  container.appendChild(host);
  const useShadow = options.shadow !== false && typeof host.attachShadow === 'function';
  const scope: ShadowRoot | HTMLElement = useShadow ? host.attachShadow({ mode: 'open' }) : host;

  const baseStyle = doc.createElement('style');
  baseStyle.textContent = useShadow ? BASE_CSS : BASE_CSS.replace(':host { display: block; }', '');
  const themeStyle = doc.createElement('style');
  const root = doc.createElement('div');
  root.className = 'fk-root';
  root.dataset.fkInstance = id;
  root.innerHTML =
    `<div data-fk-slot="header"></div>` +
    `<div class="fk-filter-row" data-fk-slot="filter"></div>` +
    `<div data-fk-slot="body"></div>` +
    `<div class="fk-sr-only" role="status" aria-live="polite" data-fk-slot="announcer"></div>`;
  scope.append(baseStyle, themeStyle, root);
  const slot = (name: string) => root.querySelector(`[data-fk-slot="${name}"]`) as HTMLElement;

  const state: State = {
    items: [],
    loading: false,
    loaded: false,
    error: null,
    sort: options.sort ?? FeedbackSort.Votes,
    filter: {},
    menuOpen: false,
    busy: new Set()
  };
  let loadSequence = 0;
  let destroyed = false;

  const flag = (value: boolean | undefined, fallback = true) => value ?? fallback;
  const offerStatus = () => flag(options.showStatusFilter) && options.filterByStatus === undefined;
  const offerCategory = () => flag(options.showCategoryFilter) && options.filterByCategory === undefined;
  const locale = () => options.locale ?? (doc.defaultView?.navigator?.language || undefined);
  const translator = () => createTranslator(locale(), options.strings);

  function context(): RenderContext {
    return {
      id,
      t: translator(),
      locale: locale(),
      selectable: typeof options.onSelect === 'function',
      headingLevel: options.headingLevel ?? 2,
      flags: {
        showStatusBadge: flag(options.showStatusBadge),
        showCategoryBadge: flag(options.showCategoryBadge),
        showCommentCount: flag(options.showCommentCount),
        showVoteCount: flag(options.showVoteCount),
        allowUndoVote: flag(options.allowUndoVote)
      }
    };
  }

  function applyTheme() {
    const scheme = options.colorScheme ?? 'auto';
    themeStyle.textContent = paletteCss(scheme, options.theme) + '\n' + tokenCss(options.theme);
    root.dataset.scheme = scheme;
    root.dataset.listStyle = options.listStyle === 'classic' ? 'classic' : 'showcase';
    root.setAttribute('dir', options.dir ?? (options.locale ? localeDirection(options.locale) : inheritedDirection()));
    const lang = locale();
    if (lang) root.setAttribute('lang', lang);
  }

  function inheritedDirection(): 'ltr' | 'rtl' {
    const computed = doc.defaultView?.getComputedStyle?.(container).direction;
    if (computed === 'rtl' || computed === 'ltr') return computed;
    return container.closest('[dir]')?.getAttribute('dir') === 'rtl' ? 'rtl' : 'ltr';
  }

  /** The rows on screen: fixed filters, then the session filter, then (for `items`) the sort. */
  function visibleItems(): Feedback[] {
    let rows = state.items;
    if (!options.client) {
      rows = applyUserFilter(rows, { status: options.filterByStatus, category: options.filterByCategory });
      rows = sortFeedback(rows, state.sort);
    }
    return applyUserFilter(rows, state.filter);
  }

  function activeKey(): string | null {
    const active = (useShadow ? (scope as ShadowRoot).activeElement : doc.activeElement) as HTMLElement | null;
    if (!active || !root.contains(active)) return null;
    return active.getAttribute('data-fk-key');
  }

  function focusKey(key: string | null) {
    if (!key) return;
    const target = root.querySelector<HTMLElement>(`[data-fk-key="${key.replace(/"/g, '\\"')}"]`);
    target?.focus({ preventScroll: true });
  }

  function render() {
    if (destroyed) return;
    const focused = activeKey();
    const ctx = context();
    const classic = options.listStyle === 'classic';
    const showMenu = flag(options.showSortMenu);

    const menu: MenuModel | null =
      !classic && showMenu
        ? { open: state.menuOpen, sort: state.sort, filter: state.filter, offerStatus: offerStatus(), offerCategory: offerCategory() }
        : null;
    const title = options.title === undefined ? ctx.t('feedback.list.title') : options.title;
    slot('header').innerHTML = renderHeader(ctx, title, menu);
    slot('filter').innerHTML = classic ? '' : renderFilterRow(ctx, state.filter);

    const body = slot('body');
    body.setAttribute('aria-busy', String(state.loading));
    const rows = visibleItems();
    const parts: string[] = [];
    if (classic && showMenu && state.items.length > 0) parts.push(renderClassicSortRow(ctx, state.sort));
    if (state.loading && state.items.length === 0) {
      parts.push(renderSkeleton(ctx));
    } else if (state.error && state.items.length === 0) {
      parts.push(renderErrorState(ctx, errorMessage(state.error)));
    } else {
      if (state.error) parts.push(renderInlineError(ctx));
      if (rows.length === 0 && isFiltered(state.filter)) {
        parts.push(renderFilteredEmpty(ctx));
      } else if (rows.length === 0 && state.loaded) {
        parts.push(renderProjectEmpty(ctx));
      } else if (rows.length > 0) {
        const row = classic ? renderClassicRow : renderShowcaseCard;
        const labelled = title === null ? '' : ` aria-labelledby="${id}-heading"`;
        parts.push(`<ul class="fk-list" role="list"${labelled}>${rows.map((f) => row(ctx, f, state.busy.has(f.id))).join('')}</ul>`);
      }
    }
    body.innerHTML = parts.join('');
    focusKey(focused);
  }

  function announce(message: string) {
    const announcer = slot('announcer');
    announcer.textContent = '';
    // A fresh text node after clearing is what makes repeated messages re-announce.
    doc.defaultView?.setTimeout(() => {
      if (!destroyed) announcer.textContent = message;
    }, 50);
  }

  async function load() {
    const client = options.client;
    if (!client) {
      state.items = [...(options.items ?? [])];
      state.loaded = true;
      state.loading = false;
      state.error = null;
      render();
      return;
    }
    const sequence = ++loadSequence;
    state.loading = true;
    render();
    try {
      const items = await client.feedback.list({
        sort: state.sort,
        status: options.filterByStatus,
        category: options.filterByCategory
      });
      if (sequence !== loadSequence || destroyed) return;
      state.items = items;
      state.error = null;
      state.loaded = true;
    } catch (error) {
      if (sequence !== loadSequence || destroyed) return;
      state.error = error;
      options.onError?.(error);
    }
    state.loading = false;
    render();
  }

  function replaceItem(next: Feedback) {
    state.items = state.items.map((item) => (item.id === next.id ? next : item));
  }

  async function toggleVote(feedbackId: string) {
    const current = state.items.find((item) => item.id === feedbackId);
    if (!current || state.busy.has(feedbackId) || !canVoteOnStatus(current.status)) return;
    const vote = !current.hasVoted;
    if (!vote && !flag(options.allowUndoVote)) return;
    const optimistic: Feedback = {
      ...current,
      hasVoted: vote,
      voteCount: Math.max(0, current.voteCount + (vote ? 1 : -1))
    };
    state.busy.add(feedbackId);
    replaceItem(optimistic);
    render();
    try {
      let response: VoteResponse | void;
      if (options.client) {
        response = vote ? await options.client.votes.vote(feedbackId) : await options.client.votes.unvote(feedbackId);
        await options.onVote?.(current, vote);
      } else {
        response = await options.onVote?.(current, vote);
      }
      if (response && typeof response.voteCount === 'number') {
        const latest = state.items.find((item) => item.id === feedbackId) ?? optimistic;
        replaceItem({ ...latest, voteCount: response.voteCount, hasVoted: response.hasVoted });
      }
    } catch (error) {
      const latest = state.items.find((item) => item.id === feedbackId);
      if (latest) replaceItem({ ...latest, hasVoted: current.hasVoted, voteCount: current.voteCount });
      announce(translator()('feedback.list.error.generic'));
      options.onError?.(error);
    } finally {
      state.busy.delete(feedbackId);
      render();
    }
  }

  function setSort(sort: FeedbackSort) {
    if (sort === state.sort) return;
    state.sort = sort;
    options.onSortChange?.(sort);
    if (options.client) void load();
    else render();
  }

  function setFilter(next: FeedbackListUserFilter) {
    state.filter = next;
    options.onFilterChange?.({ ...next });
    const summary = filterSummaryText(next, translator());
    if (summary) announce(summary);
  }

  function setMenuOpen(open: boolean, focus: 'first' | 'last' | 'button' | 'none' = 'none') {
    state.menuOpen = open;
    render();
    const menuEl = root.querySelector<HTMLElement>('.fk-menu');
    if (open && menuEl && (focus === 'first' || focus === 'last')) {
      const items = menuItems(menuEl);
      focusMenuItem(items, focus === 'first' ? 0 : items.length - 1);
    } else if (focus === 'button') {
      root.querySelector<HTMLElement>('[data-fk-key="menu-button"]')?.focus();
    }
  }

  function closeMenuToButton() {
    setMenuOpen(false, 'button');
  }

  function onClick(event: Event) {
    const target = (event.target as HTMLElement | null)?.closest<HTMLElement>('[data-fk-action]');
    if (!target || !root.contains(target)) return;
    const action = target.dataset.fkAction;
    const value = target.dataset.fkValue ?? '';
    switch (action) {
      case 'menu-toggle':
        setMenuOpen(!state.menuOpen, state.menuOpen ? 'none' : 'first');
        break;
      case 'sort':
        state.menuOpen = false;
        setSort(value as FeedbackSort);
        if (target.classList.contains('fk-menu-item')) closeMenuToButton();
        break;
      case 'status':
        setFilter({ ...state.filter, status: value ? (value as FeedbackStatus) : undefined });
        closeMenuToButton();
        break;
      case 'category':
        setFilter({ ...state.filter, category: value ? (value as FeedbackCategory) : undefined });
        closeMenuToButton();
        break;
      case 'clear-filters':
        setFilter({});
        closeMenuToButton();
        break;
      case 'retry':
        void load();
        break;
      case 'vote':
        event.stopPropagation();
        if (target.getAttribute('aria-disabled') !== 'true') void toggleVote(target.dataset.fkId ?? '');
        break;
      case 'select': {
        const feedback = state.items.find((item) => item.id === target.dataset.fkId);
        if (feedback) options.onSelect?.(feedback);
        break;
      }
    }
  }

  function onKeydown(event: KeyboardEvent) {
    const target = event.target as HTMLElement | null;
    if (!target) return;
    if (target.dataset.fkAction === 'menu-toggle') {
      if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
        event.preventDefault();
        setMenuOpen(true, event.key === 'ArrowDown' ? 'first' : 'last');
      } else if (event.key === 'Escape' && state.menuOpen) {
        event.preventDefault();
        setMenuOpen(false);
      }
      return;
    }
    const menuEl = target.closest<HTMLElement>('.fk-menu');
    if (!menuEl) return;
    const items = menuItems(menuEl);
    const index = items.indexOf(target);
    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault();
        focusMenuItem(items, (index + 1) % items.length);
        break;
      case 'ArrowUp':
        event.preventDefault();
        focusMenuItem(items, (index - 1 + items.length) % items.length);
        break;
      case 'Home':
        event.preventDefault();
        focusMenuItem(items, 0);
        break;
      case 'End':
        event.preventDefault();
        focusMenuItem(items, items.length - 1);
        break;
      case 'Escape':
        event.preventDefault();
        closeMenuToButton();
        break;
      case 'Tab':
        state.menuOpen = false;
        root.querySelector('.fk-menu')?.setAttribute('hidden', '');
        root.querySelector('[data-fk-key="menu-button"]')?.setAttribute('aria-expanded', 'false');
        break;
      default:
        if (event.key.length === 1 && !event.ctrlKey && !event.metaKey && !event.altKey) {
          const next = typeaheadIndex(items, index, event.key);
          if (next >= 0) focusMenuItem(items, next);
        }
    }
  }

  function onDocumentPointerDown(event: Event) {
    if (!state.menuOpen) return;
    const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
    const anchor = root.querySelector('.fk-menu-anchor');
    if (anchor && (path.includes(anchor) || anchor.contains(event.target as Node))) return;
    setMenuOpen(false);
  }

  root.addEventListener('click', onClick);
  root.addEventListener('keydown', onKeydown);
  doc.addEventListener('pointerdown', onDocumentPointerDown, true);

  applyTheme();
  void load();

  return {
    element: host,
    update(next) {
      const reload =
        ('client' in next && next.client !== options.client) ||
        ('items' in next && next.items !== options.items) ||
        ('filterByStatus' in next && next.filterByStatus !== options.filterByStatus) ||
        ('filterByCategory' in next && next.filterByCategory !== options.filterByCategory);
      options = { ...options, ...next };
      if (next.sort !== undefined && next.sort !== state.sort) {
        state.sort = next.sort;
        if (options.client) {
          applyTheme();
          void load();
          return;
        }
      }
      if (!offerStatus() && state.filter.status !== undefined) state.filter = { ...state.filter, status: undefined };
      if (!offerCategory() && state.filter.category !== undefined) state.filter = { ...state.filter, category: undefined };
      applyTheme();
      if (reload) void load();
      else render();
    },
    refresh: () => load(),
    getFilter: () => ({ ...state.filter }),
    destroy() {
      destroyed = true;
      root.removeEventListener('click', onClick);
      root.removeEventListener('keydown', onKeydown);
      doc.removeEventListener('pointerdown', onDocumentPointerDown, true);
      host.remove();
    }
  };
}
