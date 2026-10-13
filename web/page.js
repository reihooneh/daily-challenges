// Drawing pages (for print and for pictures) and the Damage Lab's fake photographs.

const SVG = 'http://www.w3.org/2000/svg';
export const MARGIN_CELLS = 4; // a light border the camera needs around the code

// The code as one SVG path: each run of dark cells in a row is one rectangle.
export function pageSvg(cells, cols, rows) {
  const svg = document.createElementNS(SVG, 'svg');
  const size = (n) => n + 2 * MARGIN_CELLS;
  svg.setAttribute('viewBox', `0 0 ${size(cols)} ${size(rows)}`);
  svg.setAttribute('shape-rendering', 'crispEdges');
  svg.setAttribute('role', 'img');
  svg.setAttribute('aria-label', 'Inkvault code');
  const bg = document.createElementNS(SVG, 'rect');
  bg.setAttribute('width', String(size(cols)));
  bg.setAttribute('height', String(size(rows)));
  bg.setAttribute('fill', '#fff');
  svg.append(bg);
  let d = '';
  for (let r = 0; r < rows; r++) {
    let c = 0;
    while (c < cols) {
      if (!cells[r * cols + c]) {
        c++;
        continue;
      }
      let end = c;
      while (end < cols && cells[r * cols + end]) end++;
      d += `M${c + MARGIN_CELLS} ${r + MARGIN_CELLS}h${end - c}v1h${c - end}z`;
      c = end;
    }
  }
  const path = document.createElementNS(SVG, 'path');
  path.setAttribute('d', d);
  path.setAttribute('fill', '#000');
  svg.append(path);
  return svg;
}

export function pageCanvas(cells, cols, rows, scale) {
  const canvas = document.createElement('canvas');
  canvas.width = (cols + 2 * MARGIN_CELLS) * scale;
  canvas.height = (rows + 2 * MARGIN_CELLS) * scale;
  const ctx = canvas.getContext('2d');
  ctx.fillStyle = '#fff';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = '#000';
  for (let r = 0; r < rows; r++)
    for (let c = 0; c < cols; c++)
      if (cells[r * cols + c]) ctx.fillRect((c + MARGIN_CELLS) * scale, (r + MARGIN_CELLS) * scale, scale, scale);
  return canvas;
}

// A seeded random generator, so the same settings give the same "photo".
function random(seed) {
  let s = seed >>> 0 || 1;
  return () => {
    s ^= s << 13;
    s ^= s >>> 17;
    s ^= s << 5;
    return (s >>> 0) / 4294967296;
  };
}

// Solves the perspective transform (homography) taking four points (u, v) to (x, y).
export function homography(u, v, x, y) {
  const a = [];
  for (let i = 0; i < 4; i++) {
    a.push([u[i], v[i], 1, 0, 0, 0, -u[i] * x[i], -v[i] * x[i], x[i]]);
    a.push([0, 0, 0, u[i], v[i], 1, -u[i] * y[i], -v[i] * y[i], y[i]]);
  }
  for (let c = 0; c < 8; c++) {
    let p = c;
    for (let r = c + 1; r < 8; r++) if (Math.abs(a[r][c]) > Math.abs(a[p][c])) p = r;
    [a[c], a[p]] = [a[p], a[c]];
    for (let r = 0; r < 8; r++) {
      if (r === c) continue;
      const f = a[r][c] / a[c][c];
      for (let k = c; k < 9; k++) a[r][k] -= f * a[c][k];
    }
  }
  return [...a.map((row, i) => row[8] / row[i]), 1];
}

const TABLE = [111, 103, 94];

