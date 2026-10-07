# How Wobble works

A friendly walkthrough so you can explain every part of it.

## 1. The big picture

A control loop is a circle:

```
            target ──▶ ( error = target − measurement )
                                  │
                                  ▼
                        PID controller  (pid.rs)
                                  │  effort (clamped to what the actuator can do)
                                  ▼
                            the plant    (plant.rs)   motor / arm / heater
                                  │  new measurement
                                  └──────────── back to the top, 1,000 times a second
```

`sim.rs` runs that circle and records the measurement at every step. Then:

```
 recorded response ──▶ metrics.rs ──▶ advice.rs ──▶ words
                   └─▶ plot.rs    ──▶ the graph
                   └─▶ tune.rs    ──▶ better gains (by running sim.rs many times)
```

## 2. File tour

| File | Job |
|---|---|
| `src/plant.rs` | The three things that can be controlled, each a small differential equation |
| `src/pid.rs` | The controller, with anti-windup and derivative-on-measurement |
| `src/sim.rs` | Steps controller and plant through time; stops a runaway |
| `src/metrics.rs` | Rise time, overshoot, settling time, steady error, swings, and a single score |
| `src/advice.rs` | Rules that turn metrics into sentences |
| `src/tune.rs` | The automatic tuner |
| `src/plot.rs` | The text graph |
| `src/main.rs` | Command line: argument validation, report, exit code |
| `tests/behaviour.rs` | 22 tests |

## 3. Key ideas

### The three terms
- **P (proportional):** effort = Kp × error. Far away, push hard; close, push gently. Too much and it overshoots.
- **I (integral):** effort += Ki × (error added up over time). A small error that won't go away keeps adding up until the push is big enough to remove it.
- **D (derivative):** effort −= Kd × (how fast the measurement is changing). A brake that gets stronger the faster you approach.

### Why P alone stops short
For the motor, holding a speed needs a constant push. But P only pushes when there is an error. So it must settle with *some* error left: exactly at Kp / (1 + Kp) of the target. The test `proportional_only_leaves_the_error_theory_predicts` checks five values of Kp against that formula. The arm doesn't have this problem, because holding a position needs no push.

### Three real-world problems, and the fixes in `pid.rs`
1. **Actuator limits.** A motor has a maximum voltage. The effort is clamped, and the simulator counts how long it stays clamped.
2. **Integral windup.** While the actuator is at its limit, the error stays large and the integral would grow enormous, causing a huge overshoot later. The fix: don't let the integral grow while saturated, unless growing would bring it back.
3. **Derivative kick.** When the target jumps, the error jumps, and its rate of change is a spike. The fix: take the derivative of the *measurement*, which can't jump.

### Simulating a differential equation
A plant is described by how fast it changes. To simulate, take small time steps (1 ms).

- The motor and heater are simple enough to have an exact answer for one step under a constant push, so that is used: no approximation error at all.
- The arm uses **semi-implicit Euler**: update the velocity first, then use the *new* velocity to update the position. The ordinary Euler method (using the old velocity) slowly adds energy to anything that oscillates, which would make a stable loop look unstable.

### Why the heater goes unstable
The heater reacts half a second late. The controller sees it's too cold and pushes; by the time the heat arrives the controller has pushed too much, so it overshoots, then over-corrects the other way. With enough gain each swing is bigger than the last. Delay is the classic cause of instability, and it's why you can't just turn the gains up.

### Measuring a response (`metrics.rs`)
- **Rise time:** from 10% to 90% of the target.
- **Overshoot:** the peak, as a percentage past the target.
- **Settling time:** the last moment it was more than 2% away. Found by walking *backwards* from the end.
- **Swings:** how many times it passes back through the target after arriving.
- **Growing:** compare an early swing with the last one. Bigger means unstable.

### Tuning by twiddling (`tune.rs`)
Give every run a score (ITAE: error × time, added up, so lingering errors cost more; plus a penalty for overshoot). Then for each gain in turn: try it a bit higher; if the score improves, keep it and be bolder. If not, try lower. If neither helps, put it back and make the next nudge smaller. Stop when the nudges are tiny or 400 runs are used. This is **coordinate ascent**: no calculus, no model, just organised trial and error.

## 4. Glossary

| Term | Plain version |
|---|---|
| Plant | The thing being controlled |
| Setpoint | The target value |
| Step response | What happens when the target suddenly jumps from 0 to 1 |
| Saturation | The actuator is at its limit and can't push harder |
| Dead time | The delay before a plant reacts at all |
| ITAE | A score that punishes errors more the later they occur |
| Time step (dt) | How far the simulation advances each loop: 1 ms here |

### Rust features you met here
- **Modules** (`pub mod pid;`) and a library + binary in one crate, so tests can use the library directly.
- **Enums with methods** (`Kind::parse`, `Kind::describe`) and exhaustive `match`: add a plant and the compiler lists every place to update.
- **`Option<f64>`** for "it never got there", instead of a magic number like -1.
- **Struct update syntax:** `Setup { gains: tuned.gains, ..setup }`.
- **Iterators:** `find`, `rev`, `fold`, `map`, `sum`, and `all` for validation.
- **`f64::clamp`, `is_finite`, `signum`**: careful floating-point handling.
- **Labeled breaks** (`'search: while ... break 'search`).
- **`Result<T, String>` and `?`** for errors that become one clean line.
- **`[lints.rust] unsafe_code = "forbid"`** in `Cargo.toml`.
- **Integration tests** in `tests/`, including running the real binary with `env!("CARGO_BIN_EXE_wobble")`.

## 5. Interview questions you might get

**Q: What are integral windup and derivative kick, and how did you handle them?**
A: Windup: when the actuator is saturated the error persists, the integral keeps growing, and it takes a long overshoot to unwind. I only let the integral change while saturated if the change moves the output back from the limit. Derivative kick: a step in the target makes the error's derivative a spike. I differentiate the measurement instead, which is identical for a constant target but has no spike. Both have tests.

**Q: How do you know the simulation is right?**
A: I compare it with cases that have exact answers. An open-loop first-order system must follow 1 − e^(−t/τ), and it does to nine decimals. P control on that system must settle at Kp/(1+Kp). The arm under constant torque must reach the terminal velocity where friction balances it. If the simulator matched those by accident, it would be a remarkable accident.

**Q: Your tuner has no model of the system. Why does it work, and when wouldn't it?**
A: It's coordinate ascent on a score: change one gain at a time, keep improvements, shrink the step when stuck. It works here because the score changes smoothly with the gains and there are only three of them. It can stop at a local optimum, it needs hundreds of trials, and on real hardware each trial costs time and may be unsafe, which is why real tuning usually starts from a model or a method like Ziegler-Nichols.

## 6. Ideas to extend it yourself

1. **Sensor noise:** add random noise to the measurement and a low-pass filter on the D term, then watch why real robots use less Kd than simulations suggest.
2. **Disturbances:** push the arm halfway through the run and measure how quickly it recovers.
3. **Your own plant:** read mass, friction and delay from the command line so it matches a mechanism you have actually built.
