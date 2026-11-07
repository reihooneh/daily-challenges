//! Light characteristics: parsing the chart abbreviation ("Fl(2) W 10s") and turning it into
//! the times within one period when the light comes on and goes off.
//!
//! A chart gives the rhythm and the period, but not how long each flash lasts. Those lengths are
//! modelled with typical values and a standard deviation, so every edge carries its own
//! uncertainty: the first edge of the period is exact, and the uncertainty grows with each
//! assumed length that comes before it.

use crate::rng::Rng;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Kind {
    On,
    Off,
}

/// One change of the light within a period: when (seconds from the period's start), how sure
/// the model is of that time (standard deviation, seconds), and whether it switches on or off.
#[derive(Clone, Copy, Debug)]
pub struct Edge {
    pub t: f64,
    pub sd: f64,
    pub kind: Kind,
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Class {
    Fixed,
    Flash,     // Fl
    LongFlash, // LFl
    Quick,     // Q
    VeryQuick, // VQ
    Occulting, // Oc
    Isophase,  // Iso
    Morse,     // Mo
}

/// The parsed abbreviation.
#[derive(Clone, Debug, PartialEq)]
pub struct Spec {
    pub class: Class,
    /// Flashes (or eclipses) in each group: [2] for Fl(2), [2, 1] for Fl(2+1); empty if none.
    pub groups: Vec<u8>,
    /// Q(6)+LFl: a long flash after the quick group (south cardinal marks).
    pub plus_long: bool,
    /// Mo(A): the letter.
    pub letter: Option<char>,
    pub colours: Vec<char>,
    pub period: f64,
}

/// A light ready to compare with an observation.
#[derive(Clone, Debug)]
pub struct Light {
    pub spec: Spec,
    pub text: String,
    /// How far the true period may differ from the stated one, as a fraction. Zero for charted
    /// periods; quick lights only have a rate range (50 to 80 a minute for Q).
    pub period_tol: f64,
    pub edges: Vec<Edge>,
}

pub const MAX_PERIOD: f64 = 120.0;
const MIN_PERIOD: f64 = 0.5;

// Typical lengths and their spread, in seconds.
const FL: (f64, f64) = (0.5, 0.2);
const FL_GAP: (f64, f64) = (1.0, 0.4);
const LFL: (f64, f64) = (2.0, 0.3);
const LFL_GAP: (f64, f64) = (2.0, 0.7);
const GROUP_GAP: (f64, f64) = (3.0, 1.0);
const Q: (f64, f64) = (0.3, 0.08);
const Q_GAP: (f64, f64) = (0.7, 0.08);
const VQ: (f64, f64) = (0.2, 0.04);
const VQ_GAP: (f64, f64) = (0.3, 0.04);
const OC: (f64, f64) = (1.0, 0.3);
const OC_GAP: (f64, f64) = (1.0, 0.4);
const DOT: (f64, f64) = (0.5, 0.15);
const DASH: (f64, f64) = (1.5, 0.3);
const MO_GAP: (f64, f64) = (0.5, 0.15);

/// Parses an abbreviation such as `Fl(2) W 10s`, `Q(6)+LFl 15s`, `Oc(2)R.8s`, `Iso G 4s`,
/// `Mo(U) 15s`, `VQ` or `F R`.
pub fn parse(text: &str) -> Result<Light, String> {
    let text = text.trim();
    if text.is_empty() || text.len() > 40 {
        return Err("a light's character must be 1 to 40 characters".into());
    }
    if !text.chars().all(|c| c.is_ascii_alphanumeric() || "()+. ".contains(c)) {
        return Err("a light's character may only use letters, digits, ( ) + . and spaces".into());
    }
    let b = text.as_bytes();
    let mut i = 0;
    let class = [
        ("LFl", Class::LongFlash),
        ("Fl", Class::Flash),
        ("VQ", Class::VeryQuick),
        ("Iso", Class::Isophase),
        ("Oc", Class::Occulting),
        ("Mo", Class::Morse),
        ("Q", Class::Quick),
        ("F", Class::Fixed),
    ]
    .iter()
    .find(|(p, _)| text.starts_with(p))
    .map(|&(p, c)| {
        i = p.len();
        c
    })
    .ok_or("unknown light character (try Fl, LFl, Q, VQ, Oc, Iso, Mo or F)")?;

    let mut spec = Spec {
        class,
        groups: vec![],
        plus_long: false,
        letter: None,
        colours: vec![],
        period: 0.0,
    };
    if i < b.len() && b[i] == b'(' {
        let close = text[i..].find(')').ok_or("a '(' without ')'")? + i;
        let inner = &text[i + 1..close];
        if class == Class::Morse {
            let mut cs = inner.chars();
            match (cs.next(), cs.next()) {
                (Some(c), None) if c.is_ascii_uppercase() => spec.letter = Some(c),
                _ => return Err("Mo needs one capital letter, like Mo(A)".into()),
            }
        } else if matches!(
            class,
            Class::Flash | Class::LongFlash | Class::Occulting | Class::Quick | Class::VeryQuick
        ) {
            for part in inner.split('+') {
                let n: u8 = part
                    .parse()
                    .map_err(|_| "a group must be a number from 1 to 9, like (2) or (2+1)")?;
                if !(1..=9).contains(&n) {
                    return Err("a group must be a number from 1 to 9, like (2) or (2+1)".into());
                }
                spec.groups.push(n);
            }
            if spec.groups.len() > 3 {
                return Err("at most 3 groups, like (2+1)".into());
            }
            if matches!(class, Class::Quick | Class::VeryQuick) && spec.groups.len() > 1 {
                return Err("quick lights have one group, like Q(3)".into());
            }
        } else {
            return Err("this character takes no group".into());
        }
        i = close + 1;
    } else if class == Class::Morse {
        return Err("Mo needs a letter, like Mo(A)".into());
    }
    if text[i..].starts_with("+LFl") {
        if !matches!(class, Class::Quick | Class::VeryQuick) || spec.groups.is_empty() {
            return Err("+LFl only follows a quick group, like Q(6)+LFl".into());
        }
        spec.plus_long = true;
        i += 4;
    }

    // The rest: colour letters and the period, separated by spaces or dots.
    let rest = &text[i..];
    let rb = rest.as_bytes();
    let mut j = 0;
    let mut period = None;
    while j < rb.len() {
        let c = rb[j];
        if c == b' ' || c == b'.' {
            j += 1;
        } else if c.is_ascii_digit() {
            let start = j;
            while j < rb.len() && (rb[j].is_ascii_digit() || (rb[j] == b'.' && j + 1 < rb.len() && rb[j + 1].is_ascii_digit())) {
                j += 1;
            }
            if j >= rb.len() || rb[j] != b's' || period.is_some() {
                return Err("the period is a number of seconds, like 10s or 2.5s".into());
            }
            let p: f64 = rest[start..j]
                .parse()
                .map_err(|_| "the period is a number of seconds, like 10s")?;
            period = Some(p);
            j += 1;
        } else if c.is_ascii_uppercase() {
            while j < rb.len() && rb[j].is_ascii_uppercase() {
                let col = rb[j] as char;
                if !"WRGY".contains(col) {
                    return Err("colours are W, R, G or Y".into());
                }
                if !spec.colours.contains(&col) {
                    spec.colours.push(col);
                }
                j += 1;
            }
        } else {
            return Err("after the character come the colours (W R G Y) and the period".into());
        }
    }
    if spec.colours.is_empty() {
        spec.colours.push('W'); // charts leave out W for white
    }
    let continuous = matches!(class, Class::Quick | Class::VeryQuick) && spec.groups.is_empty();
    let mut period_tol = 0.0;
    match (class, period) {
        (Class::Fixed, Some(_)) => return Err("a fixed light has no period".into()),
        (Class::Fixed, None) => spec.period = 0.0,
        (_, Some(_)) if continuous => return Err("continuous Q and VQ have no period; give a group, like Q(3) 10s".into()),
        (Class::Quick, None) if continuous => {
            spec.period = 1.0;
            period_tol = 0.2;
        }
        (Class::VeryQuick, None) if continuous => {
            spec.period = 0.5;
            period_tol = 0.25;
        }
        (_, None) => return Err("give the period, like 10s".into()),
        (_, Some(p)) => {
            if !(MIN_PERIOD..=MAX_PERIOD).contains(&p) {
                return Err(format!("the period must be from {MIN_PERIOD} to {MAX_PERIOD} seconds"));
            }
            spec.period = p;
        }
    }
    let edges = build(&spec, None)?;
    Ok(Light {
        text: describe(&spec),
        spec,
        period_tol,
        edges,
    })
}

/// The abbreviation written the standard way.
pub fn describe(s: &Spec) -> String {
    let mut out = String::from(match s.class {
        Class::Fixed => "F",
        Class::Flash => "Fl",
        Class::LongFlash => "LFl",
        Class::Quick => "Q",
        Class::VeryQuick => "VQ",
        Class::Occulting => "Oc",
        Class::Isophase => "Iso",
        Class::Morse => "Mo",
    });
    if let Some(l) = s.letter {
        out.push_str(&format!("({l})"));
    }
    if !s.groups.is_empty() {
        let g: Vec<String> = s.groups.iter().map(u8::to_string).collect();
        out.push_str(&format!("({})", g.join("+")));
    }
    if s.plus_long {
        out.push_str("+LFl");
    }
    out.push(' ');
    out.extend(s.colours.iter());
    let continuous = matches!(s.class, Class::Quick | Class::VeryQuick) && s.groups.is_empty();
    if s.class != Class::Fixed && !continuous {
        let p = if s.period.fract() == 0.0 {
            format!("{}", s.period as u32)
        } else {
            format!("{}", s.period)
        };
        out.push_str(&format!(" {p}s"));
    }
    out
}

/// Walks through one period, recording edges. With an `Rng`, every assumed length is drawn at
/// random around its typical value instead: that is how a real light differs from the model.
struct Walk<'a> {
    t: f64,
    var: f64,
    edges: Vec<Edge>,
    rng: Option<&'a mut Rng>,
}

