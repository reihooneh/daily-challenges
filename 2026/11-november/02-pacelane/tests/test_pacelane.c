/* Unit tests. Built with AddressSanitizer and UBSan by `make test`. */
#include "pacelane.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int passed, failed;
#define CHECK(cond, what)                                   \
    do {                                                    \
        if (cond) passed++;                                 \
        else {                                              \
            failed++;                                       \
            printf("FAIL  %s (line %d)\n", what, __LINE__); \
        }                                                   \
    } while (0)

static Session session;
static Split best, equal;
static char err[200];

static int load(const char *text) { return parse_session(text, strlen(text), &session, err, sizeof err); }

static void rejects(const char *text, const char *want) {
    int rc = load(text);
    char what[96];
    snprintf(what, sizeof what, "reject (%s)", want);
    CHECK(rc != 0 && strstr(err, want) != NULL, what);
    CHECK(strstr(err, "SECRET") == NULL && strstr(err, "<script>") == NULL, "error never echoes the input");
}

/* Cost of putting swimmer i in lane lane_of[i], every lane on its own best interval. */
static long long assignment_cost(const Session *s, const int *lane_of, int lanes) {
    long long total = 0;
    for (int l = 0; l < lanes; l++) {
        int order[MAX_SWIMMERS], k = 0, interval = 0;
        for (int i = 0; i < s->n; i++)
            if (lane_of[i] == l) order[k++] = i;
        if (k == 0) continue;
        long long c = lane_cost(s, order, 0, k, &interval);
        if (c < 0) return -1;
        total += c;
    }
    return total;
}

/* Every way of giving each swimmer a lane: the true optimum, with no assumption that lanes
 * hold neighbours in pace. */
static long long brute(const Session *s) {
    int lane_of[MAX_SWIMMERS] = {0};
    long long bestc = -1;
    for (;;) {
        int counts[MAX_LANES] = {0}, ok = 1;
        for (int i = 0; i < s->n; i++)
            if (++counts[lane_of[i]] > s->max_lane) ok = 0;
        if (ok) {
            long long c = assignment_cost(s, lane_of, s->lanes);
            if (c >= 0 && (bestc < 0 || c < bestc)) bestc = c;
        }
        int i = 0;
        while (i < s->n && ++lane_of[i] == s->lanes) lane_of[i++] = 0;
        if (i == s->n) break;
    }
    return bestc;
}

static unsigned rng = 12345;
static int roll(int n) {
    rng = rng * 1103515245u + 12345u;
    return (int)((rng >> 16) % (unsigned)n);
}

