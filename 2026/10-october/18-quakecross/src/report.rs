//! The text report.

use crate::locate::{azimuth_gap, Problem, Solution};
use crate::parse::Picks;
use std::fmt::Write;

pub fn clock(seconds: f64) -> String {
    let total = seconds.rem_euclid(86_400.0);
    let cs = (total * 100.0).round() as u64; // centiseconds
    let (h, m, s, c) = (cs / 360_000 % 24, cs / 6_000 % 60, cs / 100 % 60, cs % 100);
    format!("{h:02}:{m:02}:{s:02}.{c:02}")
}

pub fn compass(bearing: f64) -> &'static str {
    const NAMES: [&str; 16] = [
        "N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW",
    ];
    NAMES[((bearing.rem_euclid(360.0) + 11.25) / 22.5) as usize % 16]
}

fn deg(lat: f64, lon: f64) -> String {
    format!(
        "{:.3}°{} {:.3}°{}",
        lat.abs(),
        if lat < 0.0 { "S" } else { "N" },
        lon.abs(),
        if lon < 0.0 { "W" } else { "E" }
    )
}

pub fn render(p: &Picks, prob: &Problem, first: &Solution, flagged: &[usize], s: &Solution, name: &str) -> String {
    let mut o = String::new();
    let used = prob.obs.len() - flagged.len();
    let _ = writeln!(
        o,
        "QUAKECROSS  {name}  ({}: {} stations, {} picks; P {} km/s, S {} km/s)\n",
        p.event,
        p.stations.len(),
        prob.obs.len(),
        p.vp,
        p.vs
    );

    let (lat, lon) = prob.proj.to_deg(s.x, s.y);
    // Nearest station, for a sense of place.
    let (ni, nd) = prob
        .station_km
        .iter()
        .enumerate()
        .map(|(i, &(x, y))| (i, (s.x - x).hypot(s.y - y)))
        .min_by(|a, b| a.1.total_cmp(&b.1))
        .unwrap_or((0, 0.0));
    let (sx, sy) = prob.station_km[ni];
    let bearing = (s.x - sx).atan2(s.y - sy).to_degrees().rem_euclid(360.0);
    let _ = writeln!(
        o,
        "  Epicentre     {}   ({:.1} km {} of {})",
        deg(lat, lon),
        nd,
        compass(bearing),
        p.stations[ni].name
    );
    match (prob.fixed_depth, s.depth_error) {
        (Some(d), _) => {
            let _ = writeln!(o, "  Depth         {d} km (fixed; use 'depth free' to solve for it)");
        }
        (None, Some(e)) => {
            let _ = writeln!(o, "  Depth         {:.1} km (90%: ±{:.1} km)", s.z, e);
        }
        (None, None) => {
            let _ = writeln!(o, "  Depth         {:.1} km (not well constrained)", s.z);
        }
    }
    let _ = writeln!(o, "  Origin time   {}", clock(s.t0));
    match s.ellipse {
        Some((a, b, az)) => {
            let _ = writeln!(
                o,
                "  90% error     within {:.1} km along {} and {:.1} km across",
                a,
                compass(az),
                b
            );
        }
        None => {
            let _ = writeln!(
                o,
                "  90% error     can't be estimated: the stations don't pin the location down"
            );
        }
    }
    let gap = azimuth_gap(&prob.station_km, s.x, s.y);
    let quality = if gap <= 180.0 {
        "the stations surround it"
    } else {
        "outside the network: treat the location with care"
    };
    let _ = writeln!(
        o,
        "  Fit           RMS {:.2} s over {} picks; largest gap between stations {:.0}° ({})",
        s.rms, used, gap, quality
    );

    if !flagged.is_empty() {
        let _ = writeln!(o, "\nPICKS THAT DON'T FIT (left out of the location above)");
        for &i in flagged {
            let k = &p.picks[prob.obs[i].pick];
            let r = s.residuals[i];
            let _ = writeln!(
                o,
                "  line {:<3} {} {}: arrived {:.2} s {} than the other picks predict.",
                k.line,
                p.stations[k.station].name,
                k.phase.name(),
                r.abs(),
                if r > 0.0 { "later" } else { "earlier" }
            );
        }
        let (flat, flon) = prob.proj.to_deg(first.x, first.y);
        let shift = (first.x - s.x).hypot(first.y - s.y);
        let _ = writeln!(
            o,
            "  Likely a P/S mix-up, a pick on noise, or a station clock error. With them included the\n  fit was RMS {:.2} s and the epicentre {:.1} km away, at {}.",
            first.rms,
            shift,
            deg(flat, flon)
        );
    }

    let _ = writeln!(o, "\nPICKS");
    let _ = writeln!(o, "  Station   Phase  Distance   Arrived       Off by");
    let mut order: Vec<usize> = (0..prob.obs.len()).collect();
    let dist = |i: usize| {
        let ob = &prob.obs[i];
        ((ob.x - s.x).powi(2) + (ob.y - s.y).powi(2)).sqrt()
    };
    order.sort_by(|&a, &b| dist(a).total_cmp(&dist(b)).then(a.cmp(&b)));
    for i in order {
        let k = &p.picks[prob.obs[i].pick];
        let mark = if flagged.contains(&i) { "  << doesn't fit" } else { "" };
        let _ = writeln!(
            o,
            "  {:<9} {:<6} {:>6.1} km  {}  {:>+6.2} s{}",
            p.stations[k.station].name,
            k.phase.name(),
            dist(i),
            clock(k.time),
            s.residuals[i],
            mark
        );
    }
    let _ = writeln!(
        o,
        "\nA uniform-Earth model: good for practice and a first location, not a replacement for a seismology centre's solution."
    );
    o
}
