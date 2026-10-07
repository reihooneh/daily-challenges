//! Tests that check the simulator against physics and the advice against
//! what a control engineer would say.

use std::process::Command;

use wobble::advice::advise;
use wobble::metrics::{cost, measure};
use wobble::pid::{Gains, Pid, MAX_GAIN};
use wobble::plant::{Kind, Plant};
use wobble::plot::render;
use wobble::sim::{simulate, Run, Setup, DT};
use wobble::tune::{tune, MAX_EVALUATIONS};

fn setup(plant: Kind, kp: f64, ki: f64, kd: f64) -> Setup {
    Setup {
        plant,
        gains: Gains { kp, ki, kd },
        setpoint: 1.0,
        duration: plant.default_duration(),
        limit: 10.0,
    }
}

fn close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "expected {expected}, got {actual}"
    );
}

// ---- the plants obey their equations ----------------------------------------

#[test]
fn motor_follows_the_exponential_from_the_textbook() {
    // A constant push of 1 should give 1 - e^(-t/0.3).
    let mut motor = Plant::new(Kind::Motor);
    for step in 1..=1000 {
        motor.step(1.0, DT);
        let t = step as f64 * DT;
        close(motor.output, 1.0 - (-t / 0.3_f64).exp(), 1e-9);
    }
}

#[test]
fn arm_reaches_its_terminal_velocity() {
    // With a constant push u, friction balances it at velocity u / 0.8,
    // so over a long time the angle grows by that much each second.
    let mut arm = Plant::new(Kind::Arm);
    for _ in 0..20_000 {
        arm.step(2.0, DT);
    }
    let before = arm.output;
    for _ in 0..1000 {
        arm.step(2.0, DT);
    }
    close(arm.output - before, 2.0 / 0.8, 1e-3);
}

#[test]
fn heater_does_nothing_for_half_a_second_then_responds() {
    let mut heater = Plant::new(Kind::Heater);
    for _ in 0..499 {
        heater.step(1.0, DT);
    }
    assert_eq!(heater.output, 0.0, "the delay has not passed yet");
    for _ in 0..40_000 {
        heater.step(1.0, DT);
    }
    close(heater.output, 2.0, 1e-3); // gain of 2
}

// ---- the controller ----------------------------------------------------------

#[test]
fn proportional_only_leaves_the_error_theory_predicts() {
    // For a first-order plant with gain 1, P control settles at Kp / (1 + Kp).
    for kp in [0.5, 1.0, 2.0, 4.0, 9.0] {
        let run = simulate(&setup(Kind::Motor, kp, 0.0, 0.0));
        close(*run.output.last().unwrap(), kp / (1.0 + kp), 1e-3);
        close(
            measure(&run).steady_state_error_percent,
            100.0 / (1.0 + kp),
            0.1,
        );
    }
}

#[test]
fn integral_action_removes_the_steady_error() {
    let metrics = measure(&simulate(&setup(Kind::Motor, 2.0, 8.0, 0.0)));
    assert!(metrics.steady_state_error_percent < 0.5, "{metrics:?}");
    assert!(metrics.settling_time.is_some());
}

#[test]
fn derivative_action_reduces_overshoot() {
    let without = measure(&simulate(&setup(Kind::Arm, 30.0, 0.0, 0.0)));
    let with = measure(&simulate(&setup(Kind::Arm, 30.0, 0.0, 4.0)));
    assert!(without.overshoot_percent > 40.0, "{without:?}");
    assert!(
        with.overshoot_percent < without.overshoot_percent / 4.0,
        "{with:?}"
    );
    assert!(with.crossings < without.crossings);
}

#[test]
fn the_actuator_limit_is_never_exceeded() {
    let mut pid = Pid::new(
        Gains {
            kp: 1000.0,
            ki: 1000.0,
            kd: 10.0,
        },
        3.0,
    );
    let mut measurement = 0.0;
    for step in 0..5000 {
        let (effort, _) = pid.update(1.0, measurement, DT);
        assert!(
            (-3.0..=3.0).contains(&effort),
            "effort {effort} at step {step}"
        );
        measurement = (step as f64 * 0.01).sin() * 5.0; // a wild sensor
    }
}

#[test]
fn no_derivative_kick_when_the_target_jumps() {
    // On the very first update the measurement has not moved, so the D term
    // must contribute nothing, however large Kd is.
    let mut pid = Pid::new(
        Gains {
            kp: 1.0,
            ki: 0.0,
            kd: 5000.0,
        },
        1.0e9,
    );
    let (effort, _) = pid.update(1.0, 0.0, DT);
    close(effort, 1.0, 1e-12);
}

#[test]
fn anti_windup_limits_the_overshoot_after_saturation() {
    // A weak actuator and a big integral gain: the classic windup recipe.
    let weak = Setup {
        limit: 1.2,
        duration: 20.0,
        ..setup(Kind::Motor, 1.0, 20.0, 0.0)
    };
    let metrics = measure(&simulate(&weak));
    assert!(metrics.saturated_percent > 1.0);
    assert!(
        metrics.overshoot_percent < 25.0,
        "windup was not contained: {metrics:?}"
    );
}

