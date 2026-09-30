//! Keyglint command-line interface.
//!
//! Usage: keyglint [PATH ...] [--json] [--min-severity low|medium|high]
//! Exit codes: 0 = clean, 1 = secrets found, 2 = usage or I/O error.
//! The non-zero exit on findings makes it easy to use in CI or a pre-commit hook.

use keyglint::{mask, scan_text, Finding, Severity};
use std::fs;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::ExitCode;

const SKIP_DIRS: &[&str] = &[
    ".git",
    "target",
    "node_modules",
    ".venv",
    "venv",
    "dist",
    "build",
    "__pycache__",
];
const MAX_BYTES: u64 = 1_000_000;

struct Options {
    paths: Vec<PathBuf>,
    json: bool,
    min: Severity,
}

const HELP: &str = "keyglint: find leaked secrets before you push

USAGE:
    keyglint [PATH ...] [OPTIONS]

OPTIONS:
    --json                     Machine-readable output
    --min-severity <LEVEL>     Only report low | medium | high (default: low)
    -h, --help                 Show this help
    -V, --version              Show version

Add `keyglint:ignore` to a line to skip it.";

fn parse_args(args: Vec<String>) -> Result<Option<Options>, String> {
    let mut opts = Options {
        paths: Vec::new(),
        json: false,
        min: Severity::Low,
    };
    let mut it = args.into_iter();
    while let Some(a) = it.next() {
        match a.as_str() {
            "-h" | "--help" => {
                println!("{HELP}");
                return Ok(None);
            }
            "-V" | "--version" => {
                println!("keyglint {}", env!("CARGO_PKG_VERSION"));
                return Ok(None);
            }
            "--json" => opts.json = true,
            "--min-severity" => {
                let v = it
                    .next()
                    .ok_or("--min-severity needs a value: low, medium or high")?;
                opts.min = Severity::parse(&v)
                    .ok_or(format!("unknown severity '{v}': use low, medium or high"))?;
            }
            s if s.starts_with('-') => return Err(format!("unknown option '{s}' (try --help)")),
            p => opts.paths.push(PathBuf::from(p)),
        }
    }
    if opts.paths.is_empty() {
        opts.paths.push(PathBuf::from("."));
    }
    Ok(Some(opts))
}

/// Recursively collect scannable files, skipping noisy folders.
fn collect(path: &Path, out: &mut Vec<PathBuf>) -> std::io::Result<()> {
    let meta = fs::symlink_metadata(path)?;
    if meta.is_file() {
        out.push(path.to_path_buf());
    } else if meta.is_dir() {
        let mut entries: Vec<_> = fs::read_dir(path)?.filter_map(Result::ok).collect();
        entries.sort_by_key(|e| e.file_name());
        for e in entries {
            let name = e.file_name();
            if e.path().is_dir() && SKIP_DIRS.iter().any(|s| name == *s) {
                continue;
            }
            collect(&e.path(), out)?;
        }
    }
    Ok(())
}

/// Read a file as text, or None if it is too big or looks binary.
fn read_text(path: &Path) -> Option<String> {
    let meta = fs::metadata(path).ok()?;
    if meta.len() > MAX_BYTES {
        return None;
    }
    let mut bytes = Vec::new();
    fs::File::open(path).ok()?.read_to_end(&mut bytes).ok()?;
    if bytes.iter().take(8000).any(|&b| b == 0) {
        return None;
    }
    Some(String::from_utf8_lossy(&bytes).into_owned())
}

fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

fn print_json(findings: &[Finding], files: usize) {
    let items: Vec<String> = findings
        .iter()
        .map(|f| {
            format!(
                "{{\"path\":\"{}\",\"line\":{},\"column\":{},\"rule\":\"{}\",\"severity\":\"{}\",\"masked\":\"{}\"}}",
                json_escape(&f.path), f.line, f.column, f.rule, f.severity.to_string().to_lowercase(), json_escape(&mask(&f.secret))
            )
        })
        .collect();
    println!(
        "{{\"files_scanned\":{},\"findings\":[{}]}}",
        files,
        items.join(",")
    );
}

fn print_human(findings: &[Finding], files: usize) {
    for f in findings {
        println!(
            "{:<6}  {}:{}:{}  {:<20}  {}",
            f.severity,
            f.path,
            f.line,
            f.column,
            f.rule,
            mask(&f.secret)
        );
    }
    let count = |s| findings.iter().filter(|f| f.severity == s).count();
    if findings.is_empty() {
        println!(
            "✓ No secrets found in {files} file{}.",
            if files == 1 { "" } else { "s" }
        );
    } else {
        println!(
            "\n✗ {} finding{} ({} high, {} medium, {} low) in {} file{} scanned.",
            findings.len(),
            if findings.len() == 1 { "" } else { "s" },
            count(Severity::High),
            count(Severity::Medium),
            count(Severity::Low),
            files,
            if files == 1 { "" } else { "s" },
        );
    }
}

fn main() -> ExitCode {
    let opts = match parse_args(std::env::args().skip(1).collect()) {
        Ok(Some(o)) => o,
        Ok(None) => return ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("keyglint: {e}");
            return ExitCode::from(2);
        }
    };

    let mut files = Vec::new();
    for p in &opts.paths {
        if let Err(e) = collect(p, &mut files) {
            eprintln!("keyglint: cannot read {}: {e}", p.display());
            return ExitCode::from(2);
        }
    }

    let mut scanned = 0;
    let mut findings = Vec::new();
    for f in &files {
        if let Some(text) = read_text(f) {
            scanned += 1;
            findings.extend(
                scan_text(&f.display().to_string(), &text)
                    .into_iter()
                    .filter(|x| x.severity >= opts.min),
            );
        }
    }

    if opts.json {
        print_json(&findings, scanned);
    } else {
        print_human(&findings, scanned);
    }
    if findings.is_empty() {
        ExitCode::SUCCESS
    } else {
        ExitCode::from(1)
    }
}
