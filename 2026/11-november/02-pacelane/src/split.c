/* Choosing the lanes.
 *
 * In one lane everyone leaves on the same send-off interval T (a multiple of the pace clock's
 * step), so a swimmer who takes a seconds per repeat rests T - a. The cost of a lane is the sum
 * of (rest - target)^2, so a lane of mixed speeds is expensive: its fast swimmers wait about
 * while its slow ones barely touch the wall. With the squad sorted by pace, the best split into
 * runs of neighbours is found exactly by dynamic programming over (lanes used, swimmers placed).
 */
#include "pacelane.h"

#include <limits.h>
#include <stdlib.h>
#include <string.h>

#define INF LLONG_MAX

int repeat_time(const Session *s, int pace) {
    return (pace * s->repeat + 50) / 100;
}

static long long squared_misses(const Session *s, const int *order, int first, int count, int t) {
    long long total = 0;
    for (int i = first; i < first + count; i++) {
        long long miss = (long long)(t - repeat_time(s, s->s[order[i]].pace) - s->rest);
        total += miss * miss;
    }
    return total;
}

long long lane_cost(const Session *s, const int *order, int first, int count, int *interval) {
    if (count <= 0 || count > s->max_lane) return -1;
    long long sum = 0;
    int slowest = 0;
    for (int i = first; i < first + count; i++) {
        int a = repeat_time(s, s->s[order[i]].pace);
        sum += a;
        if (a > slowest) slowest = a;
    }
    /* Lowest allowed interval: the slowest still gets min-rest, and everyone has pushed off
     * (one gap apart) before the first swimmer goes again. */
    int low = slowest + s->min_rest;
    if (count * s->gap > low) low = count * s->gap;
    low = (low + s->step - 1) / s->step * s->step;
    /* The cost is a parabola in T with its minimum at mean + rest: try the clock steps on
     * either side of it, never going below the lowest allowed. */
    long long ideal = sum / count + s->rest;
    int below = (int)(ideal / s->step * s->step);
    int candidates[3] = {low, below, below + s->step};
    long long best = -1;
    for (int k = 0; k < 3; k++) {
        int t = candidates[k];
        if (t < low) continue;
        long long c = squared_misses(s, order, first, count, t);
        if (best < 0 || c < best || (c == best && t < *interval)) best = c, *interval = t;
    }
    return best;
}

static void sort_by_pace(const Session *s, int *order) {
    for (int i = 0; i < s->n; i++) order[i] = i;
    for (int i = 1; i < s->n; i++) { /* insertion sort: stable, so ties keep file order */
        int v = order[i], j = i;
        while (j > 0 && s->s[order[j - 1]].pace > s->s[v].pace) {
            order[j] = order[j - 1];
            j--;
        }
        order[j] = v;
    }
}

int split_best(const Session *s, Split *out) {
    static long long f[MAX_LANES + 1][MAX_SWIMMERS + 1];
    static int take[MAX_LANES + 1][MAX_SWIMMERS + 1];
    static long long cost[MAX_SWIMMERS][MAX_PER_LANE + 1];
    static int interval[MAX_SWIMMERS][MAX_PER_LANE + 1];
    int n = s->n, L = s->lanes, cap = s->max_lane;
    memset(out, 0, sizeof *out);
    if (n <= 0 || n > L * cap) return -1;
    sort_by_pace(s, out->order);

    for (int i = 0; i < n; i++)
        for (int k = 1; k <= cap && i + k <= n; k++) cost[i][k] = lane_cost(s, out->order, i, k, &interval[i][k]);

    for (int j = 0; j <= n; j++) f[0][j] = j == 0 ? 0 : INF;
    for (int l = 1; l <= L; l++) {
        for (int j = 0; j <= n; j++) {
            f[l][j] = f[l - 1][j]; /* this lane left empty */
            take[l][j] = 0;
            for (int k = 1; k <= cap && k <= j; k++) {
                if (f[l - 1][j - k] == INF) continue;
                long long c = f[l - 1][j - k] + cost[j - k][k];
                if (c < f[l][j]) f[l][j] = c, take[l][j] = k;
            }
        }
    }
    if (f[L][n] == INF) return -1;
    out->cost = f[L][n];

    /* Walk back to recover the lanes, then list them fastest first. */
    Lane tmp[MAX_LANES];
    int used = 0;
    for (int l = L, j = n; l > 0; l--) {
        int k = take[l][j];
        if (k == 0) continue;
        tmp[used].first = j - k;
        tmp[used].count = k;
        tmp[used].interval = interval[j - k][k];
        tmp[used].cost = cost[j - k][k];
        used++;
        j -= k;
    }
    for (int i = 0; i < used; i++) out->lane[i] = tmp[used - 1 - i];
    out->used = used;
    return 0;
}

int split_equal(const Session *s, Split *out) {
    memset(out, 0, sizeof *out);
    int n = s->n, lanes = s->lanes < n ? s->lanes : n;
    if (n <= 0 || n > s->lanes * s->max_lane) return -1;
    sort_by_pace(s, out->order);
    int first = 0;
    for (int l = 0; l < lanes; l++) {
        int count = n / lanes + (l < n % lanes ? 1 : 0);
        Lane *ln = &out->lane[l];
        ln->first = first;
        ln->count = count;
        ln->cost = lane_cost(s, out->order, first, count, &ln->interval);
        if (ln->cost < 0) return -1;
        out->cost += ln->cost;
        first += count;
    }
    out->used = lanes;
    return 0;
}
