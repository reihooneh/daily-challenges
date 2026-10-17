//! Quakecross: locates an earthquake from P and S arrival times, with an error ellipse, and
//! names the station pick that doesn't fit.

pub mod locate;
pub mod parse;
pub mod report;

/// Reads the pick file text and returns the report and whether any pick was flagged.
pub fn run(text: &str, name: &str) -> Result<(String, bool), String> {
    let picks = parse::parse(text)?;
    let problem = locate::Problem::new(&picks)?;
    let first = problem.solve(&(0..problem.obs.len()).collect::<Vec<_>>());
    let (flagged, clean) = locate::find_outliers(&problem);
    let report = report::render(&picks, &problem, &first, &flagged, &clean, name);
    Ok((report, !flagged.is_empty()))
}
