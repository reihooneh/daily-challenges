/* roomwright: check an escape room design for traps, dead puzzles and timing.
 *
 *   roomwright [--players N] FILE      (FILE may be - for standard input)
 *
 * Exit codes: 0 no problems, 1 problems found, 2 the input could not be used.
 */
#include "room.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int usage_error(const char *message)
{
    fprintf(stderr, "roomwright: %s\n", message);
    fprintf(stderr, "usage: roomwright [--players N] FILE   (use - to read standard input)\n");
    return 2;
}

/* Reads at most MAX_FILE + 1 bytes, so an endless stream can't fill memory. */
static long read_limited(FILE *in, char *buffer)
{
    size_t total = 0;
    while (total < MAX_FILE + 1) {
        size_t got = fread(buffer + total, 1, MAX_FILE + 1 - total, in);
        if (got == 0)
            break;
        total += got;
    }
    if (ferror(in))
        return -1;
    return (long)total;
}

int main(int argc, char **argv)
{
    const char *path = NULL;
    int players = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--players") == 0) {
            if (i + 1 >= argc)
                return usage_error("--players needs a number");
            const char *n = argv[++i];
            size_t len = strlen(n);
            players = 0;
            for (size_t k = 0; k < len && len <= 2; k++)
                players = (n[k] >= '0' && n[k] <= '9') ? players * 10 + (n[k] - '0') : -1000;
            if (len == 0 || len > 2 || players < 1 || players > MAX_PLAYERS)
                return usage_error("--players must be a whole number from 1 to 12");
        } else if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            printf("usage: roomwright [--players N] FILE   (use - to read standard input)\n");
            return 0;
        } else if (argv[i][0] == '-' && argv[i][1] != '\0') {
            return usage_error("unknown option");
        } else if (path) {
            return usage_error("give exactly one room file");
        } else {
            path = argv[i];
        }
    }
    if (!path)
        return usage_error("give a room file");

    static char buffer[MAX_FILE + 1];
    FILE *in = strcmp(path, "-") == 0 ? stdin : fopen(path, "rb");
    if (!in)
        return usage_error("the room file could not be opened");
    long len = read_limited(in, buffer);
    if (in != stdin)
        fclose(in);
    if (len < 0)
        return usage_error("the room file could not be read");
    if (len > MAX_FILE)
        return usage_error("the room file is larger than 64 KB");

    static Room room;
    char err[200];
    if (room_parse(buffer, (size_t)len, &room, err, sizeof err) != 0) {
        fprintf(stderr, "roomwright: %s\n", err);
        return 2;
    }
    if (players == 0)
        players = room.players;

    static Analysis analysis;
    if (room_analyse(&room, &analysis) != 0) {
        fprintf(stderr, "roomwright: not enough memory to analyse the room\n");
        return 2;
    }
    int problems = room_report(stdout, &room, &analysis, players);
    if (analysis.too_big)
        return 2;
    return problems ? 1 : 0;
}
