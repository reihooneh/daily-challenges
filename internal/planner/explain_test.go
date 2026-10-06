package planner

import (
	"math/rand"
	"reflect"
	"testing"
)

func bigBudget() *Budget { return &Budget{Nodes: 50_000_000, PerSolve: 1_000_000} }

func selectionOf(p *Problem, items []Item) Selection {
	s := Selection{Courses: make([]bool, len(p.Courses)), Wishes: make([]bool, len(p.Wishes))}
	for _, item := range items {
		if item.IsCourse {
			s.Courses[item.Index] = true
		} else {
			s.Wishes[item.Index] = true
		}
	}
	return s
}

func TestConflictIsImpossibleAndMinimal(t *testing.T) {
	r := rand.New(rand.NewSource(7))
	checked := 0
	for trial := 0; trial < 4000 && checked < 600; trial++ {
		p := randomProblem(r)
		if found, _, _ := bruteForce(p, Everything(p)); found {
			continue
		}
		checked++
		explanation := Explain(p, bigBudget())
		if !explanation.Complete {
			t.Fatalf("trial %d: budget ran out on a tiny problem", trial)
		}
		if len(explanation.Conflict) == 0 {
			t.Fatalf("trial %d: empty conflict", trial)
		}
		// The conflict on its own must be impossible...
		if found, _, _ := bruteForce(p, selectionOf(p, explanation.Conflict)); found {
			t.Fatalf("trial %d: the reported conflict is actually satisfiable", trial)
		}
		// ...and removing any single member must make it possible.
		for skip := range explanation.Conflict {
			var rest []Item
			rest = append(rest, explanation.Conflict[:skip]...)
			rest = append(rest, explanation.Conflict[skip+1:]...)
			if found, _, _ := bruteForce(p, selectionOf(p, rest)); !found {
				t.Fatalf("trial %d: conflict is not minimal (member %d is not needed)", trial, skip)
			}
		}
	}
	if checked < 300 {
		t.Fatalf("only %d impossible problems were generated", checked)
	}
}

func TestWaysOutWorkAndAreSmallest(t *testing.T) {
	r := rand.New(rand.NewSource(11))
	checked := 0
	for trial := 0; trial < 4000 && checked < 400; trial++ {
		p := randomProblem(r)
		if found, _, _ := bruteForce(p, Everything(p)); found {
			continue
		}
		checked++
		explanation := Explain(p, bigBudget())
		for _, way := range explanation.WaysOut {
			selection := Everything(p)
			for _, item := range way.Drop {
				if item.IsCourse {
					selection.Courses[item.Index] = false
				} else {
					selection.Wishes[item.Index] = false
				}
			}
			if !way.Solution.Found || !valid(p, selection, way.Solution.Picks) {
				t.Fatalf("trial %d: a way out does not produce a valid timetable", trial)
			}
			_, days, idle := bruteForce(p, selection)
			if way.Solution.Days != days || way.Solution.IdleMinutes != idle {
				t.Fatalf("trial %d: the timetable shown for a way out is not the best one", trial)
			}
			// No smaller sacrifice would do: putting any one item back must break it again.
			for back := range way.Drop {
				smaller := selection.clone()
				if way.Drop[back].IsCourse {
					smaller.Courses[way.Drop[back].Index] = true
				} else {
					smaller.Wishes[way.Drop[back].Index] = true
				}
				if found, _, _ := bruteForce(p, smaller); found {
					t.Fatalf("trial %d: a way out gives up more than it needs to", trial)
				}
			}
		}
		// If dropping a single wish can fix it, that fix must be listed.
		for i := range p.Wishes {
			selection := Everything(p)
			selection.Wishes[i] = false
			if found, _, _ := bruteForce(p, selection); found {
				listed := false
				for _, way := range explanation.WaysOut {
					listed = listed || (len(way.Drop) == 1 && !way.Drop[0].IsCourse && way.Drop[0].Index == i)
				}
				if !listed && len(explanation.WaysOut) < maxWaysOut {
					t.Fatalf("trial %d: dropping wish %d works but was not offered", trial, i)
				}
			}
		}
	}
}

func TestTheFridayProblemIsPickTwo(t *testing.T) {
	response := Run(example(t, "the-friday-problem.txt"))
	if response.Status != StatusImpossible || !response.Complete {
		t.Fatalf("status=%s complete=%v", response.Status, response.Complete)
	}
	var dropped []string
	for _, way := range response.WaysOut {
		if len(way.Drop) != 1 {
			t.Fatalf("expected single-wish ways out, got %d items", len(way.Drop))
		}
		dropped = append(dropped, way.Drop[0].Text)
	}
	want := []string{"Nothing before 10:00", "No classes on Fri", "At most 3 days on campus"}
	if !reflect.DeepEqual(dropped, want) {
		t.Fatalf("ways out = %q, want %q", dropped, want)
	}
	wishes := 0
	for _, row := range response.Conflict {
		if row.Kind == "wish" {
			wishes++
		}
	}
	if wishes != 3 {
		t.Fatalf("all three wishes should be in the conflict, got %d", wishes)
	}
}

func TestCoursesThatClashOnTheirOwn(t *testing.T) {
	response := Run("AAA\n Lecture: Mon 10:00-12:00\nBBB\n Lecture: Mon 11:00-13:00\nCCC\n Lecture: Tue 09:00-10:00\nwish: no Fri\n")
	if response.Status != StatusImpossible {
		t.Fatalf("status=%s", response.Status)
	}
	if len(response.Conflict) != 2 || response.Conflict[0].Text != "AAA" || response.Conflict[1].Text != "BBB" {
		t.Fatalf("conflict = %+v", response.Conflict)
	}
	if len(response.WaysOut) != 2 || response.WaysOut[0].Drop[0].Kind != "course" {
		t.Fatalf("expected the two ways out to be dropping AAA or BBB, got %+v", response.WaysOut)
	}
}

func TestExamples(t *testing.T) {
	if r := Run(example(t, "first-year.txt")); r.Status != StatusOK || r.Plan.Days != 4 || !r.Plan.Optimal {
		t.Fatalf("first-year: %+v", r)
	}
	r := Run(example(t, "impossible-pair.txt"))
	if r.Status != StatusImpossible || len(r.Conflict) != 2 {
		t.Fatalf("impossible-pair: %+v", r)
	}
}

func TestBudgetRunningOutIsReportedHonestly(t *testing.T) {
	p := mustParse(t, example(t, "the-friday-problem.txt"))
	explanation := Explain(p, &Budget{Nodes: 30, PerSolve: 30})
	if explanation.Complete {
		t.Fatal("an explanation cut short must say so")
	}
	// Whatever it did manage to report must still be true.
	if found, _, _ := bruteForce(p, selectionOf(p, explanation.Conflict)); found {
		t.Fatal("a partial conflict must still be a real conflict")
	}
}

func TestCombinations(t *testing.T) {
	var got [][]int
	forEachCombination(4, 2, func(c []int) bool { got = append(got, append([]int(nil), c...)); return true })
	want := [][]int{{0, 1}, {0, 2}, {0, 3}, {1, 2}, {1, 3}, {2, 3}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %v", got)
	}
	if !containsAny([]int{1, 2, 5}, [][]int{{2, 5}}) || containsAny([]int{1, 2}, [][]int{{2, 5}}) {
		t.Fatal("containsAny is wrong")
	}
	if len(sortedItems([]Item{{Index: 2}, {IsCourse: true, Index: 1}})) != 2 {
		t.Fatal("unreachable")
	}
}