impl Walk<'_> {
    fn edge(&mut self, kind: Kind) {
        self.edges.push(Edge {
            t: self.t,
            sd: self.var.sqrt(),
            kind,
        });
    }
    fn wait(&mut self, (len, sd): (f64, f64)) {
        let len = match self.rng.as_deref_mut() {
            Some(r) => (len + sd * r.normal()).max(len * 0.3),
            None => len,
        };
        self.t += len;
        self.var += sd * sd;
    }
    /// The light on for `len`, then off.
    fn flash(&mut self, len: (f64, f64)) {
        self.edge(Kind::On);
        self.wait(len);
        self.edge(Kind::Off);
    }
    /// The light off for `len`, then on.
    fn eclipse(&mut self, len: (f64, f64)) {
        self.edge(Kind::Off);
        self.wait(len);
        self.edge(Kind::On);
    }
}

/// The edges of one period. Errors if the rhythm doesn't fit in the period.
pub fn build(s: &Spec, rng: Option<&mut Rng>) -> Result<Vec<Edge>, String> {
    let mut w = Walk {
        t: 0.0,
        var: 0.0,
        edges: vec![],
        rng,
    };
    let groups = if s.groups.is_empty() { vec![1] } else { s.groups.clone() };
    match s.class {
        Class::Fixed => return Ok(vec![]),
        Class::Isophase => {
            w.edges.push(Edge {
                t: 0.0,
                sd: 0.0,
                kind: Kind::On,
            });
            w.edges.push(Edge {
                t: s.period / 2.0,
                sd: 0.0,
                kind: Kind::Off,
            });
            return Ok(w.edges);
        }
        Class::Morse => {
            let code = morse(s.letter.unwrap_or('A'));
            for (k, sym) in code.chars().enumerate() {
                if k > 0 {
                    w.wait(MO_GAP);
                }
                w.flash(if sym == '.' { DOT } else { DASH });
            }
        }
        Class::Flash | Class::LongFlash | Class::Quick | Class::VeryQuick => {
            let (on, gap) = match s.class {
                Class::Flash => (FL, FL_GAP),
                Class::LongFlash => (LFL, LFL_GAP),
                Class::Quick => (Q, Q_GAP),
                _ => (VQ, VQ_GAP),
            };
            for (gi, &n) in groups.iter().enumerate() {
                if gi > 0 {
                    w.wait(GROUP_GAP);
                }
                for k in 0..n {
                    if k > 0 {
                        w.wait(gap);
                    }
                    w.flash(on);
                }
            }
            if s.plus_long {
                w.wait(gap);
                w.flash(LFL);
            }
        }
        Class::Occulting => {
            for (gi, &n) in groups.iter().enumerate() {
                if gi > 0 {
                    w.wait(GROUP_GAP);
                }
                for k in 0..n {
                    if k > 0 {
                        w.wait(OC_GAP);
                    }
                    w.eclipse(OC);
                }
            }
        }
    }
    // Continuous quick lights repeat their single flash: its gap fills the period exactly.
    let min_rest = if matches!(s.class, Class::Quick | Class::VeryQuick) && s.groups.is_empty() {
        0.1
    } else {
        0.5
    };
    if w.t + min_rest > s.period + 1e-9 {
        return Err(format!(
            "{} seconds is too short for this rhythm (it needs at least {:.1})",
            s.period,
            w.t + min_rest
        ));
    }
    Ok(w.edges)
}

