use quakecross::locate::{azimuth_gap, ellipse90, find_outliers, invert, solve, Problem};
use quakecross::parse::{parse, parse_time};
use quakecross::report::{clock, compass};
use std::io::Write;
use std::process::{Command, Stdio};

const STATIONS: [(&str, f64, f64); 7] = [
    ("NEW1", -32.927, 151.776),
    ("MAIT", -32.733, 151.556),
    ("CESS", -32.833, 151.357),
    ("SING", -32.567, 151.168),
    ("GOSF", -33.426, 151.343),
    ("TARE", -31.900, 152.460),
    ("DUNG", -32.400, 151.750),
];

fn clk(t: f64) -> String {
    let t = t.rem_euclid(86_400.0);
    format!(
        "{:02}:{:02}:{:05.2}",
        (t / 3600.0) as u32,
        (t % 3600.0 / 60.0) as u32,
        t % 60.0
    )
}

/// A pick file for a quake at (lat, lon, depth, origin seconds), with tiny deterministic jitter,
/// and an optional error added to one station's S time.
fn synthetic(lat: f64, lon: f64, z: f64, t0: f64, depth_line: &str, bad: Option<(&str, f64)>) -> String {
    let mut out = format!("event Test\nvelocity p 6.0 s 3.5\n{depth_line}\n");
    for (k, (name, la, lo)) in STATIONS.iter().enumerate() {
        let x = (lo - lon) * 111.32 * lat.to_radians().cos();
        let y = (la - lat) * 110.57;
        let r = (x * x + y * y + z * z).sqrt();
        let jitter = [0.01, -0.02, 0.0, 0.02, -0.01, 0.01, -0.01][k];
        let tp = t0 + r / 6.0 + jitter;
        let mut ts = t0 + r / 3.5 - jitter;
        if let Some((b, dt)) = bad {
            if b == *name {
                ts += dt;
            }
        }
        out += &format!("station {name} {la} {lo} p {} s {}\n", clk(tp), clk(ts));
    }
    out
}

fn locate(text: &str) -> (f64, f64, f64, f64, Vec<String>) {
    let picks = parse(text).expect("parses");
    let prob = Problem::new(&picks).expect("problem");
    let (flagged, s) = find_outliers(&prob);
    let (lat, lon) = prob.proj_to_deg(s.x, s.y);
    let names = flagged.iter().map(|&i| {
        let k = &picks.picks[prob.obs[i].pick];
        format!("{} {}", picks.stations[k.station].name, k.phase.name())
    });
    (lat, lon, s.z, s.t0, names.collect())
}

fn km_between(a: (f64, f64), b: (f64, f64)) -> f64 {
    let dx = (a.1 - b.1) * 111.32 * a.0.to_radians().cos();
    let dy = (a.0 - b.0) * 110.57;
    dx.hypot(dy)
}

// ---------- locating ----------

#[test]
fn recovers_a_quake_inside_the_network_with_fixed_depth() {
    let t0 = 3.0 * 3600.0 + 14.0 * 60.0 + 3.2;
    let (lat, lon, z, ot, bad) = locate(&synthetic(-32.95, 151.61, 10.0, t0, "depth 10", None));
    assert!(km_between((lat, lon), (-32.95, 151.61)) < 0.5, "{lat} {lon}");
    assert_eq!(z, 10.0);
    assert!((ot - t0).abs() < 0.1);
    assert!(bad.is_empty());
}

#[test]
fn recovers_depth_when_free() {
    let (lat, lon, z, _, _) = locate(&synthetic(-32.80, 151.45, 14.0, 1000.0, "depth free", None));
    assert!(km_between((lat, lon), (-32.80, 151.45)) < 1.0);
    assert!((z - 14.0).abs() < 2.5, "depth {z}");
}

#[test]
fn finds_a_quake_outside_the_network() {
    // Offshore, east of every station: the grid search must still find it.
    let (lat, lon, _, _, _) = locate(&synthetic(-33.10, 152.30, 10.0, 500.0, "depth 10", None));
    assert!(km_between((lat, lon), (-33.10, 152.30)) < 2.0, "{lat} {lon}");
}

#[test]
fn names_the_bad_pick() {
    let (lat, lon, _, _, bad) = locate(&synthetic(-32.95, 151.61, 10.0, 100.0, "depth 10", Some(("CESS", 2.4))));
    assert_eq!(bad, vec!["CESS S".to_string()]);
    assert!(km_between((lat, lon), (-32.95, 151.61)) < 0.5);
}

