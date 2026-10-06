package planner

import (
	"math/rand"
	"sort"
)

// An independent, deliberately simple implementation of the rules. The tests
// compare the real solver against this, so a mistake would have to be made
// twice, in two different styles, to go unnoticed.

func meetingsOf(p *Problem, picks []Pick) []Meeting {
	var all []Meeting
	for _, pick := range picks {
		all = append(all, p.Courses[pick.Course].Components[pick.Component].Options[pick.Option].Meetings...)
	}
	return all
}

// valid reports whether the picks obey every selected wish, checking minute by minute where that is simplest.
func valid(p *Problem, selection Selection, picks []Pick) bool {
	all := meetingsOf(p, picks)
	gap := 0
	for i, wish := range p.Wishes {
		if selection.Wishes[i] && wish.Kind == MinGap && wish.Minutes > gap {
			gap = wish.Minutes
		}
	}
	for i := range all {
		for j := i + 1; j < len(all); j++ {
			a, b := all[i], all[j]
			if a.Day == b.Day && a.Start < b.End+gap && b.Start < a.End+gap {
				return false
			}
		}
	}
	for i, wish := range p.Wishes {
		if !selection.Wishes[i] {
			continue
		}
		daysUsed := map[int]bool{}
		load := map[int]int{}
		for _, m := range all {
			daysUsed[m.Day] = true
			load[m.Day] += m.End - m.Start
		}
		switch wish.Kind {
		case NoDay:
			if daysUsed[wish.Day] {
				return false
			}
		case NotBefore:
			for _, m := range all {
				if m.Start < wish.Minutes {
					return false
				}
			}
		case NotAfter:
			for _, m := range all {
				if m.End > wish.Minutes {
					return false
				}
			}
		case Busy:
			for _, m := range all {
				if m.Day == wish.Day && m.Start < wish.End && wish.Start < m.End {
					return false
				}
			}
		case MaxDays:
			if len(daysUsed) > wish.Minutes {
				return false
			}
		case MaxDayLength:
			for _, minutes := range load {
				if minutes > wish.Minutes {
					return false
				}
			}
		case Lunch:
			for day := range daysUsed {
				busy := make([]bool, minutesPerDay+1)
				for _, m := range all {
					if m.Day == day {
						for t := m.Start; t < m.End; t++ {
							busy[t] = true
						}
					}
				}
				longest, run := 0, 0
				for t := wish.Start; t < wish.End; t++ {
					if busy[t] {
						run = 0
					} else {
						run++
						longest = max(longest, run)
					}
				}
				if longest < wish.Minutes {
					return false
				}
			}
		}
	}
	return true
}

// bruteForce tries every combination of options. Returns whether any is valid and the best (days, idle).
func bruteForce(p *Problem, selection Selection) (found bool, days, idle int) {
	type slot struct{ course, component, options int }
	var slots []slot
	for ci, course := range p.Courses {
		if !selection.Courses[ci] {
			continue
		}
		for ki, component := range course.Components {
			slots = append(slots, slot{ci, ki, len(component.Options)})
		}
	}
	picks := make([]Pick, len(slots))
	var walk func(depth int)
	walk = func(depth int) {
		if depth == len(slots) {
			if valid(p, selection, picks) {
				d, i := Measure(p, picks)
				if !found || d < days || (d == days && i < idle) {
					found, days, idle = true, d, i
				}
			}
			return
		}
		for option := 0; option < slots[depth].options; option++ {
			picks[depth] = Pick{Course: slots[depth].course, Component: slots[depth].component, Option: option}
			walk(depth + 1)
		}
	}
	walk(0)
	return found, days, idle
}

// randomProblem builds a small problem that is impossible roughly half the time.
func randomProblem(r *rand.Rand) *Problem {
	p := &Problem{}
	for c := 0; c < 2+r.Intn(3); c++ {
		course := Course{Code: string(rune('A' + c))}
		for k := 0; k < 1+r.Intn(2); k++ {
			component := Component{Name: "Part"}
			for o := 0; o < 1+r.Intn(3); o++ {
				var option Option
				for m := 0; m < 1+r.Intn(2); m++ {
					start := (8 + r.Intn(9)) * 60
					meeting := Meeting{Day: r.Intn(5), Start: start, End: start + 60*(1+r.Intn(3))}
					clash := false
					for _, other := range option.Meetings {
						clash = clash || (other.Day == meeting.Day && other.Start < meeting.End && meeting.Start < other.End)
					}
					if !clash {
						option.Meetings = append(option.Meetings, meeting)
					}
				}
				component.Options = append(component.Options, option)
			}
			course.Components = append(course.Components, component)
		}
		p.Courses = append(p.Courses, course)
	}
	pool := []Wish{
		{Kind: NoDay, Day: r.Intn(5)}, {Kind: NoDay, Day: r.Intn(5)},
		{Kind: NotBefore, Minutes: (9 + r.Intn(3)) * 60}, {Kind: NotAfter, Minutes: (15 + r.Intn(4)) * 60},
		{Kind: Lunch, Minutes: 30 + 15*r.Intn(3), Start: 12 * 60, End: 14 * 60},
		{Kind: MaxDays, Minutes: 2 + r.Intn(3)}, {Kind: MaxDayLength, Minutes: 60 * (3 + r.Intn(4))},
		{Kind: MinGap, Minutes: 15 * (1 + r.Intn(4))},
		{Kind: Busy, Day: r.Intn(5), Start: 13 * 60, End: 16 * 60},
	}
	r.Shuffle(len(pool), func(a, b int) { pool[a], pool[b] = pool[b], pool[a] })
	p.Wishes = pool[:r.Intn(6)]
	return p
}

func sortedItems(items []Item) []Item {
	out := append([]Item(nil), items...)
	sort.Slice(out, func(a, b int) bool {
		if out[a].IsCourse != out[b].IsCourse {
			return out[a].IsCourse
		}
		return out[a].Index < out[b].Index
	})
	return out
}
