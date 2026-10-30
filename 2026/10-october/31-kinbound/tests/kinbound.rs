use kinbound::graph::Edge;
use kinbound::parse::{parse, Kind};
use kinbound::solve::{analyse, born, died, Bound};
use std::io::Write;
use std::process::{Command, Stdio};

fn bound(lo: i64, hi: i64) -> Bound {
    Bound {
        lo: Some(lo),
        hi: Some(hi),
    }
}

fn dates(text: &str) -> Vec<(Bound, Bound)> {
    let a = analyse(&parse(text).expect("parses"));
    assert!(a.conflicts.is_empty(), "expected no conflicts");
    a.dates.expect("dates")
}

// ---------- Reading records ----------

#[test]
fn every_kind_of_date() {
    let t = parse(
        "person a Ann\nborn a 1841\nborn a about 1841\nborn a 1840-1842\nborn a before 1850\nborn a after 1830\n\
         died a 1900\nbaptised a 1841\nburied a 1901\ncensus a 1851 age 10\nalive a 1880\n",
    )
    .unwrap();
    assert_eq!(t.records.len(), 10);
    let Kind::Born(s) = t.records[1].kind else { panic!() };
    assert_eq!(
        (s.lo, s.hi, s.phrase()),
        (Some(1839), Some(1843), "about 1841 (1839-1843)".to_string())
    );
    let Kind::Born(s) = t.records[3].kind else { panic!() };
    assert_eq!((s.lo, s.hi), (None, Some(1850)));
}

#[test]
fn census_ages_meet_in_the_middle() {
    // 25 in 1841 means 1815-1816; 36 in 1851 means 1814-1815: only 1815 fits both.
    let d = dates("person m Mary\ncensus m 1841 age 25\ncensus m 1851 age 36\n");
    assert_eq!(d[0].0, bound(1815, 1815));
}

#[test]
fn bounds_flow_through_parents() {
    let d = dates("person g Grandmother\nperson m Mother\nperson c Child\nmother g of m\nmother m of c\nborn c 1900\n");
    assert_eq!(d[1].0, bound(1850, 1886)); // mother 14 to 50 at the birth
    assert_eq!(d[0].0, bound(1800, 1872));
    assert_eq!(d[1].1.lo, Some(1900)); // alive at the birth
}

#[test]
fn a_father_may_die_before_the_birth_but_not_long_before() {
    let d = dates("person f Father\nperson c Child\nfather f of c\nborn c 1900\n");
    assert_eq!(d[0].1.lo, Some(1899));
}

#[test]
fn marriage_needs_both_old_enough_and_alive() {
    let d = dates("person a Ann\nperson b Bob\nmarried a b 1900\n");
    assert_eq!(d[0].0.hi, Some(1886));
    assert_eq!(d[1].1.lo, Some(1900));
}

#[test]
fn rules_can_be_changed() {
    let d = dates("rule mother-age 16 45\nrule lifespan 90\nperson m Mother\nperson c Child\nmother m of c\nborn c 1900\n");
    assert_eq!(d[0].0, bound(1855, 1884));
    assert_eq!(d[0].1, bound(1900, 1974));
}

// ---------- Conflicts and fixes ----------

const LATE_CHILD: &str = "person t Thomas\nperson s Sarah\nburied t 1858\nfather t of s\nborn s 1861\n";

#[test]
fn a_conflict_is_found_and_explained() {
    let t = parse(LATE_CHILD).unwrap();
    let a = analyse(&t);
    assert_eq!(a.conflicts.len(), 1);
    let c = &a.conflicts[0];
    assert_eq!(c.gap, 2);
    let total: i64 = c.edges.iter().map(|&i| a.graph.edges[i].w).sum();
    assert_eq!(total, -2);
    let lines: Vec<usize> = c.edges.iter().map(|&i| a.graph.edges[i].line).collect();
    for l in [3, 4, 5] {
        assert!(lines.contains(&l));
    }
    assert_eq!(a.fixes, vec![vec![3], vec![4], vec![5]]);
}

#[test]
fn two_separate_mistakes_need_two_fixes() {
    let text = format!("{LATE_CHILD}person x Xavier\nborn x 1900\ndied x 1890\n");
    let a = analyse(&parse(&text).unwrap());
    assert!(a.conflicts.len() >= 2);
    assert!(a.fixes.iter().all(|f| f.len() == 2));
    assert_eq!(a.fixes.len(), 6);
    assert!(a.dates.is_some());
}

#[test]
fn too_many_mistakes_are_reported_without_a_fix() {
    let mut text = String::new();
    for i in 0..5 {
        text += &format!("person p{i} P{i}\nborn p{i} 1900\ndied p{i} 1890\n");
    }
    let a = analyse(&parse(&text).unwrap());
    assert!(a.fixes.is_empty() && a.dates.is_none());
    let out = kinbound::run(&text, None).unwrap();
    assert!(!out.consistent);
    assert!(out.text.contains("No set of up to 3 records"));
}

