// kerbtuck: will the car fit that kerbside gap, and how?
//
//   kerbtuck --car golf --gap 5.6          plan parking in a 5.6 m gap
//   kerbtuck --car-file mine.json --gap 6  the same with your own car
//   kerbtuck --compare 5.6                 every built-in car in a 5.6 m gap

import { lstatSync, readFileSync } from 'node:fs';
import { PRESETS, Car, CarError, parseCar, MAX_FILE } from './car.js';
import { scene, plan, oneMoveGap, replay } from './park.js';
import { picture, goes } from './draw.js';

export function run(args: string[], out: (s: string) => void, err: (s: string) => void): number {
  const opts: Record<string, string> = {};
  for (let i = 0; i < args.length; i++) {
    const a = args[i]!;
    if (!['--car', '--car-file', '--gap', '--compare'].includes(a) || i + 1 >= args.length) {
      err('usage: kerbtuck (--car NAME | --car-file FILE) --gap METRES\n       kerbtuck --compare METRES\n' +
        `cars: ${Object.keys(PRESETS).join(', ')}`);
      return 2;
    }
    opts[a] = args[++i]!;
  }
  const metres = (s: string | undefined, what: string): number => {
    const v = Number(s);
    if (s === undefined || !/^\d+(\.\d+)?$/.test(s) || !(v >= 2 && v <= 15)) throw new CarError(`${what} should be a number of metres from 2 to 15.`);
    return v;
  };
  try {
    if (opts['--compare'] !== undefined) {
      const gap = metres(opts['--compare'], 'The gap');
      out(`Kerbtuck: every built-in car in a ${gap.toFixed(2)} m gap\n`);
      out(`  ${'car'.padEnd(22)} ${'length'.padStart(7)} ${'one go needs'.padStart(13)}   in this gap`);
      for (const car of Object.values(PRESETS)) {
        const p = plan(scene(car, gap));
        const verdict = !p.found ? "doesn't fit" : p.changes === 0 ? 'in one go' : `${p.changes + 1} goes (${p.changes} gear ${p.changes === 1 ? 'change' : 'changes'})`;
        out(`  ${car.name.padEnd(22)} ${car.length.toFixed(2).padStart(6)} m ${oneMoveGap(car).toFixed(2).padStart(10)} m   ${verdict}`);
      }
      return 0;
    }
    let car: Car;
    if (opts['--car-file'] !== undefined) car = parseCar(readCarFile(opts['--car-file']));
    else {
      const id = opts['--car'];
      const preset = id !== undefined && Object.prototype.hasOwnProperty.call(PRESETS, id) ? PRESETS[id] : undefined;
      if (!preset) throw new CarError(`Choose a car: ${Object.keys(PRESETS).join(', ')} (or --car-file).`);
      car = preset;
    }
    const gap = metres(opts['--gap'], 'The gap');
    const s = scene(car, gap);
    const one = oneMoveGap(car);
    out(`Kerbtuck: ${car.name} (${car.length.toFixed(2)} m long) into a ${gap.toFixed(2)} m gap`);
    out(`It can reverse in in one go into a gap of ${one.toFixed(2)} m or more (${(one - car.length).toFixed(2)} m more than its length).\n`);
    if (gap < car.length + 2 * 0.05) {
      out("The gap is shorter than the car: it can't fit.");
      return 0;
    }
    const p = plan(s);
    if (!p.found) {
      out(p.gave_up
        ? 'No way in found within the search limit: it may fit with more shuffles than Kerbtuck looks for.'
        : "No way in: the car can't turn tightly enough to tuck into a gap this short.");
      return 0;
    }
    const check = replay(s, p.moves);
    out(p.changes === 0 ? 'It goes in in one go:' : `It takes ${p.changes + 1} goes (${p.changes} gear ${p.changes === 1 ? 'change' : 'changes'}):`);
    for (const g of goes(p.moves)) out(`  ${g}`);
    out(`\n${p.distance.toFixed(1)} m of driving; checked every 5 cm for bumps: ${check.ok ? 'clear' : 'NOT clear'}.\n`);
    out(picture(s, p.poses, check.end));
    return 0;
  } catch (e) {
    if (e instanceof CarError) {
      err(`kerbtuck: ${e.message}`);
      return 1;
    }
    err('kerbtuck: something went wrong.');
    return 1;
  }
}

function readCarFile(path: string): string {
  let st;
  try {
    st = lstatSync(path);
  } catch {
    throw new CarError('The car file was not found.');
  }
  if (!st.isFile()) throw new CarError('The car file must be a plain file (not a link or folder).');
  if (st.size > MAX_FILE) throw new CarError('A car file is at most 4 KB.');
  return readFileSync(path, 'utf8');
}
