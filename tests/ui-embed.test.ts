// @vitest-environment jsdom
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { fireEvent, getByRole, queryByRole, waitFor, within } from '@testing-library/dom';
import userEvent from '@testing-library/user-event';
import type { FeedbackKit } from '../src/client';
import { Feedback, FeedbackCategory, FeedbackSort, FeedbackStatus, VoteResponse } from '../src/models/types';
import { FeedbackListHandle, FeedbackListOptions, mountFeedbackList } from '../src/ui';
import { BASE_CSS } from '../src/ui/styles';

/**
 * Feedback list embed (`feedbackkit-js/ui`) in a DOM: the FEEDBACK01 Showcase card
 * and vote control, the Sort & Filter menu (ARIA menu button pattern, keyboard),
 * the "Filtered by" row, load/empty/error states, Classic, theming, RTL and the
 * shadow-root default. Most cases render into the light DOM (`shadow: false`) so
 * accessible-name lookups resolve; one case pins the shadow-root default itself.
 */

function feedback(overrides: Partial<Feedback> = {}): Feedback {
  return {
    id: 'f1',
    title: 'Dark mode',
    description: 'Please add a dark theme.',
    status: FeedbackStatus.Approved,
    category: FeedbackCategory.FeatureRequest,
    userId: 'u1',
    voteCount: 12,
    hasVoted: false,
    commentCount: 0,
    createdAt: '2026-10-01T00:00:00Z',
    updatedAt: '2026-10-01T00:00:00Z',
    ...overrides
  };
}

const ITEMS: Feedback[] = [
  feedback({ id: 'a', title: 'Offline sync', description: 'Work without a connection.', status: FeedbackStatus.InProgress, category: FeedbackCategory.Improvement, voteCount: 42, commentCount: 3, createdAt: '2026-03-01T00:00:00Z' }),
  feedback({ id: 'b', title: 'Crash on launch', description: 'The app crashes on iPad.', status: FeedbackStatus.Pending, category: FeedbackCategory.BugReport, voteCount: 7, createdAt: '2026-09-01T00:00:00Z' }),
  feedback({ id: 'c', title: 'Widgets', description: 'Home screen widgets.', status: FeedbackStatus.Completed, category: FeedbackCategory.FeatureRequest, voteCount: 1, hasVoted: true, commentCount: 1, createdAt: '2026-01-01T00:00:00Z' })
];

let container: HTMLElement;
let handle: FeedbackListHandle | undefined;

function mount(options: FeedbackListOptions = {}) {
  handle = mountFeedbackList(container, { shadow: false, locale: 'en', items: ITEMS, ...options });
  return handle;
}

function mockClient(list: () => Promise<Feedback[]> = async () => ITEMS) {
  const client = {
    feedback: { list: vi.fn(list) },
    votes: {
      vote: vi.fn(async (id: string): Promise<VoteResponse> => ({ feedbackId: id, voteCount: 100, hasVoted: true })),
      unvote: vi.fn(async (id: string): Promise<VoteResponse> => ({ feedbackId: id, voteCount: 99, hasVoted: false }))
    }
  };
  return client as typeof client & FeedbackKit;
}

const cards = () => Array.from(container.querySelectorAll<HTMLElement>('article.fk-card'));
const card = (title: string) => cards().find((el) => el.querySelector('.fk-title, .fk-classic-title')?.textContent === title)!;
const menuButton = () => getByRole(container, 'button', { name: 'Sort & Filter' });

beforeEach(() => {
  document.documentElement.style.fontSize = '';
  container = document.createElement('div');
  document.body.appendChild(container);
});

afterEach(() => {
  handle?.destroy();
  handle = undefined;
  container.remove();
});

