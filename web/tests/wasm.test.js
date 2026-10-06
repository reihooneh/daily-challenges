// Loads the real WebAssembly build in Node and checks it gives the same
// answers as the native program. Run `make web` first.
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { runInThisContext } from 'node:vm';

import { buildInput, sampleState } from '../state.js';

const here = (name) => fileURLToPath(new URL(`../${name}`, import.meta.url));
const built = existsSync(here('picktwo.wasm')) && existsSync(here('wasm_exec.js'));

test('the WebAssembly planner answers the three examples', { skip: built ? false : 'run "make web" first' }, async () => {
  // wasm_exec.js is a classic script that defines a global Go class.
  runInThisContext(readFileSync(here('wasm_exec.js'), 'utf8'), { filename: 'wasm_exec.js' });
  const go = new globalThis.Go();
  const { instance } = await WebAssembly.instantiate(readFileSync(here('picktwo.wasm')), go.importObject);
  go.run(instance);
  const solve = (text) => JSON.parse(globalThis.pickTwoSolve(text));

  const friday = solve(buildInput(sampleState('friday')).text);
  assert.equal(friday.status, 'impossible');
  assert.deepEqual(friday.waysOut.map((way) => way.drop.map((row) => row.text)),
    [['Nothing before 10:00'], ['No classes on Fri'], ['At most 3 days on campus']]);

  const firstYear = solve(buildInput(sampleState('firstyear')).text);
  assert.equal(firstYear.status, 'ok');
  assert.ok(firstYear.plan.classes.every((c) => c.day !== 4 && c.start >= 540 && c.end <= 1080));

  const pair = solve(buildInput(sampleState('pair')).text);
  assert.equal(pair.status, 'impossible');
  assert.deepEqual(pair.conflict.map((row) => row.kind), ['course', 'course']);

  assert.equal(solve('<script>alert(1)</script>').status, 'error');
  assert.equal(JSON.parse(globalThis.pickTwoSolve(42)).status, 'error');
  assert.equal(JSON.parse(globalThis.pickTwoSolve('x'.repeat(70000))).status, 'error');
  assert.equal(JSON.parse(globalThis.pickTwoSolve()).status, 'error');
});
