/* Small pieces of the C library, written out because the WebAssembly build has no libc. */
#include "inkvault.h"

void iv_memset(void *dst, int value, size_t n) {
  uint8_t *d = (uint8_t *)dst;
  while (n--) *d++ = (uint8_t)value;
}

void iv_memcpy(void *dst, const void *src, size_t n) {
  uint8_t *d = (uint8_t *)dst;
  const uint8_t *s = (const uint8_t *)src;
  while (n--) *d++ = *s++;
}

/* The compiler may call these for struct copies and array initialisers. */
#ifdef IV_FREESTANDING
void *memset(void *dst, int value, size_t n) {
  iv_memset(dst, value, n);
  return dst;
}
void *memcpy(void *dst, const void *src, size_t n) {
  iv_memcpy(dst, src, n);
  return dst;
}
#endif

/* CRC-32 (the one used by zip and PNG), bit by bit: small, and fast enough for 758 bytes. */
uint32_t iv_crc32(const uint8_t *data, size_t n) {
  uint32_t crc = 0xFFFFFFFFu;
  for (size_t i = 0; i < n; i++) {
    crc ^= data[i];
    for (int k = 0; k < 8; k++) crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
  }
  return ~crc;
}