describe('Showcase card (FEEDBACK01 §6.3)', () => {
  it('renders one article per request, labelled by its heading, in the given order', () => {
    mount();
    expect(getByRole(container, 'heading', { level: 2, name: 'Feedback' })).toBeTruthy();
    const list = getByRole(container, 'list', { name: 'Feedback' });
    const articles = within(list).getAllByRole('article');
    expect(articles.map((el) => el.getAttribute('aria-labelledby') && document.getElementById(el.getAttribute('aria-labelledby')!)?.textContent)).toEqual([
      'Offline sync',
      'Crash on launch',
      'Widgets'
    ]);
    expect(within(articles[0]).getByRole('heading', { level: 3, name: 'Offline sync' })).toBeTruthy();
  });

  it('shows the status eyebrow with a shape glyph, before the title', () => {
    mount();
    const eyebrow = card('Offline sync').querySelector('.fk-eyebrow')!;
    expect(eyebrow.textContent).toBe('In Progress');
    expect(eyebrow.getAttribute('data-status')).toBe('in_progress');
    expect(eyebrow.querySelector('[data-status-glyph="in_progress"]')?.getAttribute('aria-hidden')).toBe('true');
    expect(eyebrow.compareDocumentPosition(card('Offline sync').querySelector('.fk-title')!)).toBe(Node.DOCUMENT_POSITION_FOLLOWING);
  });

  it('never truncates the description', () => {
    const long = 'A very long description. '.repeat(40).trim();
    mount({ items: [feedback({ description: long })] });
    const description = container.querySelector('.fk-description')!;
    expect(description.textContent).toBe(long);
    expect(BASE_CSS.match(/\.fk-description \{[^}]*\}/)?.[0]).not.toMatch(/line-clamp|text-overflow|max-block-size/);
  });

  it("uses the Material 'tune' glyph for Improvement and names the category", () => {
    mount();
    const fact = card('Offline sync').querySelector('[data-fk-fact="category"]')!;
    expect(fact.textContent).toBe('Improvement');
    expect(fact.querySelector('[data-icon]')?.getAttribute('data-icon')).toBe('tune');
    expect(card('Crash on launch').querySelector('[data-fk-fact="category"] [data-icon]')?.getAttribute('data-icon')).toBe('bug');
    expect(card('Widgets').querySelector('[data-fk-fact="category"] [data-icon]')?.getAttribute('data-icon')).toBe('lightbulb');
  });

  it('shows the comment count only above zero, with a spoken unit', () => {
    mount();
    expect(card('Offline sync').querySelector('[data-fk-fact="comments"]')?.textContent).toBe('33 comments');
    expect(within(card('Offline sync')).getByText('3 comments').className).toBe('fk-sr-only');
    expect(card('Crash on launch').querySelector('[data-fk-fact="comments"]')).toBeNull();
  });

  it('honours the show* flags and drops an empty footer', () => {
    mount({ showStatusBadge: false, showCategoryBadge: false, showCommentCount: false, showVoteCount: false });
    expect(container.querySelector('.fk-eyebrow')).toBeNull();
    expect(container.querySelector('.fk-footer')).toBeNull();
    expect(cards()[0].firstElementChild?.classList.contains('fk-title')).toBe(true);
  });

  it('is a single activation target only when onSelect is set', async () => {
    const onSelect = vi.fn();
    mount();
    expect(container.querySelector('.fk-card-link')).toBeNull();
    handle!.update({ onSelect });
    const link = getByRole(card('Crash on launch'), 'button', { name: 'Crash on launch' });
    await userEvent.click(link);
    expect(onSelect).toHaveBeenCalledWith(expect.objectContaining({ id: 'b' }));
  });
});

