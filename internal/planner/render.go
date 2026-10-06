package planner

import (
	"fmt"
	"strings"
)

// RenderText formats a response for a terminal. Every string it prints was
// either written here or passed the parser's allow-lists.
func RenderText(r Response) string {
	var out strings.Builder
	switch r.Status {
	case StatusError, StatusUnknown:
		fmt.Fprintf(&out, "Could not plan: %s\n", r.Error)
	case StatusOK:
		fmt.Fprintf(&out, "A timetable exists: everything fits.\n\n")
		writePlan(&out, r, *r.Plan, "")
	case StatusImpossible:
		fmt.Fprintf(&out, "No timetable can satisfy everything.\n\nWhy: these cannot all be true at once.\n")
		for _, row := range r.Conflict {
			fmt.Fprintf(&out, "  - %s\n", row.Text)
			if row.Detail != "" {
				fmt.Fprintf(&out, "      %s\n", row.Detail)
			}
		}
		fmt.Fprintf(&out, "  Each one matters: without any single one of them, the rest fit together.\n")
		if len(r.WaysOut) == 0 {
			fmt.Fprintf(&out, "\nNo small change fixes this. Try different class options or fewer courses.\n")
		} else {
			fmt.Fprintf(&out, "\nWays out (smallest sacrifices first):\n")
		}
		for i, way := range r.WaysOut {
			var names []string
			for _, row := range way.Drop {
				names = append(names, row.Text)
			}
			verb := "Give up"
			if way.Drop[0].Kind == "course" {
				verb = "Drop the course"
			}
			fmt.Fprintf(&out, "\n  %d. %s: %s\n", i+1, verb, strings.Join(names, " + "))
			writePlan(&out, r, way.Plan, "     ")
		}
		if !r.Complete {
			fmt.Fprintf(&out, "\nNote: the search budget ran out, so there may be other ways out not listed here.\n")
		}
	}
	return out.String()
}

func writePlan(out *strings.Builder, r Response, plan Plan, indent string) {
	day := -1
	for _, class := range plan.Classes {
		if class.Day != day {
			day = class.Day
			fmt.Fprintf(out, "%s%s\n", indent, DayNames[day])
		}
		fmt.Fprintf(out, "%s  %s-%s  %-10s %s\n", indent, Clock(class.Start), Clock(class.End),
			r.Courses[class.Course].Code, class.Component)
	}
	days := "days"
	if plan.Days == 1 {
		days = "day"
	}
	fmt.Fprintf(out, "%s%d %s on campus, %s", indent, plan.Days, days, Waiting(plan.IdleMinutes))
	if !plan.Optimal {
		fmt.Fprintf(out, " (a good timetable, but the search stopped before proving it is the best)")
	}
	fmt.Fprintf(out, "\n")
}

// Waiting describes the idle time in a timetable.
func Waiting(minutes int) string {
	if minutes == 0 {
		return "no waiting between classes"
	}
	return duration(minutes) + " waiting between classes"
}
