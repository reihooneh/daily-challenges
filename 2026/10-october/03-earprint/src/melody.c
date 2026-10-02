#include "melody.h"

#include <math.h>
#include <stdio.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/* C major pentatonic over two octaves. A pentatonic scale has no clashing
 * notes, so any sequence sounds pleasant, like a wind chime. */
static const char *const NAMES[MELODY_PITCHES] = {"C4", "D4", "E4", "G4", "A4", "C5", "D5", "E5", "G5", "A5"};
static const double FREQS[MELODY_PITCHES] = {261.63, 293.66, 329.63, 392.00, 440.00,
                                             523.25, 587.33, 659.25, 783.99, 880.00};

void melody_from_digest(const uint8_t digest[SHA256_DIGEST_LEN], melody_note notes[MELODY_NOTES]) {
    for (int i = 0; i < MELODY_NOTES; i++) {
        notes[i].pitch = (uint8_t)(digest[i * 2] % MELODY_PITCHES);
        notes[i].is_long = (uint8_t)(digest[i * 2 + 1] & 1u);
    }
}

const char *melody_pitch_name(uint8_t pitch) { return pitch < MELODY_PITCHES ? NAMES[pitch] : "??"; }

int melody_to_text(const melody_note notes[MELODY_NOTES], char *out, size_t out_size) {
    size_t used = 0;
    if (out_size == 0) {
        return -1;
    }
    out[0] = '\0';
    for (int i = 0; i < MELODY_NOTES; i++) {
        /* snprintf never writes past the size we give it, and tells us how
         * much it wanted, so truncation is detected instead of overflowing. */
        int n = snprintf(out + used, out_size - used, "%s%s%s", i ? " " : "", melody_pitch_name(notes[i].pitch),
                         notes[i].is_long ? "~" : "");
        if (n < 0 || (size_t)n >= out_size - used) {
            out[0] = '\0';
            return -1;
        }
        used += (size_t)n;
    }
    return 0;
}

static size_t note_samples(const melody_note *note) {
    return (size_t)(note->is_long ? MELODY_LONG_MS : MELODY_SHORT_MS) * MELODY_SAMPLE_RATE / 1000;
}

size_t melody_sample_count(const melody_note notes[MELODY_NOTES]) {
    size_t total = 0;
    for (int i = 0; i < MELODY_NOTES; i++) {
        total += note_samples(&notes[i]);
    }
    return total;
}

size_t melody_render(const melody_note notes[MELODY_NOTES], int16_t *out, size_t capacity) {
    size_t total = melody_sample_count(notes);
    if (out == NULL || total > capacity) {
        return 0; /* refuse rather than write past the caller's buffer */
    }

    size_t pos = 0;
    for (int i = 0; i < MELODY_NOTES; i++) {
        size_t n = note_samples(&notes[i]);
        double freq = notes[i].pitch < MELODY_PITCHES ? FREQS[notes[i].pitch] : FREQS[0];
        size_t attack = MELODY_SAMPLE_RATE / 200;  /* 5 ms fade in */
        size_t release = MELODY_SAMPLE_RATE / 100; /* 10 ms fade out */
        for (size_t s = 0; s < n; s++) {
            double t = (double)s / MELODY_SAMPLE_RATE;
            /* A fundamental plus two quieter overtones gives a bell-like tone. */
            double wave = sin(2 * M_PI * freq * t) + 0.30 * sin(2 * M_PI * 2 * freq * t) +
                          0.10 * sin(2 * M_PI * 3 * freq * t);
            double env = exp(-3.0 * (double)s / (double)n); /* decay like a struck bell */
            if (s < attack) {
                env *= (double)s / (double)attack;
            }
            if (n - s <= release) {
                env *= (double)(n - s - 1) / (double)release; /* no click at the end */
            }
            double v = wave / 1.4 * env * 0.7 * 32767.0;
            if (v > 32767.0) v = 32767.0; /* clamp so the cast can never overflow */
            if (v < -32768.0) v = -32768.0;
            out[pos++] = (int16_t)v;
        }
    }
    return pos;
}
