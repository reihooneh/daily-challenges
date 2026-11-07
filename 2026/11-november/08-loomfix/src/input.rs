//! Reading the two kinds of file: a list of lights, and the timings of a light being watched.
//! Both are untrusted text, so they are checked strictly and errors give only a line number.

use crate::pattern::{self, Kind, Light};

pub const MAX_BYTES: usize = 64 * 1024;
const MAX_LINE: usize = 200;
const MAX_LIGHTS: usize = 300;
const MAX_EVENTS: usize = 400;
pub const MAX_TIME: f64 = 3600.0;

#[derive(Clone, Debug)]
pub struct Named {
    pub name: String,
    pub light: Light,
}

/// How the watcher timed the light.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Timing {
    /// A stopwatch: the scale is right to within about 2%.
    Stopwatch,
    /// Counting "one thousand and one...": the scale can be out by 10% or more.
    Counted,
}

#[derive(Clone, Debug)]
pub struct Watch {
    pub timing: Timing,
    pub colour: Option<char>,
    /// Times in seconds, increasing, and whether the light came on or went off.
    pub events: Vec<(f64, Kind)>,
    /// When the watcher started and stopped looking, if noted: flashes in that time that
    /// weren't timed count as missed.
    pub window: Option<(f64, f64)>,
}

impl Watch {
    /// The time span in which an untimed flash counts as missed: the noted watching time, or
    /// else from just before the first time to just after the last.
    pub fn span(&self) -> (f64, f64) {
        let (a, b) = (self.events[0].0, self.events[self.events.len() - 1].0);
        self.window.unwrap_or((a - 0.5, b + 0.5))
    }
}

fn check_text(text: &str) -> Result<(), String> {
    if text.len() > MAX_BYTES {
        return Err("the file is over 64 KB".into());
    }
    for (n, line) in text.lines().enumerate() {
        if line.chars().count() > MAX_LINE {
            return Err(format!("line {}: longer than {MAX_LINE} characters", n + 1));
        }
        if line.chars().any(|c| {
            c.is_control() && c != '\t'
                || ('\u{200B}'..='\u{200F}').contains(&c)
                || ('\u{202A}'..='\u{202E}').contains(&c)
                || ('\u{2066}'..='\u{2069}').contains(&c)
        }) {
            return Err(format!("line {}: control or invisible formatting characters", n + 1));
        }
    }
    Ok(())
}

/// The useful part of a line: without a `#` comment and surrounding space.
fn content(line: &str) -> &str {
    line.split('#').next().unwrap_or("").trim()
}

/// A list of lights, one a line: `Name | character`, such as `Gull Rock | Fl(2) W 10s`.
pub fn lights(text: &str) -> Result<Vec<Named>, String> {
    check_text(text)?;
    let mut out: Vec<Named> = vec![];
    for (n, line) in text.lines().enumerate() {
        let line = content(line);
        if line.is_empty() {
            continue;
        }
        let at = |e: String| format!("line {}: {e}", n + 1);
        let (name, ch) = line
            .split_once('|')
            .ok_or_else(|| at("write a light as  Name | character".into()))?;
        let name = name.trim();
        if name.is_empty() || name.chars().count() > 40 || !name.chars().all(|c| c.is_alphanumeric() || " -'.".contains(c)) {
            return Err(at("a name is 1 to 40 letters, digits, spaces, - ' or .".into()));
        }
        if out.iter().any(|o| o.name == name) {
            return Err(at("this name is already in the list".into()));
        }
        let light = pattern::parse(ch).map_err(at)?;
        out.push(Named {
            name: name.to_string(),
            light,
        });
        if out.len() > MAX_LIGHTS {
            return Err(format!("at most {MAX_LIGHTS} lights"));
        }
    }
    if out.is_empty() {
        return Err("no lights in the list".into());
    }
    Ok(out)
}

