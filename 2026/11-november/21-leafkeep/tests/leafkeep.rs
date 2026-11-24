use leafkeep::*;

fn oolong() -> Brew {
    Brew::new(tea("oolong").unwrap(), 5.0, 100.0, 95.0, vessel("gaiwan").unwrap()).unwrap()
}

#[test]
fn every_cup_matches_the_first() {
    let b = oolong();
    let s = plan(&b, 20.0, 15).unwrap();
    assert!(s.cups.len() >= 8, "an oolong should last a session: {}", s.cups.len());
    for c in &s.cups {
        assert!(
            (c.strength - s.target).abs() < 1e-3 * s.target,
            "{} vs {}",
            c.strength,
            s.target
        );
    }
    // later steeps are longer, and the leaves give up less each time
    for w in s.cups.windows(2) {
        assert!(w[1].steep >= w[0].steep - 1e-6);
        assert!(w[1].left < w[0].left);
    }
    assert!(s.spent);
}

#[test]
fn nothing_is_made_or_lost() {
    let b = oolong();
    let total = Leaves::fresh(&b).total();
    let mut leaves = Leaves::fresh(&b);
    let mut poured = 0.0;
    for steep in [20.0, 30.0, 45.0, 60.0, 90.0] {
        let (cup, after) = infuse(&b, &leaves, steep);
        poured += cup.strength * cup.volume;
        leaves = after;
    }
    // what left the leaves is in the cups or in the liquor the leaves still hold
    let extracted = total - leaves.total();
    assert!(
        (poured + leaves.carry - extracted).abs() < 1e-6 * total,
        "{poured} + {} vs {extracted}",
        leaves.carry
    );
}

#[test]
fn extraction_matches_the_exact_answer_at_constant_temperature() {
    // With no cooling (a huge time constant), an unfurled leaf and one pool, the cup holds
    // M (1 - e^{-kt}) / V exactly.
    let t = Tea {
        name: "test",
        soluble: 0.3,
        fast_share: 1.0,
        k_fast: 0.02,
        k_slow: 0.0,
        ea: 40_000.0,
        unfurl: 1.0,
        hold: 2.0,
    };
    let b = Brew::new(t, 5.0, 100.0, 95.0, 1e12).unwrap();
    let (cup, _) = infuse(&b, &Leaves::fresh(&b), 60.0);
    let exact = 1500.0 * (1.0 - (-0.02f64 * 60.0).exp()) / 100.0;
    assert!((cup.strength - exact).abs() < 1e-9, "{} vs {exact}", cup.strength);
}

#[test]
fn hotter_water_and_a_warmer_pot_extract_faster() {
    let t = tea("green").unwrap();
    let hot = Brew::new(t, 4.0, 100.0, 95.0, 480.0).unwrap();
    let cool = Brew::new(t, 4.0, 100.0, 75.0, 480.0).unwrap();
    let held = Brew::new(t, 4.0, 100.0, 95.0, 900.0).unwrap();
    let f = |b: &Brew| infuse(b, &Leaves::fresh(b), 60.0).0.strength;
    assert!(f(&hot) > f(&cool) * 1.3);
    assert!(f(&held) > f(&hot));
}

#[test]
fn a_lighter_cup_lasts_longer() {
    let b = oolong();
    let full = plan(&b, 20.0, 30).unwrap();
    let light = plan_to(&b, full.target * 0.7, None, 30).unwrap();
    assert!(light.cups.len() > full.cups.len());
}

#[test]
fn too_strong_is_refused() {
    let b = oolong();
    assert_eq!(plan_to(&b, 1000.0, None, 5), Err(Error::TooStrong));
}

#[test]
fn calibration_recovers_a_different_tea() {
    let b = oolong();
    let truth = Tea {
        soluble: 0.36,
        k_fast: b.tea.k_fast * 0.7,
        k_slow: b.tea.k_slow * 1.4,
        ..b.tea
    };
    let tb = Brew { tea: truth, ..b };
    let steeps = [20.0, 25.0, 30.0, 40.0, 50.0, 70.0, 100.0];
    let readings: Vec<Reading> = predict(&tb, &steeps)
        .iter()
        .zip(steeps)
        .map(|(&tds, steep)| Reading { steep, tds })
        .collect();
    let (fit, rms) = calibrate(&b, &readings);
    assert!(rms < 0.003, "rms {rms}");
    assert!((fit.soluble - 0.36).abs() < 0.05, "soluble {}", fit.soluble);
    // and it predicts a session it wasn't shown
    let fb = Brew { tea: fit, ..b };
    let later = [150.0, 240.0];
    let mut all = steeps.to_vec();
    all.extend(later);
    let (p, q) = (predict(&fb, &all), predict(&tb, &all));
    for (a, b) in p.iter().zip(&q) {
        assert!((a - b).abs() < 0.01, "{a} vs {b}");
    }
}

#[test]
fn inputs_are_bounded() {
    let t = tea("oolong").unwrap();
    assert!(Brew::new(t, f64::NAN, 100.0, 95.0, 480.0).is_err());
    assert!(Brew::new(t, 5.0, 100.0, 120.0, 480.0).is_err());
    assert!(Brew::new(t, 5.0, 1e9, 95.0, 480.0).is_err());
    assert!(
        Brew::new(t, 30.0, 60.0, 95.0, 480.0).is_err(),
        "more leaf than the water can wet"
    );
    assert!(plan(&oolong(), f64::INFINITY, 5).is_err());
    assert!(matches!(tea("<script>"), Err(Error::UnknownTea(_))));
    assert_eq!(
        Error::UnknownTea("a\u{1b}[31mb".into()).to_string(),
        "unknown tea 'a[31mb': try green, white, oolong, black or puerh"
    );
}

#[test]
fn readings_are_parsed_strictly() {
    let ok = parse_readings("steep,tds\n# a session\n20,0.42\n25,0.40\n30, 0.38\n").unwrap();
    assert_eq!(ok.len(), 3);
    for bad in [
        "20,0.4\n25,0.4\n",
        "20,0.4,9\n25,0.4\n30,0.4\n",
        "20,abc\n25,0.4\n30,0.4\n",
        "20,NaN\n25,0.4\n30,0.4\n",
        "-5,0.4\n25,0.4\n30,0.4\n",
        "20,40\n25,0.4\n30,0.4\n",
    ] {
        assert!(parse_readings(bad).is_err(), "{bad:?}");
    }
    assert!(parse_readings(&"20,0.4\n".repeat(50)).is_err());
    assert!(parse_readings(&"x".repeat(70_000)).is_err());
}