int main(void) {
    int t = 0;
    char buf[32];
    /* ---------- times ---------- */
    CHECK(parse_time("1:25", &t) == 0 && t == 850, "1:25");
    CHECK(parse_time("1:25.5", &t) == 0 && t == 855, "1:25.5");
    CHECK(parse_time("85", &t) == 0 && t == 850, "85 seconds");
    CHECK(parse_time("0:59", &t) == 0 && t == 590, "0:59");
    CHECK(parse_time("1:5", &t) != 0 && parse_time("1:60", &t) != 0 && parse_time("", &t) != 0 &&
              parse_time("1:25.", &t) != 0 && parse_time("1.5:20", &t) != 0 && parse_time("-1:20", &t) != 0 &&
              parse_time("99999", &t) != 0 && parse_time("1:25.55", &t) != 0,
          "bad times refused");
    format_time(855, buf, sizeof buf);
    CHECK(strcmp(buf, "1:25.5") == 0, "format with tenths");
    format_time(1500, buf, sizeof buf);
    CHECK(strcmp(buf, "2:30") == 0, "format whole");

    /* ---------- one lane ---------- */
    CHECK(load("set 10 x 100\nrest 15\nmin-rest 5\nclock 5\ngap 5\nlanes 1\nswimmer A 1:20\nswimmer B 1:30\n") == 0, "loads");
    {
        int order[2] = {0, 1}, interval = 0;
        long long c = lane_cost(&session, order, 0, 2, &interval);
        /* mean 85 s + 15 s = 100 s exactly: rests 20 and 10, misses 5 and 5 (50 tenths each). */
        CHECK(interval == 1000 && c == 2 * 50 * 50, "interval sits at mean + rest");
        session.min_rest = 150;
        c = lane_cost(&session, order, 0, 2, &interval);
        CHECK(interval == 1050, "min-rest pushes the interval up for the slowest");
        session.min_rest = 0;
        session.gap = 600; /* two swimmers 60 s apart need at least 120 s */
        c = lane_cost(&session, order, 0, 2, &interval);
        CHECK(interval == 1200, "everyone must push off before the leader goes again");
        (void)c;
    }
    CHECK(load("set 4 x 200\npool 50\nswimmer A 1:20\n") == 0 && repeat_time(&session, 800) == 1600, "200 m at 1:20 pace");

    /* ---------- splitting ---------- */
    CHECK(load("lanes 3\nmax 2\nswimmer A 1:10\nswimmer B 1:12\nswimmer C 1:40\nswimmer D 1:42\nswimmer E 2:20\nswimmer F 2:22\n") ==
              0,
          "loads three pairs");
    CHECK(split_best(&session, &best) == 0 && best.used == 3, "three lanes used");
    CHECK(best.lane[0].count == 2 && best.lane[1].count == 2 && best.lane[2].count == 2, "the natural pairs");
    CHECK(load("lanes 4\nswimmer A 1:30\nswimmer B 1:30\nswimmer C 1:30\n") == 0 && split_best(&session, &best) == 0 &&
              best.used == 1,
          "equal swimmers share one lane");
    CHECK(load("lanes 2\nmax 2\nswimmer A 1:30\nswimmer B 1:30\nswimmer C 1:30\nswimmer D 1:30\nswimmer E 1:30\n") != 0 &&
              strstr(err, "don't fit") != NULL,
          "too many for the lanes");

    /* ---------- against every assignment ---------- */
    {
        int cases = 0, matched = 0;
        for (int round = 0; round < 300; round++) {
            char text[2048];
            int n = 2 + roll(6), lanes = 1 + roll(3), cap = 1 + roll(4);
            if (n > lanes * cap) continue;
            int len = snprintf(text, sizeof text, "lanes %d\nmax %d\nrest %d\nmin-rest %d\ngap %d\nclock %d\n", lanes, cap,
                               5 + roll(20), roll(6), 1 + roll(8), 1 + roll(10));
            for (int i = 0; i < n; i++)
                len += snprintf(text + len, sizeof text - (size_t)len, "swimmer S%d %d:%02d\n", i, 1 + roll(2), roll(60));
            if (load(text) != 0) continue;
            cases++;
            if (split_best(&session, &best) == 0 && best.cost == brute(&session)) matched++;
            else printf("  differs:\n%s\n", text);
        }
        CHECK(cases > 150 && matched == cases, "the split of neighbours is the true optimum on random squads");
    }

    /* ---------- the example ---------- */
    {
        FILE *f = fopen("examples/masters.txt", "rb");
        static char text[MAX_BYTES + 1];
        size_t got = f ? fread(text, 1, MAX_BYTES, f) : 0;
        if (f) fclose(f);
        CHECK(got > 0 && parse_session(text, got, &session, err, sizeof err) == 0, "example loads");
        CHECK(split_best(&session, &best) == 0 && split_equal(&session, &equal) == 0, "example splits");
        CHECK(best.used == 5 && best.cost < equal.cost, "better than equal lanes");
        CHECK(best.lane[0].interval == 950 && best.lane[4].interval == 1550, "send-offs 1:35 to 2:35");
    }

    /* ---------- hostile input ---------- */
    rejects("", "no swimmers");
    rejects("swimmer <script> 1:20\n", "names use letters");
    rejects("swimmer Ann\xE2\x80\xAESECRET 1:20\n", "names use letters"); /* right-to-left override */
    rejects("swimmer Ann\xC0\xAF 1:20\n", "names use letters");           /* overlong UTF-8 */
    rejects("swimmer Ann\x1b[2J 1:20\n", "control character");
    rejects("swimmer Ann 1:20\nswimmer Ann 1:30\n", "same name");
    rejects("swimmer Ann 0:20\n", "0:40 to 10:00");
    rejects("swimmer Ann fast\n", "0:40 to 10:00");
    rejects("swimmer 1:20\n", "names use letters");
    rejects("lanes 40\nswimmer Ann 1:20\n", "1 to 12");
    rejects("set 10 x 110\nswimmer Ann 1:20\n", "whole number of pool lengths");
    rejects("set ten x 100\nswimmer Ann 1:20\n", "write the set once");
    rejects("rest 5\nmin-rest 10\nswimmer Ann 1:20\n", "can't be more");
    rejects("lane-1 middle\nswimmer Ann 1:20\n", "lane-1 fastest");
    rejects("rm -rf SECRET\n", "lines start with");
    rejects("title A\ntitle B\nswimmer Ann 1:20\n", "comes once");
    {
        static char big[MAX_BYTES + 100];
        memset(big, '#', sizeof big - 1);
        big[sizeof big - 1] = '\0';
        rejects(big, "larger than 32 KB");
        big[300] = '\0';
        rejects(big, "is longer than 200");
        CHECK(parse_session(big, sizeof big - 1, &session, err, sizeof err) != 0 && strstr(err, "32 KB"), "size limit");
        static char many[MAX_BYTES];
        int len = 0;
        for (int i = 0; i < 201 && len < (int)sizeof many - 40; i++)
            len += snprintf(many + len, sizeof many - (size_t)len, "swimmer S%d 1:20\n", i);
        CHECK(load("lanes 12\nmax 20\n") != 0, "no swimmers");
        char *withlanes = malloc(sizeof many + 32);
        if (withlanes) {
            int w = snprintf(withlanes, 32, "lanes 12\nmax 20\n");
            memcpy(withlanes + w, many, (size_t)len + 1);
            CHECK(parse_session(withlanes, strlen(withlanes), &session, err, sizeof err) != 0 && strstr(err, "at most 200"),
                  "swimmer limit");
            free(withlanes);
        }
    }
    CHECK(load("\xEF\xBB\xBFtitle Ma\xC3\xB1" "ana squad\r\nswimmer Zo\xC3\xAB O'Neil 1:20\r\nswimmer Jos\xC3\xA9  1:21.5\n") == 0 &&
              session.s[0].chars == 10 && session.s[1].pace == 815,
          "friendly input: BOM, CRLF, accents");

    printf("%d passed, %d failed\n", passed, failed);
    return failed ? 1 : 0;
}
