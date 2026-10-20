/* Command line: commadrift PROGRESSION.txt [--hz]   (or - for standard input) */
#include "drift.h"

#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const char *USAGE =
    "Usage: commadrift PROGRESSION.txt [--hz]   (or - for standard input)\n"
    "\n"
    "Tunes every chord pure while keeping held notes as still as possible, and shows how far a\n"
    "progression would drift if held notes could not move at all.\n"
    "Exit codes: 0 done, 2 bad input.\n";

/* Read at most MAX_BYTES + 1 bytes from fd. */
static long read_all(int fd, char *buf) {
    size_t got = 0;
    while (got < MAX_BYTES + 1) {
        ssize_t r = read(fd, buf + got, MAX_BYTES + 1 - got);
        if (r < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (r == 0) break;
        got += (size_t)r;
    }
    return (long)got;
}

static void clean_name(const char *path, char *out, size_t len) {
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : path;
    size_t i = 0;
    for (; base[i] && i + 1 < len && i < 60; i++) {
        char ch = base[i];
        int ok = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '.' ||
                 ch == '_' || ch == '-';
        out[i] = ok ? ch : '?';
    }
    out[i] = '\0';
}

static double hz(double a4, int midi, double cents) {
    return a4 * pow(2.0, (midi - 69 + cents / 100.0) / 12.0);
}

static void print_report(const Piece *p, const char *name, int show_hz) {
    static double off[MAX_CHORDS], strict[MAX_CHORDS];
    double drift = strict_offsets(p, strict);
    solve_offsets(p, off);
    printf("COMMADRIFT  %s  (%d chords, A4 = %g Hz)\n\n", name, p->count, p->a4);

    if (fabs(drift) >= 0.05) {
        printf("If every chord is pure and held notes never move, the music ends %.1f cents %s than it\n", fabs(drift),
               drift < 0 ? "lower" : "higher");
        printf("started%s.\n\n", fabs(fabs(drift) - 21.51) < 0.1 ? " (exactly a syntonic comma, 81/80)" : "");
    } else {
        printf("Pure chords with perfectly still held notes don't drift here: nothing to compromise.\n\n");
    }
    printf("Balanced plan (glide weight %g, drift weight %g): cents from equal temperament\n", p->glide,
           p->drift < 1e-5 ? 0.0 : p->drift);
    for (int k = 0; k < p->count; k++) {
        const Chord *c = &p->chords[k];
        char label[24];
        snprintf(label, sizeof label, "%s %s", PC_NAMES[c->root], c->quality);
        printf("  %3d  %-9s ", k + 1, label);
        for (int i = 0; i < c->count; i++) {
            char nn[8];
            note_name(c->midi[i], nn, sizeof nn);
            double cents = off[k] + c->dev[i];
            if (show_hz) printf(" %-4s %+6.1f (%7.2f Hz)", nn, cents, hz(p->a4, c->midi[i], cents));
            else printf(" %-4s %+6.1f", nn, cents);
        }
        printf("\n");
    }
    int at_chord, at_midi;
    double g = max_glide(p, off, &at_chord, &at_midi);
    double end = off[p->count - 1] - off[0];
    printf("\n");
    if (at_chord >= 0) {
        char nn[8];
        note_name(at_midi, nn, sizeof nn);
        printf("Largest glide of a held note: %.1f cents (%s, from chord %d to %d)%s\n", g, nn, at_chord + 1,
               at_chord + 2, g < 5.0 ? ": hard to hear" : g < 10.0 ? ": just audible" : ": clearly audible");
    } else {
        printf("No notes are held from one chord to the next.\n");
    }
    printf("The last chord ends %.1f cents from where the first began (strict plan: %.1f).\n", end, drift);
}

int main(int argc, char **argv) {
    const char *path = NULL;
    int show_hz = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            fputs(USAGE, stdout);
            return 0;
        }
        if (strcmp(argv[i], "--hz") == 0) show_hz = 1;
        else if (!path && (argv[i][0] != '-' || strcmp(argv[i], "-") == 0)) path = argv[i];
        else {
            fputs(USAGE, stderr);
            return 2;
        }
    }
    if (!path) {
        fputs(USAGE, stderr);
        return 2;
    }
    static char buf[MAX_BYTES + 1];
    static Piece piece;
    char name[64] = "standard input";
    long len;
    if (strcmp(path, "-") == 0) {
        len = read_all(STDIN_FILENO, buf);
    } else {
        /* No symlinks, and only regular files: /dev/zero, pipes and directories are refused. */
        int fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
        struct stat st;
        if (fd < 0 || fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) {
            if (fd >= 0) close(fd);
            fputs("commadrift: no such file (or not a regular file)\n", stderr);
            return 2;
        }
        len = read_all(fd, buf);
        close(fd);
        clean_name(path, name, sizeof name);
    }
    if (len < 0) {
        fputs("commadrift: the file could not be read\n", stderr);
        return 2;
    }
    char err[160];
    if (parse_piece(buf, (size_t)len, &piece, err, sizeof err) != 0) {
        fprintf(stderr, "commadrift: %s\n", err);
        return 2;
    }
    print_report(&piece, name, show_hz);
    return 0;
}
