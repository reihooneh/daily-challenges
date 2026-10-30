//! Turns a family into difference constraints, then finds bounds, conflicts and the fewest
//! records that would have to be wrong.

use crate::graph::{Edge, Graph, INF};
use crate::parse::{Kind, Span, Tree};
use std::collections::BTreeSet;

pub const ZERO: usize = 0;
#[must_use]
pub fn born(p: usize) -> usize {
    1 + 2 * p
}
#[must_use]
pub fn died(p: usize) -> usize {
    2 + 2 * p
}

/// The most records a fix may doubt, and how many consistency checks the search may spend.
pub const MAX_FIX: usize = 3;
pub const CHECK_BUDGET: usize = 4000;

fn add_span(g: &mut Graph, var: usize, s: Span, line: usize, why: &str) {
    if let Some(lo) = s.lo {
        g.le(ZERO, var, -lo, line, why);
    }
    if let Some(hi) = s.hi {
        g.le(var, ZERO, hi, line, why);
    }
}

/// Builds the constraint graph: one node for the year zero, and a birth and death node per person.
#[must_use]
pub fn build(tree: &Tree) -> Graph {
    let mut g = Graph::new(1 + 2 * tree.people.len());
    let r = tree.rules;
    let name = |p: usize| tree.people[p].name.as_str();
    for p in 0..tree.people.len() {
        g.le(born(p), died(p), 0, 0, format!("{} can't die before being born", name(p)));
        g.le(
            died(p),
            born(p),
            r.lifespan,
            0,
            format!("{} lived at most {} years (rule: lifespan)", name(p), r.lifespan),
        );
    }
    for rec in &tree.records {
        let (p, n) = (rec.person, rec.line);
        match rec.kind {
            Kind::Born(s) => add_span(&mut g, born(p), s, n, &format!("{} was born {}", name(p), s.phrase())),
            Kind::Died(s) => add_span(&mut g, died(p), s, n, &format!("{} died {}", name(p), s.phrase())),
            Kind::Baptised(y) => {
                let s = Span {
                    lo: Some(y - 2),
                    hi: Some(y),
                    about: false,
                };
                add_span(
                    &mut g,
                    born(p),
                    s,
                    n,
                    &format!("{} was baptised in {y}, so born {}-{y}", name(p), y - 2),
                );
            }
            Kind::Buried(y) => {
                let s = Span {
                    lo: Some(y - 1),
                    hi: Some(y),
                    about: false,
                };
                add_span(
                    &mut g,
                    died(p),
                    s,
                    n,
                    &format!("{} was buried in {y}, so died {}-{y}", name(p), y - 1),
                );
            }
            Kind::Census { year, age } => {
                let s = Span {
                    lo: Some(year - age - 1),
                    hi: Some(year - age),
                    about: false,
                };
                let why = format!(
                    "{} was {age} in the {year} census, so born {}-{}",
                    name(p),
                    year - age - 1,
                    year - age
                );
                add_span(&mut g, born(p), s, n, &why);
            }
            Kind::Alive(y) => {
                let why = format!("{} was alive in {y}", name(p));
                g.le(born(p), ZERO, y, n, &why);
                g.le(ZERO, died(p), -y, n, why);
            }
            Kind::Mother(c) | Kind::Father(c) => {
                let mother = matches!(rec.kind, Kind::Mother(_));
                let (role, (lo, hi), rule) = if mother {
                    ("mother", r.mother_age, "mother-age")
                } else {
                    ("father", r.father_age, "father-age")
                };
                let ages = format!(
                    "{} is {}'s {role}, and a {role} is {lo} to {hi} at a birth (rule: {rule})",
                    name(p),
                    name(c)
                );
                g.le(born(p), born(c), -lo, n, &ages);
                g.le(born(c), born(p), hi, n, ages);
                if mother {
                    g.le(
                        born(c),
                        died(p),
                        0,
                        n,
                        format!("{} is {}'s mother, so was alive at the birth", name(p), name(c)),
                    );
                } else {
                    let why = format!(
                        "{} is {}'s father, so died no more than a year before the birth",
                        name(p),
                        name(c)
                    );
                    g.le(born(c), died(p), 1, n, why);
                }
            }
            Kind::Married { spouse, year } => {
                for (a, b) in [(p, spouse), (spouse, p)] {
                    let why = format!(
                        "{} married {} in {year}, so was born by {} (rule: marriage-age {}) and alive then",
                        name(a),
                        name(b),
                        year - r.marriage_age,
                        r.marriage_age
                    );
                    g.le(born(a), ZERO, year - r.marriage_age, n, &why);
                    g.le(ZERO, died(a), -year, n, why);
                }
            }
        }
    }
    g
}

/// Birth and death bounds for each person, in file order.
pub type Dates = Vec<(Bound, Bound)>;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Bound {
    pub lo: Option<i64>,
    pub hi: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Conflict {
    pub edges: Vec<usize>,
    /// How many years short of fitting the records are.
    pub gap: i64,
}

#[derive(Debug, Clone)]
pub struct Analysis {
    pub graph: Graph,
    /// Distinct sets of facts that can't all be true (empty when the tree is consistent).
    pub conflicts: Vec<Conflict>,
    /// The smallest sets of record lines that, if wrong, remove every conflict.
    pub fixes: Vec<Vec<usize>>,
    /// False when the search ran out of budget or no fix of up to [`MAX_FIX`] lines exists.
    pub fix_complete: bool,
    /// Lines assumed wrong for the dates below (empty when the tree is consistent).
    pub assumed: Vec<usize>,
    /// Birth and death bounds per person; `None` when no consistent reading was found.
    pub dates: Option<Vec<(Bound, Bound)>>,
}

struct FixSearch<'a> {
    graph: &'a Graph,
    checks: usize,
    found: BTreeSet<Vec<usize>>,
    conflicts: Vec<Conflict>,
}

