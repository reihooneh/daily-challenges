//! Runs the built command the way a user would.

use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Output, Stdio};

fn bin() -> Command {
    Command::new(env!("CARGO_BIN_EXE_loomfix"))
}

fn example(name: &str) -> String {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("examples")
        .join(name)
        .to_string_lossy()
        .into_owned()
}

fn run(args: &[&str], stdin: &str) -> (i32, String, String) {
    let mut child = bin()
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(stdin.as_bytes()).ok();
    let Output { status, stdout, stderr } = child.wait_with_output().unwrap();
    (
        status.code().unwrap_or(-1),
        String::from_utf8_lossy(&stdout).into(),
        String::from_utf8_lossy(&stderr).into(),
    )
}

#[test]
fn identifies_the_example() {
    let (code, out, _) = run(&["id", &example("kestrel-bay.txt"), &example("night-watch.txt")], "");
    assert_eq!(code, 0);
    assert!(out.contains("Most likely: Gannet Rock  Fl(2) W 10s  (100%)"), "{out}");
    assert!(out.contains("7 of 7 times paired with its rhythm, 0 flashes missed"));
    assert!(out.contains("    light  ##....##......"));
    assert!(out.contains("    you    ^     ^\n"), "{out}");
}

#[test]
fn watch_from_standard_input() {
    let watch = "colour G\n0 off\n1 on\n2 off\n3 on\n6 off\n7 on\n";
    let (code, out, _) = run(&["id", &example("kestrel-bay.txt"), "-"], watch);
    assert_eq!(code, 0);
    assert!(out.contains("Most likely: Harbour Entrance N  Oc(2) G 6s"), "{out}");
}

#[test]
fn nothing_fits() {
    let (code, out, _) = run(&["id", &example("kestrel-bay.txt"), "-"], "colour Y\n1\n2\n3\n");
    assert_eq!(code, 0);
    assert!(out.contains("No light in the list can make these timings"));
    // White, but a rhythm nobody has: flashes 0.4 s apart then 6.3 s.
    let (_, out, _) = run(
        &["id", &example("kestrel-bay.txt"), "-"],
        "colour W\nwatched 0 to 30\n1\n1.4\n7.7\n8.1\n14.4\n14.8\n21.1\n21.5\n27.8\n28.2\n",
    );
    assert!(out.contains("None of the lights fits well"), "{out}");
}

#[test]
fn audit_flags_the_close_pair() {
    let list = "Gannet Rock | Fl(2) W 10s\nBlack Ledge | Fl(2) W 9s\nSeal Island | LFl 10s\nFerry Slip | F R\n";
    let (code, out, _) = run(&["audit", "-", "--counted", "--sims", "60", "--seed", "4"], list);
    assert_eq!(code, 0);
    assert!(out.contains("Easy to mix up"), "{out}");
    assert!(
        out.contains("Gannet Rock (Fl(2) W 10s) was taken for Black Ledge (Fl(2) W 9s)"),
        "{out}"
    );
    assert!(out.contains("(a fixed light has no rhythm to time)"));
    let (_, again, _) = run(&["audit", "-", "--counted", "--sims", "60", "--seed", "4"], list);
    assert_eq!(out, again, "the same seed gives the same report");
}

#[test]
fn show_draws_one_period() {
    let (code, out, _) = run(&["show", "Mo(U) 4s"], "");
    assert_eq!(code, 0);
    assert_eq!(out, "Mo(U) W 4s  (0.25 s a column; # on, . off)\n  ##..##..######..\n");
}

#[test]
fn refusals_never_echo_input() {
    let cases: [(&[&str], &str, &str); 9] = [
        (&[], "", "usage"),
        (&["show", "Fl(2);rm -rf SECRET 10s"], "", "may only use"),
        (&["id", "-", "-"], "", "only one file"),
        (&["id", "/no/such/SECRET-file", "-"], "", "couldn't open"),
        (&["id", "/", "-"], "", "only regular files"),
        (&["audit", "-", "--sims", "99999"], "A | Q\n", "--sims must be"),
        (&["audit", "-", "--bogus"], "A | Q\n", "unknown option"),
        (&["id", "-", "/dev/null"], "A | Q\n", "only regular files"),
        (&["audit", "-"], "<script>SECRET</script> | Q\n", "line 1"),
    ];
    for (args, stdin, want) in cases {
        let (code, out, err) = run(args, stdin);
        assert_eq!(code, 2, "{args:?}");
        assert!(out.is_empty());
        assert!(err.contains(want), "{args:?}: {err}");
        assert!(!err.contains("SECRET"), "{args:?} echoed input: {err}");
    }
}

#[test]
fn refuses_links_and_huge_input() {
    let dir = std::env::temp_dir().join(format!("loomfix-test-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let link = dir.join("link.txt");
    let _ = std::fs::remove_file(&link);
    #[cfg(unix)]
    std::os::unix::fs::symlink(example("kestrel-bay.txt"), &link).unwrap();
    let (code, _, err) = run(&["audit", link.to_str().unwrap()], "");
    assert_eq!(code, 2);
    assert!(err.contains("only regular files"), "{err}");
    std::fs::remove_dir_all(&dir).ok();
    let (code, _, err) = run(&["audit", "-"], &"# x\n".repeat(20_000));
    assert_eq!(code, 2);
    assert!(err.contains("64 KB"), "{err}");
    let mut child = bin()
        .args(["audit", "-"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(b"A | Q\n\xff\xfe\n").unwrap();
    let o = child.wait_with_output().unwrap();
    assert_eq!(o.status.code(), Some(2));
    assert!(String::from_utf8_lossy(&o.stderr).contains("UTF-8"));
}