#[test]
fn the_example_family() {
    let text = std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/examples/ashworth.txt")).unwrap();
    let out = kinbound::run(&text, Some("hannah")).unwrap();
    assert!(!out.consistent);
    assert!(out.text.contains("they miss by 2 years"));
    assert!(out.text.contains("assume line 40 is the mistake"));
    assert!(out
        .text
        .lines()
        .any(|l| l.starts_with("Mary Ashworth ") && l.split_whitespace().nth(2) == Some("1815")));
    assert!(out.text.contains("Hannah Pell born no later than 1801, because:"));
}

// ---------- Against brute force ----------

struct Lcg(u64);
impl Lcg {
    fn next(&mut self, n: u64) -> u64 {
        self.0 = self
            .0
            .wrapping_mul(6_364_136_223_846_793_005)
            .wrapping_add(1_442_695_040_888_963_407);
        (self.0 >> 33) % n
    }
}

fn satisfies(edges: &[Edge], vals: &[i64], skip: &[usize]) -> bool {
    edges
        .iter()
        .all(|e| skip.contains(&e.line) || vals[e.to] - vals[e.from] <= e.w)
}

/// Two people, all four years inside a 26-year window: every assignment is checked directly.
#[test]
fn bounds_and_fixes_match_brute_force() {
    let mut rng = Lcg(7);
    let base = 1900;
    let (mut clashing, mut checked) = (0, 0);
    for case in 0..60 {
        let mut text = String::from(
            "rule lifespan 20\nrule mother-age 3 12\nrule father-age 3 12\nrule marriage-age 2\nperson a A\nperson b B\n",
        );
        for _ in 0..(2 + rng.next(4)) {
            let who = ["a", "b"][rng.next(2) as usize];
            let y = base + rng.next(26) as i64;
            text += &match rng.next(7) {
                0 => format!("born {who} {y}\n"),
                1 => format!("died {who} {y}\n"),
                2 => format!("born {who} before {y}\n"),
                3 => format!("died {who} after {y}\n"),
                4 => format!("alive {who} {y}\n"),
                5 => "mother a of b\n".to_string(),
                _ => format!("married a b {y}\n"),
            };
        }
        let window = text.lines().count() + 1; // the lines from here on only keep the years in the window
        text += &format!(
            "born a after {base}\nborn b after {base}\ndied a before {}\ndied b before {}\n",
            base + 25,
            base + 25
        );
        let tree = parse(&text).unwrap();
        let a = analyse(&tree);
        let edges = &a.graph.edges;
        let feasible = |skip: &[usize]| -> Vec<[i64; 4]> {
            let mut out = vec![];
            for v0 in base..=base + 25 {
                for v1 in v0..=base + 25 {
                    for v2 in base..=base + 25 {
                        for v3 in v2..=base + 25 {
                            let vals = [0, v0, v1, v2, v3];
                            if satisfies(edges, &vals, skip) {
                                out.push([v0, v1, v2, v3]);
                            }
                        }
                    }
                }
            }
            out
        };
        let all = feasible(&[]);
        assert_eq!(a.conflicts.is_empty(), !all.is_empty(), "case {case}:\n{text}");
        if a.fixes.iter().flatten().any(|&l| l >= window) {
            continue; // a fix that drops the window can't be checked inside it
        }
        clashing += usize::from(all.is_empty());
        checked += 1;
        let sols = if all.is_empty() { feasible(&a.assumed) } else { all };
        if let Some(d) = &a.dates {
            assert!(!sols.is_empty());
            let vars = [born(0), died(0), born(1), died(1)];
            for (k, &v) in vars.iter().enumerate() {
                let b = if v % 2 == 1 { d[(v - 1) / 2].0 } else { d[(v - 2) / 2].1 };
                let lo = sols.iter().map(|s| s[k]).min();
                let hi = sols.iter().map(|s| s[k]).max();
                assert_eq!((b.lo, b.hi), (lo, hi), "case {case} var {v}:\n{text}");
            }
        }
        // Every fix works, and nothing smaller would.
        if let Some(f) = a.fixes.first() {
            for fix in &a.fixes {
                assert!(!feasible(fix).is_empty());
            }
            let lines: Vec<usize> = tree.records.iter().map(|r| r.line).collect();
            if f.len() == 2 {
                for &l in &lines {
                    assert!(feasible(&[l]).is_empty(), "case {case}: line {l} alone would do");
                }
            }
        }
    }
    eprintln!("brute force: {checked} cases checked, {clashing} with conflicts");
    assert!(checked >= 30 && clashing >= 8 && clashing < checked);
}

// ---------- Hostile and odd input ----------

fn err(text: &str) -> String {
    match parse(text) {
        Ok(_) => panic!("accepted:\n{text}"),
        Err(e) => e.to_string(),
    }
}

