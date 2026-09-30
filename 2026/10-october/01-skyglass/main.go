// Skyglass: sunrise, sunset, twilight and the Moon's phase for any place on
// Earth, right in your terminal. Works fully offline.
package main

import (
	"flag"
	"fmt"
	"io"
	"math"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/reihooneh/daily-challenges/skyglass/sky"
)

type city struct {
	name     string
	lat, lon float64
	zone     string // IANA time zone, so daylight saving is handled correctly
}

var cities = map[string]city{
	"sydney":    {"Sydney", -33.8688, 151.2093, "Australia/Sydney"},
	"melbourne": {"Melbourne", -37.8136, 144.9631, "Australia/Melbourne"},
	"tehran":    {"Tehran", 35.6892, 51.3890, "Asia/Tehran"},
	"london":    {"London", 51.5072, -0.1276, "Europe/London"},
	"newyork":   {"New York", 40.7128, -74.0060, "America/New_York"},
	"tokyo":     {"Tokyo", 35.6762, 139.6503, "Asia/Tokyo"},
	"reykjavik": {"Reykjavik", 64.1466, -21.9426, "Atlantic/Reykjavik"},
	"tromso":    {"Tromsø", 69.6492, 18.9553, "Europe/Oslo"},
	"singapore": {"Singapore", 1.3521, 103.8198, "Asia/Singapore"},
}

func cityNames() string {
	names := make([]string, 0, len(cities))
	for k := range cities {
		names = append(names, k)
	}
	sort.Strings(names)
	return strings.Join(names, ", ")
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr, time.Now()))
}

// run is the whole program, separated from main so tests can call it.
func run(args []string, out, errOut io.Writer, now time.Time) int {
	fs := flag.NewFlagSet("skyglass", flag.ContinueOnError)
	fs.SetOutput(errOut)
	cityFlag := fs.String("city", "sydney", "built-in city: "+cityNames())
	lat := fs.Float64("lat", math.NaN(), "latitude in degrees (south is negative)")
	lon := fs.Float64("lon", math.NaN(), "longitude in degrees (west is negative)")
	zone := fs.String("tz", "", "IANA time zone for --lat/--lon, e.g. Europe/Paris (default UTC)")
	dateFlag := fs.String("date", "", "date as YYYY-MM-DD (default: today)")
	noArt := fs.Bool("no-art", false, "hide the Moon drawing")
	if err := fs.Parse(args); err != nil {
		return 2
	}

	place := cities["sydney"]
	custom := !math.IsNaN(*lat) || !math.IsNaN(*lon)
	if custom {
		if math.IsNaN(*lat) || math.IsNaN(*lon) {
			fmt.Fprintln(errOut, "skyglass: give both --lat and --lon")
			return 2
		}
		if *lat < -90 || *lat > 90 || *lon < -180 || *lon > 180 {
			fmt.Fprintln(errOut, "skyglass: latitude must be -90..90 and longitude -180..180")
			return 2
		}
		tz := *zone
		if tz == "" {
			tz = "UTC"
		}
		place = city{fmt.Sprintf("%.4f, %.4f", *lat, *lon), *lat, *lon, tz}
	} else {
		c, ok := cities[strings.ToLower(strings.ReplaceAll(*cityFlag, " ", ""))]
		if !ok {
			fmt.Fprintf(errOut, "skyglass: unknown city %q (try: %s, or use --lat/--lon)\n", *cityFlag, cityNames())
			return 2
		}
		place = c
	}

	loc, err := time.LoadLocation(place.zone)
	if err != nil {
		fmt.Fprintf(errOut, "skyglass: unknown time zone %q\n", place.zone)
		return 2
	}

	day := now.In(loc)
	if *dateFlag != "" {
		d, err := time.ParseInLocation("2006-01-02", *dateFlag, loc)
		if err != nil {
			fmt.Fprintf(errOut, "skyglass: date must look like 2026-10-01\n")
			return 2
		}
		day = d.Add(12 * time.Hour)
	}
	// Solar events are computed for the local calendar date.
	civil := time.Date(day.Year(), day.Month(), day.Day(), 0, 0, 0, 0, time.UTC)
	report(out, place, loc, civil, day, *noArt)
	return 0
}

func clock(t time.Time, loc *time.Location) string { return t.In(loc).Format("15:04") }

func report(out io.Writer, p city, loc *time.Location, civil, moment time.Time, noArt bool) {
	_, offset := moment.Zone()
	fmt.Fprintf(out, "Skyglass · %s · %s (UTC%+g)\n\n", p.name, moment.Format("Mon 2 Jan 2006"), float64(offset)/3600)

	s := sky.Sun(civil, p.lat, p.lon)
	fmt.Fprintln(out, "  Sun")
	switch s.Kind {
	case sky.MidnightSun:
		fmt.Fprintln(out, "  The Sun doesn't set today (midnight sun).")
		fmt.Fprintf(out, "  Solar noon    %s\n", clock(s.SolarNoon, loc))
	case sky.PolarNight:
		fmt.Fprintln(out, "  The Sun doesn't rise today (polar night).")
	default:
		if s.HasTwilight {
			fmt.Fprintf(out, "  First light   %s\n", clock(s.FirstLight, loc))
		}
		fmt.Fprintf(out, "  Sunrise       %s\n", clock(s.Sunrise, loc))
		fmt.Fprintf(out, "  Solar noon    %s\n", clock(s.SolarNoon, loc))
		fmt.Fprintf(out, "  Sunset        %s\n", clock(s.Sunset, loc))
		if s.HasTwilight {
			fmt.Fprintf(out, "  Last light    %s\n", clock(s.LastLight, loc))
		}
		h := int(s.DayLength.Hours())
		m := int(s.DayLength.Minutes()) - 60*h
		fmt.Fprintf(out, "  Day length    %dh %02dm\n", h, m)
	}

	m := sky.Moon(moment)
	fmt.Fprintln(out, "\n  Moon")
	if !noArt {
		for _, line := range strings.Split(sky.RenderMoon(m.Phase, 5, p.lat < 0), "\n") {
			fmt.Fprintf(out, "    %s\n", line)
		}
	}
	fmt.Fprintf(out, "  %s · %.0f%% lit · %.1f days old\n", m.Name, m.Illumination*100, m.AgeDays)
	fmt.Fprintf(out, "  Next full moon  %s\n", m.NextFull.In(loc).Format("Mon 2 Jan"))
	fmt.Fprintf(out, "  Next new moon   %s\n", m.NextNew.In(loc).Format("Mon 2 Jan"))
}
