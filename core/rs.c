/*
 * Reed-Solomon error correction over GF(256), the same family of codes used by QR codes,
 * CDs and deep-space probes.
 *
 * A codeword is k data bytes followed by nsym check bytes. Byte j is the coefficient of
 * x^(n-1-j). The code's roots are alpha^0 .. alpha^(nsym-1), so a damaged codeword can be
 * repaired as long as no more than nsym / 2 of its bytes are wrong.
 */
#include "inkvault.h"

#define GF_PRIMITIVE 0x11d
#define MAX_NSYM 64

static uint8_t gf_exp[512];
static uint8_t gf_log[256];
static int gf_ready = 0;

static void gf_init(void) {
  if (gf_ready) return;
  int x = 1;
  for (int i = 0; i < 255; i++) {
    gf_exp[i] = (uint8_t)x;
    gf_log[x] = (uint8_t)i;
    x <<= 1;
    if (x & 0x100) x ^= GF_PRIMITIVE;
  }
  for (int i = 255; i < 512; i++) gf_exp[i] = gf_exp[i - 255];
  gf_ready = 1;
}

static uint8_t gf_mul(uint8_t a, uint8_t b) {
  if (a == 0 || b == 0) return 0;
  return gf_exp[gf_log[a] + gf_log[b]];
}

static uint8_t gf_div(uint8_t a, uint8_t b) { /* b != 0 */
  if (a == 0) return 0;
  return gf_exp[(gf_log[a] + 255 - gf_log[b]) % 255];
}

static uint8_t gf_pow_alpha(int e) { /* alpha^e for any integer e */
  e %= 255;
  if (e < 0) e += 255;
  return gf_exp[e];
}

/* Evaluates a polynomial stored lowest degree first. */
static uint8_t poly_eval_low(const uint8_t *p, int len, uint8_t x) {
  uint8_t y = 0;
  for (int i = len - 1; i >= 0; i--) y = (uint8_t)(gf_mul(y, x) ^ p[i]);
  return y;
}

/* Evaluates a codeword (highest degree first) at x. */
static uint8_t poly_eval_high(const uint8_t *p, int len, uint8_t x) {
  uint8_t y = 0;
  for (int i = 0; i < len; i++) y = (uint8_t)(gf_mul(y, x) ^ p[i]);
  return y;
}

void iv_rs_encode(const uint8_t *msg, int k, int nsym, uint8_t *out) {
  gf_init();
  uint8_t gen[MAX_NSYM + 1]; /* highest degree first, gen[0] = 1 */
  iv_memset(gen, 0, sizeof gen);
  gen[0] = 1;
  for (int i = 0; i < nsym; i++) { /* gen *= (x + alpha^i) */
    uint8_t root = gf_pow_alpha(i);
    for (int j = i + 1; j >= 1; j--) gen[j] = (uint8_t)(gen[j] ^ gf_mul(gen[j - 1], root));
  }
  uint8_t rem[MAX_NSYM];
  iv_memset(rem, 0, sizeof rem);
  for (int i = 0; i < k; i++) { /* long division, one byte at a time */
    uint8_t f = (uint8_t)(msg[i] ^ rem[0]);
    for (int j = 0; j < nsym - 1; j++) rem[j] = rem[j + 1];
    rem[nsym - 1] = 0;
    if (f) {
      for (int j = 0; j < nsym; j++) rem[j] = (uint8_t)(rem[j] ^ gf_mul(f, gen[j + 1]));
    }
  }
  if (out != msg) iv_memcpy(out, msg, (size_t)k);
  iv_memcpy(out + k, rem, (size_t)nsym);
}

int iv_rs_decode(uint8_t *c, int n, int nsym) { return iv_rs_decode_erasures(c, n, nsym, 0, 0); }

/* Errors and erasures: an erasure is a byte we already suspect (its position is known), so
 * it costs half as much to repair as an unknown error. Repairs succeed while
 * 2 * errors + erasures <= nsym. */
