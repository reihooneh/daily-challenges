# Wobble 🤖

**Simulates a PID control loop and tells you, in plain words, why your robot wobbles.**

Every robot arm, drone and line-follower runs a PID controller, and every team that builds one spends hours changing three numbers and watching what happens. Wobble does that at your desk: it simulates a motor, an arm joint or a heater under PID control, draws the response, measures it the way an engineer would, and then says what is wrong and which number to change.

## What makes it different

PID simulators draw you a graph and leave the interpretation to you. Wobble is built around the interpretation:

- **Plain-language diagnosis.** "It overshoots the target by 56%. Add Kd to brake before it arrives, or reduce Kp."
- **It knows when tuning can't help.** If the motor is flat out, it tells you the limit is the hardware, not the gains.
- **It models what real robots suffer from:** actuator limits, integral windup, derivative kick and sensor delay, the things that make a textbook PID misbehave on real hardware.
- **An auto-tuner you can read.** `wobble tune` finds better gains with the same try-it-and-see method a person uses, in about 400 simulated attempts.
- **Checked against physics.** The tests compare the simulation with the exact solutions from control theory.

## Example

A robot arm with too much proportional gain and no damping:

```text
$ wobble run --plant arm --kp 30
robot arm joint, position control (inertia plus friction) to a target of 1

    1.55 |      **
         |        *
         |     *   *        *
         |                 * *
         |          *     *   *      ****      *****      ****       **
    1.00 |----*----------*-----*---**----******-----******----*******--***
         |           *          ***
         |            * *
         |   *         *
         |
         |  *
         |
         | *
    0.00 |*
         +----------------------------------------------------------------
          0 s                                                        5.0 s

  Rise time (10% to 90%):  0.22 s
  Overshoot:               56.1%
  Settles within 2%:       4.39 s
  Steady error:            0.5%
  Swings back past target: 10
  Actuator at its limit:   14% of the time

  - It overshoots the target by 56%. Add Kd to brake before it arrives, or reduce Kp.
  - It swings back through the target 10 times before calming down. More Kd (or less Kp) will damp the ringing.
```

Ask it to find better gains:

```text
$ wobble tune --plant arm --kp 30 --no-plot
Tried 399 combinations of gains.

Before:  Kp 30.000  Ki 0.000  Kd 0.000
  Rise time (10% to 90%):  0.22 s
  Overshoot:               56.1%
  Settles within 2%:       4.39 s
  Steady error:            0.5%
  Swings back past target: 10
  Actuator at its limit:   14% of the time

After:   Kp 130.514  Ki 0.000  Kd 12.875
  Rise time (10% to 90%):  0.26 s
  Overshoot:               0.6%
  Settles within 2%:       0.42 s
  Steady error:            0.0%
  Swings back past target: 0
  Actuator at its limit:   7% of the time

  - Looks good: quick, little overshoot, and it settles on the target.

These gains suit this simulated plant. On real hardware, start lower and work up.
```

## Usage

| Command | What it does |
|---|---|
| `wobble run --plant NAME --kp N --ki N --kd N` | Simulate, plot, measure and explain |
| `wobble tune --plant NAME` | Search for better gains, then show the result |
| `wobble plants` | List the three plants |

Options: `--time SECONDS`, `--limit N` (how hard the actuator can push), `--setpoint N`, `--no-plot`.

| Plant | What it models |
|---|---|
| `motor` | Wheel speed: reacts with a lag. P alone always stops short. |
| `arm` | Joint position: has inertia, so it overshoots and rings. |
| `heater` | Temperature: slow, with a half-second delay. Too much gain makes it unstable. |

Exit codes: `0` the loop is stable, `1` it is unstable, `2` the arguments could not be understood. That makes it usable in a script: fail the build if someone commits gains that oscillate.

## Tech

Rust 2021, standard library only. No dependencies, and `unsafe` code is forbidden in `Cargo.toml`.

## Build and run

```bash
cd 2026/10-october/08-wobble
cargo build --release
./target/release/wobble run --plant motor --kp 2
./target/release/wobble run --plant motor --kp 2 --ki 8
```

## Tests

```bash
cargo test
```

22 tests:

- **Physics:** the motor follows the textbook exponential to nine decimal places; the arm reaches the terminal velocity the equations predict; the heater stays at exactly zero until its delay has passed.
- **Control theory:** proportional-only control settles at Kp / (1 + Kp), as theory says; adding integral removes the error; adding derivative cuts overshoot; too much gain on a delayed plant goes unstable.
- **Real-world details:** the actuator limit is never exceeded, there is no derivative kick, and windup is contained.
- **Advice and tuning:** each situation produces the right advice; tuning never makes a loop worse and always stops.
- **Hostile input:** `inf`, `NaN`, `1e308`, negative numbers, look-alike Unicode digits, shell fragments and escape codes all get one clean error line.

`cargo clippy -- -D warnings` and `cargo fmt --check` are clean.

## Security

- **Numbers are validated as text first.** An argument must be plain digits with at most one decimal point and at most 12 characters. `inf`, `nan`, exponents and signs never reach the number parser, and every value is then range-checked.
- **Bounded work.** A run is at most 120 seconds of simulated time (120,000 steps), and tuning is capped at 400 runs. A loop that runs away is detected and stopped, so nothing can produce infinities or hang.
- **Errors never repeat the input,** so escape codes or markup in an argument cannot reach the terminal.
- **Nothing dangerous in reach.** No files, no network, no shell, no `unsafe`, no dependencies.

**Known limits, stated honestly:**

- **A simulation is not your robot.** The three plants are simple models with made-up constants. Gains that work here are a starting point; real hardware has friction, backlash, noise and flex that these models leave out. Start lower on a real machine and work up, especially on anything that can hurt someone.
- There is no sensor noise, which makes derivative action look better than it is in practice.
- The tuner optimises one score (settle fast, little overshoot). Your priorities may differ.
- No software can promise it is 100% secure; these are the protections in place.