// ---- stability -----------------------------------------------------------------

#[test]
fn a_delayed_plant_goes_unstable_with_too_much_gain() {
    let metrics = measure(&simulate(&setup(Kind::Heater, 40.0, 0.0, 0.0)));
    assert!(metrics.growing || metrics.diverged, "{metrics:?}");
    let advice = advise(
        &metrics,
        &Gains {
            kp: 40.0,
            ki: 0.0,
            kd: 0.0,
        },
    )
    .join(" ");
    assert!(
        advice.contains("UNSTABLE")
            && advice.contains("Halve Kp (try 20.000)")
            && advice.contains("Add some Kd"),
        "{advice}"
    );
}

#[test]
fn a_gentle_heater_loop_is_stable() {
    let metrics = measure(&simulate(&setup(Kind::Heater, 0.8, 0.25, 0.0)));
    assert!(!metrics.growing && !metrics.diverged, "{metrics:?}");
}

#[test]
fn every_legal_input_finishes_with_finite_numbers() {
    for plant in Kind::ALL {
        for gains in [
            [0.0, 0.0, 0.0],
            [MAX_GAIN, 0.0, 0.0],
            [0.0, MAX_GAIN, 0.0],
            [0.0, 0.0, MAX_GAIN],
            [MAX_GAIN; 3],
        ] {
            for limit in [0.01, 10.0, 1.0e6] {
                let s = Setup {
                    limit,
                    duration: 2.0,
                    ..setup(plant, gains[0], gains[1], gains[2])
                };
                let run = simulate(&s);
                assert!(
                    run.output.iter().all(|y| y.is_finite()),
                    "{plant:?} {gains:?} {limit}"
                );
                let metrics = measure(&run);
                assert!(
                    metrics.overshoot_percent.is_finite()
                        && metrics.steady_state_error_percent.is_finite()
                );
                assert!(!advise(&metrics, &s.gains).is_empty());
                assert!(!cost(&run).is_nan());
                render(&run); // must not panic
            }
        }
    }
}

// ---- metrics on hand-made signals -------------------------------------------

fn synthetic(samples: impl Iterator<Item = f64>) -> Run {
    Run {
        setpoint: 1.0,
        output: samples.collect(),
        saturated_steps: 0,
        diverged: false,
    }
}

#[test]
fn metrics_of_a_perfect_ramp() {
    // Rises in a straight line to 1.0 over one second, then holds.
    let run = synthetic((0..3000).map(|i| (i as f64 / 1000.0).min(1.0)));
    let m = measure(&run);
    close(m.rise_time.unwrap(), 0.8, 0.002); // 10% at 0.1 s, 90% at 0.9 s
    close(m.overshoot_percent, 0.0, 1e-9);
    close(m.settling_time.unwrap(), 0.98, 0.002); // enters the 2% band at 0.98 s
    close(m.steady_state_error_percent, 0.0, 1e-9);
    assert_eq!(m.crossings, 0);
}

#[test]
fn metrics_of_a_decaying_and_a_growing_wobble() {
    let wave = |growth: f64| {
        synthetic((0..6000).map(move |i| {
            let t = i as f64 * DT;
            1.0 + 0.5 * (growth * t).exp() * (6.0 * t).sin() - if i == 0 { 1.0 } else { 0.0 }
        }))
    };
    let dying = measure(&wave(-0.8));
    assert!(!dying.growing && dying.crossings >= 4, "{dying:?}");
    close(dying.overshoot_percent, 43.0, 3.0);
    let growing = measure(&wave(0.3));
    assert!(growing.growing, "{growing:?}");
}

#[test]
fn tiny_ripples_are_not_counted_as_wobbles() {
    let run = synthetic((0..4000).map(|i| {
        if i < 10 {
            0.0
        } else {
            1.0 + 0.001 * (i as f64 * 0.05).sin()
        }
    }));
    assert_eq!(measure(&run).crossings, 0);
}

#[test]
fn empty_and_degenerate_runs_do_not_panic() {
    let empty = Run {
        setpoint: 1.0,
        output: vec![],
        saturated_steps: 0,
        diverged: true,
    };
    assert!(measure(&empty).diverged);
    assert!(cost(&empty).is_infinite());
    assert!(render(&empty).contains("nothing to plot"));
    let zero_target = Run {
        setpoint: 0.0,
        output: vec![0.0; 10],
        saturated_steps: 0,
        diverged: false,
    };
    assert!(measure(&zero_target).rise_time.is_none());
}

// ---- advice --------------------------------------------------------------------

