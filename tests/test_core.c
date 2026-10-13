/*
 * Native tests for the Inkvault core, built with AddressSanitizer and UBSan.
 * They print pages, photograph them in software (rotation, perspective, blur, noise,
 * shadows, stains, tears, lens distortion) and check that the payload comes back,
 * or that the decoder says it can't, and never returns something wrong.
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../core/inkvault.h"

static int checks = 0, failures = 0;
#define CHECK(cond)                                                      \
  do {                                                                   \
    checks++;                                                            \
    if (!(cond)) {                                                       \
      failures++;                                                        \
      fprintf(stderr, "%s:%d: failed: %s\n", __FILE__, __LINE__, #cond); \
    }                                                                    \
  } while (0)

static uint32_t rng_state = 12345;
static uint32_t rnd(void) {
  rng_state = rng_state * 1664525u + 1013904223u;
  return rng_state >> 8;
}
static double rndf(void) { return (rnd() & 0xFFFFFF) / (double)0x1000000; }

/* ---------- a tiny image library for making test photos ---------- */

typedef struct {
  int w, h;
  float *px; /* 0 = black, 255 = white */
} image;

static image img_new(int w, int h, float fill) {
  image im = {w, h, malloc(sizeof(float) * (size_t)w * (size_t)h)};
  for (int i = 0; i < w * h; i++) im.px[i] = fill;
  return im;
}

static float img_get(const image *im, double x, double y, float outside) {
  if (x < 0 || y < 0 || x > im->w - 1 || y > im->h - 1) return outside;
  int x0 = (int)x, y0 = (int)y;
  int x1 = x0 + 1 < im->w ? x0 + 1 : x0, y1 = y0 + 1 < im->h ? y0 + 1 : y0;
  double fx = x - x0, fy = y - y0;
  double top = im->px[y0 * im->w + x0] * (1 - fx) + im->px[y0 * im->w + x1] * fx;
  double bottom = im->px[y1 * im->w + x0] * (1 - fx) + im->px[y1 * im->w + x1] * fx;
  return (float)(top * (1 - fy) + bottom * fy);
}

/* The printed page: `scale` pixels per cell, with a 4-cell white margin. */
static image render(const uint8_t *cells, int scale) {
  int margin = 4 * scale;
  image im = img_new(IV_COLS * scale + 2 * margin, IV_ROWS * scale + 2 * margin, 245);
  for (int r = 0; r < IV_ROWS; r++)
    for (int c = 0; c < IV_COLS; c++)
      if (cells[r * IV_COLS + c])
        for (int y = 0; y < scale; y++)
          for (int x = 0; x < scale; x++) im.px[(margin + r * scale + y) * im.w + margin + c * scale + x] = 25;
  return im;
}

/* Solves the homography mapping 4 points (u,v) -> (x,y), independently of the core. */
static void homography(const double u[4], const double v[4], const double x[4], const double y[4], double h[9]) {
  double a[8][9];
  for (int i = 0; i < 4; i++) {
    double r0[9] = {u[i], v[i], 1, 0, 0, 0, -u[i] * x[i], -v[i] * x[i], x[i]};
    double r1[9] = {0, 0, 0, u[i], v[i], 1, -u[i] * y[i], -v[i] * y[i], y[i]};
    memcpy(a[2 * i], r0, sizeof r0);
    memcpy(a[2 * i + 1], r1, sizeof r1);
  }
  for (int c = 0; c < 8; c++) {
    int p = c;
    for (int r = c + 1; r < 8; r++) if (fabs(a[r][c]) > fabs(a[p][c])) p = r;
    for (int j = 0; j < 9; j++) { double t = a[c][j]; a[c][j] = a[p][j]; a[p][j] = t; }
    for (int r = 0; r < 8; r++) {
      if (r == c) continue;
      double f = a[r][c] / a[c][c];
      for (int j = c; j < 9; j++) a[r][j] -= f * a[c][j];
    }
  }
  for (int i = 0; i < 8; i++) h[i] = a[i][8] / a[i][i];
  h[8] = 1;
}

/* Photographs `src` so its corners (TL, TR, BR, BL) land at the given points of a w x h photo
 * lying on a mid-grey table. */
