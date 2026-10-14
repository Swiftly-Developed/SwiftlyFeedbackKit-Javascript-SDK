/**
 * Inline SVG icons for the feedback list embed.
 *
 * Material Symbols paths (Apache 2.0), 24-unit grid, painted with `currentColor` so
 * they follow the text colour, forced colours and the dark scheme. Every icon is
 * decorative: the text beside it, or the control's accessible name, carries the
 * meaning, so each one is hidden from assistive technology.
 */

import { FeedbackCategory, FeedbackStatus } from '../models/types';

export type FeedbackListIconName =
  | 'tune'
  | 'lightbulb'
  | 'bug'
  | 'more'
  | 'comment'
  | 'filter'
  | 'filterActive'
  | 'arrowUp'
  | 'check'
  | 'close';

const PATHS: Record<FeedbackListIconName, string> = {
  tune:
    '<path d="M3 17v2h6v-2H3zM3 5v2h10V5H3zm10 16v-2h8v-2h-8v-2h-2v6h2zM7 9v2H3v2h4v2h2V9H7zm14 4v-2H11v2h10zm-6-4h2V7h4V5h-4V3h-2v6z"/>',
  lightbulb:
    '<path d="M9 21c0 .55.45 1 1 1h4c.55 0 1-.45 1-1v-1H9v1zm3-19C8.14 2 5 5.14 5 9c0 2.38 1.19 4.47 3 5.74V17c0 .55.45 1 1 1h6c.55 0 1-.45 1-1v-2.26c1.81-1.27 3-3.36 3-5.74 0-3.86-3.14-7-7-7zm2.85 11.1-.85.6V16h-4v-2.3l-.85-.6C7.8 12.16 7 10.63 7 9c0-2.76 2.24-5 5-5s5 2.24 5 5c0 1.63-.8 3.16-2.15 4.1z"/>',
  bug:
    '<path d="M20 8h-2.81c-.45-.78-1.07-1.45-1.82-1.96L17 4.41 15.59 3l-2.17 2.17C12.96 5.06 12.49 5 12 5s-.96.06-1.41.17L8.41 3 7 4.41l1.62 1.63C7.88 6.55 7.26 7.22 6.81 8H4v2h2.09c-.05.33-.09.66-.09 1v1H4v2h2v1c0 .34.04.67.09 1H4v2h2.81c1.04 1.79 2.97 3 5.19 3s4.15-1.21 5.19-3H20v-2h-2.09c.05-.33.09-.66.09-1v-1h2v-2h-2v-1c0-.34-.04-.67-.09-1H20V8zm-6 8h-4v-2h4v2zm0-4h-4v-2h4v2z"/>',
  more:
    '<path d="M6 10c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm12 0c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2zm-6 0c-1.1 0-2 .9-2 2s.9 2 2 2 2-.9 2-2-.9-2-2-2z"/>',
  comment: '<path d="M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H6l-2 2V4h16v12z"/>',
  filter: '<path d="M10 18h4v-2h-4v2zM3 6v2h18V6H3zm3 7h12v-2H6v2z"/>',
  filterActive:
    '<path fill-rule="evenodd" d="M12 1a11 11 0 1 1 0 22 11 11 0 0 1 0-22zM6 7.5v2h12v-2H6zm2 3.5v2h8v-2H8zm2 3.5v2h4v-2h-4z"/>',
  arrowUp: '<path d="M4 12l1.41 1.41L11 7.83V20h2V7.83l5.58 5.59L20 12l-8-8-8 8z"/>',
  check: '<path d="M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z"/>',
  close:
    '<path d="M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/>'
};

export function icon(name: FeedbackListIconName, className = 'fk-icon'): string {
  return (
    `<svg class="${className}" data-icon="${name}" viewBox="0 0 24 24" fill="currentColor" ` +
    `aria-hidden="true" focusable="false">${PATHS[name]}</svg>`
  );
}

const CATEGORY_ICONS: Record<string, FeedbackListIconName> = {
  [FeedbackCategory.FeatureRequest]: 'lightbulb',
  [FeedbackCategory.BugReport]: 'bug',
  [FeedbackCategory.Improvement]: 'tune',
  [FeedbackCategory.Other]: 'more'
};

export function categoryIconName(category: FeedbackCategory): FeedbackListIconName {
  return CATEGORY_ICONS[category] ?? 'more';
}

/**
 * The status glyph encodes status by shape as well as colour, so it reads in
 * greyscale and for colour-blind users: dashed ring (Pending), empty ring
 * (Approved), half-filled ring (In Progress), three-quarter ring (TestFlight),
 * filled check (Completed), filled cross (Rejected).
 *
 * Like its SF Symbol counterpart the glyph is a fixed shape: the half and the
 * missing quarter stay on the physical left and right in right-to-left layouts.
 */
export function statusGlyph(status: FeedbackStatus): string {
  const ring = (extra = '') =>
    `<circle cx="8" cy="8" r="6.25" fill="none" stroke="currentColor" stroke-width="1.5"${extra}/>`;
  let body: string;
  switch (status) {
    case FeedbackStatus.Pending:
      body = ring(' stroke-dasharray="2.45 1.8"');
      break;
    case FeedbackStatus.Approved:
      body = ring();
      break;
    case FeedbackStatus.InProgress:
      body = ring() + '<path d="M8 3.5a4.5 4.5 0 0 0 0 9z"/>';
      break;
    case FeedbackStatus.TestFlight:
      body = ring() + '<path d="M8 8V3.5a4.5 4.5 0 1 0 4.5 4.5z"/>';
      break;
    case FeedbackStatus.Completed:
      body =
        '<circle cx="8" cy="8" r="7"/>' +
        '<path class="fk-glyph-cut" d="M4.8 8.2 7 10.4l4.2-4.4" fill="none" stroke-width="1.6" ' +
        'stroke-linecap="round" stroke-linejoin="round"/>';
      break;
    case FeedbackStatus.Rejected:
      body =
        '<circle cx="8" cy="8" r="7"/>' +
        '<path class="fk-glyph-cut" d="M5.5 5.5l5 5m0-5-5 5" fill="none" stroke-width="1.6" stroke-linecap="round"/>';
      break;
    default:
      body = ring();
  }
  return (
    `<svg class="fk-status-glyph" data-status-glyph="${status}" viewBox="0 0 16 16" fill="currentColor" ` +
    `aria-hidden="true" focusable="false">${body}</svg>`
  );
}
