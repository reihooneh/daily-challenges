/*
 * Reads a room description. The format is line-based:
 *
 *   title  The Clockmaker's Study
 *   players 4
 *   limit  60
 *   start  torn_note lamp
 *   puzzle drawer 5 : torn_note -> brass_key
 *   puzzle chest  4 : brass_key* -> gear       (* = used up)
 *   puzzle door   2 : code -> EXIT
 *
 * Everything is checked against an allow-list and a size limit, and an
 * error message names the line and the problem but never repeats the text.
 */
#include "room.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#define MAX_TOKENS 80

#if defined(__GNUC__) || defined(__clang__)
#define PRINTF_LIKE(f, a) __attribute__((format(printf, f, a)))
#else
#define PRINTF_LIKE(f, a)
#endif

/* Formats are always literals in this file; the attribute lets the compiler check every call. */
static int fail(char *err, size_t size, int line, const char *fmt, ...) PRINTF_LIKE(4, 5);

static int fail(char *err, size_t size, int line, const char *fmt, ...)
{
    char message[160];
    va_list args;
    va_start(args, fmt);
    vsnprintf(message, sizeof message, fmt, args);
    va_end(args);
    if (line > 0)
        snprintf(err, size, "line %d: %s", line, message);
    else
        snprintf(err, size, "%s", message);
    return -1;
}

static int is_lower(char c) { return c >= 'a' && c <= 'z'; }
static int is_digit(char c) { return c >= '0' && c <= '9'; }

/* [a-z][a-z0-9_]{0,23}, or the special item EXIT. */
static int valid_name(const char *s, size_t len)
{
    if (len == 4 && memcmp(s, "EXIT", 4) == 0)
        return 1;
    if (len == 0 || len > MAX_NAME || !is_lower(s[0]))
        return 0;
    for (size_t i = 1; i < len; i++)
        if (!is_lower(s[i]) && !is_digit(s[i]) && s[i] != '_')
            return 0;
    return 1;
}

/* Plain digits only, at most 4 of them, then a range check. */
static int parse_number(const char *s, int lo, int hi, int *out)
{
    size_t len = strlen(s);
    if (len == 0 || len > 4)
        return 0;
    int value = 0;
    for (size_t i = 0; i < len; i++) {
        if (!is_digit(s[i]))
            return 0;
        value = value * 10 + (s[i] - '0');
    }
    if (value < lo || value > hi)
        return 0;
    *out = value;
    return 1;
}

static int find_item(const Room *room, const char *name)
{
    for (int i = 0; i < room->n_items; i++)
        if (strcmp(room->items[i], name) == 0)
            return i;
    return -1;
}

static int item_index(Room *room, const char *name)
{
    int found = find_item(room, name);
    size_t len = strlen(name);
    if (found >= 0 || room->n_items >= MAX_ITEMS || len > MAX_NAME)
        return found;
    memcpy(room->items[room->n_items], name, len + 1);
    if (strcmp(name, "EXIT") == 0)
        room->exit_item = room->n_items;
    return room->n_items++;
}

/* Turn a list of item tokens into a set. `allow_star` lets "key*" mean "used up". */
static int read_items(Room *room, char **tokens, int count, int line, int allow_star, int allow_exit, set64 *items,
                      set64 *used_up, char *err, size_t size)
{
    *items = 0;
    if (used_up)
        *used_up = 0;
    for (int t = 0; t < count; t++) {
        char name[MAX_NAME + 2];
        size_t len = strlen(tokens[t]);
        int star = 0;
        if (len > MAX_NAME + 1)
            return fail(err, size, line, "item %d has a name longer than %d characters", t + 1, MAX_NAME);
        memcpy(name, tokens[t], len + 1);
        if (len > 0 && name[len - 1] == '*') {
            if (!allow_star)
                return fail(err, size, line, "only a puzzle's needs can be marked as used up (*)");
            star = 1;
            name[--len] = '\0';
        }
        if (!valid_name(name, len))
            return fail(err, size, line, "item %d is not a valid name (use a-z, 0-9 and _, starting with a letter)", t + 1);
        if (strcmp(name, "EXIT") == 0 && !allow_exit)
            return fail(err, size, line, "EXIT can only appear after ->");
        int index = item_index(room, name);
        if (index < 0)
            return fail(err, size, line, "too many different items (the limit is %d)", MAX_ITEMS);
        set64 bit = (set64)1 << index;
        if (*items & bit)
            return fail(err, size, line, "item %d is listed twice", t + 1);
        *items |= bit;
        if (star)
            *used_up |= bit;
    }
    return 0;
}

static int parse_title(Room *room, const char *text, int line, char *err, size_t size)
{
    while (*text == ' ' || *text == '\t')
        text++;
    size_t len = strlen(text);
    while (len > 0 && (text[len - 1] == ' ' || text[len - 1] == '\t'))
        len--;
    if (len == 0 || len > MAX_TITLE)
        return fail(err, size, line, "the title must be 1 to %d characters", MAX_TITLE);
    for (size_t i = 0; i < len; i++) {
        char c = text[i];
        if (!(is_lower(c) || is_digit(c) || (c >= 'A' && c <= 'Z') || strchr(" .,'!?&:-", c)))
            return fail(err, size, line, "the title may only use letters, digits, spaces and . , ' ! ? & : -");
    }
    memcpy(room->title, text, len);
    room->title[len] = '\0';
    return 0;
}

