#include "foldgrain.h"

#include <ctype.h>
#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const fg_scheme FG_SCHEMES_LIST[FG_SCHEMES] = {
    {"folio", 2, 1, 300},
    {"quarto", 2, 2, 140},
    {"octavo", 4, 2, 110},
    {"sextodecimo", 4, 4, 80},
};

int fg_max_nest(int gsm) {
    if (gsm <= 80) return 8;
    if (gsm <= 100) return 6;
    if (gsm <= 140) return 4;
    if (gsm <= 200) return 2;
    return 1;
}

/* ------------------------------------------------------------------ parsing */

static int number(const char **p, double lo, double hi, double *out) {
    while (**p == ' ' || **p == '\t') (*p)++;
    if (!isdigit((unsigned char)**p) && **p != '.') return 0; /* refuses signs, nan and inf */
    char *end;
    errno = 0;
    double v = strtod(*p, &end);
    if (end == *p || errno != 0 || !isfinite(v) || v < lo || v > hi) return 0;
    *p = end;
    *out = v;
    return 1;
}

static int word(const char **p, char *out, size_t cap) {
    while (**p == ' ' || **p == '\t') (*p)++;
    size_t n = 0;
    if (**p == '"') {
        (*p)++;
        while (**p && **p != '"' && **p != '\n') {
            unsigned char c = (unsigned char)**p;
            if (!isprint(c) || n + 1 >= cap) return 0;
            out[n++] = (char)c;
            (*p)++;
        }
        if (**p != '"') return 0;
        (*p)++;
    } else {
        while (**p && !isspace((unsigned char)**p)) {
            unsigned char c = (unsigned char)**p;
            if (!isprint(c) || n + 1 >= cap) return 0;
            out[n++] = (char)c;
            (*p)++;
        }
    }
    out[n] = '\0';
    return n > 0;
}

static int at_end(const char *p) {
    while (*p == ' ' || *p == '\t' || *p == '\r') p++;
    return *p == '\0' || *p == '#';
}

#define FAIL(...) do { snprintf(err, errlen, __VA_ARGS__); return -lineno; } while (0)

int fg_parse(const char *text, size_t len, fg_book *book, char *err, size_t errlen) {
    memset(book, 0, sizeof *book);
    book->copies = 1;
    book->gsm = 90;
    book->margin = 3;
    int lineno = 0;
    if (len > (size_t)64 * 1024) {
        snprintf(err, errlen, "the file is larger than 64 KB");
        return -1;
    }
    char line[512];
    size_t i = 0;
    while (i < len) {
        size_t n = 0;
        lineno++;
        while (i < len && text[i] != '\n') {
            if (text[i] == '\0') FAIL("line %d contains a NUL byte", lineno);
            if (n + 1 >= sizeof line) FAIL("line %d is too long", lineno);
            line[n++] = text[i++];
        }
        i++;
        line[n] = '\0';
        const char *p = line;
        char key[FG_NAME];
        while (*p == ' ' || *p == '\t') p++;
        if (at_end(p)) continue;
        if (!word(&p, key, sizeof key)) FAIL("line %d: expected a keyword", lineno);
        double a, b;
        if (strcmp(key, "trim") == 0) {
            if (!number(&p, 20, 1000, &a) || !number(&p, 20, 1000, &b)) FAIL("line %d: trim needs width and height in mm (20 to 1000)", lineno);
            book->trim_w = a;
            book->trim_h = b;
        } else if (strcmp(key, "pages") == 0) {
            if (!number(&p, 4, 2000, &a) || a != floor(a)) FAIL("line %d: pages must be a whole number from 4 to 2000", lineno);
            book->pages = (int)a;
        } else if (strcmp(key, "copies") == 0) {
            if (!number(&p, 1, 500, &a) || a != floor(a)) FAIL("line %d: copies must be a whole number from 1 to 500", lineno);
            book->copies = (int)a;
        } else if (strcmp(key, "gsm") == 0) {
            if (!number(&p, 30, 400, &a) || a != floor(a)) FAIL("line %d: gsm must be a whole number from 30 to 400", lineno);
            book->gsm = (int)a;
        } else if (strcmp(key, "margin") == 0) {
            if (!number(&p, 0, 20, &a)) FAIL("line %d: margin must be 0 to 20 mm", lineno);
            book->margin = a;
        } else if (strcmp(key, "sheet") == 0) {
            if (book->n_sheets >= FG_MAX_SHEETS) FAIL("line %d: at most %d sheet sizes", lineno, FG_MAX_SHEETS);
            fg_sheet *s = &book->sheets[book->n_sheets];
            char grain[16];
            if (!word(&p, s->name, sizeof s->name)) FAIL("line %d: sheet needs a name (quote it if it has spaces)", lineno);
            if (!number(&p, 50, 3000, &s->w) || !number(&p, 50, 3000, &s->h)) FAIL("line %d: sheet needs width and height in mm (50 to 3000)", lineno);
            if (!word(&p, grain, sizeof grain) || (strcmp(grain, "long") != 0 && strcmp(grain, "short") != 0))
                FAIL("line %d: say whether the grain runs along the long or short side", lineno);
            s->grain_long = strcmp(grain, "long") == 0;
            if (!number(&p, 0, 10000, &s->price)) FAIL("line %d: sheet needs a price", lineno);
            book->n_sheets++;
        } else {
            FAIL("line %d: unknown keyword (use trim, pages, copies, gsm, margin or sheet)", lineno);
        }
        if (!at_end(p)) FAIL("line %d: unexpected text after the values", lineno);
    }
    /* Whole-file problems aren't on any one line: report them as line 1 so the result is non-zero. */
    lineno = 1;
    if (book->trim_w <= 0) FAIL("the book needs a trim size");
    if (book->pages <= 0) FAIL("the book needs a page count");
    if (book->n_sheets == 0) FAIL("list at least one sheet of paper you can buy");
    return 0;
}