describe('vote control (FEEDBACK01 §6.4)', () => {
  it('votable: a toggle button named by its count, not pressed, with a hint', () => {
    mount();
    const vote = getByRole(card('Offline sync'), 'button', { name: '42 votes' });
    expect(vote.getAttribute('aria-pressed')).toBe('false');
    expect(vote.getAttribute('data-fk-vote')).toBe('votable');
    expect(document.getElementById(vote.getAttribute('aria-describedby')!)?.textContent).toBe('Adds your vote');
    expect(vote.textContent).toBe('42');
  });

  it('closed: plain text with the count and "Voting is closed", no control', () => {
    mount();
    const closed = card('Widgets');
    expect(queryByRole(closed, 'button', { name: /vote/ })).toBeNull();
    expect(closed.querySelector('.fk-vote-closed .fk-sr-only')?.textContent).toBe('1 vote, Voting is closed');
  });

  it('voted with undo allowed: pressed, and the hint says it removes the vote', () => {
    mount({ items: [feedback({ hasVoted: true })] });
    const vote = getByRole(container, 'button', { name: '12 votes' });
    expect(vote.getAttribute('aria-pressed')).toBe('true');
    expect(vote.hasAttribute('aria-disabled')).toBe(false);
    expect(document.getElementById(vote.getAttribute('aria-describedby')!)?.textContent).toBe('Removes your vote');
  });

  it('voted without undo: pressed, aria-disabled but focusable, and inert', async () => {
    const onVote = vi.fn();
    mount({ items: [feedback({ hasVoted: true })], allowUndoVote: false, onVote });
    const vote = getByRole(container, 'button', { name: '12 votes' });
    expect(vote.getAttribute('aria-disabled')).toBe('true');
    expect(vote.hasAttribute('disabled')).toBe(false);
    expect(document.getElementById(vote.getAttribute('aria-describedby')!)?.textContent).toBe("You've voted. Votes can't be removed");
    await userEvent.click(vote);
    expect(onVote).not.toHaveBeenCalled();
    expect(vote.getAttribute('aria-pressed')).toBe('true');
  });

  it('votes through the client: optimistic, busy, then the server count, focus kept', async () => {
    const client = mockClient();
    let release!: () => void;
    client.votes.vote.mockImplementation(
      (id: string) => new Promise((resolve) => (release = () => resolve({ feedbackId: id, voteCount: 50, hasVoted: true })))
    );
    const onVote = vi.fn();
    mount({ client, items: undefined, onVote });
    await waitFor(() => expect(cards()).toHaveLength(3));
    await userEvent.click(getByRole(card('Offline sync'), 'button', { name: '42 votes' }));
    const busy = getByRole(card('Offline sync'), 'button', { name: '43 votes' });
    expect(busy.getAttribute('aria-pressed')).toBe('true');
    expect(busy.getAttribute('aria-busy')).toBe('true');
    expect(client.votes.vote).toHaveBeenCalledWith('a');
    release();
    await waitFor(() => expect(getByRole(card('Offline sync'), 'button', { name: '50 votes' })).toBeTruthy());
    expect(document.activeElement).toBe(getByRole(card('Offline sync'), 'button', { name: '50 votes' }));
    expect(onVote).toHaveBeenCalledWith(expect.objectContaining({ id: 'a' }), true);
  });

  it('unvotes through the client', async () => {
    const client = mockClient(async () => [feedback({ id: 'x', hasVoted: true, voteCount: 5 })]);
    mount({ client, items: undefined });
    await waitFor(() => expect(cards()).toHaveLength(1));
    await userEvent.click(getByRole(container, 'button', { name: '5 votes' }));
    expect(client.votes.unvote).toHaveBeenCalledWith('x');
    await waitFor(() => expect(getByRole(container, 'button', { name: '99 votes' }).getAttribute('aria-pressed')).toBe('false'));
  });

  it('rolls back and announces a failed vote', async () => {
    const client = mockClient();
    const failure = new Error('offline');
    client.votes.vote.mockRejectedValue(failure);
    const onError = vi.fn();
    mount({ client, items: undefined, onError });
    await waitFor(() => expect(cards()).toHaveLength(3));
    await userEvent.click(getByRole(card('Crash on launch'), 'button', { name: '7 votes' }));
    await waitFor(() => expect(getByRole(card('Crash on launch'), 'button', { name: '7 votes' }).getAttribute('aria-pressed')).toBe('false'));
    expect(onError).toHaveBeenCalledWith(failure);
    await waitFor(() => expect(getByRole(container, 'status', { name: '' }).textContent).toBe('Something went wrong'));
  });

  it('without a client, applies the response onVote returns', async () => {
    const onVote = vi.fn(async (f: Feedback, vote: boolean) => ({ feedbackId: f.id, voteCount: 8, hasVoted: vote }));
    mount({ onVote });
    await userEvent.click(getByRole(card('Crash on launch'), 'button', { name: '7 votes' }));
    expect(onVote).toHaveBeenCalledWith(expect.objectContaining({ id: 'b' }), true);
    await waitFor(() => expect(getByRole(card('Crash on launch'), 'button', { name: '8 votes' })).toBeTruthy());
  });

  it('formats counts for the locale', () => {
    mount({ locale: 'de', items: [feedback({ voteCount: 1234 })] });
    expect(getByRole(container, 'button', { name: '1.234 Stimmen' }).textContent).toBe('1.234');
  });
});

