package planner

// The solver: depth-first search with pruning (branch and bound).
//
// Each component of each course is a variable, and its options are the
// values. The search picks an option for one component at a time and gives up
// on a branch as soon as it breaks a rule. Every rule here has the property
// that adding more classes can never repair it, which is what makes early
// pruning correct.

import "sort"

// Selection says which courses and wishes take part in a solve. Explanations
// work by solving the same problem many times with different selections.
type Selection struct {
	Courses []bool
	Wishes  []bool
}

// Everything returns a selection with every course and wish switched on.
func Everything(p *Problem) Selection {
	s := Selection{Courses: make([]bool, len(p.Courses)), Wishes: make([]bool, len(p.Wishes))}
	for i := range s.Courses {
		s.Courses[i] = true
	}
	for i := range s.Wishes {
		s.Wishes[i] = true
	}
	return s
}

func (s Selection) clone() Selection {
	return Selection{Courses: append([]bool(nil), s.Courses...), Wishes: append([]bool(nil), s.Wishes...)}
}

// Pick is the chosen option for one component.
type Pick struct {
	Course    int
	Component int
	Option    int
}

// Solution is the outcome of one solve.
type Solution struct {
	Found       bool
	Picks       []Pick
	Days        int // days with at least one class
	IdleMinutes int // waiting time between classes, summed over the week
	Nodes       int // search steps taken
	LimitHit    bool
}

// Definite reports whether the answer can be trusted: either a timetable was
// found, or the whole search space was covered without finding one.
func (s Solution) Definite() bool {
	return s.Found || !s.LimitHit
}

type variable struct {
	course    int
	component int
	options   []candidate
}

type candidate struct {
	index    int
	meetings []Meeting
}

type rules struct {
	minGap       int
	maxDays      int
	maxDayLength int
	lunches      []Wish
}

type search struct {
	variables []variable
	rules     rules
	optimise  bool
	limit     int

	nodes    int
	limitHit bool
	perDay   [daysPerWeek][]Meeting
	dayLoad  [daysPerWeek]int
	days     int
	current  []int
	best     []int
	bestCost int
	found    bool
}

// Solve looks for the best timetable: fewest days on campus first, then the
// least waiting between classes. With optimise false it stops at the first
// valid timetable, which is all an explanation needs.
func Solve(p *Problem, selection Selection, optimise bool, nodeLimit int) Solution {
	s := &search{optimise: optimise, limit: nodeLimit, rules: rules{maxDays: daysPerWeek, maxDayLength: minutesPerDay}}
	var filters []Wish
	for i, wish := range p.Wishes {
		if !selection.Wishes[i] {
			continue
		}
		switch wish.Kind {
		case NoDay, NotBefore, NotAfter, Busy:
			filters = append(filters, wish)
		case Lunch:
			s.rules.lunches = append(s.rules.lunches, wish)
		case MaxDays:
			s.rules.maxDays = min(s.rules.maxDays, wish.Minutes)
		case MaxDayLength:
			s.rules.maxDayLength = min(s.rules.maxDayLength, wish.Minutes)
		case MinGap:
			s.rules.minGap = max(s.rules.minGap, wish.Minutes)
		}
	}

	for ci, course := range p.Courses {
		if !selection.Courses[ci] {
			continue
		}
		for ki, component := range course.Components {
			v := variable{course: ci, component: ki}
			for oi, option := range component.Options {
				if allowed(option, filters) {
					v.options = append(v.options, candidate{index: oi, meetings: option.Meetings})
				}
			}
			if len(v.options) == 0 {
				return Solution{} // a component with nothing left: impossible, and certain
			}
			s.variables = append(s.variables, v)
		}
	}
	// Most constrained first: components with few options are decided early,
	// so dead ends are discovered near the top of the search tree.
	sort.SliceStable(s.variables, func(a, b int) bool {
		return len(s.variables[a].options) < len(s.variables[b].options)
	})

	s.current = make([]int, len(s.variables))
	s.descend(0)

	solution := Solution{Found: s.found, Nodes: s.nodes, LimitHit: s.limitHit}
	if s.found {
		for i, v := range s.variables {
			solution.Picks = append(solution.Picks, Pick{Course: v.course, Component: v.component, Option: v.options[s.best[i]].index})
		}
		sort.Slice(solution.Picks, func(a, b int) bool {
			if solution.Picks[a].Course != solution.Picks[b].Course {
				return solution.Picks[a].Course < solution.Picks[b].Course
			}
			return solution.Picks[a].Component < solution.Picks[b].Component
		})
		solution.Days, solution.IdleMinutes = Measure(p, solution.Picks)
	}
	return solution
}