static image photograph(const image *src, int w, int h, const double cx[4], const double cy[4]) {
  double u[4] = {0, src->w - 1.0, src->w - 1.0, 0}, v[4] = {0, 0, src->h - 1.0, src->h - 1.0}, hm[9];
  homography(cx, cy, u, v, hm); /* photo -> page */
  image out = img_new(w, h, 0);
  for (int y = 0; y < h; y++)
    for (int x = 0; x < w; x++) {
      double d = hm[6] * x + hm[7] * y + hm[8];
      double sx = (hm[0] * x + hm[1] * y + hm[2]) / d, sy = (hm[3] * x + hm[4] * y + hm[5]) / d;
      out.px[y * w + x] = img_get(src, sx, sy, 110);
    }
  return out;
}

static void blur(image *im, int r) {
  image tmp = img_new(im->w, im->h, 0);
  for (int pass = 0; pass < 2; pass++) {
    image *from = pass ? &tmp : im, *to = pass ? im : &tmp;
    for (int y = 0; y < im->h; y++)
      for (int x = 0; x < im->w; x++) {
        double sum = 0;
        int n = 0;
        for (int k = -r; k <= r; k++) {
          int xx = pass ? x : x + k, yy = pass ? y + k : y;
          if (xx < 0 || yy < 0 || xx >= im->w || yy >= im->h) continue;
          sum += from->px[yy * im->w + xx];
          n++;
        }
        to->px[y * im->w + x] = (float)(sum / n);
      }
  }
  free(tmp.px);
}

static void noise(image *im, double amount) {
  for (int i = 0; i < im->w * im->h; i++) im->px[i] += (float)((rndf() - 0.5) * 2 * amount);
}

static void lighting(image *im, double darkest) { /* a shadow falling across the page */
  for (int y = 0; y < im->h; y++)
    for (int x = 0; x < im->w; x++) im->px[y * im->w + x] *= (float)(darkest + (1 - darkest) * x / im->w);
}

static void stain(image *im, double cx, double cy, double r) { /* a coffee stain: darker, with a ring */
  for (int y = 0; y < im->h; y++)
    for (int x = 0; x < im->w; x++) {
      double d = sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
      if (d < r) im->px[y * im->w + x] = im->px[y * im->w + x] * 0.55f + (d > 0.9 * r ? -20.0f : 15.0f);
    }
}

static void tear(image *im, int x0, int y0, int x1, int y1, float value) {
  for (int y = y0; y < y1 && y < im->h; y++)
    for (int x = x0; x < x1 && x < im->w; x++) im->px[y * im->w + x] = value;
}

static image barrel(const image *im, double k) { /* lens distortion */
  image out = img_new(im->w, im->h, 0);
  double cx = im->w / 2.0, cy = im->h / 2.0, norm = cx * cx + cy * cy;
  for (int y = 0; y < im->h; y++)
    for (int x = 0; x < im->w; x++) {
      double dx = x - cx, dy = y - cy, f = 1 + k * (dx * dx + dy * dy) / norm;
      out.px[y * im->w + x] = img_get(im, cx + dx * f, cy + dy * f, 110);
    }
  return out;
}

/* Decodes a photo through the same entry point the browser uses. */
static int decode_photo(const image *im, uint8_t *payload, iv_info *info) {
  uint8_t *gray = malloc((size_t)im->w * (size_t)im->h);
  for (int i = 0; i < im->w * im->h; i++) {
    float v = im->px[i];
    gray[i] = (uint8_t)(v < 0 ? 0 : v > 255 ? 255 : v);
  }
  size_t need = iv_work_size(im->w, im->h);
  uint8_t *work = malloc(need ? need : 1);
  int len = iv_decode_image(gray, im->w, im->h, work, payload, info);
  free(work);
  free(gray);
  return len;
}

/* ---------- the tests ---------- */

static uint8_t page[IV_COLS * IV_ROWS];
static uint8_t message[IV_CAPACITY], got[IV_CAPACITY + 64];

static int make_message(int len) {
  for (int i = 0; i < len; i++) message[i] = (uint8_t)rnd();
  return len;
}

static void test_crc(void) {
  CHECK(iv_crc32((const uint8_t *)"123456789", 9) == 0xCBF43926u);
  CHECK(iv_crc32(NULL, 0) == 0);
}