/* ------------------------------------------------------------------ planning */

static int cmp(const void *a, const void *b) {
    const fg_option *x = a, *y = b;
    if (x->cost != y->cost) return x->cost < y->cost ? -1 : 1;
    if (x->blanks != y->blanks) return x->blanks - y->blanks;
    if (x->signatures != y->signatures) return x->signatures - y->signatures;
    return x->waste < y->waste ? -1 : (x->waste > y->waste);
}

int fg_options(const fg_book *b, fg_option *out, int max) {
    int n = 0;
    for (int s = 0; s < b->n_sheets; s++) {
        const fg_sheet *sh = &b->sheets[s];
        double longer = sh->w > sh->h ? sh->w : sh->h, shorter = sh->w > sh->h ? sh->h : sh->w;
        double along_grain = sh->grain_long ? longer : shorter;
        double across_grain = sh->grain_long ? shorter : longer;
        for (int k = 0; k < FG_SCHEMES; k++) {
            const fg_scheme *sc = &FG_SCHEMES_LIST[k];
            if (b->gsm > sc->max_gsm) continue;
            double fw = sc->cols * b->trim_w + 2 * b->margin;
            double fh = sc->rows * b->trim_h + 2 * b->margin;
            /* The spine runs along the flat sheet's height, so that must lie along the grain. */
            int along = (int)floor(along_grain / fh + 1e-9), across = (int)floor(across_grain / fw + 1e-9);
            if (along < 1 || across < 1) continue;
            int per_page = 2 * sc->cols * sc->rows;
            int folded = (b->pages + per_page - 1) / per_page;
            int nest = fg_max_nest(b->gsm);
            int signatures = (folded + nest - 1) / nest;
            int per_parent = along * across;
            long need = (long)folded * b->copies;
            int parents = (int)((need + per_parent - 1) / per_parent);
            if (n >= max) break;
            fg_option *o = &out[n++];
            o->sheet = s;
            o->scheme = k;
            o->flat_w = fw;
            o->flat_h = fh;
            o->across = across;
            o->along = along;
            o->per_parent = per_parent;
            o->folded = folded;
            o->signatures = signatures;
            o->nest = (folded + signatures - 1) / signatures; /* spread evenly */
            o->blanks = folded * per_page - b->pages;
            o->parents = parents;
            o->cost = parents * sh->price;
            o->waste = 1.0 - (double)need * fw * fh / ((double)parents * sh->w * sh->h);
        }
    }
    qsort(out, (size_t)n, sizeof *out, cmp);
    return n;
}
