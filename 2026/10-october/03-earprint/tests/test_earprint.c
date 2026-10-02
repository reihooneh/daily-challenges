/* Unit tests. Built with AddressSanitizer and UndefinedBehaviorSanitizer, so
 * any out-of-bounds access or undefined behaviour fails the run. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "melody.h"
#include "sha256.h"
#include "wav.h"

static int checks = 0, failures = 0;

#define CHECK(cond, msg)                                              \
    do {                                                              \
        checks++;                                                     \
        if (!(cond)) {                                                \
            failures++;                                               \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, (msg));    \
        }                                                             \
    } while (0)

static void hash_hex(const void *data, size_t len, char hex[65]) {
    sha256_ctx ctx;
    uint8_t digest[SHA256_DIGEST_LEN];
    sha256_init(&ctx);
    sha256_update(&ctx, (const uint8_t *)data, len);
    sha256_final(&ctx, digest);
    sha256_to_hex(digest, hex);
}

/* Official test vectors from NIST (FIPS 180-4 examples). */
static void test_sha256_known_answers(void) {
    char hex[65];
    hash_hex("", 0, hex);
    CHECK(strcmp(hex, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") == 0, "empty input");
    hash_hex("abc", 3, hex);
    CHECK(strcmp(hex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") == 0, "abc");
    const char *two_blocks = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
    hash_hex(two_blocks, strlen(two_blocks), hex);
    CHECK(strcmp(hex, "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1") == 0, "two blocks");

    size_t n = 1000000;
    char *million = malloc(n);
    CHECK(million != NULL, "allocation");
    if (million != NULL) {
        memset(million, 'a', n);
        hash_hex(million, n, hex);
        CHECK(strcmp(hex, "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0") == 0, "million a");
        free(million);
    }
}

/* Feeding data in awkward piece sizes must give the same answer as one call.
 * Lengths around 55, 56, 63, 64 and 65 hit every padding edge case. */
static void test_sha256_chunking(void) {
    uint8_t data[200];
    for (size_t i = 0; i < sizeof data; i++) data[i] = (uint8_t)(i * 7 + 3);
    const size_t lengths[] = {0, 1, 55, 56, 57, 63, 64, 65, 119, 120, 128, 200};
    const size_t pieces[] = {1, 3, 7, 64, 65};
    for (size_t li = 0; li < sizeof lengths / sizeof lengths[0]; li++) {
        char expected[65];
        hash_hex(data, lengths[li], expected);
        for (size_t pi = 0; pi < sizeof pieces / sizeof pieces[0]; pi++) {
            sha256_ctx ctx;
            uint8_t digest[SHA256_DIGEST_LEN];
            char hex[65];
            sha256_init(&ctx);
            for (size_t off = 0; off < lengths[li]; off += pieces[pi]) {
                size_t take = lengths[li] - off < pieces[pi] ? lengths[li] - off : pieces[pi];
                sha256_update(&ctx, data + off, take);
            }
            sha256_final(&ctx, digest);
            sha256_to_hex(digest, hex);
            CHECK(strcmp(hex, expected) == 0, "chunked update matches one-shot");
        }
    }
}

static void test_sha256_equal(void) {
    uint8_t a[SHA256_DIGEST_LEN] = {0}, b[SHA256_DIGEST_LEN] = {0};
    CHECK(sha256_equal(a, b) == 1, "equal digests");
    b[31] = 1;
    CHECK(sha256_equal(a, b) == 0, "last byte differs");
    b[31] = 0;
    b[0] = 0x80;
    CHECK(sha256_equal(a, b) == 0, "first byte differs");
}

static void digest_of(const char *s, uint8_t digest[SHA256_DIGEST_LEN]) {
    sha256_ctx ctx;
    sha256_init(&ctx);
    sha256_update(&ctx, (const uint8_t *)s, strlen(s));
    sha256_final(&ctx, digest);
}

static void test_melody_mapping(void) {
    uint8_t d1[SHA256_DIGEST_LEN], d2[SHA256_DIGEST_LEN];
    melody_note m1[MELODY_NOTES], m1b[MELODY_NOTES], m2[MELODY_NOTES];
    digest_of("abc", d1);
    digest_of("abd", d2); /* one letter changed */
    melody_from_digest(d1, m1);
    melody_from_digest(d1, m1b);
    melody_from_digest(d2, m2);
    CHECK(memcmp(m1, m1b, sizeof m1) == 0, "same input gives the same melody");
    CHECK(memcmp(m1, m2, sizeof m1) != 0, "a one-letter change gives a different melody");
    for (int i = 0; i < MELODY_NOTES; i++) {
        CHECK(m1[i].pitch < MELODY_PITCHES, "pitch in range");
        CHECK(m1[i].is_long <= 1, "length flag is 0 or 1");
    }

    /* Extreme digests must still map into range. */
    uint8_t ones[SHA256_DIGEST_LEN];
    memset(ones, 0xff, sizeof ones);
    melody_from_digest(ones, m2);
    for (int i = 0; i < MELODY_NOTES; i++) CHECK(m2[i].pitch < MELODY_PITCHES, "0xff digest in range");
}

static void test_melody_text(void) {
    uint8_t zeros[SHA256_DIGEST_LEN] = {0};
    melody_note notes[MELODY_NOTES];
    char text[MELODY_TEXT_LEN];
    melody_from_digest(zeros, notes);
    CHECK(melody_to_text(notes, text, sizeof text) == 0, "text fits");
    CHECK(strcmp(text, "C4 C4 C4 C4 C4 C4 C4 C4 C4 C4 C4 C4 C4 C4 C4 C4") == 0, "all-zero digest is sixteen C4s");

    /* Worst case: every note long ("A5~"), which must still fit exactly. */
    for (int i = 0; i < MELODY_NOTES; i++) { notes[i].pitch = 9; notes[i].is_long = 1; }
    CHECK(melody_to_text(notes, text, sizeof text) == 0, "longest text fits the documented size");
    CHECK(strlen(text) == MELODY_TEXT_LEN - 2, "longest text length");

    char tiny[8];
    CHECK(melody_to_text(notes, tiny, sizeof tiny) == -1, "too-small buffer is refused");
    CHECK(tiny[0] == '\0', "refused buffer is left empty, not half-written");
    CHECK(melody_to_text(notes, tiny, 0) == -1, "zero-size buffer is refused");

    CHECK(strcmp(melody_pitch_name(0), "C4") == 0, "first pitch name");
    CHECK(strcmp(melody_pitch_name(200), "??") == 0, "out-of-range pitch name is safe");
}

static void test_melody_render(void) {
    uint8_t digest[SHA256_DIGEST_LEN];
    melody_note notes[MELODY_NOTES];
    digest_of("earprint", digest);
    melody_from_digest(digest, notes);

    size_t need = melody_sample_count(notes);
    CHECK(need > 0 && need <= MELODY_MAX_SAMPLES, "sample count within the documented maximum");

    int16_t *buf = malloc(need * sizeof *buf);
    CHECK(buf != NULL, "allocation");
    if (buf == NULL) return;
    CHECK(melody_render(notes, buf, need - 1) == 0, "buffer one sample too small is refused");
    CHECK(melody_render(notes, NULL, need) == 0, "NULL buffer is refused");
    CHECK(melody_render(notes, buf, need) == need, "exact-size buffer works");

    int loud = 0;
    for (size_t i = 0; i < need; i++) {
        if (buf[i] > 8000 || buf[i] < -8000) loud = 1;
    }
    CHECK(loud, "audio is not silent");
    CHECK(buf[0] == 0, "starts at zero (no click)");
    CHECK(abs(buf[need - 1]) < 200, "ends near zero (no click)");

    /* A corrupted note must not read outside the frequency table. */
    notes[3].pitch = 250;
    CHECK(melody_render(notes, buf, need) == need, "out-of-range pitch is rendered safely");
    free(buf);

    for (int i = 0; i < MELODY_NOTES; i++) notes[i].is_long = 1;
    CHECK(melody_sample_count(notes) == MELODY_MAX_SAMPLES, "all-long melody equals the maximum");
}

static uint32_t le32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static void test_wav(void) {
    const int16_t samples[] = {0, 1000, -1000, 32767, -32768};
    FILE *f = tmpfile();
    CHECK(f != NULL, "tmpfile");
    if (f == NULL) return;
    CHECK(wav_write(f, samples, 5, 22050) == 0, "write succeeds");
    rewind(f);
    uint8_t out[64];
    size_t got = fread(out, 1, sizeof out, f);
    fclose(f);
    CHECK(got == WAV_HEADER_LEN + 10, "file is header plus two bytes per sample");
    CHECK(memcmp(out, "RIFF", 4) == 0 && memcmp(out + 8, "WAVEfmt ", 8) == 0, "RIFF/WAVE markers");
    CHECK(le32(out + 4) == 36 + 10, "RIFF size");
    CHECK(out[20] == 1 && out[22] == 1, "PCM, mono");
    CHECK(le32(out + 24) == 22050 && le32(out + 28) == 44100, "sample rate and byte rate");
    CHECK(memcmp(out + 36, "data", 4) == 0 && le32(out + 40) == 10, "data chunk");
    CHECK(out[46] == 0xe8 && out[47] == 0x03, "1000 stored little-endian");
    CHECK(out[52] == 0x00 && out[53] == 0x80, "-32768 stored little-endian");

    f = tmpfile();
    if (f != NULL) {
        CHECK(wav_write(f, NULL, 5, 22050) == -1, "NULL samples refused");
        CHECK(wav_write(f, samples, 5, 0) == -1, "zero sample rate refused");
        CHECK(wav_write(f, samples, (size_t)0x90000000u, 22050) == -1, "oversized count refused before any write");
        CHECK(wav_write(NULL, samples, 5, 22050) == -1, "NULL file refused");
        fclose(f);
    }
}

int main(void) {
    test_sha256_known_answers();
    test_sha256_chunking();
    test_sha256_equal();
    test_melody_mapping();
    test_melody_text();
    test_melody_render();
    test_wav();
    printf("%d checks, %d failed\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
