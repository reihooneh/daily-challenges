use std::io::Read;
use std::process::ExitCode;

use loomfix::audit::{audit, longest_on, MAX_SIMS};
use loomfix::fit::identify;
use loomfix::input::{self, Named, Timing, MAX_BYTES};
use loomfix::{pattern, render};

const USAGE: &str = "usage:
  loomfix id LIGHTS WATCH          which light in the list made these timings
  loomfix audit LIGHTS [--counted] [--sims N] [--seed N]
                                   which lights in the list are easy to mix up
  loomfix show CHARACTER           draw one period, e.g. loomfix show \"Fl(2) W 10s\"
A file name of - reads standard input.";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("loomfix: {e}");
            ExitCode::from(2)
        }
    }
}

fn run(args: &[String]) -> Result<(), String> {
    let a: Vec<&str> = args.iter().map(String::as_str).collect();
    match a.as_slice() {
        ["show", ch] => {
            let l = pattern::parse(ch)?;
            let (_, res) = render::columns(&l);
            println!("{}  ({} s a column; # on, . off)", l.text, fmt(res));
            println!("  {}", render::strip(&l));
            Ok(())
        }
        ["id", lights, watch] => {
            if *lights == "-" && *watch == "-" {
                return Err("only one file can be standard input".into());
            }
            id(&input::lights(&read(lights)?)?, &input::watch(&read(watch)?)?);
            Ok(())
        }
        ["audit", lights, rest @ ..] => {
            let (mut timing, mut sims, mut seed) = (Timing::Stopwatch, 200usize, 1u64);
            let mut it = rest.iter();
            while let Some(&opt) = it.next() {
                match opt {
                    "--counted" => timing = Timing::Counted,
                    "--sims" | "--seed" => {
                        let v: u64 = it
                            .next()
                            .and_then(|v| v.parse().ok())
                            .ok_or(format!("{opt} needs a whole number"))?;
                        if opt == "--seed" {
                            seed = v;
                        } else if (1..=MAX_SIMS as u64).contains(&v) {
                            sims = v as usize;
                        } else {
                            return Err(format!("--sims must be from 1 to {MAX_SIMS}"));
                        }
                    }
                    _ => return Err(format!("unknown option\n{USAGE}")),
                }
            }
            report_audit(&input::lights(&read(lights)?)?, timing, sims, seed);
            Ok(())
        }
        _ => Err(USAGE.into()),
    }
}

/// Reads a regular file (not a link, device or folder) or standard input, at most 64 KB.
fn read(path: &str) -> Result<String, String> {
    let mut buf = Vec::new();
    let limit = MAX_BYTES as u64 + 1;
    if path == "-" {
        std::io::stdin()
            .take(limit)
            .read_to_end(&mut buf)
            .map_err(|_| "couldn't read standard input")?;
    } else {
        let meta = std::fs::symlink_metadata(path).map_err(|_| "couldn't open a file (check the name)")?;
        if !meta.file_type().is_file() {
            return Err("only regular files are read (not links, folders or devices)".into());
        }
        std::fs::File::open(path)
            .and_then(|f| f.take(limit).read_to_end(&mut buf))
            .map_err(|_| "couldn't read a file")?;
    }
    if buf.len() > MAX_BYTES {
        return Err("a file is over 64 KB".into());
    }
    String::from_utf8(buf).map_err(|_| "a file isn't valid UTF-8 text".into())
}

fn fmt(x: f64) -> String {
    let s = format!("{x:.2}");
    s.trim_end_matches('0').trim_end_matches('.').to_string()
}

