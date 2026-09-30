//! Keyglint: find leaked secrets in source code before they reach Git.
//!
//! The library is pure: give it text, get back findings. The CLI in
//! `main.rs` handles files, folders and output formats.
//!
//! Detection uses two ideas:
//! 1. **Known shapes.** Many providers give their keys a recognisable prefix
//!    (`AKIA` for AWS, `ghp_` for GitHub, `sk_live_` for Stripe). We match
//!    those exactly, with hand-written matchers (no regex crate needed).
//! 2. **Randomness.** Real secrets look random. We measure that with
//!    Shannon entropy, which catches secrets that have no known prefix.

use std::fmt;

/// How serious a finding is. Ordered so `High > Medium > Low`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum Severity {
    Low,
    Medium,
    High,
}

impl Severity {
    pub fn parse(s: &str) -> Option<Severity> {
        match s.to_ascii_lowercase().as_str() {
            "low" => Some(Severity::Low),
            "medium" => Some(Severity::Medium),
            "high" => Some(Severity::High),
            _ => None,
        }
    }
}

impl fmt::Display for Severity {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let s = match self {
            Severity::Low => "LOW",
            Severity::Medium => "MEDIUM",
            Severity::High => "HIGH",
        };
        f.pad(s)
    }
}

/// One suspected secret.
#[derive(Debug, Clone, PartialEq)]
pub struct Finding {
    pub path: String,
    /// 1-based line number.
    pub line: usize,
    /// 1-based column (in characters) where the secret starts.
    pub column: usize,
    pub rule: &'static str,
    pub severity: Severity,
    /// The raw matched text. Never print this directly; use [`mask`].
    pub secret: String,
}

/// Lines containing this marker are skipped, for known-safe test values.
pub const IGNORE_MARKER: &str = "keyglint:ignore";

/// Words in a variable name that suggest its value is a secret.
const SECRET_NAMES: &[&str] = &[
    "password",
    "passwd",
    "pwd",
    "secret",
    "token",
    "api_key",
    "apikey",
    "access_key",
    "private_key",
    "auth",
    "credential",
];

/// Values that are obviously placeholders, not real secrets.
const PLACEHOLDERS: &[&str] = &[
    "example",
    "changeme",
    "change_me",
    "xxxx",
    "your_",
    "your-",
    "<",
    "${",
    "{{",
    "placeholder",
    "dummy",
    "redacted",
    "****",
];

/// Shannon entropy in bits per character.
///
/// "aaaa" scores 0 (no surprise at all); a random base64 string scores
/// close to 6. English words usually land between 2.5 and 3.5.
pub fn shannon_entropy(s: &str) -> f64 {
    let chars: Vec<char> = s.chars().collect();
    if chars.is_empty() {
        return 0.0;
    }
    let mut counts = std::collections::HashMap::new();
    for c in &chars {
        *counts.entry(*c).or_insert(0usize) += 1;
    }
    let len = chars.len() as f64;
    counts
        .values()
        .map(|&n| {
            let p = n as f64 / len;
            -p * p.log2()
        })
        .sum()
}

/// Hide most of a secret so reports are safe to share.
/// `AKIAIOSFODNN7EXAMPLE` becomes `AKIA************`.
pub fn mask(secret: &str) -> String {
    let chars: Vec<char> = secret.chars().collect();
    if chars.len() <= 4 {
        return "*".repeat(chars.len());
    }
    let shown: String = chars[..4].iter().collect();
    format!("{}{}", shown, "*".repeat((chars.len() - 4).min(12)))
}

fn is_alnum(c: char) -> bool {
    c.is_ascii_alphanumeric()
}

/// Find every occurrence of `prefix` followed by at least `min_body` characters
/// accepted by `body`. The match must not be glued to a preceding word
/// character, so `XAKIA...` does not count as an AWS key.
/// Returns (character column, full token).
fn find_prefixed(
    line: &str,
    prefix: &str,
    min_body: usize,
    max_body: usize,
    body: fn(char) -> bool,
) -> Vec<(usize, String)> {
    let chars: Vec<char> = line.chars().collect();
    let pre: Vec<char> = prefix.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i + pre.len() <= chars.len() {
        let boundary = i == 0 || !(is_alnum(chars[i - 1]) || chars[i - 1] == '_');
        if boundary && chars[i..i + pre.len()] == pre[..] {
            let mut j = i + pre.len();
            while j < chars.len() && j - (i + pre.len()) < max_body && body(chars[j]) {
                j += 1;
            }
            let body_len = j - (i + pre.len());
            let glued_after = j < chars.len() && body(chars[j]);
            if body_len >= min_body && !glued_after {
                out.push((i, chars[i..j].iter().collect()));
                i = j;
                continue;
            }
        }
        i += 1;
    }
    out
}

/// A quoted string literal found on a line.
struct Quoted {
    column: usize,
    value: String,
    /// Everything before the opening quote, e.g. `DB_PASSWORD = `.
    before: String,
}

