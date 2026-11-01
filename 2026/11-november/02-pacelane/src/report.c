/* The printed lane sheet. */
#include "pacelane.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static double typical_miss(const Session *s, const Split *sp) {
    return sqrt((double)sp->cost / s->n) / 10.0;
}

static void secs(int tenths, char *buf, size_t len) {
    if (tenths % 10) snprintf(buf, len, "%d.%d s", tenths / 10, (tenths < 0 ? -tenths : tenths) % 10);
    else snprintf(buf, len, "%d s", tenths / 10);
}

void print_report(const Session *s, const Split *best, const Split *equal) {
    char a[32], b[32], c[32];
    secs(s->rest, a, sizeof a);
    secs(s->min_rest, b, sizeof b);
    secs(s->step, c, sizeof c);
    printf("PACELANE  %s\n", s->title);
    printf("Set: %d x %d in a %d pool, aiming for %s rest (never under %s), intervals in steps of %s.\n", s->reps, s->repeat,
           s->pool, a, b, c);
    secs(s->gap, a, sizeof a);
    printf("%d swimmers in %d of %d lanes (at most %d a lane, pushing off %s apart).\n\n", s->n, best->used, s->lanes,
           s->max_lane, a);

    int width = 6;
    for (int i = 0; i < s->n; i++)
        if (s->s[i].chars > width) width = s->s[i].chars;

    int worst = -1, worst_lane = 0, worst_miss = 0;
    for (int k = 0; k < best->used; k++) {
        int idx = s->slow_first ? best->used - 1 - k : k;
        const Lane *ln = &best->lane[idx];
        int last = best->order[ln->first + ln->count - 1];
        int done = (s->reps - 1) * ln->interval + (ln->count - 1) * s->gap + repeat_time(s, s->s[last].pace);
        format_time(ln->interval, a, sizeof a);
        format_time(done, b, sizeof b);
        printf("Lane %-2d  on %-7s %d swimmer%s, set done after %s\n", k + 1, a, ln->count, ln->count == 1 ? "" : "s", b);
        for (int i = ln->first; i < ln->first + ln->count; i++) {
            const Swimmer *sw = &s->s[best->order[i]];
            int rest = ln->interval - repeat_time(s, sw->pace);
            int miss = rest - s->rest;
            format_time(sw->pace, a, sizeof a);
            secs(rest, b, sizeof b);
            printf("    %s%*s  %7s /100   rest %s\n", sw->name, width - sw->chars, "", a, b);
            if (worst < 0 || abs(miss) > abs(worst_miss)) worst = best->order[i], worst_lane = k + 1, worst_miss = miss;
        }
        printf("\n");
    }
    if (best->used + 1 == s->lanes) printf("Lane %d is free for other swimmers.\n\n", s->lanes);
    else if (best->used < s->lanes) printf("Lanes %d to %d are free for other swimmers.\n\n", best->used + 1, s->lanes);

    printf("Typical miss from the target rest: %.1f s.", typical_miss(s, best));
    if (equal->used > 0) printf(" Equal-sized lanes by pace would give %.1f s.", typical_miss(s, equal));
    printf("\n");
    if (worst >= 0 && worst_miss != 0) {
        secs(worst_miss < 0 ? -worst_miss : worst_miss, a, sizeof a);
        printf("Biggest miss: %s, %s %s rest than wanted, in lane %d.\n", s->s[worst].name, a, worst_miss < 0 ? "less" : "more",
               worst_lane);
    }
    printf("This is the best split into lanes of pace neighbours (every such split was checked).\n");
}
