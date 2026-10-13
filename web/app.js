// Inkvault's page: making, reading and damaging pages. All user text reaches the page
// through textContent or form values, never as HTML.
import { loadCore } from './core.js';
import {
  seal, open, packItem, passphraseBits, generatePassphrase, safeFileName,
  InkvaultError, ENCRYPTION_OVERHEAD, FLAG_ENCRYPTED,
} from './codec.js';
import { pageSvg, pageCanvas, photograph, grayFrom } from './page.js';

const $ = (id) => document.getElementById(id);
const MAX_FILE = 64 * 1024; // files bigger than this can't fit even compressed; don't read them
const MAX_PHOTO = 40 * 1024 * 1024;

let core;
let current = null; // the page most recently made: { cells, title }
let decoded = null; // what was last read: { bytes, flags }
let shown = null; // the opened item
let camera = null;

// ---------- tabs ----------
const tabs = ['make', 'read', 'lab'];
function showTab(name) {
  for (const t of tabs) {
    const tab = $(`tab-${t}`);
    const on = t === name;
    tab.setAttribute('aria-selected', String(on));
    tab.tabIndex = on ? 0 : -1;
    $(t).hidden = !on;
  }
  if (name !== 'read') stopCamera();
  if (name === 'lab') runLab();
}
for (const t of tabs) {
  $(`tab-${t}`).addEventListener('click', () => showTab(t));
  $(`tab-${t}`).addEventListener('keydown', (e) => {
    const i = tabs.indexOf(t);
    const next = e.key === 'ArrowRight' ? tabs[(i + 1) % 3] : e.key === 'ArrowLeft' ? tabs[(i + 2) % 3] : null;
    if (next) {
      showTab(next);
      $(`tab-${next}`).focus();
    }
  });
}

// ---------- make ----------
const kind = () => document.querySelector('input[name="kind"]:checked').value;
let pickedFile = null;

function currentItem() {
  if (kind() === 'file') return pickedFile ? { kind: 'file', name: pickedFile.name, data: pickedFile.data } : null;
  return { kind: 'text', text: $('secret').value };
}

// The size before compression: a safe upper bound shown while typing.
function updateCapacity() {
  const item = currentItem();
  const size = (item ? packItem(item).length : 0) + ($('passphrase').value ? ENCRYPTION_OVERHEAD : 0);
  const cap = core ? core.capacity : 758;
  const fill = $('fill');
  fill.style.width = `${Math.min(100, (size / cap) * 100)}%`;
  fill.className = size > cap ? 'warn' : '';
  $('capacity-text').textContent =
    size > cap ? `${size} bytes: may not fit (text is compressed when you make the page)` : `${size} of ${cap} bytes`;
}

function updateStrength() {
  const p = $('passphrase').value;
  const el = $('strength');
  const bits = passphraseBits(p);
  if (!p) {
    el.textContent = 'Anyone with the paper can read an unlocked page.';
    el.className = 'hint';
  } else if (bits < 50) {
    el.textContent = `Weak (about ${bits} bits). Someone with the paper could guess it. Try Generate.`;
    el.className = 'hint warn';
  } else {
    el.textContent = `Strong (about ${bits} bits). Keep the passphrase somewhere other than the paper.`;
    el.className = 'hint good';
  }
}

for (const r of document.querySelectorAll('input[name="kind"]')) {
  r.addEventListener('change', () => {
    $('text-field').hidden = kind() !== 'text';
    $('file-field').hidden = kind() !== 'file';
    updateCapacity();
  });
}
$('secret').addEventListener('input', updateCapacity);
$('passphrase').addEventListener('input', () => {
  updateStrength();
  updateCapacity();
});
$('generate').addEventListener('click', () => {
  $('passphrase').value = generatePassphrase();
  updateStrength();
  updateCapacity();
});
$('file').addEventListener('change', async () => {
  const f = $('file').files[0];
  pickedFile = null;
  $('make-error').hidden = true;
  if (f && f.size > MAX_FILE) {
    showError('make-error', 'That file is far too big for one page. Inkvault is for small, precious things.');
  } else if (f) {
    pickedFile = { name: safeFileName(f.name), data: new Uint8Array(await f.arrayBuffer()) };
  }
  updateCapacity();
});

