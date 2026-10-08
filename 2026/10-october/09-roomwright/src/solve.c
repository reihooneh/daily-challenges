/*
 * Explores every order in which a team could solve the puzzles.
 *
 * A state is (which puzzles are solved, which items the team holds), two
 * 64-bit sets. Solving a puzzle always adds one to the solved count, so the
 * states form layers and breadth-first search visits them in that order.
 * That makes three things easy:
 *
 *   1. walking the states backwards answers "can the team still win from
 *      here?" for every state, because successors are always further on;
 *   2. the first losing state found is reached by the shortest route;
 *   3. a single forward pass finds the route with the least total work.
 */
#include "room.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#define TABLE_BITS 19 /* 524,288 slots: always under half full */
#define TABLE_SIZE (1u << TABLE_BITS)

typedef struct {
    set64 solved, inv;
} State;

typedef struct {
    State *states;
    int *parent;       /* BFS parent: gives the shortest route to each state */
    signed char *move; /* puzzle solved to arrive here */
    int *table;        /* hash table of state index + 1 */
    int count;
} Graph;

static uint64_t mix(uint64_t x)
{
    /* splitmix64 finaliser: spreads the bits so similar states don't collide */
    x ^= x >> 30;
    x *= 0xbf58476d1ce4e5b9ULL;
    x ^= x >> 27;
    x *= 0x94d049bb133111ebULL;
    x ^= x >> 31;
    return x;
}

static unsigned slot_of(State s) { return (unsigned)(mix(s.solved ^ mix(s.inv)) & (TABLE_SIZE - 1)); }

static int lookup(const Graph *g, State s)
{
    for (unsigned slot = slot_of(s);; slot = (slot + 1) & (TABLE_SIZE - 1)) {
        int entry = g->table[slot];
        if (entry == 0)
            return -1;
        const State *t = &g->states[entry - 1];
        if (t->solved == s.solved && t->inv == s.inv)
            return entry - 1;
    }
}

/* Returns the index of s, adding it if new; -2 if the state limit is reached. */
static int insert(Graph *g, State s, int parent, int move, int *added)
{
    unsigned slot = slot_of(s);
    for (;; slot = (slot + 1) & (TABLE_SIZE - 1)) {
        int entry = g->table[slot];
        if (entry == 0)
            break;
        const State *t = &g->states[entry - 1];
        if (t->solved == s.solved && t->inv == s.inv) {
            *added = 0;
            return entry - 1;
        }
    }
    if (g->count >= MAX_STATES)
        return -2;
    int index = g->count++;
    g->states[index] = s;
    g->parent[index] = parent;
    g->move[index] = (signed char)move;
    g->table[slot] = index + 1;
    *added = 1;
    return index;
}

static int can_solve(const Puzzle *p, int index, State s)
{
    return !(s.solved >> index & 1) && (s.inv & p->needs) == p->needs;
}

static State after(const Puzzle *p, int index, State s)
{
    State next = {s.solved | (set64)1 << index, (s.inv & ~p->consumes) | p->gives};
    return next;
}

static int route_to(const Graph *g, int state, int *route)
{
    int len = 0, reversed[MAX_PUZZLES];
    for (int s = state; g->parent[s] >= 0; s = g->parent[s])
        reversed[len++] = g->move[s];
    for (int i = 0; i < len; i++)
        route[i] = reversed[len - 1 - i];
    return len;
}

