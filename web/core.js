// A thin wrapper around the WebAssembly core (core/*.c). The module has no imports at all:
// it can only read and write its own memory, through the buffers below.

const ERRORS = {
  '-1': 'That is more than one page can hold.',
  '-2': 'The photo is too small or too large.',
  '-3': 'No Inkvault page found. Make sure all four corner squares are in the picture.',
  '-4': 'Found the page, but it is too damaged to read. Try a sharper, flatter, brighter photo.',
};

export async function loadCore(source) {
  let instance;
  if (source instanceof ArrayBuffer || ArrayBuffer.isView(source)) {
    ({ instance } = await WebAssembly.instantiate(source, {}));
  } else {
    const response = await fetch(source);
    if (!response.ok) throw new Error('Could not load the decoder.');
    ({ instance } = await WebAssembly.instantiate(await response.arrayBuffer(), {}));
  }
  const e = instance.exports;
  const cols = e.cols();
  const rows = e.rows();
  const capacity = e.capacity();
  const maxSide = e.max_side();
  const bytes = () => new Uint8Array(e.memory.buffer);

  function result(code) {
    const info = new Int32Array(e.memory.buffer, e.info_ptr(), 13);
    if (code < 0) return { ok: false, code, error: ERRORS[code] ?? 'Unknown error.', candidates: info[12] };
    const p = e.payload_ptr();
    return {
      ok: true,
      bytes: bytes().slice(p, p + code),
      corners: Array.from(info.slice(0, 8)),
      repaired: info[8],
      worst: info[9],
      limit: info[10],
      flags: info[11],
    };
  }

  return {
    // Zeroes the buffers that held page contents, so secrets don't linger in memory.
    wipe() {
      const m = bytes();
      m.fill(0, e.payload_ptr(), e.payload_ptr() + capacity);
      m.fill(0, e.cells_ptr(), e.cells_ptr() + cols * rows);
      m.fill(0, e.image_ptr(), e.image_ptr() + maxSide * maxSide);
    },
    cols,
    rows,
    capacity,
    maxSide,
    // Returns the page's cells (1 = dark), row by row.
    encode(payload, flags) {
      if (!(payload instanceof Uint8Array) || payload.length > capacity) throw new RangeError(ERRORS['-1']);
      bytes().set(payload, e.payload_ptr());
      const code = e.encode(payload.length, flags & 0xff);
      if (code < 0) throw new RangeError(ERRORS[code]);
      const c = e.cells_ptr();
      return bytes().slice(c, c + cols * rows);
    },
    decodeCells(cells) {
      if (cells.length !== cols * rows) throw new RangeError('Wrong number of cells.');
      bytes().set(cells, e.cells_ptr());
      return result(e.decode_cells());
    },
    // gray: one byte per pixel, 0 = black. The core checks the size again.
    decodeGray(gray, width, height) {
      if (!Number.isInteger(width) || !Number.isInteger(height) || width < 1 || height < 1) return result(-2);
      if (width > maxSide || height > maxSide || gray.length !== width * height) return result(-2);
      bytes().set(gray, e.image_ptr());
      return result(e.decode_image(width, height));
    },
  };
}

// RGBA pixels -> one grey byte per pixel.
export function toGray(rgba, width, height) {
  const gray = new Uint8Array(width * height);
  for (let i = 0, j = 0; i < gray.length; i++, j += 4) {
    gray[i] = (rgba[j] * 299 + rgba[j + 1] * 587 + rgba[j + 2] * 114) / 1000;
  }
  return gray;
}
