#!/usr/bin/env node
/**
 * Renders the feedback list embed (`dist/feedbackkit-ui.global.js`) in headless
 * Chrome at 100%, 150% and 200% browser text size, light and dark, plus the open
 * menu, a filtered list, the filtered-empty state, Arabic RTL and Classic, and
 * checks each layout: no horizontal overflow, no clipped titles or descriptions,
 * 48px-or-larger vote targets, the vote capsule never overlapping the facts, and
 * the menu inside the viewport. Exits non-zero when a check fails.
 *
 * Usage: npm run build && npm run screenshots:ui [-- --out <dir>]
 * Chrome: CHROME_PATH, else /usr/local/bin/google-chrome, else Playwright's `chrome` channel.
 */

import { existsSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright-core';

const here = dirname(fileURLToPath(import.meta.url));
const pkg = resolve(here, '..');
const bundle = join(pkg, 'dist', 'feedbackkit-ui.global.js');
const outArg = process.argv.indexOf('--out');
const outDir = resolve(outArg > -1 ? process.argv[outArg + 1] : join(pkg, '..', 'docs', 'design', 'feedback01-showcase-web-2026-10'));

if (!existsSync(bundle)) {
  console.error(`Missing ${bundle}; run \`npm run build\` first.`);
  process.exit(1);
}
mkdirSync(outDir, { recursive: true });

const day = (n) => new Date(Date.UTC(2026, 9, 14 - n)).toISOString();
const item = (id, title, description, status, category, voteCount, commentCount, hasVoted, age) => ({
  id, title, description, status, category, userId: 'u', voteCount, hasVoted, commentCount,
  createdAt: day(age), updatedAt: day(age)
});

const ITEMS = [
  item('1', 'Dark mode for the public board', 'The public roadmap is blinding at night. Follow the system appearance, or offer a toggle in the header.', 'in_progress', 'feature_request', 186, 24, true, 30),
  item('2', 'Export requests to CSV', 'We review feedback in a spreadsheet every sprint. A CSV export with votes, status and category would save us an hour a week.', 'approved', 'improvement', 142, 11, false, 21),
  item('3', 'Keyboard shortcut to vote on Mac', 'Command-U to upvote the selected request would make triage much faster.', 'in_progress', 'improvement', 119, 0, false, 12),
  item('4', 'Suggest duplicates while typing', 'Show similar requests as I type a title, so I can vote instead of posting a duplicate.', 'pending', 'improvement', 63, 9, false, 5),
  item('5', 'Crash when attaching a large screenshot', 'Attaching a 12 MB screenshot closes the app on iPad. Smaller images work.', 'testflight', 'bug_report', 41, 6, true, 9),
  item('6', 'Sign in with Apple', 'Let people sign in with their Apple Account instead of an email link.', 'completed', 'feature_request', 312, 18, true, 60),
  item('7', 'Replace the logo with a mascot', 'A friendly mascot on the empty state would make the board feel less corporate.', 'rejected', 'other', 7, 2, false, 40)
];

const ARABIC = ITEMS.map((f, i) => ({
  ...f,
  title: ['الوضع الداكن للوحة العامة', 'تصدير الطلبات إلى CSV', 'اختصار لوحة المفاتيح للتصويت على Mac', 'اقتراح المكررات أثناء الكتابة', 'تعطل عند إرفاق لقطة شاشة كبيرة', 'تسجيل الدخول باستخدام Apple', 'استبدال الشعار بتميمة'][i],
  description: ['خارطة الطريق العامة ساطعة جدًا ليلًا. اتبع مظهر النظام أو أضف مفتاح تبديل في الرأس.', 'نراجع الملاحظات في جدول بيانات كل دورة. سيوفر تصدير CSV ساعة أسبوعيًا.', 'سيجعل الاختصار ⌘U الفرز أسرع بكثير.', 'اعرض الطلبات المشابهة أثناء كتابة العنوان حتى أصوّت بدل النشر مرة أخرى.', 'إرفاق لقطة شاشة بحجم 12 ميغابايت يغلق التطبيق على iPad.', 'اسمح بتسجيل الدخول بحساب Apple بدل رابط البريد.', 'تميمة لطيفة في الحالة الفارغة ستجعل اللوحة أقل رسمية.'][i]
}));

/** Each scene: file name, colour scheme, root font-size %, mount options, and an optional interaction. */
const scenes = [];
for (const scheme of ['light', 'dark']) {
  for (const size of [100, 150, 200]) {
    scenes.push({ name: `showcase-${scheme}-${size}`, scheme, size, options: { items: ITEMS } });
  }
}
scenes.push(
  { name: 'menu-open-light-100', scheme: 'light', size: 100, options: { items: ITEMS }, act: 'openMenu', viewportHeight: 1100 },
  { name: 'menu-open-dark-200', scheme: 'dark', size: 200, options: { items: ITEMS }, act: 'openMenu', viewportHeight: 900 },
  { name: 'filtered-light-100', scheme: 'light', size: 100, options: { items: ITEMS }, act: 'filterImprovementInProgress' },
  { name: 'filtered-dark-200', scheme: 'dark', size: 200, options: { items: ITEMS }, act: 'filterImprovementInProgress' },
  { name: 'filtered-empty-light-150', scheme: 'light', size: 150, options: { items: ITEMS }, act: 'filterBugApproved' },
  { name: 'rtl-ar-light-150', scheme: 'light', size: 150, options: { items: ARABIC, locale: 'ar' } },
  { name: 'rtl-ar-dark-100', scheme: 'dark', size: 100, options: { items: ARABIC, locale: 'ar' } },
  { name: 'classic-light-100', scheme: 'light', size: 100, options: { items: ITEMS, listStyle: 'classic' } },
  { name: 'classic-dark-200', scheme: 'dark', size: 200, options: { items: ITEMS, listStyle: 'classic' } }
);

function launchOptions() {
  const path = process.env.CHROME_PATH ?? (existsSync('/usr/local/bin/google-chrome') ? '/usr/local/bin/google-chrome' : undefined);
  return path ? { executablePath: path } : { channel: 'chrome' };
}

const PAGE = (scheme, size) => `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<style>
  html { font-size: ${size}%; font-family: Inter, "Noto Sans", "Noto Sans Arabic", system-ui, sans-serif; }
  body { margin: 0; background: ${scheme === 'dark' ? '#000' : '#f2f2f7'}; }
</style></head><body><main id="app"></main></body></html>`;

/** Runs in the page: returns a list of human-readable layout failures. */
function inspectLayout(scale) {
  const failures = [];
  const host = document.querySelector('.feedbackkit-list');
  const root = host.shadowRoot ?? host;
  const doc = document.documentElement;
  if (doc.scrollWidth > doc.clientWidth + 1) failures.push(`page scrolls horizontally (${doc.scrollWidth} > ${doc.clientWidth})`);
  const rect = (el) => el.getBoundingClientRect();
  const overlaps = (a, b) => a.left < b.right - 0.5 && b.left < a.right - 0.5 && a.top < b.bottom - 0.5 && b.top < a.bottom - 0.5;

  for (const el of root.querySelectorAll('.fk-title, .fk-description, .fk-heading, .fk-filter-text, .fk-btn, .fk-menu-item, .fk-fact, .fk-eyebrow')) {
    if (el.scrollWidth > el.clientWidth + 1 || el.scrollHeight > el.clientHeight + 1) {
      const clamped = getComputedStyle(el).webkitLineClamp;
      if (!clamped || clamped === 'none') failures.push(`clipped: ${el.className} "${el.textContent.trim().slice(0, 40)}"`);
    }
  }
  for (const card of root.querySelectorAll('.fk-card, .fk-classic-row')) {
    const cardBox = rect(card);
    if (cardBox.right > doc.clientWidth + 0.5 || cardBox.left < -0.5) failures.push(`card outside viewport: ${card.textContent.slice(0, 30)}`);
    const vote = card.querySelector('[data-fk-vote]');
    const facts = card.querySelector('.fk-facts');
    if (vote) {
      const v = rect(vote);
      if (v.right > cardBox.right + 0.5 || v.left < cardBox.left - 0.5) failures.push(`vote outside card: ${card.textContent.slice(0, 30)}`);
      if (facts && overlaps(v, rect(facts))) failures.push(`vote overlaps facts: ${card.textContent.slice(0, 30)}`);
      if (vote.tagName === 'BUTTON') {
        const before = getComputedStyle(vote, '::before');
        const inset = parseFloat(before.insetBlockStart || before.top || '0') || 0;
        const target = v.height - 2 * inset;
        if (target < 47.5 * Math.min(scale, 1)) failures.push(`vote target ${target.toFixed(1)}px < 48px`);
        if (v.height < 40 * scale - 0.5) failures.push(`vote capsule ${v.height.toFixed(1)}px did not scale with text (${40 * scale}px)`);
      }
    }
  }
  const menu = root.querySelector('.fk-menu:not([hidden])');
  if (menu) {
    const m = rect(menu);
    if (m.left < -0.5 || m.right > doc.clientWidth + 0.5) failures.push(`menu outside viewport horizontally (${m.left.toFixed(0)}–${m.right.toFixed(0)})`);
    if (m.bottom > window.innerHeight + 0.5 && menu.scrollHeight <= menu.clientHeight) failures.push('menu runs past the viewport without scrolling');
  }
  return failures;
}

const browser = await chromium.launch(launchOptions());
const script = readFileSync(bundle, 'utf8');
let failed = 0;
try {
  for (const scene of scenes) {
    const context = await browser.newContext({
      viewport: { width: 412, height: scene.viewportHeight ?? 915 },
      deviceScaleFactor: 2,
      colorScheme: scene.scheme,
      reducedMotion: 'reduce'
    });
    const page = await context.newPage();
    page.on('pageerror', (error) => { failed += 1; console.error(`${scene.name}: page error ${error.message}`); });
    await page.setContent(PAGE(scene.scheme, scene.size));
    await page.addScriptTag({ content: script });
    await page.evaluate((options) => {
      window.__list = window.FeedbackKitUI.mountFeedbackList(document.getElementById('app'), {
        ...options,
        onSelect: () => {}
      });
    }, scene.options);

    const menuButton = page.locator('[data-fk-action="menu-toggle"]');
    const choose = async (action, value) => {
      if ((await menuButton.getAttribute('aria-expanded')) !== 'true') await menuButton.click();
      await page.locator(`.fk-menu [data-fk-action="${action}"][data-fk-value="${value}"]`).click();
    };
    if (scene.act === 'openMenu') {
      await menuButton.click();
    } else if (scene.act === 'filterImprovementInProgress') {
      await choose('category', 'improvement');
      await choose('status', 'in_progress');
    } else if (scene.act === 'filterBugApproved') {
      await choose('category', 'bug_report');
      await choose('status', 'approved');
    }
    await page.evaluate(() => document.fonts.ready);

    const failures = await page.evaluate(inspectLayout, scene.size / 100);
    const file = join(outDir, `${scene.name}.png`);
    await page.screenshot({ path: file, fullPage: true });
    if (failures.length) {
      failed += failures.length;
      console.error(`✗ ${scene.name}\n  ${failures.join('\n  ')}`);
    } else {
      console.log(`✓ ${scene.name} → ${file}`);
    }
    await context.close();
  }
} finally {
  await browser.close();
}
if (failed) {
  console.error(`${failed} layout check(s) failed`);
  process.exit(1);
}