function showError(id, message) {
  const el = $(id);
  el.textContent = message;
  el.hidden = false;
}

$('make-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  $('make-error').hidden = true;
  const item = currentItem();
  if (!item || (item.kind === 'text' && !item.text.trim())) {
    showError('make-error', kind() === 'file' ? 'Choose a file first.' : 'Type something to keep first.');
    return;
  }
  const button = $('make-button');
  button.disabled = true;
  button.textContent = 'Making…';
  try {
    const { bytes, flags } = await seal(item, $('passphrase').value);
    if (bytes.length > core.capacity) {
      showError('make-error', `That is ${bytes.length} bytes once packed; one page holds ${core.capacity}. Shorten it a little.`);
      return;
    }
    const cells = core.encode(bytes, flags);
    core.wipe();
    current = { cells, title: $('title').value.trim(), flags, size: bytes.length };
    drawSheet();
  } catch (err) {
    showError('make-error', err instanceof InkvaultError || err instanceof RangeError ? err.message : 'Something went wrong making the page.');
  } finally {
    button.disabled = false;
    button.textContent = 'Make the page';
  }
});

function drawSheet() {
  const sheet = $('sheet');
  sheet.replaceChildren();
  const h = document.createElement('h3');
  h.textContent = current.title || 'Inkvault page';
  const meta = document.createElement('p');
  meta.className = 'meta';
  meta.append(`Made ${new Date().toLocaleDateString(undefined, { day: 'numeric', month: 'long', year: 'numeric' })} · ${current.size} bytes · `);
  if (current.flags & FLAG_ENCRYPTED) {
    const lock = document.createElement('span');
    lock.className = 'lock';
    lock.textContent = 'LOCKED';
    meta.append(lock, ' needs its passphrase');
  } else {
    meta.append('not locked: keep this paper safe');
  }
  const foot = document.createElement('p');
  foot.className = 'foot';
  foot.textContent =
    'To read: open reihooneh.github.io/inkvault, choose "Read a page" and point a phone camera at this sheet. ' +
    'Keep all four corner squares in view. Survives stains, creases and small tears.';
  sheet.append(h, meta, pageSvg(current.cells, core.cols, core.rows), foot);
  $('sheet-actions').hidden = false;
}

$('print').addEventListener('click', () => window.print());
$('save-image').addEventListener('click', () => {
  pageCanvas(current.cells, core.cols, core.rows, 12).toBlob((blob) => {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = 'inkvault-page.png';
    a.click();
    setTimeout(() => URL.revokeObjectURL(a.href), 10_000);
  });
});
$('to-lab').addEventListener('click', () => showTab('lab'));

// ---------- read ----------
function setStatus(id, text, tone) {
  const el = $(id);
  el.textContent = text;
  el.className = `status ${tone || ''}`;
}

function drawCorners(ctx, corners, scale) {
  ctx.strokeStyle = '#2fbf5a';
  ctx.lineWidth = Math.max(3, ctx.canvas.width / 200);
  ctx.beginPath();
  for (let i = 0; i < 4; i++) {
    const x = corners[2 * i] / scale, y = corners[2 * i + 1] / scale;
    if (i === 0) ctx.moveTo(x, y);
    else ctx.lineTo(x, y);
  }
  ctx.closePath();
  ctx.stroke();
}

function healthText(r) {
  const used = r.limit ? r.worst / r.limit : 0;
  const pct = Math.round(used * 100);
  const text =
    r.repaired === 0
      ? 'Read perfectly: no damage to repair.'
      : `${r.repaired} damaged byte${r.repaired === 1 ? '' : 's'} repaired. The worst-hit part used ${r.worst} of its ${r.limit} repairs (${pct}%).`;
  const advice = used > 0.6 ? ' This page is getting worn. Print a fresh copy soon.' : '';
  return { text: text + advice, pct, tone: used > 0.6 ? 'warn' : '' };
}

