/**
 * Stylesheet for the feedback list embed.
 *
 * Sizes are in `rem`, so the list scales with the reader's browser text size and
 * zoom. Horizontal gutters are capped by the viewport/container width instead, so
 * large text gets the width rather than the padding; at 200% nothing is clipped, the card footer wraps the vote control under
 * the facts, and the menu scrolls. Spacing uses logical properties throughout, so
 * `dir="rtl"` mirrors the layout without a second sheet. Colours come from the
 * `--fk-*` properties written by `theme.ts`.
 */

export const BASE_CSS = String.raw`
:host { display: block; }
.fk-root {
  box-sizing: border-box;
  font-family: var(--fk-font, inherit);
  font-size: 1rem;
  line-height: 1.4;
  color: var(--fk-title);
  background: var(--fk-bg);
  padding-block: 1rem;
  padding-inline: min(1rem, 4vw);
  container-type: inline-size;
  -webkit-text-size-adjust: 100%;
  text-size-adjust: 100%;
}
.fk-root *, .fk-root *::before, .fk-root *::after { box-sizing: inherit; }
/* :where() keeps this reset below every single-class button rule. */
:where(.fk-root) button { font: inherit; color: inherit; }
.fk-sr-only {
  position: absolute !important;
  inline-size: 1px; block-size: 1px;
  margin: -1px; padding: 0; border: 0;
  overflow: hidden; clip: rect(0 0 0 0); clip-path: inset(50%);
  white-space: nowrap;
}
.fk-icon { inline-size: 1.25em; block-size: 1.25em; flex: none; }

/* Header: title and the Sort & Filter menu */
.fk-header {
  display: flex; flex-wrap: wrap; align-items: center;
  gap: 0.5rem 1rem; margin-block-end: 0.75rem;
}
.fk-heading {
  margin: 0; font-size: 1.375rem; font-weight: 600; line-height: 1.25;
  color: var(--fk-title-on-bg); overflow-wrap: anywhere;
}
.fk-menu-anchor { position: relative; margin-inline-start: auto; }

/* Material 3 buttons: a state layer on hover/press, a visible focus ring */
.fk-btn {
  position: relative; display: inline-flex; align-items: center; justify-content: center;
  gap: 0.5rem; min-block-size: 2.5rem; padding-block: 0.5rem; padding-inline: 1.5rem;
  border: 0; border-radius: 1.25rem; cursor: pointer;
  font-size: 0.875rem; font-weight: 600; line-height: 1.25; text-align: start;
  -webkit-tap-highlight-color: transparent; isolation: isolate;
}
.fk-btn:has(> .fk-icon:first-child) { padding-inline: 1rem 1.5rem; }
.fk-btn::after {
  content: ''; position: absolute; inset: 0; border-radius: inherit;
  background: currentColor; opacity: 0; transition: opacity 120ms linear; z-index: -1;
  pointer-events: none;
}
.fk-btn:hover::after { opacity: 0.08; }
.fk-btn:active::after { opacity: 0.12; }
.fk-root :focus-visible { outline: 0.1875rem solid var(--fk-focus); outline-offset: 0.125rem; }
.fk-btn-tonal { background: var(--fk-tonal-on-bg); color: var(--fk-on-tonal-on-bg); }
.fk-btn-filled { background: var(--fk-primary); color: var(--fk-on-primary); }
.fk-btn-text {
  background: transparent; color: var(--fk-primary-on-bg);
  padding-inline: 0.75rem; min-inline-size: 3rem;
}

/* Menu */
.fk-menu {
  position: absolute; inset-block-start: calc(100% + 0.25rem); inset-inline-end: 0; z-index: 10;
  min-inline-size: min(15rem, calc(100vw - 2rem)); max-inline-size: min(22rem, calc(100vw - 2rem));
  max-block-size: min(34rem, 70vh); overflow-y: auto; overscroll-behavior: contain;
  margin: 0; padding: 0.5rem 0; list-style: none;
  background: var(--fk-menu); color: var(--fk-menu-text);
  border-radius: 0.75rem; box-shadow: var(--fk-shadow-2);
}
.fk-menu[hidden] { display: none; }
.fk-menu-heading {
  padding: 0.75rem 1rem 0.25rem; font-size: 0.75rem; font-weight: 600;
  letter-spacing: 0.03em; color: var(--fk-menu-muted);
}
.fk-menu-group { margin: 0; padding: 0; list-style: none; }
.fk-menu-separator { block-size: 1px; margin: 0.5rem 0; background: var(--fk-card-border); }
.fk-menu-item {
  position: relative; display: flex; align-items: center; gap: 0.75rem;
  inline-size: 100%; min-block-size: 3rem; padding: 0.5rem 1rem;
  border: 0; background: transparent; cursor: pointer; text-align: start;
  font-size: 0.9375rem; line-height: 1.3; color: var(--fk-menu-text); isolation: isolate;
}
.fk-menu-item::after {
  content: ''; position: absolute; inset: 0; background: var(--fk-state); opacity: 0; z-index: -1;
}
.fk-menu-item:hover::after, .fk-menu-item:focus::after { opacity: 0.08; }
.fk-menu-item:focus-visible { outline-offset: -0.1875rem; }
.fk-menu-item[aria-checked="true"] { font-weight: 600; }
.fk-menu-check { inline-size: 1.25em; block-size: 1.25em; flex: none; display: inline-flex; color: var(--fk-primary-on-menu); }
.fk-menu-check .fk-icon { visibility: hidden; }
.fk-menu-item[aria-checked="true"] .fk-menu-check .fk-icon { visibility: visible; }
.fk-menu-lead { display: inline-flex; flex: none; color: var(--fk-menu-muted); }
.fk-menu-label { flex: 1 1 auto; min-inline-size: 0; overflow-wrap: anywhere; hyphens: auto; }
.fk-menu-item-danger { color: var(--fk-danger); }

/* "Filtered by … Clear" */
.fk-filter-row {
  display: flex; flex-wrap: wrap; align-items: center; gap: 0.25rem 0.5rem;
  margin-block-end: 0.75rem; padding-inline-start: min(1.125rem, 4.5vw); padding-inline-start: min(1.125rem, 4.5cqi);
  font-size: 0.9375rem; color: var(--fk-title-on-bg);
}
.fk-filter-row:empty { display: none; }
.fk-filter-row .fk-icon { color: var(--fk-primary-on-bg); }
.fk-filter-text { flex: 1 1 0; min-inline-size: min(8rem, 60%); overflow-wrap: anywhere; color: var(--fk-body-on-bg); }
.fk-filter-text strong { font-weight: 700; color: var(--fk-title-on-bg); }

/* Showcase cards */
.fk-list { display: grid; gap: 0.75rem; margin: 0; padding: 0; list-style: none; }
.fk-card {
  position: relative; display: flex; flex-direction: column;
  padding-block: 1rem; padding-inline: min(1.125rem, 4.5vw); padding-inline: min(1.125rem, 4.5cqi);
  border-radius: 1rem;
  background: var(--fk-card); color: var(--fk-title);
  box-shadow: var(--fk-shadow-1); isolation: isolate;
  overflow-wrap: anywhere;
}
.fk-card-selectable:hover { box-shadow: var(--fk-shadow-2); }
.fk-card-selectable::before {
  content: ''; position: absolute; inset: 0; border-radius: inherit; z-index: -1;
  background: var(--fk-state); opacity: 0; transition: opacity 120ms linear; pointer-events: none;
}
.fk-card-selectable:hover::before { opacity: 0.04; }
.fk-card-selectable:active::before { opacity: 0.08; }
.fk-eyebrow {
  display: flex; align-items: center; gap: 0.375rem; margin: 0 0 0.5rem;
  font-size: 0.8125rem; font-weight: 600; line-height: 1.3;
}
.fk-status-glyph { inline-size: 1em; block-size: 1em; flex: none; }
.fk-glyph-cut { stroke: var(--fk-card); }
.fk-title { margin: 0; font-size: 1.25rem; font-weight: 600; line-height: 1.3; color: var(--fk-title); }
.fk-card-link {
  all: unset; cursor: pointer; overflow-wrap: anywhere;
}
.fk-card-link::after { content: ''; position: absolute; inset: 0; border-radius: inherit; z-index: 0; }
.fk-card-link:focus-visible { outline: none; }
.fk-card-link:focus-visible::after { outline: 0.1875rem solid var(--fk-focus); outline-offset: 0.125rem; }
.fk-description {
  margin: 0.25rem 0 0; font-size: 0.9375rem; line-height: 1.45; color: var(--fk-body);
  white-space: pre-line;
}
.fk-footer {
  display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between;
  gap: 0.5rem 1rem; margin-block-start: 0.875rem;
}
.fk-facts {
  display: flex; flex-wrap: wrap; align-items: center; gap: 0.25rem 1rem;
  font-size: 0.8125rem; color: var(--fk-body);
}
.fk-fact { display: inline-flex; align-items: center; gap: 0.375rem; white-space: nowrap; }
.fk-fact .fk-icon { inline-size: 1.125em; block-size: 1.125em; }

/* Vote capsule: 2.5rem visual, 3rem hit area */
.fk-vote {
  position: relative; z-index: 1; display: inline-flex; align-items: center; gap: 0.375rem;
  min-block-size: 2.5rem; min-inline-size: 3.5rem; padding-block: 0; padding-inline: 0.75rem 1rem;
  border: 0; border-radius: 1.25rem; cursor: pointer; isolation: isolate;
  font-size: 0.9375rem; font-weight: 600; font-variant-numeric: tabular-nums;
  background: var(--fk-tonal); color: var(--fk-on-tonal);
  -webkit-tap-highlight-color: transparent;
}
.fk-vote::before { content: ''; position: absolute; inset: -0.25rem -0.125rem; }
.fk-vote::after {
  content: ''; position: absolute; inset: 0; border-radius: inherit; background: currentColor;
  opacity: 0; transition: opacity 120ms linear; z-index: -1; pointer-events: none;
}
.fk-vote:hover::after { opacity: 0.08; }
.fk-vote:active::after { opacity: 0.12; }
.fk-vote[aria-pressed="true"] { background: var(--fk-primary); color: var(--fk-on-primary); }
.fk-vote[aria-disabled="true"] { cursor: default; opacity: 0.62; }
.fk-vote[aria-disabled="true"]::after { display: none; }
.fk-vote[aria-busy="true"] { cursor: progress; }
.fk-vote .fk-icon { inline-size: 1.125em; block-size: 1.125em; }
.fk-vote-closed {
  position: relative; display: inline-flex; align-items: center; gap: 0.375rem;
  min-block-size: 2.5rem; padding-inline: 0.25rem;
  font-size: 0.9375rem; font-weight: 600; font-variant-numeric: tabular-nums; color: var(--fk-body);
}
.fk-vote-closed .fk-icon { inline-size: 1.125em; block-size: 1.125em; }

/* Skeleton */
.fk-skeleton .fk-bone {
  display: block; border-radius: 0.375rem; background: var(--fk-placeholder);
  animation: fk-pulse 1.4s ease-in-out infinite;
}
.fk-skeleton .fk-bone-eyebrow { inline-size: 6rem; block-size: 0.875rem; margin-block-end: 0.75rem; }
.fk-skeleton .fk-bone-title { inline-size: 70%; block-size: 1.25rem; }
.fk-skeleton .fk-bone-line { inline-size: 100%; block-size: 0.875rem; margin-block-start: 0.5rem; }
.fk-skeleton .fk-bone-line-short { inline-size: 55%; }
.fk-skeleton .fk-bone-vote { inline-size: 4rem; block-size: 2.5rem; border-radius: 1.25rem; }
.fk-skeleton .fk-bone-fact { inline-size: 7rem; block-size: 0.875rem; }
@keyframes fk-pulse { 50% { opacity: 0.55; } }

/* Empty and error states */
.fk-state {
  display: flex; flex-direction: column; align-items: center; gap: 0.5rem;
  padding: 2.5rem 1rem; text-align: center; color: var(--fk-title-on-bg);
}
.fk-state-icon { inline-size: 2.5rem; block-size: 2.5rem; color: var(--fk-body-on-bg); }
.fk-state-title { margin: 0; font-size: 1.125rem; font-weight: 600; }
.fk-state-text { margin: 0 0 0.5rem; font-size: 0.9375rem; color: var(--fk-body-on-bg); max-inline-size: 32rem; }
.fk-error-text { color: var(--fk-danger); }
.fk-inline-error {
  display: flex; flex-wrap: wrap; align-items: center; gap: 0.5rem 1rem;
  margin-block-end: 0.75rem; color: var(--fk-danger); font-size: 0.9375rem;
}

/* Classic */
.fk-sort-row {
  display: flex; flex-wrap: wrap; align-items: center; gap: 0.5rem; margin-block-end: 0.75rem;
}
.fk-sort-label { font-size: 0.875rem; font-weight: 600; color: var(--fk-body-on-bg); }
.fk-chip {
  position: relative; display: inline-flex; align-items: center; gap: 0.375rem;
  min-block-size: 2rem; padding: 0.25rem 1rem; border-radius: 0.5rem; cursor: pointer;
  border: 1px solid var(--fk-card-border); background: var(--fk-card); color: var(--fk-title);
  font-size: 0.875rem; font-weight: 500; isolation: isolate;
}
.fk-chip::before { content: ''; position: absolute; inset: -0.5rem 0; }
.fk-chip[aria-pressed="true"] {
  background: var(--fk-chip-selected); color: var(--fk-on-chip-selected); border-color: transparent;
  padding-inline-start: 0.5rem;
}
.fk-chip .fk-icon { inline-size: 1.125em; block-size: 1.125em; }
.fk-classic-row {
  display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 0.75rem 1rem; align-items: start;
}
.fk-classic-title {
  margin: 0; font-size: 1.0625rem; font-weight: 600; line-height: 1.3;
  display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden;
}
.fk-classic-description {
  margin: 0.25rem 0 0.5rem; font-size: 0.875rem; color: var(--fk-body);
  display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden;
}
.fk-badges { display: flex; flex-wrap: wrap; align-items: center; gap: 0.375rem 0.5rem; font-size: 0.75rem; }
.fk-badge { display: inline-flex; align-items: center; padding: 0.125rem 0.5rem; border-radius: 0.375rem; font-weight: 600; }
.fk-classic-comments { display: inline-flex; align-items: center; gap: 0.25rem; color: var(--fk-body); }
.fk-vote-stack {
  flex-direction: column; gap: 0; min-inline-size: 3rem; min-block-size: 3.5rem;
  padding: 0.375rem 0.5rem; border-radius: 0.75rem;
}
.fk-vote-stack.fk-vote-closed { padding: 0.375rem 0.5rem; }
@media (prefers-reduced-motion: reduce) {
  .fk-root *, .fk-root *::before, .fk-root *::after { transition: none !important; animation: none !important; }
}
@media (prefers-contrast: more) {
  .fk-card { box-shadow: none; border: 1px solid var(--fk-title); }
  .fk-description, .fk-facts, .fk-vote-closed { color: var(--fk-title); }
  .fk-vote, .fk-btn-tonal { border: 1px solid currentColor; }
}
@media (forced-colors: active) {
  .fk-card { border: 1px solid CanvasText; box-shadow: none; }
  .fk-btn, .fk-vote, .fk-chip { border: 1px solid ButtonText; }
  .fk-vote[aria-pressed="true"], .fk-chip[aria-pressed="true"], .fk-btn-filled {
    background: Highlight; color: HighlightText; forced-color-adjust: none;
  }
  .fk-glyph-cut { stroke: Canvas; }
  .fk-menu { border: 1px solid CanvasText; }
  .fk-card-link:focus-visible::after, .fk-root :focus-visible { outline-color: Highlight; }
}
`;
