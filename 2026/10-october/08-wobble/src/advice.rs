//! Turns measurements into advice a person can act on.
//!
//! These are the rules of thumb every robotics team learns the hard way,
//! written down as code. Each rule looks at the metrics and, if it applies,
//! says what is happening and which gain to change.

use crate::metrics::Metrics;
use crate::pid::Gains;

pub fn advise(metrics: &Metrics, gains: &Gains) -> Vec<String> {
    let mut advice = Vec::new();

    if metrics.diverged || metrics.growing {
        advice.push(format!(
            "UNSTABLE: the swings are getting bigger, not smaller. Halve Kp (try {:.3}){}.",
            gains.kp / 2.0,
            if gains.ki > 0.0 { " and reduce Ki" } else { "" }
        ));
        if gains.kd == 0.0 {
            advice.push("Add some Kd: it acts like a brake and calms oscillation.".to_string());
        }
        return advice; // nothing else is worth saying about an unstable loop
    }

    if metrics.rise_time.is_none() {
        if gains.ki == 0.0 && metrics.steady_state_error_percent > 2.0 {
            advice.push(format!(
                "It stops {:.0}% short of the target and stays there. Proportional control alone cannot hold \
                 this load: add Ki so the leftover error builds up into enough push.",
                metrics.steady_state_error_percent
            ));
        } else {
            advice.push(
                "It never gets close to the target in this time. Increase Kp, or run for longer."
                    .to_string(),
            );
        }
    } else if metrics.steady_state_error_percent > 2.0 {
        if gains.ki == 0.0 {
            advice.push(format!(
                "It settles {:.1}% away from the target. Add Ki to remove a steady error like this.",
                metrics.steady_state_error_percent
            ));
        } else {
            advice.push(format!(
                "Still {:.1}% off at the end. Increase Ki, or run for longer to see whether it gets there.",
                metrics.steady_state_error_percent
            ));
        }
    }

    if metrics.overshoot_percent > 25.0 {
        advice.push(format!(
            "It overshoots the target by {:.0}%. {}",
            metrics.overshoot_percent,
            if gains.kd == 0.0 {
                "Add Kd to brake before it arrives, or reduce Kp."
            } else {
                "Increase Kd, or reduce Kp."
            }
        ));
        if gains.ki > 0.0 && metrics.saturated_percent > 20.0 {
            advice.push(
                "Some of that overshoot is the integral term still pushing after a long time at the actuator limit. \
                 Reduce Ki."
                    .to_string(),
            );
        }
    } else if metrics.overshoot_percent > 10.0 {
        advice.push(format!(
            "A {:.0}% overshoot: fine for a drivetrain, too much for an arm near a hard stop. A little more Kd would trim it.",
            metrics.overshoot_percent
        ));
    }

    if metrics.crossings >= 5 {
        advice.push(format!(
            "It swings back through the target {} times before calming down. More Kd (or less Kp) will damp the ringing.",
            metrics.crossings
        ));
    }

    if metrics.saturated_percent > 30.0 {
        advice.push(format!(
            "The actuator is flat out for {:.0}% of the run. Past this point higher gains cannot make it faster: \
                 the limit is the hardware, not the tuning.",
            metrics.saturated_percent
        ));
    }

    if metrics.settling_time.is_none() && advice.is_empty() {
        advice.push("It has not settled within 2% of the target by the end. Run for longer, or raise Kp a little.".to_string());
    }

    if advice.is_empty() {
        advice
            .push("Looks good: quick, little overshoot, and it settles on the target.".to_string());
    }
    advice
}