describe('Sort & Filter menu (FEEDBACK01 §6.6)', () => {
  it('is a menu button that opens a labelled menu and focuses the first item', async () => {
    mount();
    const button = menuButton();
    expect(button.getAttribute('aria-haspopup')).toBe('menu');
    expect(button.getAttribute('aria-expanded')).toBe('false');
    expect(document.getElementById(button.getAttribute('aria-describedby')!)?.textContent).toBe('Most Votes');
    await userEvent.click(button);
    expect(menuButton().getAttribute('aria-expanded')).toBe('true');
    const menu = getByRole(container, 'menu', { name: 'Sort & Filter' });
    expect(within(menu).getAllByRole('group').map((g) => g.getAttribute('aria-label'))).toEqual(['Sort By', 'Status', 'Category']);
    expect(document.activeElement).toBe(within(menu).getByRole('menuitemradio', { name: 'Most Votes' }));
    expect(within(menu).getByRole('menuitemradio', { name: 'Most Votes' }).getAttribute('aria-checked')).toBe('true');
    expect(within(menu).getAllByRole('menuitemradio')).toHaveLength(4 + 7 + 5);
    expect(within(menu).queryByRole('menuitem', { name: 'Clear Filters' })).toBeNull();
  });

  it('supports arrows with wrap, Home/End, type-ahead, and Escape back to the button', async () => {
    const user = userEvent.setup();
    mount();
    menuButton().focus();
    await user.keyboard('{ArrowDown}');
    const menu = getByRole(container, 'menu');
    const items = within(menu).getAllByRole('menuitemradio');
    expect(document.activeElement).toBe(items[0]);
    await user.keyboard('{ArrowUp}');
    expect(document.activeElement).toBe(items[items.length - 1]);
    await user.keyboard('{Home}{ArrowDown}');
    expect(document.activeElement).toBe(items[1]);
    await user.keyboard('{End}');
    expect(document.activeElement).toBe(items[items.length - 1]);
    await user.keyboard('t');
    expect(document.activeElement?.textContent).toBe('TestFlight');
    await user.keyboard('{Escape}');
    expect(document.activeElement).toBe(menuButton());
    expect(getByRole(container, 'menu', { hidden: true }).hidden).toBe(true);
  });

  it('opens on ArrowUp at the last item, and closes on an outside click', async () => {
    const user = userEvent.setup();
    mount();
    menuButton().focus();
    await user.keyboard('{ArrowUp}');
    expect(document.activeElement?.textContent).toBe('Other');
    await user.click(document.body);
    expect(menuButton().getAttribute('aria-expanded')).toBe('false');
  });

  it('filtering shows the "Filtered by" row, activates the button, and Clear restores', async () => {
    const onFilterChange = vi.fn();
    mount({ onFilterChange });
    await userEvent.click(menuButton());
    await userEvent.click(getByRole(container, 'menuitemradio', { name: 'In Progress' }));
    expect(document.activeElement).toBe(menuButton());
    expect(cards().map((el) => el.querySelector('.fk-title')?.textContent)).toEqual(['Offline sync']);
    const row = container.querySelector('.fk-filter-row')!;
    expect(row.querySelector('.fk-filter-text')?.textContent).toBe('Filtered by In Progress');
    expect(row.querySelector('strong')?.textContent).toBe('In Progress');
    expect(menuButton().getAttribute('data-active')).toBe('true');
    expect(menuButton().classList.contains('fk-btn-filled')).toBe(true);
    expect(menuButton().querySelector('[data-icon]')?.getAttribute('data-icon')).toBe('filterActive');
    expect(document.getElementById(menuButton().getAttribute('aria-describedby')!)?.textContent).toBe('Filtered by In Progress');

    await userEvent.click(menuButton());
    await userEvent.click(getByRole(container, 'menuitemradio', { name: 'Improvements' }));
    expect(row.querySelector('.fk-filter-text')?.textContent).toBe('Filtered by Improvements · In Progress');
    expect(onFilterChange).toHaveBeenLastCalledWith({ status: FeedbackStatus.InProgress, category: FeedbackCategory.Improvement });

    await userEvent.click(getByRole(row as HTMLElement, 'button', { name: 'Clear filters' }));
    expect(row.textContent).toBe('');
    expect(cards()).toHaveLength(3);
    expect(document.activeElement).toBe(menuButton());
    expect(menuButton().getAttribute('data-active')).toBe('false');
  });

  it('offers Clear Filters in the menu only while filtered', async () => {
    mount();
    await userEvent.click(menuButton());
    await userEvent.click(getByRole(container, 'menuitemradio', { name: 'Bug Reports' }));
    await userEvent.click(menuButton());
    await userEvent.click(getByRole(container, 'menuitem', { name: 'Clear Filters' }));
    expect(handle!.getFilter()).toEqual({});
  });

  it('shows the filtered-empty state with its own Clear Filters', async () => {
    mount();
    await userEvent.click(menuButton());
    await userEvent.click(getByRole(container, 'menuitemradio', { name: 'Rejected' }));
    const empty = container.querySelector('[data-fk-state="filtered-empty"]') as HTMLElement;
    expect(within(empty).getByRole('heading', { name: 'No Matching Requests' })).toBeTruthy();
    await userEvent.click(within(empty).getByRole('button', { name: 'Clear Filters' }));
    expect(cards()).toHaveLength(3);
  });

  it('sorts host items locally and asks the server when there is a client', async () => {
    const onSortChange = vi.fn();
    mount({ onSortChange });
    await userEvent.click(menuButton());
    await userEvent.click(getByRole(container, 'menuitemradio', { name: 'Newest' }));
    expect(cards().map((el) => el.querySelector('.fk-title')?.textContent)).toEqual(['Crash on launch', 'Offline sync', 'Widgets']);
    expect(onSortChange).toHaveBeenCalledWith(FeedbackSort.Newest);
    handle!.destroy();

    const client = mockClient();
    mount({ client, items: undefined });
    await waitFor(() => expect(cards()).toHaveLength(3));
    await userEvent.click(menuButton());
    await userEvent.click(getByRole(container, 'menuitemradio', { name: 'Most Comments' }));
    expect(client.feedback.list).toHaveBeenLastCalledWith({ sort: FeedbackSort.Comments, status: undefined, category: undefined });
  });

  it('hides sections the host turned off or fixed, and applies a fixed filter', async () => {
    mount({ showCategoryFilter: false, filterByStatus: FeedbackStatus.Pending });
    expect(cards().map((el) => el.querySelector('.fk-title')?.textContent)).toEqual(['Crash on launch']);
    await userEvent.click(menuButton());
    expect(within(getByRole(container, 'menu')).getAllByRole('group').map((g) => g.getAttribute('aria-label'))).toEqual(['Sort By']);
  });

  it('can be hidden', () => {
    mount({ showSortMenu: false });
    expect(queryByRole(container, 'button', { name: 'Sort & Filter' })).toBeNull();
  });
});

