/* Tests for Foldgrain. Built with AddressSanitizer and UBSan by `make test`. */
#include "../src/foldgrain.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static int parse(const char *text, fg_book *b, char *err) {
    return fg_parse(text, strlen(text), b, err, 160);
}

static const char *BASE = "trim 140 210\npages 192\ncopies 3\ngsm 100\nmargin 3\n"
                          "sheet \"Fabriano 50x70\" 700 500 short 2.40\nsheet A2 594 420 long 1.90\n";

static void test_parse_and_plan(void) {
    fg_book b;
    char err[160];
    CHECK(parse(BASE, &b, err) == 0);
    CHECK(b.n_sheets == 2 && b.pages == 192 && b.copies == 3);
    CHECK(strcmp(b.sheets[0].name, "Fabriano 50x70") == 0);
    fg_option o[16];
    int n = fg_options(&b, o, 16);
    CHECK(n == 5); /* sextodecimo is too heavy at 100 gsm */
    for (int i = 0; i < n; i++) CHECK(strcmp(FG_SCHEMES_LIST[o[i].scheme].name, "sextodecimo") != 0);
    for (int i = 1; i < n; i++) CHECK(o[i - 1].cost <= o[i].cost);
    /* the cheapest is the Fabriano octavo: 12 folded sheets per copy, one flat per parent sheet */
    CHECK(o[0].sheet == 0 && strcmp(FG_SCHEMES_LIST[o[0].scheme].name, "octavo") == 0);
    CHECK(o[0].folded == 12 && o[0].parents == 36 && o[0].signatures == 2 && o[0].blanks == 0);
    CHECK(fabs(o[0].cost - 86.40) < 1e-9);
}

/* Brute force: try both orientations of the flat in the parent sheet, keep only grain-correct ones. */
static int brute_count(const fg_sheet *s, double fw, double fh) {
    int best = 0;
    for (int rot = 0; rot < 2; rot++) {
        double along_w = rot ? s->h : s->w; /* the parent side the flat's height lies along */
        double other = rot ? s->w : s->h;
        int grain_on_w = s->grain_long ? s->w >= s->h : s->w < s->h;
        int grain_along_this = rot ? !grain_on_w : grain_on_w;
        if (!grain_along_this) continue;
        int n = (int)floor(along_w / fh + 1e-9) * (int)floor(other / fw + 1e-9);
        if (n > best) best = n;
    }
    return best;
}

static void test_grain_always_runs_along_the_spine(void) {
    for (int w = 300; w <= 1000; w += 70) {
        for (int h = 250; h <= 900; h += 65) {
            for (int g = 0; g < 2; g++) {
                fg_book b;
                char err[160], text[400];
                snprintf(text, sizeof text, "trim 120 180\npages 64\ngsm 80\nmargin 2\nsheet S %d %d %s 1\n", w, h, g ? "long" : "short");
                CHECK(parse(text, &b, err) == 0);
                fg_option o[8];
                int n = fg_options(&b, o, 8);
                for (int i = 0; i < n; i++) CHECK(o[i].per_parent == brute_count(&b.sheets[0], o[i].flat_w, o[i].flat_h));
                for (int k = 0; k < FG_SCHEMES; k++) {
                    double fw = FG_SCHEMES_LIST[k].cols * 120 + 4, fh = FG_SCHEMES_LIST[k].rows * 180 + 4;
                    int listed = 0;
                    for (int i = 0; i < n; i++) listed |= o[i].scheme == k;
                    CHECK(listed == (brute_count(&b.sheets[0], fw, fh) > 0));
                }
            }
        }
    }
}

static void test_padding_and_signatures(void) {
    fg_book b;
    char err[160];
    CHECK(parse("trim 100 150\npages 70\ngsm 70\nsheet big 1000 700 long 1\n", &b, err) == 0);
    fg_option o[8];
    int n = fg_options(&b, o, 8);
    CHECK(n > 0);
    for (int i = 0; i < n; i++) {
        int per = 2 * FG_SCHEMES_LIST[o[i].scheme].cols * FG_SCHEMES_LIST[o[i].scheme].rows;
        CHECK(o[i].folded * per >= 70 && (o[i].folded - 1) * per < 70);
        CHECK(o[i].blanks == o[i].folded * per - 70);
        CHECK(o[i].signatures * fg_max_nest(70) >= o[i].folded);
        CHECK(o[i].waste >= 0 && o[i].waste < 1);
    }
    CHECK(fg_max_nest(300) == 1 && fg_max_nest(60) == 8);
}

static void test_hostile_input(void) {
    fg_book b;
    char err[160];
    const char *bad[] = {
        "trim nan 200\npages 10\nsheet a 500 500 long 1\n",
        "trim inf 200\npages 10\nsheet a 500 500 long 1\n",
        "trim -140 200\npages 10\nsheet a 500 500 long 1\n",
        "trim 140 200\npages 10.5\nsheet a 500 500 long 1\n",
        "trim 140 200\npages 10\nsheet a 500 500 sideways 1\n",
        "trim 140 200\npages 10\nsheet \"unclosed 500 500 long 1\n",
        "trim 140 200\npages 10\nsheet a 500 500 long 1 extra\n",
        "trim 140 200\npages 10\nrm -rf /\n",
        "trim 140 200\npages 10\n",
        "pages 10\nsheet a 500 500 long 1\n",
        "trim 140 200 \x1b[31m\npages 10\nsheet a 500 500 long 1\n",
        "trim 1e308 200\npages 10\nsheet a 500 500 long 1\n",
    };
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        if (parse(bad[i], &b, err) == 0) printf("accepted bad input %zu\n", i);
        CHECK(parse(bad[i], &b, err) != 0);
    }
    char line[1200];
    memset(line, 'a', sizeof line - 1);
    line[sizeof line - 1] = '\0';
    CHECK(parse(line, &b, err) != 0 && strstr(err, "too long") != NULL);
    char many[4000];
    int used = snprintf(many, sizeof many, "trim 140 200\npages 10\n");
    for (int i = 0; i < 20; i++) used += snprintf(many + used, sizeof many - (size_t)used, "sheet a 500 500 long 1\n");
    CHECK(parse(many, &b, err) != 0 && strstr(err, "at most") != NULL);
    const char nul[] = "trim 140 200\0\npages 10\n";
    CHECK(fg_parse(nul, sizeof nul - 1, &b, err, sizeof err) != 0);
    /* a parse error names the line */
    CHECK(parse("trim 140 200\npages 10\nsheet a 500 500 long\n", &b, err) == -3);
}

int main(void) {
    test_parse_and_plan();
    test_grain_always_runs_along_the_spine();
    test_padding_and_signatures();
    test_hostile_input();
    if (failures) {
        printf("%d check(s) failed\n", failures);
        return 1;
    }
    printf("All Foldgrain tests passed.\n");
    return 0;
}
