//! Draws a step response as text.

use crate::sim::{Run, DT};

const WIDTH: usize = 64;
const HEIGHT: usize = 14;

pub fn render(run: &Run) -> String {
    if run.output.is_empty() {
        return String::from("(nothing to plot)\n");
    }
    // One value per column: the average of the samples that fall in it.
    let n = run.output.len();
    let columns: Vec<f64> = (0..WIDTH)
        .map(|c| {
            let from = c * n / WIDTH;
            let to = (((c + 1) * n) / WIDTH).max(from + 1).min(n);
            run.output[from..to].iter().sum::<f64>() / (to - from) as f64
        })
        .collect();

    let low = columns
        .iter()
        .copied()
        .fold(0.0_f64, f64::min)
        .min(run.setpoint);
    let high = columns
        .iter()
        .copied()
        .fold(run.setpoint * 1.1, f64::max)
        .max(run.setpoint);
    let span = (high - low).max(f64::MIN_POSITIVE);
    let row_of = |value: f64| -> usize {
        let scaled = ((high - value) / span * (HEIGHT - 1) as f64).round();
        scaled.clamp(0.0, (HEIGHT - 1) as f64) as usize
    };

    let mut grid = vec![vec![' '; WIDTH]; HEIGHT];
    let target_row = row_of(run.setpoint);
    for cell in grid[target_row].iter_mut() {
        *cell = '-';
    }
    for (c, &value) in columns.iter().enumerate() {
        grid[row_of(value)][c] = '*';
    }

    let mut out = String::new();
    for (r, row) in grid.iter().enumerate() {
        let label = if r == target_row {
            format!("{:>8.2} ", run.setpoint)
        } else if r == 0 {
            format!("{:>8.2} ", high)
        } else if r == HEIGHT - 1 {
            format!("{:>8.2} ", low)
        } else {
            " ".repeat(9)
        };
        out.push_str(&label);
        out.push('|');
        out.push_str(row.iter().collect::<String>().trim_end());
        out.push('\n');
    }
    out.push_str(&format!("{}+{}\n", " ".repeat(9), "-".repeat(WIDTH)));
    out.push_str(&format!(
        "{}0 s{:>width$.1} s\n",
        " ".repeat(10),
        n as f64 * DT,
        width = WIDTH - 5
    ));
    out
}
