/**
 * Shared source-census helpers for the parity suites.
 *
 * `stripComments` is the honesty of every absence gate in `metrics-transport.test.ts`
 * and `metrics-api.test.ts`. A second copy of it could drift from the first, and a
 * drifted stripper turns a gate green for a reason nobody chose — so there is exactly
 * one, here.
 *
 * Not a `.test.ts` file, deliberately: the suite count asserted by the gate battery is
 * `ls tests/*.test.ts`, and a helper is not a suite.
 */

import { readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

export const SRC_ROOT = fileURLToPath(new URL('../../src', import.meta.url));

export function readSrc(relative: string): string {
  return readFileSync(join(SRC_ROOT, relative), 'utf8');
}

export function listSrcFiles(dir: string = SRC_ROOT): string[] {
  const out: string[] = [];
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      out.push(...listSrcFiles(full));
    } else if (entry.endsWith('.ts')) {
      out.push(full);
    }
  }
  return out.sort();
}

/**
 * Remove `//`, block and TSDoc comments, string-literal aware.
 *
 * A census of declarations otherwise counts the doc comment that describes them, and
 * a naive `//.*$` strip also eats the `//` inside a `https://` literal. The scanner
 * below tracks single, double and template quotes plus backslash escapes, which is
 * what the absence gates need to be honest.
 */
export function stripComments(source: string): string {
  let out = '';
  let i = 0;
  let quote: string | null = null;
  while (i < source.length) {
    const ch = source[i];
    const next = source[i + 1];
    if (quote) {
      out += ch;
      if (ch === '\\') {
        out += next ?? '';
        i += 2;
        continue;
      }
      if (ch === quote) quote = null;
      i += 1;
      continue;
    }
    if (ch === "'" || ch === '"' || ch === '`') {
      quote = ch;
      out += ch;
      i += 1;
      continue;
    }
    if (ch === '/' && next === '/') {
      while (i < source.length && source[i] !== '\n') i += 1;
      continue;
    }
    if (ch === '/' && next === '*') {
      i += 2;
      while (i < source.length && !(source[i] === '*' && source[i + 1] === '/')) i += 1;
      i += 2;
      continue;
    }
    out += ch;
    i += 1;
  }
  return out;
}

/** Load a committed wire corpus from `tests/fixtures/`. */
export function loadCorpus<T>(name: string): T {
  const path = fileURLToPath(new URL(`../fixtures/${name}`, import.meta.url));
  return JSON.parse(readFileSync(path, 'utf8')) as T;
}
