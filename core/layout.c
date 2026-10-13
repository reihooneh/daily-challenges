/*
 * The page layout: where each byte goes, and how the payload becomes cells.
 *
 *   payload -> [header | payload | padding] (768 bytes)
 *           -> 8 Reed-Solomon blocks of 96 data + 40 check bytes
 *           -> interleaved into one stream of 1088 bytes
 *           -> scattered over the page by a fixed shuffle, so a stain or tear
 *              damages a few bytes in many blocks instead of many bytes in one
 *           -> masked with a fixed pseudo-random pattern, so even an empty
 *              payload prints as an even mix of dark and light
 *           -> each byte drawn as a 4 x 2 tile of cells
 */
#include "inkvault.h"

static uint8_t tile_x[IV_TILES], tile_y[IV_TILES]; /* top-left cell of each tile */
static uint16_t place[IV_TILES];                   /* stream position -> tile */
static uint8_t mask[IV_TILES];
static int layout_ready = 0;

static uint32_t xorshift(uint32_t *state) {
  uint32_t x = *state;
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  *state = x;
  return x;
}

static int in_corner(int x, int y) {
  int left = x < IV_ZONE, right = x >= IV_COLS - IV_ZONE;
  int top = y < IV_ZONE, bottom = y >= IV_ROWS - IV_ZONE;
  return (left || right) && (top || bottom);
}

static void layout_init(void) {
  if (layout_ready) return;
  int t = 0;
  for (int y = 0; y < IV_ROWS; y += IV_TILE_H) {
    for (int x = 0; x < IV_COLS; x += IV_TILE_W) {
      if (in_corner(x, y)) continue;
      tile_x[t] = (uint8_t)x;
      tile_y[t] = (uint8_t)y;
      t++;
    }
  }
  for (int i = 0; i < IV_TILES; i++) place[i] = (uint16_t)i;
  uint32_t seed = 0x1EAF5EEDu;
  for (int i = IV_TILES - 1; i > 0; i--) { /* Fisher-Yates shuffle with a fixed seed */
    int j = (int)(xorshift(&seed) % (uint32_t)(i + 1));
    uint16_t tmp = place[i];
    place[i] = place[j];
    place[j] = tmp;
  }
  seed = 0xC0FFEE11u;
  for (int i = 0; i < IV_TILES; i++) mask[i] = (uint8_t)(xorshift(&seed) >> 24);
  layout_ready = 1;
}

static void draw_finder(uint8_t *cells, int ox, int oy) {
  for (int y = 0; y < IV_FINDER; y++) {
    for (int x = 0; x < IV_FINDER; x++) {
      int ring = x == 0 || y == 0 || x == IV_FINDER - 1 || y == IV_FINDER - 1;
      int core = x >= 2 && x <= 4 && y >= 2 && y <= 4;
      cells[(oy + y) * IV_COLS + ox + x] = (uint8_t)(ring || core);
    }
  }
}

int iv_encode(const uint8_t *payload, int len, int flags, uint8_t *cells) {
  if (len < 0 || len > IV_CAPACITY) return IV_ERR_TOO_BIG;
  layout_init();
  uint8_t data[IV_DATA];
  iv_memset(data, 0, sizeof data);
  uint32_t crc = iv_crc32(payload, (size_t)len);
  data[0] = 'I';
  data[1] = 'V';
  data[2] = IV_VERSION;
  data[3] = (uint8_t)flags;
  data[4] = (uint8_t)(len >> 8);
  data[5] = (uint8_t)len;
  for (int i = 0; i < 4; i++) data[6 + i] = (uint8_t)(crc >> (24 - 8 * i));
  iv_memcpy(data + IV_HEADER, payload, (size_t)len);

  uint8_t blocks[IV_BLOCKS][IV_BLOCK_N];
  for (int b = 0; b < IV_BLOCKS; b++) iv_rs_encode(data + (size_t)b * IV_BLOCK_K, IV_BLOCK_K, IV_NSYM, blocks[b]);

  iv_memset(cells, 0, (size_t)IV_COLS * IV_ROWS);
  draw_finder(cells, 0, 0);
  draw_finder(cells, IV_COLS - IV_FINDER, 0);
  draw_finder(cells, IV_COLS - IV_FINDER, IV_ROWS - IV_FINDER);
  draw_finder(cells, 0, IV_ROWS - IV_FINDER);
  for (int p = 0; p < IV_TILES; p++) {
    uint8_t byte = (uint8_t)(blocks[p % IV_BLOCKS][p / IV_BLOCKS] ^ mask[p]);
    int t = place[p];
    for (int bit = 0; bit < 8; bit++) {
      int x = tile_x[t] + bit % IV_TILE_W, y = tile_y[t] + bit / IV_TILE_W;
      cells[y * IV_COLS + x] = (uint8_t)((byte >> (7 - bit)) & 1);
    }
  }
  return 0;
}

