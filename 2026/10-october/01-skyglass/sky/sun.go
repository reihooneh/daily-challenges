// Package sky computes sunrise, sunset, twilight and Moon phase with
// closed-form astronomy formulas. No network, no data files.
package sky

import (
	"math"
	"time"
)

const deg = math.Pi / 180

// Zenith angles (degrees) that define each event. Sunrise is 90.833°, not 90°,
// because the atmosphere bends sunlight over the horizon (refraction) and the
// Sun is a disc, not a point: we see it slightly before it "should" rise.
const (
	zenithSunrise = 90.833
	zenithCivil   = 96.0
)

// DayKind says whether the Sun rises and sets normally on a given day.
type DayKind int

const (
	Normal      DayKind = iota
	MidnightSun         // the Sun never sets (polar summer)
	PolarNight          // the Sun never rises (polar winter)
)

// SunTimes holds one day's solar events in UTC.
type SunTimes struct {
	Kind       DayKind
	FirstLight time.Time // civil dawn: bright enough to see without lights
	Sunrise    time.Time
	SolarNoon  time.Time
	Sunset     time.Time
	LastLight  time.Time // civil dusk
	DayLength  time.Duration
	// Civil twilight can be missing near the poles even on a normal day.
	HasTwilight bool
}

// solarParams returns the equation of time (minutes) and the Sun's
// declination (radians) using NOAA's Fourier-series approximation.
// The equation of time is how far a sundial runs ahead or behind a clock.
func solarParams(date time.Time) (eqTime, decl float64) {
	doy := float64(date.YearDay())
	daysInYear := 365.0
	if y := date.Year(); (y%4 == 0 && y%100 != 0) || y%400 == 0 {
		daysInYear = 366
	}
	g := 2 * math.Pi / daysInYear * (doy - 1) // fractional year, radians
	eqTime = 229.18 * (0.000075 + 0.001868*math.Cos(g) - 0.032077*math.Sin(g) -
		0.014615*math.Cos(2*g) - 0.040849*math.Sin(2*g))
	decl = 0.006918 - 0.399912*math.Cos(g) + 0.070257*math.Sin(g) -
		0.006758*math.Cos(2*g) + 0.000907*math.Sin(2*g) -
		0.002697*math.Cos(3*g) + 0.00148*math.Sin(3*g)
	return
}

// hourAngle returns the Sun's hour angle (degrees) when it reaches the given
// zenith. ok is false if it never gets there that day; above is then true
// when the Sun stays above that angle all day.
func hourAngle(lat, decl, zenith float64) (ha float64, ok, above bool) {
	c := math.Cos(zenith*deg)/(math.Cos(lat*deg)*math.Cos(decl)) - math.Tan(lat*deg)*math.Tan(decl)
	if c > 1 {
		return 0, false, false
	}
	if c < -1 {
		return 0, false, true
	}
	return math.Acos(c) / deg, true, false
}

// minutesToTime converts "minutes after midnight UTC" into a time on date.
func minutesToTime(date time.Time, minutes float64) time.Time {
	day := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, time.UTC)
	return day.Add(time.Duration(minutes * float64(time.Minute)))
}

// Sun computes solar events for the calendar day `date` at latitude/longitude
// in degrees (north and east positive). Accuracy is about ±2 minutes outside
// the polar regions.
func Sun(date time.Time, lat, lon float64) SunTimes {
	eq, decl := solarParams(date)
	noon := 720 - 4*lon - eq // minutes after UTC midnight
	st := SunTimes{SolarNoon: minutesToTime(date, noon)}

	ha, ok, above := hourAngle(lat, decl, zenithSunrise)
	switch {
	case !ok && above:
		st.Kind, st.DayLength = MidnightSun, 24*time.Hour
		return st
	case !ok:
		st.Kind = PolarNight
		return st
	}
	st.Sunrise = minutesToTime(date, noon-4*ha)
	st.Sunset = minutesToTime(date, noon+4*ha)
	st.DayLength = st.Sunset.Sub(st.Sunrise)

	if hc, ok, _ := hourAngle(lat, decl, zenithCivil); ok {
		st.HasTwilight = true
		st.FirstLight = minutesToTime(date, noon-4*hc)
		st.LastLight = minutesToTime(date, noon+4*hc)
	}
	return st
}
