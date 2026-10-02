/* Minimal WAV writer: 16-bit mono PCM. */
#ifndef EARPRINT_WAV_H
#define EARPRINT_WAV_H

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

#define WAV_HEADER_LEN 44

/* Writes a complete WAV file to `f`. Returns 0 on success, -1 on any error
 * (bad arguments, too many samples for the format, or a failed write). */
int wav_write(FILE *f, const int16_t *samples, size_t count, uint32_t sample_rate);

#endif