static void test_reed_solomon(void) {
  uint8_t msg[200], code[255], damaged[255];
  int wrongButAccepted = 0, refused = 0;
  for (int trial = 0; trial < 3000; trial++) {
    int nsym = 2 + (int)(rnd() % 31) * 2, k = 1 + (int)(rnd() % (unsigned)(255 - nsym - 1));
    if (k > 200) k = 200;
    for (int i = 0; i < k; i++) msg[i] = (uint8_t)rnd();
    iv_rs_encode(msg, k, nsym, code);
    int n = k + nsym;
    CHECK(iv_rs_decode(code, n, nsym) == 0);
    int errors = (int)(rnd() % (unsigned)(nsym / 2 + 1));
    int beyond = trial % 3 == 0;
    if (beyond) errors = nsym / 2 + 1 + (int)(rnd() % (unsigned)(nsym / 2 + 1));
    if (errors > n) errors = n;
    memcpy(damaged, code, (size_t)n);
    int hit[255] = {0};
    for (int e = 0; e < errors;) {
      int p = (int)(rnd() % (unsigned)n);
      if (hit[p]) continue;
      hit[p] = 1;
      damaged[p] ^= (uint8_t)(1 + rnd() % 255);
      e++;
    }
    int fixed = iv_rs_decode(damaged, n, nsym);
    if (!beyond) {
      CHECK(fixed == errors);
      CHECK(memcmp(damaged, code, (size_t)n) == 0);
    } else if (fixed < 0) {
      refused++;
    } else if (memcmp(damaged, code, (size_t)n) != 0) {
      wrongButAccepted++; /* possible for any code past its limit; the page checksum catches it */
    }
  }
  CHECK(refused > 900);
  CHECK(wrongButAccepted < 50);
  printf("    beyond the limit: %d refused, %d mis-repaired (caught later by the CRC)\n", refused, wrongButAccepted);
  CHECK(iv_rs_decode(code, 300, 10) == -1); /* bad parameters are refused */
  CHECK(iv_rs_decode(code, 20, 30) == -1);
}

static void test_erasures(void) {
  uint8_t msg[200], code[255], damaged[255];
  for (int trial = 0; trial < 3000; trial++) {
    int nsym = 4 + (int)(rnd() % 30) * 2, k = 20 + (int)(rnd() % 150);
    int n = k + nsym;
    for (int i = 0; i < k; i++) msg[i] = (uint8_t)rnd();
    iv_rs_encode(msg, k, nsym, code);
    memcpy(damaged, code, (size_t)n);
    int ne = (int)(rnd() % (unsigned)(nsym + 1));       /* known-bad bytes */
    int errors = (int)(rnd() % (unsigned)((nsym - ne) / 2 + 1)); /* unknown bad bytes */
    int erased[64], hit[255] = {0};
    for (int i = 0; i < ne;) {
      int p = (int)(rnd() % (unsigned)n);
      if (hit[p]) continue;
      hit[p] = 1;
      erased[i++] = p;
      if (rnd() & 1) damaged[p] ^= (uint8_t)(1 + rnd() % 255); /* an erasure may happen to be right */
    }
    for (int e = 0; e < errors;) {
      int p = (int)(rnd() % (unsigned)n);
      if (hit[p]) continue;
      hit[p] = 1;
      damaged[p] ^= (uint8_t)(1 + rnd() % 255);
      e++;
    }
    int fixed = iv_rs_decode_erasures(damaged, n, nsym, erased, ne);
    CHECK(fixed >= 0);
    CHECK(memcmp(damaged, code, (size_t)n) == 0);
  }
  int bad[2] = {0, 300};
  CHECK(iv_rs_decode_erasures(damaged, 100, 10, bad, 2) == -1); /* position out of range */
  CHECK(iv_rs_decode_erasures(damaged, 100, 10, bad, 11) == -1); /* more erasures than check bytes */
}

static void test_cells_round_trip(void) {
  iv_info info;
  for (int trial = 0; trial < 60; trial++) {
    int len = trial == 0 ? 0 : trial == 1 ? IV_CAPACITY : (int)(rnd() % IV_CAPACITY);
    make_message(len);
    CHECK(iv_encode(message, len, trial & 3, page) == 0);
    CHECK(iv_decode_cells(page, got, &info) == len);
    CHECK(memcmp(got, message, (size_t)len) == 0);
    CHECK(info.repaired == 0 && info.flags == (trial & 3) && info.limit == IV_NSYM / 2);
  }
  CHECK(iv_encode(message, IV_CAPACITY + 1, 0, page) == IV_ERR_TOO_BIG);
  CHECK(iv_encode(message, -1, 0, page) == IV_ERR_TOO_BIG);
  /* An even mix of dark and light, even for an empty payload. */
  iv_encode(message, 0, 0, page);
  int dark = 0;
  for (int i = 0; i < IV_COLS * IV_ROWS; i++) dark += page[i];
  CHECK(dark > IV_COLS * IV_ROWS * 4 / 10 && dark < IV_COLS * IV_ROWS * 6 / 10);
}

