/* Commadrift: tune a chord progression so every chord is pure (just intonation) while notes
 * held from one chord to the next move as little as possible, and show the comma drift. */
#ifndef DRIFT_H
#define DRIFT_H

#include <stddef.h>

#define MAX_BYTES 16384
#define MAX_LINE 120
#define MAX_CHORDS 256
#define MAX_NOTES 6

typedef struct {
    int midi[MAX_NOTES];  /* MIDI note numbers, e.g. 60 = C4 */
    int count;
    int root;             /* root pitch class 0..11 (C = 0) */
    const char *quality;  /* "maj", "min", "dom7", ... */
    double dev[MAX_NOTES];/* pure tuning minus equal temperament, in cents, per note */
    int line;
} Chord;

typedef struct {
    Chord chords[MAX_CHORDS];
    int count;
    double a4;      /* reference pitch in Hz */
    double glide;   /* weight for held notes moving */
    double drift;   /* weight for the whole piece wandering away from equal temperament */
} Piece;

/* parse.c: returns 0 on success, or fills err (line-numbered, never echoing the input). */
int parse_piece(const char *text, size_t len, Piece *out, char *err, size_t errlen);
int parse_note(const char *s, int *midi);
void note_name(int midi, char *buf, size_t len);

/* chords.c: identify a chord's root and quality and fill dev[]. 0 on success. */
int identify(Chord *c);
extern const char *const PC_NAMES[12];

/* solve.c */
double ratio_cents(double ratio);
/* Least-squares offsets (cents) of each chord's root from equal temperament. */
int solve_offsets(const Piece *p, double *offset);
/* Offsets when held notes may not move at all (the first chord stays put); returns the drift. */
double strict_offsets(const Piece *p, double *offset);
/* Largest glide of a held note between chord k and k+1 under the given offsets. */
double max_glide(const Piece *p, const double *offset, int *at_chord, int *at_midi);
int solve_tridiagonal(int n, const double *sub, double *diag, const double *sup, double *rhs);

#endif
