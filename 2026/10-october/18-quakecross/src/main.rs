//! Command line: quakecross PICKS.txt   (or - for standard input)

use std::fs::File;
use std::io::{self, Read};
use std::process::ExitCode;

const USAGE: &str = "Usage: quakecross PICKS.txt   (or - for standard input)

Locates an earthquake from P and S arrival times at three or more stations, gives a 90% error
ellipse, and names any pick that doesn't fit.
Exit codes: 0 located, 1 located but some picks don't fit, 2 bad input.
";

fn read_limited(r: impl Read) -> Result<String, String> {
    let mut buf = Vec::new();
    r.take(quakecross::parse::MAX_BYTES as u64 + 1)
        .read_to_end(&mut buf)
        .map_err(|_| "the input could not be read".to_string())?;
    if buf.len() > quakecross::parse::MAX_BYTES {
        return Err("the pick file is larger than 64 KB".into());
    }
    String::from_utf8(buf).map_err(|_| "the pick file is not valid UTF-8 text".into())
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args.iter().any(|a| a == "-h" || a == "--help") {
        print!("{USAGE}");
        return ExitCode::SUCCESS;
    }
    if args.len() != 1 || (args[0].starts_with('-') && args[0] != "-") {
        eprint!("{USAGE}");
        return ExitCode::from(2);
    }
    let path = &args[0];
    let (text, name) = if path == "-" {
        (read_limited(io::stdin().lock()), "standard input".to_string())
    } else {
        // Only regular files (not devices or directories), read with a size limit.
        let opened = std::fs::symlink_metadata(path)
            .ok()
            .filter(|m| m.file_type().is_file())
            .and_then(|_| File::open(path).ok());
        let name: String = std::path::Path::new(path)
            .file_name()
            .map(|n| {
                n.to_string_lossy()
                    .chars()
                    .map(|c| {
                        if c.is_ascii_alphanumeric() || "._-".contains(c) {
                            c
                        } else {
                            '?'
                        }
                    })
                    .take(60)
                    .collect()
            })
            .unwrap_or_default();
        match opened {
            Some(f) => (read_limited(f), name),
            None => (Err("no such file (or not a regular file)".to_string()), name),
        }
    };
    let result = text.and_then(|t| quakecross::run(&t, &name));
    match result {
        Ok((report, flagged)) => {
            print!("{report}");
            if flagged {
                ExitCode::from(1)
            } else {
                ExitCode::SUCCESS
            }
        }
        Err(e) => {
            eprintln!("quakecross: {e}");
            ExitCode::from(2)
        }
    }
}
