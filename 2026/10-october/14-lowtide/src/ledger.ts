// Day-by-day balance forecast. On a day with both, money is assumed to leave before the
// pay arrives: the cautious assumption, because banks don't promise an order.
import { type Item, type Plan, type Schedule, daysInMonth, dayOf, ymd } from './plan.js';

// Every day (as an offset from the start) on which the schedule falls, within the window.
export function occurrences(schedule: Schedule, start: number, days: number): number[] {
  const out: number[] = [];
  const end = start + days;
  const add = (day: number) => {
    if (day >= start && day < end) out.push(day - start);
  };
  switch (schedule.every) {
    case 'day':
      for (let d = 0; d < days; d++) out.push(d);
      break;
    case 'once':
      add(schedule.from);
      break;
    case 'week':
    case 'fortnight': {
      const step = schedule.every === 'week' ? 7 : 14;
      let d = schedule.from;
      if (d < start) d += Math.ceil((start - d) / step) * step;
      for (; d < end; d += step) add(d);
      break;
    }
    case 'month':
    case 'quarter':
    case 'year': {
      const first = ymd(start);
      const anchor = schedule.every === 'month' ? null : ymd(schedule.from);
      const stepMonths = schedule.every === 'quarter' ? 3 : schedule.every === 'year' ? 12 : 1;
      // Walk month by month from a little before the window; months that don't fit the
      // step (counted from the anchor's month) are skipped.
      for (let k = -12; k <= Math.ceil(days / 28) + 1; k++) {
        const total = first.y * 12 + (first.m - 1) + k;
        const y = Math.floor(total / 12);
        const m = (total % 12) + 1;
        let dom: number;
        if (anchor) {
          const since = total - (anchor.y * 12 + anchor.m - 1);
          if (since < 0 || since % stepMonths !== 0) continue;
          dom = anchor.d;
        } else {
          dom = (schedule as { on: number }).on;
        }
        add(dayOf(y, m, Math.min(dom, daysInMonth(y, m))));
      }
      break;
    }
  }
  return out.sort((a, b) => a - b);
}

export interface Forecast {
  low: number[]; // lowest balance each day (cents), after payments and before pay
  close: number[]; // balance at the end of each day
  lowTide: number; // the lowest of all
  lowDay: number; // offset of the first day it happens
}

// Cents flowing in and out on each day, for a list of items.
export function flows(items: Item[], plan: Plan): { out: number[]; in: number[] } {
  const out = new Array<number>(plan.days).fill(0);
  const income = new Array<number>(plan.days).fill(0);
  for (const it of items) {
    for (const d of occurrences(it.schedule, plan.start, plan.days)) {
      if (it.kind === 'income') income[d]! += it.cents;
      else out[d]! += it.cents;
    }
  }
  return { out, in: income };
}

export function forecast(plan: Plan, items: Item[] = plan.items): Forecast {
  const f = flows(items, plan);
  const low: number[] = [];
  const close: number[] = [];
  let balance = plan.balance;
  let lowTide = Infinity;
  let lowDay = 0;
  for (let d = 0; d < plan.days; d++) {
    balance -= f.out[d]!;
    low.push(balance);
    if (balance < lowTide) {
      lowTide = balance;
      lowDay = d;
    }
    balance += f.in[d]!;
    close.push(balance);
  }
  return { low, close, lowTide, lowDay };
}
