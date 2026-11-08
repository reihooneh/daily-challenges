/* Reading a kiln file: untrusted text, read strictly. Every line is one known command with a
 * fixed number of fields; numbers are plain decimals within a range; names are printable
 * ASCII. Errors give a line number, never the line. */
#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "kilnstack.h"

#define LINE_MAX_LEN 200
#define MAX_WORDS 16

static int fail(char *err, size_t errlen, int line, const char *msg) {
    if (line > 0)
        snprintf(err, errlen, "line %d: %s", line, msg);
    else
        snprintf(err, errlen, "%s", msg);
    return -1;
}

/* A plain decimal: optional digits, optional . and up to 3 decimals; no signs, exponents,
 * nan or inf. */
static int number(const char *s, double lo, double hi, double *out) {
    size_t i = 0, digits = 0, frac = 0;
    while (isdigit((unsigned char)s[i])) { i++; digits++; }
    if (s[i] == '.') {
        i++;
        while (isdigit((unsigned char)s[i])) { i++; frac++; }
    }
    if (s[i] != '\0' || digits == 0 || digits > 4 || frac > 3) return -1;
    double v = strtod(s, NULL);
    if (!isfinite(v) || v < lo || v > hi) return -1;
    *out = v;
    return 0;
}

static int split(char *line, char *words[], int max) {
    int n = 0;
    char *save = NULL;
    for (char *w = strtok_r(line, " \t", &save); w; w = strtok_r(NULL, " \t", &save)) {
        if (n == max) return -1;
        words[n++] = w;
    }
    return n;
}

static int add_piece(Kiln *k, const char *name, double d, double h) {
    if (k->npieces >= KS_MAX_PIECES) return -1;
    Piece *p = &k->pieces[k->npieces++];
    snprintf(p->name, sizeof p->name, "%s", name);
    p->d = d;
    p->h = h;
    return 0;
}

int ks_parse(const char *text, size_t len, Kiln *k, char *err, size_t errlen) {
    memset(k, 0, sizeof *k);
    k->diameter = 46; k->height = 66; k->shelf = 1.6; k->wall = 2.5; k->gap = 1.0;
    k->headroom = 1.5; k->floor_post = 2.5; k->glaze = 1; k->full = 0;
    int have_kiln = 0;
    if (len > KS_MAX_BYTES) return fail(err, errlen, 0, "the kiln file is over 64 KB");
    char line[LINE_MAX_LEN + 2];
    size_t pos = 0;
    int n = 0;
    while (pos < len) {
        n++;
        size_t end = pos;
        while (end < len && text[end] != '\n') end++;
        size_t ll = end - pos;
        if (ll > 0 && text[pos + ll - 1] == '\r') ll--;
        if (ll > LINE_MAX_LEN) return fail(err, errlen, n, "longer than 200 characters");
        memcpy(line, text + pos, ll);
        line[ll] = '\0';
        pos = end + 1;
        for (size_t i = 0; i < ll; i++) {
            unsigned char c = (unsigned char)line[i];
            if (c == '\t') continue;
            if (c < 0x20 || c > 0x7e) return fail(err, errlen, n, "only printable ASCII text is allowed");
        }
        char *hash = strchr(line, '#');
        if (hash) *hash = '\0';
        char *w[MAX_WORDS];
        int nw = split(line, w, MAX_WORDS);
        if (nw < 0) return fail(err, errlen, n, "too many words");
        if (nw == 0) continue;
        double a, b, c;
        if (strcmp(w[0], "kiln") == 0 && nw == 3) {
            if (number(w[1], 20, 150, &a) || number(w[2], 15, 150, &b))
                return fail(err, errlen, n, "kiln is the inside diameter (20-150 cm) and height (15-150 cm)");
            k->diameter = a; k->height = b; have_kiln = 1;
        } else if (strcmp(w[0], "shelves") == 0 && nw == 2 && (!strcmp(w[1], "half") || !strcmp(w[1], "full"))) {
            k->full = strcmp(w[1], "full") == 0;
        } else if (strcmp(w[0], "firing") == 0 && nw == 2 && (!strcmp(w[1], "glaze") || !strcmp(w[1], "bisque"))) {
            k->glaze = strcmp(w[1], "glaze") == 0;
            if (!k->glaze) k->gap = 0.0;
        } else if ((!strcmp(w[0], "shelf") || !strcmp(w[0], "wall") || !strcmp(w[0], "gap") ||
                    !strcmp(w[0], "headroom") || !strcmp(w[0], "floor")) && nw == 2) {
            double lo = strcmp(w[0], "shelf") == 0 ? 0.5 : 0.0;
            if (number(w[1], lo, 10, &a)) return fail(err, errlen, n, "a setting is a number of cm from 0 to 10");
            if (!strcmp(w[0], "shelf")) k->shelf = a;
            else if (!strcmp(w[0], "wall")) k->wall = a;
            else if (!strcmp(w[0], "gap")) k->gap = a;
            else if (!strcmp(w[0], "headroom")) k->headroom = a;
            else k->floor_post = a;
        } else if (strcmp(w[0], "posts") == 0 && nw >= 2) {
            if (nw - 1 > KS_MAX_POSTS) return fail(err, errlen, n, "at most 12 post sizes");
            k->nposts = 0;
            for (int i = 1; i < nw; i++) {
                if (number(w[i], 0.5, 60, &a)) return fail(err, errlen, n, "post heights are 0.5 to 60 cm");
                k->posts[k->nposts++] = a;
            }
        } else if (strcmp(w[0], "piece") == 0 && nw >= 3) {
            /* piece DIAMETER HEIGHT [COUNT] [NAME...] */
            if (number(w[1], 1, 150, &a) || number(w[2], 0.5, 150, &b))
                return fail(err, errlen, n, "a piece is its diameter and height in cm");
            int count = 1, first = 3;
            if (nw > 3 && strspn(w[3], "0123456789.") == strlen(w[3])) {
                if (number(w[3], 1, 300, &c) != 0) return fail(err, errlen, n, "a count is from 1 to 300");
                if (c != floor(c)) return fail(err, errlen, n, "a count is a whole number");
                count = (int)c;
                first = 4;
            }
            char name[KS_NAME + 1] = "";
            size_t used = 0;
            for (int i = first; i < nw; i++) {
                size_t wl = strlen(w[i]);
                if (used + wl + (used ? 1 : 0) > KS_NAME) return fail(err, errlen, n, "a name is at most 32 characters");
                if (used) name[used++] = ' ';
                memcpy(name + used, w[i], wl);
                used += wl;
                name[used] = '\0';
            }
            for (size_t i = 0; i < used; i++)
                if (!isalnum((unsigned char)name[i]) && !strchr(" -'.&()", name[i]))
                    return fail(err, errlen, n, "a name uses letters, digits, spaces and - ' . & ( )");
            if (used == 0) snprintf(name, sizeof name, "piece");
            for (int i = 0; i < count; i++)
                if (add_piece(k, name, a, b)) return fail(err, errlen, n, "at most 300 pieces");
        } else {
            return fail(err, errlen, n, "expected kiln, shelves, firing, shelf, wall, gap, headroom, floor, posts or piece");
        }
    }
    (void)have_kiln;
    if (k->nposts == 0) return fail(err, errlen, 0, "list the post heights you have, like: posts 2.5 5 7.5 10 15");
    if (k->npieces == 0) return fail(err, errlen, 0, "no pieces to load");
    if (k->diameter / 2 - k->wall < 5) return fail(err, errlen, 0, "the wall clearance leaves no room");
    return 0;
}
