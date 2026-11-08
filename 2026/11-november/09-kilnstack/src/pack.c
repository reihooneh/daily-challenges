/* Packing: which shelf each piece goes on, where on it, and the posts between shelves.
 *
 * Shelves go in bottom up, tallest pieces first. Each new shelf is as tall as the tallest piece
 * still waiting; it is then filled with every shorter piece that fits (first fit, tallest
 * first). Pieces are placed one at a time at the free spot nearest the wall, which packs rings
 * from the outside in. The posts above a shelf are the shortest stack from the sizes in stock
 * that clears its tallest piece. When the next shelf wouldn't fit under the lid, that firing
 * is full and the next one starts. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#include "kilnstack.h"

#define STEP 0.5     /* candidate spots, cm apart */
#define POST_GAP 0.3 /* clearance around posts */
#define PI 3.14159265358979323846

double ks_radius(const Kiln *k) { return k->diameter / 2 - k->wall; }

/* Posts sit just inside the shelf edge: for a half shelf at 15, 90 and 165 degrees round its
 * curved edge; for a full shelf at 90, 210 and 330 degrees. */
void ks_post_xy(const Kiln *k, int half, int i, double *x, double *y) {
    double rp = k->diameter / 2 - k->wall + KS_POST_R;
    double deg = k->full ? 90.0 + 120.0 * i : (i == 0 ? 15.0 : i == 1 ? 90.0 : 165.0);
    double a = deg * PI / 180;
    rp = fmin(rp, k->diameter / 2 - KS_POST_R - 0.5);
    *x = rp * cos(a);
    *y = rp * sin(a) * (half == 1 ? -1 : 1);
}

int ks_fits_at(const Kiln *k, const Plan *p, int lvl, int half, double r, double x, double y) {
    if (hypot(x, y) + r > ks_radius(k) + 1e-9) return 0;
    if (!k->full) {
        if (half == 0 && y - r < KS_SPLIT / 2 - 1e-9) return 0;
        if (half == 1 && y + r > -KS_SPLIT / 2 + 1e-9) return 0;
    }
    for (int i = 0; i < KS_POSTS_PER; i++) {
        double px, py;
        ks_post_xy(k, half, i, &px, &py);
        if (hypot(x - px, y - py) < r + KS_POST_R + POST_GAP - 1e-9) return 0;
    }
    for (int j = 0; j < k->npieces; j++) {
        if (p->level[j] != lvl || p->half[j] != half) continue;
        double rj = k->pieces[j].d / 2;
        if (hypot(x - p->x[j], y - p->y[j]) < r + rj + k->gap - 1e-9) return 0;
    }
    return 1;
}

/* Where to put the next piece: strategy 0 takes the free spot nearest the wall (rings from the
 * outside in); strategy 1 the spot nearest the straight edge, then furthest left (rows). */
static double score(int strategy, int full, double x, double y) {
    if (strategy == 0) return hypot(x, y) * 10 - fabs(x) * 0.01;
    return full ? -(y * 1000 + x) : -(fabs(y) * 1000 + x);
}

static int place(const Kiln *k, Plan *p, int lvl, int piece, int strategy) {
    double r = k->pieces[piece].d / 2, R = ks_radius(k);
    int halves = k->full ? 1 : 2;
    double best = -HUGE_VAL, bx = 0, by = 0;
    int bh = -1;
    for (int h = 0; h < halves; h++) {
        int steps = (int)floor(2 * R / STEP);
        for (int iy = 0; iy <= steps; iy++) {
            for (int ix = 0; ix <= steps; ix++) {
                double x = -R + ix * STEP, y = -R + iy * STEP;
                double sc = score(strategy, k->full, x, y);
                if (sc <= best) continue;
                if (!ks_fits_at(k, p, lvl, h, r, x, y)) continue;
                best = sc; bx = x; by = y; bh = h;
            }
        }
    }
    if (bh < 0) return 0;
    p->level[piece] = lvl;
    p->half[piece] = bh;
    p->x[piece] = bx;
    p->y[piece] = by;
    return 1;
}

double ks_stack(const Kiln *k, double need, int combo[3], int *n) {
    double best = 0;
    *n = 0;
    int m = k->nposts;
    /* One, two or three posts (repeats allowed), the shortest total that is tall enough. */
    for (int a = 0; a < m; a++)
        for (int b = -1; b < m; b++)
            for (int c = -1; c < m; c++) {
                if (b < 0 && c >= 0) continue;
                double s = k->posts[a] + (b >= 0 ? k->posts[b] : 0) + (c >= 0 ? k->posts[c] : 0);
                if (s + 1e-9 < need) continue;
                int cnt = 1 + (b >= 0) + (c >= 0);
                if (best == 0 || s < best - 1e-9 || (fabs(s - best) < 1e-9 && cnt < *n)) {
                    best = s;
                    *n = cnt;
                    combo[0] = a; combo[1] = b; combo[2] = c;
                }
            }
    return best;
}