#[test]
fn names_two_bad_picks_and_an_early_one() {
    let mut text = synthetic(-32.95, 151.61, 10.0, 100.0, "depth 10", Some(("SING", -1.8)));
    text = text.replace("station DUNG", "# station DUNG"); // swap DUNG's line for one with a bad S time
    text += &synthetic(-32.95, 151.61, 10.0, 100.0, "depth 10", Some(("DUNG", 3.0)))
        .lines()
        .filter(|l| l.starts_with("station DUNG"))
        .map(|l| format!("{l}\n"))
        .collect::<String>();
    let (_, _, _, _, mut bad) = locate(&text);
    bad.sort();
    assert_eq!(bad, vec!["DUNG S".to_string(), "SING S".to_string()]);
}

#[test]
fn good_picks_are_not_flagged() {
    for (lat, lon) in [(-32.95, 151.61), (-32.6, 151.9), (-33.2, 151.2)] {
        let (_, _, _, _, bad) = locate(&synthetic(lat, lon, 8.0, 50.0, "depth 8", None));
        assert!(bad.is_empty(), "{lat} {lon}: {bad:?}");
    }
}

#[test]
fn picks_across_midnight() {
    let t0 = 86_400.0 - 5.0; // 23:59:55
    let (lat, lon, _, ot, _) = locate(&synthetic(-32.95, 151.61, 10.0, t0, "depth 10", None));
    assert!(km_between((lat, lon), (-32.95, 151.61)) < 0.5);
    assert!((ot.rem_euclid(86_400.0) - t0).abs() < 0.1);
}

// ---------- maths ----------

#[test]
fn linear_algebra() {
    let a = vec![vec![4.0, 1.0, 0.0], vec![1.0, 3.0, 1.0], vec![0.0, 1.0, 2.0]];
    let x = solve(a.clone(), vec![1.0, 2.0, 3.0]).unwrap();
    for (row, b) in a.iter().zip([1.0, 2.0, 3.0]) {
        let v: f64 = row.iter().zip(&x).map(|(p, q)| p * q).sum();
        assert!((v - b).abs() < 1e-12);
    }
    let inv = invert(a.clone()).unwrap();
    for (i, row) in a.iter().enumerate() {
        for j in 0..3 {
            let v: f64 = row.iter().zip(&inv).map(|(p, inv_row)| p * inv_row[j]).sum();
            assert!((v - if i == j { 1.0 } else { 0.0 }).abs() < 1e-12);
        }
    }
    assert!(
        solve(vec![vec![1.0, 2.0], vec![2.0, 4.0]], vec![1.0, 2.0]).is_none(),
        "singular"
    );
}

#[test]
fn ellipse_axes_and_direction() {
    let k = 4.605_f64.sqrt();
    let (a, b, az) = ellipse90(4.0, 1.0, 0.0); // long in x = east
    assert!((a - 2.0 * k).abs() < 1e-9 && (b - k).abs() < 1e-9 && (az - 90.0).abs() < 1e-9);
    let (_, _, az) = ellipse90(1.0, 4.0, 0.0); // long in y = north
    assert!(az.abs() < 1e-9 || (az - 180.0).abs() < 1e-9);
    let (_, _, az) = ellipse90(2.5, 2.5, 1.5); // tilted 45° towards north-east
    assert!((az - 45.0).abs() < 1e-9, "{az}");
}

#[test]
fn azimuthal_gap() {
    let around = [(1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0)];
    assert!((azimuth_gap(&around, 0.0, 0.0) - 90.0).abs() < 1e-9);
    let one_side = [(1.0, 1.0), (1.0, -1.0), (2.0, 0.0)];
    assert!(azimuth_gap(&one_side, 0.0, 0.0) > 180.0);
}

#[test]
fn formatting() {
    assert_eq!(clock(3.0 * 3600.0 + 14.0 * 60.0 + 7.426), "03:14:07.43");
    assert_eq!(clock(86_400.0 + 1.0), "00:00:01.00");
    assert_eq!(clock(59.999), "00:01:00.00");
    assert_eq!(compass(0.0), "N");
    assert_eq!(compass(359.0), "N");
    assert_eq!(compass(247.5), "WSW");
    assert_eq!(parse_time("03:14:07.42"), Some(11647.42));
    for bad in [
        "3:14:07",
        "03:60:00",
        "24:00:00",
        "03:14:60.0",
        "03:14:07.",
        "03:14:+7.4",
        "aa:bb:cc",
        "03:14:07:00",
        "03:14:07.1234567",
    ] {
        assert_eq!(parse_time(bad), None, "{bad}");
    }
}

// ---------- bad input ----------

