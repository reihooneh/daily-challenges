//! Tests for the Keyglint library and CLI.
//!
//! Fake tokens are built at runtime (e.g. `format!("ghp_{}", ...)`) so this
//! file never contains a real-looking secret that GitHub would block on push.

use keyglint::{mask, scan_text, shannon_entropy, Severity};
use std::fs;
use std::process::Command;

fn rules(text: &str) -> Vec<&'static str> {
    scan_text("t", text).into_iter().map(|f| f.rule).collect()
}

#[test]
fn entropy_is_zero_for_repeats_and_high_for_random() {
    assert_eq!(shannon_entropy(""), 0.0);
    assert_eq!(shannon_entropy("aaaaaaaa"), 0.0);
    assert!((shannon_entropy("ab") - 1.0).abs() < 1e-9);
    assert!(shannon_entropy("q8Vz2LmP0xR7tYw4Kc9N") > 4.0);
}

#[test]
fn mask_hides_all_but_four_characters() {
    assert_eq!(mask("AKIAIOSFODNN7EXAMPLE"), "AKIA************");
    assert_eq!(mask("abc"), "***");
    assert_eq!(mask("abcde"), "abcd*");
}

#[test]
fn finds_aws_access_key_with_position() {
    // AWS's own documented example key.
    let f = scan_text("config.py", "key = AKIAIOSFODNN7EXAMPLE");
    assert_eq!(f.len(), 1);
    assert_eq!(f[0].rule, "aws-access-key");
    assert_eq!(f[0].severity, Severity::High);
    assert_eq!((f[0].line, f[0].column), (1, 7));
}

#[test]
fn aws_key_must_not_be_glued_to_other_text() {
    assert!(rules("XAKIAIOSFODNN7EXAMPLE").is_empty());
    assert!(rules("AKIAIOSFODNN7EXAMPLEEXTRA").is_empty());
}

#[test]
fn finds_github_slack_and_stripe_tokens() {
    let gh = format!("token: {}{}", "ghp_", "a1B2".repeat(9));
    assert_eq!(rules(&gh), vec!["github-token"]);

    let pat = format!("{}{}", "github_pat_", "A1b2_".repeat(6));
    assert_eq!(rules(&pat), vec!["github-token"]);

    let slack = format!("{}{}", "xoxb-", "123456789012-abcdef");
    assert_eq!(rules(&slack), vec!["slack-token"]);

    let stripe = format!("{}{}", "sk_live_", "Zx9".repeat(9));
    assert_eq!(rules(&stripe), vec!["stripe-live-key"]);
}

#[test]
fn short_prefixes_are_not_tokens() {
    assert!(rules("ghp_short").is_empty());
    assert!(rules("sk_live_tooshort").is_empty());
}

#[test]
fn finds_private_key_headers() {
    let header = format!("-----BEGIN RSA {}-----", "PRIVATE KEY");
    assert_eq!(rules(&header), vec!["private-key"]);
    assert!(rules("-----BEGIN PUBLIC KEY-----").is_empty());
}

#[test]
fn finds_named_secrets_in_many_syntaxes() {
    assert_eq!(
        rules(r#"DB_PASSWORD = "Tr0ub4dor&3x""#),
        vec!["named-secret"]
    );
    assert_eq!(
        rules(r#"  "apiKey": "k3Yv9Qm2pLx8","#),
        vec!["named-secret"]
    );
    assert_eq!(rules(r#"secret := 'n0tS0S3cr3t!'"#), vec!["named-secret"]);
    let f = scan_text("t", r#"password: "hunter2hunter""#);
    assert_eq!(f[0].severity, Severity::Medium);
    // Column points at the first character inside the quotes.
    assert_eq!(f[0].column, 12);
}

#[test]
fn ignores_placeholders_and_normal_strings() {
    assert!(rules(r#"password = "changeme123""#).is_empty());
    assert!(rules(r#"api_key = "<your-api-key>""#).is_empty());
    assert!(rules(r#"token = "${GITHUB_TOKEN}""#).is_empty());
    assert!(rules(r#"password = "xxxxxxxxxxxx""#).is_empty());
    assert!(rules(r#"greeting = "hello there, friend""#).is_empty());
    assert!(rules(r#"let name = "Reihaneh";"#).is_empty());
}

#[test]
fn flags_high_entropy_strings_but_not_readable_ones() {
    let f = scan_text("t", r#"blob = "q8Vz2LmP0xR7tYw4Kc9NbH3s""#);
    assert_eq!(f.len(), 1);
    assert_eq!(f[0].rule, "high-entropy-string");
    assert_eq!(f[0].severity, Severity::Low);
    assert!(rules(r#"path = "src/components/Button""#).is_empty());
}

#[test]
fn ignore_marker_skips_a_line() {
    assert!(rules("key = AKIAIOSFODNN7EXAMPLE  # keyglint:ignore").is_empty());
}

#[test]
fn reports_correct_line_numbers() {
    let text = "first\nsecond\nkey = AKIAIOSFODNN7EXAMPLE\n";
    assert_eq!(scan_text("t", text)[0].line, 3);
}

#[test]
fn a_known_token_is_not_double_reported_as_entropy() {
    let line = format!(r#"TOKEN = "{}{}""#, "ghp_", "a1B2".repeat(9));
    assert_eq!(rules(&line), vec!["github-token"]);
}

#[test]
fn cli_scans_folders_and_uses_exit_codes() {
    let dir = std::env::temp_dir().join(format!("keyglint-test-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(dir.join("src")).unwrap();
    fs::create_dir_all(dir.join("node_modules")).unwrap();
    fs::write(dir.join("src/clean.txt"), "nothing to see here\n").unwrap();
    fs::write(
        dir.join("node_modules/lib.js"),
        "key = AKIAIOSFODNN7EXAMPLE",
    )
    .unwrap();

    let bin = env!("CARGO_BIN_EXE_keyglint");
    let clean = Command::new(bin).arg(&dir).output().unwrap();
    assert_eq!(clean.status.code(), Some(0), "node_modules must be skipped");

    fs::write(dir.join("src/config.env"), "AWS_KEY=AKIAIOSFODNN7EXAMPLE\n").unwrap();
    let dirty = Command::new(bin).arg(&dir).arg("--json").output().unwrap();
    assert_eq!(dirty.status.code(), Some(1));
    let out = String::from_utf8(dirty.stdout).unwrap();
    assert!(out.contains("\"rule\":\"aws-access-key\""));
    assert!(out.contains("AKIA****"));
    assert!(
        !out.contains("AKIAIOSFODNN7EXAMPLE"),
        "raw secrets must never be printed"
    );

    let high_only = Command::new(bin)
        .arg(&dir)
        .args(["--min-severity", "high"])
        .output()
        .unwrap();
    assert_eq!(high_only.status.code(), Some(1));

    let bad = Command::new(bin).arg("--nope").output().unwrap();
    assert_eq!(bad.status.code(), Some(2));
    let _ = fs::remove_dir_all(&dir);
}
