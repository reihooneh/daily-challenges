//! Automatic tuning by "twiddle" (coordinate ascent).
//!
//! No calculus and no model of the plant: just try nudging one gain up, then
//! down, keep whichever change made the response better, and shrink the
//! nudge when neither helps. It is what a person does at the workbench,
//! only faster and without getting bored.

use crate::metrics::cost;
use crate::pid::{Gains, MAX_GAIN};
use crate::sim::{simulate, Setup};

/// Hard cap on simulations, so tuning always finishes.
pub const MAX_EVALUATIONS: usize = 400;

#[derive(Debug, Clone, Copy)]
pub struct Tuned {
    pub gains: Gains,
    pub cost_before: f64,
    pub cost_after: f64,
    pub evaluations: usize,
}

pub fn tune(start: &Setup) -> Tuned {
    let mut gains = [start.gains.kp, start.gains.ki, start.gains.kd];
    // First nudges: half of each gain, or a small fixed amount if it is zero.
    let mut nudges = [
        (gains[0] * 0.5).max(0.5),
        (gains[1] * 0.5).max(0.2),
        (gains[2] * 0.5).max(0.1),
    ];
    let mut evaluations = 0;

    let evaluate = |g: &[f64; 3], evaluations: &mut usize| -> f64 {
        *evaluations += 1;
        let setup = Setup {
            gains: Gains {
                kp: g[0],
                ki: g[1],
                kd: g[2],
            },
            ..*start
        };
        cost(&simulate(&setup))
    };

    let cost_before = evaluate(&gains, &mut evaluations);
    let mut best = cost_before;

    'search: while nudges.iter().sum::<f64>() > 1e-3 {
        for i in 0..3 {
            if evaluations + 2 > MAX_EVALUATIONS {
                break 'search;
            }
            let original = gains[i];

            gains[i] = (original + nudges[i]).min(MAX_GAIN);
            let up = evaluate(&gains, &mut evaluations);
            if up < best {
                best = up;
                nudges[i] *= 1.1; // that worked: be a bit bolder next time
                continue;
            }

            gains[i] = (original - nudges[i]).max(0.0);
            let down = evaluate(&gains, &mut evaluations);
            if down < best {
                best = down;
                nudges[i] *= 1.1;
                continue;
            }

            gains[i] = original; // neither helped: go back and be more careful
            nudges[i] *= 0.5;
        }
    }

    Tuned {
        gains: Gains {
            kp: gains[0],
            ki: gains[1],
            kd: gains[2],
        },
        cost_before,
        cost_after: best,
        evaluations,
    }
}
