//! Which lights in a list are easy to mix up? Simulates many watchers timing each light (each
//! with a real light whose flash lengths differ from the model, a random reaction time, a
//! stopwatch or counted seconds, and the odd missed flash), identifies every simulated watch
//! against the whole list, and counts the mistakes.

use crate::fit::{identify, scale_sd, JITTER};
use crate::input::{Named, Timing, Watch};
use crate::pattern::{build, Class, Kind, Light};
use crate::rng::Rng;

pub const MAX_SIMS: usize = 5000;
const P_MISS: f64 = 0.05;

#[derive(Clone, Debug)]
pub struct Confusion {
    pub light: usize,
    pub sims: usize,
    pub right: usize,
    /// Other lights it was taken for, and how often, most often first.
    pub mistaken: Vec<(usize, usize)>,
}

/// One simulated watch of `light`, as a watcher would write it down.
pub fn simulate(light: &Light, timing: Timing, rng: &mut Rng) -> Watch {
    let spec = &light.spec;
    let edges = build(spec, Some(&mut *rng)).unwrap_or_else(|_| light.edges.clone());
    let period = spec.period * (1.0 + light.period_tol / 2.0 * rng.normal().clamp(-2.0, 2.0));
    let scale = 1.0 + scale_sd(timing) * rng.normal().clamp(-2.5, 2.5);
    // Watchers time the eclipses of an occulting light, and the flashes of the rest.
    let kind = if spec.class == Class::Occulting { Kind::Off } else { Kind::On };
    let start = rng.uniform() * period;
    let mut span = (2.5 * period).max(15.0);
    loop {
        let mut events: Vec<(f64, Kind)> = Vec::new();
        let mut k = 0.0;
        while k * period - start <= span {
            for e in edges.iter().filter(|e| e.kind == kind) {
                let t = k * period + e.t - start;
                if (0.0..=span).contains(&t) && rng.uniform() >= P_MISS {
                    events.push((1.0 + scale * t + JITTER * rng.normal(), kind));
                }
            }
            k += 1.0;
        }
        events.sort_by(|a, b| a.0.total_cmp(&b.0));
        for i in 1..events.len() {
            if events[i].0 <= events[i - 1].0 {
                events[i].0 = events[i - 1].0 + 0.01;
            }
        }
        if events.len() >= 3 {
            let window = Some((1.0, 1.0 + scale * span));
            return Watch {
                timing,
                colour: spec.colours.first().copied(),
                events,
                window,
            };
        }
        span *= 2.0;
    }
}

/// Simulates `sims` watches of every light in the list and identifies each against the list.
/// Lights are shared between threads; each light has its own seeded generator, so the result
/// doesn't depend on how many threads ran.
pub fn audit(lights: &[Named], timing: Timing, sims: usize, seed: u64) -> Vec<Confusion> {
    let threads = std::thread::available_parallelism().map_or(1, |n| n.get()).clamp(1, 8);
    let mut out: Vec<Confusion> = std::thread::scope(|scope| {
        let handles: Vec<_> = (0..threads)
            .map(|t| {
                scope.spawn(move || {
                    (t..lights.len())
                        .step_by(threads)
                        .map(|i| audit_one(lights, i, timing, sims, seed))
                        .collect::<Vec<_>>()
                })
            })
            .collect();
        handles.into_iter().flat_map(|h| h.join().unwrap_or_default()).collect()
    });
    out.sort_by_key(|c| c.light);
    out
}

fn audit_one(lights: &[Named], i: usize, timing: Timing, sims: usize, seed: u64) -> Confusion {
    let mut rng = Rng::new(seed.wrapping_mul(1_000_003).wrapping_add(i as u64));
    let mut c = Confusion {
        light: i,
        sims: 0,
        right: 0,
        mistaken: vec![],
    };
    if lights[i].light.spec.class == Class::Fixed {
        return c; // a fixed light has no rhythm to time
    }
    let mut wrong = vec![0usize; lights.len()];
    for _ in 0..sims {
        let w = simulate(&lights[i].light, timing, &mut rng);
        c.sims += 1;
        match identify(lights, &w).first() {
            Some(r) if r.index == i => c.right += 1,
            Some(r) => wrong[r.index] += 1,
            None => {}
        }
    }
    c.mistaken = wrong
        .iter()
        .enumerate()
        .filter(|(_, &k)| k > 0)
        .map(|(j, &k)| (j, k))
        .collect();
    c.mistaken.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    c
}

/// The longest time the light stays on in one period (a fixed light: forever).
pub fn longest_on(light: &Light) -> f64 {
    let e = &light.edges;
    let p = light.spec.period;
    if e.is_empty() {
        return f64::INFINITY;
    }
    (0..e.len())
        .filter(|&k| e[k].kind == Kind::On)
        .map(|k| {
            let next = &e[(k + 1) % e.len()];
            if k + 1 < e.len() {
                next.t - e[k].t
            } else {
                next.t + p - e[k].t
            }
        })
        .fold(0.0, f64::max)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::input;

    #[test]
    fn simulated_watches_are_valid_input() {
        let l = crate::pattern::parse("Oc(2) R 8s").unwrap();
        let mut r = Rng::new(3);
        for _ in 0..50 {
            let w = simulate(&l, Timing::Counted, &mut r);
            assert!(w.events.len() >= 3 && w.events.iter().all(|e| e.1 == Kind::Off && e.0 >= 0.0));
            assert!(w.events.windows(2).all(|p| p[0].0 < p[1].0));
            assert_eq!(w.colour, Some('R'));
        }
    }

    #[test]
    fn distinct_lights_are_told_apart_and_close_ones_are_not() {
        let lights = input::lights("A | Fl(2) 10s\nB | Fl(2) 10.5s\nC | Fl(4) 20s\nD | Iso 6s\n").unwrap();
        let a = audit(&lights, Timing::Counted, 40, 1);
        assert!(a[2].right >= 38 && a[3].right >= 38, "{a:?}");
        // 10 s and 10.5 s are 5% apart: counted seconds can't separate them.
        assert!(a[0].right < 36 && a[0].mistaken[0].0 == 1, "{a:?}");
        let s = audit(&lights, Timing::Stopwatch, 40, 1);
        assert!(s[0].right > a[0].right, "a stopwatch helps: {s:?}");
    }

    #[test]
    fn flash_lengths() {
        let on = |c: &str| longest_on(&crate::pattern::parse(c).unwrap());
        assert_eq!(on("Mo(A) 8s"), 1.5);
        assert_eq!(on("Fl(2) 9s"), 0.5);
        assert_eq!(on("Oc 4s"), 3.0);
        assert_eq!(on("Iso 6s"), 3.0);
        assert!(on("F").is_infinite());
    }
}
