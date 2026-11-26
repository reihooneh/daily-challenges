// Sunrise and sunset, and the clock on the wall.
//
// The sun: the NOAA solar calculator's approximation (equation of time and declination as Fourier
// series in the fractional year), good to a minute or two between 60° south and 60° north. Sunrise
// and sunset are when the sun's centre is 0.833° below the horizon (refraction plus its radius).
//
// The clock: a plug-in timer runs on local clock time, so daylight saving moves sunrise by an hour
// against its pins overnight. Days are whole calendar dates; the switch happens at 2 or 3 am, before
// any coop light comes on, so each date has one offset.

export type DstRule = 'none' | 'au' | 'eu' | 'us';
export const DST_RULES: readonly DstRule[] = ['none', 'au', 'eu', 'us'];

const RAD = Math.PI / 180;

/** Day of the year, 1 to 366, for a UTC date. */
export function dayOfYear(date: Date): number {
  const start = Date.UTC(date.getUTCFullYear(), 0, 1);
  return Math.floor((date.getTime() - start) / 86400000) + 1;
}

/** Sunrise and sunset in minutes after midnight UTC on that date, or null in polar day or night. */
export function sunTimesUtc(date: Date, lat: number, lon: number): { rise: number; set: number } | null {
  const year = date.getUTCFullYear();
  const leap = (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
  const g = ((2 * Math.PI) / (leap ? 366 : 365)) * (dayOfYear(date) - 1); // fractional year at noon-ish
  const eqtime =
    229.18 *
    (0.000075 + 0.001868 * Math.cos(g) - 0.032077 * Math.sin(g) - 0.014615 * Math.cos(2 * g) - 0.040849 * Math.sin(2 * g));
  const decl =
    0.006918 - 0.399912 * Math.cos(g) + 0.070257 * Math.sin(g) - 0.006758 * Math.cos(2 * g) +
    0.000907 * Math.sin(2 * g) - 0.002697 * Math.cos(3 * g) + 0.00148 * Math.sin(3 * g);
  const cosHa = Math.cos(90.833 * RAD) / (Math.cos(lat * RAD) * Math.cos(decl)) - Math.tan(lat * RAD) * Math.tan(decl);
  if (cosHa < -1 || cosHa > 1) return null;
  const ha = Math.acos(cosHa) / RAD; // degrees
  return { rise: 720 - 4 * (lon + ha) - eqtime, set: 720 - 4 * (lon - ha) - eqtime };
}

/** The UTC date of the n-th given weekday (0 = Sunday) of a month; n = -1 for the last. */
function nthWeekday(year: number, month: number, weekday: number, n: number): number {
  if (n > 0) {
    const first = new Date(Date.UTC(year, month, 1)).getUTCDay();
    return Date.UTC(year, month, 1 + ((weekday - first + 7) % 7) + 7 * (n - 1));
  }
  const lastDay = new Date(Date.UTC(year, month + 1, 0));
  const back = (lastDay.getUTCDay() - weekday + 7) % 7;
  return Date.UTC(year, month, lastDay.getUTCDate() - back);
}

/** Whether daylight saving is in force on that (local) date. */
export function isDst(date: Date, rule: DstRule): boolean {
  const y = date.getUTCFullYear();
  const t = Date.UTC(y, date.getUTCMonth(), date.getUTCDate());
  switch (rule) {
    case 'au': // first Sunday in October until the first Sunday in April
      return t >= nthWeekday(y, 9, 0, 1) || t < nthWeekday(y, 3, 0, 1);
    case 'eu': // last Sunday in March until the last Sunday in October
      return t >= nthWeekday(y, 2, 0, -1) && t < nthWeekday(y, 9, 0, -1);
    case 'us': // second Sunday in March until the first Sunday in November
      return t >= nthWeekday(y, 2, 0, 2) && t < nthWeekday(y, 10, 0, 1);
    default:
      return false;
  }
}

export interface Day {
  date: Date;
  /** Sunrise and sunset on the wall clock, minutes after midnight. */
  rise: number;
  set: number;
  dst: boolean;
}

/** Sunrise and sunset on the local clock for one date. */
export function clockDay(date: Date, lat: number, lon: number, utcOffsetHours: number, rule: DstRule): Day | null {
  const t = sunTimesUtc(date, lat, lon);
  if (!t) return null;
  const dst = isDst(date, rule);
  const shift = (utcOffsetHours + (dst ? 1 : 0)) * 60;
  return { date, rise: t.rise + shift, set: t.set + shift, dst };
}

export const hhmm = (minutes: number): string => {
  const m = Math.round(minutes);
  const h = Math.floor(m / 60), r = ((m % 60) + 60) % 60;
  return `${String(h).padStart(2, '0')}:${String(r).padStart(2, '0')}`;
};

export const hm = (minutes: number): string => {
  const m = Math.round(minutes);
  return `${Math.floor(m / 60)} h ${String(m % 60).padStart(2, '0')} m`;
};
