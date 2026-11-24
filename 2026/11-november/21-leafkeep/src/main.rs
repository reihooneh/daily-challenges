//! Command line for Leafkeep.
//!
//!   leafkeep plan [--tea oolong] [--leaf 5] [--water 100] [--temp 95] [--pot gaiwan] [--first 20]
//!   leafkeep calibrate READINGS.csv [same options]
use leafkeep::{calibrate, check, clean, parse_readings, plan, predict, tea, vessel, Brew, Error, Session, MAX_STEEP};
use std::fmt::Write as _;
use std::fs;
use std::io::Write as _;
use std::process::ExitCode;

const USAGE: &str = "usage:
  leafkeep plan [options]                 time every infusion to match the first
  leafkeep calibrate READINGS.csv [opts]  fit the tea to refractometer readings, then plan
options:
  --tea green|white|oolong|black|puerh   (oolong)
  --leaf GRAMS       dry leaf, 0.5 to 30           (5)
  --water ML         water per infusion, 30 to 500 (100)
  --temp C           water temperature, 60 to 100  (95)
  --pot gaiwan|clay|glass                          (gaiwan)
  --first SECONDS    the first steep, 2 to 300     (20)
  --cups N           stop after N infusions, 1 to 30 (15)";

struct Options {
    tea: String,
    leaf: f64,
    water: f64,
    temp: f64,
    pot: String,
    first: f64,
    cups: usize,
    file: Option<String>,
}

fn parse(args: &[String]) -> Result<Options, String> {
    let mut o = Options {
        tea: "oolong".into(),
        leaf: 5.0,
        water: 100.0,
        temp: 95.0,
        pot: "gaiwan".into(),
        first: 20.0,
        cups: 15,
        file: None,
    };
    let mut i = 0;
    while i < args.len() {
        let a = args[i].as_str();
        let value = || args.get(i + 1).cloned().ok_or_else(|| format!("{} needs a value", clean(a)));
        let num = |v: String| v.parse::<f64>().map_err(|_| format!("{} needs a number", clean(a)));
        match a {
            "--tea" => o.tea = value()?,
            "--pot" => o.pot = value()?,
            "--leaf" => o.leaf = num(value()?)?,
            "--water" => o.water = num(value()?)?,
            "--temp" => o.temp = num(value()?)?,
            "--first" => o.first = num(value()?)?,
            "--cups" => o.cups = check("cups", num(value()?)?, 1.0, 30.0).map_err(|e| e.to_string())? as usize,
            _ if !a.starts_with("--") && o.file.is_none() => {
                o.file = Some(a.to_string());
                i += 1;
                continue;
            }
            _ => return Err(format!("unknown option {}", clean(a))),
        }
        i += 2;
    }
    Ok(o)
}

fn brew(o: &Options) -> Result<Brew, Error> {
    Brew::new(tea(&o.tea)?, o.leaf, o.water, o.temp, vessel(&o.pot)?)
}

fn mmss(s: f64) -> String {
    let s = s.round() as i64;
    if s < 60 {
        format!("{s} s")
    } else {
        format!("{}:{:02}", s / 60, s % 60)
    }
}

fn print_session(out: &mut String, b: &Brew, s: &Session) {
    writeln!(
        out,
        "{} tea, {} g in {} ml at {} °C. Every cup at {:.1} mg/ml (about {:.2} % TDS).\n",
        b.tea.name,
        b.leaf,
        b.water,
        b.temp,
        s.target,
        s.target / 10.0
    )
    .ok();
    writeln!(out, "  #   steep   poured off at   left in the leaves").ok();
    for (i, c) in s.cups.iter().enumerate() {
        let bar = "█".repeat((c.left * 30.0).round() as usize);
        writeln!(
            out,
            "  {:>2}  {:>6}   {:>5.0} °C         {:>3.0} % {bar}",
            i + 1,
            mmss(c.steep),
            c.end_temp,
            c.left * 100.0
        )
        .ok();
    }
    if s.spent {
        writeln!(
            out,
            "\nAfter {} infusions the leaves can't reach that strength even in {}: they're spent.",
            s.cups.len(),
            mmss(MAX_STEEP)
        )
        .ok();
    }
}

fn alternatives(out: &mut String, b: &Brew, s: &Session, cups: usize) {
    writeln!(out, "\nA lighter cup lasts longer:").ok();
    for share in [0.8, 0.6] {
        if let Ok(alt) = leafkeep::plan_to(b, s.target * share, None, cups) {
            let more = if alt.spent {
                format!("{} infusions", alt.cups.len())
            } else {
                format!("{cups}+ infusions")
            };
            writeln!(out, "  {:>3.0} % of this strength: {more}", share * 100.0).ok();
        }
    }
}

fn run(out: &mut String, args: &[String]) -> Result<(), String> {
    let (cmd, rest) = args.split_first().ok_or(USAGE)?;
    let o = parse(rest)?;
    match cmd.as_str() {
        "plan" => {
            if o.file.is_some() {
                return Err(USAGE.into());
            }
            let b = brew(&o).map_err(|e| e.to_string())?;
            let s = plan(&b, o.first, o.cups).map_err(|e| e.to_string())?;
            print_session(out, &b, &s);
            alternatives(out, &b, &s, o.cups);
        }
        "calibrate" => {
            let path = o.file.as_deref().ok_or("calibrate needs a readings file")?;
            let meta = fs::metadata(path).map_err(|_| format!("can't read {}", clean(path)))?;
            if !meta.is_file() || meta.len() > 64 * 1024 {
                return Err("the readings must be a regular file under 64 KB".into());
            }
            let text = fs::read_to_string(path).map_err(|_| format!("can't read {} as text", clean(path)))?;
            let readings = parse_readings(&text).map_err(|e| e.to_string())?;
            let b = brew(&o).map_err(|e| e.to_string())?;
            let (fitted, rms) = calibrate(&b, &readings);
            let fb = Brew { tea: fitted, ..b };
            writeln!(
                out,
                "Fitted to {} infusions (typical error {:.3} % TDS):",
                readings.len(),
                rms
            )
            .ok();
            writeln!(
                out,
                "  solubles {:.0} % of the leaf, surface rate ×{:.2}, inner rate ×{:.2} of the {} preset\n",
                fitted.soluble * 100.0,
                fitted.k_fast / b.tea.k_fast,
                fitted.k_slow / b.tea.k_slow,
                b.tea.name
            )
            .ok();
            let steeps: Vec<f64> = readings.iter().map(|r| r.steep).collect();
            writeln!(out, "  #   steep   measured   fitted").ok();
            for (i, (r, p)) in readings.iter().zip(predict(&fb, &steeps)).enumerate() {
                writeln!(out, "  {:>2}  {:>6}   {:>6.2} %   {:>5.2} %", i + 1, mmss(r.steep), r.tds, p).ok();
            }
            writeln!(out).ok();
            let s = plan(&fb, readings[0].steep.clamp(2.0, 300.0), o.cups).map_err(|e| e.to_string())?;
            print_session(out, &fb, &s);
            alternatives(out, &fb, &s, o.cups);
        }
        _ => return Err(USAGE.into()),
    }
    Ok(())
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut out = String::new();
    let result = run(&mut out, &args);
    // A closed pipe (leafkeep plan | head) isn't an error worth a panic.
    let _ = std::io::stdout().lock().write_all(out.as_bytes());
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("leafkeep: {e}");
            ExitCode::from(2)
        }
    }
}