static int taller_first(const void *pa, const void *pb, const Kiln *k) {
    const Piece *a = &k->pieces[*(const int *)pa], *b = &k->pieces[*(const int *)pb];
    if (a->h != b->h) return a->h < b->h ? 1 : -1;
    if (a->d != b->d) return a->d < b->d ? 1 : -1;
    return *(const int *)pa - *(const int *)pb;
}

static const Kiln *sort_kiln;
static int cmp(const void *a, const void *b) { return taller_first(a, b, sort_kiln); }

static int pack_with(const Kiln *k, Plan *p, int strategy, char *err, size_t errlen) {
    p->nlevels = 0;
    p->nfirings = 0;
    double R = ks_radius(k);
    double first = k->floor_post + k->shelf;
    for (int i = 0; i < k->npieces; i++) {
        p->order[i] = i;
        p->level[i] = -1;
        p->half[i] = 0;
        p->x[i] = p->y[i] = 0;
    }
    for (int i = 0; i < k->npieces; i++) {
        const Piece *pc = &k->pieces[i];
        if (first + pc->h + k->headroom > k->height + 1e-9) {
            snprintf(err, errlen, "a piece %.1f cm tall (%s) won't fit under the lid on the bottom shelf", pc->h, pc->name);
            return -1;
        }
        /* Can it sit on an empty shelf at all? (No piece is on level -2.) */
        const Plan *probe = p;
        int ok = 0;
        int steps = (int)floor(2 * R / STEP);
        for (int h = 0; h < (k->full ? 1 : 2) && !ok; h++)
            for (int iy = 0; iy <= steps && !ok; iy++)
                for (int ix = 0; ix <= steps && !ok; ix++)
                    ok = ks_fits_at(k, probe, -2, h, pc->d / 2, -R + ix * STEP, -R + iy * STEP);
        if (!ok) {
            snprintf(err, errlen, "a piece %.1f cm across (%s) is too wide for %s shelves in this kiln", pc->d, pc->name,
                     k->full ? "full" : "half");
            return -1;
        }
    }
    sort_kiln = k;
    qsort(p->order, (size_t)k->npieces, sizeof p->order[0], cmp);

    int left = k->npieces;
    double surface = first;
    int firing = 0;
    while (left > 0) {
        /* The tallest waiting piece that fits under the lid on a shelf at this height. */
        int start = -1;
        for (int o = 0; o < k->npieces; o++) {
            int i = p->order[o];
            if (p->level[i] < 0 && surface + k->pieces[i].h + k->headroom <= k->height + 1e-9) {
                start = i;
                break;
            }
        }
        if (start < 0) { /* this firing is full */
            firing++;
            surface = first;
            continue;
        }
        if (p->nlevels >= KS_MAX_PIECES) {
            snprintf(err, errlen, "too many shelves");
            return -1;
        }
        int lvl = p->nlevels++;
        Level *L = &p->levels[lvl];
        L->firing = firing;
        L->surface = surface;
        L->tallest = k->pieces[start].h;
        L->stack = 0;
        L->ncombo = 0;
        place(k, p, lvl, start, strategy);
        left--;
        for (int o = 0; o < k->npieces; o++) {
            int i = p->order[o];
            if (p->level[i] < 0 && k->pieces[i].h <= L->tallest + 1e-9 && place(k, p, lvl, i, strategy)) left--;
        }
        if (left == 0) break;
        /* Posts for the next shelf; if no next shelf fits in this firing, this one is the top. */
        double stack = ks_stack(k, L->tallest + k->headroom, L->combo, &L->ncombo);
        double next = surface + stack + k->shelf;
        int any = 0;
        for (int i = 0; i < k->npieces && !any; i++)
            if (p->level[i] < 0 && stack > 0 && next + k->pieces[i].h + k->headroom <= k->height + 1e-9) any = 1;
        if (any) {
            L->stack = stack;
            surface = next;
        } else {
            L->ncombo = 0;
            firing++;
            surface = first;
        }
    }
    p->nfirings = p->nlevels ? p->levels[p->nlevels - 1].firing + 1 : 0;
    return 0;
}

/* Packs with both strategies and keeps the plan with fewer firings, then fewer shelves. */
int ks_pack(const Kiln *k, Plan *p, char *err, size_t errlen) {
    if (pack_with(k, p, 0, err, errlen) != 0) return -1;
    Plan *other = malloc(sizeof *other);
    if (!other) return 0;
    if (pack_with(k, other, 1, err, errlen) == 0 &&
        (other->nfirings < p->nfirings || (other->nfirings == p->nfirings && other->nlevels < p->nlevels)))
        *p = *other;
    free(other);
    return 0;
}