function setHealth(fillId, textId, r) {
  const h = healthText(r);
  $(fillId).style.width = `${Math.max(4, h.pct)}%`;
  $(fillId).className = h.tone;
  $(textId).textContent = h.text;
}

// Tries a few sizes: a smaller image helps when the photo is noisy or the page is small.
function decodeSource(source, sides = [core.maxSide, 1100, 800]) {
  let last = null;
  for (const side of sides) {
    const g = grayFrom(source, side);
    const r = core.decodeGray(g.gray, g.width, g.height);
    r.scale = g.scale;
    if (r.ok) return r;
    if (!last || r.code === -4) last = r;
  }
  return last;
}

async function handleRead(r, source) {
  const view = $('view');
  view.width = source.videoWidth || source.width;
  view.height = source.videoHeight || source.height;
  const ctx = view.getContext('2d');
  ctx.drawImage(source, 0, 0);
  view.hidden = false;
  if (!r.ok) {
    setStatus('read-status', r.error, 'bad');
    return false;
  }
  drawCorners(ctx, r.corners, r.scale);
  decoded = { bytes: r.bytes, flags: r.flags };
  core.wipe();
  setStatus('read-status', 'Page found and read.', 'good');
  $('health').hidden = false;
  setHealth('health-fill', 'health-text', r);
  $('read-empty').hidden = true;
  if (r.flags & FLAG_ENCRYPTED) {
    $('unlock').hidden = false;
    $('unlock-pass').focus();
  } else {
    await openDecoded('');
  }
  return true;
}

async function openDecoded(passphrase) {
  $('read-error').hidden = true;
  try {
    shown = await open(decoded.bytes, decoded.flags, passphrase);
  } catch (err) {
    showError('read-error', err instanceof InkvaultError ? err.message : 'Could not open the page.');
    return;
  }
  $('unlock').hidden = true;
  $('unlock-pass').value = '';
  const result = $('result');
  if (shown.kind === 'text') {
    result.textContent = shown.text;
    $('download').hidden = true;
    $('copy').hidden = false;
  } else {
    result.textContent = `File: ${shown.name} (${shown.data.length} bytes)`;
    $('download').hidden = false;
    $('copy').hidden = true;
  }
  result.hidden = false;
  $('result-actions').hidden = false;
}

$('unlock').addEventListener('submit', async (e) => {
  e.preventDefault();
  const button = $('unlock').querySelector('button');
  button.disabled = true;
  button.textContent = 'Unlocking…';
  await openDecoded($('unlock-pass').value);
  button.disabled = false;
  button.textContent = 'Unlock';
});

$('copy').addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(shown.text);
    $('copy').textContent = 'Copied';
  } catch {
    $('copy').textContent = 'Copy failed: select the text instead';
  }
  setTimeout(() => ($('copy').textContent = 'Copy'), 2000);
});
$('download').addEventListener('click', () => {
  // Always a plain download: the browser never opens or runs the file.
  const blob = new Blob([shown.data], { type: 'application/octet-stream' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = safeFileName(shown.name);
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 10_000);
});
$('clear').addEventListener('click', () => {
  if (decoded) decoded.bytes.fill(0);
  shown = decoded = null;
  core.wipe();
  $('result').textContent = '';
  for (const id of ['result', 'result-actions', 'health', 'unlock', 'view']) $(id).hidden = true;
  $('read-empty').hidden = false;
  setStatus('read-status', '');
});

$('photo').addEventListener('change', async () => {
  const f = $('photo').files[0];
  $('photo').value = '';
  if (!f) return;
  stopCamera();
  if (f.size > MAX_PHOTO) {
    setStatus('read-status', 'Choose a photo (an image file under 40 MB).', 'bad');
    return;
  }
  setStatus('read-status', 'Reading…');
  let bitmap;
  try {
    bitmap = await createImageBitmap(f);
  } catch {
    setStatus('read-status', 'That image could not be opened.', 'bad');
    return;
  }
  await handleRead(decodeSource(bitmap), bitmap);
  bitmap.close();
});

async function startCamera() {
  if (!navigator.mediaDevices?.getUserMedia) {
    setStatus('read-status', 'This browser cannot use the camera here. Choose a photo instead.', 'bad');
    return;
  }
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: 'environment', width: { ideal: 1920 }, height: { ideal: 1080 } },
      audio: false,
    });
    const video = $('video');
    video.srcObject = stream;
    video.hidden = false;
    $('view').hidden = true;
    await video.play();
    camera = { stream, timer: 0 };
    $('camera').textContent = 'Stop the camera';
    setStatus('read-status', 'Looking for the four corner squares…');
    const tick = async () => {
      if (!camera) return;
      if (video.videoWidth) {
        const r = decodeSource(video, [1280]); // one size per frame keeps the camera smooth
        if (r.ok) {
          const frame = grayFrame(video);
          stopCamera();
          await handleRead(r, frame);
          return;
        }
        if (r.code === -4) setStatus('read-status', 'Found the page. Hold still, closer and in better light…');
      }
      camera.timer = setTimeout(tick, 250);
    };
    tick();
  } catch {
    setStatus('read-status', 'No camera, or permission was refused. You can choose a photo instead.', 'bad');
  }
}

