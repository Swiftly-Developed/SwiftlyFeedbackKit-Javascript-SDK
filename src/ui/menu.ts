/**
 * Keyboard support for the Sort & Filter menu, per the WAI-ARIA menu button
 * pattern: roving focus over the items, wrap-around arrows, Home/End, and
 * first-character type-ahead.
 */

export function menuItems(menu: HTMLElement): HTMLElement[] {
  return Array.from(menu.querySelectorAll<HTMLElement>('[role^="menuitem"]'));
}

export function focusMenuItem(items: HTMLElement[], index: number): void {
  const item = items[index];
  if (!item) return;
  for (const candidate of items) candidate.tabIndex = candidate === item ? 0 : -1;
  item.focus();
}

/** The next item after `from` whose label starts with `char`, wrapping; -1 when none does. */
export function typeaheadIndex(items: HTMLElement[], from: number, char: string): number {
  const wanted = char.toLocaleLowerCase();
  for (let step = 1; step <= items.length; step += 1) {
    const index = (from + step + items.length) % items.length;
    const label = (items[index].textContent ?? '').trim().toLocaleLowerCase();
    if (label.startsWith(wanted)) return index;
  }
  return -1;
}
