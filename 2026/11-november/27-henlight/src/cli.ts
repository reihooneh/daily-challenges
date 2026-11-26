// Putting it together: settings in, a timer plan out.
import { Config, ConfigError, check, parseFlags, readConfigFile } from './config.js';
import { Day, clockDay, hhmm, hm } from './sun.js';
import { NoSettingError, Segment, plan, totalLight } from './plan.js';

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const dateText = (d: Date): string => `${d.getUTCDate()} ${MONTHS[d.getUTCMonth()]}`;

export function seasonDays(c: Config): Day[] {
  const [fm, fd] = c.from.split('-').map(Number) as [number, number];
  const [tm, td] = c.to.split('-').map(Number) as [number, number];
  const out: Day[] = [];
  for (let t = Date.UTC(c.year, fm - 1, fd); t <= Date.UTC(c.year, tm - 1, td); t += 86400000) {
    const d = clockDay(new Date(t), c.lat, c.lon, c.utcOffset, c.dst);
    if (!d) throw new ConfigError('the sun does not rise and set every day there');
    out.push(d);
  }
  return out;
}

export interface Result {
  config: Config;
  days: Day[];
  segments: Segment[];
}

export function compute(c: Config): Result {
  const days = seasonDays(c);
  const segments = plan(days, { target: c.target * 60, most: c.most * 60, ramp: c.ramp, step: c.step });
  return { config: c, days, segments };
}

export function report(r: Result): string {
  const { config: c, days, segments } = r;
  const lines: string[] = [];
  const first = days[0]!, last = days[days.length - 1]!;
  lines.push(`Henlight: ${c.name} (${c.lat.toFixed(2)}, ${c.lon.toFixed(2)}), ${dateText(first.date)} to ${dateText(last.date)} ${c.year}`);
  lines.push(`At least ${hm(c.target * 60)} of light, at most ${hm(c.most * 60)}, ramping up ${c.ramp} min a week; timer pins every ${c.step} min.`);
  lines.push(`Daylight goes from ${hm(first.set - first.rise)} to a low of ${hm(Math.min(...days.map((d) => d.set - d.rise)))}.`);
  lines.push('');
  const changes = segments.length;
  lines.push(`Set the timer ${changes} time${changes === 1 ? '' : 's'} this season:`);
  for (const s of segments) {
    const a = days[s.from]!, b = days[s.to]!;
    const span = `${dateText(a.date).padStart(6)} to ${dateText(b.date).padEnd(6)}`;
    const tot = days.slice(s.from, s.to + 1).map((d) => totalLight(d, s.setting));
    const range = `${hm(Math.min(...tot))} to ${hm(Math.max(...tot))} of light`;
    const what = s.setting.off ? 'lamp off (daylight is enough)  ' : `on ${hhmm(s.setting.on)}, off ${hhmm(s.setting.until)}      `;
    const dst = a.dst !== days[Math.max(0, s.from - 1)]!.dst ? '  (clocks changed)' : '';
    lines.push(`  ${span}  ${what}${range}${dst}`);
  }
  const lampMinutes = segments.reduce((t, s) => t + s.lampMinutes, 0);
  const kwh = (lampMinutes / 60) * (c.watts / 1000);
  lines.push('');
  lines.push(`The ${c.watts} W lamp runs ${Math.round(lampMinutes / 60)} hours over the season: ${kwh.toFixed(1)} kWh, about $${(kwh * c.price).toFixed(2)}.`);
  lines.push('');
  lines.push('Light each week (█ daylight, ▒ lamp; one block is 30 min, from 8 h):');
  for (let i = 0; i < days.length; i += 7) {
    const d = days[i]!;
    const s = segments.find((g) => g.from <= i && i <= g.to)!;
    const natural = d.set - d.rise, total = totalLight(d, s.setting);
    const blocks = (m: number): number => Math.max(0, Math.round((m - 480) / 30));
    const bar = '█'.repeat(blocks(natural)) + '▒'.repeat(Math.max(0, blocks(total) - blocks(natural)));
    lines.push(`  ${dateText(d.date).padStart(6)}  ${bar.padEnd(22)} ${hm(total)}`);
  }
  return lines.join('\n');
}

const USAGE = `usage: henlight [settings.json] [--key value ...]
  --name    place name                       (Sydney)
  --lat --lon  latitude and longitude, degrees (-33.87, 151.21)
  --utcOffset  standard time offset, hours     (10)
  --dst     none | au | eu | us              (au)
  --year --from --to   season, dates as MM-DD (2026, 03-01, 09-30)
  --target  hours of light to keep           (14)
  --most    most hours of light              (15)
  --ramp    minutes added a week at first    (30)
  --step    timer pin spacing: 5, 10, 15, 30 (15)
  --watts --price   lamp watts and $/kWh     (9, 0.33)`;

/** Runs the command line; returns the text to print and the exit code. */
export function run(args: string[]): { out: string; code: number } {
  if (args.includes('--help') || args.includes('-h')) return { out: USAGE, code: 0 };
  try {
    const { file, raw } = parseFlags(args);
    const merged: Record<string, unknown> = Object.create(null);
    if (file !== null) Object.assign(merged, readConfigFile(file));
    Object.assign(merged, raw);
    return { out: report(compute(check(merged))), code: 0 };
  } catch (e) {
    if (e instanceof ConfigError) return { out: `henlight: ${e.message}\n\n${USAGE}`, code: 2 };
    if (e instanceof NoSettingError) return { out: 'henlight: no timer setting keeps the light in range on some day; try a finer timer step or a wider range (--most).', code: 1 };
    throw e;
  }
}
