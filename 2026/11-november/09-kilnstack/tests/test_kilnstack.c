/* Tests for Kilnstack: parsing, posts, and the packing's invariants on fixed and random kilns. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "kilnstack.h"

static int failures = 0, checks = 0;
#define CHECK(cond, ...)                                     \
    do {                                                     \
        checks++;                                            \
        if (!(cond)) {                                       \
            failures++;                                      \
            printf("FAIL line %d: ", __LINE__);              \
            printf(__VA_ARGS__);                             \
            printf("\n");                                    \
        }                                                    \
    } while (0)

static Kiln kiln;
static Plan plan;
static char err[200];

static int parse(const char *s) { return ks_parse(s, strlen(s), &kiln, err, sizeof err); }

static const char *BASE = "kiln 46 66\nposts 2.5 5 7.5 10 15\n";

static char buf[4096];
static const char *with(const char *extra) {
    snprintf(buf, sizeof buf, "%s%s", BASE, extra);
    return buf;
}

/* Every promise a plan makes, checked directly. */
static int valid(const Kiln *k, const Plan *p) {
    double R = ks_radius(k);
    for (int i = 0; i < k->npieces; i++) {
        int l = p->level[i];
        if (l < 0 || l >= p->nlevels) return 0;
        double r = k->pieces[i].d / 2, x = p->x[i], y = p->y[i];
        if (hypot(x, y) + r > R + 1e-6) return 0;
        if (!k->full && (p->half[i] == 0 ? y - r < KS_SPLIT / 2 - 1e-6 : y + r > -KS_SPLIT / 2 + 1e-6)) return 0;
        for (int q = 0; q < KS_POSTS_PER; q++) {
            double px, py;
            ks_post_xy(k, p->half[i], q, &px, &py);
            if (hypot(x - px, y - py) < r + KS_POST_R) return 0;
        }
        if (k->pieces[i].h > p->levels[l].tallest + 1e-9) return 0;
        for (int j = i + 1; j < k->npieces; j++)
            if (p->level[j] == l && p->half[j] == p->half[i] &&
                hypot(x - p->x[j], y - p->y[j]) < r + k->pieces[j].d / 2 + k->gap - 1e-6)
                return 0;
    }
    for (int l = 0; l < p->nlevels; l++) {
        const Level *L = &p->levels[l];
        if (L->surface + L->tallest + k->headroom > k->height + 1e-6) return 0;
        if (l + 1 < p->nlevels && p->levels[l + 1].firing == L->firing) {
            if (fabs(p->levels[l + 1].surface - (L->surface + L->stack + k->shelf)) > 1e-6) return 0;
            if (L->stack < L->tallest + k->headroom - 1e-9) return 0;
        }
    }
    return 1;
}

static void test_parse(void) {
    CHECK(parse(with("piece 9 11 12 Mug\npiece 30 5\n")) == 0, "good file: %s", err);
    CHECK(kiln.npieces == 13 && strcmp(kiln.pieces[0].name, "Mug") == 0 && strcmp(kiln.pieces[12].name, "piece") == 0, "counts and names");
    struct { const char *text, *msg; } bad[] = {
        {"kiln 46 66\nposts 5\n", "no pieces"},
        {"kiln 46 66\npiece 9 9\n", "post heights"},
        {"piece 9 nan\nposts 5\n", "diameter and height"},
        {"piece 9 1e3\nposts 5\n", "diameter and height"},
        {"piece -9 5\nposts 5\n", "diameter and height"},
        {"piece 9 5 2.5\nposts 5\n", "whole number"},
        {"piece 9 5 301\nposts 5\n", "from 1 to 300"},
        {"piece 9 5 200\npiece 9 5 200\nposts 5\n", "at most 300"},
        {"piece 9 5 <script>SECRET\nposts 5\n", "a name uses"},
        {"piece 9 5 AVeryLongNameThatGoesOnAndOnForever SECRET\nposts 5\n", "at most 32"},
        {"piece 9 5\n$(touch SECRET)\nposts 5\n", "expected kiln"},
        {"piece 9 5 Mug\x1b[2J\nposts 5\n", "printable ASCII"},
        {"piece 9 5 Caf\xc3\xa9\nposts 5\n", "printable ASCII"},
        {"kiln 46 66\nwall 10\nwall 10.5\npiece 9 5\nposts 5\n", "a setting"},
        {"kiln 20 66\nwall 6\npiece 9 5\nposts 5\n", "no room"},
        {"posts 1 2 3 4 5 6 7 8 9 10 11 12 13\npiece 9 5\n", "at most 12"},
        {"firing raku\nposts 5\npiece 9 5\n", "expected kiln"},
    };
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        int r = parse(bad[i].text);
        CHECK(r != 0 && strstr(err, bad[i].msg) && !strstr(err, "SECRET"), "refuse %zu: %s", i, err);
    }
    char big[KS_MAX_BYTES + 10];
    memset(big, '#', sizeof big);
    CHECK(ks_parse(big, sizeof big, &kiln, err, sizeof err) != 0 && strstr(err, "64 KB"), "size cap");
    char longl[300];
    memset(longl, 'x', sizeof longl - 1);
    longl[sizeof longl - 1] = '\0';
    CHECK(parse(longl) != 0 && strstr(err, "200 characters"), "long line");
    const char nul[] = "posts 5\npiece 9\0 5\n";
    CHECK(ks_parse(nul, sizeof nul - 1, &kiln, err, sizeof err) != 0, "NUL byte");
}

