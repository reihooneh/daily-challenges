/* The squad file. Every line has a fixed shape and every number a range; error messages give
 * the line number and what was expected, never the text of the line. */
#include "pacelane.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static void fail(char *err, size_t len, int line, const char *fmt, ...) {
    char msg[160];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(msg, sizeof msg, fmt, ap); /* NOLINT(clang-analyzer-valist.Uninitialized): va_start is just above */
    va_end(ap);
    if (line > 0) snprintf(err, len, "line %d: %s", line, msg);
    else snprintf(err, len, "%s", msg);
}

/* Decodes one UTF-8 character; returns its length or 0 if the bytes aren't valid UTF-8
 * (overlong forms, surrogates and values past U+10FFFF are refused). */
static size_t utf8_next(const unsigned char *p, size_t left, unsigned *cp) {
    if (left == 0) return 0;
    unsigned c = p[0];
    size_t n;
    unsigned min;
    if (c < 0x80) {
        *cp = c;
        return 1;
    } else if ((c & 0xE0) == 0xC0) {
        n = 2, min = 0x80, c &= 0x1F;
    } else if ((c & 0xF0) == 0xE0) {
        n = 3, min = 0x800, c &= 0x0F;
    } else if ((c & 0xF8) == 0xF0) {
        n = 4, min = 0x10000, c &= 0x07;
    } else {
        return 0;
    }
    if (left < n) return 0;
    for (size_t i = 1; i < n; i++) {
        if ((p[i] & 0xC0) != 0x80) return 0;
        c = (c << 6) | (p[i] & 0x3Fu);
    }
    if (c < min || c > 0x10FFFF || (c >= 0xD800 && c <= 0xDFFF)) return 0;
    *cp = c;
    return n;
}

/* Characters that could rewrite the terminal or reorder text: controls, zero-width and
 * direction-changing marks, and the byte-order mark. */
static int hidden(unsigned cp) {
    return cp < 0x20 || (cp >= 0x7F && cp <= 0x9F) || (cp >= 0x200B && cp <= 0x200F) || (cp >= 0x202A && cp <= 0x202E) ||
           (cp >= 0x2060 && cp <= 0x2069) || cp == 0xFEFF || cp == 0xAD;
}

/* A name: letters (any script), digits, spaces and ' . -; returns its character count or -1. */
static int check_name(const char *s, size_t len) {
    const unsigned char *p = (const unsigned char *)s;
    int chars = 0;
    if (len == 0 || len > NAME_BYTES || p[0] == ' ') return -1;
    for (size_t i = 0; i < len;) {
        unsigned cp;
        size_t n = utf8_next(p + i, len - i, &cp);
        if (n == 0 || hidden(cp)) return -1;
        if (cp < 0x80) {
            int ok = (cp >= 'a' && cp <= 'z') || (cp >= 'A' && cp <= 'Z') || (cp >= '0' && cp <= '9') || cp == ' ' ||
                     cp == '\'' || cp == '.' || cp == '-';
            if (!ok) return -1;
        }
        i += n;
        if (++chars > NAME_CHARS) return -1;
    }
    return chars;
}

static int parse_int(const char *s, int lo, int hi, int *out) {
    int v = 0;
    if (!*s || strlen(s) > 4) return -1;
    for (; *s; s++) {
        if (*s < '0' || *s > '9') return -1;
        v = v * 10 + (*s - '0');
    }
    if (v < lo || v > hi) return -1;
    *out = v;
    return 0;
}

int parse_time(const char *s, int *tenths) {
    int min = 0, sec = 0, tenth = 0;
    const char *colon = strchr(s, ':');
    const char *dot = strchr(s, '.');
    char buf[16];
    size_t len = strlen(s);
    if (len == 0 || len >= sizeof buf) return -1;
    memcpy(buf, s, len + 1);
    if (dot) {
        size_t at = (size_t)(dot - s);
        if (at + 2 != len || buf[at + 1] < '0' || buf[at + 1] > '9') return -1;
        tenth = buf[at + 1] - '0';
        buf[at] = '\0';
    }
    if (colon) {
        size_t at = (size_t)(colon - s);
        if (dot && colon > dot) return -1;
        buf[at] = '\0';
        if (strlen(buf + at + 1) != 2 || parse_int(buf, 0, 9, &min) || parse_int(buf + at + 1, 0, 59, &sec)) return -1;
    } else if (parse_int(buf, 0, 599, &sec)) {
        return -1;
    }
    *tenths = (min * 60 + sec) * 10 + tenth;
    return 0;
}

