//! Leafkeep: plans gongfu tea steep times so every infusion comes out the same strength.
//!
//! The leaves hold two pools of solubles: a fast one on the surface of the leaf and a slow one
//! inside it, which only opens up as the leaf unfurls in hot water. Each pool gives up its solubles
//! at a first-order rate that rises with water temperature (Arrhenius). The water in the pot cools
//! while it steeps, and the wet leaves keep some liquor back, which goes into the next cup. From the
//! strength of the first cup, Leafkeep finds how long every later steep must be to match it, and
//! says when the leaves can't reach that strength any more.

use std::fmt;

/// Gas constant, J/(mol K).
const R: f64 = 8.314;
/// Rates are quoted at this temperature (°C).
const T_REF: f64 = 95.0;
/// Integration step, seconds.
const DT: f64 = 0.25;
/// The longest steep Leafkeep will suggest, seconds.
pub const MAX_STEEP: f64 = 900.0;
/// Room temperature the pot cools towards, °C.
const ROOM: f64 = 22.0;

#[derive(Debug, Clone, PartialEq)]
pub enum Error {
    Range(&'static str, f64, f64),
    UnknownTea(String),
    UnknownVessel(String),
    Readings(String),
    TooStrong,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Error::Range(what, lo, hi) => write!(f, "{what} must be between {lo} and {hi}"),
            Error::UnknownTea(t) => write!(f, "unknown tea '{}': try green, white, oolong, black or puerh", clean(t)),
            Error::UnknownVessel(v) => write!(f, "unknown pot '{}': try gaiwan, clay or glass", clean(v)),
            Error::Readings(why) => write!(f, "readings: {why}"),
            Error::TooStrong => write!(f, "these leaves can't make a cup that strong even in {MAX_STEEP} s"),
        }
    }
}

/// Echoes user text back safely: printable characters only, and not too much of it.
pub fn clean(s: &str) -> String {
    s.chars().filter(|c| !c.is_control()).take(24).collect()
}

/// How a kind of tea gives up its solubles. These are typical figures for planning a session,
/// meant to be refined with `calibrate` for a particular tea.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Tea {
    pub name: &'static str,
    /// Grams of extractable solubles per gram of dry leaf.
    pub soluble: f64,
    /// Share of the solubles on the outside of the leaf (the fast pool).
    pub fast_share: f64,
    /// Rate constants at 95 °C, per second.
    pub k_fast: f64,
    pub k_slow: f64,
    /// Activation energy, J/mol: how much hotter water speeds things up.
    pub ea: f64,
    /// Seconds of steeping for the leaf to mostly unfurl and open the slow pool.
    pub unfurl: f64,
    /// Millilitres of liquor the wet leaves hold back, per gram of dry leaf.
    pub hold: f64,
}

pub const TEAS: [Tea; 5] = [
    Tea {
        name: "green",
        soluble: 0.30,
        fast_share: 0.30,
        k_fast: 0.030,
        k_slow: 0.0100,
        ea: 45_000.0,
        unfurl: 40.0,
        hold: 3.0,
    },
    Tea {
        name: "white",
        soluble: 0.26,
        fast_share: 0.35,
        k_fast: 0.020,
        k_slow: 0.0060,
        ea: 45_000.0,
        unfurl: 70.0,
        hold: 3.2,
    },
    Tea {
        name: "oolong",
        soluble: 0.30,
        fast_share: 0.20,
        k_fast: 0.025,
        k_slow: 0.0080,
        ea: 40_000.0,
        unfurl: 150.0,
        hold: 2.6,
    },
    Tea {
        name: "black",
        soluble: 0.32,
        fast_share: 0.30,
        k_fast: 0.035,
        k_slow: 0.0110,
        ea: 40_000.0,
        unfurl: 30.0,
        hold: 2.8,
    },
    Tea {
        name: "puerh",
        soluble: 0.34,
        fast_share: 0.25,
        k_fast: 0.030,
        k_slow: 0.0070,
        ea: 40_000.0,
        unfurl: 220.0,
        hold: 2.4,
    },
];

pub fn tea(name: &str) -> Result<Tea, Error> {
    TEAS.iter()
        .copied()
        .find(|t| t.name.eq_ignore_ascii_case(name))
        .ok_or_else(|| Error::UnknownTea(name.to_string()))
}

/// The pot: how fast the water in it cools (time constant, seconds).
pub fn vessel(name: &str) -> Result<f64, Error> {
    match name.to_ascii_lowercase().as_str() {
        "gaiwan" => Ok(480.0),
        "clay" => Ok(900.0),
        "glass" => Ok(360.0),
        _ => Err(Error::UnknownVessel(name.to_string())),
    }
}

/// One brewing session's set-up.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Brew {
    pub tea: Tea,
    pub leaf: f64,  // g
    pub water: f64, // ml per infusion
    pub temp: f64,  // °C of the water poured
    pub cool: f64,  // pot cooling time constant, s
}

