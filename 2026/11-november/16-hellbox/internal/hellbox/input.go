// Package hellbox plans a letterpress job around the type a printer actually owns.
//
// A case of type holds a fixed number of each letter (each "sort"). Setting a page uses them
// up; when a letter runs out, printers either substitute (a turned n for a u, two Vs for a W),
// print the job in several goes ("formes"), distributing the type back into the case between
// them, or buy more. Hellbox does all three as well as it can.
package hellbox

import (
	"bufio"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"
)

// Limits on what Hellbox will read.
const (
	MaxFileBytes = 256 * 1024
	MaxPages     = 200
	MaxGlyphs    = 400
	MaxCount     = 100000
	MaxSubs      = 200
)

// A Glyph is what one sort prints: a single character, or a ligature such as "fi".
type Glyph string

// Ligatures Hellbox knows how to use, longest first.
var Ligatures = []Glyph{"ffi", "ffl", "ff", "fi", "fl"}

// A Case is the type a printer owns: how many sorts of each glyph.
type Case struct {
	Name  string
	Count map[Glyph]int
}

// A Page is one page (or one block) of the job, with what it needs.
type Page struct {
	Title string
	Need  map[Glyph]int // single characters, counting every letter
	Ligs  map[Glyph]int // places a ligature could replace its letters (non-overlapping, longest first)
}

// A Sub lets one glyph be set with other sorts, at a cost in looks.
type Sub struct {
	For  Glyph
	Use  []Glyph // sorts consumed for one occurrence (VV for W uses V twice)
	Cost int
	Note string
}

// InputError is a problem with an input file, with its line. Messages never repeat the input.
type InputError struct {
	File string
	Line int
	Msg  string
}

func (e *InputError) Error() string {
	if e.Line > 0 {
		return fmt.Sprintf("%s, line %d: %s", e.File, e.Line, e.Msg)
	}
	return fmt.Sprintf("%s: %s", e.File, e.Msg)
}

func checkText(file, text string) error {
	if len(text) > MaxFileBytes {
		return &InputError{file, 0, "larger than 256 KB"}
	}
	if !utf8.ValidString(text) {
		return &InputError{file, 0, "not valid UTF-8 text"}
	}
	if strings.ContainsRune(text, 0) {
		return &InputError{file, 0, "not a text file"}
	}
	return nil
}

// printable reports whether a glyph is something a sort could print.
func printable(g string) bool {
	if g == "" || utf8.RuneCountInString(g) > 3 {
		return false
	}
	for _, r := range g {
		if !unicode.IsPrint(r) || unicode.IsSpace(r) {
			return false
		}
	}
	return true
}

// ParseCase reads a case: "name <words>" once, then one "<glyph> <count>" per line.
// Lines starting with "//" are comments (so "#" can be a glyph).
func ParseCase(file, text string) (*Case, error) {
	if err := checkText(file, text); err != nil {
		return nil, err
	}
	c := &Case{Name: "type case", Count: map[Glyph]int{}}
	sc := bufio.NewScanner(strings.NewReader(text))
	sc.Buffer(make([]byte, 4096), 4096)
	n := 0
	for sc.Scan() {
		n++
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "//") {
			continue
		}
		f := strings.Fields(line)
		if f[0] == "name" {
			c.Name = cleanName(strings.Join(f[1:], " "))
			continue
		}
		if len(f) != 2 {
			return nil, &InputError{file, n, "write each sort as: <glyph> <count>"}
		}
		if !printable(f[0]) {
			return nil, &InputError{file, n, "a glyph is 1 to 3 printable characters"}
		}
		k, err := strconv.Atoi(f[1])
		if err != nil || k < 0 || k > MaxCount {
			return nil, &InputError{file, n, fmt.Sprintf("the count should be a whole number from 0 to %d", MaxCount)}
		}
		g := Glyph(f[0])
		if _, dup := c.Count[g]; dup {
			return nil, &InputError{file, n, "this glyph is listed twice"}
		}
		if len(c.Count) >= MaxGlyphs {
			return nil, &InputError{file, n, fmt.Sprintf("at most %d different sorts", MaxGlyphs)}
		}
		c.Count[g] = k
	}
	if err := sc.Err(); err != nil {
		return nil, &InputError{file, n + 1, "a line is too long"}
	}
	if len(c.Count) == 0 {
		return nil, &InputError{file, 0, "the case lists no sorts"}
	}
	return c, nil
}

func cleanName(s string) string {
	var b strings.Builder
	for _, r := range s {
		if unicode.IsLetter(r) || unicode.IsDigit(r) || strings.ContainsRune(" -'.,&()", r) {
			b.WriteRune(r)
		}
		if b.Len() >= 60 {
			break
		}
	}
	if b.Len() == 0 {
		return "untitled"
	}
	return b.String()
}

