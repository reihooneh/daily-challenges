/*
 * Estimates how a team works through a route in parallel.
 *
 * First the route becomes a dependency graph: a puzzle waits for whichever
 * earlier puzzle provided each item it needs, and a puzzle that uses an item
 * up waits for every earlier puzzle that only needed to look at it.
 *
 * Then a list scheduler assigns puzzles to players: whenever a puzzle could
 * start, the one that can start soonest goes first, and ties go to the one
 * with the most work still waiting behind it (the critical-path rule).
 */
#include "room.h"

#include <string.h>

char plan_symbol(int i)
{
    static const char symbols[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
    return (i >= 0 && i < (int)sizeof symbols - 1) ? symbols[i] : '?';
}

static void dependencies(const Room *room, const int *plan, int n, set64 *deps)
{
    for (int j = 0; j < n; j++) {
        const Puzzle *pj = &room->puzzles[plan[j]];
        deps[j] = 0;
        for (int item = 0; item < room->n_items; item++) {
            set64 bit = (set64)1 << item;
            if (!(pj->needs & bit))
                continue;
            int provider = -1;
            for (int i = j - 1; i >= 0 && provider < 0; i--)
                if (room->puzzles[plan[i]].gives & bit)
                    provider = i;
            if (provider >= 0)
                deps[j] |= (set64)1 << provider;
            if (pj->consumes & bit) /* wait for everyone who still needed to look at it */
                for (int i = provider + 1; i < j; i++)
                    if (room->puzzles[plan[i]].needs & bit)
                        deps[j] |= (set64)1 << i;
        }
    }
}

void room_schedule(const Room *room, const int *plan, int n, int players, Schedule *out)
{
    memset(out, 0, sizeof *out);
    if (n <= 0)
        return;
    if (players < 1)
        players = 1;
    if (players > MAX_PLAYERS)
        players = MAX_PLAYERS;

    set64 deps[MAX_PUZZLES];
    dependencies(room, plan, n, deps);

    /* Critical path: the longest chain of dependent puzzles. */
    int finish[MAX_PUZZLES], before[MAX_PUZZLES];
    int last = 0;
    for (int j = 0; j < n; j++) {
        finish[j] = 0;
        before[j] = -1;
        for (int i = 0; i < j; i++)
            if ((deps[j] >> i & 1) && finish[i] > finish[j]) {
                finish[j] = finish[i];
                before[j] = i;
            }
        finish[j] += room->puzzles[plan[j]].minutes;
        if (finish[j] > finish[last])
            last = j;
    }
    out->critical_minutes = finish[last];
    int chain[MAX_PUZZLES], len = 0;
    for (int j = last; j >= 0; j = before[j])
        chain[len++] = j;
    for (int k = 0; k < len; k++)
        out->critical[k] = chain[len - 1 - k];
    out->critical_len = len;

    /* Work remaining behind each puzzle, used to break ties. */
    int tail[MAX_PUZZLES];
    for (int j = n - 1; j >= 0; j--) {
        tail[j] = 0;
        for (int k = j + 1; k < n; k++)
            if ((deps[k] >> j & 1) && tail[k] > tail[j])
                tail[j] = tail[k];
        tail[j] += room->puzzles[plan[j]].minutes;
    }

    int free_at[MAX_PLAYERS] = {0};
    set64 done = 0;
    for (int round = 0; round < n; round++) {
        int pick = -1, pick_start = 0, pick_player = 0;
        for (int j = 0; j < n; j++) {
            if ((done >> j & 1) || (deps[j] & ~done))
                continue;
            int ready = 0;
            for (int i = 0; i < j; i++)
                if ((deps[j] >> i & 1) && out->end[i] > ready)
                    ready = out->end[i];
            int player = 0;
            for (int q = 1; q < players; q++)
                if (free_at[q] < free_at[player])
                    player = q;
            int start = ready > free_at[player] ? ready : free_at[player];
            if (pick < 0 || start < pick_start || (start == pick_start && tail[j] > tail[pick])) {
                pick = j;
                pick_start = start;
                pick_player = player;
            }
        }
        /* deps only point backwards, so something is always ready */
        out->start[pick] = pick_start;
        out->end[pick] = pick_start + room->puzzles[plan[pick]].minutes;
        out->player[pick] = pick_player;
        free_at[pick_player] = out->end[pick];
        done |= (set64)1 << pick;
        if (out->end[pick] > out->makespan)
            out->makespan = out->end[pick];
    }
}
