/*
 * Reading a page from a photo:
 *
 *   1. Adaptive threshold: each pixel is dark if it is darker than its neighbourhood,
 *      so shadows and uneven light don't matter (Bradley's method, with an integral image).
 *   2. Find the corner squares: scan for the 1:1:3:1:1 dark-light-dark-light-dark
 *      pattern across rows, then confirm it down the column and across again.
 *   3. Pick the four squares that make the biggest four-sided shape: the page corners.
 *   4. Fit a homography (perspective transform) from page cells to photo pixels, sample
 *      every cell, and let Reed-Solomon repair the damage. We don't know which corner is
 *      the top-left (or whether the photo is mirrored), so we try all eight ways;
 *      only the right one gets past the error correction and the checksum.
 */
#include "inkvault.h"

#define MAX_CANDIDATES 256
#define MIN_MODULE 2.0 /* smaller patterns are speckle, not corner squares */
#define MAX_QUADS 6

typedef struct {
  double x, y, module; /* centre and size of one cell, in pixels */
  int count;           /* how many scan lines confirmed it */
} candidate;

typedef struct {
  const uint8_t *bin; /* 1 = dark */
  int w, h;
  candidate c[MAX_CANDIDATES];
  int n;
} finder_state;

static double absd(double v) { return v < 0 ? -v : v; }

size_t iv_work_size(int w, int h) {
  if (w < IV_MIN_SIDE || h < IV_MIN_SIDE || w > IV_MAX_SIDE || h > IV_MAX_SIDE) return 0;
  return (size_t)w * (size_t)h + 8 + 4u * (size_t)(w + 1) * (size_t)(h + 1);
}

/* ---- 1. adaptive threshold ---- */

static void threshold(const uint8_t *gray, int w, int h, uint8_t *bin, uint32_t *integral) {
  const int iw = w + 1;
  for (int x = 0; x <= w; x++) integral[x] = 0;
  for (int y = 1; y <= h; y++) {
    uint32_t row = 0;
    integral[(size_t)y * (size_t)iw] = 0;
    for (int x = 1; x <= w; x++) {
      row += gray[(y - 1) * w + (x - 1)];
      integral[y * iw + x] = integral[(y - 1) * iw + x] + row;
    }
  }
  int half = (w > h ? w : h) / 16;
  if (half < 4) half = 4;
  for (int y = 0; y < h; y++) {
    int y0 = y - half < 0 ? 0 : y - half, y1 = y + half >= h ? h - 1 : y + half;
    for (int x = 0; x < w; x++) {
      int x0 = x - half < 0 ? 0 : x - half, x1 = x + half >= w ? w - 1 : x + half;
      uint64_t area = (uint64_t)(x1 - x0 + 1) * (uint64_t)(y1 - y0 + 1);
      uint64_t sum = (uint64_t)integral[(y1 + 1) * iw + (x1 + 1)] - integral[y0 * iw + (x1 + 1)] -
                     integral[(y1 + 1) * iw + x0] + integral[y0 * iw + x0];
      /* dark if more than 15% darker than the local average, and by at least 10 levels
       * (so camera noise on a plain, dim background doesn't count) */
      uint64_t g = (uint64_t)gray[y * w + x] * area;
      bin[y * w + x] = (uint8_t)(g * 100u < sum * 85u && g + 10u * area < sum);
    }
  }
}

/* ---- 2. finder patterns ---- */

static int ratio_ok(const int counts[5]) {
  int total = 0;
  for (int i = 0; i < 5; i++) {
    if (counts[i] == 0) return 0;
    total += counts[i];
  }
  if (total < 7) return 0;
  double module = total / 7.0, tolerance = module / 1.6;
  return absd(module - counts[0]) < tolerance && absd(module - counts[1]) < tolerance &&
         absd(3 * module - counts[2]) < 3 * tolerance && absd(module - counts[3]) < tolerance &&
         absd(module - counts[4]) < tolerance;
}

static double centre_from_end(const int counts[5], int end) {
  return end - counts[4] - counts[3] - counts[2] / 2.0;
}

/* Walks out from (x, y) along a line (dx, dy) and back, measuring the five runs.
 * Returns the refined centre along that line, or a negative number. */
