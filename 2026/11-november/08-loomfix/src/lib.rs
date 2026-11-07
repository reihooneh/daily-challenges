//! Loomfix: identifies a lighthouse or buoy light from stopwatch timings of its flashes, and
//! finds the lights in a list that a watcher could easily mix up.

#![forbid(unsafe_code)]

pub mod audit;
pub mod fit;
pub mod input;
pub mod pattern;
pub mod render;
pub mod rng;
