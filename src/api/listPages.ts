/**
 * Follows a paged list. Callers send `paged=1` so a current server returns
 * `{ items, meta }`. A JSON array is a server that ignored that flag and is
 * already the whole collection, so this does not request another page.
 */

const maxPages = 100;

interface PageMeta {
  page?: number;
  perPage?: number;
  totalPages?: number;
}

interface DecodedPage<T> {
  items: T[];
  meta: PageMeta;
}

function readPage<T>(body: unknown): DecodedPage<T> | null {
  if (body === null || typeof body !== 'object' || Array.isArray(body)) {
    return null;
  }
  const record = body as { items?: unknown; meta?: PageMeta };
  if (!Array.isArray(record.items)) {
    return null;
  }
  return { items: record.items as T[], meta: record.meta ?? {} };
}

export async function collectList<T>(
  fetchPage: (page?: number, perPage?: number) => Promise<unknown>,
  page?: number,
  perPage?: number
): Promise<T[]> {
  const first = await fetchPage(page, perPage);
  if (Array.isArray(first)) {
    return first as T[];
  }
  const decoded = readPage<T>(first);
  if (!decoded) {
    return [];
  }
  if (page !== undefined) {
    return decoded.items;
  }

  const items = [...decoded.items];
  let next = (decoded.meta.page ?? 1) + 1;
  let size = decoded.meta.perPage ?? decoded.items.length;
  let totalPages = decoded.meta.totalPages ?? 1;
  if (size < 1 || decoded.items.length === 0 || (decoded.meta.page ?? 1) >= totalPages) {
    return items;
  }

  while (next <= totalPages && next <= maxPages) {
    const body = await fetchPage(next, size);
    if (Array.isArray(body)) {
      break;
    }
    const more = readPage<T>(body);
    if (!more || more.items.length === 0 || (more.meta.perPage ?? size) < 1) {
      break;
    }
    items.push(...more.items);
    const morePage = more.meta.page ?? next;
    size = more.meta.perPage ?? size;
    totalPages = more.meta.totalPages ?? totalPages;
    if (morePage >= totalPages) {
      break;
    }
    next = morePage + 1;
  }
  return items;
}
