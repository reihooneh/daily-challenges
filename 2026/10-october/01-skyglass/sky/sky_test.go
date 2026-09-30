package sky

import (
	"math"
	"strings"
	"testing"
	"time"
)

func day(y int, m time.Month, d int) time.Time { return time.Date(y, m, d, 0, 0, 0, 0, time.UTC) }

func within(t *testing.T, label string, got, want time.Time, tol time.Duration) {
	t.Helper()
	if diff := got.Sub(want); diff > tol || diff < -tol {
		t.Errorf("%s = %s, want %s ± %s (off by %s)", label, got.Format("15:04"), want.Format("15:04"), tol, diff)
	}
}

// Reference values from a published almanac (sunrisesunset.com) for
// Sydney at 33°S 151°E. Times are converted to UTC.
func TestSunMatchesAlmanacForSydney(t *testing.T) {
	aest := time.FixedZone("AEST", 10*3600)
	aedt := time.FixedZone("AEDT", 11*3600)
	cases := []struct {
		date            time.Time
		sunrise, sunset time.Time
	}{
		{day(2026, 10, 1), time.Date(2026, 10, 1, 5, 34, 0, 0, aest), time.Date(2026, 10, 1, 17, 58, 0, 0, aest)},
		{day(2026, 10, 5), time.Date(2026, 10, 5, 6, 28, 0, 0, aedt), time.Date(2026, 10, 5, 19, 1, 0, 0, aedt)},
	}
	for _, c := range cases {
		s := Sun(c.date, -33, 151)
		if s.Kind != Normal {
			t.Fatalf("expected a normal day on %s", c.date)
		}
		within(t, "sunrise "+c.date.Format("2 Jan"), s.Sunrise, c.sunrise, 3*time.Minute)
		within(t, "sunset "+c.date.Format("2 Jan"), s.Sunset, c.sunset, 3*time.Minute)
	}
}

func TestEquatorEquinoxIsAboutTwelveHours(t *testing.T) {
	s := Sun(day(2026, 3, 20), 0, 0)
	// A little over 12 h because refraction lifts the Sun early and holds it late.
	if s.DayLength < 12*time.Hour || s.DayLength > 12*time.Hour+15*time.Minute {
		t.Errorf("day length %s, want 12h-12h15m", s.DayLength)
	}
}

func TestSolarNoonIsBetweenSunriseAndSunset(t *testing.T) {
	s := Sun(day(2026, 7, 15), 51.5, -0.12)
	if !s.Sunrise.Before(s.SolarNoon) || !s.SolarNoon.Before(s.Sunset) {
		t.Errorf("order wrong: %v %v %v", s.Sunrise, s.SolarNoon, s.Sunset)
	}
	if !s.FirstLight.Before(s.Sunrise) || !s.Sunset.Before(s.LastLight) {
		t.Error("twilight should surround sunrise and sunset")
	}
}

func TestPolarNightAndMidnightSun(t *testing.T) {
	if k := Sun(day(2026, 12, 21), 78, 15).Kind; k != PolarNight {
		t.Errorf("78°N in December: got %v, want PolarNight", k)
	}
	if k := Sun(day(2026, 6, 21), 78, 15).Kind; k != MidnightSun {
		t.Errorf("78°N in June: got %v, want MidnightSun", k)
	}
	// Seasons flip in the southern hemisphere.
	if k := Sun(day(2026, 12, 21), -78, 166).Kind; k != MidnightSun {
		t.Errorf("78°S in December: got %v, want MidnightSun", k)
	}
}

func TestHemispheresMirrorEachOther(t *testing.T) {
	north := Sun(day(2026, 6, 21), 40, 0).DayLength
	south := Sun(day(2026, 12, 21), -40, 0).DayLength
	if d := north - south; d > 10*time.Minute || d < -10*time.Minute {
		t.Errorf("40°N in June (%s) should roughly equal 40°S in December (%s)", north, south)
	}
}

// Known 2026 events: total lunar eclipse (full moon) on 3 March 11:38 UTC,
// total solar eclipse (new moon) on 12 August 17:37 UTC.
func TestMoonPhaseMatchesEclipses(t *testing.T) {
	full := Moon(time.Date(2026, 3, 3, 11, 38, 0, 0, time.UTC))
	if math.Abs(full.Phase-0.5) > 0.035 {
		t.Errorf("3 Mar 2026 phase %.3f, want ≈0.5", full.Phase)
	}
	if full.Illumination < 0.98 || full.Name != "Full Moon" {
		t.Errorf("3 Mar 2026: %s %.2f, want Full Moon ≈1.0", full.Name, full.Illumination)
	}
	nw := Moon(time.Date(2026, 8, 12, 17, 37, 0, 0, time.UTC))
	if math.Min(nw.Phase, 1-nw.Phase) > 0.035 {
		t.Errorf("12 Aug 2026 phase %.3f, want ≈0", nw.Phase)
	}
	if nw.Illumination > 0.02 || nw.Name != "New Moon" {
		t.Errorf("12 Aug 2026: %s %.2f, want New Moon ≈0", nw.Name, nw.Illumination)
	}
}

func TestNextFullAndNewAreWithinAMonth(t *testing.T) {
	now := time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)
	m := Moon(now)
	for label, next := range map[string]time.Time{"full": m.NextFull, "new": m.NextNew} {
		d := next.Sub(now).Hours() / 24
		if d <= 0 || d > SynodicMonth {
			t.Errorf("next %s moon %.1f days away, want within one lunar month", label, d)
		}
	}
	// The next full moon after 1 Oct 2026 is 26 Oct (04:12 UTC).
	within(t, "next full moon", m.NextFull, time.Date(2026, 10, 26, 4, 12, 0, 0, time.UTC), 18*time.Hour)
}

func TestPhaseNames(t *testing.T) {
	cases := map[float64]string{
		0: "New Moon", 0.02: "New Moon", 0.98: "New Moon",
		0.125: "Waxing Crescent", 0.25: "First Quarter", 0.375: "Waxing Gibbous",
		0.5: "Full Moon", 0.625: "Waning Gibbous", 0.75: "Last Quarter", 0.875: "Waning Crescent",
	}
	for p, want := range cases {
		if got := PhaseName(p); got != want {
			t.Errorf("PhaseName(%v) = %q, want %q", p, got, want)
		}
	}
}

func count(s string, r rune) int { return strings.Count(s, string(r)) }

func TestRenderMoonShapes(t *testing.T) {
	if art := RenderMoon(0, 5, false); count(art, '#') != 0 {
		t.Error("a new moon should have no lit characters")
	}
	if art := RenderMoon(0.5, 5, false); count(art, '.') != 0 {
		t.Error("a full moon should have no dark characters")
	}
	// First quarter, northern view: lit on the right.
	for _, line := range strings.Split(RenderMoon(0.25, 5, false), "\n") {
		trimmed := strings.TrimSpace(line)
		if strings.HasPrefix(trimmed, "#") && strings.Contains(trimmed, ".") {
			t.Fatalf("first quarter should be dark on the left, lit on the right: %q", line)
		}
	}
	// The southern view is a mirror image of the northern one.
	n := strings.Split(RenderMoon(0.3, 5, false), "\n")
	s := strings.Split(RenderMoon(0.3, 5, true), "\n")
	for i := range n {
		if count(n[i], '#') != count(s[i], '#') {
			t.Fatalf("row %d: southern view should mirror northern view", i)
		}
	}
	if len(n) != 11 {
		t.Errorf("radius 5 should draw 11 rows, got %d", len(n))
	}
}
