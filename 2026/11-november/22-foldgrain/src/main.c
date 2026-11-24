/* foldgrain BOOK.txt: prints every way to make the book, cheapest first, and the cutting plan. */
#define _POSIX_C_SOURCE 200809L /* stat() and off_t */
#include "foldgrain.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#define MAX_OPTIONS (FG_MAX_SHEETS * FG_SCHEMES)

static int region(const fg_option *o, double x, double y) {
    int ix = (int)(x / o->flat_w), iy = (int)(y / o->flat_h);
    return ix < o->across && iy < o->along ? iy * o->across + ix : -1;
}

static void diagram(const fg_book *b, const fg_option *o) {
    const fg_sheet *sh = &b->sheets[o->sheet];
    /* Drawn with the grain running down the page: rows are along the grain. */
    double longer = sh->w > sh->h ? sh->w : sh->h, shorter = sh->w > sh->h ? sh->h : sh->w;
    double along = sh->grain_long ? longer : shorter, across = sh->grain_long ? shorter : longer;
    int cols = 44, rows = (int)(cols * along / across / 2.0 + 0.5);
    if (rows < 6) rows = 6;
    if (rows > 30) rows = 30;
    printf("\n  %s, grain running down (%.0f x %.0f mm), %d flat sheet%s per parent:\n\n", sh->name, across, along,
           o->per_parent, o->per_parent == 1 ? "" : "s");
    double dx = across / cols, dy = along / rows;
    for (int r = 0; r < rows; r++) {
        printf("  ");
        for (int c = 0; c < cols; c++) {
            double x = (c + 0.5) * dx, y = (r + 0.5) * dy;
            int here = region(o, x, y);
            int left = c > 0 ? region(o, x - dx, y) : -2, right = c < cols - 1 ? region(o, x + dx, y) : -2;
            int up = r > 0 ? region(o, x, y - dy) : -2, down = r < rows - 1 ? region(o, x, y + dy) : -2;
            int vert = here >= 0 && (left != here || right != here);
            int horiz = here >= 0 && (up != here || down != here);
            if (here < 0) putchar('.');
            else if (vert && horiz) putchar('+');
            else if (horiz) putchar('-');
            else if (vert) putchar('|');
            else putchar(c % 4 == 2 ? '\'' : ' ');
        }
        putchar('\n');
    }
    printf("\n  ' marks the grain, parallel to every spine fold; dots are offcuts.\n");
}

static void signatures(const fg_option *o) {
    int q = o->folded / o->signatures, extra = o->folded % o->signatures;
    printf("  Sew %d signature%s: ", o->signatures, o->signatures == 1 ? "" : "s");
    if (extra) printf("%d of %d folded sheets and %d of %d", extra, q + 1, o->signatures - extra, q);
    else printf("%d folded sheets each", q);
    printf(".\n");
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: foldgrain BOOK.txt\n");
        return 2;
    }
    struct stat st;
    if (stat(argv[1], &st) != 0 || !S_ISREG(st.st_mode) || st.st_size > (off_t)64 * 1024) {
        fprintf(stderr, "foldgrain: the book must be a regular file under 64 KB\n");
        return 2;
    }
    FILE *f = fopen(argv[1], "rb");
    if (!f) {
        fprintf(stderr, "foldgrain: can't open the file\n");
        return 2;
    }
    char *text = malloc((size_t)st.st_size + 1);
    size_t len = text ? fread(text, 1, (size_t)st.st_size, f) : 0;
    fclose(f);
    if (!text) return 2;
    text[len] = '\0';
    fg_book book;
    char err[160];
    if (fg_parse(text, len, &book, err, sizeof err) != 0) {
        fprintf(stderr, "foldgrain: %s\n", err);
        free(text);
        return 2;
    }
    free(text);
    fg_option opts[MAX_OPTIONS];
    int n = fg_options(&book, opts, MAX_OPTIONS);
    printf("%d pages of %.0f x %.0f mm, %d cop%s, on %d gsm paper.\n\n", book.pages, book.trim_w, book.trim_h, book.copies,
           book.copies == 1 ? "y" : "ies", book.gsm);
    if (n == 0) {
        printf("No sheet you listed can be folded into these pages with the grain along the spine.\n");
        return 1;
    }
    printf("  %-22s %-12s %6s %7s %7s %7s %8s %6s\n", "paper", "fold", "flats", "sheets", "sigs", "blanks", "cost", "waste");
    for (int i = 0; i < n; i++) {
        const fg_option *o = &opts[i];
        printf("  %-22.22s %-12s %6d %7d %7d %7d %8.2f %5.0f%%\n", book.sheets[o->sheet].name, FG_SCHEMES_LIST[o->scheme].name,
               o->per_parent, o->parents, o->signatures, o->blanks, o->cost, o->waste * 100);
    }
    const fg_option *best = &opts[0];
    printf("\nCheapest: %d sheet%s of %s, cut into %d flat%s each (%.0f x %.0f mm), folded as %s.\n", best->parents,
           best->parents == 1 ? "" : "s", book.sheets[best->sheet].name, best->per_parent, best->per_parent == 1 ? "" : "s",
           best->flat_w, best->flat_h, FG_SCHEMES_LIST[best->scheme].name);
    signatures(best);
    if (best->blanks) printf("  The last folded sheet has %d blank page%s.\n", best->blanks, best->blanks == 1 ? "" : "s");
    diagram(&book, best);
    return 0;
}