/// Timings of a light: optional `timing stopwatch|counted` and `colour W|R|G|Y` lines, then one
/// time in seconds a line, each followed by `on` (the default) or `off`.
pub fn watch(text: &str) -> Result<Watch, String> {
    check_text(text)?;
    let mut w = Watch {
        timing: Timing::Stopwatch,
        colour: None,
        events: vec![],
        window: None,
    };
    let number = |t: &str| -> Option<f64> {
        let ok = !t.is_empty() && t.len() <= 10 && t.chars().all(|c| c.is_ascii_digit() || c == '.');
        t.parse().ok().filter(|v| ok && (0.0..=MAX_TIME).contains(v))
    };
    for (n, line) in text.lines().enumerate() {
        let line = content(line);
        if line.is_empty() {
            continue;
        }
        let at = |e: &str| format!("line {}: {e}", n + 1);
        let words: Vec<&str> = line.split_whitespace().collect();
        match words.as_slice() {
            ["timing", "stopwatch"] => w.timing = Timing::Stopwatch,
            ["timing", "counted"] => w.timing = Timing::Counted,
            ["watched", a, "to", b] => match (number(a), number(b)) {
                (Some(a), Some(b)) if a < b => w.window = Some((a, b)),
                _ => return Err(at("write  watched FROM to TO  in seconds, like  watched 0 to 40")),
            },
            ["colour" | "color", c] => match *c {
                "W" | "R" | "G" | "Y" => w.colour = c.chars().next(),
                _ => return Err(at("the colour is W, R, G or Y")),
            },
            [t] | [t, "on" | "off"] => {
                let kind = if words.get(1) == Some(&"off") { Kind::Off } else { Kind::On };
                let time = number(t).ok_or_else(|| at("a time is a number of seconds from 0 to 3600, then on or off"))?;
                if let Some(&(last, _)) = w.events.last() {
                    if time <= last {
                        return Err(at("times must increase"));
                    }
                }
                w.events.push((time, kind));
                if w.events.len() > MAX_EVENTS {
                    return Err(format!("at most {MAX_EVENTS} times"));
                }
            }
            _ => return Err(at("expected a time (then on or off), timing, or colour")),
        }
    }
    if w.events.len() < 3 {
        return Err("time at least 3 changes of the light (a full period or two is best)".into());
    }
    if let Some((a, b)) = w.window {
        if a > w.events[0].0 || b < w.events[w.events.len() - 1].0 {
            return Err("the watched time must include every timed change".into());
        }
    }
    Ok(w)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_list() {
        let l = lights("# harbour\nGull Rock | Fl(2) W 10s\n\nNorth Pier | Oc R 4s  # red\n").unwrap();
        assert_eq!(l.len(), 2);
        assert_eq!(l[1].name, "North Pier");
        assert_eq!(l[1].light.text, "Oc R 4s");
    }

    #[test]
    fn a_watch() {
        let w = watch("timing counted\ncolour R\nwatched 0 to 30\n0\n1.5\n10.2 on\n10.9 off\n").unwrap();
        assert_eq!(w.window, Some((0.0, 30.0)));
        assert_eq!(w.timing, Timing::Counted);
        assert_eq!(w.colour, Some('R'));
        assert_eq!(w.events.len(), 4);
        assert_eq!(w.events[3], (10.9, Kind::Off));
    }

    #[test]
    fn refusals() {
        assert!(lights("").unwrap_err().contains("no lights"));
        assert!(lights("Gull | Fl(2) 10s\nGull | Q").unwrap_err().contains("line 2"));
        assert!(lights("<b>x</b> | Q").is_err());
        assert!(lights("A | Q\x1b[2J").is_err());
        assert!(lights("A\u{202E}B | Q").is_err());
        assert!(watch("1\n2\n").unwrap_err().contains("at least 3"));
        assert!(watch("1\n3\n2\n").unwrap_err().contains("increase"));
        assert!(watch("1\n2\n1e9\n").is_err());
        assert!(watch("1\n2\n5000\n").is_err());
        assert!(watch("1\n2\nNaN\n").is_err());
        assert!(watch("1\n2\n3 sideways\n").is_err());
        assert!(watch("watched 2 to 9\n1\n2\n3\n").unwrap_err().contains("include"));
        assert!(watch("watched 9 to 2\n1\n2\n3\n").is_err());
        assert!(watch(&"1\n".repeat(70_000)).unwrap_err().contains("64 KB"));
    }
}
