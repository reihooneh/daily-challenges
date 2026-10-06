// Package planner turns a list of courses and wishes into a clash-free
// timetable, or explains exactly why no such timetable exists.
package planner

import "fmt"

// Limits on everything a user can supply. The solver's work is bounded by
// these numbers, so no input can make it run away.
const (
	MaxInputBytes      = 64 * 1024
	MaxLines           = 2000
	MaxLineLength      = 1000
	MaxCourses         = 12
	MaxComponents      = 6
	MaxOptions         = 30
	MaxMeetings        = 6
	MaxWishes          = 24
	MaxTitleLength     = 60
	minutesPerDay      = 24 * 60
	daysPerWeek        = 7
	maxComponentLength = 20
)

// DayNames are indexed by Meeting.Day.
var DayNames = [daysPerWeek]string{"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}

// Meeting is one block of time in the week. Start and End are minutes after midnight.
type Meeting struct {
	Day   int
	Start int
	End   int
}

// Option is one way of attending a component: for example the Monday stream
// of a lecture. Choosing an option means attending all of its meetings.
type Option struct {
	Meetings []Meeting
}

// Component is a part of a course that must be attended, such as "Lecture" or
// "Lab". Exactly one of its options has to be chosen.
type Component struct {
	Name    string
	Options []Option
}

// Course is something the student has to take.
type Course struct {
	Code       string
	Title      string
	Components []Component
}

// WishKind identifies a type of preference.
type WishKind int

const (
	NoDay        WishKind = iota // no classes on Day
	NotBefore                    // nothing starts before Minutes
	NotAfter                     // nothing ends after Minutes
	Lunch                        // Minutes free between Start and End on every day with classes
	MaxDays                      // at most Minutes days with classes
	MaxDayLength                 // at most Minutes of class per day
	MinGap                       // at least Minutes between two classes
	Busy                         // unavailable on Day from Start to End
)

// Wish is one preference. Which fields matter depends on Kind.
type Wish struct {
	Kind    WishKind
	Day     int
	Minutes int
	Start   int
	End     int
	Label   string // only for Busy: what the time is for
}

// Problem is everything the solver needs.
type Problem struct {
	Courses []Course
	Wishes  []Wish
}

// Clock formats minutes after midnight as 09:30.
func Clock(minutes int) string {
	return fmt.Sprintf("%02d:%02d", minutes/60, minutes%60)
}

// Describe returns the wish as a plain sentence. It is built entirely from
// validated values, so it is always safe to display.
func (w Wish) Describe() string {
	switch w.Kind {
	case NoDay:
		return "No classes on " + DayNames[w.Day]
	case NotBefore:
		return "Nothing before " + Clock(w.Minutes)
	case NotAfter:
		return "Nothing after " + Clock(w.Minutes)
	case Lunch:
		return fmt.Sprintf("A %d-minute break between %s and %s", w.Minutes, Clock(w.Start), Clock(w.End))
	case MaxDays:
		if w.Minutes == 1 {
			return "At most 1 day on campus"
		}
		return fmt.Sprintf("At most %d days on campus", w.Minutes)
	case MaxDayLength:
		return "At most " + duration(w.Minutes) + " of class per day"
	case MinGap:
		return fmt.Sprintf("At least %d minutes between classes", w.Minutes)
	case Busy:
		text := fmt.Sprintf("Busy %s %s-%s", DayNames[w.Day], Clock(w.Start), Clock(w.End))
		if w.Label != "" {
			text += " (" + w.Label + ")"
		}
		return text
	}
	return "Unknown wish"
}

func duration(minutes int) string {
	switch {
	case minutes == 0:
		return "no time"
	case minutes%60 == 0 && minutes == 60:
		return "1 hour"
	case minutes%60 == 0:
		return fmt.Sprintf("%d hours", minutes/60)
	case minutes < 60:
		return fmt.Sprintf("%d minutes", minutes)
	default:
		return fmt.Sprintf("%dh %02dm", minutes/60, minutes%60)
	}
}