static double cross_check(const finder_state *s, int x, int y, int dx, int dy, int maxCount, int originalTotal) {
  int counts[5] = {0, 0, 0, 0, 0};
  int cx = x, cy = y;
#define DARK(px, py) ((px) >= 0 && (py) >= 0 && (px) < s->w && (py) < s->h && s->bin[(py) * s->w + (px)])
#define INSIDE(px, py) ((px) >= 0 && (py) >= 0 && (px) < s->w && (py) < s->h)
  while (INSIDE(cx, cy) && DARK(cx, cy)) { counts[2]++; cx -= dx; cy -= dy; }
  if (!INSIDE(cx, cy)) return -1;
  while (INSIDE(cx, cy) && !DARK(cx, cy) && counts[1] <= maxCount) { counts[1]++; cx -= dx; cy -= dy; }
  if (!INSIDE(cx, cy) || counts[1] > maxCount) return -1;
  while (INSIDE(cx, cy) && DARK(cx, cy) && counts[0] <= maxCount) { counts[0]++; cx -= dx; cy -= dy; }
  if (counts[0] > maxCount) return -1;
  cx = x + dx;
  cy = y + dy;
  while (INSIDE(cx, cy) && DARK(cx, cy)) { counts[2]++; cx += dx; cy += dy; }
  if (!INSIDE(cx, cy)) return -1;
  while (INSIDE(cx, cy) && !DARK(cx, cy) && counts[3] < maxCount) { counts[3]++; cx += dx; cy += dy; }
  if (!INSIDE(cx, cy) || counts[3] >= maxCount) return -1;
  while (INSIDE(cx, cy) && DARK(cx, cy) && counts[4] < maxCount) { counts[4]++; cx += dx; cy += dy; }
  if (counts[4] >= maxCount) return -1;
#undef DARK
#undef INSIDE
  int total = counts[0] + counts[1] + counts[2] + counts[3] + counts[4];
  if (5 * absd(total - originalTotal) >= 2 * originalTotal) return -1;
  if (!ratio_ok(counts)) return -1;
  int end = dx ? cx : cy; /* one past the last dark pixel */
  return centre_from_end(counts, end);
}

static void add_candidate(finder_state *s, double x, double y, double module) {
  for (int i = 0; i < s->n; i++) {
    candidate *c = &s->c[i];
    if (absd(c->x - x) <= c->module * 1.5 && absd(c->y - y) <= c->module * 1.5 &&
        absd(c->module - module) <= c->module) {
      double n = c->count;
      c->x = (c->x * n + x) / (n + 1);
      c->y = (c->y * n + y) / (n + 1);
      c->module = (c->module * n + module) / (n + 1);
      c->count++;
      return;
    }
  }
  if (s->n < MAX_CANDIDATES) {
    s->c[s->n++] = (candidate){x, y, module, 1};
  }
}

static void try_pattern(finder_state *s, const int counts[5], int x_end, int y) {
  int total = counts[0] + counts[1] + counts[2] + counts[3] + counts[4];
  double cx = centre_from_end(counts, x_end);
  double cy = cross_check(s, (int)cx, y, 0, 1, counts[2], total);
  if (cy < 0) return;
  double cx2 = cross_check(s, (int)cx, (int)cy, 1, 0, counts[2], total);
  if (cx2 < 0) return;
  if (total / 7.0 < MIN_MODULE) return;
  add_candidate(s, cx2, cy, total / 7.0);
}

static void find_candidates(finder_state *s) {
  for (int y = 0; y < s->h; y++) {
    int counts[5] = {0, 0, 0, 0, 0};
    int state = 0;
    const uint8_t *row = s->bin + (size_t)y * (size_t)s->w;
    for (int x = 0; x < s->w; x++) {
      if (row[x]) {
        if (state & 1) state++; /* light -> dark */
        counts[state]++;
      } else if (state & 1) {
        counts[state]++;
      } else if (state == 0 && counts[0] == 0) {
        continue; /* still looking for the first dark run */
      } else if (state == 4) {
        if (ratio_ok(counts)) try_pattern(s, counts, x, y);
        counts[0] = counts[2];
        counts[1] = counts[3];
        counts[2] = counts[4];
        counts[3] = 1;
        counts[4] = 0;
        state = 3;
      } else {
        state++;
        counts[state]++;
      }
    }
    if (state == 4 && ratio_ok(counts)) try_pattern(s, counts, s->w, y);
  }
}

