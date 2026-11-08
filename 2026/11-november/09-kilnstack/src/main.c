/* kilnstack KILN-FILE   ('-' reads standard input) */
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include "kilnstack.h"

static int read_all(const char *path, char *buf, size_t cap, size_t *len, const char **why) {
    int fd;
    if (strcmp(path, "-") == 0) {
        fd = STDIN_FILENO;
    } else {
        fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
        if (fd < 0) {
            *why = "couldn't open the kiln file (check the name; links aren't followed)";
            return -1;
        }
        struct stat st;
        if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode)) {
            close(fd);
            *why = "only regular files are read (not folders or devices)";
            return -1;
        }
    }
    size_t n = 0;
    for (;;) {
        ssize_t r = read(fd, buf + n, cap - n);
        if (r < 0) {
            if (fd != STDIN_FILENO) close(fd);
            *why = "couldn't read the kiln file";
            return -1;
        }
        if (r == 0) break;
        n += (size_t)r;
        if (n == cap) break;
    }
    if (fd != STDIN_FILENO) close(fd);
    *len = n;
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: kilnstack KILN-FILE   (- for standard input)\n");
        return 2;
    }
    static char text[KS_MAX_BYTES + 1];
    static Kiln kiln;
    static Plan plan;
    static char out[1 << 20];
    size_t len = 0;
    const char *why = NULL;
    char err[160];
    if (read_all(argv[1], text, sizeof text, &len, &why) != 0) {
        fprintf(stderr, "kilnstack: %s\n", why);
        return 2;
    }
    if (ks_parse(text, len, &kiln, err, sizeof err) != 0 || ks_pack(&kiln, &plan, err, sizeof err) != 0) {
        fprintf(stderr, "kilnstack: %s\n", err);
        return 2;
    }
    ks_report(&kiln, &plan, out, sizeof out);
    fputs(out, stdout);
    return 0;
}
