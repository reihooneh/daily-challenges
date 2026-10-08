#define _POSIX_C_SOURCE 200809L /* for rand_r */
/* Unit tests for the parser, the solver and the scheduler.
 * Built with AddressSanitizer and UndefinedBehaviorSanitizer by `make test`. */
#include "room.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static int failures = 0, checks = 0;

#define CHECK(cond)                                                                                                    \
    do {                                                                                                               \
        checks++;                                                                                                      \
        if (!(cond)) {                                                                                                 \
            failures++;                                                                                                \
            fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond);                                            \
        }                                                                                                              \
    } while (0)

static Room room;
static Analysis analysis;
static char err[200];

static int parse_text(const char *text) { return room_parse(text, strlen(text), &room, err, sizeof err); }

static int find_puzzle(const char *name)
{
    for (int i = 0; i < room.n_puzzles; i++)
        if (strcmp(room.puzzles[i].name, name) == 0)
            return i;
    return -1;
}

static char *read_file(const char *path, size_t *len)
{
    static char buffer[MAX_FILE + 1];
    FILE *f = fopen(path, "rb");
    if (!f)
        return NULL;
    *len = fread(buffer, 1, MAX_FILE, f);
    fclose(f);
    buffer[*len] = '\0';
    return buffer;
}

/* ---------- parsing ---------- */

static void test_example_parses(void)
{
    size_t len = 0;
    char *text = read_file("examples/clockmaker.room", &len);
    CHECK(text != NULL);
    if (!text)
        return;
    CHECK(room_parse(text, len, &room, err, sizeof err) == 0);
    CHECK(strcmp(room.title, "The Clockmaker's Study") == 0);
    CHECK(room.players == 4 && room.limit == 45);
    CHECK(room.n_puzzles == 9 && room.n_items == 11);
    int chest = find_puzzle("chest");
    CHECK(chest >= 0 && room.puzzles[chest].consumes == room.puzzles[chest].needs);
    CHECK(room.puzzles[find_puzzle("bookshelf")].needs == 0);
}

static void expect_error(const char *text, const char *expected, const char *must_not_echo)
{
    int result = parse_text(text);
    CHECK(result == -1);
    if (result != -1)
        return;
    if (!strstr(err, expected)) {
        failures++;
        fprintf(stderr, "FAIL: expected \"%s\" in \"%s\"\n", expected, err);
    }
    checks++;
    if (must_not_echo)
        CHECK(strstr(err, must_not_echo) == NULL);
}

#define DOOR "puzzle door 1 : -> EXIT\n"