/* ---- 3. the four corners ---- */

/* Increases steadily with the angle of (dx, dy), without needing atan2. */
static double pseudo_angle(double dx, double dy) {
  double p = dx / (absd(dx) + absd(dy) + 1e-12);
  return dy >= 0 ? 1 - p : 3 + p;
}

typedef struct {
  double x[4], y[4];
  double area;
} quad;

/* Orders four points around their centre; returns the area, or 0 if not convex. */
static double make_quad(const candidate *pts[4], quad *q) {
  double mx = 0, my = 0;
  for (int i = 0; i < 4; i++) { mx += pts[i]->x / 4; my += pts[i]->y / 4; }
  int order[4] = {0, 1, 2, 3};
  for (int i = 1; i < 4; i++) { /* insertion sort by angle */
    for (int j = i; j > 0; j--) {
      const candidate *a = pts[order[j - 1]], *b = pts[order[j]];
      if (pseudo_angle(a->x - mx, a->y - my) > pseudo_angle(b->x - mx, b->y - my)) {
        int t = order[j]; order[j] = order[j - 1]; order[j - 1] = t;
      }
    }
  }
  for (int i = 0; i < 4; i++) { q->x[i] = pts[order[i]]->x; q->y[i] = pts[order[i]]->y; }
  double area = 0;
  int sign = 0;
  for (int i = 0; i < 4; i++) {
    int j = (i + 1) % 4, k = (i + 2) % 4;
    area += q->x[i] * q->y[j] - q->x[j] * q->y[i];
    double cross = (q->x[j] - q->x[i]) * (q->y[k] - q->y[j]) - (q->y[j] - q->y[i]) * (q->x[k] - q->x[j]);
    int sg = cross > 0 ? 1 : -1;
    if (sign && sg != sign) return 0;
    sign = sg;
  }
  return absd(area) / 2;
}

/* ---- 4. homography and sampling ---- */

/* Solves for H (h[8] = 1) mapping (u, v) -> (x, y) for four point pairs. */
static int solve_homography(const double u[4], const double v[4], const double x[4], const double y[4], double h[9]) {
  double a[8][9];
  for (int i = 0; i < 4; i++) {
    double r0[9] = {u[i], v[i], 1, 0, 0, 0, -u[i] * x[i], -v[i] * x[i], x[i]};
    double r1[9] = {0, 0, 0, u[i], v[i], 1, -u[i] * y[i], -v[i] * y[i], y[i]};
    const int even = 2 * i, odd = 2 * i + 1;
    for (int j = 0; j < 9; j++) { a[even][j] = r0[j]; a[odd][j] = r1[j]; }
  }
  for (int col = 0; col < 8; col++) { /* Gaussian elimination with partial pivoting */
    int pivot = col;
    for (int r = col + 1; r < 8; r++) if (absd(a[r][col]) > absd(a[pivot][col])) pivot = r;
    if (absd(a[pivot][col]) < 1e-9) return 0;
    for (int j = 0; j < 9; j++) { double t = a[col][j]; a[col][j] = a[pivot][j]; a[pivot][j] = t; }
    for (int r = 0; r < 8; r++) {
      if (r == col) continue;
      double f = a[r][col] / a[col][col];
      for (int j = col; j < 9; j++) a[r][j] -= f * a[col][j];
    }
  }
  for (int i = 0; i < 8; i++) h[i] = a[i][8] / a[i][i];
  h[8] = 1;
  return 1;
}

static int sample(const finder_state *s, const double h[9], double u, double v) {
  double d = h[6] * u + h[7] * v + h[8];
  if (absd(d) < 1e-12) return 0;
  double x = (h[0] * u + h[1] * v + h[2]) / d, y = (h[3] * u + h[4] * v + h[5]) / d;
  if (!(x >= 0 && y >= 0 && x < s->w && y < s->h)) return 0; /* also rejects NaN */
  return s->bin[(int)y * s->w + (int)x];
}

