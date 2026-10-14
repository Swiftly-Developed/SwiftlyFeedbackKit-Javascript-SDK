/**
 * Persistent anonymous user ids.
 *
 * The value matches Swift (`local_` + UUID) and Flutter's lowercase UUID v4
 * (`local_<uuid>`). Browsers keep it in `localStorage` under the same key
 * Flutter uses. Node and SSR have no usable storage, so the id stays in
 * memory for that client and a throwing `localStorage` does not crash setup.
 */

export const USER_ID_STORAGE_KEY = 'feedbackkit_user_id';

export interface UserIdStore {
  get(): string | undefined;
  set(userId: string | undefined): void;
}

/**
 * An id the host set, else the stored one, else a new `local_<uuid>` which is
 * then stored. A blank string is not an explicit id.
 */
export function initialUserId(configured: string | undefined, store: UserIdStore): string {
  const explicit = configured?.trim();
  if (explicit) {
    store.set(explicit);
    return explicit;
  }

  const stored = store.get()?.trim();
  if (stored) return stored;

  const generated = generateLocalUserId();
  store.set(generated);
  return generated;
}

export function generateLocalUserId(): string {
  return `local_${randomUuid()}`;
}

export function createUserIdStore(): UserIdStore {
  let memory: string | undefined;
  let loaded = false;
  const storage = readLocalStorage();

  return {
    get() {
      if (loaded) return memory;
      loaded = true;
      if (!storage) return memory;
      try {
        const stored = storage.getItem(USER_ID_STORAGE_KEY)?.trim();
        memory = stored || undefined;
      } catch {
        memory = undefined;
      }
      return memory;
    },
    set(userId) {
      const value = userId?.trim() || undefined;
      memory = value;
      loaded = true;
      if (!storage) return;
      try {
        if (value) storage.setItem(USER_ID_STORAGE_KEY, value);
        else storage.removeItem(USER_ID_STORAGE_KEY);
      } catch {
        // Storage can throw in private mode. The memory copy still identifies
        // this client for the rest of the session.
      }
    }
  };
}

function readLocalStorage(): Storage | undefined {
  try {
    const storage = globalThis.localStorage;
    if (
      !storage ||
      typeof storage.getItem !== 'function' ||
      typeof storage.setItem !== 'function' ||
      typeof storage.removeItem !== 'function'
    ) {
      return undefined;
    }
    return storage;
  } catch {
    return undefined;
  }
}

function randomUuid(): string {
  const cryptoObj = readCrypto();
  if (cryptoObj && typeof cryptoObj.randomUUID === 'function') {
    return cryptoObj.randomUUID();
  }

  const bytes = new Uint8Array(16);
  if (cryptoObj && typeof cryptoObj.getRandomValues === 'function') {
    cryptoObj.getRandomValues(bytes);
  } else {
    for (let index = 0; index < bytes.length; index += 1) {
      bytes[index] = Math.floor(Math.random() * 256);
    }
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function readCrypto(): Crypto | undefined {
  try {
    return globalThis.crypto;
  } catch {
    return undefined;
  }
}
