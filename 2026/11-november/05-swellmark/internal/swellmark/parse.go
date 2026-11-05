package swellmark

// The design file. Every line has a fixed shape and every number a range. Errors give the line
// number and what was expected, never the text of the line.

import (
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"
)

// Limits on the design file.
const (
	MaxInput   = 64 * 1024
	MaxLine    = 200
	MaxParts   = 100
	MaxJoints  = 300
	MaxSpecies = 50
)

// Kind is how a joint holds its two parts together.
type Kind int

const (
	// Rigid joints (glue, screws, pegs) can't slide: the wood itself has to take any mismatch.
	Rigid Kind = iota
	// Sliding joints (slots, buttons, figure-8 fasteners) allow a set travel each way.
	Sliding
	// Floating joints are a panel in a groove, with a gap to swell into and a depth to shrink from.
	Floating
)

// Part is one board of the piece. Axes are x, y and z of the piece; the board's thickness runs
// along the axis that is neither its grain nor its width.
type Part struct {
	Name    string
	Species Species
	Cut     Cut
	Grain   byte
	Width   byte
	Line    int
}

// Joint joins two parts over a length (mm) along one axis of the piece.
type Joint struct {
	A, B      *Part // for a floating joint, A is the panel and B the frame
	Fastening string
	Kind      Kind
	Allow     float64 // sliding: travel each way (mm); floating: total gap (mm)
	Depth     float64 // floating: groove depth on each side (mm)
	Axis      byte
	Extent    float64
	FromEnd   bool // fixed at one end instead of the middle
	Line      int
}

// Design is the whole piece and the climate it lives in.
type Design struct {
	Title      string
	Low, High  float64 // indoor relative humidity over the year (%)
	Built      float64 // relative humidity when it was made (%)
	TempC      float64
	RigidLimit float64 // mm a rigid joint can take before it's at risk
	Parts      []*Part
	Joints     []Joint
}

// InputError is a problem in the design file. Its message never repeats the input.
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

var (
	nameRe   = regexp.MustCompile(`^[a-z][a-z0-9-]{0,23}$`)
	numberRe = regexp.MustCompile(`^\d{1,4}(\.\d{1,5})?$`)
	titleRe  = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9 '.,&()!-]{0,59}$`)
)

type parser struct {
	line    int
	species map[string]Species
	parts   map[string]*Part
}

func (p *parser) fail(format string, args ...any) error {
	return &InputError{Line: p.line, Msg: fmt.Sprintf(format, args...)}
}

func (p *parser) number(s, what string, lo, hi float64) (float64, error) {
	if !numberRe.MatchString(s) {
		return 0, p.fail("%s must be a number like 3 or 0.5", what)
	}
	v, err := strconv.ParseFloat(s, 64)
	if err != nil || v < lo || v > hi {
		return 0, p.fail("%s must be from %g to %g", what, lo, hi)
	}
	return v, nil
}

func (p *parser) axis(s, what string) (byte, error) {
	if s != "x" && s != "y" && s != "z" {
		return 0, p.fail("%s must be x, y or z", what)
	}
	return s[0], nil
}

// hidden reports control characters and invisible formatting characters (zero-width spaces and
// joiners, bidirectional marks and overrides, the byte-order mark), which can disguise text.
func hidden(s string) bool {
	for _, r := range s {
		switch {
		case r < 0x20 && r != '\t', r == 0x7f, r >= 0x80 && r < 0xa0:
			return true
		case r >= 0x200b && r <= 0x200f, r >= 0x202a && r <= 0x202e, r >= 0x2060 && r <= 0x206f, r == 0xfeff:
			return true
		}
	}
	return false
}