static void test_cell_damage(void) {
  iv_info info;
  int len = make_message(500);
  iv_encode(message, len, 0, page);
  /* A solid block covering 8% of the page (a sticker, or ink spilt on it). */
  uint8_t damaged[IV_COLS * IV_ROWS];
  memcpy(damaged, page, sizeof page);
  for (int y = 30; y < 30 + 28; y++)
    for (int x = 20; x < 20 + 26; x++) damaged[y * IV_COLS + x] = 1;
  CHECK(iv_decode_cells(damaged, got, &info) == len);
  CHECK(memcmp(got, message, (size_t)len) == 0);
  CHECK(info.repaired > 50);
  printf("    8%% of the page blacked out: %d bytes repaired, worst block %d of %d\n", info.repaired, info.worst,
         info.limit);
  /* Far too much damage is refused, never misread. */
  int wrong = 0, refused = 0;
  for (int trial = 0; trial < 300; trial++) {
    memcpy(damaged, page, sizeof page);
    int area = 30 + (int)(rnd() % 60);
    for (int i = 0; i < IV_COLS * IV_ROWS * area / 100; i++) damaged[rnd() % (IV_COLS * IV_ROWS)] ^= 1;
    int r = iv_decode_cells(damaged, got, &info);
    if (r < 0) refused++;
    else if (r != len || memcmp(got, message, (size_t)len) != 0) wrong++;
  }
  CHECK(wrong == 0);
  CHECK(refused == 300);
  /* Random cells are not a page. */
  for (int trial = 0; trial < 300; trial++) {
    for (int i = 0; i < IV_COLS * IV_ROWS; i++) damaged[i] = (uint8_t)(rnd() & 1);
    CHECK(iv_decode_cells(damaged, got, &info) < 0);
  }
}

typedef struct {
  const char *name;
  int scale;
  double corners[8]; /* where TL, TR, BR, BL land, as fractions of the photo */
  int photo_w, photo_h;
  int blur, light, stain, tear, barrel_on;
  double noise;
} scene;

static int run_scene(const scene *sc, int len, iv_info *info) {
  iv_encode(message, len, 0, page);
  image printed = render(page, sc->scale);
  double cx[4], cy[4];
  for (int i = 0; i < 4; i++) {
    cx[i] = sc->corners[2 * i] * sc->photo_w;
    cy[i] = sc->corners[2 * i + 1] * sc->photo_h;
  }
  image photo = photograph(&printed, sc->photo_w, sc->photo_h, cx, cy);
  free(printed.px);
  if (sc->stain) stain(&photo, sc->photo_w * 0.55, sc->photo_h * 0.45, sc->photo_w * 0.14);
  if (sc->tear == 1) tear(&photo, (int)(cx[1] - sc->photo_w * 0.18), (int)(sc->photo_h * 0.3), (int)(cx[1] + 30),
                          (int)(sc->photo_h * 0.42), 110);
  if (sc->tear == 2) { /* an ink blot in the middle of the page */
    int bx = sc->photo_w * 2 / 5, by = sc->photo_h * 2 / 5;
    tear(&photo, bx, by, bx + sc->photo_w / 5, by + sc->photo_h / 8, 20);
  }
  if (sc->light) lighting(&photo, 0.45);
  if (sc->blur) blur(&photo, sc->blur);
  if (sc->noise > 0) noise(&photo, sc->noise);
  if (sc->barrel_on) {
    image bent = barrel(&photo, 0.02);
    free(photo.px);
    photo = bent;
  }
  int r = decode_photo(&photo, got, info);
  free(photo.px);
  return r;
}