// ParseJob reads the text to be printed. Pages are separated by lines of "---"; a page's first
// line may be "title: <words>". Spaces and line breaks are spacing material, not sorts.
func ParseJob(file, text string) ([]Page, error) {
	if err := checkText(file, text); err != nil {
		return nil, err
	}
	var pages []Page
	var cur []string
	flush := func() error {
		body := strings.Join(cur, "\n")
		cur = nil
		title := ""
		if strings.HasPrefix(strings.TrimSpace(body), "title:") {
			first, rest, _ := strings.Cut(strings.TrimSpace(body), "\n")
			title = cleanName(strings.TrimSpace(strings.TrimPrefix(first, "title:")))
			body = rest
		}
		if strings.TrimSpace(body) == "" {
			return nil
		}
		if len(pages) >= MaxPages {
			return &InputError{file, 0, fmt.Sprintf("at most %d pages", MaxPages)}
		}
		if title == "" {
			title = fmt.Sprintf("page %d", len(pages)+1)
		}
		pages = append(pages, pageOf(title, body))
		return nil
	}
	for _, line := range strings.Split(text, "\n") {
		if strings.TrimSpace(line) == "---" {
			if err := flush(); err != nil {
				return nil, err
			}
			continue
		}
		cur = append(cur, line)
	}
	if err := flush(); err != nil {
		return nil, err
	}
	if len(pages) == 0 {
		return nil, &InputError{file, 0, "there is nothing to set"}
	}
	for _, p := range pages {
		for g := range p.Need {
			if !printable(string(g)) {
				return nil, &InputError{file, 0, "the text has control characters"}
			}
		}
	}
	return pages, nil
}

func pageOf(title, body string) Page {
	p := Page{Title: title, Need: map[Glyph]int{}, Ligs: map[Glyph]int{}}
	rs := []rune(body)
	for i := 0; i < len(rs); {
		r := rs[i]
		if unicode.IsSpace(r) {
			i++
			continue
		}
		matched := false
		for _, l := range Ligatures {
			lr := []rune(string(l))
			if i+len(lr) <= len(rs) && string(rs[i:i+len(lr)]) == string(l) {
				p.Ligs[l]++
				for _, x := range lr {
					p.Need[Glyph(x)]++
				}
				i += len(lr)
				matched = true
				break
			}
		}
		if !matched {
			p.Need[Glyph(r)]++
			i++
		}
	}
	return p
}

// DefaultSubs are the tricks compositors have always used.
func DefaultSubs() []Sub {
	turned := [][2]string{{"u", "n"}, {"n", "u"}, {"d", "p"}, {"p", "d"}, {"b", "q"}, {"q", "b"}, {"6", "9"}, {"9", "6"}}
	var s []Sub
	for _, t := range turned {
		s = append(s, Sub{Glyph(t[0]), []Glyph{Glyph(t[1])}, 2, "a turned " + t[1]})
	}
	s = append(s,
		Sub{"'", []Glyph{","}, 1, "a turned comma"},
		Sub{"W", []Glyph{"V", "V"}, 3, "two Vs kerned together"},
		Sub{"w", []Glyph{"v", "v"}, 3, "two vs kerned together"},
		Sub{"\"", []Glyph{"'", "'"}, 1, "two apostrophes"},
		Sub{"0", []Glyph{"O"}, 2, "a capital O"},
		Sub{"1", []Glyph{"l"}, 2, "a lowercase l"},
		Sub{"1", []Glyph{"I"}, 3, "a capital I"},
	)
	return s
}

// ParseSubs reads extra substitutions: "<glyph> = <sort> [<sort>...] <cost>" per line.
func ParseSubs(file, text string) ([]Sub, error) {
	if err := checkText(file, text); err != nil {
		return nil, err
	}
	var subs []Sub
	for n, raw := range strings.Split(text, "\n") {
		line := strings.TrimSpace(raw)
		if line == "" || strings.HasPrefix(line, "//") {
			continue
		}
		f := strings.Fields(line)
		if len(f) < 4 || f[1] != "=" {
			return nil, &InputError{file, n + 1, "write a substitution as: <glyph> = <sort> [<sort>...] <cost>"}
		}
		cost, err := strconv.Atoi(f[len(f)-1])
		if err != nil || cost < 0 || cost > 100 {
			return nil, &InputError{file, n + 1, "the cost should be a whole number from 0 to 100"}
		}
		use := f[2 : len(f)-1]
		if len(use) > 3 {
			return nil, &InputError{file, n + 1, "a substitute uses at most 3 sorts"}
		}
		s := Sub{For: Glyph(f[0]), Cost: cost, Note: "your substitution"}
		for _, u := range append([]string{f[0]}, use...) {
			if !printable(u) {
				return nil, &InputError{file, n + 1, "a glyph is 1 to 3 printable characters"}
			}
		}
		for _, u := range use {
			s.Use = append(s.Use, Glyph(u))
		}
		if len(subs) >= MaxSubs {
			return nil, &InputError{file, n + 1, fmt.Sprintf("at most %d substitutions", MaxSubs)}
		}
		subs = append(subs, s)
	}
	return subs, nil
}

// Show writes a glyph for a report, making anything unusual visible.
func Show(g Glyph) string {
	if printable(string(g)) && !strings.ContainsAny(string(g), "​‎‏‪‫‬‭‮") {
		return string(g)
	}
	var parts []string
	for _, r := range string(g) {
		parts = append(parts, fmt.Sprintf("U+%04X", r))
	}
	return strings.Join(parts, " ")
}

func sortedGlyphs(m map[Glyph]int) []Glyph {
	out := make([]Glyph, 0, len(m))
	for g := range m {
		out = append(out, g)
	}
	sort.Slice(out, func(i, j int) bool { return out[i] < out[j] })
	return out
}
