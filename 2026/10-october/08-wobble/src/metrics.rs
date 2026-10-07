//! Measures a step response the way a control engineer would.

use crate::sim::{Run, DT};

#[derive(Debug, Clone, PartialEq)]
pub struct Metrics {
    /// Time to go from 10% to 90% of the setpoint. `None` if it never got there.
    pub rise_time: Option<f64>,
    /// How far past the setpoint it went, as a percentage of the setpoint.
    pub overshoot_percent: f64,
    /// Time after which it stays within 2% of the setpoint. `None` if it never settles.
    pub settling_time: Option<f64>,
    /// Remaining error at the end, as a percentage of the setpoint.
    pub steady_state_error_percent: f64,
    /// How many times it swung back through the setpoint after arriving (swings over 2% only).
    pub crossings: usize,
    /// Share of the run spent with the actuator at its limit.
    pub saturated_percent: f64,
    /// True if the swings are getting bigger instead of dying away.
    pub growing: bool,
    pub diverged: bool,
}

const SETTLE_BAND: f64 = 0.02;

pub fn measure(run: &Run) -> Metrics {
    let n = run.output.len();
    let target = run.setpoint;
    let mut metrics = Metrics {
        rise_time: None,
        overshoot_percent: 0.0,
        settling_time: None,
        steady_state_error_percent: 100.0,
        crossings: 0,
        saturated_percent: 0.0,
        growing: false,
        diverged: run.diverged,
    };
    if n == 0 || target == 0.0 {
        return metrics;
    }
    // Work with the response as a fraction of the setpoint: 1.0 is "on target".
    let fraction = |i: usize| run.output[i] / target;

    let first_10 = (0..n).find(|&i| fraction(i) >= 0.1);
    let first_90 = (0..n).find(|&i| fraction(i) >= 0.9);
    if let (Some(a), Some(b)) = (first_10, first_90) {
        metrics.rise_time = Some((b - a) as f64 * DT);
    }

    let peak = (0..n).map(fraction).fold(f64::MIN, f64::max);
    metrics.overshoot_percent = ((peak - 1.0) * 100.0).max(0.0);

    // Settling: walk backwards to the last moment it was outside the band.
    let last_outside = (0..n)
        .rev()
        .find(|&i| (fraction(i) - 1.0).abs() > SETTLE_BAND);
    metrics.settling_time = match last_outside {
        None => Some(0.0),
        Some(i) if i + 1 < n => Some((i + 1) as f64 * DT),
        Some(_) => None, // still outside at the very end
    };

    // Average the last 5% of the run so one wiggle does not decide the answer.
    let tail = (n / 20).max(1);
    let final_value = (n - tail..n).map(fraction).sum::<f64>() / tail as f64;
    metrics.steady_state_error_percent = ((1.0 - final_value) * 100.0).abs();

    // Crossings, and the size of each swing between them.
    let mut swings: Vec<f64> = Vec::new();
    let mut biggest = 0.0_f64;
    for i in 1..n {
        let (before, now) = (fraction(i - 1) - 1.0, fraction(i) - 1.0);
        biggest = biggest.max(now.abs());
        if before.signum() != now.signum() && before != 0.0 {
            // Only count a wobble if the swing before it left the 2% band;
            // microscopic ripples around the target are not worth reporting.
            if biggest > SETTLE_BAND {
                swings.push(biggest);
            }
            biggest = 0.0;
        }
    }
    // The first crossing is simply arriving at the target. Every one after
    // that is the output swinging back through it: a wobble.
    metrics.crossings = swings.len().saturating_sub(1);
    // Likewise the first "swing" is the initial approach from zero, so skip it.
    if swings.len() >= 4 {
        let early = swings[1];
        let late = swings[swings.len() - 1];
        metrics.growing = late > early * 1.05;
    }
    metrics.growing |= run.diverged;

    metrics.saturated_percent = run.saturated_steps as f64 * 100.0 / n as f64;
    metrics
}

/// A single number for "how good was that": smaller is better.
///
/// This is ITAE (the Integral of Time multiplied by Absolute Error): errors
/// that are still there late in the run cost more than errors at the start,
/// which rewards settling quickly. Overshoot is penalised on top.
pub fn cost(run: &Run) -> f64 {
    if run.diverged || run.output.is_empty() || run.setpoint == 0.0 {
        return f64::INFINITY;
    }
    let mut itae = 0.0;
    let mut peak = f64::MIN;
    for (i, &y) in run.output.iter().enumerate() {
        let fraction = y / run.setpoint;
        itae += (i as f64 * DT) * (1.0 - fraction).abs() * DT;
        peak = peak.max(fraction);
    }
    let overshoot = (peak - 1.0).max(0.0);
    let total = itae + 2.0 * overshoot * overshoot * run.output.len() as f64 * DT;
    if total.is_finite() {
        total
    } else {
        f64::INFINITY
    }
}
