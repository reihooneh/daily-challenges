package planner

import (
	"fmt"
	"sort"
)

// Work limits for one request. See SECURITY.md for how they were chosen.
const (
	MainSolveNodes   = 2_000_000
	ExplainNodes     = 6_000_000
	ExplainPerSolve  = 400_000
	StatusOK         = "ok"
	StatusImpossible = "impossible"
	StatusUnknown    = "unknown"
	StatusError      = "error"
)

// Response is what the command line and the web page both display.
type Response struct {
	Status   string        `json:"status"`
	Error    string        `json:"error,omitempty"`
	Courses  []CourseInfo  `json:"courses,omitempty"`
	Wishes   []string      `json:"wishes,omitempty"`
	Plan     *Plan         `json:"plan,omitempty"`
	Conflict []ConflictRow `json:"conflict,omitempty"`
	WaysOut  []Escape      `json:"waysOut,omitempty"`
	Complete bool          `json:"complete"`
	Nodes    int           `json:"nodes"`
}

// CourseInfo describes a course for display.
type CourseInfo struct {
	Code  string `json:"code"`
	Title string `json:"title"`
}

// Class is one block in a finished timetable.
type Class struct {
	Course    int    `json:"course"` // index into Response.Courses
	Component string `json:"component"`
	Option    int    `json:"option"` // 1-based, in the order the user listed them
	Day       int    `json:"day"`
	Start     int    `json:"start"`
	End       int    `json:"end"`
}

// Plan is a finished timetable.
type Plan struct {
	Classes     []Class `json:"classes"`
	Days        int     `json:"days"`
	IdleMinutes int     `json:"idleMinutes"`
	Optimal     bool    `json:"optimal"`
}

// ConflictRow is one member of the minimal conflict.
type ConflictRow struct {
	Kind   string `json:"kind"` // "course" or "wish"
	Index  int    `json:"index"`
	Text   string `json:"text"`
	Detail string `json:"detail,omitempty"`
}

// Escape is one way out of an impossible problem.
type Escape struct {
	Drop []ConflictRow `json:"drop"`
	Plan Plan          `json:"plan"`
}

// Run parses the text and produces the full answer. It never panics on bad
// input and never does more than a fixed amount of work.
func Run(text string) Response {
	problem, err := Parse(text)
	if err != nil {
		return Response{Status: StatusError, Error: err.Error(), Complete: true}
	}
	response := Response{Complete: true}
	for _, course := range problem.Courses {
		response.Courses = append(response.Courses, CourseInfo{Code: course.Code, Title: course.Title})
	}
	for _, wish := range problem.Wishes {
		response.Wishes = append(response.Wishes, wish.Describe())
	}

	solution := Solve(problem, Everything(problem), true, MainSolveNodes)
	response.Nodes = solution.Nodes
	if solution.Found {
		response.Status = StatusOK
		plan := buildPlan(problem, solution)
		response.Plan = &plan
		response.Complete = !solution.LimitHit
		return response
	}
	if !solution.Definite() {
		response.Status = StatusUnknown
		response.Complete = false
		response.Error = "this timetable is too large to search completely; try fewer options per class"
		return response
	}

	budget := &Budget{Nodes: ExplainNodes, PerSolve: ExplainPerSolve}
	explanation := Explain(problem, budget)
	response.Status = StatusImpossible
	response.Complete = explanation.Complete
	response.Nodes += ExplainNodes - budget.Nodes
	for _, item := range explanation.Conflict {
		response.Conflict = append(response.Conflict, describeItem(problem, item, true))
	}
	for _, way := range explanation.WaysOut {
		escape := Escape{Plan: buildPlan(problem, way.Solution)}
		for _, item := range way.Drop {
			escape.Drop = append(escape.Drop, describeItem(problem, item, false))
		}
		response.WaysOut = append(response.WaysOut, escape)
	}
	return response
}

func describeItem(p *Problem, item Item, withDetail bool) ConflictRow {
	if !item.IsCourse {
		return ConflictRow{Kind: "wish", Index: item.Index, Text: p.Wishes[item.Index].Describe()}
	}
	course := p.Courses[item.Index]
	row := ConflictRow{Kind: "course", Index: item.Index, Text: course.Code}
	if course.Title != "" {
		row.Text += " " + course.Title
	}
	if withDetail {
		row.Detail = tightestComponent(course)
	}
	return row
}

// tightestComponent describes the component with the fewest options, which
// is usually the one responsible for a clash.
func tightestComponent(course Course) string {
	tightest := course.Components[0]
	for _, component := range course.Components[1:] {
		if len(component.Options) < len(tightest.Options) {
			tightest = component
		}
	}
	if len(tightest.Options) > 3 {
		return ""
	}
	text := tightest.Name + " is only offered "
	for i, option := range tightest.Options {
		if i > 0 {
			text += " or "
		}
		for j, m := range option.Meetings {
			if j > 0 {
				text += " + "
			}
			text += fmt.Sprintf("%s %s-%s", DayNames[m.Day], Clock(m.Start), Clock(m.End))
		}
	}
	return text
}

func buildPlan(p *Problem, solution Solution) Plan {
	plan := Plan{Days: solution.Days, IdleMinutes: solution.IdleMinutes, Optimal: !solution.LimitHit, Classes: []Class{}}
	for _, pick := range solution.Picks {
		component := p.Courses[pick.Course].Components[pick.Component]
		for _, m := range component.Options[pick.Option].Meetings {
			plan.Classes = append(plan.Classes, Class{
				Course: pick.Course, Component: component.Name, Option: pick.Option + 1,
				Day: m.Day, Start: m.Start, End: m.End,
			})
		}
	}
	sort.SliceStable(plan.Classes, func(a, b int) bool {
		if plan.Classes[a].Day != plan.Classes[b].Day {
			return plan.Classes[a].Day < plan.Classes[b].Day
		}
		return plan.Classes[a].Start < plan.Classes[b].Start
	})
	return plan
}
