package planner

// Explanations: when no timetable exists, work out why, and what to give up.
//
// Both answers come from re-running the solver on smaller versions of the
// problem. Nothing here knows anything about timetables; it only asks
// "is it possible if I leave these out?".

import "sort"

// Item names one course or one wish.
type Item struct {
	IsCourse bool
	Index    int
}

// WayOut is a smallest set of things to give up that makes a timetable possible.
type WayOut struct {
	Drop     []Item
	Solution Solution
}

// Explanation is the result of analysing an impossible problem.
type Explanation struct {
	// Conflict is a minimal set of courses and wishes that cannot all hold.
	// Minimal means every member matters: without any one of them, the rest fit.
	Conflict []Item
	WaysOut  []WayOut
	// Complete is false if the work budget ran out, in which case the lists
	// are still correct but may be missing entries or be larger than needed.
	Complete bool
}

const (
	maxDropSize = 3
	maxWaysOut  = 6
)

// Budget caps the total work an explanation may do.
type Budget struct {
	Nodes    int // search steps remaining across all solves
	PerSolve int // search steps allowed for a single solve
}

func (b *Budget) solve(p *Problem, selection Selection, optimise bool) Solution {
	limit := min(b.PerSolve, b.Nodes)
	if limit <= 0 {
		return Solution{LimitHit: true}
	}
	solution := Solve(p, selection, optimise, limit)
	b.Nodes -= solution.Nodes
	return solution
}

// Explain analyses a problem that is known to have no timetable.
func Explain(p *Problem, budget *Budget) Explanation {
	explanation := Explanation{Complete: true}
	explanation.Conflict = minimalConflict(p, budget, &explanation.Complete)
	explanation.WaysOut = waysOut(p, budget, &explanation.Complete)
	return explanation
}

// minimalConflict uses the "deletion" method. Start with everything, which is
// known to be impossible. Take one thing away: if what is left is still
// impossible, that thing was not needed for the clash, so leave it out for
// good. Otherwise put it back. What survives is a minimal conflict.
func minimalConflict(p *Problem, budget *Budget, complete *bool) []Item {
	selection := Everything(p)
	try := func(flags []bool, index int) {
		flags[index] = false
		result := budget.solve(p, selection, false)
		if result.Found || !result.Definite() {
			flags[index] = true // needed for the clash (or unsure: keep it to stay correct)
		}
		if !result.Definite() {
			*complete = false
		}
	}
	for i := range selection.Courses {
		try(selection.Courses, i)
	}
	for i := range selection.Wishes {
		try(selection.Wishes, i)
	}

	var conflict []Item
	for i, kept := range selection.Courses {
		if kept {
			conflict = append(conflict, Item{IsCourse: true, Index: i})
		}
	}
	for i, kept := range selection.Wishes {
		if kept {
			conflict = append(conflict, Item{Index: i})
		}
	}
	return conflict
}

// waysOut looks for the smallest sets of wishes to drop. It tries every
// single wish, then every pair, then every triple, skipping any set that
// contains a smaller answer already found. If no wishes can save the
// timetable, it reports which single course could be dropped instead.
func waysOut(p *Problem, budget *Budget, complete *bool) []WayOut {
	var found [][]int
	for size := 1; size <= maxDropSize && size <= len(p.Wishes); size++ {
		forEachCombination(len(p.Wishes), size, func(combo []int) bool {
			if len(found) >= maxWaysOut {
				return false
			}
			if containsAny(combo, found) {
				return true
			}
			selection := Everything(p)
			for _, index := range combo {
				selection.Wishes[index] = false
			}
			result := budget.solve(p, selection, false)
			if !result.Definite() {
				*complete = false
				return budget.Nodes > 0
			}
			if result.Found {
				found = append(found, append([]int(nil), combo...))
			}
			return true
		})
	}

	var ways []WayOut
	for _, combo := range found {
		selection := Everything(p)
		way := WayOut{}
		for _, index := range combo {
			selection.Wishes[index] = false
			way.Drop = append(way.Drop, Item{Index: index})
		}
		way.Solution = budget.solve(p, selection, true)
		if way.Solution.Found {
			ways = append(ways, way)
		} else {
			*complete = false
		}
	}

	if len(ways) == 0 && len(p.Courses) > 1 {
		for i := range p.Courses {
			selection := Everything(p)
			selection.Courses[i] = false
			if result := budget.solve(p, selection, true); result.Found {
				ways = append(ways, WayOut{Drop: []Item{{IsCourse: true, Index: i}}, Solution: result})
			} else if !result.Definite() {
				*complete = false
			}
		}
	}

	sort.SliceStable(ways, func(a, b int) bool {
		if len(ways[a].Drop) != len(ways[b].Drop) {
			return len(ways[a].Drop) < len(ways[b].Drop)
		}
		if ways[a].Solution.Days != ways[b].Solution.Days {
			return ways[a].Solution.Days < ways[b].Solution.Days
		}
		return ways[a].Solution.IdleMinutes < ways[b].Solution.IdleMinutes
	})
	return ways
}

// forEachCombination calls visit with every way of choosing k indexes out of
// n, in order. It stops early if visit returns false.
func forEachCombination(n, k int, visit func([]int) bool) {
	combo := make([]int, k)
	var build func(start, depth int) bool
	build = func(start, depth int) bool {
		if depth == k {
			return visit(combo)
		}
		for i := start; i <= n-(k-depth); i++ {
			combo[depth] = i
			if !build(i+1, depth+1) {
				return false
			}
		}
		return true
	}
	build(0, 0)
}

// containsAny reports whether combo includes every member of one of the sets.
func containsAny(combo []int, sets [][]int) bool {
	for _, set := range sets {
		matched := 0
		for _, wanted := range set {
			for _, have := range combo {
				if have == wanted {
					matched++
					break
				}
			}
		}
		if matched == len(set) {
			return true
		}
	}
	return false
}
