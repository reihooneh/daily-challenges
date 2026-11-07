//! Comparing an observation with a light: the best line-up of the watcher's times against the
//! light's rhythm, and how likely the times are if it really is that light.
//!
//! Unknowns: the phase (when the watcher's stopwatch started, within the light's period) and
//! the scale (a stopwatch is close to right; counting seconds aloud can be 10% out). For each
//! line-up the times are paired one-to-one with the modelled edges, and scored as a likelihood:
//! a pair scores by how close it is, given the watcher's reaction time and the model's
//! uncertainty about flash lengths; a time with no edge near it is a stray click; an edge with
//! no time near it is a flash the watcher missed.

use crate::input::{Named, Timing, Watch};
use crate::pattern::{Class, Kind, Light};

/// The watcher's reaction-time spread, in seconds.
pub const JITTER: f64 = 0.25;
const P_MISS: f64 = 0.05;
/// Log density of a stray click: unlikely, but not impossible.
const LN_STRAY: f64 = -5.0;
const LN_ROOT_TAU: f64 = 0.918_938_533_204_672_8; // ln(sqrt(2*pi))

pub fn scale_sd(t: Timing) -> f64 {
    match t {
        Timing::Stopwatch => 0.02,
        Timing::Counted => 0.08,
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Fit {
    /// Log-likelihood of the times if it is this light (higher is better).
    pub ll: f64,
    /// Watcher's seconds per model second.
    pub scale: f64,
    /// Where the period starts on the watcher's clock.
    pub phase: f64,
    pub matched: usize,
    pub missed: usize,
    pub stray: usize,
    /// Root mean square of the paired differences, in seconds.
    pub rms: f64,
}

impl Fit {
    /// Every time paired, and at most one flash in ten missed.
    pub fn is_good(&self) -> bool {
        self.stray == 0 && self.missed * 10 <= self.matched.max(10)
    }
}

/// The best fit of `w` to `light`, or None if it can't be this light (wrong colour, a fixed
/// light, or no edges of the kind timed).
pub fn fit(light: &Light, w: &Watch) -> Option<Fit> {
    if light.spec.class == Class::Fixed {
        return None;
    }
    if let Some(c) = w.colour {
        if !light.spec.colours.contains(&c) {
            return None;
        }
    }
    let used = |k: Kind| w.events.iter().any(|e| e.1 == k);
    if !light.edges.iter().any(|e| used(e.kind)) {
        return None;
    }
    let sd = (scale_sd(w.timing).powi(2) + (light.period_tol / 2.0).powi(2)).sqrt();
    let steps = 40;
    let lo = 1.0 - 2.5 * sd;
    let step = 5.0 * sd / steps as f64;
    let mut best: Option<Fit> = None;
    let keep = |f: Option<Fit>, best: &mut Option<Fit>| {
        if let Some(f) = f {
            if best.is_none_or(|b| f.ll > b.ll) {
                *best = Some(f);
            }
        }
    };
    for i in 0..=steps {
        keep(best_phase(light, w, lo + step * i as f64, sd), &mut best);
    }
    let coarse = best?.scale;
    for i in -8..=8 {
        keep(best_phase(light, w, coarse + step * i as f64 / 8.0, sd), &mut best);
    }
    best
}

/// The best phase at one scale: line up each of the first few times with each edge of the
/// same kind, then try small shifts around that.
fn best_phase(light: &Light, w: &Watch, s: f64, sd: f64) -> Option<Fit> {
    let mut best: Option<Fit> = None;
    for &(ta, ka) in w.events.iter().take(3) {
        for e in light.edges.iter().filter(|e| e.kind == ka) {
            // Line up, then slide by the weighted mean of the paired differences (twice).
            let mut phase = ta - s * e.t;
            for _ in 0..3 {
                let (f, shift) = score(light, w, s, phase, sd);
                if best.is_none_or(|b| f.ll > b.ll) {
                    best = Some(f);
                }
                if shift.abs() < 0.005 {
                    break;
                }
                phase += shift;
            }
        }
    }
    best
}

/// Scores one line-up. Also returns the shift of phase that would best fit the pairs it made.
fn score(light: &Light, w: &Watch, s: f64, phase: f64, sd: f64) -> (Fit, f64) {
    let period = s * light.spec.period;
    let (first, last) = w.span();
    let has = |k: Kind| w.events.iter().any(|e| e.1 == k);
    let (has_on, has_off) = (has(Kind::On), has(Kind::Off));

    // Modelled edges near the watched span, in time order, with their total spread.
    let max_sd = light.edges.iter().map(|e| e.sd).fold(0.0, f64::max);
    let reach = 4.0 * (JITTER * JITTER + (s * max_sd).powi(2)).sqrt();
    let k0 = ((first - reach - phase) / period).floor() as i64;
    let k1 = ((last + reach - phase) / period).ceil() as i64;
    let mut model: Vec<(f64, f64, Kind)> = Vec::new();
    for k in k0..=k1 {
        for e in &light.edges {
            if (e.kind == Kind::On && has_on) || (e.kind == Kind::Off && has_off) {
                let sig = (JITTER * JITTER + (s * e.sd).powi(2)).sqrt();
                model.push((phase + k as f64 * period + s * e.t, sig, e.kind));
            }
        }
    }

    // Candidate pairs within 4 standard deviations, closest first, taken one-to-one.
    let mut pairs: Vec<(f64, usize, usize)> = Vec::new();
    for (i, &(t, kind)) in w.events.iter().enumerate() {
        let start = model.partition_point(|m| m.0 < t - reach);
        for (j, m) in model.iter().enumerate().skip(start) {
            if m.0 > t + reach {
                break;
            }
            let z = (t - m.0) / m.1;
            if m.2 == kind && z.abs() < 4.0 {
                pairs.push((z, i, j));
            }
        }
    }
    pairs.sort_by(|a, b| a.0.abs().total_cmp(&b.0.abs()));
    let mut obs_used = vec![false; w.events.len()];
    let mut mod_used = vec![false; model.len()];
    let mut ll = -0.5 * ((s - 1.0) / sd).powi(2);
    let (mut matched, mut sumsq, mut num, mut den) = (0, 0.0, 0.0, 0.0);
    for (z, i, j) in pairs {
        if obs_used[i] || mod_used[j] {
            continue;
        }
        obs_used[i] = true;
        mod_used[j] = true;
        matched += 1;
        let d = w.events[i].0 - model[j].0;
        sumsq += d * d;
        num += d / model[j].1.powi(2);
        den += 1.0 / model[j].1.powi(2);
        ll += -0.5 * z * z - model[j].1.ln() - LN_ROOT_TAU + (1.0 - P_MISS).ln();
    }
    let stray = obs_used.iter().filter(|u| !**u).count();
    ll += stray as f64 * LN_STRAY;
    let missed = model
        .iter()
        .zip(&mod_used)
        .filter(|(m, used)| !**used && m.0 >= first && m.0 <= last)
        .count();
    ll += missed as f64 * P_MISS.ln();
    let rms = if matched > 0 { (sumsq / matched as f64).sqrt() } else { 0.0 };
    let shift = if den > 0.0 { num / den } else { 0.0 };
    (
        Fit {
            ll,
            scale: s,
            phase,
            matched,
            missed,
            stray,
            rms,
        },
        shift,
    )
}

#[derive(Clone, Debug)]
pub struct Ranked {
    pub index: usize,
    pub fit: Fit,
    /// Chance it's this light, if it's one of the list and each was equally likely beforehand.
    pub prob: f64,
}

/// Every light that could have made these times, most likely first.
pub fn identify(lights: &[Named], w: &Watch) -> Vec<Ranked> {
    let mut out: Vec<Ranked> = lights
        .iter()
        .enumerate()
        .filter_map(|(i, n)| {
            fit(&n.light, w).map(|f| Ranked {
                index: i,
                fit: f,
                prob: 0.0,
            })
        })
        .collect();
    out.sort_by(|a, b| b.fit.ll.total_cmp(&a.fit.ll));
    if let Some(top) = out.first().map(|r| r.fit.ll) {
        let total: f64 = out.iter().map(|r| (r.fit.ll - top).exp()).sum();
        for r in &mut out {
            r.prob = (r.fit.ll - top).exp() / total;
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::input;

    fn named(list: &str) -> Vec<Named> {
        input::lights(list).unwrap()
    }

    const LIST: &str = "A | Fl(2) W 10s\nB | Fl(3) W 10s\nC | Fl W 5s\nD | Oc W 4s\nE | Fl(2) R 10s\nF | Q\nG | Fl(2) W 6s\n";

    #[test]
    fn group_of_two_every_ten_seconds() {
        // Two flashes, 1.6 s apart, every 10 s, with sloppy thumbs.
        let w = input::watch("3.1\n4.6\n13.0\n14.7\n23.1\n24.5\n").unwrap();
        let r = identify(&named(LIST), &w);
        // A and E have the same rhythm; without a colour they can't be told apart.
        let mut top = [r[0].index, r[1].index];
        top.sort();
        assert_eq!(top, [0, 4], "{r:?}");
        assert!((r[0].prob - 0.5).abs() < 0.01 && r[0].fit.is_good());
        assert!(r[2].prob < 0.01);
    }

    #[test]
    fn colour_rules_lights_out() {
        let w = input::watch("colour R\n3.1\n4.6\n13.0\n14.7\n").unwrap();
        let r = identify(&named(LIST), &w);
        assert_eq!(r.len(), 1);
        assert_eq!(r[0].index, 4);
    }

    #[test]
    fn counted_seconds_run_slow() {
        // Fl(2) 6s counted 12% slow: the watcher's "seconds" are longer, so numbers are smaller.
        let k = 1.0 / 1.12;
        let times: Vec<String> = [0.0, 1.5, 6.0, 7.5, 12.0, 13.5, 18.0, 19.5]
            .iter()
            .map(|t| format!("{:.2}", t * k))
            .collect();
        let stopwatch = input::watch(&times.join("\n")).unwrap();
        let counted = input::watch(&format!("timing counted\n{}", times.join("\n"))).unwrap();
        let lights = named(LIST);
        let r = identify(&lights, &counted);
        assert_eq!(lights[r[0].index].name, "G");
        assert!((r[0].fit.scale - k).abs() < 0.02, "{}", r[0].fit.scale);
        // Told it was a stopwatch, the same times fit badly.
        assert!(fit(&lights[6].light, &stopwatch).unwrap().ll < r[0].fit.ll);
    }

    #[test]
    fn a_missed_flash_and_a_stray_click() {
        let w = input::watch("0\n1.5\n11.5\n20\n21.5\n25.2\n30\n31.5\n").unwrap();
        let f = fit(&named(LIST)[0].light, &w).unwrap();
        assert_eq!((f.missed, f.stray), (1, 1));
        assert!(!f.is_good());
    }

    #[test]
    fn occulting_timed_by_eclipses() {
        let w = input::watch("0 off\n1 on\n4 off\n5 on\n8 off\n9.1 on\n").unwrap();
        let r = identify(&named(LIST), &w);
        assert_eq!(r[0].index, 3);
    }

    #[test]
    fn quick_light_rate_found() {
        let w = input::watch(
            &(0..20)
                .map(|i| format!("{:.2}", 0.4 + i as f64 * 0.85))
                .collect::<Vec<_>>()
                .join("\n"),
        )
        .unwrap();
        let lights = named(LIST);
        let r = identify(&lights, &w);
        assert_eq!(lights[r[0].index].name, "F");
        assert!((r[0].fit.scale - 0.85).abs() < 0.02, "{}", r[0].fit.scale);
    }
}
