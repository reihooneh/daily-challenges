//! Text output: a light's rhythm as a strip, with the watcher's times folded onto it.

use crate::fit::Fit;
use crate::input::Watch;
use crate::pattern::{is_on, Kind, Light};

/// Columns for one period: a quarter second each, at most 60.
pub fn columns(light: &Light) -> (usize, f64) {
    let p = light.spec.period.max(0.25);
    let cols = ((p / 0.25).ceil() as usize).clamp(1, 60);
    (cols, p / cols as f64)
}

/// One period: `#` while the light is on, `.` while it is off.
pub fn strip(light: &Light) -> String {
    let (cols, res) = columns(light);
    (0..cols)
        .map(|c| {
            if is_on(&light.edges, light.spec.class, (c as f64 + 0.5) * res) {
                '#'
            } else {
                '.'
            }
        })
        .collect()
}

/// The watcher's times folded into one period with the fitted phase and scale: `^` for on,
/// `v` for off, `*` where several land in the same column.
pub fn folded(light: &Light, w: &Watch, f: &Fit) -> String {
    let (cols, res) = columns(light);
    let mut row = vec![' '; cols];
    for &(t, kind) in &w.events {
        let m = ((t - f.phase) / f.scale).rem_euclid(light.spec.period);
        let c = (m / res).round() as usize % cols;
        let mark = if kind == Kind::On { '^' } else { 'v' };
        row[c] = if row[c] == ' ' || row[c] == mark { mark } else { '*' };
    }
    row.into_iter().collect::<String>().trim_end().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::pattern::parse;

    #[test]
    fn strips() {
        assert_eq!(strip(&parse("Fl(2) 5s").unwrap()), "##....##............");
        assert_eq!(strip(&parse("Iso 2s").unwrap()), "####....");
        assert_eq!(strip(&parse("Oc 3s").unwrap()), "....########");
        assert_eq!(strip(&parse("F R").unwrap()), "#");
        assert_eq!(columns(&parse("Fl 30s").unwrap()).0, 60);
    }
}