impl FixSearch<'_> {
    fn cycle(&mut self, removed: &[usize]) -> Option<Vec<usize>> {
        self.checks += 1;
        let mut c = self.graph.negative_cycle(&|e: &Edge| !removed.contains(&e.line))?;
        // Start the story at the earliest line in the file (rules count as last).
        let key = |i: &usize| match self.graph.edges[*i].line {
            0 => usize::MAX,
            l => l,
        };
        if let Some(first) = c.iter().enumerate().min_by_key(|(_, i)| key(i)).map(|(k, _)| k) {
            c.rotate_left(first);
        }
        let gap = -c.iter().map(|&i| self.graph.edges[i].w).sum::<i64>();
        let lines: BTreeSet<usize> = c.iter().map(|&i| self.graph.edges[i].line).collect();
        let known = self
            .conflicts
            .iter()
            .any(|k| k.edges.iter().map(|&i| self.graph.edges[i].line).collect::<BTreeSet<_>>() == lines);
        if !known && self.conflicts.len() < 8 {
            self.conflicts.push(Conflict { edges: c.clone(), gap });
        }
        Some(c)
    }

    /// Depth-limited search: any fix must remove a line from every conflict, so it is enough to
    /// branch on the lines of one conflict at a time.
    fn search(&mut self, removed: &mut Vec<usize>, depth: usize) {
        if self.checks >= CHECK_BUDGET {
            return;
        }
        let Some(c) = self.cycle(removed) else {
            let mut s = removed.clone();
            s.sort_unstable();
            self.found.insert(s);
            return;
        };
        if depth == 0 {
            return;
        }
        let lines: BTreeSet<usize> = c.iter().map(|&i| self.graph.edges[i].line).filter(|&l| l > 0).collect();
        for l in lines {
            removed.push(l);
            self.search(removed, depth - 1);
            removed.pop();
        }
    }
}

fn bounds(g: &Graph, people: usize, removed: &[usize]) -> Vec<(Bound, Bound)> {
    let keep = |e: &Edge| !removed.contains(&e.line);
    let up = g.shortest(ZERO, false, &keep);
    let down = g.shortest(ZERO, true, &keep);
    let b = |v: usize| Bound {
        lo: (down.dist[v] < INF).then(|| -down.dist[v]),
        hi: (up.dist[v] < INF).then_some(up.dist[v]),
    };
    (0..people).map(|p| (b(born(p)), b(died(p)))).collect()
}

/// How many candidate fixes are compared when choosing which one to assume.
pub const MAX_RANKED: usize = 20;

/// Total width of every range, counting an open end as 200 years.
fn looseness(dates: &[(Bound, Bound)]) -> i64 {
    let width = |b: &Bound| match (b.lo, b.hi) {
        (Some(a), Some(z)) => z - a,
        _ => 200,
    };
    dates.iter().map(|(b, d)| width(b) + width(d)).sum()
}

#[must_use]
pub fn analyse(tree: &Tree) -> Analysis {
    let graph = build(tree);
    let mut s = FixSearch {
        graph: &graph,
        checks: 0,
        found: BTreeSet::new(),
        conflicts: vec![],
    };
    if s.cycle(&[]).is_none() {
        let dates = bounds(&graph, tree.people.len(), &[]);
        return Analysis {
            graph,
            conflicts: vec![],
            fixes: vec![],
            fix_complete: true,
            assumed: vec![],
            dates: Some(dates),
        };
    }
    for depth in 1..=MAX_FIX {
        s.search(&mut Vec::new(), depth);
        if !s.found.is_empty() || s.checks >= CHECK_BUDGET {
            break;
        }
    }
    let fix_complete = !s.found.is_empty() && s.checks < CHECK_BUDGET;
    let fixes: Vec<Vec<usize>> = s.found.into_iter().collect();
    let conflicts = s.conflicts;
    // Of the equally small fixes, assume the one that keeps the other dates tightest: it throws
    // away the least information. Ties go to the earliest lines.
    let mut best: Option<(i64, Vec<usize>, Dates)> = None;
    for f in fixes.iter().take(MAX_RANKED) {
        let d = bounds(&graph, tree.people.len(), f);
        let w = looseness(&d);
        if best.as_ref().is_none_or(|(bw, _, _)| w < *bw) {
            best = Some((w, f.clone(), d));
        }
    }
    let (assumed, dates) = best.map_or((vec![], None), |(_, f, d)| (f, Some(d)));
    Analysis {
        graph,
        conflicts,
        fixes,
        fix_complete,
        assumed,
        dates,
    }
}

/// Why a bound holds: the chain of facts on its shortest path. `upper` picks the latest-possible
/// bound, otherwise the earliest-possible.
#[must_use]
pub fn explain(a: &Analysis, var: usize, upper: bool) -> Vec<usize> {
    let keep = |e: &Edge| !a.assumed.contains(&e.line);
    let paths = a.graph.shortest(ZERO, !upper, &keep);
    if paths.dist[var] >= INF {
        return vec![];
    }
    let mut chain = a.graph.path_to(&paths, var, !upper);
    if !upper {
        chain.reverse();
    }
    chain
}
