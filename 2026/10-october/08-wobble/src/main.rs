use std::process::ExitCode;

use wobble::advice::advise;
use wobble::metrics::{measure, Metrics};
use wobble::pid::{Gains, MAX_GAIN};
use wobble::plant::Kind;
use wobble::plot::render;
use wobble::sim::{simulate, Setup, MAX_DURATION};
use wobble::tune::tune;

const USAGE: &str = "\
Usage:
  wobble run  --plant NAME [--kp N] [--ki N] [--kd N] [options]   simulate and explain
  wobble tune --plant NAME [--kp N] [--ki N] [--kd N] [options]   search for better gains
  wobble plants                                                  list what can be simulated

Options:
  --time SECONDS    how long to simulate (default depends on the plant, max 120)
  --limit N         the hardest the actuator can push (default 10)
  --setpoint N      the target value (default 1)
  --no-plot         leave out the graph

Exit codes: 0 stable, 1 unstable, 2 the arguments could not be understood.
";

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok((text, stable)) => {
            print!("{text}");
            if stable {
                ExitCode::SUCCESS
            } else {
                ExitCode::from(1)
            }
        }
        Err(message) => {
            eprintln!("wobble: {message}");
            ExitCode::from(2)
        }
    }
}

/// Parses a plain decimal number. Scientific notation, signs, "inf" and "nan"
/// are all refused before the text ever reaches the float parser.
fn number(text: &str, name: &str, min: f64, max: f64) -> Result<f64, String> {
    let plain = !text.is_empty()
        && text.len() <= 12
        && text.bytes().all(|b| b.is_ascii_digit() || b == b'.')
        && text.bytes().filter(|&b| b == b'.').count() <= 1
        && text.bytes().any(|b| b.is_ascii_digit());
    let value: f64 = if plain {
        text.parse().map_err(|_| ())
    } else {
        Err(())
    }
    .map_err(|_| format!("{name} needs a plain number such as 2 or 0.5"))?;
    if !(min..=max).contains(&value) {
        return Err(format!("{name} must be between {min} and {max}"));
    }
    Ok(value)
}

fn run(args: &[String]) -> Result<(String, bool), String> {
    let command = args.first().map(String::as_str).unwrap_or("");
    match command {
        "-h" | "--help" | "help" => return Ok((USAGE.to_string(), true)),
        "plants" if args.len() == 1 => {
            let list: String = Kind::ALL
                .iter()
                .map(|k| format!("  {:<7} {}\n", k.name(), k.describe()))
                .collect();
            return Ok((list, true));
        }
        "run" | "tune" => {}
        _ => return Err(format!("unknown command\n\n{USAGE}")),
    }

    let mut plant = None;
    let mut gains = Gains {
        kp: 1.0,
        ki: 0.0,
        kd: 0.0,
    };
    let (mut duration, mut limit, mut setpoint, mut plot) = (None, 10.0, 1.0, true);

    let mut rest = args[1..].iter();
    while let Some(flag) = rest.next() {
        if flag == "--no-plot" {
            plot = false;
            continue;
        }
        let known = [
            "--plant",
            "--kp",
            "--ki",
            "--kd",
            "--time",
            "--limit",
            "--setpoint",
        ];
        if !known.contains(&flag.as_str()) {
            return Err("unknown option (see --help)".to_string());
        }
        let value = rest.next().ok_or_else(|| format!("{flag} needs a value"))?;
        match flag.as_str() {
            "--plant" => {
                plant = Some(Kind::parse(value).ok_or("unknown plant (try: wobble plants)")?)
            }
            "--kp" => gains.kp = number(value, "--kp", 0.0, MAX_GAIN)?,
            "--ki" => gains.ki = number(value, "--ki", 0.0, MAX_GAIN)?,
            "--kd" => gains.kd = number(value, "--kd", 0.0, MAX_GAIN)?,
            "--time" => duration = Some(number(value, "--time", 0.1, MAX_DURATION)?),
            "--limit" => limit = number(value, "--limit", 0.01, 1_000_000.0)?,
            _ => setpoint = number(value, "--setpoint", 0.001, 1_000_000.0)?,
        }
    }
    let plant = plant.ok_or("choose what to control with --plant (try: wobble plants)")?;
    let setup = Setup {
        plant,
        gains,
        setpoint,
        duration: duration.unwrap_or(plant.default_duration()),
        limit,
    };

    if command == "run" {
        return Ok(report(&setup, plot));
    }

    let tuned = tune(&setup);
    let after = Setup {
        gains: tuned.gains,
        ..setup
    };
    let mut text = format!(
        "Tried {} combinations of gains.\n\nBefore:  Kp {:.3}  Ki {:.3}  Kd {:.3}\n{}\nAfter:   Kp {:.3}  Ki {:.3}  Kd {:.3}\n",
        tuned.evaluations,
        gains.kp,
        gains.ki,
        gains.kd,
        summary(&measure(&simulate(&setup))),
        tuned.gains.kp,
        tuned.gains.ki,
        tuned.gains.kd,
    );
    let (after_report, stable) = report(&after, plot);
    text.push_str(&after_report);
    text.push_str(
        "\nThese gains suit this simulated plant. On real hardware, start lower and work up.\n",
    );
    Ok((text, stable))
}

fn summary(m: &Metrics) -> String {
    let seconds = |t: Option<f64>| t.map_or("never".to_string(), |s| format!("{s:.2} s"));
    format!(
        "  Rise time (10% to 90%):  {}\n  Overshoot:               {:.1}%\n  Settles within 2%:       {}\n  \
         Steady error:            {:.1}%\n  Swings back past target: {}\n  Actuator at its limit:   {:.0}% of the time\n",
        seconds(m.rise_time),
        m.overshoot_percent,
        seconds(m.settling_time),
        m.steady_state_error_percent,
        m.crossings,
        m.saturated_percent,
    )
}

fn report(setup: &Setup, plot: bool) -> (String, bool) {
    let result = simulate(setup);
    let metrics = measure(&result);
    let mut text = String::new();
    if plot {
        text.push_str(&format!(
            "{} to a target of {}\n\n",
            setup.plant.describe(),
            setup.setpoint
        ));
        text.push_str(&render(&result));
        text.push('\n');
    }
    if metrics.diverged {
        text.push_str("  The output ran away and the simulation was stopped.\n");
    } else {
        text.push_str(&summary(&metrics));
    }
    text.push('\n');
    for line in advise(&metrics, &setup.gains) {
        text.push_str(&format!("  - {line}\n"));
    }
    (text, !(metrics.diverged || metrics.growing))
}
