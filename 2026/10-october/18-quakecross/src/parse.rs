//! The pick file: stations, their coordinates and the times the P and S waves arrived.
//!
//! ```text
//! event Practice quake
//! velocity p 6.0 s 3.5        # km/s
//! depth 8                     # fixed focal depth in km, or "depth free"
//! station NEW1 -32.92 151.78 p 03:14:07.42 s 03:14:11.90
//! station SNG  -32.56 151.18 p 03:14:09.10           # an S time is optional
//! ```

pub const MAX_BYTES: usize = 64 * 1024;
pub const MAX_LINE: usize = 200;
pub const MAX_STATIONS: usize = 200;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Phase {
    P,
    S,
}

impl Phase {
    pub fn name(self) -> &'static str {
        match self {
            Phase::P => "P",
            Phase::S => "S",
        }
    }
}

#[derive(Debug, Clone)]
pub struct Station {
    pub name: String,
    pub lat: f64,
    pub lon: f64,
}

#[derive(Debug, Clone)]
pub struct Pick {
    pub station: usize,
    pub phase: Phase,
    /// Seconds after midnight.
    pub time: f64,
    pub line: usize,
}

#[derive(Debug, Clone)]
pub struct Picks {
    pub event: String,
    pub vp: f64,
    pub vs: f64,
    /// `None` means solve for depth too.
    pub depth: Option<f64>,
    pub stations: Vec<Station>,
    pub picks: Vec<Pick>,
}

fn err(line: usize, msg: &str) -> String {
    format!("line {line}: {msg}")
}

/// Parses "HH:MM:SS.sss" into seconds after midnight.
pub fn parse_time(text: &str) -> Option<f64> {
    let mut parts = text.split(':');
    let (h, m, s) = (parts.next()?, parts.next()?, parts.next()?);
    if parts.next().is_some() || h.len() != 2 || m.len() != 2 || s.len() < 2 || s.len() > 9 {
        return None;
    }
    let all_digits = |t: &str| !t.is_empty() && t.bytes().all(|b| b.is_ascii_digit());
    let (whole, frac) = s.split_once('.').unwrap_or((s, ""));
    let frac_ok = if s.contains('.') { all_digits(frac) } else { frac.is_empty() };
    if !all_digits(h) || !all_digits(m) || whole.len() != 2 || !all_digits(whole) || !frac_ok {
        return None;
    }
    let (h, m, sec): (u32, u32, f64) = (h.parse().ok()?, m.parse().ok()?, s.parse().ok()?);
    if h > 23 || m > 59 || sec >= 60.0 {
        return None;
    }
    Some(f64::from(h) * 3600.0 + f64::from(m) * 60.0 + sec)
}

fn number(text: &str, lo: f64, hi: f64, line: usize, what: &str) -> Result<f64, String> {
    let ok_chars = !text.is_empty() && text.len() <= 12 && text.bytes().all(|b| b.is_ascii_digit() || b == b'.' || b == b'-');
    let value: f64 = if ok_chars {
        text.parse().map_err(|_| err(line, &format!("{what} isn't a number")))?
    } else {
        return Err(err(line, &format!("{what} isn't a number")));
    };
    if !value.is_finite() || value < lo || value > hi {
        return Err(err(line, &format!("{what} must be between {lo} and {hi}")));
    }
    Ok(value)
}

pub fn parse(text: &str) -> Result<Picks, String> {
    if text.len() > MAX_BYTES {
        return Err("the pick file is larger than 64 KB".into());
    }
    let mut out = Picks {
        event: "Unnamed event".into(),
        vp: 6.0,
        vs: 3.5,
        depth: Some(10.0),
        stations: vec![],
        picks: vec![],
    };
    for (i, raw) in text.lines().enumerate() {
        let n = i + 1;
        if raw.chars().count() > MAX_LINE {
            return Err(err(n, &format!("longer than {MAX_LINE} characters")));
        }
        if raw.chars().any(|c| {
            (c.is_control() && c != '\t')
                || matches!(c, '\u{200E}' | '\u{200F}' | '\u{202A}'..='\u{202E}' | '\u{2066}'..='\u{2069}')
        }) {
            return Err(err(n, "contains control or hidden direction characters"));
        }
        let line = raw.split('#').next().unwrap_or("").trim();
        if line.is_empty() {
            continue;
        }
        let words: Vec<&str> = line.split_whitespace().collect();
        match words[0] {
            "event" => {
                let name = words[1..].join(" ");
                if name.is_empty()
                    || name.chars().count() > 60
                    || !name.chars().all(|c| c.is_alphanumeric() || " ,.'()-/".contains(c))
                {
                    return Err(err(n, "event names are 1-60 letters, digits, spaces and simple punctuation"));
                }
                out.event = name;
            }
            "velocity" => {
                if words.len() != 5 || words[1] != "p" || words[3] != "s" {
                    return Err(err(n, "expected 'velocity p 6.0 s 3.5'"));
                }
                out.vp = number(words[2], 0.5, 15.0, n, "P velocity")?;
                out.vs = number(words[4], 0.3, 10.0, n, "S velocity")?;
                if out.vs >= out.vp {
                    return Err(err(n, "S waves are always slower than P waves"));
                }
            }
            "depth" => {
                if words.len() != 2 {
                    return Err(err(n, "expected 'depth 10' or 'depth free'"));
                }
                out.depth = if words[1] == "free" {
                    None
                } else {
                    Some(number(words[1], 0.0, 700.0, n, "depth")?)
                };
            }
            "station" => parse_station(&words, n, &mut out)?,
            _ => return Err(err(n, "lines start with event, velocity, depth or station")),
        }
    }
    if out.stations.is_empty() {
        return Err("the pick file has no stations".into());
    }
    Ok(out)
}

fn parse_station(words: &[&str], n: usize, out: &mut Picks) -> Result<(), String> {
    if words.len() < 6 {
        return Err(err(n, "expected 'station NAME LAT LON p HH:MM:SS.ss [s HH:MM:SS.ss]'"));
    }
    let name = words[1];
    if name.is_empty() || name.len() > 8 || !name.bytes().all(|b| b.is_ascii_uppercase() || b.is_ascii_digit()) {
        return Err(err(n, "station names are 1-8 capital letters or digits"));
    }
    if out.stations.iter().any(|s| s.name == name) {
        return Err(err(n, &format!("station {name} is listed twice")));
    }
    if out.stations.len() >= MAX_STATIONS {
        return Err(err(n, &format!("more than {MAX_STATIONS} stations")));
    }
    let lat = number(words[2], -90.0, 90.0, n, "latitude")?;
    let lon = number(words[3], -180.0, 180.0, n, "longitude")?;
    let index = out.stations.len();
    let mut seen = [false, false];
    let mut rest = &words[4..];
    while !rest.is_empty() {
        if rest.len() < 2 {
            return Err(err(n, "each phase needs a time, like 'p 03:14:07.42'"));
        }
        let phase = match rest[0] {
            "p" => Phase::P,
            "s" => Phase::S,
            _ => return Err(err(n, "phases are p or s")),
        };
        let k = usize::from(phase == Phase::S);
        if seen[k] {
            return Err(err(n, &format!("two {} times for one station", phase.name())));
        }
        seen[k] = true;
        let time = parse_time(rest[1]).ok_or_else(|| err(n, "times are HH:MM:SS.ss, like 03:14:07.42"))?;
        out.picks.push(Pick {
            station: index,
            phase,
            time,
            line: n,
        });
        rest = &rest[2..];
    }
    out.stations.push(Station {
        name: name.to_string(),
        lat,
        lon,
    });
    Ok(())
}
