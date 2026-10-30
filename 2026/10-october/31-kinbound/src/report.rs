//! The printed report.

use crate::graph::Edge;
use crate::parse::Tree;
use crate::solve::{born, died, explain, Analysis, Bound};
use std::fmt::Write;

fn range(b: Bound) -> String {
    match (b.lo, b.hi) {
        (Some(a), Some(z)) if a == z => a.to_string(),
        (Some(a), Some(z)) => format!("{a}-{z}"),
        (None, Some(z)) => format!("by {z}"),
        (Some(a), None) => format!("{a} or later"),
        (None, None) => "?".to_string(),
    }
}

fn pad(s: &str, width: usize) -> String {
    let n = s.chars().count();
    format!("{s}{}", " ".repeat(width.saturating_sub(n)))
}

fn source(e: &Edge) -> String {
    if e.line == 0 {
        "rule   ".to_string()
    } else {
        format!("line {:<3}", e.line)
    }
}

/// Lists the facts on a chain of edges, merging neighbours that came from the same sentence.
fn facts(out: &mut String, a: &Analysis, chain: &[usize]) {
    let mut last: Option<&str> = None;
    for &i in chain {
        let e = &a.graph.edges[i];
        if last != Some(e.why.as_str()) {
            let _ = writeln!(out, "    {}  {}", source(e), e.why);
        }
        last = Some(e.why.as_str());
    }
}

fn lines(ls: &[usize]) -> String {
    let parts: Vec<String> = ls.iter().map(|l| format!("line {l}")).collect();
    match parts.len() {
        0 => String::new(),
        1 => parts[0].clone(),
        _ => format!("{} and {}", parts[..parts.len() - 1].join(", "), parts[parts.len() - 1]),
    }
}

#[must_use]
pub fn render(tree: &Tree, a: &Analysis) -> String {
    let mut out = String::new();
    let w = &mut out;
    let _ = writeln!(w, "KINBOUND  {}", tree.title);
    let _ = writeln!(w, "{} people, {} records.", tree.people.len(), tree.records.len());

    if a.conflicts.is_empty() {
        let _ = writeln!(w, "Every record fits with every other.\n");
    } else {
        let _ = writeln!(w, "Some records can't all be true.\n");
        for (k, c) in a.conflicts.iter().enumerate() {
            let years = if c.gap == 1 { "1 year" } else { &format!("{} years", c.gap) };
            let _ = writeln!(w, "CONFLICT {}: these can't all hold (they miss by {years})", k + 1);
            facts(w, a, &c.edges);
            let _ = writeln!(w);
        }
        if a.fixes.is_empty() {
            let _ = writeln!(
                w,
                "No set of up to {} records explains every conflict on its own: check the rules (adoption, a second marriage\nor a step-parent can break them) or look for several mistakes.",
                crate::solve::MAX_FIX
            );
            return out;
        }
        let size = a.fixes[0].len();
        let what = if size == 1 {
            "one record".to_string()
        } else {
            format!("{size} records")
        };
        let _ = writeln!(
            w,
            "Fewest records that would have to be wrong: {what}. Any of these would explain every conflict:"
        );
        for f in a.fixes.iter().take(8) {
            let _ = writeln!(w, "  - {}", lines(f));
            for &l in f {
                let in_conflict = a
                    .conflicts
                    .iter()
                    .flat_map(|c| &c.edges)
                    .map(|&i| &a.graph.edges[i])
                    .find(|e| e.line == l);
                if let Some(e) = in_conflict.or_else(|| a.graph.edges.iter().find(|e| e.line == l)) {
                    let _ = writeln!(w, "      {}", e.why);
                }
            }
        }
        if a.fixes.len() > 8 {
            let _ = writeln!(w, "  ... and {} more", a.fixes.len() - 8);
        }
        if !a.fix_complete {
            let _ = writeln!(w, "  (the search stopped at its limit, so there may be others)");
        }
        let _ = writeln!(
            w,
            "\nThe dates below assume {} is the mistake: of these, it changes the other dates least.\n",
            lines(&a.assumed)
        );
    }

    let Some(dates) = &a.dates else { return out };
    let width = tree.people.iter().map(|p| p.name.chars().count()).max().unwrap_or(4).max(6) + 2;
    let _ = writeln!(w, "{}{:<14}Died", pad("Person", width), "Born");
    for (p, (b, d)) in tree.people.iter().zip(dates) {
        let _ = writeln!(w, "{}{:<14}{}", pad(&p.name, width), range(*b), range(*d));
    }

    // The widest birth ranges: where a search of the records would help most.
    let mut wide: Vec<(i64, usize)> = dates
        .iter()
        .enumerate()
        .filter_map(|(p, (b, _))| Some((b.hi? - b.lo?, p)))
        .filter(|&(span, _)| span >= 5)
        .collect();
    wide.sort_by(|x, y| y.0.cmp(&x.0).then(x.1.cmp(&y.1)));
    if !wide.is_empty() {
        let names: Vec<String> = wide
            .iter()
            .take(3)
            .map(|&(s, p)| format!("{} ({} years)", tree.people[p].name, s + 1))
            .collect();
        let _ = writeln!(
            w,
            "\nWidest birth ranges, where a new record would help most: {}.",
            names.join(", ")
        );
    }
    out
}

/// The reasons behind one person's bounds.
#[must_use]
pub fn why(tree: &Tree, a: &Analysis, p: usize) -> String {
    let mut out = String::new();
    let Some(dates) = &a.dates else {
        let _ = writeln!(out, "\nNo dates can be given until the conflicts are resolved.");
        return out;
    };
    let name = &tree.people[p].name;
    let (b, d) = dates[p];
    for (label, var, bound) in [("born", born(p), b), ("died", died(p), d)] {
        for (upper, value, word) in [(false, bound.lo, "no earlier than"), (true, bound.hi, "no later than")] {
            let _ = writeln!(out);
            let Some(v) = value else {
                let _ = writeln!(
                    out,
                    "{name} {label}: nothing limits how {}.",
                    if upper { "late" } else { "early" }
                );
                continue;
            };
            let _ = writeln!(out, "{name} {label} {word} {v}, because:");
            facts(&mut out, a, &explain(a, var, upper));
        }
    }
    out
}
