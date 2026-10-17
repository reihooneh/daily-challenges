//! Finding the earthquake: where and when it must have happened for the waves to reach each
//! station at the recorded times.
//!
//! Model: a uniform Earth with P speed vp and S speed vs. A wave from (x, y, depth) leaving at
//! origin time t0 reaches a station at distance r at t0 + r / v. We look for the x, y, (depth)
//! and t0 that make these predictions closest to the picks (least squares).

use crate::parse::{Phase, Picks};

const KM_PER_DEG_LAT: f64 = 110.57;
const KM_PER_DEG_LON: f64 = 111.32;
const MAX_SPREAD_KM: f64 = 1000.0;
/// Smallest pick error assumed (seconds): about the precision of a careful hand pick. Without a
/// floor, a lucky near-perfect fit would claim an unrealistically small error ellipse.
const FLOOR_SIGMA: f64 = 0.1;

/// A local flat map in kilometres around the stations (fine for a few hundred km).
#[derive(Debug, Clone, Copy)]
pub struct Projection {
    lat0: f64,
    lon0: f64,
    cos0: f64,
}

impl Projection {
    pub fn to_km(&self, lat: f64, lon: f64) -> (f64, f64) {
        let mut dlon = lon - self.lon0;
        if dlon > 180.0 {
            dlon -= 360.0;
        } else if dlon < -180.0 {
            dlon += 360.0;
        }
        (dlon * KM_PER_DEG_LON * self.cos0, (lat - self.lat0) * KM_PER_DEG_LAT)
    }
    pub fn to_deg(&self, x: f64, y: f64) -> (f64, f64) {
        let lat = self.lat0 + y / KM_PER_DEG_LAT;
        let mut lon = self.lon0 + x / (KM_PER_DEG_LON * self.cos0);
        if lon > 180.0 {
            lon -= 360.0;
        } else if lon < -180.0 {
            lon += 360.0;
        }
        (lat, lon)
    }
}

/// One observation ready for the solver.
#[derive(Debug, Clone, Copy)]
pub struct Obs {
    pub pick: usize,
    pub x: f64,
    pub y: f64,
    pub v: f64,
    pub t: f64,
}

#[derive(Debug, Clone)]
pub struct Solution {
    pub x: f64,
    pub y: f64,
    pub z: f64,
    pub t0: f64,
    /// Observed minus predicted arrival time, per observation (seconds).
    pub residuals: Vec<f64>,
    pub rms: f64,
    /// 90% confidence ellipse of the epicentre: semi-axes in km and the long axis bearing.
    pub ellipse: Option<(f64, f64, f64)>,
    pub depth_error: Option<f64>,
}

#[derive(Debug)]
pub struct Problem {
    pub proj: Projection,
    pub obs: Vec<Obs>,
    pub fixed_depth: Option<f64>,
    pub station_km: Vec<(f64, f64)>,
}