// allowed applies the wishes that rule out an option on its own.
func allowed(option Option, filters []Wish) bool {
	for _, m := range option.Meetings {
		for _, wish := range filters {
			switch wish.Kind {
			case NoDay:
				if m.Day == wish.Day {
					return false
				}
			case NotBefore:
				if m.Start < wish.Minutes {
					return false
				}
			case NotAfter:
				if m.End > wish.Minutes {
					return false
				}
			case Busy:
				if m.Day == wish.Day && m.Start < wish.End && wish.Start < m.End {
					return false
				}
			}
		}
	}
	return true
}

func (s *search) descend(depth int) {
	if depth == len(s.variables) {
		cost := s.cost()
		if !s.found || cost < s.bestCost {
			s.found = true
			s.bestCost = cost
			s.best = append(s.best[:0], s.current...)
		}
		return
	}
	for i, option := range s.variables[depth].options {
		if s.limitHit || (s.found && !s.optimise) {
			return
		}
		s.nodes++
		if s.nodes > s.limit {
			s.limitHit = true
			return
		}
		placed, ok := s.place(option.meetings)
		// Bound: days can only go up from here and waiting time is never
		// negative, so if the days alone already cost as much as the best
		// timetable so far, this branch cannot win.
		if ok && (!s.found || s.days*costPerDay < s.bestCost) {
			s.current[depth] = i
			s.descend(depth + 1)
		}
		s.remove(option.meetings[:placed])
	}
}

const costPerDay = 100_000 // larger than any possible weekly waiting time

// place adds meetings one by one. It returns how many were added (the caller
// must remove exactly those) and whether all of them fit the rules.
func (s *search) place(meetings []Meeting) (added int, ok bool) {
	for i, m := range meetings {
		for _, other := range s.perDay[m.Day] {
			if m.Start < other.End+s.rules.minGap && other.Start < m.End+s.rules.minGap {
				return i, false
			}
		}
		if len(s.perDay[m.Day]) == 0 && s.days+1 > s.rules.maxDays {
			return i, false
		}
		if s.dayLoad[m.Day]+m.End-m.Start > s.rules.maxDayLength {
			return i, false
		}
		if len(s.perDay[m.Day]) == 0 {
			s.days++
		}
		s.perDay[m.Day] = append(s.perDay[m.Day], m)
		s.dayLoad[m.Day] += m.End - m.Start
		if !s.lunchOK(m.Day) {
			return i + 1, false
		}
	}
	return len(meetings), true
}

func (s *search) remove(meetings []Meeting) {
	for i := len(meetings) - 1; i >= 0; i-- {
		m := meetings[i]
		s.perDay[m.Day] = s.perDay[m.Day][:len(s.perDay[m.Day])-1]
		s.dayLoad[m.Day] -= m.End - m.Start
		if len(s.perDay[m.Day]) == 0 {
			s.days--
		}
	}
}

// lunchOK checks that every lunch wish still has a long enough free stretch
// inside its window on the given day.
func (s *search) lunchOK(day int) bool {
	for _, wish := range s.rules.lunches {
		if !hasFreeStretch(s.perDay[day], wish.Start, wish.End, wish.Minutes) {
			return false
		}
	}
	return true
}

func hasFreeStretch(meetings []Meeting, windowStart, windowEnd, needed int) bool {
	sorted := append([]Meeting(nil), meetings...)
	sort.Slice(sorted, func(a, b int) bool { return sorted[a].Start < sorted[b].Start })
	free := windowStart
	for _, m := range sorted {
		if m.End <= free {
			continue
		}
		if m.Start >= windowEnd {
			break
		}
		if m.Start-free >= needed {
			return true
		}
		free = max(free, m.End)
	}
	return windowEnd-free >= needed
}

func (s *search) cost() int {
	idle := 0
	for day := range s.perDay {
		idle += idleMinutes(s.perDay[day], s.dayLoad[day])
	}
	return s.days*costPerDay + idle
}

func idleMinutes(meetings []Meeting, load int) int {
	if len(meetings) == 0 {
		return 0
	}
	first, last := meetings[0].Start, meetings[0].End
	for _, m := range meetings[1:] {
		first = min(first, m.Start)
		last = max(last, m.End)
	}
	return last - first - load
}

// Measure reports the days on campus and total waiting time of a set of picks.
func Measure(p *Problem, picks []Pick) (days, idle int) {
	var perDay [daysPerWeek][]Meeting
	var load [daysPerWeek]int
	for _, pick := range picks {
		for _, m := range p.Courses[pick.Course].Components[pick.Component].Options[pick.Option].Meetings {
			perDay[m.Day] = append(perDay[m.Day], m)
			load[m.Day] += m.End - m.Start
		}
	}
	for day := range perDay {
		if len(perDay[day]) > 0 {
			days++
		}
		idle += idleMinutes(perDay[day], load[day])
	}
	return days, idle
}
