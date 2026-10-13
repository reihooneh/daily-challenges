/*
 * Inkvault core: turns a small payload into a printable page of dark and light cells,
 * and reads it back from a photo of that page, even a damaged one.
 *
 * Freestanding C17: no libc, no allocation. The same code is tested natively (with
 * sanitizers) and compiled to WebAssembly for the browser.
 */
#ifndef INKVAULT_H
#define INKVAULT_H

#include <stddef.h>
#include <stdint.h>

/* Page geometry, in cells. */
#define IV_COLS 80
#define IV_ROWS 112
#define IV_FINDER 7                  /* finder squares in the four corners */
#define IV_ZONE 8                    /* finder plus a one-cell light border */
#define IV_TILE_W 4                  /* one byte = a 4 x 2 tile of cells */
#define IV_TILE_H 2
#define IV_TILES ((IV_COLS / IV_TILE_W) * (IV_ROWS / IV_TILE_H) - 4 * (IV_ZONE / IV_TILE_W) * (IV_ZONE / IV_TILE_H))

/* Error correction: IV_BLOCKS Reed-Solomon blocks, interleaved across the page. */
#define IV_BLOCKS 8
#define IV_BLOCK_N (IV_TILES / IV_BLOCKS) /* 136 bytes per block */
#define IV_NSYM 40                        /* repairs up to 20 damaged bytes per block */
#define IV_BLOCK_K (IV_BLOCK_N - IV_NSYM) /* 96 data bytes per block */
#define IV_DATA (IV_BLOCKS * IV_BLOCK_K)  /* 768 */
#define IV_HEADER 10                      /* 'I' 'V' version flags length(2) crc32(4) */
#define IV_CAPACITY (IV_DATA - IV_HEADER) /* 758 bytes of payload */
#define IV_VERSION 1

/* Largest photo the decoder accepts (the browser scales photos down to fit). */
#define IV_MAX_SIDE 1600
#define IV_MIN_SIDE 64

/* Results. Negative values are errors. */
#define IV_ERR_TOO_BIG (-1)      /* payload larger than IV_CAPACITY */
#define IV_ERR_IMAGE_SIZE (-2)   /* photo too small or too large */
#define IV_ERR_NO_PAGE (-3)      /* could not find the four corner squares */
#define IV_ERR_DAMAGED (-4)      /* found the page, but too damaged to repair */

/* What the decoder found, for the user interface. */
typedef struct {
  int32_t corners[8];   /* finder centres in the photo: x0 y0 ... x3 y3 (top-left first, clockwise) */
  int32_t repaired;     /* damaged bytes that were repaired */
  int32_t worst;        /* most repairs needed in any one block */
  int32_t limit;        /* most repairs possible per block (IV_NSYM / 2) */
  int32_t flags;        /* the flags byte from the page header */
  int32_t candidates;   /* finder-like patterns seen (for diagnostics) */
} iv_info;

/* ---- building blocks (exposed for tests) ---- */
void iv_memset(void *dst, int value, size_t n);
void iv_memcpy(void *dst, const void *src, size_t n);
uint32_t iv_crc32(const uint8_t *data, size_t n);

void iv_rs_encode(const uint8_t *msg, int k, int nsym, uint8_t *out); /* out has k + nsym bytes */
/* Repairs a codeword in place. Returns the number of bytes repaired, or -1 if it can't. */
int iv_rs_decode(uint8_t *codeword, int n, int nsym);
/* The same, with the positions of bytes already known to be doubtful ("erasures"). */
int iv_rs_decode_erasures(uint8_t *codeword, int n, int nsym, const int *erased, int count);

/* ---- the page ---- */
/* Writes IV_COLS * IV_ROWS cells (1 = dark), row by row. Returns 0 or IV_ERR_TOO_BIG. */
int iv_encode(const uint8_t *payload, int len, int flags, uint8_t *cells);
/* Reads cells back (no photo involved). Returns the payload length or an error. */
int iv_decode_cells(const uint8_t *cells, uint8_t *payload, iv_info *info);
/* The same, with a second grid marking cells that were hard to read (1 = unsure). */
int iv_decode_cells_doubt(const uint8_t *cells, const uint8_t *unsure, uint8_t *payload, iv_info *info);
/* Reads a greyscale photo (0 = black, 255 = white), w x h pixels. `work` must hold
 * iv_work_size(w, h) bytes. Returns the payload length or an error. */
int iv_decode_image(const uint8_t *gray, int w, int h, uint8_t *work, uint8_t *payload, iv_info *info);
size_t iv_work_size(int w, int h);

#endif