describe('states (FEEDBACK01 §6.7)', () => {
  it('shows a skeleton with a spoken status while the first load is pending', async () => {
    let resolve!: (items: Feedback[]) => void;
    const client = mockClient(() => new Promise((r) => (resolve = r)));
    mount({ client, items: undefined });
    const loading = container.querySelector('[data-fk-state="loading"]')!;
    expect(loading.getAttribute('role')).toBe('status');
    expect(loading.textContent).toBe('Loading feedback');
    expect(loading.querySelector('.fk-list')?.getAttribute('aria-hidden')).toBe('true');
    expect(container.querySelector('[data-fk-slot="body"]')?.getAttribute('aria-busy')).toBe('true');
    resolve(ITEMS);
    await waitFor(() => expect(cards()).toHaveLength(3));
    expect(container.querySelector('[data-fk-slot="body"]')?.getAttribute('aria-busy')).toBe('false');
  });

  it('shows an error with Try Again, which reloads', async () => {
    const client = mockClient();
    client.feedback.list.mockRejectedValueOnce(new Error('Network down'));
    mount({ client, items: undefined });
    const error = await waitFor(() => {
      const el = container.querySelector<HTMLElement>('[data-fk-state="error"]');
      expect(el).not.toBeNull();
      return el!;
    });
    expect(error.textContent).toContain('Network down');
    await userEvent.click(within(error).getByRole('button', { name: 'Try Again' }));
    await waitFor(() => expect(cards()).toHaveLength(3));
    expect(client.feedback.list).toHaveBeenCalledTimes(2);
  });

  it('keeps rows and shows an inline alert when a reload fails', async () => {
    const client = mockClient();
    mount({ client, items: undefined });
    await waitFor(() => expect(cards()).toHaveLength(3));
    client.feedback.list.mockRejectedValueOnce(new Error('again'));
    await handle!.refresh();
    expect(getByRole(container, 'alert').textContent).toContain('Something went wrong');
    expect(cards()).toHaveLength(3);
  });

  it('ignores a stale response that lands after a newer one', async () => {
    const resolvers: Array<(items: Feedback[]) => void> = [];
    const client = mockClient(() => new Promise((r) => resolvers.push(r)));
    mount({ client, items: undefined });
    handle!.update({ sort: FeedbackSort.Newest });
    resolvers[1]([feedback({ id: 'new', title: 'Fresh' })]);
    await waitFor(() => expect(cards()).toHaveLength(1));
    resolvers[0](ITEMS);
    await Promise.resolve();
    await Promise.resolve();
    expect(cards().map((el) => el.querySelector('.fk-title')?.textContent)).toEqual(['Fresh']);
  });

  it('shows the project-empty state', () => {
    mount({ items: [] });
    expect(getByRole(container, 'heading', { name: 'No feedback yet' })).toBeTruthy();
  });
});