#[test]
fn rejects_bad_files() {
    let ok = "velocity p 6 s 3.5\nstation AA -33 151 p 00:00:01 s 00:00:02\nstation BB -33.1 151 p 00:00:01\nstation CC -33 151.1 p 00:00:01\n";
    assert!(parse(ok).is_ok());
    let cases = [
        ("", "no stations"),
        ("station aa -33 151 p 00:00:01\n", "capital"),
        ("station AA -33 151 p 00:00:01\nstation AA -33 151 p 00:00:02\n", "twice"),
        ("station AA -95 151 p 00:00:01\n", "latitude"),
        ("station AA -33 1e3 p 00:00:01\n", "longitude"),
        ("station AA -33 151 p 00:00:01 p 00:00:02\n", "two P"),
        ("station AA -33 151 q 00:00:01\n", "phases"),
        ("station AA -33 151 p 25:00:00\n", "HH:MM"),
        ("velocity p 3 s 4\n", "slower"),
        ("velocity p NaN s 3\n", "number"),
        ("depth 900\n", "depth"),
        ("event <script>\n", "event names"),
        ("rm -rf /\n", "lines start"),
        ("station AA -33 151 p 00:00:01 \u{1b}[31m\n", "control"),
        ("event x\u{202e}y\n", "hidden"),
    ];
    for (text, want) in cases {
        let e = parse(text).expect_err(text);
        assert!(e.contains(want), "{text:?}: {e}");
    }
    assert!(parse(&"#".repeat(70_000)).unwrap_err().contains("64 KB"));
    assert!(parse(&format!("# {}\n", "x".repeat(300))).unwrap_err().contains("longer"));
}

#[test]
fn refuses_impossible_problems() {
    let two = "station AA -33 151 p 00:00:01 s 00:00:02\nstation BB -33.1 151 p 00:00:01 s 00:00:03\n";
    assert!(Problem::new(&parse(two).unwrap()).unwrap_err().contains("3 stations"));
    let few = "station AA -33 151 p 00:00:01\nstation BB -33.1 151 p 00:00:01\nstation CC -33 151.1 p 00:00:01\n";
    assert!(Problem::new(&parse(few).unwrap()).unwrap_err().contains("aren't enough"));
    let far =
        "station AA -33 151 p 00:00:01 s 00:00:02\nstation BB 40 -3 p 00:00:01 s 00:00:03\nstation CC -33 151.1 p 00:00:01\n";
    assert!(Problem::new(&parse(far).unwrap()).unwrap_err().contains("1,000 km"));
    let slow =
        "station AA -33 151 p 00:00:01 s 00:00:02\nstation BB -33.1 151 p 00:20:01 s 00:00:03\nstation CC -33 151.1 p 00:00:01\n";
    assert!(Problem::new(&parse(slow).unwrap()).unwrap_err().contains("10 minutes"));
}

// ---------- command line ----------

fn cli(args: &[&str], stdin: &str) -> (i32, String, String) {
    let mut child = Command::new(env!("CARGO_BIN_EXE_quakecross"))
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .current_dir(env!("CARGO_MANIFEST_DIR"))
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(stdin.as_bytes()).ok();
    let out = child.wait_with_output().unwrap();
    (
        out.status.code().unwrap_or(-1),
        String::from_utf8_lossy(&out.stdout).into(),
        String::from_utf8_lossy(&out.stderr).into(),
    )
}

#[test]
fn command_line() {
    let (code, out, _) = cli(&["examples/hunter.txt"], "");
    assert_eq!(code, 1);
    assert!(out.contains("CESS S: arrived 2.36 s later"), "{out}");
    assert!(out.contains("32.949°S 151.610°E"), "{out}");
    let (code, out, _) = cli(&["-"], &synthetic(-32.95, 151.61, 10.0, 100.0, "depth 10", None));
    assert_eq!(code, 0, "{out}");
    assert!(out.contains("standard input"));
    let (code, _, err) = cli(&["/dev/zero"], "");
    assert_eq!(code, 2);
    assert!(err.contains("regular file"));
    let (code, _, _) = cli(&["no/such/file"], "");
    assert_eq!(code, 2);
    let (code, _, _) = cli(&["a", "b"], "");
    assert_eq!(code, 2);
    let (code, _, err) = cli(&["-"], "station AA -33 151 p 00:00:01 \u{1b}]0;pwned\u{7}\n");
    assert_eq!(code, 2);
    assert!(!err.contains('\u{1b}') && !err.contains("pwned"));
    let (code, out, _) = cli(&["--help"], "");
    assert_eq!(code, 0);
    assert!(out.contains("Usage"));
}
