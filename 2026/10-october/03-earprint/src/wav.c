#include "wav.h"

/* WAV stores numbers little-endian. Writing byte by byte makes the output
 * identical on every CPU, whatever its native byte order. */
static void put_u32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
    p[2] = (uint8_t)(v >> 16);
    p[3] = (uint8_t)(v >> 24);
}

static void put_u16(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t)v;
    p[1] = (uint8_t)(v >> 8);
}

int wav_write(FILE *f, const int16_t *samples, size_t count, uint32_t sample_rate) {
    /* The size fields are 32-bit, so guard against overflow before multiplying. */
    if (f == NULL || samples == NULL || sample_rate == 0 || sample_rate > UINT32_MAX / 2u || count > (UINT32_MAX - 36u) / 2u) {
        return -1;
    }
    uint32_t data_bytes = (uint32_t)count * 2u;

    uint8_t h[WAV_HEADER_LEN] = {'R', 'I', 'F', 'F', 0, 0, 0, 0, 'W', 'A', 'V', 'E', 'f', 'm', 't', ' '};
    put_u32(h + 4, 36u + data_bytes);
    put_u32(h + 16, 16);              /* size of the format chunk */
    put_u16(h + 20, 1);               /* 1 = uncompressed PCM */
    put_u16(h + 22, 1);               /* channels: mono */
    put_u32(h + 24, sample_rate);
    put_u32(h + 28, sample_rate * 2); /* bytes per second */
    put_u16(h + 32, 2);               /* bytes per sample frame */
    put_u16(h + 34, 16);              /* bits per sample */
    h[36] = 'd'; h[37] = 'a'; h[38] = 't'; h[39] = 'a';
    put_u32(h + 40, data_bytes);
    if (fwrite(h, 1, sizeof h, f) != sizeof h) {
        return -1;
    }

    for (size_t i = 0; i < count; i++) {
        uint8_t b[2];
        put_u16(b, (uint16_t)samples[i]);
        if (fwrite(b, 1, 2, f) != 2) {
            return -1;
        }
    }
    return fflush(f) == 0 ? 0 : -1;
}
