import type { Forecast } from './ledger.js';
import type { Result } from './optimise.js';
import { type Plan, formatDay, formatMoney, ordinal } from './plan.js';

const BARS = '▁▂▃▄▅▆▇█';
export const CHART_WIDTH = 60;

// One mark per bucket of days (the bucket's lowest point), and a line of ^ under any
// bucket that dips below the buffer.
export function chart(lows: number[], buffer: number): string[] {
  const per = Math.max(1, Math.ceil(lows.length / CHART_WIDTH));
  const buckets: number[] = [];
  for (let i = 0; i < lows.length; i += per) buckets.push(Math.min(...lows.slice(i, i + per)));
  const lo = Math.min(...buckets, buffer);
  const hi = Math.max(...buckets, buffer + 1);
  const bars = buckets.map((v) => BARS[Math.round(((v - lo) / (hi - lo)) * (BARS.length - 1))]).join('');
  const marks = buckets.map((v) => (v < buffer ? '^' : ' ')).join('').trimEnd();
  const legend = `one mark per ${per === 1 ? 'day' : `${per} days`}`;
  return marks ? [bars, marks, `${legend}; ^ = below your buffer`] : [bars, legend];
}

function summary(plan: Plan, lowTide: number, lowDay: number, lows: number[]): string {
  const below = lows.filter((v) => v < plan.buffer).length;
  const overdrawn = lows.filter((v) => v < 0).length;
  let text = `Low tide ${formatMoney(lowTide)} on ${formatDay(plan.start + lowDay)}`;
  if (below === 0) return `${text}: never below your buffer.`;
  text += `\n  Below your buffer on ${below} day${below === 1 ? '' : 's'}`;
  return overdrawn ? `${text}, overdrawn on ${overdrawn}.` : `${text}.`;
}

export function render(plan: Plan, before: Forecast, after: Forecast, result: Result, name: string): string {
  const out: string[] = [];
  out.push(`LOWTIDE  ${name}  (${plan.days} days from ${formatDay(plan.start)}; buffer ${formatMoney(plan.buffer)})`);
  out.push('', 'AS IT IS', `  ${summary(plan, before.lowTide, before.lowDay, before.low)}`);
  for (const line of chart(before.low, plan.buffer)) out.push(`  ${line}`);

  const movable = plan.items.filter((it) => it.movable).length;
  out.push('');
  if (movable === 0) {
    out.push('No bills are marked movable. Add "movable" to the monthly bills whose due date you could change.');
  } else if (result.moves.length === 0) {
    out.push(
      before.lowTide >= plan.buffer
        ? 'Nothing to move: you stay above your buffer as it is.'
        : 'Moving due dates would not help: the low point comes from bills that are fixed or already well placed.',
    );
  } else {
    out.push('MOVE THESE DUE DATES');
    const width = Math.max(...result.moves.map((m) => m.item.name.length));
    for (const m of result.moves) {
      out.push(`  ${m.item.name.padEnd(width)}  ${formatMoney(m.item.cents).padStart(10)}   from the ${ordinal(m.from)} to the ${ordinal(m.to)}`);
    }
    out.push('', 'AFTER', `  ${summary(plan, after.lowTide, after.lowDay, after.low)}`);
    for (const line of chart(after.low, plan.buffer)) out.push(`  ${line}`);
    out.push(`  That's ${formatMoney(after.lowTide - before.lowTide)} more at the lowest point.`);
  }
  if (after.lowTide < plan.buffer) {
    out.push(
      '',
      `To stay above your buffer you'd still need ${formatMoney(plan.buffer - after.lowTide)} more by ${formatDay(plan.start + after.lowDay)}, or a smaller bill before then.`,
    );
  }
  if (!result.exhaustive) out.push('', '(The search stopped early, so a slightly better plan may exist.)');
  out.push(
    '',
    'Most companies let you choose the day of the month a bill is due: ask them to change it.',
    'This is arithmetic on the numbers you gave it, not financial advice.',
  );
  return out.join('\n') + '\n';
}
