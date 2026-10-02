/* Earprint: hear a file's SHA-256 fingerprint as a short melody.
 *
 *   earprint FILE                 print the hash and its melody
 *   earprint FILE -o tune.wav     also save the melody as audio
 *   earprint --compare A B        do two files have the same fingerprint?
 *
 * Exit codes: 0 = success (or files match), 1 = files differ, 2 = error.
 */
#include <errno.h>
#include <stdio.h>
#include <string.h>

#include "melody.h"
#include "sha256.h"
#include "wav.h"

#define VERSION "0.1.0"
#define READ_CHUNK 65536

static const char USAGE[] =
    "earprint: hear a file's SHA-256 fingerprint as a melody\n"
    "\n"
    "USAGE:\n"
    "    earprint FILE [-o OUT.wav] [--force]\n"
    "    earprint --compare FILE_A FILE_B\n"
    "\n"
    "OPTIONS:\n"
    "    -o OUT.wav     Save the melody as a WAV file\n"
    "    --force        Allow -o to replace an existing file\n"
    "    --compare      Compare two files' fingerprints (exit 0 if equal, 1 if not)\n"
    "    -h, --help     Show this help\n"
    "    -V, --version  Show version\n";

/* Hashes a file in fixed-size chunks, so memory use stays constant however
 * large the file is. Returns 0 on success, -1 on error (message printed). */
static int hash_file(const char *path, uint8_t digest[SHA256_DIGEST_LEN]) {
    FILE *f = fopen(path, "rb");
    if (f == NULL) {
        fprintf(stderr, "earprint: cannot open '%s': %s\n", path, strerror(errno));
        return -1;
    }
    static uint8_t chunk[READ_CHUNK];
    sha256_ctx ctx;
    sha256_init(&ctx);
    size_t n;
    while ((n = fread(chunk, 1, sizeof chunk, f)) > 0) {
        sha256_update(&ctx, chunk, n);
    }
    int failed = ferror(f);
    int saved = errno;
    fclose(f);
    if (failed) {
        fprintf(stderr, "earprint: cannot read '%s': %s\n", path, strerror(saved));
        return -1;
    }
    sha256_final(&ctx, digest);
    return 0;
}

static int print_fingerprint(const char *label, const uint8_t digest[SHA256_DIGEST_LEN],
                             melody_note notes[MELODY_NOTES]) {
    char hex[65];
    char text[MELODY_TEXT_LEN];
    sha256_to_hex(digest, hex);
    melody_from_digest(digest, notes);
    if (melody_to_text(notes, text, sizeof text) != 0) {
        fprintf(stderr, "earprint: internal error formatting melody\n");
        return -1;
    }
    /* The path is printed with %s as data, never used as a format string. */
    printf("%s\n  sha256  %s\n  melody  %s\n", label, hex, text);
    return 0;
}

static int save_wav(const char *path, const melody_note notes[MELODY_NOTES], int force) {
    static int16_t samples[MELODY_MAX_SAMPLES];
    size_t count = melody_render(notes, samples, MELODY_MAX_SAMPLES);
    if (count == 0) {
        fprintf(stderr, "earprint: internal error rendering audio\n");
        return -1;
    }
    /* "x" makes fopen fail if the file already exists (including via a
     * symlink), so we never overwrite something by accident. */
    FILE *f = fopen(path, force ? "wb" : "wbx");
    if (f == NULL) {
        if (errno == EEXIST) {
            fprintf(stderr, "earprint: '%s' already exists (use --force to replace it)\n", path);
        } else {
            fprintf(stderr, "earprint: cannot create '%s': %s\n", path, strerror(errno));
        }
        return -1;
    }
    int rc = wav_write(f, samples, count, MELODY_SAMPLE_RATE);
    if (fclose(f) != 0) {
        rc = -1;
    }
    if (rc != 0) {
        fprintf(stderr, "earprint: failed while writing '%s'\n", path);
        return -1;
    }
    printf("  saved   %s (%.1f seconds)\n", path, (double)count / MELODY_SAMPLE_RATE);
    return 0;
}

static int compare(const char *a, const char *b) {
    uint8_t da[SHA256_DIGEST_LEN], db[SHA256_DIGEST_LEN];
    melody_note na[MELODY_NOTES], nb[MELODY_NOTES];
    if (hash_file(a, da) != 0 || hash_file(b, db) != 0) {
        return 2;
    }
    if (print_fingerprint(a, da, na) != 0 || print_fingerprint(b, db, nb) != 0) {
        return 2;
    }
    if (sha256_equal(da, db)) {
        printf("\nMATCH: the fingerprints are identical.\n");
        return 0;
    }
    printf("\nDIFFERENT: these are not the same file.\n");
    return 1;
}

int main(int argc, char **argv) {
    const char *input = NULL, *output = NULL;
    int force = 0;

    for (int i = 1; i < argc; i++) {
        const char *arg = argv[i];
        if (strcmp(arg, "-h") == 0 || strcmp(arg, "--help") == 0) {
            fputs(USAGE, stdout);
            return 0;
        } else if (strcmp(arg, "-V") == 0 || strcmp(arg, "--version") == 0) {
            puts("earprint " VERSION);
            return 0;
        } else if (strcmp(arg, "--compare") == 0) {
            if (argc != 4 || i != 1) {
                fprintf(stderr, "earprint: --compare needs exactly two files\n");
                return 2;
            }
            return compare(argv[2], argv[3]);
        } else if (strcmp(arg, "--force") == 0) {
            force = 1;
        } else if (strcmp(arg, "-o") == 0) {
            if (i + 1 >= argc) {
                fprintf(stderr, "earprint: -o needs a file name\n");
                return 2;
            }
            output = argv[++i];
        } else if (arg[0] == '-' && arg[1] != '\0') {
            fprintf(stderr, "earprint: unknown option '%s' (try --help)\n", arg);
            return 2;
        } else if (input == NULL) {
            input = arg;
        } else {
            fprintf(stderr, "earprint: only one input file is allowed (did you mean --compare?)\n");
            return 2;
        }
    }
    if (input == NULL) {
        fputs(USAGE, stderr);
        return 2;
    }

    uint8_t digest[SHA256_DIGEST_LEN];
    melody_note notes[MELODY_NOTES];
    if (hash_file(input, digest) != 0 || print_fingerprint(input, digest, notes) != 0) {
        return 2;
    }
    if (output != NULL && save_wav(output, notes, force) != 0) {
        return 2;
    }
    return 0;
}
