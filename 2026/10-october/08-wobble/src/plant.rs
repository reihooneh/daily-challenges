//! The "plant" is control-engineering language for the thing you are trying
//! to control. Each one is a small differential equation: given where it is
//! now and how hard it is being pushed, how fast does it change?

/// The built-in plants.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    /// A wheel motor under speed control. Push harder, spin faster, with a lag.
    Motor,
    /// A robot arm joint under position control. It has inertia, so it coasts.
    Arm,
    /// A heater. Slow, and it reacts late (the heat has to travel).
    Heater,
}

impl Kind {
    pub const ALL: [Kind; 3] = [Kind::Motor, Kind::Arm, Kind::Heater];

    pub fn parse(name: &str) -> Option<Kind> {
        match name {
            "motor" => Some(Kind::Motor),
            "arm" => Some(Kind::Arm),
            "heater" => Some(Kind::Heater),
            _ => None,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Kind::Motor => "motor",
            Kind::Arm => "arm",
            Kind::Heater => "heater",
        }
    }

    pub fn describe(self) -> &'static str {
        match self {
            Kind::Motor => "wheel motor, speed control (first-order lag, 0.3 s time constant)",
            Kind::Arm => "robot arm joint, position control (inertia plus friction)",
            Kind::Heater => "heater, temperature control (slow, with a 0.5 s delay)",
        }
    }

    /// A sensible length of simulation for this plant, in seconds.
    pub fn default_duration(self) -> f64 {
        match self {
            Kind::Motor => 3.0,
            Kind::Arm => 5.0,
            Kind::Heater => 30.0,
        }
    }
}

/// How many past control values the heater remembers (its dead time).
const DELAY_STEPS: usize = 500; // 0.5 s at the simulator's 1 ms step

/// The state of a plant at one instant.
#[derive(Debug, Clone)]
pub struct Plant {
    kind: Kind,
    /// What the sensor reads: speed, angle or temperature.
    pub output: f64,
    /// Rate of change of the output (used by the arm).
    velocity: f64,
    /// Recent control values, for the heater's delay.
    pipeline: Vec<f64>,
    cursor: usize,
}

impl Plant {
    pub fn new(kind: Kind) -> Plant {
        Plant {
            kind,
            output: 0.0,
            velocity: 0.0,
            pipeline: vec![0.0; DELAY_STEPS],
            cursor: 0,
        }
    }

    /// Advances the plant by `dt` seconds with control effort `u` applied.
    ///
    /// The motor and heater have exact solutions for a constant push over one
    /// step, so those are used directly. The arm uses the semi-implicit Euler
    /// method (update velocity first, then position), which stays stable for
    /// oscillating systems where the plain Euler method slowly gains energy.
    pub fn step(&mut self, u: f64, dt: f64) {
        match self.kind {
            Kind::Motor => {
                // tau * dy/dt = gain*u - y
                let (gain, tau) = (1.0, 0.3);
                let target = gain * u;
                self.output = target + (self.output - target) * (-dt / tau).exp();
            }
            Kind::Arm => {
                // inertia * angle'' = u - friction * angle'
                let (inertia, friction) = (0.5, 0.8);
                let acceleration = (u - friction * self.velocity) / inertia;
                self.velocity += acceleration * dt;
                self.output += self.velocity * dt;
            }
            Kind::Heater => {
                // The control value takes DELAY_STEPS steps to reach the heater.
                let delayed = self.pipeline[self.cursor];
                self.pipeline[self.cursor] = u;
                self.cursor = (self.cursor + 1) % DELAY_STEPS;
                let (gain, tau) = (2.0, 4.0);
                let target = gain * delayed;
                self.output = target + (self.output - target) * (-dt / tau).exp();
            }
        }
    }
}
