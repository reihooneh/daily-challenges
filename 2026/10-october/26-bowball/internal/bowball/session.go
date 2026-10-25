// Package bowball reads a seat-racing session, estimates each rower's speed from the results,
// and works out who makes the boat and which swap to race next.
package bowball

import "fmt"

// Side is the side of the boat a rower's oar is on. Scullers (and rowers happy either way) are Either.
type Side int

const (
	Either Side = iota
	Bow
	Stroke
)

func (s Side) String() string {
	switch s {
	case Bow:
		return "bow"
	case Stroke:
		return "stroke"
	}
	return "either"
}

// CanSwap reports whether two rowers can trade seats: same side, or one of them rows either side.
func CanSwap(a, b Side) bool { return a == Either || b == Either || a == b }

type Rower struct {
	Name string
	Side Side
	Line int
}

type Boat struct {
	Hull string  // the boat's name: the same name in two pieces is the same hull
	Time float64 // seconds; only differences within a piece matter
	Crew []int   // indexes into Session.Rowers
	Line int
}

type Piece struct {
	Distance float64 // metres
	Boats    []Boat
	Line     int
}

type Session struct {
	Name   string
	Seats  int     // how many rowers make the boat
	Sweep  bool    // some rowers have a side: half the seats are bow side, half stroke side
	Noise  float64 // typical timing noise per crew, seconds per 1000 m (a starting guess)
	Rowers []Rower
	Hulls  []string
	Pieces []Piece
}

// InputError is a problem in the file. Its message never repeats the input.
type InputError struct {
	Line int
	Msg  string
}

func (e *InputError) Error() string {
	if e.Line > 0 {
		return fmt.Sprintf("line %d: %s", e.Line, e.Msg)
	}
	return e.Msg
}
