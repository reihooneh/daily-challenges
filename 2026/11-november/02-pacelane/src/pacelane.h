/* Pacelane: splits a swim squad into lanes so that, on each lane's send-off interval, every
 * swimmer gets as close as possible to the rest the coach wants. */
#ifndef PACELANE_H
#define PACELANE_H

#include <stddef.h>

#define MAX_BYTES 32768
#define MAX_LINE 200
#define MAX_SWIMMERS 200
#define MAX_LANES 12
#define MAX_PER_LANE 20
#define NAME_BYTES 96 /* UTF-8 bytes, at most 40 characters */
#define NAME_CHARS 40
#define TITLE_BYTES 128

/* All times are in tenths of a second, so 1:25.5 is 855. */
typedef struct {
    char name[NAME_BYTES + 1];
    int chars; /* characters shown, for lining up columns */
    int pace;  /* per 100 (m or yd) */
} Swimmer;

typedef struct {
    char title[TITLE_BYTES + 1];
    int pool;       /* length of the pool */
    int repeat;     /* distance of one repeat, a multiple of the pool */
    int reps;       /* how many repeats */
    int lanes;      /* lanes available */
    int max_lane;   /* most swimmers in a lane */
    int gap;        /* between swimmers pushing off */
    int rest;       /* the rest the coach is aiming for */
    int min_rest;   /* nobody should get less than this */
    int step;       /* intervals are multiples of this (pace clocks) */
    int slow_first; /* lane 1 is the slowest instead of the fastest */
    int n;
    Swimmer s[MAX_SWIMMERS];
} Session;

typedef struct {
    int first, count; /* a run of swimmers in pace order, fastest first */
    int interval;     /* send-off time for one repeat */
    long long cost;   /* sum of squared misses from the target rest, tenths squared */
} Lane;

typedef struct {
    int order[MAX_SWIMMERS]; /* swimmer indices, fastest first */
    int used;                /* lanes with swimmers in */
    Lane lane[MAX_LANES];    /* fastest lane first */
    long long cost;
} Split;

/* parse.c: 0 on success; otherwise err holds a message that never repeats the input. */
int parse_session(const char *text, size_t len, Session *out, char *err, size_t errlen);
int parse_time(const char *s, int *tenths); /* "1:25", "85", "1:25.5" */
void format_time(int tenths, char *buf, size_t len);

/* split.c */
int repeat_time(const Session *s, int pace);
/* Best interval and cost for swimmers order[first .. first+count-1]; -1 if no interval works. */
long long lane_cost(const Session *s, const int *order, int first, int count, int *interval);
/* Optimal split into at most s->lanes runs; 0 on success, -1 if the squad can't fit. */
int split_best(const Session *s, Split *out);
/* What most coaches do: equal-sized lanes by pace, on the best interval for each. */
int split_equal(const Session *s, Split *out);

/* report.c */
void print_report(const Session *s, const Split *best, const Split *equal);

#endif
