/* The tuning problem.
 *
 * Each chord is tuned pure, then the whole chord is shifted by an offset o[k] (cents) from equal
 * temperament. A note held from chord k into chord k+1 moves ("glides") by
 *     g = o[k+1] + dev[k+1](note) - o[k] - dev[k](note).
 * We choose the offsets to minimise
 *     glide * sum of g^2 over held notes  +  drift * sum of o[k]^2
 * The first part keeps held notes still; the second keeps the piece near concert pitch. Setting
 * the derivative to zero gives a tridiagonal linear system, solved in O(n) by the Thomas algorithm.
 */
#include "drift.h"

#include <math.h>
#include <stdlib.h>

/* Common tones of chords a and b: fills dev pairs, returns how many. */
static int common(const Chord *a, const Chord *b, double *da, double *db, int *midi) {
    int n = 0;
    for (int i = 0; i < a->count; i++)
        for (int j = 0; j < b->count; j++)
            if (a->midi[i] == b->midi[j]) {
                da[n] = a->dev[i];
                db[n] = b->dev[j];
                if (midi) midi[n] = a->midi[i];
                n++;
            }
    return n;
}

/* Thomas algorithm for a tridiagonal system. sub[i] couples row i to i-1, sup[i] to i+1.
 * diag and rhs are overwritten; the answer is left in rhs. */
int solve_tridiagonal(int n, const double *sub, double *diag, const double *sup, double *rhs) {
    for (int i = 1; i < n; i++) {
        if (fabs(diag[i - 1]) < 1e-12) return -1;
        double f = sub[i] / diag[i - 1];
        diag[i] -= f * sup[i - 1];
        rhs[i] -= f * rhs[i - 1];
    }
    if (fabs(diag[n - 1]) < 1e-12) return -1;
    rhs[n - 1] /= diag[n - 1];
    for (int i = n - 2; i >= 0; i--) rhs[i] = (rhs[i] - sup[i] * rhs[i + 1]) / diag[i];
    return 0;
}

int solve_offsets(const Piece *p, double *offset) {
    int n = p->count;
    double sub[MAX_CHORDS] = {0}, diag[MAX_CHORDS], sup[MAX_CHORDS] = {0};
    for (int k = 0; k < n; k++) {
        diag[k] = p->drift;
        offset[k] = 0.0;
    }
    for (int k = 0; k + 1 < n; k++) {
        double da[MAX_NOTES], db[MAX_NOTES];
        int m = common(&p->chords[k], &p->chords[k + 1], da, db, NULL);
        for (int i = 0; i < m; i++) {
            double c = db[i] - da[i]; /* glide = o[k+1] - o[k] + c */
            diag[k] += p->glide;
            diag[k + 1] += p->glide;
            sup[k] -= p->glide;
            sub[k + 1] -= p->glide;
            offset[k] += p->glide * c;
            offset[k + 1] -= p->glide * c;
        }
    }
    return solve_tridiagonal(n, sub, diag, sup, offset);
}

double strict_offsets(const Piece *p, double *offset) {
    offset[0] = 0.0;
    for (int k = 0; k + 1 < p->count; k++) {
        double da[MAX_NOTES], db[MAX_NOTES], sum = 0.0;
        int m = common(&p->chords[k], &p->chords[k + 1], da, db, NULL);
        for (int i = 0; i < m; i++) sum += db[i] - da[i];
        /* No held notes: nothing pins the next chord, so it keeps the same offset. */
        offset[k + 1] = offset[k] - (m ? sum / m : 0.0);
    }
    return offset[p->count - 1] - offset[0];
}

double max_glide(const Piece *p, const double *offset, int *at_chord, int *at_midi) {
    double worst = 0.0;
    *at_chord = -1;
    *at_midi = -1;
    for (int k = 0; k + 1 < p->count; k++) {
        double da[MAX_NOTES], db[MAX_NOTES];
        int midi[MAX_NOTES];
        int m = common(&p->chords[k], &p->chords[k + 1], da, db, midi);
        for (int i = 0; i < m; i++) {
            double g = fabs(offset[k + 1] + db[i] - offset[k] - da[i]);
            if (g > worst) {
                worst = g;
                *at_chord = k;
                *at_midi = midi[i];
            }
        }
    }
    return worst;
}