int iv_rs_decode_erasures(uint8_t *c, int n, int nsym, const int *erased, int ne) {
  gf_init();
  if (n > 255 || nsym > MAX_NSYM || nsym >= n || nsym < 2 || ne < 0 || ne > nsym) return -1;
  for (int i = 0; i < ne; i++) {
    if (erased[i] < 0 || erased[i] >= n) return -1;
  }

  /* 1. Syndromes: all zero means nothing is wrong. */
  uint8_t s[MAX_NSYM];
  int clean = 1;
  for (int i = 0; i < nsym; i++) {
    s[i] = poly_eval_high(c, n, gf_pow_alpha(i));
    if (s[i]) clean = 0;
  }
  if (clean) return 0;

  /* 2. Berlekamp-Massey: the locator L(x) = product of (1 - X_k x) over every bad byte.
   *    Erasures are known in advance, so the search starts from their locator. */
  uint8_t lam[MAX_NSYM + 1], prev[MAX_NSYM + 1], tmp[MAX_NSYM + 1];
  iv_memset(lam, 0, sizeof lam);
  lam[0] = 1;
  for (int i = 0; i < ne; i++) { /* lam *= (1 + X x), X = alpha^(power of the erased byte) */
    uint8_t x = gf_pow_alpha(n - 1 - erased[i]);
    for (int j = i + 1; j >= 1; j--) lam[j] = (uint8_t)(lam[j] ^ gf_mul(lam[j - 1], x));
  }
  iv_memcpy(prev, lam, sizeof lam);
  int L = ne, m = 1;
  uint8_t b = 1;
  for (int r = ne; r < nsym; r++) {
    uint8_t d = s[r];
    for (int i = 1; i <= L; i++) d = (uint8_t)(d ^ gf_mul(lam[i], s[r - i]));
    if (d == 0) {
      m++;
      continue;
    }
    uint8_t coef = gf_div(d, b);
    iv_memcpy(tmp, lam, sizeof lam);
    for (int i = 0; i + m <= nsym; i++) lam[i + m] = (uint8_t)(lam[i + m] ^ gf_mul(coef, prev[i]));
    if (2 * L <= r + ne) {
      L = r + 1 + ne - L;
      iv_memcpy(prev, tmp, sizeof tmp);
      b = d;
      m = 1;
    } else {
      m++;
    }
  }
  if (2 * (L - ne) + ne > nsym) return -1;

  /* 3. Chien search: error at power e where L(alpha^-e) = 0. */
  int pos[MAX_NSYM];
  int found = 0;
  for (int e = 0; e < n && found <= L; e++) {
    if (poly_eval_low(lam, L + 1, gf_pow_alpha(-e)) == 0) {
      if (found < MAX_NSYM) pos[found] = e;
      found++;
    }
  }
  if (found != L) return -1; /* errors outside the codeword: too much damage */

  /* 4. Forney: error values from the evaluator O(x) = S(x) L(x) mod x^nsym. */
  uint8_t omega[MAX_NSYM];
  iv_memset(omega, 0, sizeof omega);
  for (int i = 0; i < nsym; i++) {
    for (int j = 0; j <= L && i + j < nsym; j++) omega[i + j] = (uint8_t)(omega[i + j] ^ gf_mul(s[i], lam[j]));
  }
  for (int k = 0; k < found; k++) {
    uint8_t x = gf_pow_alpha(pos[k]);
    uint8_t xinv = gf_pow_alpha(-pos[k]);
    uint8_t num = poly_eval_low(omega, nsym, xinv);
    uint8_t den = 0; /* L'(x): the odd terms, as GF(256) has characteristic 2 */
    for (int i = 1; i <= L; i += 2) den = (uint8_t)(den ^ gf_mul(lam[i], gf_exp[(gf_log[xinv] * (i - 1)) % 255]));
    if (den == 0) return -1;
    uint8_t magnitude = gf_mul(x, gf_div(num, den));
    c[n - 1 - pos[k]] = (uint8_t)(c[n - 1 - pos[k]] ^ magnitude);
  }

  /* 5. Check the repair: every syndrome must now be zero. */
  for (int i = 0; i < nsym; i++) {
    if (poly_eval_high(c, n, gf_pow_alpha(i))) return -1;
  }
  return found;
}
