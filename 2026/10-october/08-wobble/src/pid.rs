//! The PID controller: three simple ideas added together.
//!
//! * **P**roportional: push in proportion to how far off you are right now.
//! * **I**ntegral: keep adding up the error, so a small leftover error
//!   eventually gets a big enough push to remove it.
//! * **D**erivative: push against how fast things are changing, like a brake.

/// The three tuning numbers.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Gains {
    pub kp: f64,
    pub ki: f64,
    pub kd: f64,
}

/// Largest gain accepted. Far beyond anything useful for the built-in plants.
pub const MAX_GAIN: f64 = 10_000.0;

impl Gains {
    /// Gains must be finite and between 0 and [`MAX_GAIN`].
    pub fn is_valid(&self) -> bool {
        [self.kp, self.ki, self.kd]
            .iter()
            .all(|g| g.is_finite() && (0.0..=MAX_GAIN).contains(g))
    }
}

#[derive(Debug, Clone)]
pub struct Pid {
    gains: Gains,
    /// The actuator cannot push harder than this in either direction.
    limit: f64,
    integral: f64,
    previous_measurement: Option<f64>,
}

impl Pid {
    pub fn new(gains: Gains, limit: f64) -> Pid {
        Pid {
            gains,
            limit,
            integral: 0.0,
            previous_measurement: None,
        }
    }

    /// Returns `(effort, saturated)`: the control effort to apply, and whether
    /// the actuator limit cut it short.
    pub fn update(&mut self, setpoint: f64, measurement: f64, dt: f64) -> (f64, bool) {
        let error = setpoint - measurement;

        // Derivative of the MEASUREMENT, not of the error. They are the same
        // while the setpoint is constant, but when the setpoint jumps the
        // error jumps too, and its derivative would be an enormous spike
        // ("derivative kick"). The measurement never jumps.
        let rate = match self.previous_measurement {
            Some(previous) => (measurement - previous) / dt,
            None => 0.0,
        };
        self.previous_measurement = Some(measurement);

        let candidate_integral = self.integral + error * dt;
        let unclamped =
            self.gains.kp * error + self.gains.ki * candidate_integral - self.gains.kd * rate;
        let effort = unclamped.clamp(-self.limit, self.limit);
        let saturated = effort != unclamped;

        // Anti-windup: while the actuator is flat out, only let the integral
        // change if that would bring it back from the limit. Otherwise it
        // "winds up" to a huge value and causes a long overshoot afterwards.
        if !saturated
            || (unclamped > self.limit && error < 0.0)
            || (unclamped < -self.limit && error > 0.0)
        {
            self.integral = candidate_integral;
        }
        (effort, saturated)
    }
}