static void test_rejected_input(void)
{
    expect_error("dance party\n" DOOR, "line 1: unknown keyword", "dance");
    expect_error("puzzle Drawer 5 : -> key\n" DOOR, "puzzle name is not valid", "Drawer");
    expect_error("puzzle a 0 : -> EXIT\n", "minutes must be", NULL);
    expect_error("puzzle a 121 : -> EXIT\n", "minutes must be", NULL);
    expect_error("puzzle a 5x : -> EXIT\n", "minutes must be", NULL);
    expect_error("puzzle a -3 : -> EXIT\n", "minutes must be", NULL);
    expect_error("puzzle a 99999 : -> EXIT\n", "minutes must be", NULL);
    expect_error("puzzle a 5 -> EXIT\n", "write a puzzle as", NULL);
    expect_error("puzzle a 5 : key\n" DOOR, "write a puzzle as", NULL);
    expect_error("puzzle a 5 : key ->\n" DOOR, "at least one item after ->", NULL);
    expect_error("puzzle a 5 : key -> b -> c\n" DOOR, "exactly one ->", NULL);
    expect_error("puzzle a 5 : key -> gem*\n" DOOR, "only a puzzle's needs", NULL);
    expect_error("puzzle a 5 : EXIT -> gem\n" DOOR, "EXIT can only appear after ->", NULL);
    expect_error("start EXIT\n" DOOR, "EXIT can only appear after ->", NULL);
    expect_error("puzzle a 5 : -> gem\npuzzle a 5 : -> EXIT\n", "already used on line 1", NULL);
    expect_error("puzzle a 5 : key key -> EXIT\n", "listed twice", NULL);
    expect_error("puzzle a 5 : <script> -> EXIT\n", "item 1 is not a valid name", "script");
    expect_error("puzzle a 5 : ../../etc -> EXIT\n", "not a valid name", "etc");
    expect_error("# nothing here\n", "no puzzles", NULL);
    expect_error("puzzle a 5 : -> gem\n", "no puzzle gives EXIT", NULL);
    expect_error("title Caf\xc3\xa9\n" DOOR, "line 1: only plain printable ASCII", NULL);
    expect_error("title a\x1b[2Jb\n" DOOR, "only plain printable ASCII", NULL);
    expect_error("title <b>bold</b>\n" DOOR, "title may only use", "bold");
    expect_error("title \n" DOOR, "the title is empty", NULL);
    expect_error("players 13\n" DOOR, "players must be", NULL);
    expect_error("players 0\n" DOOR, "players must be", NULL);
    expect_error("players 4 4\n" DOOR, "players must be", NULL);
    expect_error("limit 601\n" DOOR, "limit must be", NULL);
    expect_error("start a\nstart b\n" DOOR, "line 2: there can only be one start line", NULL);
    expect_error("puzzle a 5 : abcdefghijklmnopqrstuvwxyz -> EXIT\n", "longer than 24 characters", NULL);

    /* A NUL byte hidden in the middle must not end the check early. */
    const char with_nul[] = "puzzle a 5 : -> EXIT\0puzzle b 5 : -> gem\n";
    CHECK(room_parse(with_nul, sizeof with_nul - 1, &room, err, sizeof err) == -1);
    CHECK(strstr(err, "printable ASCII") != NULL);

    /* Size limits. */
    char line[400];
    memset(line, 'a', sizeof line - 1);
    line[sizeof line - 1] = '\0';
    expect_error(line, "longer than 200", NULL);

    static char big[MAX_FILE + 10];
    memset(big, '\n', sizeof big);
    CHECK(room_parse(big, sizeof big, &room, err, sizeof err) == -1 && strstr(err, "larger than") != NULL);

    static char many[8000];
    size_t used = 0;
    for (int i = 0; i < MAX_PUZZLES + 1; i++)
        used += (size_t)snprintf(many + used, sizeof many - used, "puzzle p%d 1 : -> EXIT\n", i);
    expect_error(many, "too many puzzles", NULL);

    used = 0;
    for (int i = 0; i < 9; i++) {
        used += (size_t)snprintf(many + used, sizeof many - used, "puzzle p%d 1 : ->", i);
        for (int k = 0; k < 8; k++)
            used += (size_t)snprintf(many + used, sizeof many - used, " i%d_%d", i, k);
        used += (size_t)snprintf(many + used, sizeof many - used, "\n");
    }
    snprintf(many + used, sizeof many - used, DOOR);
    expect_error(many, "too many different items", NULL);
}

static void test_accepted_variations(void)
{
    CHECK(parse_text("title  Spaces   Kept\r\nstart a # comment\r\npuzzle\tdoor\t1\t:\ta*\t->\tEXIT\r\n") == 0);
    CHECK(strcmp(room.title, "Spaces   Kept") == 0);
    CHECK(room.n_puzzles == 1 && room.puzzles[0].consumes == room.puzzles[0].needs);
    CHECK(parse_text(DOOR) == 0 && room.players == 4 && room.limit == 60);
}

/* ---------- the solver ---------- */

static void analyse_text(const char *text)
{
    CHECK(parse_text(text) == 0);
    CHECK(room_analyse(&room, &analysis) == 0);
}

static void test_example_trap(void)
{
    size_t len = 0;
    char *text = read_file("examples/clockmaker.room", &len);
    if (!text)
        return;
    CHECK(room_parse(text, len, &room, err, sizeof err) == 0);
    CHECK(room_analyse(&room, &analysis) == 0);
    CHECK(analysis.escapable && !analysis.always_escapable);
    CHECK(analysis.n_traps == 1);
    const Trap *t = &analysis.traps[0];
    CHECK(t->puzzle == find_puzzle("cabinet"));
    CHECK(t->route_len == 2 && t->route[0] == find_puzzle("drawer") && t->route[1] == find_puzzle("cabinet"));
    CHECK(t->blocked == (set64)1 << find_puzzle("chest"));
    CHECK(analysis.plan_len == 8 && analysis.plan_minutes == 39);
    for (int i = 0; i < analysis.plan_len; i++)
        CHECK(analysis.plan[i] != find_puzzle("cabinet"));
    CHECK(analysis.never_needed != 0);
}