fn id(lights: &[Named], w: &input::Watch) {
    let span = w.events[w.events.len() - 1].0 - w.events[0].0;
    let how = if w.timing == Timing::Counted {
        "counted seconds"
    } else {
        "stopwatch"
    };
    let colour = w.colour.map_or("colour not noted".to_string(), |c| format!("colour {c}"));
    println!("LOOMFIX  {} times over {} s ({how}), {colour}\n", w.events.len(), fmt(span));
    let ranked = identify(lights, w);
    let Some(top) = ranked.first() else {
        println!("No light in the list can make these timings (check the colour, and whether you timed flashes or eclipses).");
        return;
    };
    let best = &lights[top.index];
    let f = top.fit;
    println!(
        "  Most likely: {}  {}  ({:.0}%)",
        best.name,
        best.light.text,
        100.0 * top.prob
    );
    println!(
        "  {} of {} times paired with its rhythm, {} flash{} missed, typical error {} s",
        f.matched,
        w.events.len(),
        f.missed,
        if f.missed == 1 { "" } else { "es" },
        fmt(f.rms)
    );
    if best.light.period_tol > 0.0 || (f.scale - 1.0).abs() > 0.03 {
        println!(
            "  Its period as you timed it: {} s (charted {} s)",
            fmt(f.scale * best.light.spec.period),
            fmt(best.light.spec.period)
        );
    }
    if !f.is_good() {
        println!(
            "\n  None of the lights fits well: it may not be in the list, or some times are off. Time another period or two."
        );
    } else if top.prob < 0.8 {
        println!("\n  Not certain. Note the colour, time two or three full periods, and use a stopwatch if you can.");
    }

    println!(
        "\n  {:<3} {:<22} {:<16} {:>6}  {:>6}  {:>6}  {:>5}",
        "#", "Light", "Character", "Chance", "Paired", "Missed", "Stray"
    );
    for (k, r) in ranked.iter().take(8).enumerate() {
        let n = &lights[r.index];
        println!(
            "  {:<3} {:<22} {:<16} {:>5.0}%  {:>6}  {:>6}  {:>5}",
            k + 1,
            n.name,
            n.light.text,
            100.0 * r.prob,
            format!("{}/{}", r.fit.matched, w.events.len()),
            r.fit.missed,
            r.fit.stray
        );
    }
    let (_, res) = render::columns(&best.light);
    println!(
        "\n  One period of {}, {} s a column (# on, . off; ^ your 'on' times, v your 'off' times):",
        best.name,
        fmt(res)
    );
    println!("    light  {}", render::strip(&best.light));
    println!("    you    {}", render::folded(&best.light, w, &f));
}

fn report_audit(lights: &[Named], timing: Timing, sims: usize, seed: u64) {
    let how = if timing == Timing::Counted {
        "counting seconds"
    } else {
        "with a stopwatch"
    };
    println!(
        "LOOMFIX audit  {} lights, {sims} simulated watches of each, timed {how}\n",
        lights.len()
    );
    println!(
        "  {:<22} {:<16} {:>11}   Most often taken for",
        "Light", "Character", "Named right"
    );
    let results = audit(lights, timing, sims, seed);
    let mut pairs: Vec<(usize, usize, f64)> = Vec::new();
    for c in &results {
        let n = &lights[c.light];
        if c.sims == 0 {
            println!(
                "  {:<22} {:<16} {:>11}   (a fixed light has no rhythm to time)",
                n.name, n.light.text, "-"
            );
            continue;
        }
        let other = c.mistaken.first().map_or(String::new(), |&(j, k)| {
            format!("{} ({:.0}%)", lights[j].name, 100.0 * k as f64 / c.sims as f64)
        });
        println!(
            "  {:<22} {:<16} {:>10.0}%   {other}",
            n.name,
            n.light.text,
            100.0 * c.right as f64 / c.sims as f64
        );
        for &(j, k) in &c.mistaken {
            let rate = k as f64 / c.sims as f64;
            if rate > 0.05 {
                pairs.push((c.light, j, rate));
            }
        }
    }
    if pairs.is_empty() {
        println!("\nNo two lights are mixed up in more than 5% of watches.");
    } else {
        println!("\nEasy to mix up (more than 5% of watches):");
        for (i, j, rate) in pairs {
            println!(
                "  - {} ({}) was taken for {} ({}) in {:.0}%",
                lights[i].name,
                lights[i].light.text,
                lights[j].name,
                lights[j].light.text,
                100.0 * rate
            );
            let (a, b) = (longest_on(&lights[i].light), longest_on(&lights[j].light));
            if (a - b).abs() >= 1.0 && a.is_finite() && b.is_finite() {
                let (long, short) = if a > b { (i, j) } else { (j, i) };
                println!(
                    "      Tell them apart by flash length: {} stays on for about {} s, {} for {} s.",
                    lights[long].name,
                    fmt(a.max(b)),
                    lights[short].name,
                    fmt(a.min(b))
                );
            }
        }
        if timing == Timing::Counted {
            println!("  A stopwatch helps tell apart lights whose periods differ by a few percent.");
        }
    }
}