impl Problem {
    pub fn new(p: &Picks) -> Result<Self, String> {
        let n = p.stations.len() as f64;
        let lat0 = p.stations.iter().map(|s| s.lat).sum::<f64>() / n;
        // Average longitude through unit vectors, so stations either side of 180° work.
        let (sx, sy) = p.stations.iter().fold((0.0, 0.0), |(a, b), s| {
            (a + s.lon.to_radians().cos(), b + s.lon.to_radians().sin())
        });
        let lon0 = sy.atan2(sx).to_degrees();
        if lat0.abs() > 80.0 {
            return Err("stations this close to a pole aren't supported (the flat map breaks down)".into());
        }
        let proj = Projection {
            lat0,
            lon0,
            cos0: lat0.to_radians().cos(),
        };
        let station_km: Vec<(f64, f64)> = p.stations.iter().map(|s| proj.to_km(s.lat, s.lon)).collect();
        if station_km.iter().any(|&(x, y)| x.hypot(y) > MAX_SPREAD_KM) {
            return Err("stations are spread over more than 1,000 km; Quakecross is for local and regional quakes".into());
        }
        // Picks that cross midnight: bring early-morning times after late-evening ones.
        let times: Vec<f64> = p.picks.iter().map(|k| k.time).collect();
        let lo = times.iter().cloned().fold(f64::INFINITY, f64::min);
        let hi = times.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
        let wrap = hi - lo > 43_200.0;
        let obs: Vec<Obs> = p
            .picks
            .iter()
            .enumerate()
            .map(|(i, k)| {
                let (x, y) = station_km[k.station];
                let t = if wrap && k.time < 43_200.0 {
                    k.time + 86_400.0
                } else {
                    k.time
                };
                Obs {
                    pick: i,
                    x,
                    y,
                    v: if k.phase == Phase::P { p.vp } else { p.vs },
                    t,
                }
            })
            .collect();
        let spread =
            obs.iter().map(|o| o.t).fold(f64::NEG_INFINITY, f64::max) - obs.iter().map(|o| o.t).fold(f64::INFINITY, f64::min);
        if spread > 600.0 {
            return Err("the picks span more than 10 minutes; they can't all be from one local quake".into());
        }
        let unknowns = if p.depth.is_some() { 3 } else { 4 };
        if obs.len() < unknowns + 1 {
            return Err(format!(
                "{} picks aren't enough: at least {} are needed to locate a quake and check the fit",
                obs.len(),
                unknowns + 1
            ));
        }
        let distinct = station_km.len();
        if distinct < 3 {
            return Err(
                "at least 3 stations are needed (with 2, the quake could be on either side of the line between them)".into(),
            );
        }
        Ok(Problem {
            proj,
            obs,
            fixed_depth: p.depth,
            station_km,
        })
    }

    pub fn proj_to_deg(&self, x: f64, y: f64) -> (f64, f64) {
        self.proj.to_deg(x, y)
    }

    pub fn unknowns(&self) -> usize {
        if self.fixed_depth.is_some() {
            3
        } else {
            4
        }
    }

    /// Locate using only the observations whose index is in `use_obs`.
    pub fn solve(&self, use_obs: &[usize]) -> Solution {
        let obs: Vec<Obs> = use_obs.iter().map(|&i| self.obs[i]).collect();
        let start = self.grid_start(&obs);
        self.solve_from(use_obs, start)
    }

    /// Refine from a known starting point (used when one pick at a time is left out).
    pub fn solve_from(&self, use_obs: &[usize], start: [f64; 3]) -> Solution {
        let obs: Vec<Obs> = use_obs.iter().map(|&i| self.obs[i]).collect();
        let mut s = self.refine(&obs, start);
        s.residuals = self.obs.iter().map(|o| o.t - predict(o, s.x, s.y, s.z, s.t0)).collect();
        s
    }

    /// Coarse grid search: avoids the wrong local minimum that Gauss-Newton alone can fall into.
    fn grid_start(&self, obs: &[Obs]) -> [f64; 3] {
        let (mut x0, mut x1, mut y0, mut y1) = (f64::INFINITY, f64::NEG_INFINITY, f64::INFINITY, f64::NEG_INFINITY);
        for &(x, y) in &self.station_km {
            x0 = x0.min(x);
            x1 = x1.max(x);
            y0 = y0.min(y);
            y1 = y1.max(y);
        }
        let pad = 150.0;
        let depths: Vec<f64> = match self.fixed_depth {
            Some(d) => vec![d],
            None => vec![2.0, 8.0, 15.0, 30.0, 60.0],
        };
        let steps = 60;
        let mut best = (f64::INFINITY, [0.0, 0.0, depths[0]]);
        for &z in &depths {
            for i in 0..=steps {
                for j in 0..=steps {
                    let x = x0 - pad + (x1 - x0 + 2.0 * pad) * f64::from(i) / f64::from(steps);
                    let y = y0 - pad + (y1 - y0 + 2.0 * pad) * f64::from(j) / f64::from(steps);
                    let t0 = best_t0(obs, x, y, z);
                    let rss: f64 = obs.iter().map(|o| (o.t - predict(o, x, y, z, t0)).powi(2)).sum();
                    if rss < best.0 {
                        best = (rss, [x, y, z]);
                    }
                }
            }
        }
        best.1
    }