impl Brew {
    pub fn new(tea: Tea, leaf: f64, water: f64, temp: f64, cool: f64) -> Result<Brew, Error> {
        check("leaf", leaf, 0.5, 30.0)?;
        check("water", water, 30.0, 500.0)?;
        check("temperature", temp, 60.0, 100.0)?;
        if tea.hold * leaf >= 0.5 * water {
            return Err(Error::Range("leaf per 100 ml of water", 0.5, 50.0 / tea.hold));
        }
        Ok(Brew {
            tea,
            leaf,
            water,
            temp,
            cool,
        })
    }

    /// Rate multiplier at a water temperature (Arrhenius, relative to 95 °C).
    fn arrhenius(&self, temp_c: f64) -> f64 {
        let t = temp_c + 273.15;
        let tr = T_REF + 273.15;
        (-self.tea.ea / R * (1.0 / t - 1.0 / tr)).exp()
    }
}

pub fn check(what: &'static str, v: f64, lo: f64, hi: f64) -> Result<f64, Error> {
    if v.is_finite() && (lo..=hi).contains(&v) {
        Ok(v)
    } else {
        Err(Error::Range(what, lo, hi))
    }
}

/// What is left in the leaves between infusions.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Leaves {
    pub fast: f64,    // mg left in the fast pool
    pub slow: f64,    // mg left in the slow pool
    pub contact: f64, // seconds steeped so far (how unfurled the leaf is)
    pub carry: f64,   // mg of solubles in the liquor the leaves held back
    pub wet: bool,    // false before the first infusion: dry leaves soak up liquor
}

impl Leaves {
    pub fn fresh(b: &Brew) -> Leaves {
        let total = b.tea.soluble * b.leaf * 1000.0;
        Leaves {
            fast: total * b.tea.fast_share,
            slow: total * (1.0 - b.tea.fast_share),
            contact: 0.0,
            carry: 0.0,
            wet: false,
        }
    }

    pub fn total(&self) -> f64 {
        self.fast + self.slow
    }
}

/// One infusion's outcome.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Cup {
    pub steep: f64,    // s
    pub strength: f64, // mg/ml in the cup
    pub volume: f64,   // ml poured out
    pub left: f64,     // share of the solubles still in the leaves
    pub end_temp: f64, // °C of the water when poured off
}

/// Steeps the leaves for `steep` seconds; returns the cup and the leaves afterwards.
pub fn infuse(b: &Brew, before: &Leaves, steep: f64) -> (Cup, Leaves) {
    let mut l = *before;
    let start_total = Leaves::fresh(b).total();
    let mut extracted = 0.0;
    let mut t = 0.0;
    let n = (steep / DT).ceil().max(1.0) as usize;
    let h = steep / n as f64;
    // Rates are integrated with the exact exponential over each small step, at the step's mid temperature.
    for _ in 0..n {
        let temp = ROOM + (b.temp - ROOM) * (-(t + h / 2.0) / b.cool).exp();
        let a = b.arrhenius(temp);
        let open = 0.15 + 0.85 * (1.0 - (-(l.contact + h / 2.0) / b.tea.unfurl).exp());
        let df = l.fast * (1.0 - (-b.tea.k_fast * a * h).exp());
        let ds = l.slow * (1.0 - (-b.tea.k_slow * a * open * h).exp());
        l.fast -= df;
        l.slow -= ds;
        extracted += df + ds;
        l.contact += h;
        t += h;
    }
    let held = b.tea.hold * b.leaf;
    let liquor = b.water + if l.wet { held } else { 0.0 }; // the water poured in, plus what the leaves held
    let mass = extracted + l.carry;
    let strength = mass / liquor;
    let volume = liquor - held; // the leaves keep `held` ml back
    l.carry = strength * held;
    l.wet = true;
    let end_temp = ROOM + (b.temp - ROOM) * (-steep / b.cool).exp();
    let cup = Cup {
        steep,
        strength,
        volume,
        left: l.total() / start_total,
        end_temp,
    };
    (cup, l)
}