describe('Classic style', () => {
  it('renders compact rows with badges, stacked votes and sort chips, and no menu', async () => {
    mount({ listStyle: 'classic' });
    expect(container.querySelector('.fk-root')?.getAttribute('data-list-style')).toBe('classic');
    expect(queryByRole(container, 'button', { name: 'Sort & Filter' })).toBeNull();
    const group = getByRole(container, 'group', { name: 'Sort' });
    const chips = within(group).getAllByRole('button');
    expect(chips.map((chip) => [chip.textContent, chip.getAttribute('aria-pressed')])).toEqual([
      ['Most Votes', 'true'],
      ['Newest', 'false'],
      ['Oldest', 'false'],
      ['Most Comments', 'false']
    ]);
    const row = card('Offline sync');
    expect(row.querySelector('.fk-badge[data-status="in_progress"]')?.textContent).toBe('In Progress');
    expect(row.querySelector('.fk-badge[data-category="improvement"]')?.textContent).toBe('Improvement');
    expect(row.querySelector('.fk-vote.fk-vote-stack')).not.toBeNull();
    await userEvent.click(within(group).getByRole('button', { name: 'Oldest' }));
    expect(cards()[0].querySelector('.fk-classic-title')?.textContent).toBe('Widgets');
    expect(document.activeElement?.textContent).toBe('Oldest');
  });

  it('defaults to Showcase', () => {
    mount();
    expect(container.querySelector('.fk-root')?.getAttribute('data-list-style')).toBe('showcase');
  });
});

