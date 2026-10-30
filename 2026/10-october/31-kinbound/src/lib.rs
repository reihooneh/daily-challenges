//! Kinbound: earliest and latest possible years for everyone in a family tree, and a clear
//! account of which records can't all be true.

pub mod graph;
pub mod parse;
pub mod report;
pub mod solve;

pub use parse::InputError;

/// The outcome of a run: the text to print and whether every record fits.
pub struct Outcome {
    pub text: String,
    pub consistent: bool,
}

/// Parses a family file and builds the report, optionally with the reasons for one person's dates.
///
/// # Errors
/// An [`InputError`] if the file or the person id is not acceptable.
pub fn run(text: &str, why: Option<&str>) -> Result<Outcome, InputError> {
    let tree = parse::parse(text)?;
    let who = match why {
        Some(id) => Some(tree.find(id).ok_or(InputError {
            line: 0,
            msg: "--why names a person who isn't in the file".into(),
        })?),
        None => None,
    };
    let a = solve::analyse(&tree);
    let mut out = report::render(&tree, &a);
    if let Some(p) = who {
        out.push_str(&report::why(&tree, &a, p));
    }
    Ok(Outcome {
        text: out,
        consistent: a.conflicts.is_empty(),
    })
}