void format_time(int tenths, char *buf, size_t len) {
    int whole = tenths / 10, t = tenths % 10;
    if (t) snprintf(buf, len, "%d:%02d.%d", whole / 60, whole % 60, t);
    else snprintf(buf, len, "%d:%02d", whole / 60, whole % 60);
}

/* Splits a line into at most `max` words; returns the count, or -1 if there are more. */
static int words(char *line, char **w, int max) {
    int n = 0;
    char *save = NULL;
    for (char *p = strtok_r(line, " \t", &save); p; p = strtok_r(NULL, " \t", &save)) {
        if (n == max) return -1;
        w[n++] = p;
    }
    return n;
}

static int setting(Session *s, char **w, int nw, int ln, char *err, size_t errlen) {
    struct {
        const char *key;
        int *field, lo, hi, scale;
        const char *hint;
    } table[] = {
        {"pool", &s->pool, 10, 100, 1, "write it like 'pool 25' (metres or yards)"},
        {"lanes", &s->lanes, 1, MAX_LANES, 1, "lanes must be 1 to 12"},
        {"max", &s->max_lane, 1, MAX_PER_LANE, 1, "'max' (swimmers in a lane) must be 1 to 20"},
        {"gap", &s->gap, 1, 20, 10, "'gap' (seconds between swimmers) must be 1 to 20"},
        {"rest", &s->rest, 0, 120, 10, "'rest' (seconds) must be 0 to 120"},
        {"min-rest", &s->min_rest, 0, 120, 10, "'min-rest' (seconds) must be 0 to 120"},
        {"clock", &s->step, 1, 30, 10, "'clock' (seconds intervals are rounded to) must be 1 to 30"},
    };
    for (size_t i = 0; i < sizeof table / sizeof table[0]; i++) {
        if (strcmp(w[0], table[i].key) != 0) continue;
        int v;
        if (nw != 2 || parse_int(w[1], table[i].lo, table[i].hi, &v)) {
            fail(err, errlen, ln, "%s", table[i].hint);
            return -1;
        }
        *table[i].field = v * table[i].scale;
        return 0;
    }
    return 1; /* not a setting */
}