describe('appearance, language and direction', () => {
  it("'auto' carries a prefers-color-scheme dark block; 'dark' and 'light' carry one palette", () => {
    mount();
    const themeCss = () => container.querySelectorAll('style')[1].textContent ?? '';
    expect(themeCss()).toContain('@media (prefers-color-scheme: dark)');
    handle!.update({ colorScheme: 'dark' });
    expect(themeCss()).not.toContain('@media (prefers-color-scheme');
    expect(themeCss()).toContain('color-scheme: dark');
    handle!.update({ colorScheme: 'light', theme: { primaryColor: '#6750A4' } });
    expect(themeCss()).toContain('--fk-primary: #6750A4');
  });

  it('localizes and lays out right-to-left for Arabic', () => {
    mount({ locale: 'ar' });
    const root = container.querySelector('.fk-root')!;
    expect(root.getAttribute('dir')).toBe('rtl');
    expect(root.getAttribute('lang')).toBe('ar');
    expect(getByRole(container, 'button', { name: 'ترتيب وتصفية' })).toBeTruthy();
  });

  it('inherits the page direction when no locale is given, and dir overrides both', () => {
    container.setAttribute('dir', 'rtl');
    mount({ locale: undefined });
    expect(container.querySelector('.fk-root')?.getAttribute('dir')).toBe('rtl');
    handle!.update({ dir: 'ltr' });
    expect(container.querySelector('.fk-root')?.getAttribute('dir')).toBe('ltr');
  });

  it('takes copy overrides and a custom heading level, or no heading', () => {
    mount({ strings: { 'list.sortAndFilter': 'Options' }, headingLevel: 3 });
    expect(getByRole(container, 'button', { name: 'Options' })).toBeTruthy();
    expect(getByRole(container, 'heading', { level: 3, name: 'Feedback' })).toBeTruthy();
    expect(within(cards()[0]).getByRole('heading', { level: 4 })).toBeTruthy();
    handle!.update({ title: null });
    expect(queryByRole(container, 'heading', { level: 3 })).toBeNull();
  });

  it('escapes server text', () => {
    mount({ items: [feedback({ title: '<img src=x onerror=alert(1)>', description: '<b>bold</b>' })] });
    expect(container.querySelector('img')).toBeNull();
    expect(container.querySelector('.fk-title')?.textContent).toBe('<img src=x onerror=alert(1)>');
  });
});

describe('mounting', () => {
  it('renders into an open shadow root by default, with style parts, and destroy removes it', () => {
    handle = mountFeedbackList(container, { items: ITEMS, locale: 'en' });
    const host = container.querySelector('.feedbackkit-list') as HTMLElement;
    expect(host.shadowRoot).not.toBeNull();
    expect(container.querySelector('article')).toBeNull();
    const shadow = host.shadowRoot!;
    expect(shadow.querySelectorAll('[part="card"]')).toHaveLength(3);
    expect(shadow.querySelector('[part="menu-button"]')).not.toBeNull();
    expect(shadow.querySelectorAll('[part="vote"]')).toHaveLength(3);
    fireEvent.click(shadow.querySelector('[data-fk-key="menu-button"]')!);
    expect(shadow.querySelector('[role="menu"]')?.hasAttribute('hidden')).toBe(false);
    handle.destroy();
    handle = undefined;
    expect(container.querySelector('.feedbackkit-list')).toBeNull();
  });

  it('gives two embeds on one page distinct ids', () => {
    mount();
    const second = mountFeedbackList(container, { shadow: false, items: ITEMS, locale: 'en' });
    const ids = Array.from(container.querySelectorAll('[id]')).map((el) => el.id);
    expect(new Set(ids).size).toBe(ids.length);
    second.destroy();
  });

  it('rejects a missing container', () => {
    expect(() => mountFeedbackList(null as unknown as HTMLElement)).toThrow(TypeError);
  });
});

/** Instance ids depend on how many lists earlier tests mounted. */
const stable = (html: string | undefined) => (html ?? '').replace(/\bfk\d+-/g, 'fkN-');

describe('large text (200%)', () => {
  // jsdom has no layout engine, so these pin the markup rendered at 200% root
  // text size; the Playwright screenshots under docs/ are the layout evidence.
  beforeEach(() => {
    document.documentElement.style.fontSize = '200%';
  });

  it('card markup', () => {
    mount({ items: [ITEMS[0], ITEMS[2]] });
    expect(stable(container.querySelector('.fk-list')?.innerHTML)).toMatchSnapshot();
  });

  it('filtered header and open menu markup', async () => {
    mount();
    await userEvent.click(menuButton());
    await userEvent.click(getByRole(container, 'menuitemradio', { name: 'Improvements' }));
    await userEvent.click(menuButton());
    expect(stable(container.querySelector('[data-fk-slot="header"]')?.innerHTML)).toMatchSnapshot();
    expect(stable(container.querySelector('.fk-filter-row')?.innerHTML)).toMatchSnapshot();
  });
});
