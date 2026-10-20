/* Reading a progression file.
 *
 *   a4 440                    reference pitch in Hz (optional)
 *   weights glide 1 drift 1   (optional; these are the defaults)
 *   C4 E4 G4                  one chord per line, lowest note first; # starts a comment
 */
#include "drift.h"

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const int LETTER_PC[7] = {9, 11, 0, 2, 4, 5, 7}; /* A B C D E F G */

/* "C#4", "Bb3", "E4". Octave 0..8, default 4. Returns 0 and sets *midi on success. */
int parse_note(const char *s, int *midi) {
    size_t n = strlen(s);
    if (n < 1 || n > 4) return -1;
    char letter = (char)toupper((unsigned char)s[0]);
    if (letter < 'A' || letter > 'G') return -1;
    int pc = LETTER_PC[letter - 'A'];
    size_t i = 1;
    if (i < n && (s[i] == '#' || s[i] == 'b')) {
        pc += s[i] == '#' ? 1 : -1;
        i++;
    }
    int octave = 4;
    if (i < n) {
        if (i + 1 != n || !isdigit((unsigned char)s[i]) || s[i] == '9') return -1;
        octave = s[i] - '0';
    }
    int m = (octave + 1) * 12 + pc;
    if (m < 12 || m > 119) return -1;
    *midi = m;
    return 0;
}

void note_name(int midi, char *buf, size_t len) {
    snprintf(buf, len, "%s%d", PC_NAMES[midi % 12], midi / 12 - 1);
}

/* A plain decimal number in [lo, hi]: digits and at most one point, nothing else (no "nan", "1e9"). */
static int parse_number(const char *s, double lo, double hi, double *out) {
    size_t n = strlen(s);
    int dots = 0;
    if (n == 0 || n > 10) return -1;
    for (size_t i = 0; i < n; i++) {
        if (s[i] == '.') dots++;
        else if (!isdigit((unsigned char)s[i])) return -1;
    }
    if (dots > 1 || s[0] == '.' || s[n - 1] == '.') return -1;
    double v = strtod(s, NULL);
    if (!isfinite(v) || v < lo || v > hi) return -1;
    *out = v;
    return 0;
}

#define FAIL(...) do { snprintf(err, errlen, __VA_ARGS__); return -1; } while (0)

int parse_piece(const char *text, size_t len, Piece *out, char *err, size_t errlen) {
    memset(out, 0, sizeof *out);
    out->a4 = 440.0;
    out->glide = 1.0;
    out->drift = 1.0;
    if (len > MAX_BYTES) FAIL("the file is larger than 16 KB");
    size_t pos = 0;
    int lineno = 0;
    while (pos < len) {
        lineno++;
        size_t end = pos;
        while (end < len && text[end] != '\n') end++;
        size_t n = end - pos;
        if (n > 0 && text[pos + n - 1] == '\r') n--;
        if (n > MAX_LINE) FAIL("line %d is longer than %d characters", lineno, MAX_LINE);
        char line[MAX_LINE + 1];
        memcpy(line, text + pos, n);
        line[n] = '\0';
        pos = end + 1;
        for (size_t i = 0; i < n; i++) {
            unsigned char ch = (unsigned char)line[i];
            /* Plain printable ASCII only: no terminal escapes, no hidden Unicode direction marks. */
            if (ch == '\t') line[i] = ' ';
            else if (ch < 0x20 || ch > 0x7e) FAIL("line %d contains a character that isn't plain text", lineno);
        }
        char *hash = strchr(line, '#');
        if (hash) *hash = '\0';

        char *words[MAX_NOTES + 2];
        int count = 0;
        for (char *tok = strtok(line, " "); tok; tok = strtok(NULL, " ")) {
            if (count == MAX_NOTES + 2) FAIL("line %d: at most %d notes in a chord", lineno, MAX_NOTES);
            words[count++] = tok;
        }
        if (count == 0) continue;

        if (strcmp(words[0], "a4") == 0) {
            if (count != 2 || parse_number(words[1], 400.0, 480.0, &out->a4) != 0)
                FAIL("line %d: expected 'a4 440' (400 to 480 Hz)", lineno);
            continue;
        }
        if (strcmp(words[0], "weights") == 0) {
            if (count != 5 || strcmp(words[1], "glide") != 0 || strcmp(words[3], "drift") != 0 ||
                parse_number(words[2], 0.0, 1000.0, &out->glide) != 0 ||
                parse_number(words[4], 0.0, 1000.0, &out->drift) != 0)
                FAIL("line %d: expected 'weights glide 1 drift 0.1' (each 0 to 1000)", lineno);
            continue;
        }
        if (count > MAX_NOTES) FAIL("line %d: at most %d notes in a chord", lineno, MAX_NOTES);
        if (out->count == MAX_CHORDS) FAIL("line %d: more than %d chords", lineno, MAX_CHORDS);
        Chord *c = &out->chords[out->count];
        c->line = lineno;
        for (int i = 0; i < count; i++) {
            int m;
            if (parse_note(words[i], &m) != 0)
                FAIL("line %d: notes look like C4, F#3 or Bb2 (octaves 0 to 8)", lineno);
            for (int j = 0; j < c->count; j++)
                if (c->midi[j] == m) FAIL("line %d: the same note twice in one chord", lineno);
            c->midi[c->count++] = m;
        }
        if (identify(c) != 0)
            FAIL("line %d: not a chord Commadrift knows (major, minor, 7th chords, sus4, diminished, or a dyad)", lineno);
        out->count++;
    }
    if (out->count == 0) FAIL("the file has no chords");
    if (out->drift <= 0.0) out->drift = 1e-6; /* keeps the system solvable; see HOW-IT-WORKS */
    return 0;
}
