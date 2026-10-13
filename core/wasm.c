/*
 * The WebAssembly interface. All memory is static: the page asks for pointers to fixed
 * buffers, copies data in, calls a function and reads the result. Nothing is allocated,
 * and every size is checked again here, whatever JavaScript passes in.
 */
#include "inkvault.h"

#define EXPORT(name) __attribute__((export_name(#name)))

static uint8_t image_buf[IV_MAX_SIDE * IV_MAX_SIDE];
static uint8_t work_buf[IV_MAX_SIDE * IV_MAX_SIDE + 8 + 4 * (IV_MAX_SIDE + 1) * (IV_MAX_SIDE + 1)];
static uint8_t payload_buf[IV_CAPACITY];
static uint8_t cells_buf[IV_COLS * IV_ROWS];
static iv_info info_buf;

EXPORT(image_ptr) uint8_t *image_ptr(void) { return image_buf; }
EXPORT(payload_ptr) uint8_t *payload_ptr(void) { return payload_buf; }
EXPORT(cells_ptr) uint8_t *cells_ptr(void) { return cells_buf; }
EXPORT(info_ptr) iv_info *info_ptr(void) { return &info_buf; }
EXPORT(capacity) int capacity(void) { return IV_CAPACITY; }
EXPORT(cols) int cols(void) { return IV_COLS; }
EXPORT(rows) int rows(void) { return IV_ROWS; }
EXPORT(max_side) int max_side(void) { return IV_MAX_SIDE; }

EXPORT(encode) int encode(int len, int flags) { return iv_encode(payload_buf, len, flags & 0xFF, cells_buf); }

EXPORT(decode_cells) int decode_cells(void) {
  iv_memset(&info_buf, 0, sizeof info_buf);
  return iv_decode_cells(cells_buf, payload_buf, &info_buf);
}

EXPORT(decode_image) int decode_image(int w, int h) {
  if (iv_work_size(w, h) == 0 || iv_work_size(w, h) > sizeof work_buf) return IV_ERR_IMAGE_SIZE;
  return iv_decode_image(image_buf, w, h, work_buf, payload_buf, &info_buf);
}
