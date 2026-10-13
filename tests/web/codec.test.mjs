// Unit tests for the page contents (web/codec.js) and the WebAssembly wrapper (web/core.js).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import {
  seal, open, packItem, unpackItem, safeFileName, deflate, passphraseBits, generatePassphrase,
  InkvaultError, FLAG_COMPRESSED, FLAG_ENCRYPTED, ENCRYPTION_OVERHEAD,
} from '../../web/codec.js';
import { loadCore, toGray } from '../../web/core.js';

const core = await loadCore(await readFile(new URL('../../web/inkvault.wasm', import.meta.url)));

test('text and files survive packing', () => {
  for (const text of ['', 'hello', 'Ünïcödé — 日本語 🔐', 'a'.repeat(700)]) {
    assert.deepEqual(unpackItem(packItem({ kind: 'text', text })), { kind: 'text', text });
  }
  const data = new Uint8Array([0, 1, 2, 255]);
  const back = unpackItem(packItem({ kind: 'file', name: 'keys.txt', data }));
  assert.equal(back.name, 'keys.txt');
  assert.deepEqual(back.data, data);
});

test('file names are made safe', () => {
  assert.equal(safeFileName('../../etc/passwd'), '_.._etc_passwd');
  assert.equal(safeFileName('C:\\Windows\\evil.exe'), 'C__Windows_evil.exe');
  assert.equal(safeFileName('report\u202Etxt.exe'), 'reporttxt.exe'); // right-to-left trick removed
  assert.equal(safeFileName('a\u0000b\u001b[31m'), 'ab[31m');
  assert.equal(safeFileName(''), 'restored-file');
  assert.equal(safeFileName('...'), 'restored-file');
  assert.ok(new TextEncoder().encode(safeFileName('é'.repeat(100))).length <= 64);
});

test('malformed page contents are refused with a clear message', () => {
  for (const bad of [[], [9, 0], [2, 200, 1, 2], [1, 0, 0xff, 0xfe]]) {
    assert.throws(() => unpackItem(new Uint8Array(bad)), InkvaultError);
  }
});

test('sealing without a passphrase, with compression when it helps', async () => {
  const item = { kind: 'text', text: 'recovery code '.repeat(30) };
  const { bytes, flags } = await seal(item);
  assert.equal(flags, FLAG_COMPRESSED);
  assert.ok(bytes.length < 100);
  assert.deepEqual(await open(bytes, flags), item);
  const random = { kind: 'file', name: 'r.bin', data: crypto.getRandomValues(new Uint8Array(200)) };
  const sealed = await seal(random);
  assert.equal(sealed.flags, 0, 'random data is not compressed');
});

test('a passphrase locks the page with AES-GCM', async () => {
  const item = { kind: 'text', text: 'the safe combination is 31-4-15' };
  const { bytes, flags } = await seal(item, 'correct horse battery staple');
  assert.ok(flags & FLAG_ENCRYPTED);
  assert.ok(!new TextDecoder().decode(bytes).includes('combination'));
  assert.deepEqual(await open(bytes, flags, 'correct horse battery staple'), item);
  await assert.rejects(open(bytes, flags, 'wrong'), /Wrong passphrase/);
  await assert.rejects(open(bytes, flags), /locked/);
  const tampered = bytes.slice();
  tampered[tampered.length - 1] ^= 1;
  await assert.rejects(open(tampered, flags, 'correct horse battery staple'), /altered/);
  // The flags are authenticated: claiming "not compressed" breaks the seal.
  await assert.rejects(open(bytes, flags ^ FLAG_COMPRESSED, 'correct horse battery staple'), /altered/);
  await assert.rejects(open(bytes.slice(0, ENCRYPTION_OVERHEAD - 1), flags, 'x'), /too short/);
  await assert.rejects(open(bytes, 0x80), /does not know/);
  // Same input, different salt and IV each time.
  const again = await seal(item, 'correct horse battery staple');
  assert.notDeepEqual(again.bytes, bytes);
});

test('a decompression bomb is refused', async () => {
  const bomb = await deflate(new Uint8Array(1024 * 1024));
  assert.ok(bomb.length < 2000);
  await assert.rejects(open(bomb, FLAG_COMPRESSED), /more than 64 KB/);
  await assert.rejects(open(new Uint8Array([1, 2, 3, 4]), FLAG_COMPRESSED), /could not be unpacked/);
});

test('passphrase helpers', () => {
  assert.equal(passphraseBits(''), 0);
  assert.ok(passphraseBits('password') < 40);
  assert.ok(passphraseBits('aaaaaaaaaaaaaaaaaaaa') < 40, 'repetition does not count as strength');
  const p = generatePassphrase();
  assert.match(p, /^([A-Z2-9]{4}-){4}[A-Z2-9]{4}$/);
  assert.ok(passphraseBits(p) >= 90);
  assert.notEqual(generatePassphrase(), p);
});

test('end to end through the WebAssembly core', async () => {
  const item = { kind: 'text', text: 'Wi-Fi: Hogwarts-5G / password: alohomora-2026' };
  const { bytes, flags } = await seal(item, 'K7QF-2MZD-9XWA-TR4P-H6NB');
  const cells = core.encode(bytes, flags);
  assert.equal(cells.length, core.cols * core.rows);
  const read = core.decodeCells(cells);
  assert.ok(read.ok);
  assert.equal(read.flags, flags);
  assert.deepEqual(await open(read.bytes, read.flags, 'K7QF-2MZD-9XWA-TR4P-H6NB'), item);
});

test('the core refuses what does not fit, and bad sizes', () => {
  assert.throws(() => core.encode(new Uint8Array(core.capacity + 1), 0), RangeError);
  assert.throws(() => core.encode('not bytes', 0), RangeError);
  assert.equal(core.decodeGray(new Uint8Array(10), 5, 2).code, -2);
  assert.equal(core.decodeGray(new Uint8Array(4), 1e9, 1e9).code, -2);
  assert.equal(core.decodeGray(new Uint8Array(100 * 100).fill(200), 100, 100).code, -3);
  assert.throws(() => core.decodeCells(new Uint8Array(5)), RangeError);
});

test('a page drawn as pixels reads back', () => {
  const cells = core.encode(new TextEncoder().encode('pixels'), 0);
  const scale = 5, margin = 20;
  const w = core.cols * scale + 2 * margin, h = core.rows * scale + 2 * margin;
  const rgba = new Uint8ClampedArray(w * h * 4).fill(240);
  for (let r = 0; r < core.rows; r++)
    for (let c = 0; c < core.cols; c++)
      if (cells[r * core.cols + c])
        for (let y = 0; y < scale; y++)
          for (let x = 0; x < scale; x++) {
            const i = ((margin + r * scale + y) * w + margin + c * scale + x) * 4;
            rgba[i] = rgba[i + 1] = rgba[i + 2] = 20;
          }
  const read = core.decodeGray(toGray(rgba, w, h), w, h);
  assert.ok(read.ok, read.error);
  assert.equal(new TextDecoder().decode(read.bytes), 'pixels');
  assert.equal(read.corners.length, 8);
});
