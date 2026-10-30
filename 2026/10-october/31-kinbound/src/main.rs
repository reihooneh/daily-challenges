use kinbound::parse::MAX_BYTES;
use std::fs::File;
use std::io::{self, Read, Write};
use std::process::ExitCode;

const USAGE: &str = "Usage: kinbound FAMILY.txt [--why PERSON-ID]     (- reads standard input)

Prints the earliest and latest possible birth and death years for everyone, or, when records
contradict each other, each conflict and the fewest records that would have to be wrong.

Exit codes: 0 every record fits, 1 conflicts found, 2 bad usage or input.";

/// Reads at most `MAX_BYTES` + 1 bytes, so an oversized or endless input is refused, not loaded.
fn read_bounded(r: impl Read) -> io::Result<Vec<u8>> {
    let mut buf = Vec::new();
    r.take(MAX_BYTES as u64 + 1).read_to_end(&mut buf)?;
    Ok(buf)
}

fn fail(msg: &str) -> ExitCode {
    let _ = writeln!(io::stderr(), "kinbound: {msg}");
    ExitCode::from(2)
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (path, why) = match args.as_slice() {
        [p] if p != "-h" && p != "--help" => (p.as_str(), None),
        [p, flag, id] if flag == "--why" => (p.as_str(), Some(id.as_str())),
        _ => {
            let _ = writeln!(io::stderr(), "{USAGE}");
            return ExitCode::from(2);
        }
    };
    let bytes = if path == "-" {
        read_bounded(io::stdin().lock())
    } else {
        // Only regular files; the path is never echoed back.
        match std::fs::metadata(path) {
            Ok(m) if m.is_file() => File::open(path).and_then(read_bounded),
            _ => return fail("the family file could not be read (it must be a readable file)"),
        }
    };
    let Ok(bytes) = bytes else {
        return fail("the family file could not be read");
    };
    if bytes.len() > MAX_BYTES {
        return fail("the file is larger than 64 KB");
    }
    let Ok(text) = String::from_utf8(bytes) else {
        return fail("the file must be UTF-8 text");
    };
    match kinbound::run(&text, why) {
        Ok(out) => {
            if io::stdout().write_all(out.text.as_bytes()).is_err() {
                return ExitCode::from(2);
            }
            if out.consistent {
                ExitCode::SUCCESS
            } else {
                ExitCode::from(1)
            }
        }
        Err(e) => fail(&e.to_string()),
    }
}