// Parse reads a design file.
func Parse(text string) (*Design, error) {
	if len(text) > MaxInput {
		return nil, &InputError{Msg: "the design file is larger than 64 KB"}
	}
	if !utf8.ValidString(text) {
		return nil, &InputError{Msg: "the design file is not valid UTF-8 text"}
	}
	text = strings.TrimPrefix(text, "\ufeff")
	d := &Design{Title: "A piece of furniture", Low: -1, Built: -1, TempC: 20, RigidLimit: 0.35}
	p := &parser{species: map[string]Species{}, parts: map[string]*Part{}}
	for _, s := range builtinSpecies {
		p.species[s.Name] = s
	}
	added, seen := 0, map[string]bool{}
	for i, raw := range strings.Split(text, "\n") {
		p.line = i + 1
		raw = strings.TrimSuffix(raw, "\r")
		if len(raw) > MaxLine {
			return nil, p.fail("is longer than %d characters", MaxLine)
		}
		if hidden(raw) {
			return nil, p.fail("contains a control or invisible formatting character")
		}
		line, _, _ := strings.Cut(raw, "#")
		w := strings.Fields(line)
		if len(w) == 0 {
			continue
		}
		head := w[0]
		if head != "species" && head != "part" && head != "joint" {
			if seen[head] {
				return nil, p.fail("'%s' may only appear once", safeWord(head))
			}
			seen[head] = true
		}
		var err error
		switch {
		case head == "design":
			title := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(line), "design"))
			if !titleRe.MatchString(title) {
				return nil, p.fail("the design's name: letters, digits, spaces and ' . , & ( ) ! - (up to 60)")
			}
			d.Title = title
		case head == "climate" && len(w) == 4 && w[2] == "to":
			if d.Low, err = p.number(w[1], "the lowest humidity", 5, 95); err != nil {
				return nil, err
			}
			if d.High, err = p.number(w[3], "the highest humidity", 5, 95); err != nil {
				return nil, err
			}
			if d.High <= d.Low {
				return nil, p.fail("the highest humidity must be above the lowest")
			}
		case head == "built-at" && len(w) == 2:
			d.Built, err = p.number(w[1], "the humidity when it was built", 5, 95)
		case head == "temperature" && len(w) == 2:
			d.TempC, err = p.number(w[1], "the temperature", 0, 40)
		case head == "rigid-limit" && len(w) == 2:
			d.RigidLimit, err = p.number(w[1], "the rigid joint limit", 0.05, 5)
		case head == "species" && len(w) == 6 && w[2] == "radial" && w[4] == "tangential":
			err = p.addSpecies(w)
			added++
			if added > MaxSpecies {
				return nil, p.fail("at most %d species lines", MaxSpecies)
			}
		case head == "part" && len(w) == 8 && w[4] == "grain" && w[6] == "width":
			var part *Part
			if part, err = p.addPart(w); err == nil {
				if len(d.Parts) >= MaxParts {
					return nil, p.fail("at most %d parts", MaxParts)
				}
				d.Parts = append(d.Parts, part)
			}
		case head == "joint":
			var j Joint
			if j, err = p.joint(w); err == nil {
				if len(d.Joints) >= MaxJoints {
					return nil, p.fail("at most %d joints", MaxJoints)
				}
				d.Joints = append(d.Joints, j)
			}
		default:
			return nil, p.fail("lines are design, climate, built-at, temperature, rigid-limit, species, part or joint (see the README)")
		}
		if err != nil {
			return nil, err
		}
	}
	p.line = 0
	switch {
	case d.Low < 0:
		return nil, p.fail("say the indoor humidity over the year, like 'climate 30 to 65'")
	case d.Built < 0:
		return nil, p.fail("say the humidity when it was built, like 'built-at 45'")
	case len(d.Joints) == 0:
		return nil, p.fail("the design has no joints")
	}
	return d, nil
}

// safeWord is only ever called on a word that has passed the hidden-character check, and is
// shortened so an error line stays short. Only known keywords reach it in practice.
func safeWord(s string) string {
	if !nameRe.MatchString(s) {
		return "that keyword"
	}
	return s
}

func (p *parser) addSpecies(w []string) error {
	if !nameRe.MatchString(w[1]) {
		return p.fail("a species name is lower-case letters, digits and -, up to 24")
	}
	r, err := p.number(w[3], "the radial coefficient", 0.0001, 0.01)
	if err != nil {
		return err
	}
	t, err := p.number(w[5], "the tangential coefficient", 0.0001, 0.01)
	if err != nil {
		return err
	}
	if _, used := p.speciesUsed(w[1]); used {
		return p.fail("define a species before the parts made from it")
	}
	p.species[w[1]] = Species{Name: w[1], Radial: r, Tangential: t}
	return nil
}