fn morse(c: char) -> &'static str {
    const CODES: [&str; 26] = [
        ".-", "-...", "-.-.", "-..", ".", "..-.", "--.", "....", "..", ".---", "-.-", ".-..", "--", "-.", "---", ".--.", "--.-",
        ".-.", "...", "-", "..-", "...-", ".--", "-..-", "-.--", "--..",
    ];
    CODES[(c as u8 - b'A') as usize]
}

/// Whether the light is on at time `t` (seconds into the period) by the model.
pub fn is_on(edges: &[Edge], class: Class, t: f64) -> bool {
    if class == Class::Fixed {
        return true;
    }
    // Occulting lights are on between eclipses; the others are off between flashes.
    let mut on = class == Class::Occulting;
    for e in edges {
        if e.t <= t {
            on = e.kind == Kind::On;
        }
    }
    on
}

#[cfg(test)]
mod tests {
    use super::*;

    fn times(l: &Light, k: Kind) -> Vec<f64> {
        l.edges
            .iter()
            .filter(|e| e.kind == k)
            .map(|e| (e.t * 10.0).round() / 10.0)
            .collect()
    }

    #[test]
    fn group_flashing() {
        let l = parse("Fl(2) W 10s").unwrap();
        assert_eq!(times(&l, Kind::On), vec![0.0, 1.5]);
        assert_eq!(l.edges[0].sd, 0.0);
        assert!(l.edges[2].sd > 0.4, "the second flash depends on two assumed lengths");
        assert_eq!(l.text, "Fl(2) W 10s");
    }

