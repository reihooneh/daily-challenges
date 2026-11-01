/* Command line: pacelane SQUAD.txt   (or - for standard input) */
#include "pacelane.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const char *USAGE =
    "Usage: pacelane SQUAD.txt     (or - for standard input)\n"
    "\n"
    "  title Tuesday masters\n"
    "  pool 25                 set 10 x 100\n"
    "  lanes 5                 max 8          most swimmers in a lane\n"
    "  rest 15                 min-rest 5     seconds of rest wanted, and the least allowed\n"
    "  gap 5                   clock 5        seconds between swimmers; intervals in steps of\n"
    "  lane-1 fastest                         or slowest\n"
    "  swimmer Alex Moreau 1:18               pace per 100\n"
    "\n"
    "Exit codes: 0 lanes printed, 2 bad usage or input.\n";

/* Reads at most MAX_BYTES + 1 bytes, so an oversized or endless input is refused, not loaded. */
static long read_all(int fd, char *buf) {
    size_t got = 0;
    while (got < MAX_BYTES + 1) {
        ssize_t r = read(fd, buf + got, MAX_BYTES + 1 - got);
        if (r < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        if (r == 0) break;
        got += (size_t)r;
    }
    return (long)got;
}

int main(int argc, char **argv) {
    if (argc != 2 || strcmp(argv[1], "--help") == 0 || strcmp(argv[1], "-h") == 0) {
        fputs(USAGE, argc == 2 ? stdout : stderr);
        return argc == 2 ? 0 : 2;
    }
    static char buf[MAX_BYTES + 1];
    static Session session;
    static Split best, equal;
    const char *path = argv[1];
    long len;
    if (strcmp(path, "-") == 0) {
        len = read_all(STDIN_FILENO, buf);
    } else {
        /* No symlinks, and only regular files: /dev/zero, pipes and directories are refused.
         * The path itself is never printed. */
        int fd = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC);
        struct stat st;
        if (fd < 0 || fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) {
            if (fd >= 0) close(fd);
            fputs("pacelane: the squad file could not be read (it must be a regular file)\n", stderr);
            return 2;
        }
        len = read_all(fd, buf);
        close(fd);
    }
    if (len < 0) {
        fputs("pacelane: the squad file could not be read\n", stderr);
        return 2;
    }
    if (len > MAX_BYTES) {
        fputs("pacelane: the file is larger than 32 KB\n", stderr);
        return 2;
    }
    char err[200];
    if (parse_session(buf, (size_t)len, &session, err, sizeof err) != 0) {
        fprintf(stderr, "pacelane: %s\n", err);
        return 2;
    }
    if (split_best(&session, &best) != 0) {
        fputs("pacelane: the squad doesn't fit in the lanes\n", stderr);
        return 2;
    }
    if (split_equal(&session, &equal) != 0) equal.used = 0;
    print_report(&session, &best, &equal);
    return fflush(stdout) == 0 ? 0 : 2;
}
