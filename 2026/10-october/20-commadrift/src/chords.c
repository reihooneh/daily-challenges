/* Recognising chords and their pure (just) tuning.
 *
 * Each template lists semitones above the root and the frequency ratio a pure version uses.
 * A major triad is 4:5:6, so its third is 5/4 (386.3 cents) instead of equal temperament's 400:
 * equal temperament's major third is 13.7 cents sharp, which is why it "beats".
 */
#include "drift.h"

#include <math.h>
#include <string.h>

const char *const PC_NAMES[12] = {"C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"};

typedef struct {
    const char *name;
    int size;
    int steps[4];
    double ratio[4];
} Template;

static const Template TEMPLATES[] = {
    {"maj", 3, {0, 4, 7, 0}, {1.0, 5.0 / 4, 3.0 / 2, 0}},
    {"min", 3, {0, 3, 7, 0}, {1.0, 6.0 / 5, 3.0 / 2, 0}},
    {"dom7", 4, {0, 4, 7, 10}, {1.0, 5.0 / 4, 3.0 / 2, 7.0 / 4}},
    {"maj7", 4, {0, 4, 7, 11}, {1.0, 5.0 / 4, 3.0 / 2, 15.0 / 8}},
    {"min7", 4, {0, 3, 7, 10}, {1.0, 6.0 / 5, 3.0 / 2, 9.0 / 5}},
    {"sus4", 3, {0, 5, 7, 0}, {1.0, 4.0 / 3, 3.0 / 2, 0}},
    {"dim", 3, {0, 3, 6, 0}, {1.0, 6.0 / 5, 7.0 / 5, 0}},
    {"fifth", 2, {0, 7, 0, 0}, {1.0, 3.0 / 2, 0, 0}},
    {"maj3", 2, {0, 4, 0, 0}, {1.0, 5.0 / 4, 0, 0}},
    {"min3", 2, {0, 3, 0, 0}, {1.0, 6.0 / 5, 0, 0}},
    {"note", 1, {0, 0, 0, 0}, {1.0, 0, 0, 0}},
};

double ratio_cents(double ratio) { return 1200.0 * log2(ratio); }

/* Try each note of the chord as the root, lowest first; the first template that fits wins. */
int identify(Chord *c) {
    int present[12] = {0};
    int pcs = 0;
    for (int i = 0; i < c->count; i++) {
        int pc = c->midi[i] % 12;
        if (!present[pc]) pcs++;
        present[pc] = 1;
    }
    for (int r = 0; r < c->count; r++) {
        int root = c->midi[r] % 12;
        for (size_t t = 0; t < sizeof TEMPLATES / sizeof TEMPLATES[0]; t++) {
            const Template *tp = &TEMPLATES[t];
            if (tp->size != pcs) continue;
            int ok = 1;
            for (int k = 0; k < tp->size && ok; k++) ok = present[(root + tp->steps[k]) % 12];
            if (!ok) continue;
            for (int i = 0; i < c->count; i++) {
                int step = (c->midi[i] - root + 120) % 12;
                for (int k = 0; k < tp->size; k++)
                    if (tp->steps[k] == step) c->dev[i] = ratio_cents(tp->ratio[k]) - 100.0 * step;
            }
            c->root = root;
            c->quality = tp->name;
            return 0;
        }
    }
    return -1;
}