/// The steep time that brings the next cup to `target` mg/ml, or None if the leaves can't.
pub fn steep_for(b: &Brew, leaves: &Leaves, target: f64) -> Option<f64> {
    if infuse(b, leaves, MAX_STEEP).0.strength < target {
        return None;
    }
    let (mut lo, mut hi) = (0.5_f64, MAX_STEEP);
    if infuse(b, leaves, lo).0.strength >= target {
        return Some(lo);
    }
    // Strength rises with steep time, so bisection finds the time to within a fraction of a second.
    for _ in 0..40 {
        let mid = 0.5 * (lo + hi);
        if infuse(b, leaves, mid).0.strength < target {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    Some(hi)
}

/// A whole session: the first infusion steeps `first` seconds; every later one is timed to match it.
#[derive(Debug, Clone, PartialEq)]
pub struct Session {
    pub target: f64,
    pub cups: Vec<Cup>,
    pub spent: bool, // true if the session ended because the leaves couldn't reach the strength
}

pub fn plan(b: &Brew, first: f64, limit: usize) -> Result<Session, Error> {
    check("first steep", first, 2.0, 300.0)?;
    let (cup, leaves) = infuse(b, &Leaves::fresh(b), first);
    plan_to(b, cup.strength, Some((cup, leaves)), limit)
}

/// A session aimed at `target` mg/ml from the first cup, optionally with the first cup already made.
pub fn plan_to(b: &Brew, target: f64, first: Option<(Cup, Leaves)>, limit: usize) -> Result<Session, Error> {
    let mut cups = Vec::new();
    let mut leaves = Leaves::fresh(b);
    if let Some((cup, after)) = first {
        cups.push(cup);
        leaves = after;
    }
    while cups.len() < limit {
        match steep_for(b, &leaves, target) {
            Some(t) => {
                let (cup, after) = infuse(b, &leaves, t);
                cups.push(cup);
                leaves = after;
            }
            None if cups.is_empty() => return Err(Error::TooStrong),
            None => {
                return Ok(Session {
                    target,
                    cups,
                    spent: true,
                })
            }
        }
    }
    Ok(Session {
        target,
        cups,
        spent: false,
    })
}

/// A refractometer reading for one infusion of a calibration session.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Reading {
    pub steep: f64,
    pub tds: f64, // percent total dissolved solids; 1 % is about 10 mg/ml
}

pub const MAX_READINGS: usize = 40;

/// Reads `steep_seconds,tds_percent` lines (a header and # comments are allowed).
pub fn parse_readings(text: &str) -> Result<Vec<Reading>, Error> {
    if text.len() > 64 * 1024 {
        return Err(Error::Readings("the file is larger than 64 KB".into()));
    }
    let mut out = Vec::new();
    for (i, line) in text.lines().enumerate() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') || (out.is_empty() && line.chars().next().is_some_and(char::is_alphabetic)) {
            continue;
        }
        let mut parts = line.split(',').map(str::trim);
        let (Some(a), Some(b), None) = (parts.next(), parts.next(), parts.next()) else {
            return Err(Error::Readings(format!("line {} should be steep_seconds,tds_percent", i + 1)));
        };
        let steep: f64 = a
            .parse()
            .map_err(|_| Error::Readings(format!("line {}: the steep time isn't a number", i + 1)))?;
        let tds: f64 = b
            .parse()
            .map_err(|_| Error::Readings(format!("line {}: the TDS isn't a number", i + 1)))?;
        check("steep time", steep, 1.0, MAX_STEEP).map_err(|e| Error::Readings(format!("line {}: {e}", i + 1)))?;
        check("TDS", tds, 0.01, 5.0).map_err(|e| Error::Readings(format!("line {}: {e}", i + 1)))?;
        out.push(Reading { steep, tds });
        if out.len() > MAX_READINGS {
            return Err(Error::Readings(format!("at most {MAX_READINGS} infusions")));
        }
    }
    if out.len() < 3 {
        return Err(Error::Readings("at least 3 infusions are needed".into()));
    }
    Ok(out)
}

/// Predicted TDS (%) for a sequence of steeps.
pub fn predict(b: &Brew, steeps: &[f64]) -> Vec<f64> {
    let mut leaves = Leaves::fresh(b);
    steeps
        .iter()
        .map(|&s| {
            let (cup, after) = infuse(b, &leaves, s);
            leaves = after;
            cup.strength / 10.0
        })
        .collect()
}

/// Fits the tea's soluble content and both rates to refractometer readings: a coarse grid over
/// log-multipliers, then two rounds of finer grids around the best point.
pub fn calibrate(b: &Brew, readings: &[Reading]) -> (Tea, f64) {
    let steeps: Vec<f64> = readings.iter().map(|r| r.steep).collect();
    let error = |t: Tea| -> f64 {
        let bb = Brew { tea: t, ..*b };
        predict(&bb, &steeps)
            .iter()
            .zip(readings)
            .map(|(p, r)| (p - r.tds).powi(2))
            .sum::<f64>()
            / readings.len() as f64
    };
    let make = |m: [f64; 3]| Tea {
        soluble: b.tea.soluble * m[0],
        k_fast: b.tea.k_fast * m[1],
        k_slow: b.tea.k_slow * m[2],
        ..b.tea
    };
    let mut best = [1.0, 1.0, 1.0];
    let mut best_err = error(make(best));
    let mut span = 1.2_f64; // natural-log half-width of the grid
    for _ in 0..4 {
        let centre = best;
        let steps = 7;
        for i in 0..steps {
            for j in 0..steps {
                for k in 0..steps {
                    let f = |c: f64, n: usize| c * ((n as f64 / (steps - 1) as f64 * 2.0 - 1.0) * span).exp();
                    let m = [f(centre[0], i), f(centre[1], j), f(centre[2], k)];
                    if m[0] * b.tea.soluble > 0.6 {
                        continue; // more than 60 % of the leaf dissolving isn't tea
                    }
                    let e = error(make(m));
                    if e < best_err {
                        best_err = e;
                        best = m;
                    }
                }
            }
        }
        span /= 3.0;
    }
    (make(best), best_err.sqrt())
}
