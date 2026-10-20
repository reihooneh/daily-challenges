/* Unit tests. Built with AddressSanitizer and UBSan by `make test`. */
#include "drift.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static int passed, failed;
#define CHECK(cond, what)                                   \
    do {                                                    \
        if (cond) passed++;                                 \
        else {                                              \
            failed++;                                       \
            printf("FAIL  %s (line %d)\n", what, __LINE__); \
        }                                                   \
    } while (0)
#define NEAR(a, b, tol, what) CHECK(fabs((a) - (b)) <= (tol), what)

static Piece piece;
static char err[160];

static int load(const char *text) { return parse_piece(text, strlen(text), &piece, err, sizeof err); }

static void rejects(const char *text, const char *want) {
    int rc = load(text);
    char what[96];
    snprintf(what, sizeof what, "reject: %.40s", text);
    CHECK(rc != 0 && strstr(err, want) != NULL, what);
}

int main(void) {
    int m = 0;
    /* ---------- notes ---------- */
    CHECK(parse_note("C4", &m) == 0 && m == 60, "C4 is 60");
    CHECK(parse_note("A4", &m) == 0 && m == 69, "A4 is 69");
    CHECK(parse_note("Bb3", &m) == 0 && m == 58, "Bb3");
    CHECK(parse_note("F#2", &m) == 0 && m == 42, "F#2");
    CHECK(parse_note("e", &m) == 0 && m == 64, "default octave 4");
    CHECK(parse_note("Cb4", &m) == 0 && m == 59, "Cb4 is B3");
    CHECK(parse_note("H4", &m) != 0 && parse_note("C9", &m) != 0 && parse_note("C##4", &m) != 0 && parse_note("", &m) != 0,
          "bad notes refused");
    char nn[8];
    note_name(61, nn, sizeof nn);
    CHECK(strcmp(nn, "C#4") == 0, "note names");

    /* ---------- chords and pure tuning ---------- */
    NEAR(ratio_cents(5.0 / 4), 386.3137, 1e-3, "pure major third is 386.3 cents");
    NEAR(ratio_cents(81.0 / 80), 21.5063, 1e-3, "syntonic comma is 21.5 cents");
    CHECK(load("C4 E4 G4\n") == 0 && strcmp(piece.chords[0].quality, "maj") == 0 && piece.chords[0].root == 0, "C major");
    NEAR(piece.chords[0].dev[1], -13.686, 1e-3, "pure third is 13.7 cents below equal temperament");
    NEAR(piece.chords[0].dev[2], 1.955, 1e-3, "pure fifth is 2.0 cents above");
    CHECK(load("E3 G3 C4\n") == 0 && piece.chords[0].root == 0, "first inversion still has root C");
    CHECK(load("A3 C4 E4\n") == 0 && strcmp(piece.chords[0].quality, "min") == 0 && piece.chords[0].root == 9, "A minor");
    CHECK(load("G3 B3 D4 F4\n") == 0 && strcmp(piece.chords[0].quality, "dom7") == 0, "G7");
    NEAR(piece.chords[0].dev[3], -31.174, 1e-3, "harmonic seventh is 31.2 cents flat");
    CHECK(load("C3 C4 E4 G4\n") == 0 && fabs(piece.chords[0].dev[0]) < 1e-9 && fabs(piece.chords[0].dev[1]) < 1e-9,
          "doubled root in another octave");
    CHECK(load("C4 D4 E4\n") != 0, "a cluster isn't a known chord");

    /* ---------- the comma pump ---------- */
    const char *pump = "C4 E4 G4\nA3 C4 E4\nA3 D4 F4\nG3 B3 D4\nG3 C4 E4\n";
    double off[MAX_CHORDS];
    CHECK(load(pump) == 0 && piece.count == 5, "pump parses");
    double drift = strict_offsets(&piece, off);
    NEAR(drift, -21.5063, 1e-3, "strict tuning drifts down a syntonic comma");
    int at_c, at_m;
    NEAR(max_glide(&piece, off, &at_c, &at_m), 0.0, 1e-9, "strict plan: held notes don't move");
    CHECK(solve_offsets(&piece, off) == 0, "balanced plan solves");
    double balanced_drift = off[4] - off[0];
    CHECK(fabs(balanced_drift) < 21.0 && max_glide(&piece, off, &at_c, &at_m) < 5.0, "balanced plan trades drift for small glides");

    /* The least-squares answer really is a minimum: nudging any offset makes the cost worse. */
    {
        double best = 0.0, base[MAX_CHORDS];
        memcpy(base, off, sizeof base);
        for (int pass = 0; pass < 2 * piece.count + 1; pass++) {
            double o[MAX_CHORDS];
            memcpy(o, base, sizeof o);
            if (pass) o[(pass - 1) / 2] += (pass % 2) ? 0.5 : -0.5;
            double cost = 0.0;
            for (int k = 0; k < piece.count; k++) cost += piece.drift * o[k] * o[k];
            for (int k = 0; k + 1 < piece.count; k++)
                for (int i = 0; i < piece.chords[k].count; i++)
                    for (int j = 0; j < piece.chords[k + 1].count; j++)
                        if (piece.chords[k].midi[i] == piece.chords[k + 1].midi[j]) {
                            double g = o[k + 1] + piece.chords[k + 1].dev[j] - o[k] - piece.chords[k].dev[i];
                            cost += piece.glide * g * g;
                        }
            if (!pass) best = cost;
            else CHECK(cost > best, "nudged plan costs more");
        }
    }
    /* Without the drift term pulling back, glide-only tuning reproduces the strict drift. */
    CHECK(load("weights glide 1 drift 0\nC4 E4 G4\nA3 C4 E4\nA3 D4 F4\nG3 B3 D4\nG3 C4 E4\n") == 0 &&
              solve_offsets(&piece, off) == 0,
          "drift weight 0 still solvable");
    NEAR(off[4] - off[0], -21.5063, 0.01, "glide-only plan drifts the full comma");

    /* A progression with nothing held never drifts in the strict plan. */
    CHECK(load("C4 E4 G4\nD4 F#4 A4\n") == 0 && fabs(strict_offsets(&piece, off)) < 1e-9, "no held notes, no drift");

    /* Thomas algorithm against a known system. */
    {
        double sub[3] = {0, 1, 1}, diag[3] = {4, 4, 4}, sup[3] = {1, 1, 0}, rhs[3] = {5, 6, 5};
        CHECK(solve_tridiagonal(3, sub, diag, sup, rhs) == 0, "tridiagonal solves");
        NEAR(rhs[0], 1.0, 1e-12, "x0");
        NEAR(rhs[1], 1.0, 1e-12, "x1");
        NEAR(rhs[2], 1.0, 1e-12, "x2");
    }

    /* ---------- bad input ---------- */
    rejects("", "no chords");
    rejects("C4 C4 E4\n", "same note twice");
    rejects("C4 E4 G4 B4 D5 F5 A5\n", "at most 6");
    rejects("a4 999\nC4 E4 G4\n", "a4 440");
    rejects("a4 nan\nC4 E4 G4\n", "a4 440");
    rejects("weights glide 1e9 drift 1\nC4\n", "weights");
    rejects("weights glide -1 drift 1\nC4\n", "weights");
    rejects("C4 E4 G4\x1b[31m\n", "plain text");
    rejects("C4 E4 G4 \xe2\x80\xae\n", "plain text");
    rejects("rm -rf /\n", "notes look like");
    {
        static char big[MAX_BYTES + 10];
        memset(big, '#', sizeof big - 1);
        big[sizeof big - 1] = '\0';
        rejects(big, "16 KB");
        char longline[200];
        memset(longline, '#', sizeof longline - 1);
        longline[sizeof longline - 1] = '\0';
        rejects(longline, "longer than");
        static char many[MAX_BYTES];
        many[0] = '\0';
        for (int i = 0; i < MAX_CHORDS + 1; i++) strcat(many, "C4\n");
        rejects(many, "more than 256");
    }

    printf("\n%d passed, %d failed\n", passed, failed);
    return failed ? 1 : 0;
}