    /// Levenberg–Marquardt: Gauss–Newton steps, damped when a step would make things worse.
    fn refine(&self, obs: &[Obs], start: [f64; 3]) -> Solution {
        let free = self.fixed_depth.is_none();
        let m = self.unknowns();
        let [mut x, mut y, mut z] = start;
        let mut t0 = best_t0(obs, x, y, z);
        let rss_of =
            |x: f64, y: f64, z: f64, t0: f64| -> f64 { obs.iter().map(|o| (o.t - predict(o, x, y, z, t0)).powi(2)).sum() };
        let mut rss = rss_of(x, y, z, t0);
        let mut lambda = 1e-3;
        for _ in 0..200 {
            let (jtj, jtr) = normal_equations(obs, x, y, z, t0, free);
            let mut a = jtj.clone();
            for k in 0..m {
                a[k][k] += lambda * jtj[k][k].max(1e-12);
            }
            let Some(step) = solve(a, jtr) else { break };
            let (nx, ny) = (x + step[0], y + step[1]);
            let nz = if free { (z + step[2]).clamp(0.0, 700.0) } else { z };
            let nt0 = t0 + step[m - 1];
            let new_rss = rss_of(nx, ny, nz, nt0);
            if new_rss < rss {
                let gain = rss - new_rss;
                (x, y, z, t0, rss) = (nx, ny, nz, nt0, new_rss);
                lambda = (lambda / 3.0).max(1e-9);
                if gain < 1e-12 && step.iter().map(|v| v.abs()).fold(0.0, f64::max) < 1e-6 {
                    break;
                }
            } else {
                lambda *= 4.0;
                if lambda > 1e9 {
                    break;
                }
            }
        }
        let n = obs.len();
        let sigma2 = if n > m {
            (rss / (n - m) as f64).max(FLOOR_SIGMA * FLOOR_SIGMA)
        } else {
            FLOOR_SIGMA * FLOOR_SIGMA
        };
        let (jtj, _) = normal_equations(obs, x, y, z, t0, free);
        let cov = invert(jtj).map(|c| {
            c.into_iter()
                .map(|row| row.into_iter().map(|v| v * sigma2).collect())
                .collect::<Vec<Vec<f64>>>()
        });
        let ellipse = cov.as_ref().map(|c| ellipse90(c[0][0], c[1][1], c[0][1]));
        let depth_error = if free {
            cov.as_ref().map(|c| 1.645 * c[2][2].max(0.0).sqrt())
        } else {
            None
        };
        Solution {
            x,
            y,
            z,
            t0,
            residuals: vec![],
            rms: (rss / n as f64).sqrt(),
            ellipse,
            depth_error,
        }
    }
}

pub fn predict(o: &Obs, x: f64, y: f64, z: f64, t0: f64) -> f64 {
    t0 + ((o.x - x).powi(2) + (o.y - y).powi(2) + z * z).sqrt() / o.v
}

/// For a fixed place, the best origin time is the average of (arrival - travel time).
fn best_t0(obs: &[Obs], x: f64, y: f64, z: f64) -> f64 {
    obs.iter().map(|o| o.t - predict(o, x, y, z, 0.0)).sum::<f64>() / obs.len() as f64
}

/// JᵀJ and Jᵀr for the unknowns (x, y, [z,] t0).
fn normal_equations(obs: &[Obs], x: f64, y: f64, z: f64, t0: f64, free: bool) -> (Vec<Vec<f64>>, Vec<f64>) {
    let m = if free { 4 } else { 3 };
    let mut jtj = vec![vec![0.0; m]; m];
    let mut jtr = vec![0.0; m];
    for o in obs {
        let r = ((o.x - x).powi(2) + (o.y - y).powi(2) + z * z).sqrt().max(1e-6);
        let mut row = vec![(x - o.x) / (r * o.v), (y - o.y) / (r * o.v)];
        if free {
            row.push(z / (r * o.v));
        }
        row.push(1.0);
        let res = o.t - predict(o, x, y, z, t0);
        for a in 0..m {
            jtr[a] += row[a] * res;
            for b in 0..m {
                jtj[a][b] += row[a] * row[b];
            }
        }
    }
    (jtj, jtr)
}