static int read_page(const finder_state *s, const quad *q, int start, int dir, uint8_t *cells, uint8_t *unsure,
                     uint8_t *payload, iv_info *info) {
  /* Finder centres in page cell coordinates: top-left, top-right, bottom-right, bottom-left. */
  const double c = IV_FINDER / 2.0;
  const double u[4] = {c, IV_COLS - c, IV_COLS - c, c};
  const double v[4] = {c, c, IV_ROWS - c, IV_ROWS - c};
  double x[4], y[4], h[9];
  for (int i = 0; i < 4; i++) {
    int k = ((start + dir * i) % 4 + 4) % 4;
    x[i] = q->x[k];
    y[i] = q->y[k];
  }
  if (!solve_homography(u, v, x, y, h)) return IV_ERR_NO_PAGE;
  for (int row = 0; row < IV_ROWS; row++) {
    for (int col = 0; col < IV_COLS; col++) {
      int votes = 0; /* nine samples near the cell centre, majority wins */
      for (int dy = -1; dy <= 1; dy++)
        for (int dx = -1; dx <= 1; dx++) votes += sample(s, h, col + 0.5 + 0.22 * dx, row + 0.5 + 0.22 * dy);
      cells[row * IV_COLS + col] = (uint8_t)(votes >= 5);
      unsure[row * IV_COLS + col] = (uint8_t)(votes >= 3 && votes <= 6); /* a split vote */
    }
  }
  int len = iv_decode_cells_doubt(cells, unsure, payload, info);
  if (len >= 0 && info) {
    for (int i = 0; i < 4; i++) {
      const int k = 2 * i;
      info->corners[k] = (int32_t)x[i];
      info->corners[k + 1] = (int32_t)y[i];
    }
  }
  return len;
}

int iv_decode_image(const uint8_t *gray, int w, int h, uint8_t *work, uint8_t *payload, iv_info *info) {
  if (iv_work_size(w, h) == 0) return IV_ERR_IMAGE_SIZE;
  if (info) iv_memset(info, 0, sizeof *info);
  uint8_t *bin = work;
  uintptr_t aligned = ((uintptr_t)(work + (size_t)w * (size_t)h) + 7u) & ~(uintptr_t)7u;
  threshold(gray, w, h, bin, (uint32_t *)aligned);

  static finder_state s; /* static: too big for the WebAssembly stack */
  s.bin = bin;
  s.w = w;
  s.h = h;
  s.n = 0;
  find_candidates(&s);
  if (info) info->candidates = s.n;

  /* Keep the most-confirmed candidates: real corner squares are seen on many scan lines. */
  for (int i = 1; i < s.n; i++) {
    for (int j = i; j > 0 && s.c[j - 1].count < s.c[j].count; j--) {
      candidate t = s.c[j];
      s.c[j] = s.c[j - 1];
      s.c[j - 1] = t;
    }
  }
  const candidate *best[12];
  int nb = 0;
  for (int i = 0; i < s.n && nb < 12; i++) best[nb++] = &s.c[i];
  if (nb < 4) return IV_ERR_NO_PAGE;

  /* Every convex four-point shape with similar cell sizes, largest first. */
  quad quads[MAX_QUADS];
  int nq = 0;
  for (int a = 0; a < nb; a++)
    for (int b = a + 1; b < nb; b++)
      for (int c = b + 1; c < nb; c++)
        for (int d = c + 1; d < nb; d++) {
          const candidate *pts[4] = {best[a], best[b], best[c], best[d]};
          double lo = pts[0]->module, hi = lo;
          for (int i = 1; i < 4; i++) {
            if (pts[i]->module < lo) lo = pts[i]->module;
            if (pts[i]->module > hi) hi = pts[i]->module;
          }
          if (hi > 2.5 * lo) continue;
          quad q;
          q.area = make_quad(pts, &q);
          if (q.area <= 0) continue;
          int at = nq < MAX_QUADS ? nq++ : MAX_QUADS; /* insert in order of area */
          while (at > 0 && quads[at - 1].area < q.area) {
            if (at < MAX_QUADS) quads[at] = quads[at - 1];
            at--;
          }
          if (at < MAX_QUADS) quads[at] = q;
        }

  static uint8_t cells[IV_COLS * IV_ROWS], unsure[IV_COLS * IV_ROWS];
  int result = nq ? IV_ERR_DAMAGED : IV_ERR_NO_PAGE;
  for (int i = 0; i < nq; i++) {
    for (int start = 0; start < 4; start++) {
      for (int dir = -1; dir <= 1; dir += 2) {
        int len = read_page(&s, &quads[i], start, dir, cells, unsure, payload, info);
        if (len >= 0) return len;
      }
    }
  }
  return result;
}
