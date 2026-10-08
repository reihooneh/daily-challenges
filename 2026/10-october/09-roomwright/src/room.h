/* Roomwright: data model and the three stages (parse, analyse, schedule). */
#ifndef ROOMWRIGHT_ROOM_H
#define ROOMWRIGHT_ROOM_H

#include <stddef.h>
#include <stdint.h>

#define MAX_ITEMS 64
#define MAX_PUZZLES 62 /* one display symbol each: A-Z, a-z, 0-9 */
#define MAX_NAME 24
#define MAX_TITLE 60
#define MAX_LINE 200
#define MAX_FILE (64 * 1024)
#define MAX_STATES 200000
#define MAX_PLAYERS 12
#define MAX_MINUTES 120
#define MAX_LIMIT 600

typedef uint64_t set64; /* bit i set = item (or puzzle) i */

typedef struct {
    char name[MAX_NAME + 1];
    int minutes;
    set64 needs;    /* every item the puzzle requires */
    set64 consumes; /* the part of needs that is used up (written with a *) */
    set64 gives;
    int line;
} Puzzle;

typedef struct {
    char title[MAX_TITLE + 1];
    int players;
    int limit;
    char items[MAX_ITEMS][MAX_NAME + 1];
    int n_items;
    Puzzle puzzles[MAX_PUZZLES];
    int n_puzzles;
    set64 start;
    int exit_item;
} Room;

/* Parse a room description. Returns 0, or -1 with a one-line message in err. */
int room_parse(const char *text, size_t len, Room *room, char *err, size_t err_size);

typedef struct {
    int puzzle;                 /* the move that can trap the team */
    int route[MAX_PUZZLES + 1]; /* shortest sequence of moves ending with it */
    int route_len;
    set64 lost;                 /* used-up items that unsolved puzzles still need */
    set64 blocked;              /* the unsolved puzzles that needed them */
} Trap;

typedef struct {
    int n_states;
    int too_big;   /* more than MAX_STATES states: nothing else is valid */
    int escapable; /* some order of play reaches EXIT */
    int always_escapable;
    Trap traps[MAX_PUZZLES];
    int n_traps;
    set64 ever_solved; /* puzzles that can be solved on some route */
    set64 never_needed; /* items obtainable but never required: red herrings */
    int plan[MAX_PUZZLES]; /* least total work route to EXIT */
    int plan_len;
    int plan_minutes;
} Analysis;

/* Explore every order the team could play in. Returns 0, or -1 if memory ran out. */
int room_analyse(const Room *room, Analysis *out);

typedef struct {
    int start[MAX_PUZZLES]; /* indexed by position in the plan */
    int end[MAX_PUZZLES];
    int player[MAX_PUZZLES];
    int makespan;
    int critical_minutes;
    int critical[MAX_PUZZLES]; /* plan positions on the critical path, in order */
    int critical_len;
} Schedule;

/* Estimate how a team of `players` would work through the plan in parallel. */
void room_schedule(const Room *room, const int *plan, int plan_len, int players, Schedule *out);

/* The symbol shown for the puzzle at plan position i. */
char plan_symbol(int i);

/* Print the full report. Returns the number of problems found. */
#include <stdio.h>
int room_report(FILE *out, const Room *room, const Analysis *analysis, int players);

#endif