/* Repairs one block: first as plain errors; if that fails, again treating the bytes whose
 * cells were hardest to read as erasures (known suspects cost half as much to repair). */
static int repair_block(uint8_t *block, const uint8_t *doubt) {
  uint8_t copy[IV_BLOCK_N];
  iv_memcpy(copy, block, IV_BLOCK_N);
  int fixed = iv_rs_decode(copy, IV_BLOCK_N, IV_NSYM);
  if (fixed >= 0 || !doubt) {
    if (fixed >= 0) iv_memcpy(block, copy, IV_BLOCK_N);
    return fixed;
  }
  int order[IV_BLOCK_N], n = 0;
  for (int level = 8; level >= 1; level--) /* most doubtful first */
    for (int i = 0; i < IV_BLOCK_N; i++)
      if (doubt[i] == level) order[n++] = i;
  /* Never spend every check byte on erasures: keep at least 10 to confirm the repair. */
  const int limits[2] = {IV_NSYM - 10, IV_NSYM / 2};
  for (int k = 0; k < 2; k++) {
    int count = n < limits[k] ? n : limits[k];
    if (count == 0) break;
    iv_memcpy(copy, block, IV_BLOCK_N);
    fixed = iv_rs_decode_erasures(copy, IV_BLOCK_N, IV_NSYM, order, count);
    if (fixed >= 0) {
      iv_memcpy(block, copy, IV_BLOCK_N);
      return fixed;
    }
  }
  return -1;
}

int iv_decode_cells(const uint8_t *cells, uint8_t *payload, iv_info *info) {
  return iv_decode_cells_doubt(cells, 0, payload, info);
}

int iv_decode_cells_doubt(const uint8_t *cells, const uint8_t *unsure, uint8_t *payload, iv_info *info) {
  layout_init();
  uint8_t blocks[IV_BLOCKS][IV_BLOCK_N];
  uint8_t doubt[IV_BLOCKS][IV_BLOCK_N]; /* unsure cells in each byte's tile, 0 to 8 */
  for (int p = 0; p < IV_TILES; p++) {
    int t = place[p];
    uint8_t byte = 0, d = 0;
    for (int bit = 0; bit < 8; bit++) {
      int x = tile_x[t] + bit % IV_TILE_W, y = tile_y[t] + bit / IV_TILE_W;
      byte = (uint8_t)((byte << 1) | (cells[y * IV_COLS + x] & 1));
      if (unsure && unsure[y * IV_COLS + x]) d++;
    }
    blocks[p % IV_BLOCKS][p / IV_BLOCKS] = (uint8_t)(byte ^ mask[p]);
    doubt[p % IV_BLOCKS][p / IV_BLOCKS] = d;
  }
  int repaired = 0, worst = 0;
  uint8_t data[IV_DATA];
  for (int b = 0; b < IV_BLOCKS; b++) {
    int fixed = repair_block(blocks[b], unsure ? doubt[b] : 0);
    if (fixed < 0) return IV_ERR_DAMAGED;
    repaired += fixed;
    if (fixed > worst) worst = fixed;
    iv_memcpy(data + (size_t)b * IV_BLOCK_K, blocks[b], IV_BLOCK_K);
  }
  /* Repaired, but is it really an Inkvault page, and intact? */
  if (data[0] != 'I' || data[1] != 'V' || data[2] != IV_VERSION) return IV_ERR_DAMAGED;
  int len = (data[4] << 8) | data[5];
  if (len > IV_CAPACITY) return IV_ERR_DAMAGED;
  uint32_t crc = 0;
  for (int i = 0; i < 4; i++) crc = (crc << 8) | data[6 + i];
  if (iv_crc32(data + IV_HEADER, (size_t)len) != crc) return IV_ERR_DAMAGED;
  iv_memcpy(payload, data + IV_HEADER, (size_t)len);
  if (info) {
    info->repaired = repaired;
    info->worst = worst;
    info->limit = IV_NSYM / 2;
    info->flags = data[3];
  }
  return len;
}
