package sky

import (
	"math"
	"time"
)

// SynodicMonth is the average time from one new moon to the next, in days.
const SynodicMonth = 29.530588853

// referenceNewMoon is a known new moon: 6 January 2000, 18:14 UTC.
var referenceNewMoon = time.Date(2000, 1, 6, 18, 14, 0, 0, time.UTC)

// MoonInfo describes the Moon at one instant.
type MoonInfo struct {
	Phase        float64 // 0 = new, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter
	Illumination float64 // fraction of the disc lit, 0..1
	AgeDays      float64 // days since the last new moon
	Name         string
	NextNew      time.Time
	NextFull     time.Time
}

var phaseNames = [8]string{
	"New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
	"Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent",
}

// PhaseName maps a phase (0..1) to one of eight traditional names. Each name
// covers a slice of 1/8 of the cycle, centred on its exact moment.
func PhaseName(phase float64) string {
	idx := int(math.Floor(phase*8+0.5)) % 8
	return phaseNames[idx]
}

// Moon works out the Moon's phase from the mean length of a lunar month.
// The real Moon speeds up and slows down along its orbit, so this "mean"
// method can be off by up to about half a day. That is plenty for a phase
// name and a drawing, and it fits in ten lines.
func Moon(t time.Time) MoonInfo {
	days := t.Sub(referenceNewMoon).Hours() / 24
	phase := math.Mod(days/SynodicMonth, 1)
	if phase < 0 {
		phase++
	}
	age := phase * SynodicMonth
	untilNew := (1 - phase) * SynodicMonth
	untilFull := math.Mod(0.5-phase+1, 1) * SynodicMonth
	return MoonInfo{
		Phase:        phase,
		Illumination: (1 - math.Cos(2*math.Pi*phase)) / 2,
		AgeDays:      age,
		Name:         PhaseName(phase),
		NextNew:      t.Add(time.Duration(untilNew * 24 * float64(time.Hour))),
		NextFull:     t.Add(time.Duration(untilFull * 24 * float64(time.Hour))),
	}
}
