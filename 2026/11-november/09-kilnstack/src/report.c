/* The loading plan in words, with a map of every shelf seen from above. */
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "kilnstack.h"

#define MAP_W 41
#define MAP_H 21

typedef struct {
    char *buf;
    size_t len, used;
} Out;

__attribute__((format(printf, 2, 3))) static void put(Out *o, const char *fmt, ...) {
    if (o->used >= o->len) return;
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(o->buf + o->used, o->len - o->used, fmt, ap);
    va_end(ap);
    if (n < 0) return;
    o->used += (size_t)n;
    if (o->used >= o->len) o->used = o->len - 1; /* truncated, still terminated */
}

static char label(int k) {
    const char *s = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    return k < 62 ? s[k] : '*';
}

static void map(Out *o, const Kiln *k, const Plan *p, int lvl, const int *pieces, int n) {
    double R = k->diameter / 2;
    for (int row = 0; row < MAP_H; row++) {
        char line[MAP_W + 1];
        double y = R - (row + 0.5) * (2 * R / MAP_H);
        for (int col = 0; col < MAP_W; col++) {
            double x = -R + (col + 0.5) * (2 * R / MAP_W);
            char c = ' ';
            if (hypot(x, y) <= R) c = (!k->full && fabs(y) < KS_SPLIT / 2) ? ' ' : '.';
            int half = (!k->full && y < 0) ? 1 : 0;
            for (int i = 0; i < KS_POSTS_PER && c != ' '; i++) {
                double px, py;
                ks_post_xy(k, half, i, &px, &py);
                if (hypot(x - px, y - py) <= KS_POST_R + 0.6) c = 'o';
            }
            for (int m = 0; m < n && c != ' '; m++) {
                int j = pieces[m];
                if (p->half[j] == half && hypot(x - p->x[j], y - p->y[j]) <= k->pieces[j].d / 2) c = label(m);
            }
            line[col] = c;
        }
        line[MAP_W] = '\0';
        size_t e = MAP_W;
        while (e > 0 && line[e - 1] == ' ') line[--e] = '\0';
        put(o, "      %s\n", line);
    }
    (void)lvl;
}

void ks_report(const Kiln *k, const Plan *p, char *out, size_t outlen) {
    Out o = {out, outlen, 0};
    out[0] = '\0';
    double R = ks_radius(k), area = 0, used_area = 0;
    for (int i = 0; i < k->npieces; i++) area += M_PI * k->pieces[i].d * k->pieces[i].d / 4;
    double shelf_area = k->full ? M_PI * R * R : M_PI * R * R - 2 * R * KS_SPLIT;
    used_area = shelf_area * p->nlevels;
    put(&o, "KILNSTACK  %s firing, %.0f cm kiln %.0f cm tall, %s shelves: %d piece%s in %d firing%s on %d shelves\n",
        k->glaze ? "glaze" : "bisque", k->diameter, k->height, k->full ? "full" : "half", k->npieces,
        k->npieces == 1 ? "" : "s", p->nfirings, p->nfirings == 1 ? "" : "s", p->nlevels);
    int bound = (int)ceil(area / shelf_area - 1e-9);
    put(&o, "  By floor area alone they need at least %d shel%s.\n", bound, bound == 1 ? "f" : "ves");
    put(&o, "  Pieces cover %.0f%% of the shelf space used; %s.\n\n", used_area > 0 ? 100 * area / used_area : 0,
        k->glaze ? "glazed pieces kept apart so they can't fuse" : "bisque pieces may touch");

    for (int f = 0; f < p->nfirings; f++) {
        double top = 0;
        int nl = 0;
        for (int l = 0; l < p->nlevels; l++)
            if (p->levels[l].firing == f) {
                nl++;
                top = p->levels[l].surface + p->levels[l].tallest + k->headroom;
            }
        put(&o, "Firing %d: %d shel%s, loaded to %.1f of %.1f cm\n", f + 1, nl, nl == 1 ? "f" : "ves", top, k->height);
        int shelfno = 0;
        for (int l = 0; l < p->nlevels; l++) {
            const Level *L = &p->levels[l];
            if (L->firing != f) continue;
            shelfno++;
            int pieces[KS_MAX_PIECES], n = 0;
            for (int o2 = 0; o2 < k->npieces; o2++) {
                int i = p->order[o2];
                if (p->level[i] == l) pieces[n++] = i;
            }
            put(&o, "  Shelf %d at %.1f cm, tallest piece %.1f cm", shelfno, L->surface, L->tallest);
            if (L->ncombo > 0) {
                put(&o, "; posts above: ");
                for (int c = 0; c < L->ncombo; c++) put(&o, "%s%g", c ? " + " : "", k->posts[L->combo[c]]);
                put(&o, " = %g cm\n", L->stack);
            } else {
                put(&o, "; top shelf\n");
            }
            for (int m = 0; m < n; m++) {
                const Piece *pc = &k->pieces[pieces[m]];
                put(&o, "%s%c %s %gx%g", m % 4 == 0 ? "    " : "   ", label(m), pc->name, pc->d, pc->h);
                if (m % 4 == 3 || m == n - 1) put(&o, "\n");
            }
            map(&o, k, p, l, pieces, n);
        }
        put(&o, "\n");
    }
    put(&o, "Map: letters are pieces, o is a post, the blank band splits the two half shelves.\n");
}