#[test]
fn refuses_bad_input_without_echoing_it() {
    let cases = [
        ("born a 1841\n", "before their 'person' line"),
        ("person a Ann\nperson a Again\n", "already used"),
        ("person A Ann\n", "id is lower-case"),
        ("person a <script>\n", "names use letters"),
        ("person a Ann\u{202E}nhoJ\n", "names use letters"),
        ("person a Ann\x1b[2J\n", "control character"),
        ("person a Ann\nborn a 999\n", "between 1000 and 2100"),
        ("person a Ann\nborn a 1e3\n", "plain numbers"),
        ("person a Ann\nborn a 1850-1840\n", "earlier to later"),
        ("person a Ann\nborn a circa 1840\n", "write a date as"),
        ("person a Ann\ncensus a 1851 age 999\n", "0 to 120"),
        ("person a Ann\nmother a of a\n", "own parent"),
        ("person a Ann\nmarried a a 1900\n", "two different people"),
        ("person a Ann\nrule lifespan 500\n", "0 to 120"),
        ("person a Ann\nrule mother-age 50 14\n", "smaller number comes first"),
        ("person a Ann\nrule bedtime 9\n", "rules are"),
        ("person a Ann\nexhume a 1900\n", "lines start with"),
        ("person a Ann\nborn a\n", "write a date as"),
        ("name Smith\nname Jones\nperson a Ann\n", "title comes once"),
        ("# only a comment\n", "no 'person' lines"),
    ];
    for (text, want) in cases {
        let e = err(text);
        assert!(e.contains(want), "{text:?} gave {e:?}");
        assert!(!e.contains("script") && !e.contains("exhume") && !e.contains("bedtime"));
    }
    assert!(err(&format!("person a {}\n", "x".repeat(250))).contains("longer than 200"));
    assert!(err(&"#\n".repeat(40_000)).contains("larger than 64 KB"));
    let many: String = (0..401).map(|i| format!("person p{i} P\n")).collect();
    assert!(err(&many).contains("at most 400 people"));
}

#[test]
fn friendly_input_is_accepted() {
    let t = parse("\u{FEFF}name The Ó Briain family\r\nperson aoife Aoife Ó Briain\r\nperson jp Jean-Pierre d'Arcy\tJr.\nborn aoife 1950 # from a letter\n").unwrap();
    assert_eq!(t.people[0].name, "Aoife Ó Briain");
    assert_eq!(t.people[1].name, "Jean-Pierre d'Arcy Jr.");
    assert_eq!(t.records.len(), 1);
}

#[test]
fn a_large_family_stays_fast() {
    // 400 generations of mothers, each with a census record: a long chain for Bellman-Ford.
    let mut text = String::new();
    for i in 0..400 {
        text += &format!("person p{i} P{i}\n");
        if i > 0 {
            text += &format!("mother p{} of p{i}\n", i - 1);
        }
    }
    text += "born p399 2000\n";
    let start = std::time::Instant::now();
    let a = analyse(&parse(&text).unwrap());
    assert!(a.conflicts.is_empty());
    assert_eq!(a.dates.unwrap()[0].0.hi, Some(2000 - 399 * 14));
    assert!(start.elapsed().as_secs() < 20);
}

// ---------- The command line ----------

fn cli(args: &[&str], stdin: &str) -> (i32, String, String) {
    let mut child = Command::new(env!("CARGO_BIN_EXE_kinbound"))
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .unwrap();
    // The program may stop reading early (oversized input), so a broken pipe here is fine.
    let _ = child.stdin.take().unwrap().write_all(stdin.as_bytes());
    let out = child.wait_with_output().unwrap();
    (
        out.status.code().unwrap_or(-1),
        String::from_utf8_lossy(&out.stdout).into(),
        String::from_utf8_lossy(&out.stderr).into(),
    )
}

#[test]
fn command_line_exit_codes() {
    assert_eq!(cli(&["-"], "person a Ann\nborn a 1900\n").0, 0);
    assert_eq!(cli(&["-"], LATE_CHILD).0, 1);
    assert_eq!(cli(&["-"], "nonsense\n").0, 2);
    assert_eq!(cli(&[], "").0, 2);
    assert_eq!(cli(&["-", "--why"], "").0, 2);
    let (code, _, e) = cli(&["-", "--why", "nobody"], "person a Ann\n");
    assert_eq!((code, e.contains("isn't in the file")), (2, true));
}

#[test]
fn command_line_files() {
    let ex = concat!(env!("CARGO_MANIFEST_DIR"), "/examples/ashworth.txt");
    let (code, from_file, _) = cli(&[ex], "");
    assert_eq!(code, 1);
    assert_eq!(cli(&["-"], &std::fs::read_to_string(ex).unwrap()).1, from_file);
    let (code, _, e) = cli(&[env!("CARGO_MANIFEST_DIR")], "");
    assert_eq!((code, e.contains("could not be read")), (2, true));
    let (_, _, e) = cli(&["secret-name-zz.txt"], "");
    assert!(!e.contains("secret-name"));
    let (code, _, e) = cli(&["-"], &"#".repeat(200_000));
    assert_eq!((code, e.contains("larger than 64 KB")), (2, true));
    let (code, _, e) = cli(&["-"], "person a Ann\n\u{0}");
    assert_eq!((code, e.contains("control character")), (2, true));
}
