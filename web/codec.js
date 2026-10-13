// What goes inside a page, and how it is protected. Runs in the browser and in Node.
//
//   item  ->  [kind][name length][name][data]          kind 1 = text, 2 = file
//         ->  deflate, if that makes it smaller         (flag bit 1)
//         ->  AES-256-GCM with a key from the passphrase (flag bit 0)
//              salt (16) | iv (12) | ciphertext + tag (16)
//              key = PBKDF2-SHA-256(passphrase, salt, 600,000 rounds)
//
// The cryptography is the browser's own Web Crypto API. Nothing here is home-made.

export const FLAG_ENCRYPTED = 1;
export const FLAG_COMPRESSED = 2;
export const KIND_TEXT = 1;
export const KIND_FILE = 2;
export const PBKDF2_ROUNDS = 600_000;
export const MAX_NAME = 64; // bytes of UTF-8
export const MAX_UNPACKED = 64 * 1024; // a decompressed page can't be bigger than this
const SALT = 16;
const IV = 12;
const TAG = 16;
export const ENCRYPTION_OVERHEAD = SALT + IV + TAG;

export class InkvaultError extends Error {}

const encoder = new TextEncoder();
const decoder = new TextDecoder('utf-8', { fatal: true });

// File names are only ever used as a download name; keep them plain and short.
export function safeFileName(name) {
  const cleaned = String(name ?? '')
    .normalize('NFC')
    .replace(/[\u0000-\u001f\u007f-\u009f​-‏‪-‮⁦-⁩]/g, '')
    .replace(/[\\/:*?"<>|]/g, '_')
    .replace(/^[.\s]+/, '')
    .trim();
  let bytes = encoder.encode(cleaned || 'restored-file');
  let out = cleaned || 'restored-file';
  while (bytes.length > MAX_NAME) {
    out = out.slice(0, -1);
    bytes = encoder.encode(out);
  }
  return out;
}

export function packItem(item) {
  const kind = item.kind === 'file' ? KIND_FILE : KIND_TEXT;
  const name = kind === KIND_FILE ? encoder.encode(safeFileName(item.name)) : new Uint8Array(0);
  const data = kind === KIND_FILE ? new Uint8Array(item.data) : encoder.encode(String(item.text ?? ''));
  const out = new Uint8Array(2 + name.length + data.length);
  out[0] = kind;
  out[1] = name.length;
  out.set(name, 2);
  out.set(data, 2 + name.length);
  return out;
}

export function unpackItem(bytes) {
  if (bytes.length < 2) throw new InkvaultError('The page is empty or not from Inkvault.');
  const kind = bytes[0];
  const nameLength = bytes[1];
  if ((kind !== KIND_TEXT && kind !== KIND_FILE) || nameLength > MAX_NAME || 2 + nameLength > bytes.length) {
    throw new InkvaultError('The page contents are not in a format Inkvault knows.');
  }
  const data = bytes.slice(2 + nameLength);
  if (kind === KIND_TEXT) {
    try {
      return { kind: 'text', text: decoder.decode(data) };
    } catch {
      throw new InkvaultError('The text on the page is not valid UTF-8.');
    }
  }
  let name;
  try {
    name = decoder.decode(bytes.slice(2, 2 + nameLength));
  } catch {
    name = 'restored-file';
  }
  return { kind: 'file', name: safeFileName(name), data };
}

async function streamThrough(bytes, stream, limit) {
  const reader = new Blob([bytes]).stream().pipeThrough(stream).getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.length;
    if (total > limit) {
      await reader.cancel();
      throw new InkvaultError('The page unpacks to more than 64 KB, so it was refused.');
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let at = 0;
  for (const c of chunks) {
    out.set(c, at);
    at += c.length;
  }
  return out;
}

export const deflate = (bytes) => streamThrough(bytes, new CompressionStream('deflate-raw'), Infinity);
// Bounded, so a small page can't expand into a huge "decompression bomb".
export async function inflate(bytes) {
  try {
    return await streamThrough(bytes, new DecompressionStream('deflate-raw'), MAX_UNPACKED);
  } catch (e) {
    if (e instanceof InkvaultError) throw e;
    throw new InkvaultError('The page data could not be unpacked.');
  }
}

async function deriveKey(passphrase, salt) {
  const material = await crypto.subtle.importKey('raw', encoder.encode(passphrase.normalize('NFC')), 'PBKDF2', false, [
    'deriveKey',
  ]);
  return crypto.subtle.deriveKey(
    { name: 'PBKDF2', hash: 'SHA-256', salt, iterations: PBKDF2_ROUNDS },
    material,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt'],
  );
}

// The version and flags are authenticated too, so they can't be swapped unnoticed.
const associated = (flags) => new Uint8Array([1, flags]);

// Returns { bytes, flags } ready for the page.
export async function seal(item, passphrase) {
  let body = packItem(item);
  let flags = 0;
  const packed = await deflate(body);
  if (packed.length < body.length) {
    body = packed;
    flags |= FLAG_COMPRESSED;
  }
  if (passphrase) {
    flags |= FLAG_ENCRYPTED;
    const salt = crypto.getRandomValues(new Uint8Array(SALT));
    const iv = crypto.getRandomValues(new Uint8Array(IV));
    const key = await deriveKey(passphrase, salt);
    const sealed = new Uint8Array(
      await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData: associated(flags) }, key, body),
    );
    const out = new Uint8Array(SALT + IV + sealed.length);
    out.set(salt, 0);
    out.set(iv, SALT);
    out.set(sealed, SALT + IV);
    body = out;
  }
  return { bytes: body, flags };
}

// The reverse of seal(). Throws InkvaultError with a message fit to show the user.
export async function open(bytes, flags, passphrase) {
  let body = bytes;
  if (flags & ~(FLAG_ENCRYPTED | FLAG_COMPRESSED)) throw new InkvaultError('The page uses features this version does not know.');
  if (flags & FLAG_ENCRYPTED) {
    if (!passphrase) throw new InkvaultError('This page is locked. Enter its passphrase.');
    if (body.length < ENCRYPTION_OVERHEAD) throw new InkvaultError('The locked data is too short.');
    const key = await deriveKey(passphrase, body.slice(0, SALT));
    try {
      body = new Uint8Array(
        await crypto.subtle.decrypt(
          { name: 'AES-GCM', iv: body.slice(SALT, SALT + IV), additionalData: associated(flags) },
          key,
          body.slice(SALT + IV),
        ),
      );
    } catch {
      throw new InkvaultError('Wrong passphrase, or the page was altered.');
    }
  }
  if (flags & FLAG_COMPRESSED) body = await inflate(body);
  return unpackItem(body);
}

// A rough guide, not a guarantee: bits of guessing work for a passphrase.
export function passphraseBits(passphrase) {
  const p = String(passphrase ?? '');
  if (!p) return 0;
  let pool = 0;
  if (/[a-z]/.test(p)) pool += 26;
  if (/[A-Z]/.test(p)) pool += 26;
  if (/[0-9]/.test(p)) pool += 10;
  if (/[^a-zA-Z0-9]/.test(p)) pool += 33;
  const distinct = new Set(p).size;
  return Math.round(Math.min(p.length, distinct * 2) * Math.log2(Math.max(pool, 2)));
}

// 20 random characters in groups, about 100 bits: strong, and easy to copy by hand.
const ALPHABET = 'ABCDEFGHJKMNPQRSTVWXYZ23456789'; // no 0/O, 1/I/L, U
export function generatePassphrase() {
  const out = [];
  const limit = 256 - (256 % ALPHABET.length); // avoid modulo bias
  while (out.length < 20) {
    for (const b of crypto.getRandomValues(new Uint8Array(32))) {
      if (b < limit && out.length < 20) out.push(ALPHABET[b % ALPHABET.length]);
    }
  }
  return out.join('').match(/.{4}/g).join('-');
}