static void test_photos(void) {
  const scene scenes[] = {
      {"straight on", 6, {0.1, 0.05, 0.9, 0.05, 0.9, 0.95, 0.1, 0.95}, 700, 900, 0, 0, 0, 0, 0, 0},
      {"upside down", 6, {0.9, 0.95, 0.1, 0.95, 0.1, 0.05, 0.9, 0.05}, 700, 900, 0, 0, 0, 0, 0, 0},
      {"sideways", 6, {0.95, 0.12, 0.95, 0.88, 0.05, 0.88, 0.05, 0.12}, 1000, 760, 0, 0, 0, 0, 0, 0},
      {"mirrored (selfie camera)", 6, {0.9, 0.05, 0.1, 0.05, 0.1, 0.95, 0.9, 0.95}, 700, 900, 0, 0, 0, 0, 0, 0},
      {"tilted, in perspective", 6, {0.18, 0.08, 0.86, 0.14, 0.94, 0.93, 0.05, 0.86}, 800, 1000, 0, 0, 0, 0, 0, 0},
      {"blurry and noisy", 6, {0.1, 0.06, 0.9, 0.04, 0.92, 0.95, 0.08, 0.94}, 700, 900, 2, 0, 0, 0, 0, 25},
      {"shadow across it", 6, {0.1, 0.06, 0.9, 0.04, 0.92, 0.95, 0.08, 0.94}, 700, 900, 1, 1, 0, 0, 0, 10},
      {"coffee stain", 6, {0.1, 0.06, 0.9, 0.04, 0.92, 0.95, 0.08, 0.94}, 700, 900, 1, 0, 1, 0, 0, 8},
      {"torn edge", 6, {0.1, 0.06, 0.9, 0.04, 0.92, 0.95, 0.08, 0.94}, 700, 900, 0, 0, 0, 1, 0, 5},
      {"ink blot", 6, {0.1, 0.06, 0.9, 0.04, 0.92, 0.95, 0.08, 0.94}, 700, 900, 0, 0, 0, 2, 0, 5},
      {"phone lens distortion", 6, {0.12, 0.07, 0.88, 0.06, 0.9, 0.94, 0.1, 0.93}, 700, 900, 1, 0, 0, 0, 1, 8},
      {"everything at once", 6, {0.16, 0.08, 0.87, 0.12, 0.92, 0.94, 0.07, 0.88}, 800, 1000, 1, 1, 1, 0, 0, 12},
      {"low resolution (4 px a cell)", 4, {0.06, 0.04, 0.94, 0.04, 0.94, 0.96, 0.06, 0.96}, 400, 540, 0, 0, 0, 0, 0, 6},
  };
  for (size_t i = 0; i < sizeof scenes / sizeof scenes[0]; i++) {
    iv_info info;
    int len = make_message(300 + (int)(rnd() % 400));
    int r = run_scene(&scenes[i], len, &info);
    CHECK(r == len);
    CHECK(r == len && memcmp(got, message, (size_t)len) == 0);
    printf("    %-30s %s  repaired %3d bytes, worst block %2d of %d\n", scenes[i].name, r == len ? "read" : "FAIL",
           info.repaired, info.worst, info.limit);
  }
}

static void test_bad_photos(void) {
  iv_info info;
  uint8_t work[8] = {0};
  CHECK(iv_decode_image(work, 10, 10, work, got, &info) == IV_ERR_IMAGE_SIZE);
  CHECK(iv_decode_image(work, IV_MAX_SIDE + 1, 100, work, got, &info) == IV_ERR_IMAGE_SIZE);
  CHECK(iv_decode_image(work, -5, 100, work, got, &info) == IV_ERR_IMAGE_SIZE);
  CHECK(iv_work_size(100000, 100000) == 0);

  image blank = img_new(300, 400, 240);
  CHECK(decode_photo(&blank, got, &info) == IV_ERR_NO_PAGE);
  /* Random photos (noise, stripes, checkerboards) never decode, and never crash. */
  for (int trial = 0; trial < 60; trial++) {
    int kind = trial % 3;
    for (int y = 0; y < blank.h; y++)
      for (int x = 0; x < blank.w; x++)
        blank.px[y * blank.w + x] = kind == 0 ? (float)(rnd() & 255)
                                    : kind == 1 ? (float)(((x / (1 + trial % 9)) & 1) * 255)
                                                : (float)((((x / 7) ^ (y / 7)) & 1) * 255);
    CHECK(decode_photo(&blank, got, &info) < 0);
  }
  free(blank.px);

  /* Half the page torn away: refused, not misread. */
  int len = make_message(400);
  iv_encode(message, len, 0, page);
  image printed = render(page, 5);
  tear(&printed, printed.w / 4, printed.h / 4, printed.w * 3 / 4, printed.h * 3 / 4, 245);
  CHECK(decode_photo(&printed, got, &info) == IV_ERR_DAMAGED);
  free(printed.px);
}

int main(void) {
  struct {
    const char *name;
    void (*fn)(void);
  } tests[] = {{"crc32", test_crc},
               {"reed-solomon", test_reed_solomon},
               {"reed-solomon with erasures", test_erasures},
               {"cells round trip", test_cells_round_trip},
               {"cell damage", test_cell_damage},
               {"photos", test_photos},
               {"bad photos", test_bad_photos}};
  for (size_t i = 0; i < sizeof tests / sizeof tests[0]; i++) {
    int before = failures;
    printf("%s\n", tests[i].name);
    tests[i].fn();
    printf("  %s\n", failures == before ? "ok" : "FAILED");
  }
  printf("%d checks, %d failed\n", checks, failures);
  return failures ? 1 : 0;
}