// Fakes a phone photo of a printed page. Settings (all 0 = perfect):
//   rotate (degrees), tilt (0..0.35 perspective), blur (px), noise (0..80), shadow (0..0.7),
//   stains (count), blot (0..0.25 of the page), tear (0..0.3 of the page), seed.
// Stains, ink and tears are drawn on the paper first, so the camera sees them in perspective.
export function photograph(page, s) {
  const pw0 = page.width, ph0 = page.height;
  const paper = document.createElement('canvas');
  paper.width = pw0;
  paper.height = ph0;
  const pc = paper.getContext('2d', { willReadFrequently: true });
  pc.drawImage(page, 0, 0);
  const rnd = random(s.seed || 7);
  for (let i = 0; i < (s.stains || 0); i++) { // coffee: translucent brown discs with a darker ring
    const x = (0.15 + rnd() * 0.7) * pw0, y = (0.15 + rnd() * 0.7) * ph0, r = pw0 * (0.08 + rnd() * 0.08);
    const g = pc.createRadialGradient(x, y, r * 0.2, x, y, r);
    g.addColorStop(0, 'rgba(140, 90, 40, 0.25)');
    g.addColorStop(0.85, 'rgba(120, 75, 30, 0.35)');
    g.addColorStop(0.95, 'rgba(90, 50, 20, 0.6)');
    g.addColorStop(1, 'rgba(90, 50, 20, 0)');
    pc.fillStyle = g;
    pc.beginPath();
    pc.arc(x, y, r, 0, Math.PI * 2);
    pc.fill();
  }
  if (s.blot > 0) { // ink: a solid blot near the middle
    pc.fillStyle = '#121218';
    pc.beginPath();
    pc.ellipse(pw0 * 0.56, ph0 * 0.53, pw0 * s.blot, ph0 * s.blot * 0.6, 0.4, 0, Math.PI * 2);
    pc.fill();
  }
  const paperPx = pc.getImageData(0, 0, pw0, ph0).data;

  // Where the page's corners land in the photo: rotated, with the top edge further away.
  const W = 760, H = 1000;
  const angle = ((s.rotate || 0) * Math.PI) / 180, cos = Math.cos(angle), sin = Math.sin(angle);
  // Step back far enough that the whole rotated page is in the shot, as a person would.
  const ac = Math.abs(cos), as = Math.abs(sin);
  const fit = Math.min((W * 0.9) / (pw0 * ac + ph0 * as), (H * 0.9) / (pw0 * as + ph0 * ac));
  const hw = (pw0 * fit) / 2, hh = (ph0 * fit) / 2, t = s.tilt || 0;
  const local = [[-hw * (1 - t), -hh * (1 - 0.3 * t)], [hw * (1 - t), -hh * (1 - 0.3 * t)], [hw, hh], [-hw, hh]];
  const dx = [], dy = [];
  for (const [x, y] of local) {
    dx.push(W / 2 + x * cos - y * sin);
    dy.push(H / 2 + x * sin + y * cos);
  }
  const h = homography(dx, dy, [0, pw0, pw0, 0], [0, 0, ph0, ph0]); // photo -> paper

  // A torn edge: part of the right-hand side is missing, so the table shows through.
  const torn = (u, v) => s.tear > 0 && u > pw0 * (1 - s.tear) && v > ph0 * 0.3 && v < ph0 * (0.3 + s.tear) &&
    u - pw0 * (1 - s.tear) > (v - ph0 * 0.3) * 0.3;

  const out = document.createElement('canvas');
  out.width = W;
  out.height = H;
  const ctx = out.getContext('2d', { willReadFrequently: true });
  const image = ctx.createImageData(W, H);
  const px = image.data;
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const d = h[6] * x + h[7] * y + h[8];
      const u = (h[0] * x + h[1] * y + h[2]) / d, v = (h[3] * x + h[4] * y + h[5]) / d;
      const o = (y * W + x) * 4;
      if (u >= 0 && v >= 0 && u < pw0 - 1 && v < ph0 - 1 && !torn(u, v)) {
        const i = ((v | 0) * pw0 + (u | 0)) * 4;
        px[o] = paperPx[i];
        px[o + 1] = paperPx[i + 1];
        px[o + 2] = paperPx[i + 2];
      } else {
        px[o] = TABLE[0];
        px[o + 1] = TABLE[1];
        px[o + 2] = TABLE[2];
      }
      px[o + 3] = 255;
    }
  }
  // A shadow falling across the top-left, then camera blur and sensor noise.
  if (s.shadow > 0) {
    for (let y = 0; y < H; y++)
      for (let x = 0; x < W; x++) {
        const k = 1 - s.shadow * Math.max(0, 1 - (x / W + y / H) * 0.9);
        const o = (y * W + x) * 4;
        px[o] *= k;
        px[o + 1] *= k;
        px[o + 2] *= k;
      }
  }
  if (s.blur > 0) boxBlur(image, Math.round(s.blur));
  if (s.noise > 0) {
    for (let i = 0; i < px.length; i += 4) {
      const n = (rnd() - 0.5) * 2 * s.noise;
      px[i] += n;
      px[i + 1] += n;
      px[i + 2] += n;
    }
  }
  ctx.putImageData(image, 0, 0);
  return out;
}

function boxBlur(image, r) {
  const { width: w, height: h, data } = image;
  const tmp = new Float32Array(w * h * 3);
  for (let pass = 0; pass < 2; pass++) {
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        let a = 0, b = 0, c = 0, n = 0;
        for (let k = -r; k <= r; k++) {
          const xx = pass ? x : x + k, yy = pass ? y + k : y;
          if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
          const i = yy * w + xx;
          if (pass) {
            a += tmp[i * 3];
            b += tmp[i * 3 + 1];
            c += tmp[i * 3 + 2];
          } else {
            a += data[i * 4];
            b += data[i * 4 + 1];
            c += data[i * 4 + 2];
          }
          n++;
        }
        const i = y * w + x;
        if (pass) {
          data[i * 4] = a / n;
          data[i * 4 + 1] = b / n;
          data[i * 4 + 2] = c / n;
        } else {
          tmp[i * 3] = a / n;
          tmp[i * 3 + 1] = b / n;
          tmp[i * 3 + 2] = c / n;
        }
      }
    }
  }
}

// Scales any image source to fit within `maxSide` and returns its grey pixels.
export function grayFrom(source, maxSide) {
  const sw = source.videoWidth || source.width, sh = source.videoHeight || source.height;
  const k = Math.min(1, maxSide / Math.max(sw, sh));
  const w = Math.max(1, Math.round(sw * k)), h = Math.max(1, Math.round(sh * k));
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  ctx.drawImage(source, 0, 0, w, h);
  const rgba = ctx.getImageData(0, 0, w, h).data;
  const gray = new Uint8Array(w * h);
  for (let i = 0, j = 0; i < gray.length; i++, j += 4) gray[i] = (rgba[j] * 299 + rgba[j + 1] * 587 + rgba[j + 2] * 114) / 1000;
  return { gray, width: w, height: h, scale: k };
}