#[test]
fn advice_matches_the_situation() {
    let say = |s: &Setup| advise(&measure(&simulate(s)), &s.gains).join(" ");
    assert!(say(&setup(Kind::Motor, 2.0, 0.0, 0.0)).contains("add Ki"));
    assert!(say(&setup(Kind::Arm, 30.0, 0.0, 0.0)).contains("Add Kd to brake"));
    assert!(say(&setup(Kind::Arm, 30.0, 0.0, 0.0)).contains("swings back through the target"));
    assert!(say(&setup(Kind::Motor, 2.0, 8.0, 0.0)).contains("Looks good"));
    let weak = Setup {
        limit: 0.5,
        ..setup(Kind::Arm, 20.0, 0.0, 3.0)
    };
    assert!(
        say(&weak).contains("limit is the hardware"),
        "{}",
        say(&weak)
    );
}

// ---- tuning ----------------------------------------------------------------------

#[test]
fn tuning_never_makes_things_worse_and_always_stops() {
    for plant in Kind::ALL {
        for start in [
            [1.0, 0.0, 0.0],
            [30.0, 0.0, 0.0],
            [0.0, 0.0, 0.0],
            [5.0, 5.0, 5.0],
        ] {
            let tuned = tune(&setup(plant, start[0], start[1], start[2]));
            assert!(tuned.cost_after <= tuned.cost_before, "{plant:?} {start:?}");
            assert!(tuned.evaluations <= MAX_EVALUATIONS);
            assert!(tuned.gains.is_valid());
        }
    }
}

#[test]
fn tuning_fixes_the_wobbly_arm() {
    let wobbly = setup(Kind::Arm, 30.0, 0.0, 0.0);
    let tuned = tune(&wobbly);
    let after = measure(&simulate(&Setup {
        gains: tuned.gains,
        ..wobbly
    }));
    assert!(after.overshoot_percent < 5.0, "{after:?}");
    assert!(after.settling_time.unwrap() < 1.0, "{after:?}");
    assert!(
        tuned.gains.kd > 0.0,
        "the tuner should have discovered derivative action"
    );
}

// ---- the command line ------------------------------------------------------------

fn cli(args: &[&str]) -> (i32, String, String) {
    let output = Command::new(env!("CARGO_BIN_EXE_wobble"))
        .args(args)
        .output()
        .expect("binary runs");
    (
        output.status.code().unwrap_or(-1),
        String::from_utf8_lossy(&output.stdout).into(),
        String::from_utf8_lossy(&output.stderr).into(),
    )
}

#[test]
fn exit_codes_tell_stable_from_unstable() {
    let (code, out, _) = cli(&["run", "--plant", "arm", "--kp", "30"]);
    assert_eq!(code, 0);
    assert!(out.contains("Overshoot:") && out.contains('*') && out.contains("5.0 s"));
    let (code, out, _) = cli(&["run", "--plant", "heater", "--kp", "40", "--no-plot"]);
    assert_eq!(code, 1);
    assert!(out.contains("UNSTABLE") && !out.contains('*'));
    assert_eq!(cli(&["plants"]).0, 0);
    assert_eq!(cli(&["--help"]).0, 0);
}

#[test]
fn bad_arguments_get_one_clean_line_and_exit_code_two() {
    let cases: &[&[&str]] = &[
        &[],
        &["explode"],
        &["run"],
        &["run", "--plant"],
        &["run", "--plant", "toaster"],
        &["run", "--plant", "arm", "--kp"],
        &["run", "--plant", "arm", "--kp", "-1"],
        &["run", "--plant", "arm", "--kp", "1e308"],
        &["run", "--plant", "arm", "--kp", "inf"],
        &["run", "--plant", "arm", "--kp", "NaN"],
        &["run", "--plant", "arm", "--kp", "1.2.3"],
        &["run", "--plant", "arm", "--kp", "."],
        &["run", "--plant", "arm", "--kp", "99999999"],
        &["run", "--plant", "arm", "--kp", "１２"],
        &["run", "--plant", "arm", "--time", "0"],
        &["run", "--plant", "arm", "--time", "100000"],
        &["run", "--plant", "arm", "--limit", "0"],
        &["run", "--plant", "arm", "--setpoint", "0"],
        &["run", "--plant", "arm", "--bogus", "1"],
        &["run", "--plant", "arm", "--kp", "$(reboot)"],
        &["run", "--plant", "<script>alert(1)</script>"],
        &["run", "--plant", "\u{1b}[2Jowned"],
        &["plants", "extra"],
    ];
    for args in cases {
        let (code, out, err) = cli(args);
        assert_eq!(code, 2, "{args:?}");
        assert!(out.is_empty(), "{args:?}");
        assert!(err.starts_with("wobble: "), "{args:?}: {err}");
        for leaked in ["reboot", "script", "owned", "\u{1b}", "toaster"] {
            assert!(!err.contains(leaked), "{args:?} echoed input: {err}");
        }
    }
}

#[test]
fn the_longest_allowed_run_and_a_full_tune_finish_quickly() {
    let started = std::time::Instant::now();
    let (code, _, _) = cli(&["tune", "--plant", "heater", "--time", "120", "--no-plot"]);
    assert!(code == 0 || code == 1);
    assert!(
        started.elapsed().as_secs() < 60,
        "took {:?}",
        started.elapsed()
    );
}