function grayFrame(video) { // a still of the frame that was read, for the preview
  const c = document.createElement('canvas');
  c.width = video.videoWidth;
  c.height = video.videoHeight;
  c.getContext('2d').drawImage(video, 0, 0);
  return c;
}

function stopCamera() {
  if (!camera) return;
  clearTimeout(camera.timer);
  for (const track of camera.stream.getTracks()) track.stop();
  camera = null;
  $('video').srcObject = null;
  $('video').hidden = true;
  $('camera').textContent = 'Use the camera';
}
$('camera').addEventListener('click', () => (camera ? stopCamera() : startCamera()));
document.addEventListener('visibilitychange', () => document.hidden && stopCamera());

// ---------- damage lab ----------
let labSeed = 7;
let labPage = null;
let labTimer = 0;

async function samplePage() {
  const { bytes, flags } = await seal({
    kind: 'text',
    text: 'This is a sample Inkvault page. If you can read this, the page survived everything you threw at it.',
  });
  return core.encode(bytes, flags);
}

function labSettings() {
  const s = { seed: labSeed };
  for (const input of $('controls').querySelectorAll('input')) {
    s[input.id] = Number(input.value);
    const out = input.parentElement.querySelector('output');
    const v = Number(input.value);
    out.textContent =
      input.id === 'rotate' ? `${v}°`
        : ['tilt', 'shadow', 'blot', 'tear'].includes(input.id) ? `${Math.round(v * 100)}%`
          : input.id === 'blur' ? `${v} px` : String(v);
  }
  return s;
}

async function runLab() {
  if (!core) return;
  const cells = current ? current.cells : (labPage ??= await samplePage());
  const page = pageCanvas(cells, core.cols, core.rows, 5);
  const photo = photograph(page, labSettings());
  const view = $('lab-photo');
  const ctx = view.getContext('2d');
  ctx.drawImage(photo, 0, 0);
  const g = grayFrom(photo, core.maxSide);
  const r = core.decodeGray(g.gray, g.width, g.height);
  if (r.ok) {
    drawCorners(ctx, r.corners, 1);
    setStatus('lab-status', current ? 'Read back: your page survived.' : 'Read back: the sample page survived.', 'good');
    setHealth('lab-fill', 'lab-text', r);
  } else {
    setStatus('lab-status', r.error, 'bad');
    $('lab-fill').style.width = '100%';
    $('lab-fill').className = 'full';
    $('lab-text').textContent = 'Too much damage: more than error correction can repair, or a corner square is hidden.';
  }
}
$('controls').addEventListener('input', () => {
  clearTimeout(labTimer);
  labTimer = setTimeout(runLab, 60);
});
$('reshuffle').addEventListener('click', () => {
  labSeed = (labSeed * 7919 + 13) % 100000;
  runLab();
});

// ---------- start ----------
try {
  core = await loadCore(new URL('inkvault.wasm', import.meta.url));
  updateCapacity();
  updateStrength();
  document.documentElement.dataset.ready = 'true';
} catch {
  showError('make-error', 'The decoder could not load. Please reload the page.');
}
