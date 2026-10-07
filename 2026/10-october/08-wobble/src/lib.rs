//! Wobble: simulate a PID control loop, measure how it behaves, and explain
//! what to change.
//!
//! The library is split the way a real control loop is:
//!
//! * [`plant`]   — the thing being controlled (a motor, a robot arm, a heater)
//! * [`pid`]     — the controller that decides how hard to push
//! * [`sim`]     — runs the two against each other through time
//! * [`metrics`] — measures the result: overshoot, settling time and so on
//! * [`advice`]  — turns the measurements into plain-language suggestions
//! * [`tune`]    — searches for better gains automatically
//! * [`plot`]    — draws the response as text

pub mod advice;
pub mod metrics;
pub mod pid;
pub mod plant;
pub mod plot;
pub mod sim;
pub mod tune;