static void test_simple_rooms(void)
{
    analyse_text("start a\npuzzle one 3 : a -> b\npuzzle two 4 : b -> EXIT\n");
    CHECK(analysis.always_escapable && analysis.n_states == 3 && analysis.plan_minutes == 7);

    analyse_text("puzzle door 2 : key -> EXIT\npuzzle box 2 : -> gem\n");
    CHECK(!analysis.escapable && analysis.plan_len == 0);
    CHECK(!(analysis.ever_solved >> find_puzzle("door") & 1));

    /* Two locks, one key, both needed: impossible from the start, not a trap. */
    analyse_text("start key\npuzzle a 1 : key* -> x\npuzzle b 1 : key* -> y\npuzzle door 1 : x y -> EXIT\n");
    CHECK(!analysis.escapable && analysis.n_traps == 0);

    /* Looking at an item without using it up is always safe. */
    analyse_text("start key\npuzzle a 1 : key -> x\npuzzle b 1 : key -> y\npuzzle door 1 : x y -> EXIT\n");
    CHECK(analysis.always_escapable);

    /* The least-work route avoids the long way round. */
    analyse_text("puzzle slow 30 : -> code\npuzzle quick 2 : -> code2\npuzzle door 1 : code2 -> EXIT\n"
                 "puzzle back 1 : code -> EXIT\n");
    CHECK(analysis.plan_minutes == 3 && analysis.plan_len == 2);
}

/* A plain recursive search, slow but obviously right, to cross-check the solver. */
static int naive_can_escape(set64 solved, set64 inv)
{
    if (inv >> room.exit_item & 1)
        return 1;
    for (int p = 0; p < room.n_puzzles; p++) {
        const Puzzle *z = &room.puzzles[p];
        if (!(solved >> p & 1) && (inv & z->needs) == z->needs &&
            naive_can_escape(solved | (set64)1 << p, (inv & ~z->consumes) | z->gives))
            return 1;
    }
    return 0;
}

static void random_room(unsigned *seed, int allow_stars)
{
    char text[4000];
    size_t used = 0;
    int puzzles = 3 + (int)(rand_r(seed) % 6);
    used += (size_t)snprintf(text + used, sizeof text - used, "start i0 i1\n");
    for (int p = 0; p < puzzles; p++) {
        used += (size_t)snprintf(text + used, sizeof text - used, "puzzle p%d %d :", p, 1 + (int)(rand_r(seed) % 9));
        int needs = (int)(rand_r(seed) % 3);
        set64 seen = 0;
        for (int k = 0; k < needs; k++) {
            int item = (int)(rand_r(seed) % 6);
            if (seen >> item & 1)
                continue;
            seen |= (set64)1 << item;
            int star = allow_stars && rand_r(seed) % 2;
            used += (size_t)snprintf(text + used, sizeof text - used, " i%d%s", item, star ? "*" : "");
        }
        int give = p == puzzles - 1 ? -1 : (int)(rand_r(seed) % 6);
        if (give < 0 || seen >> give & 1)
            used += (size_t)snprintf(text + used, sizeof text - used, " -> EXIT\n");
        else
            used += (size_t)snprintf(text + used, sizeof text - used, " -> i%d\n", give);
    }
    CHECK(parse_text(text) == 0);
}

static void test_against_naive_search(void)
{
    unsigned seed = 2026;
    int escapable = 0, trapped = 0;
    for (int trial = 0; trial < 400; trial++) {
        random_room(&seed, 1);
        CHECK(room_analyse(&room, &analysis) == 0);
        CHECK(analysis.escapable == naive_can_escape(0, room.start));
        escapable += analysis.escapable;
        trapped += analysis.n_traps > 0;
        /* Every reported trap really does trap: replaying its route leaves no way out. */
        for (int t = 0; t < analysis.n_traps; t++) {
            set64 solved = 0, inv = room.start;
            for (int k = 0; k < analysis.traps[t].route_len; k++) {
                const Puzzle *z = &room.puzzles[analysis.traps[t].route[k]];
                CHECK((inv & z->needs) == z->needs);
                solved |= (set64)1 << analysis.traps[t].route[k];
                inv = (inv & ~z->consumes) | z->gives;
            }
            CHECK(!naive_can_escape(solved, inv));
        }
    }
    CHECK(escapable > 50 && trapped > 5); /* the random rooms really exercise both cases */
}

