/* Turns a SHA-256 digest into a 16-note melody and renders it as audio. */
#ifndef EARPRINT_MELODY_H
#define EARPRINT_MELODY_H

#include <stddef.h>
#include <stdint.h>

#include "sha256.h"

#define MELODY_NOTES 16
#define MELODY_PITCHES 10
#define MELODY_SAMPLE_RATE 22050
#define MELODY_SHORT_MS 180
#define MELODY_LONG_MS 360
/* Worst case: every note long. Lets callers use a fixed-size buffer. */
#define MELODY_MAX_SAMPLES ((size_t)MELODY_NOTES * MELODY_LONG_MS * MELODY_SAMPLE_RATE / 1000)
/* "C4~ " is at most 4 characters per note, plus the terminating NUL. */
#define MELODY_TEXT_LEN (MELODY_NOTES * 4 + 1)

typedef struct {
    uint8_t pitch;   /* 0..MELODY_PITCHES-1, an index into the scale */
    uint8_t is_long; /* 0 = short note, 1 = long note */
} melody_note;

/* Derives the melody: each note uses two bytes of the digest. */
void melody_from_digest(const uint8_t digest[SHA256_DIGEST_LEN], melody_note notes[MELODY_NOTES]);

/* Note name such as "C4" or "A5". Returns "??" for an out-of-range pitch. */
const char *melody_pitch_name(uint8_t pitch);

/* Writes e.g. "C4 E5~ G4 ..." ("~" marks a long note). Returns 0 on success,
 * -1 if the buffer is too small. */
int melody_to_text(const melody_note notes[MELODY_NOTES], char *out, size_t out_size);

/* Number of audio samples the melody needs. */
size_t melody_sample_count(const melody_note notes[MELODY_NOTES]);

/* Renders 16-bit mono audio into `out`. Returns the number of samples written,
 * or 0 if `capacity` is too small (nothing is written in that case). */
size_t melody_render(const melody_note notes[MELODY_NOTES], int16_t *out, size_t capacity);

#endif
