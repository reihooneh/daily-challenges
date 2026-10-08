/* Turns the analysis into a readable report. Every name printed here passed
 * the parser's allow-list, so nothing can smuggle control codes to the terminal. */
#include "room.h"

#include <stdio.h>

#define GANTT_WIDTH 60

static void print_items(FILE *out, const Room *room, set64 items)
{
    int first = 1;
    for (int i = 0; i < room->n_items; i++)
        if (items >> i & 1) {
            fprintf(out, "%s%s", first ? "" : ", ", room->items[i]);
            first = 0;
        }
}

static void print_route(FILE *out, const Room *room, const int *route, int len)
{
    for (int i = 0; i < len; i++)
        fprintf(out, "%s%s", i ? " -> " : "", room->puzzles[route[i]].name);
}

static int count_bits(set64 s)
{
    int n = 0;
    for (; s; s &= s - 1)
        n++;
    return n;
}

static void gantt(FILE *out, const Schedule *sch, int n, int players)
{
    int scale = (sch->makespan + GANTT_WIDTH - 1) / GANTT_WIDTH;
    if (scale < 1)
        scale = 1;
    int columns = (sch->makespan + scale - 1) / scale;
    fprintf(out, "  minute ");
    for (int c = 0; c < columns; c += 10)
        fprintf(out, "%-10d", c * scale);
    fprintf(out, "\n");
    for (int p = 0; p < players; p++) {
        fprintf(out, "  P%-2d    ", p + 1);
        for (int c = 0; c < columns; c++) {
            int minute = c * scale;
            char mark = '.';
            for (int j = 0; j < n; j++)
                if (sch->player[j] == p && sch->start[j] <= minute && minute < sch->end[j])
                    mark = plan_symbol(j);
            fputc(mark, out);
        }
        fputc('\n', out);
    }
    if (scale > 1)
        fprintf(out, "  (each column is %d minutes)\n", scale);
}

int room_report(FILE *out, const Room *room, const Analysis *a, int players)
{
    int problems = 0;
    char problem[2 * MAX_PUZZLES + 4][200];

    fprintf(out, "ROOMWRIGHT  %s\n", room->title);
    fprintf(out, "%d player%s, %d minute limit, %d puzzles, %d items\n", players, players == 1 ? "" : "s", room->limit,
            room->n_puzzles, room->n_items);
    if (a->too_big) {
        fprintf(out, "\nThere are more than %d possible situations to check, so the room was not analysed.\n"
                     "Split it into stages (each stage's EXIT is the next stage's start item) and check each one.\n",
                MAX_STATES);
        return 1;
    }
    fprintf(out, "Checked every order of play: %d possible situation%s.\n\n", a->n_states, a->n_states == 1 ? "" : "s");

    if (!a->escapable)
        fprintf(out, "Can it be escaped?  NO: no order of play reaches EXIT.\n");
    else if (a->n_traps)
        fprintf(out, "Can it be escaped?  yes, but %d move%s can make it impossible.\n", a->n_traps,
                a->n_traps == 1 ? "" : "s");
    else
        fprintf(out, "Can it be escaped?  yes, in every order of play. No traps.\n");
    if (!a->escapable)
        snprintf(problem[problems++], sizeof problem[0], "The room cannot be escaped in any order of play.");

    if (a->n_traps) {
        fprintf(out, "\nTRAPS (moves after which the team can never get out)\n");
        for (int t = 0; t < a->n_traps; t++) {
            const Trap *trap = &a->traps[t];
            fprintf(out, "  ! '%s'", room->puzzles[trap->puzzle].name);
            if (trap->lost) {
                fprintf(out, " uses up ");
                print_items(out, room, trap->lost);
                fprintf(out, ", which ");
                int first = 1;
                for (int q = 0; q < room->n_puzzles; q++)
                    if (trap->blocked >> q & 1) {
                        fprintf(out, "%s'%s'", first ? "" : " and ", room->puzzles[q].name);
                        first = 0;
                    }
                fprintf(out, " still need%s.\n", count_bits(trap->blocked) == 1 ? "s" : "");
            } else {
                fprintf(out, " leads to a dead end.\n");
            }
            fprintf(out, "      shortest way in: ");
            print_route(out, room, trap->route, trap->route_len);
            fprintf(out, "\n");
            snprintf(problem[problems++], sizeof problem[0],
                     "Trap: solving '%s' at the wrong time makes the room unwinnable. Give each lock its own key, "
                     "or stop the key being used up.",
                     room->puzzles[trap->puzzle].name);
        }
    }

    for (int p = 0; p < room->n_puzzles; p++)
        if (!(a->ever_solved >> p & 1))
            snprintf(problem[problems++], sizeof problem[0],
                     "'%s' can never be solved: the team can't hold everything it needs at once (line %d).",
                     room->puzzles[p].name, room->puzzles[p].line);

    if (a->plan_len > 0) {
        Schedule sch;
        room_schedule(room, a->plan, a->plan_len, players, &sch);
        fprintf(out, "\nFASTEST ROUTE  (%d puzzles, %d minutes of work)\n", a->plan_len, a->plan_minutes);
        for (int j = 0; j < a->plan_len; j++)
            fprintf(out, "  %c  %-24s %3d min   P%d, minute %d-%d\n", plan_symbol(j), room->puzzles[a->plan[j]].name,
                    room->puzzles[a->plan[j]].minutes, sch.player[j] + 1, sch.start[j], sch.end[j]);

        fprintf(out, "\nTEAM ESTIMATE\n  critical path: ");
        for (int k = 0; k < sch.critical_len; k++)
            fprintf(out, "%s%s", k ? " -> " : "", room->puzzles[a->plan[sch.critical[k]]].name);
        fprintf(out, "  (%d min: no team can be faster)\n  by team size: ", sch.critical_minutes);
        int enough = players;
        for (int k = 1; k <= players; k++) {
            Schedule trial;
            room_schedule(room, a->plan, a->plan_len, k, &trial);
            fprintf(out, "%s%d -> %d min", k > 1 ? "   " : "", k, trial.makespan);
            if (trial.makespan == sch.makespan && k < enough)
                enough = k;
        }
        int busy = (100 * a->plan_minutes) / (players * sch.makespan);
        fprintf(out, "\n  %d %s in about %d minutes, busy %d%% of the time.\n", players,
                players == 1 ? "player finishes" : "players finish", sch.makespan, busy);
        if (enough < players)
            fprintf(out, "  A team of %d is just as fast, so extra players mostly wait. A parallel thread of\n"
                         "  puzzles would give everyone something to do.\n",
                    enough);
        fprintf(out, "\n");
        gantt(out, &sch, a->plan_len, players);
        if (sch.makespan > room->limit)
            snprintf(problem[problems++], sizeof problem[0],
                     "Even the fastest route takes about %d minutes with %d player%s, over the %d minute limit.",
                     sch.makespan, players, players == 1 ? "" : "s", room->limit);
    }

    if (a->never_needed) {
        fprintf(out, "\nNOTES\n  Red herrings (never needed, fine if deliberate): ");
        print_items(out, room, a->never_needed);
        fprintf(out, "\n");
    }

    if (problems) {
        fprintf(out, "\n%d problem%s:\n", problems, problems == 1 ? "" : "s");
        for (int i = 0; i < problems; i++)
            fprintf(out, "  - %s\n", problem[i]);
    } else {
        fprintf(out, "\nNo problems found.\n");
    }
    return problems;
}
