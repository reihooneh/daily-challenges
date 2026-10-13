/*
 * A libFuzzer target: feeds arbitrary bytes to every decoder entry point.
 * Build and run:  make fuzz   (needs clang)
 */
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "../core/inkvault.h"

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  static uint8_t payload[IV_CAPACITY], cells[IV_COLS * IV_ROWS];
  iv_info info;
  /* 1. As cells. */
  memset(cells, 0, sizeof cells);
  for (size_t i = 0; i < size && i < sizeof cells * 8; i++) cells[i % sizeof cells] ^= data[i] & 1;
  iv_decode_cells(cells, payload, &info);
  /* 2. As a Reed-Solomon codeword, with erasures taken from the data too. */
  if (size >= 4) {
    uint8_t code[255];
    int n = 20 + data[0] % 236, nsym = 2 + (data[1] % 31) * 2, ne = data[2] % (nsym + 1);
    int erased[64];
    for (int i = 0; i < ne; i++) erased[i] = (int)(data[(size_t)(3 + i) % size] % (unsigned)n);
    for (int i = 0; i < n; i++) code[i] = data[(size_t)i % size];
    iv_rs_decode_erasures(code, n, nsym, erased, ne);
  }
  /* 3. As a small greyscale photo, whose size comes from the first bytes. */
  if (size >= 2) {
    int w = IV_MIN_SIDE + data[0] % 64, h = IV_MIN_SIDE + data[1] % 64;
    uint8_t *gray = malloc((size_t)w * (size_t)h), *work = malloc(iv_work_size(w, h));
    for (int i = 0; i < w * h; i++) gray[i] = data[(size_t)i % size];
    iv_decode_image(gray, w, h, work, payload, &info);
    free(gray);
    free(work);
  }
  return 0;
}

#ifdef IV_FUZZ_DRIVER
/* Without libFuzzer: a fixed-seed random driver, so CI can run it under any compiler. */
#include <stdio.h>
int main(int argc, char **argv) {
  long runs = argc > 1 ? atol(argv[1]) : 3000;
  uint32_t s = 2463534242u;
  static uint8_t buf[12000];
  for (long r = 0; r < runs; r++) {
    size_t size = (size_t)(r % 97) * 120 + (size_t)(r % 13);
    for (size_t i = 0; i < size; i++) {
      s ^= s << 13; s ^= s >> 17; s ^= s << 5;
      buf[i] = (uint8_t)(r % 4 == 0 ? (s & 1) * 255 : s); /* some high-contrast inputs */
    }
    LLVMFuzzerTestOneInput(buf, size);
  }
  printf("fuzz driver: %ld inputs, no crashes\n", runs);
  return 0;
}
#endif