int room_analyse(const Room *room, Analysis *out)
{
    memset(out, 0, sizeof *out);
    Graph g = {0};
    g.states = malloc(sizeof *g.states * MAX_STATES);
    g.parent = malloc(sizeof *g.parent * MAX_STATES);
    g.move = malloc(sizeof *g.move * MAX_STATES);
    g.table = calloc(TABLE_SIZE, sizeof *g.table);
    char *wins = calloc(MAX_STATES, 1);
    int *best = malloc(sizeof *best * MAX_STATES);
    int *best_parent = malloc(sizeof *best_parent * MAX_STATES);
    signed char *best_move = malloc(sizeof *best_move * MAX_STATES);
    int status = -1;
    if (!g.states || !g.parent || !g.move || !g.table || !wins || !best || !best_parent || !best_move)
        goto done;
    status = 0;

    const set64 exit_bit = (set64)1 << room->exit_item;
    int added;
    State first = {0, room->start};
    insert(&g, first, -1, -1, &added);

    /* 1. Breadth-first search over every reachable state. */
    for (int i = 0; i < g.count; i++) {
        State s = g.states[i];
        if (s.inv & exit_bit)
            continue; /* the team is out: nothing further matters */
        for (int p = 0; p < room->n_puzzles; p++) {
            if (!can_solve(&room->puzzles[p], p, s))
                continue;
            out->ever_solved |= (set64)1 << p;
            if (insert(&g, after(&room->puzzles[p], p, s), i, p, &added) == -2) {
                out->too_big = 1;
                out->n_states = g.count;
                goto done;
            }
        }
    }
    out->n_states = g.count;

    /* 2. Backwards: a state wins if it holds EXIT or any move leads to a win. */
    for (int i = g.count - 1; i >= 0; i--) {
        State s = g.states[i];
        if (s.inv & exit_bit) {
            wins[i] = 1;
            continue;
        }
        for (int p = 0; p < room->n_puzzles && !wins[i]; p++)
            if (can_solve(&room->puzzles[p], p, s))
                wins[i] = wins[lookup(&g, after(&room->puzzles[p], p, s))];
    }
    out->escapable = wins[0];

    /* 3. Traps: a move from a winnable state into an unwinnable one. BFS order
     *    means the first time each trap is seen, its route is the shortest. */
    set64 trap_seen = 0;
    for (int i = 0; i < g.count; i++) {
        State s = g.states[i];
        if (!wins[i] || (s.inv & exit_bit))
            continue;
        for (int p = 0; p < room->n_puzzles; p++) {
            if (!can_solve(&room->puzzles[p], p, s) || (trap_seen >> p & 1))
                continue;
            State next = after(&room->puzzles[p], p, s);
            if (wins[lookup(&g, next)])
                continue;
            trap_seen |= (set64)1 << p;
            Trap *t = &out->traps[out->n_traps++];
            t->puzzle = p;
            t->route_len = route_to(&g, i, t->route);
            t->route[t->route_len++] = p;
            set64 still_needed = 0;
            for (int q = 0; q < room->n_puzzles; q++)
                if (!(next.solved >> q & 1))
                    still_needed |= room->puzzles[q].needs;
            t->lost = room->puzzles[p].consumes & still_needed & ~next.inv;
            for (int q = 0; q < room->n_puzzles; q++)
                if (!(next.solved >> q & 1) && (room->puzzles[q].needs & t->lost))
                    t->blocked |= (set64)1 << q;
        }
    }
    out->always_escapable = out->escapable && out->n_traps == 0;

    /* 4. The route with the least total work: the layers are in topological
     *    order, so one forward pass of relaxation is enough. */
    for (int i = 0; i < g.count; i++)
        best[i] = INT_MAX;
    best[0] = 0;
    best_parent[0] = -1;
    int goal = -1;
    for (int i = 0; i < g.count; i++) {
        State s = g.states[i];
        if (best[i] == INT_MAX)
            continue;
        if (s.inv & exit_bit) {
            if (goal < 0 || best[i] < best[goal])
                goal = i;
            continue;
        }
        for (int p = 0; p < room->n_puzzles; p++) {
            if (!can_solve(&room->puzzles[p], p, s))
                continue;
            int j = lookup(&g, after(&room->puzzles[p], p, s));
            if (best[i] + room->puzzles[p].minutes < best[j]) {
                best[j] = best[i] + room->puzzles[p].minutes;
                best_parent[j] = i;
                best_move[j] = (signed char)p;
            }
        }
    }
    if (goal >= 0) {
        int reversed[MAX_PUZZLES], len = 0;
        for (int s = goal; best_parent[s] >= 0; s = best_parent[s])
            reversed[len++] = best_move[s];
        for (int k = 0; k < len; k++)
            out->plan[k] = reversed[len - 1 - k];
        out->plan_len = len;
        out->plan_minutes = best[goal];
    }

    /* 5. Red herrings: items you can get that nothing ever asks for. */
    set64 obtainable = room->start, required = 0;
    for (int p = 0; p < room->n_puzzles; p++) {
        obtainable |= room->puzzles[p].gives;
        required |= room->puzzles[p].needs;
    }
    out->never_needed = obtainable & ~required & ~exit_bit;

done:
    free(g.states);
    free(g.parent);
    free(g.move);
    free(g.table);
    free(wins);
    free(best);
    free(best_parent);
    free(best_move);
    return status;
}
