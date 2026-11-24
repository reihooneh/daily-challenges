#!/usr/bin/env node
// crownwind COLLECTION.json: when to wind which watch.
import { readFileSync, statSync } from 'node:fs';
import { LIMITS, PlanError, label, parse, sessions, windings } from './crownwind.js';

function hours(m) {
  return `${Math.round(m / 60)} h`;
}

export function report(plan) {
  const { sessions: chosen, stranded } = sessions(plan);
  const per = windings(plan, chosen);
  const lines = [];
  const kept = plan.watches.filter((w) => !w.mayStop);
  lines.push(`${plan.watches.length} watches over ${plan.horizon / 1440} days, keeping a ${Math.round(plan.margin * 100)} % reserve margin.`);
  lines.push(`${chosen.length} winding session${chosen.length === 1 ? '' : 's'} keep ${kept.length - stranded.length} of them running; ` +
    `${[...per.values()].reduce((s, v) => s + v.length, 0)} crown windings in all.\n`);
  for (const t of chosen) {
    const who = [...per.entries()].filter(([, ts]) => ts.includes(t)).map(([n]) => n);
    lines.push(`  ${label(plan, t)}   wind ${who.join(', ')}`);
  }
  for (const { watch, at } of stranded) {
    lines.push(`\n! ${watch.name} will stop at ${label(plan, at)}: there's no winding time before then. Add a slot, wear it, or let it stop.`);
  }
  const free = plan.watches.filter((w) => w.mayStop).map((w) => w.name);
  if (free.length) lines.push(`\nAllowed to stop (not planned): ${free.join(', ')}.`);
  lines.push('\nPer watch:');
  for (const w of kept) {
    const n = per.get(w.name)?.length ?? 0;
    lines.push(`  ${w.name.padEnd(24)} ${w.kind.padEnd(9)} reserve ${hours(w.reserve).padStart(6)}   wound ${n} time${n === 1 ? '' : 's'}`);
  }
  return lines.join('\n');
}

function main(argv) {
  if (argv.length !== 1) {
    process.stderr.write('usage: crownwind COLLECTION.json\n');
    return 2;
  }
  try {
    const st = statSync(argv[0]);
    if (!st.isFile() || st.size > LIMITS.bytes) throw new PlanError('the collection must be a regular file under 64 KB');
    process.stdout.write(report(parse(readFileSync(argv[0], 'utf8'))) + '\n');
    return 0;
  } catch (e) {
    if (e instanceof PlanError) process.stderr.write(`crownwind: ${e.message}\n`);
    else process.stderr.write("crownwind: can't read that file\n");
    return 2;
  }
}

if (import.meta.url === `file://${process.argv[1]}`) process.exitCode = main(process.argv.slice(2));