static void test_no_used_up_items_means_no_traps(void)
{
    /* Without "*", the team only ever gains items, so a move can't hurt. */
    unsigned seed = 7;
    for (int trial = 0; trial < 300; trial++) {
        random_room(&seed, 0);
        CHECK(room_analyse(&room, &analysis) == 0);
        CHECK(analysis.n_traps == 0);
    }
}

static void test_state_explosion_is_refused_quickly(void)
{
    static char text[6000];
    size_t used = 0;
    for (int i = 0; i < 30; i++)
        used += (size_t)snprintf(text + used, sizeof text - used, "puzzle p%d 1 : -> g%d\n", i, i);
    used += (size_t)snprintf(text + used, sizeof text - used, "puzzle door 1 :");
    for (int i = 0; i < 30; i++)
        used += (size_t)snprintf(text + used, sizeof text - used, " g%d", i);
    snprintf(text + used, sizeof text - used, " -> EXIT\n");
    clock_t started = clock();
    analyse_text(text);
    CHECK(analysis.too_big && analysis.n_states == MAX_STATES);
    CHECK((double)(clock() - started) / CLOCKS_PER_SEC < 10.0);
}

/* ---------- the scheduler ---------- */

static void test_schedule(void)
{
    Schedule s;
    analyse_text("puzzle a 5 : -> x\npuzzle b 5 : -> y\npuzzle c 5 : -> z\npuzzle d 5 : -> w\n"
                 "puzzle door 2 : x y z w -> EXIT\n");
    room_schedule(&room, analysis.plan, analysis.plan_len, 4, &s);
    CHECK(s.makespan == 7 && s.critical_minutes == 7);
    room_schedule(&room, analysis.plan, analysis.plan_len, 2, &s);
    CHECK(s.makespan == 12);
    room_schedule(&room, analysis.plan, analysis.plan_len, 1, &s);
    CHECK(s.makespan == 22);

    analyse_text("puzzle a 3 : -> x\npuzzle b 4 : x -> y\npuzzle door 2 : y -> EXIT\n");
    room_schedule(&room, analysis.plan, analysis.plan_len, 6, &s);
    CHECK(s.makespan == 9 && s.critical_minutes == 9 && s.critical_len == 3);

    /* Someone only reading the key must finish before another player uses it up. */
    analyse_text("start key\npuzzle read 6 : key -> clue\npuzzle open 1 : key* -> box\n"
                 "puzzle door 1 : clue box -> EXIT\n");
    room_schedule(&room, analysis.plan, analysis.plan_len, 3, &s);
    int read = -1, open = -1;
    for (int j = 0; j < analysis.plan_len; j++) {
        if (analysis.plan[j] == find_puzzle("read"))
            read = j;
        if (analysis.plan[j] == find_puzzle("open"))
            open = j;
    }
    CHECK(read >= 0 && open >= 0 && s.start[open] >= s.end[read]);

    /* General bounds on random rooms: never faster than the critical path or
     * than the work divided by the players, never slower than one person. */
    unsigned seed = 99;
    for (int trial = 0; trial < 300; trial++) {
        random_room(&seed, 1);
        CHECK(room_analyse(&room, &analysis) == 0);
        if (!analysis.plan_len)
            continue;
        int players = 1 + (int)(rand_r(&seed) % MAX_PLAYERS);
        room_schedule(&room, analysis.plan, analysis.plan_len, players, &s);
        CHECK(s.makespan >= s.critical_minutes);
        CHECK(s.makespan * players >= analysis.plan_minutes);
        CHECK(s.makespan <= analysis.plan_minutes);
        for (int a = 0; a < analysis.plan_len; a++) /* no player does two things at once */
            for (int b = a + 1; b < analysis.plan_len; b++)
                if (s.player[a] == s.player[b])
                    CHECK(s.end[a] <= s.start[b] || s.end[b] <= s.start[a]);
    }
}

int main(void)
{
    test_example_parses();
    test_rejected_input();
    test_accepted_variations();
    test_example_trap();
    test_simple_rooms();
    test_against_naive_search();
    test_no_used_up_items_means_no_traps();
    test_state_explosion_is_refused_quickly();
    test_schedule();
    printf("%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