int parse_session(const char *text, size_t len, Session *out, char *err, size_t errlen) {
    static Session s;
    char line[MAX_LINE + 2];
    int ln = 0, have_set = 0, have_title = 0;
    memset(&s, 0, sizeof s);
    snprintf(s.title, sizeof s.title, "Squad");
    s.pool = 25, s.repeat = 100, s.reps = 10, s.lanes = 4, s.max_lane = 8;
    s.gap = 50, s.rest = 150, s.min_rest = 50, s.step = 50;

    if (len > MAX_BYTES) {
        fail(err, errlen, 0, "the file is larger than 32 KB");
        return -1;
    }
    if (len >= 3 && memcmp(text, "\xEF\xBB\xBF", 3) == 0) text += 3, len -= 3;
    for (size_t at = 0; at < len;) {
        const char *nl = memchr(text + at, '\n', len - at);
        size_t end = nl ? (size_t)(nl - text) : len, n = end - at;
        ln++;
        if (n > MAX_LINE) {
            fail(err, errlen, ln, "is longer than %d characters", MAX_LINE);
            return -1;
        }
        memcpy(line, text + at, n);
        line[n] = '\0';
        at = end + 1;
        if (n && line[n - 1] == '\r') line[--n] = '\0';
        for (size_t i = 0; i < n; i++) {
            unsigned char c = (unsigned char)line[i];
            if (c == '\0' || (c < 0x20 && c != '\t') || c == 0x7F) {
                fail(err, errlen, ln, "contains a control character");
                return -1;
            }
        }
        char *hash = strchr(line, '#');
        if (hash) *hash = '\0';
        char *w[24];
        int nw = words(line, w, 24);
        if (nw < 0) {
            fail(err, errlen, ln, "has too many words");
            return -1;
        }
        if (nw == 0) continue;

        int rc = setting(&s, w, nw, ln, err, errlen);
        if (rc < 0) return -1;
        if (rc == 0) continue;

        if (strcmp(w[0], "title") == 0 || strcmp(w[0], "swimmer") == 0) {
            int is_swimmer = w[0][0] == 's';
            int last = is_swimmer ? nw - 1 : nw; /* a swimmer's last word is the pace */
            char joined[NAME_BYTES + 32] = "";
            size_t used = 0;
            int too_long = 0;
            for (int i = 1; i < last; i++) {
                size_t wl = strlen(w[i]);
                if (used + wl + 2 > NAME_BYTES) {
                    too_long = 1;
                    break;
                }
                if (used) joined[used++] = ' ';
                memcpy(joined + used, w[i], wl + 1);
                used += wl;
            }
            int chars = too_long || last < 2 ? -1 : check_name(joined, used);
            if (chars < 0) {
                fail(err, errlen, ln, "names use letters, digits, spaces and ' . - (up to %d)", NAME_CHARS);
                return -1;
            }
            if (!is_swimmer) {
                if (have_title++) {
                    fail(err, errlen, ln, "the title comes once");
                    return -1;
                }
                snprintf(s.title, sizeof s.title, "%s", joined);
                continue;
            }
            int pace;
            if (parse_time(w[nw - 1], &pace) || pace < 400 || pace > 6000) {
                fail(err, errlen, ln, "a pace per 100 is a time from 0:40 to 10:00, like 1:25 or 1:25.5");
                return -1;
            }
            for (int i = 0; i < s.n; i++) {
                if (strcmp(s.s[i].name, joined) == 0) {
                    fail(err, errlen, ln, "two swimmers have the same name");
                    return -1;
                }
            }
            if (s.n == MAX_SWIMMERS) {
                fail(err, errlen, ln, "at most %d swimmers", MAX_SWIMMERS);
                return -1;
            }
            Swimmer *sw = &s.s[s.n++];
            snprintf(sw->name, sizeof sw->name, "%s", joined);
            sw->chars = chars;
            sw->pace = pace;
        } else if (strcmp(w[0], "set") == 0) {
            if (have_set++ || nw != 4 || strcmp(w[2], "x") != 0 || parse_int(w[1], 1, 100, &s.reps) ||
                parse_int(w[3], 25, 1500, &s.repeat)) {
                fail(err, errlen, ln, "write the set once, like 'set 10 x 100' (1-100 repeats of 25-1500)");
                return -1;
            }
        } else if (strcmp(w[0], "lane-1") == 0) {
            if (nw != 2 || (strcmp(w[1], "fastest") != 0 && strcmp(w[1], "slowest") != 0)) {
                fail(err, errlen, ln, "write 'lane-1 fastest' or 'lane-1 slowest'");
                return -1;
            }
            s.slow_first = w[1][0] == 's';
        } else {
            fail(err, errlen, ln, "lines start with title, pool, set, lanes, max, gap, rest, min-rest, clock, lane-1 or swimmer");
            return -1;
        }
    }
    if (s.n == 0) {
        fail(err, errlen, 0, "the file has no swimmers");
        return -1;
    }
    if (s.repeat % s.pool != 0) {
        fail(err, errlen, 0, "the repeat distance must be a whole number of pool lengths");
        return -1;
    }
    if (s.min_rest > s.rest) {
        fail(err, errlen, 0, "'min-rest' can't be more than 'rest'");
        return -1;
    }
    if (s.n > s.lanes * s.max_lane) {
        fail(err, errlen, 0, "%d swimmers don't fit in %d lanes of %d", s.n, s.lanes, s.max_lane);
        return -1;
    }
    *out = s;
    return 0;
}
