// Cars as rectangles on wheels: the numbers every brochure gives, and what they imply for how
// tightly the car can turn.

export interface Car {
  name: string;
  length: number;        // m, bumper to bumper
  width: number;         // m, body without mirrors
  wheelbase: number;     // m, front axle to rear axle
  frontOverhang: number; // m, front bumper to front axle
  turningCircle: number; // m, kerb-to-kerb diameter
}

export interface Derived {
  rearOverhang: number;  // m
  track: number;         // m, distance between left and right wheels (estimated)
  radius: number;        // m, turning radius of the middle of the rear axle on full lock
  curvature: number;     // 1/m, its reciprocal
}

// Approximate published figures; your own car's handbook is better.
export const PRESETS: Record<string, Car> = {
  fiat500: { name: 'Fiat 500', length: 3.571, width: 1.627, wheelbase: 2.3, frontOverhang: 0.67, turningCircle: 9.3 },
  golf: { name: 'Volkswagen Golf', length: 4.284, width: 1.789, wheelbase: 2.636, frontOverhang: 0.88, turningCircle: 10.9 },
  corolla: { name: 'Toyota Corolla hatch', length: 4.375, width: 1.79, wheelbase: 2.64, frontOverhang: 0.93, turningCircle: 10.4 },
  cx5: { name: 'Mazda CX-5', length: 4.55, width: 1.84, wheelbase: 2.7, frontOverhang: 0.95, turningCircle: 11.0 },
  model3: { name: 'Tesla Model 3', length: 4.694, width: 1.849, wheelbase: 2.875, frontOverhang: 0.85, turningCircle: 11.6 },
  ranger: { name: 'Ford Ranger dual cab', length: 5.37, width: 1.918, wheelbase: 3.27, frontOverhang: 0.95, turningCircle: 12.9 },
};

export class CarError extends Error {}

const LIMITS: Record<Exclude<keyof Car, 'name'>, [number, number]> = {
  length: [2, 7],
  width: [1.2, 2.6],
  wheelbase: [1.5, 4.5],
  frontOverhang: [0.3, 1.6],
  turningCircle: [7, 18],
};

export function derive(c: Car): Derived {
  const rearOverhang = c.length - c.wheelbase - c.frontOverhang;
  // The wheels sit a little inside the body.
  const track = c.width - 0.2;
  // The turning circle is traced by the outer front wheel: radius² = wheelbase² + (rear axle
  // centre radius + half the track)².
  const outer = c.turningCircle / 2;
  const radius = Math.sqrt(outer * outer - c.wheelbase * c.wheelbase) - track / 2;
  return { rearOverhang, track, radius, curvature: 1 / radius };
}

// Checks a car, whether built in or read from a file.
export function checkCar(c: Car): Car {
  for (const [k, [lo, hi]] of Object.entries(LIMITS) as [keyof typeof LIMITS, [number, number]][]) {
    const v = c[k];
    if (typeof v !== 'number' || !Number.isFinite(v) || v < lo || v > hi) {
      throw new CarError(`${k} should be a number of metres between ${lo} and ${hi}.`);
    }
  }
  const d = derive(c);
  if (d.rearOverhang < 0.2) throw new CarError('The wheelbase and front overhang leave too little car behind the rear axle.');
  if (!(d.radius > c.width / 2 + 0.3)) throw new CarError('That turning circle is too tight for that wheelbase.');
  return c;
}

const KEYS = ['name', 'length', 'width', 'wheelbase', 'frontOverhang', 'turningCircle'];
export const MAX_FILE = 4096;

// Reads a car from JSON text: only these keys, plain numbers, a short plain name.
export function parseCar(text: string): Car {
  if (text.length > MAX_FILE) throw new CarError('A car file is at most 4 KB.');
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    throw new CarError("The car file isn't valid JSON.");
  }
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw) || Object.getPrototypeOf(raw) !== Object.prototype) {
    throw new CarError('The car file should be one JSON object.');
  }
  const o = raw as Record<string, unknown>;
  for (const k of Object.keys(o)) {
    if (!KEYS.includes(k)) throw new CarError("The car file has a field Kerbtuck doesn't know.");
  }
  const name = o.name ?? 'Your car';
  if (typeof name !== 'string' || !/^[A-Za-z0-9 .,'()&-]{1,40}$/.test(name)) {
    throw new CarError('The name uses letters, numbers, spaces and simple punctuation (40 characters at most).');
  }
  return checkCar({
    name,
    length: o.length as number,
    width: o.width as number,
    wheelbase: o.wheelbase as number,
    frontOverhang: o.frontOverhang as number,
    turningCircle: o.turningCircle as number,
  });
}
