/* SHA-256 (FIPS 180-4), written from the standard. No dependencies. */
#ifndef EARPRINT_SHA256_H
#define EARPRINT_SHA256_H

#include <stddef.h>
#include <stdint.h>

#define SHA256_DIGEST_LEN 32

typedef struct {
    uint32_t state[8];
    uint64_t total_len; /* bytes hashed so far */
    uint8_t buffer[64]; /* partial block waiting for more data */
    size_t buffer_len;
} sha256_ctx;

void sha256_init(sha256_ctx *ctx);
void sha256_update(sha256_ctx *ctx, const uint8_t *data, size_t len);
void sha256_final(sha256_ctx *ctx, uint8_t out[SHA256_DIGEST_LEN]);

/* Writes 64 lowercase hex characters plus a terminating NUL (65 bytes). */
void sha256_to_hex(const uint8_t digest[SHA256_DIGEST_LEN], char hex[65]);

/* Compares two digests without leaking where they differ through timing.
 * Returns 1 if equal, 0 otherwise. */
int sha256_equal(const uint8_t a[SHA256_DIGEST_LEN], const uint8_t b[SHA256_DIGEST_LEN]);

#endif