func (p *parser) speciesUsed(name string) (*Part, bool) {
	for _, part := range p.parts {
		if part.Species.Name == name {
			return part, true
		}
	}
	return nil, false
}

// part NAME SPECIES CUT grain AXIS width AXIS
func (p *parser) addPart(w []string) (*Part, error) {
	if !nameRe.MatchString(w[1]) {
		return nil, p.fail("a part name is lower-case letters, digits and -, up to 24, starting with a letter")
	}
	if _, dup := p.parts[w[1]]; dup {
		return nil, p.fail("each part name must be different")
	}
	sp, ok := p.species[w[2]]
	if !ok {
		return nil, p.fail("unknown species (built in: ash, beech, birch, cherry, douglas-fir, maple, pine, poplar, red-oak, teak, walnut, white-oak; or add one with a species line)")
	}
	cut, ok := cutNames[w[3]]
	if !ok {
		return nil, p.fail("the cut is flat, quarter or rift")
	}
	grain, err := p.axis(w[5], "the grain direction")
	if err != nil {
		return nil, err
	}
	width, err := p.axis(w[7], "the width direction")
	if err != nil {
		return nil, err
	}
	if grain == width {
		return nil, p.fail("a board's grain and width run in different directions")
	}
	part := &Part{Name: w[1], Species: sp, Cut: cut, Grain: grain, Width: width, Line: p.line}
	p.parts[w[1]] = part
	return part, nil
}

// joint A B FASTENING [MM | GAP depth DEPTH] along AXIS LENGTH [from-end]
func (p *parser) joint(w []string) (Joint, error) {
	var j Joint
	j.Line = p.line
	if len(w) < 7 {
		return j, p.fail("a joint is like 'joint top apron buttons 3 along y 450'")
	}
	a, okA := p.parts[w[1]]
	b, okB := p.parts[w[2]]
	if !okA || !okB {
		return j, p.fail("a joint joins two parts named on earlier part lines")
	}
	if a == b {
		return j, p.fail("a joint joins two different parts")
	}
	j.A, j.B, j.Fastening = a, b, w[3]
	rest := w[4:]
	var err error
	switch w[3] {
	case "glue", "screws", "pegs", "nails":
		j.Kind = Rigid
	case "slots", "buttons", "figure8":
		j.Kind = Sliding
		if j.Allow, err = p.number(rest[0], "the travel each way", 0, 50); err != nil {
			return j, err
		}
		rest = rest[1:]
	case "floating":
		j.Kind = Floating
		if len(rest) < 3 || rest[1] != "depth" {
			return j, p.fail("a floating panel is like 'joint panel frame floating 4 depth 10 along x 300'")
		}
		if j.Allow, err = p.number(rest[0], "the gap", 0, 50); err != nil {
			return j, err
		}
		if j.Depth, err = p.number(rest[2], "the groove depth", 1, 100); err != nil {
			return j, err
		}
		if j.Depth <= j.Allow/2 {
			return j, p.fail("the groove must be deeper than half the gap, or the panel isn't held")
		}
		rest = rest[3:]
	default:
		return j, p.fail("fastenings are glue, screws, pegs, nails, slots, buttons, figure8 or floating")
	}
	if len(rest) < 3 || len(rest) > 4 || rest[0] != "along" {
		return j, p.fail("then say the direction and length the joint runs, like 'along y 450'")
	}
	if j.Axis, err = p.axis(rest[1], "the joint's direction"); err != nil {
		return j, err
	}
	if j.Extent, err = p.number(rest[2], "the joint's length", 1, 5000); err != nil {
		return j, err
	}
	if len(rest) == 4 {
		if rest[3] != "from-end" || j.Kind == Floating {
			return j, p.fail("the only word after the length is from-end (not for floating panels)")
		}
		j.FromEnd = true
	}
	return j, nil
}