static int parse_puzzle(Room *room, char **tok, int n, int line, char *err, size_t size)
{
    /* puzzle NAME MINUTES : needs... -> gives... */
    if (n < 6 || strcmp(tok[3], ":") != 0)
        return fail(err, size, line, "write a puzzle as: puzzle NAME MINUTES : NEEDS -> GIVES");
    if (room->n_puzzles >= MAX_PUZZLES)
        return fail(err, size, line, "too many puzzles (the limit is %d)", MAX_PUZZLES);
    size_t name_len = strlen(tok[1]);
    if (!valid_name(tok[1], name_len) || strcmp(tok[1], "EXIT") == 0)
        return fail(err, size, line, "the puzzle name is not valid (use a-z, 0-9 and _, starting with a letter)");
    for (int i = 0; i < room->n_puzzles; i++)
        if (strcmp(room->puzzles[i].name, tok[1]) == 0)
            return fail(err, size, line, "this puzzle name is already used on line %d", room->puzzles[i].line);
    Puzzle *p = &room->puzzles[room->n_puzzles];
    memset(p, 0, sizeof *p);
    if (!parse_number(tok[2], 1, MAX_MINUTES, &p->minutes))
        return fail(err, size, line, "minutes must be a whole number from 1 to %d", MAX_MINUTES);
    int arrow = -1;
    for (int i = 4; i < n; i++)
        if (strcmp(tok[i], "->") == 0) {
            if (arrow >= 0)
                return fail(err, size, line, "a puzzle has exactly one ->");
            arrow = i;
        }
    if (arrow < 0 || arrow == n - 1)
        return fail(err, size, line, "a puzzle must give at least one item after ->");
    if (read_items(room, tok + 4, arrow - 4, line, 1, 0, &p->needs, &p->consumes, err, size) != 0)
        return -1;
    if (read_items(room, tok + arrow + 1, n - arrow - 1, line, 0, 1, &p->gives, NULL, err, size) != 0)
        return -1;
    snprintf(p->name, sizeof p->name, "%s", tok[1]);
    p->line = line;
    room->n_puzzles++;
    return 0;
}

static int parse_line(Room *room, char *text, int line, int *seen_start, char *err, size_t size)
{
    char *hash = strchr(text, '#');
    if (hash)
        *hash = '\0';

    char *tok[MAX_TOKENS];
    int n = 0;
    char *keyword_end = NULL;
    for (char *p = text; *p;) {
        while (*p == ' ' || *p == '\t')
            *p++ = '\0';
        if (!*p)
            break;
        if (n == MAX_TOKENS)
            return fail(err, size, line, "too many words on one line");
        tok[n++] = p;
        while (*p && *p != ' ' && *p != '\t')
            p++;
        if (n == 1)
            keyword_end = p;
    }
    if (n == 0)
        return 0;

    if (strcmp(tok[0], "title") == 0) {
        /* The title is the raw rest of the line, so rejoin what was split. */
        if (n < 2)
            return fail(err, size, line, "the title is empty");
        for (char *p = keyword_end + 1; p < tok[n - 1]; p++)
            if (*p == '\0')
                *p = ' ';
        return parse_title(room, tok[1], line, err, size);
    }
    if (strcmp(tok[0], "players") == 0) {
        if (n != 2 || !parse_number(tok[1], 1, MAX_PLAYERS, &room->players))
            return fail(err, size, line, "players must be a whole number from 1 to %d", MAX_PLAYERS);
        return 0;
    }
    if (strcmp(tok[0], "limit") == 0) {
        if (n != 2 || !parse_number(tok[1], 1, MAX_LIMIT, &room->limit))
            return fail(err, size, line, "limit must be a whole number of minutes from 1 to %d", MAX_LIMIT);
        return 0;
    }
    if (strcmp(tok[0], "start") == 0) {
        if (*seen_start)
            return fail(err, size, line, "there can only be one start line");
        *seen_start = 1;
        return read_items(room, tok + 1, n - 1, line, 0, 0, &room->start, NULL, err, size);
    }
    if (strcmp(tok[0], "puzzle") == 0)
        return parse_puzzle(room, tok, n, line, err, size);
    return fail(err, size, line, "unknown keyword (expected title, players, limit, start or puzzle)");
}

int room_parse(const char *text, size_t len, Room *room, char *err, size_t err_size)
{
    memset(room, 0, sizeof *room);
    snprintf(room->title, sizeof room->title, "Untitled room");
    room->players = 4;
    room->limit = 60;
    room->exit_item = -1;

    if (len > MAX_FILE)
        return fail(err, err_size, 0, "the file is larger than %d bytes", MAX_FILE);

    int line = 0, seen_start = 0;
    size_t pos = 0;
    while (pos < len) {
        line++;
        size_t end = pos;
        while (end < len && text[end] != '\n')
            end++;
        size_t line_len = end - pos;
        if (line_len > 0 && text[pos + line_len - 1] == '\r')
            line_len--;
        if (line_len > MAX_LINE)
            return fail(err, err_size, line, "the line is longer than %d characters", MAX_LINE);
        char buffer[MAX_LINE + 1];
        for (size_t i = 0; i < line_len; i++) {
            unsigned char c = (unsigned char)text[pos + i];
            if ((c < 0x20 && c != '\t') || c > 0x7e)
                return fail(err, err_size, line, "only plain printable ASCII text is allowed");
            buffer[i] = (char)c;
        }
        buffer[line_len] = '\0';
        if (parse_line(room, buffer, line, &seen_start, err, err_size) != 0)
            return -1;
        pos = end + 1;
    }

    if (room->n_puzzles == 0)
        return fail(err, err_size, 0, "the room has no puzzles");
    if (room->exit_item < 0)
        return fail(err, err_size, 0, "no puzzle gives EXIT, so the room can never be escaped");
    return 0;
}