fn quoted_strings(line: &str) -> Vec<Quoted> {
    let chars: Vec<char> = line.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i < chars.len() {
        let q = chars[i];
        if q == '"' || q == '\'' || q == '`' {
            if let Some(end) = (i + 1..chars.len()).find(|&k| chars[k] == q && chars[k - 1] != '\\')
            {
                out.push(Quoted {
                    column: i + 1,
                    value: chars[i + 1..end].iter().collect(),
                    before: chars[..i].iter().collect(),
                });
                i = end + 1;
                continue;
            }
        }
        i += 1;
    }
    out
}

/// The variable name a value is being assigned to, lower-cased:
/// `const API_KEY = "..."` gives `api_key`; `password: "..."` gives `password`.
fn assigned_name(before: &str) -> Option<String> {
    let mut t = before.trim_end();
    for op in [":=", "=>", "=", ":"] {
        if let Some(rest) = t.strip_suffix(op) {
            t = rest.trim_end();
            // Allow quoted keys, as in JSON: "password": "..."
            t = t.trim_end_matches(['"', '\'']);
            let name: String = t
                .chars()
                .rev()
                .take_while(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.'))
                .collect::<Vec<_>>()
                .into_iter()
                .rev()
                .collect();
            return if name.is_empty() {
                None
            } else {
                Some(name.to_ascii_lowercase())
            };
        }
    }
    None
}

fn is_placeholder(value: &str) -> bool {
    let v = value.to_ascii_lowercase();
    PLACEHOLDERS.iter().any(|p| v.contains(p))
        || value
            .chars()
            .all(|c| c == value.chars().next().unwrap_or(' '))
}

fn is_base64ish(c: char) -> bool {
    c.is_ascii_alphanumeric() || matches!(c, '+' | '/' | '=' | '_' | '-')
}

/// Scan one file's text. `path` is only used to label findings.
pub fn scan_text(path: &str, text: &str) -> Vec<Finding> {
    let mut findings = Vec::new();
    for (idx, line) in text.lines().enumerate() {
        if line.contains(IGNORE_MARKER) {
            continue;
        }
        let mut hits: Vec<Finding> = Vec::new();
        // `col` is 0-based here; findings store 1-based columns for humans.
        let make = |col: usize, rule: &'static str, severity: Severity, secret: String| Finding {
            path: path.to_string(),
            line: idx + 1,
            column: col + 1,
            rule,
            severity,
            secret,
        };

        // 1. Known shapes.
        if line.contains("-----BEGIN ") && line.contains("PRIVATE KEY-----") {
            let col = line.find("-----BEGIN").unwrap_or(0);
            hits.push(make(
                line[..col].chars().count(),
                "private-key",
                Severity::High,
                line.trim().to_string(),
            ));
        }
        for prefix in ["AKIA", "ASIA"] {
            let upper_digit = |c: char| c.is_ascii_uppercase() || c.is_ascii_digit();
            for (col, tok) in find_prefixed(line, prefix, 16, 16, upper_digit) {
                hits.push(make(col, "aws-access-key", Severity::High, tok));
            }
        }
        for prefix in ["ghp_", "gho_", "ghu_", "ghs_", "ghr_"] {
            for (col, tok) in find_prefixed(line, prefix, 36, 255, is_alnum) {
                hits.push(make(col, "github-token", Severity::High, tok));
            }
        }
        for (col, tok) in find_prefixed(line, "github_pat_", 22, 255, |c| is_alnum(c) || c == '_') {
            hits.push(make(col, "github-token", Severity::High, tok));
        }
        for kind in ['b', 'a', 'p', 'r', 's'] {
            let prefix = format!("xox{kind}-");
            for (col, tok) in find_prefixed(line, &prefix, 10, 255, |c| is_alnum(c) || c == '-') {
                hits.push(make(col, "slack-token", Severity::High, tok));
            }
        }
        for (col, tok) in find_prefixed(line, "sk_live_", 24, 255, is_alnum) {
            hits.push(make(col, "stripe-live-key", Severity::High, tok));
        }

        // 2. Quoted values: named secrets and high-entropy blobs.
        for q in quoted_strings(line) {
            let start = q.column - 1;
            // Skip values already reported by a known-shape rule above.
            let end = start + q.value.chars().count();
            let already = hits.iter().any(|h| h.column > start && h.column <= end + 1);
            if already || q.value.chars().count() < 8 || is_placeholder(&q.value) {
                continue;
            }
            let entropy = shannon_entropy(&q.value);
            let named = assigned_name(&q.before)
                .map(|n| SECRET_NAMES.iter().any(|s| n.contains(s)))
                .unwrap_or(false);
            if named && entropy >= 2.5 {
                hits.push(make(
                    start + 1,
                    "named-secret",
                    Severity::Medium,
                    q.value.clone(),
                ));
            } else if q.value.chars().count() >= 20 && q.value.chars().all(is_base64ish) {
                let hex = q.value.chars().all(|c| c.is_ascii_hexdigit());
                let threshold = if hex { 3.0 } else { 4.5 };
                if entropy >= threshold {
                    hits.push(make(
                        start + 1,
                        "high-entropy-string",
                        Severity::Low,
                        q.value.clone(),
                    ));
                }
            }
        }

        hits.sort_by_key(|h| h.column);
        findings.extend(hits);
    }
    findings
}
