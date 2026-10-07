//! Runs a controller against a plant and records what happens.

use crate::pid::{Gains, Pid};
use crate::plant::{Kind, Plant};

/// Simulation time step: 1 millisecond, typical of a small robot's control loop.
pub const DT: f64 = 0.001;
/// Longest simulation allowed, which bounds the work at 120,000 steps.
pub const MAX_DURATION: f64 = 120.0;
/// Outputs beyond this multiple of the setpoint mean the loop has run away.
const RUNAWAY: f64 = 1.0e6;

#[derive(Debug, Clone, Copy)]
pub struct Setup {
    pub plant: Kind,
    pub gains: Gains,
    pub setpoint: f64,
    pub duration: f64,
    /// Actuator limit (the most the controller is able to push).
    pub limit: f64,
}

#[derive(Debug, Clone)]
pub struct Run {
    pub setpoint: f64,
    /// Sensor reading at every step.
    pub output: Vec<f64>,
    /// How many steps the actuator spent at its limit.
    pub saturated_steps: usize,
    /// True if the output grew without bound and the run was stopped early.
    pub diverged: bool,
}

/// Simulates a step change: the setpoint jumps from 0 to `setup.setpoint` at t = 0.
pub fn simulate(setup: &Setup) -> Run {
    let steps = (setup.duration.clamp(DT, MAX_DURATION) / DT).round() as usize;
    let mut plant = Plant::new(setup.plant);
    let mut pid = Pid::new(setup.gains, setup.limit);
    let mut run = Run {
        setpoint: setup.setpoint,
        output: Vec::with_capacity(steps),
        saturated_steps: 0,
        diverged: false,
    };

    for _ in 0..steps {
        let (effort, saturated) = pid.update(setup.setpoint, plant.output, DT);
        plant.step(effort, DT);
        if saturated {
            run.saturated_steps += 1;
        }
        if !plant.output.is_finite() || plant.output.abs() > RUNAWAY * setup.setpoint.abs().max(1.0)
        {
            run.diverged = true;
            break;
        }
        run.output.push(plant.output);
    }
    run
}