/// Gaussian elimination with partial pivoting (the systems here are at most 4×4).
pub fn solve(mut a: Vec<Vec<f64>>, mut b: Vec<f64>) -> Option<Vec<f64>> {
    let n = b.len();
    for col in 0..n {
        let pivot = (col..n).max_by(|&i, &j| a[i][col].abs().total_cmp(&a[j][col].abs()))?;
        if a[pivot][col].abs() < 1e-14 {
            return None;
        }
        a.swap(col, pivot);
        b.swap(col, pivot);
        for row in col + 1..n {
            let f = a[row][col] / a[col][col];
            let pivot_row = a[col].clone();
            for (v, p) in a[row].iter_mut().zip(pivot_row).skip(col) {
                *v -= f * p;
            }
            b[row] -= f * b[col];
        }
    }
    let mut x = vec![0.0; n];
    for row in (0..n).rev() {
        let s: f64 = (row + 1..n).map(|k| a[row][k] * x[k]).sum();
        x[row] = (b[row] - s) / a[row][row];
    }
    x.iter().all(|v| v.is_finite()).then_some(x)
}

pub fn invert(a: Vec<Vec<f64>>) -> Option<Vec<Vec<f64>>> {
    let n = a.len();
    let mut cols = Vec::with_capacity(n);
    for k in 0..n {
        let mut e = vec![0.0; n];
        e[k] = 1.0;
        cols.push(solve(a.clone(), e)?);
    }
    Some((0..n).map(|i| (0..n).map(|j| cols[j][i]).collect()).collect())
}

/// 90% confidence ellipse from a 2×2 covariance: semi-axes (km) and the bearing of the long axis.
/// For two unknowns, 90% of a 2D normal distribution lies within sqrt(4.605) standard deviations.
pub fn ellipse90(sxx: f64, syy: f64, sxy: f64) -> (f64, f64, f64) {
    let mean = (sxx + syy) / 2.0;
    let diff = ((sxx - syy) / 2.0).hypot(sxy);
    let (l1, l2) = ((mean + diff).max(0.0), (mean - diff).max(0.0));
    // Direction of the long axis, as a compass bearing (0 = north, clockwise).
    let angle_from_x = 0.5 * (2.0 * sxy).atan2(sxx - syy);
    let bearing = (90.0 - angle_from_x.to_degrees()).rem_euclid(180.0);
    let k = 4.605_f64.sqrt();
    (k * l1.sqrt(), k * l2.sqrt(), bearing)
}

/// The largest angle, seen from the epicentre, with no station in it. Over 180° the quake is
/// outside the network and the location is much less certain.
pub fn azimuth_gap(stations: &[(f64, f64)], x: f64, y: f64) -> f64 {
    let mut az: Vec<f64> = stations
        .iter()
        .map(|&(sx, sy)| (sx - x).atan2(sy - y).to_degrees().rem_euclid(360.0))
        .collect();
    az.sort_by(f64::total_cmp);
    let mut gap: f64 = 360.0 - az[az.len() - 1] + az[0];
    for w in az.windows(2) {
        gap = gap.max(w[1] - w[0]);
    }
    gap
}

/// Picks that don't fit: remove the worst one at a time while it clearly doesn't fit, up to 3.
/// A pick is flagged when leaving it out makes the rest fit much better and its own misfit is
/// far beyond what the others show.
pub fn find_outliers(p: &Problem) -> (Vec<usize>, Solution) {
    let mut keep: Vec<usize> = (0..p.obs.len()).collect();
    let mut flagged = vec![];
    let mut sol = p.solve(&keep);
    while flagged.len() < 3 && keep.len() > p.unknowns() + 2 {
        let mut best: Option<(f64, usize, Solution)> = None;
        for (pos, _) in keep.iter().enumerate() {
            let mut rest = keep.clone();
            let removed = rest.remove(pos);
            let s = p.solve_from(&rest, [sol.x, sol.y, sol.z]);
            let rms_rest = (rest.iter().map(|&i| s.residuals[i].powi(2)).sum::<f64>() / rest.len() as f64).sqrt();
            if best.as_ref().is_none_or(|b| rms_rest < b.0) {
                best = Some((rms_rest, removed, s));
            }
        }
        let Some((rms_rest, removed, s)) = best else { break };
        let off = s.residuals[removed].abs();
        if off > 4.0 * rms_rest.max(FLOOR_SIGMA) && off > 0.5 && sol.rms > 2.0 * rms_rest {
            flagged.push(removed);
            keep.retain(|&i| i != removed);
            sol = s;
        } else {
            break;
        }
    }
    (flagged, sol)
}