    #[test]
    fn chart_spellings() {
        assert_eq!(parse("Fl(3)R.15s").unwrap().text, "Fl(3) R 15s");
        assert_eq!(parse("Oc.WRG.4s").unwrap().text, "Oc WRG 4s");
        assert_eq!(parse("Q(6)+LFl 15s").unwrap().text, "Q(6)+LFl W 15s");
        assert_eq!(parse("Iso G 2.5s").unwrap().text, "Iso G 2.5s");
        assert_eq!(parse("VQ").unwrap().spec.period, 0.5);
        assert_eq!(parse("F R").unwrap().edges.len(), 0);
    }

    #[test]
    fn south_cardinal() {
        let l = parse("Q(6)+LFl 15s").unwrap();
        let on = times(&l, Kind::On);
        assert_eq!(on, vec![0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0]);
        assert_eq!(times(&l, Kind::Off).last(), Some(&8.0));
    }

    #[test]
    fn morse_u() {
        let l = parse("Mo(U) 15s").unwrap(); // ..-
        assert_eq!(times(&l, Kind::On), vec![0.0, 1.0, 2.0]);
        assert_eq!(times(&l, Kind::Off), vec![0.5, 1.5, 3.5]);
    }

    #[test]
    fn occulting_starts_dark() {
        let l = parse("Oc(2) 8s").unwrap();
        assert_eq!(l.edges[0].kind, Kind::Off);
        assert!(is_on(&l.edges, Class::Occulting, 3.0));
        assert!(!is_on(&l.edges, Class::Occulting, 0.5));
    }

    #[test]
    fn refusals() {
        for bad in [
            "",
            "Xy 10s",
            "Fl(0) 10s",
            "Fl(12) 10s",
            "Fl(2) 10",
            "Fl(2) B 10s",
            "Fl(2) 1000s",
            "Fl(5) 3s",
            "Q 10s",
            "Fl(2)+LFl 10s",
            "Mo(ab) 8s",
            "Fl(2) 10s 5s",
            "F 10s",
            "Fl(2);rm 10s",
            "Fl(1+1+1+1) 20s",
        ] {
            assert!(parse(bad).is_err(), "{bad:?} should be refused");
        }
    }

    #[test]
    fn random_lengths_stay_in_order() {
        let s = parse("Fl(2+1) 15s").unwrap().spec;
        let mut r = Rng::new(7);
        for _ in 0..100 {
            let e = build(&s, Some(&mut r)).unwrap_or_default();
            assert!(e.windows(2).all(|p| p[0].t < p[1].t));
        }
    }
}
