//! Difference constraints and Bellman-Ford.
//!
//! Every fact about years has the form `x - y <= c`: "Kate was born at most 50 years after Mary"
//! is `born(Kate) - born(Mary) <= 50`. Such a system becomes a graph with an edge `y -> x` of
//! weight `c`. Shortest paths then give the tightest bounds, and a cycle of negative total weight
//! is exactly a set of facts that can't all be true.

/// Larger than any real distance, small enough that adding an edge weight can't overflow.
pub const INF: i64 = i64::MAX / 4;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Edge {
    pub from: usize,
    pub to: usize,
    /// `value(to) - value(from) <= w`
    pub w: i64,
    /// The file line the fact came from; 0 for a rule of thumb that always applies.
    pub line: usize,
    pub why: String,
}

#[derive(Debug, Clone, Default)]
pub struct Graph {
    pub nodes: usize,
    pub edges: Vec<Edge>,
}

/// The result of a shortest-path run: distance and the edge that last improved each node.
pub struct Paths {
    pub dist: Vec<i64>,
    pub pred: Vec<Option<usize>>,
}

impl Graph {
    #[must_use]
    pub fn new(nodes: usize) -> Self {
        Self {
            nodes,
            edges: Vec::new(),
        }
    }

    /// Adds the fact `x - y <= c`.
    pub fn le(&mut self, x: usize, y: usize, c: i64, line: usize, why: impl Into<String>) {
        self.edges.push(Edge {
            from: y,
            to: x,
            w: c,
            line,
            why: why.into(),
        });
    }

    /// Finds a cycle of negative weight among the edges `keep` allows, as edge indices in
    /// order around the cycle, or `None` if the facts are consistent.
    #[must_use]
    pub fn negative_cycle(&self, keep: &dyn Fn(&Edge) -> bool) -> Option<Vec<usize>> {
        // Starting every node at 0 is the same as a hidden source joined to all of them.
        let mut dist = vec![0i64; self.nodes];
        let mut pred: Vec<Option<usize>> = vec![None; self.nodes];
        let mut last = None;
        for _ in 0..self.nodes {
            last = None;
            for (i, e) in self.edges.iter().enumerate() {
                if keep(e) && dist[e.from] + e.w < dist[e.to] {
                    dist[e.to] = dist[e.from] + e.w;
                    pred[e.to] = Some(i);
                    last = Some(e.to);
                }
            }
            last?;
        }
        // Still improving after `nodes` rounds: walk back far enough to be inside the cycle.
        let mut x = last?;
        for _ in 0..self.nodes {
            x = self.edges[pred[x]?].from;
        }
        let start = x;
        let mut cycle = Vec::new();
        loop {
            let e = pred[x]?;
            cycle.push(e);
            x = self.edges[e].from;
            if x == start || cycle.len() > self.nodes {
                break;
            }
        }
        cycle.reverse();
        Some(cycle)
    }

    /// Shortest distances from `src` (along the edges, or against them when `reverse`).
    /// Only meaningful when [`Graph::negative_cycle`] found nothing for the same `keep`.
    #[must_use]
    pub fn shortest(&self, src: usize, reverse: bool, keep: &dyn Fn(&Edge) -> bool) -> Paths {
        let mut dist = vec![INF; self.nodes];
        let mut pred = vec![None; self.nodes];
        dist[src] = 0;
        for _ in 1..self.nodes.max(2) {
            let mut changed = false;
            for (i, e) in self.edges.iter().enumerate() {
                let (a, b) = if reverse { (e.to, e.from) } else { (e.from, e.to) };
                if keep(e) && dist[a] < INF && dist[a] + e.w < dist[b] {
                    dist[b] = dist[a] + e.w;
                    pred[b] = Some(i);
                    changed = true;
                }
            }
            if !changed {
                break;
            }
        }
        Paths { dist, pred }
    }

    /// The edges on the shortest path from the source to `x`, source end first.
    #[must_use]
    pub fn path_to(&self, paths: &Paths, x: usize, reverse: bool) -> Vec<usize> {
        let mut out = Vec::new();
        let mut at = x;
        while let Some(e) = paths.pred[at] {
            out.push(e);
            at = if reverse { self.edges[e].to } else { self.edges[e].from };
            if out.len() > self.nodes {
                break;
            }
        }
        out.reverse();
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bounds_and_cycles() {
        // 0 is the zero point; a in [10, 20]; b - a in [5, 5]
        let mut g = Graph::new(3);
        g.le(1, 0, 20, 1, "a <= 20");
        g.le(0, 1, -10, 1, "a >= 10");
        g.le(2, 1, 5, 2, "b <= a + 5");
        g.le(1, 2, -5, 2, "b >= a + 5");
        assert!(g.negative_cycle(&|_| true).is_none());
        let up = g.shortest(0, false, &|_| true);
        let down = g.shortest(0, true, &|_| true);
        assert_eq!((up.dist[2], -down.dist[2]), (25, 15));
        assert_eq!(g.path_to(&up, 2, false).len(), 2);

        g.le(2, 0, 12, 3, "b <= 12");
        let c = g.negative_cycle(&|_| true).expect("b <= 12 contradicts b >= 15");
        let total: i64 = c.iter().map(|&i| g.edges[i].w).sum();
        assert!(total < 0);
        // Following the cycle returns to where it started.
        for k in 0..c.len() {
            assert_eq!(g.edges[c[k]].to, g.edges[c[(k + 1) % c.len()]].from);
        }
        assert!(g.negative_cycle(&|e| e.line != 3).is_none());
    }
}