static void test_posts(void) {
    parse(with("piece 9 5\n"));
    int c[3], n;
    CHECK(fabs(ks_stack(&kiln, 12, c, &n) - 12.5) < 1e-9 && n == 2, "12 cm needs 12.5 from two posts");
    CHECK(fabs(ks_stack(&kiln, 15, c, &n) - 15) < 1e-9 && n == 1, "15 is one post");
    CHECK(fabs(ks_stack(&kiln, 27, c, &n) - 27.5) < 1e-9 && n == 3, "27 cm needs 27.5");
    CHECK(ks_stack(&kiln, 46, c, &n) == 0, "more than three 15s is impossible");
}

static void test_known(void) {
    /* Ten 6 cm tiles, all the same height: one shelf, and the plan is valid. */
    CHECK(parse(with("piece 6 2 10 Tile\n")) == 0, "%s", err);
    CHECK(ks_pack(&kiln, &plan, err, sizeof err) == 0 && plan.nlevels == 1 && plan.nfirings == 1 && valid(&kiln, &plan), "tiles on one shelf");
    /* Too tall for a 30 cm kiln; too wide for half shelves, but fine on a full shelf. */
    CHECK(parse(with("kiln 46 30\npiece 10 28 Vase\n")) == 0 && ks_pack(&kiln, &plan, err, sizeof err) != 0 && strstr(err, "under the lid"), "%s", err);
    CHECK(parse(with("piece 30 5 Platter\n")) == 0 && ks_pack(&kiln, &plan, err, sizeof err) != 0 && strstr(err, "too wide"), "%s", err);
    CHECK(parse(with("shelves full\npiece 30 5 Platter\n")) == 0 && ks_pack(&kiln, &plan, err, sizeof err) == 0 && valid(&kiln, &plan), "%s", err);
    /* Shelves stack: a tall piece and a short one go on two shelves with posts between. */
    CHECK(parse(with("piece 18 24 Vase\npiece 18 24 Vase\npiece 18 24 Vase\npiece 18 24 Vase\npiece 18 24 Vase\npiece 9 9 Mug\n")) == 0, "%s", err);
    CHECK(ks_pack(&kiln, &plan, err, sizeof err) == 0 && valid(&kiln, &plan) && plan.nlevels >= 3, "levels %d", plan.nlevels);
    /* Bisque pieces may touch, so more fit than in a glaze firing. */
    CHECK(parse(with("firing glaze\npiece 8 5 60 Cup\n")) == 0 && ks_pack(&kiln, &plan, err, sizeof err) == 0, "%s", err);
    int glaze_levels = plan.nlevels;
    CHECK(valid(&kiln, &plan), "glaze valid");
    CHECK(parse(with("firing bisque\npiece 8 5 60 Cup\n")) == 0 && ks_pack(&kiln, &plan, err, sizeof err) == 0 && valid(&kiln, &plan), "%s", err);
    CHECK(plan.nlevels <= glaze_levels, "bisque %d glaze %d", plan.nlevels, glaze_levels);
}

static void test_random(void) {
    srand(9);
    int ok = 0;
    for (int t = 0; t < 120; t++) {
        char text[3000];
        int n = snprintf(text, sizeof text, "kiln %d %d\nshelves %s\nfiring %s\nposts 2.5 5 7.5 10 15\n", 40 + rand() % 40,
                         40 + rand() % 40, rand() % 3 ? "half" : "full", rand() % 2 ? "glaze" : "bisque");
        int kinds = 1 + rand() % 6;
        for (int i = 0; i < kinds; i++)
            n += snprintf(text + n, sizeof text - (size_t)n, "piece %d %d %d\n", 4 + rand() % 14, 2 + rand() % 25, 1 + rand() % 12);
        if (parse(text) != 0) continue;
        if (ks_pack(&kiln, &plan, err, sizeof err) != 0) continue;
        ok++;
        CHECK(valid(&kiln, &plan), "random kiln %d breaks a rule", t);
        double area = 0, R = ks_radius(&kiln);
        for (int i = 0; i < kiln.npieces; i++) area += M_PI * kiln.pieces[i].d * kiln.pieces[i].d / 4;
        CHECK(plan.nlevels >= (int)ceil(area / (M_PI * R * R) - 1e-9), "beats the area bound?");
    }
    CHECK(ok > 80, "only %d random kilns packed", ok);
}

static void test_report(void) {
    parse(with("piece 9 11 3 Mug\n"));
    ks_pack(&kiln, &plan, err, sizeof err);
    static char out[1 << 16];
    ks_report(&kiln, &plan, out, sizeof out);
    CHECK(strstr(out, "KILNSTACK  glaze firing, 46 cm kiln 66 cm tall, half shelves: 3 pieces in 1 firing on 1 shelves") != NULL, "%.120s", out);
    CHECK(strstr(out, "A Mug 9x11") && strstr(out, "top shelf"), "piece list");
    char tiny[64];
    ks_report(&kiln, &plan, tiny, sizeof tiny);
    CHECK(strlen(tiny) < sizeof tiny, "a small buffer truncates safely");
}

int main(void) {
    test_parse();
    test_posts();
    test_known();
    test_random();
    test_report();
    printf("%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
