// Checks the built WebAssembly module: no imports (it cannot reach anything outside its
// own memory), a fixed memory size, and a small file.
import { readFile } from 'node:fs/promises';

const bytes = await readFile(new URL('../web/inkvault.wasm', import.meta.url));
const module = new WebAssembly.Module(bytes);
const imports = WebAssembly.Module.imports(module);
const problems = [];
if (imports.length) problems.push(`it imports ${imports.map((i) => `${i.module}.${i.name}`).join(', ')}`);
const memory = new WebAssembly.Instance(module, {}).exports.memory;
try {
  memory.grow(1);
  problems.push('its memory can grow');
} catch {
  // expected: the maximum equals the initial size
}
if (bytes.length > 64 * 1024) problems.push(`it is ${bytes.length} bytes`);
if (problems.length) {
  console.error(`inkvault.wasm: ${problems.join('; ')}`);
  process.exit(1);
}
console.log(`inkvault.wasm: ${bytes.length} bytes, no imports, fixed memory`);
