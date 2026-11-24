/* Foldgrain: plans how to cut and fold a handbound book's signatures from the paper you can buy,
 * with the grain parallel to the spine of every folded sheet. */
#ifndef FOLDGRAIN_H
#define FOLDGRAIN_H

#include <stddef.h>

#define FG_MAX_SHEETS 16
#define FG_NAME 40
#define FG_SCHEMES 4

typedef struct {
    char name[FG_NAME];
    double w, h;    /* mm */
    int grain_long; /* 1: grain runs along the long side; 0: along the short side */
    double price;   /* per sheet */
} fg_sheet;

typedef struct {
    double trim_w, trim_h; /* the finished page, mm */
    int pages;
    int copies;
    int gsm;
    double margin; /* trimmed off each outer edge of a folded sheet, mm */
    int n_sheets;
    fg_sheet sheets[FG_MAX_SHEETS];
} fg_book;

typedef struct {
    const char *name; /* folio, quarto, octavo, sextodecimo */
    int cols, rows;   /* page panels across and along the spine on one side of the flat sheet */
    int max_gsm;      /* heavier paper won't fold this many times cleanly */
} fg_scheme;

extern const fg_scheme FG_SCHEMES_LIST[FG_SCHEMES];

typedef struct {
    int sheet, scheme;
    double flat_w, flat_h;   /* flat sheet before folding: w across the spine, h along it */
    int across, along;       /* flats per parent sheet, laid out across and along the grain */
    int per_parent;
    int folded;              /* folded sheets per copy */
    int nest;                /* folded sheets per signature (the largest) */
    int signatures;
    int blanks;              /* blank pages added to fill the last folded sheet */
    int parents;             /* parent sheets to buy */
    double cost, waste;      /* waste: share of the paper bought that ends up as offcuts */
} fg_option;

/* Reads a book description. Returns 0, or -line on error with a message in err. */
int fg_parse(const char *text, size_t len, fg_book *book, char *err, size_t errlen);

/* Every feasible way to make the book, cheapest first. Returns the count (at most max). */
int fg_options(const fg_book *book, fg_option *out, int max);

/* Folded sheets per signature for a paper weight (heavier paper, fewer per signature). */
int fg_max_nest(int gsm);

#endif
