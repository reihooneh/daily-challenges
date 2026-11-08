/* Kilnstack: plans how to load a pottery kiln, shelf by shelf.
 *
 * The kiln is round, loaded with half (or full) shelves held up by stacks of posts. Pieces are
 * round-footed (bowls, mugs, vases): a diameter and a height. A plan says which shelf every
 * piece goes on and where, which posts hold up each shelf, and how many firings it takes. */
#ifndef KILNSTACK_H
#define KILNSTACK_H

#include <stddef.h>

#define KS_MAX_PIECES 300
#define KS_MAX_POSTS 12
#define KS_NAME 32
#define KS_MAX_BYTES (64 * 1024)
#define KS_POST_R 1.5   /* a post's footprint radius, cm */
#define KS_SPLIT 1.0    /* the gap between two half shelves, cm */
#define KS_POSTS_PER 3  /* posts under each half shelf (or under a full shelf) */

typedef struct {
    char name[KS_NAME + 1];
    double d, h; /* diameter and height, cm */
} Piece;

typedef struct {
    double diameter, height;  /* inside the kiln, cm */
    double shelf;             /* shelf thickness */
    double wall;              /* keep pieces this far from the wall and elements */
    double gap;               /* between pieces (glaze firings: they must not touch) */
    double headroom;          /* above the tallest piece on a shelf */
    double floor_post;        /* posts under the bottom shelf */
    int glaze;                /* 1 glaze firing, 0 bisque */
    int full;                 /* 1 full shelves, 0 half shelves */
    int nposts;
    double posts[KS_MAX_POSTS]; /* post heights in stock */
    int npieces;
    Piece pieces[KS_MAX_PIECES]; /* one per piece (counts are expanded) */
} Kiln;

typedef struct {
    int firing;     /* 0-based */
    double surface; /* height of the shelf's top above the kiln floor */
    double tallest;
    double stack;   /* posts holding up the next shelf (0 for the top shelf) */
    int combo[3], ncombo;
} Level;

typedef struct {
    int nlevels, nfirings;
    Level levels[KS_MAX_PIECES];
    int level[KS_MAX_PIECES]; /* each piece's level */
    int half[KS_MAX_PIECES];  /* 0 back half, 1 front half (or 0 on a full shelf) */
    double x[KS_MAX_PIECES], y[KS_MAX_PIECES];
    int order[KS_MAX_PIECES]; /* pieces tallest first */
} Plan;

/* parse.c: reads a kiln file. Returns 0, or -1 with a message (line number only) in err. */
int ks_parse(const char *text, size_t len, Kiln *k, char *err, size_t errlen);

/* pack.c */
double ks_radius(const Kiln *k);  /* usable radius for piece edges */
void ks_post_xy(const Kiln *k, int half, int i, double *x, double *y);
int ks_fits_at(const Kiln *k, const Plan *p, int lvl, int half, double r, double x, double y);
/* Smallest stack of up to three stock posts that is at least `need` tall; 0 if none. */
double ks_stack(const Kiln *k, double need, int combo[3], int *n);
/* Plans the load. Returns 0, or -1 with a reason in err (a piece too wide or too tall). */
int ks_pack(const Kiln *k, Plan *p, char *err, size_t errlen);

/* report.c */
void ks_report(const Kiln *k, const Plan *p, char *out, size_t outlen);

#endif
