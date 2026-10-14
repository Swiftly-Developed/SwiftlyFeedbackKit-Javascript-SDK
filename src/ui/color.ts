/**
 * Colour helpers for the Showcase list.
 *
 * Every function accepts the hex forms a host can put in `theme` (`#RGB`, `#RRGGBB`,
 * `#RRGGBBAA`) and `rgb()`/`rgba()`. Anything else (a named colour, `hsl()`, a
 * `PlatformColor`) is returned unchanged by the mixers, so a host value is never
 * replaced with a guess.
 */

export interface Rgba {
  r: number;
  g: number;
  b: number;
  a: number;
}

export function parseColor(input: string): Rgba | null {
  const value = input.trim();
  const hex = /^#([0-9a-f]{3,8})$/i.exec(value);
  if (hex) {
    const digits = hex[1];
    if (digits.length === 3 || digits.length === 4) {
      const [r, g, b, a = 'f'] = digits.split('');
      return {
        r: parseInt(r + r, 16),
        g: parseInt(g + g, 16),
        b: parseInt(b + b, 16),
        a: parseInt(a + a, 16) / 255
      };
    }
    if (digits.length === 6 || digits.length === 8) {
      return {
        r: parseInt(digits.slice(0, 2), 16),
        g: parseInt(digits.slice(2, 4), 16),
        b: parseInt(digits.slice(4, 6), 16),
        a: digits.length === 8 ? parseInt(digits.slice(6, 8), 16) / 255 : 1
      };
    }
    return null;
  }
  const rgb = /^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)$/i.exec(value);
  if (rgb) {
    return {
      r: Number(rgb[1]),
      g: Number(rgb[2]),
      b: Number(rgb[3]),
      a: rgb[4] !== undefined ? Number(rgb[4]) : 1
    };
  }
  return null;
}

function toHex({ r, g, b }: Rgba): string {
  const part = (n: number) => Math.round(Math.min(255, Math.max(0, n))).toString(16).padStart(2, '0');
  return `#${part(r)}${part(g)}${part(b)}`.toUpperCase();
}

/** `amount` of `top` laid over `bottom`, as an opaque hex colour. */
export function mix(top: string, bottom: string, amount: number): string {
  const a = parseColor(top);
  const b = parseColor(bottom);
  if (!a || !b) return top;
  const t = Math.min(1, Math.max(0, amount * a.a));
  return toHex({
    r: a.r * t + b.r * (1 - t),
    g: a.g * t + b.g * (1 - t),
    b: a.b * t + b.b * (1 - t),
    a: 1
  });
}

function channel(c: number): number {
  const s = c / 255;
  return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
}

export function relativeLuminance(color: string): number | null {
  const c = parseColor(color);
  if (!c) return null;
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/** WCAG 2.x contrast ratio, or `null` when either colour cannot be parsed. */
export function contrastRatio(a: string, b: string): number | null {
  const la = relativeLuminance(a);
  const lb = relativeLuminance(b);
  if (la === null || lb === null) return null;
  const [hi, lo] = la > lb ? [la, lb] : [lb, la];
  return (hi + 0.05) / (lo + 0.05);
}

export function isDark(color: string): boolean {
  const l = relativeLuminance(color);
  return l !== null && l < 0.4;
}

/**
 * `foreground` unchanged when it already meets `target` against `background`;
 * otherwise mixed toward black (light backgrounds) or white (dark backgrounds) in
 * small steps until it does. Unparseable input is returned unchanged.
 */
export function ensureContrast(foreground: string, background: string, target = 4.5): string {
  const start = contrastRatio(foreground, background);
  if (start === null || start >= target) return foreground;
  const toward = isDark(background) ? '#FFFFFF' : '#000000';
  for (let step = 1; step <= 20; step += 1) {
    const candidate = mix(toward, foreground, step * 0.05);
    const ratio = contrastRatio(candidate, background);
    if (ratio !== null && ratio >= target) return candidate;
  }
  return toward;
}

/**
 * Label colour for a filled control. White is kept while it reaches 3:1, the
 * threshold for the bold labels these controls carry, so a host's saturated brand
 * colour keeps the white label both platforms use; a light fill (FeedbackKit
 * orange, yellow) gets black.
 */
export function onColor(background: string): string {
  const white = contrastRatio('#FFFFFF', background);
  if (white === null) return '#FFFFFF';
  return white >= 3 ? '#FFFFFF' : '#000000';
}
