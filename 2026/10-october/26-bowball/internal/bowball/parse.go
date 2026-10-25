package bowball

import (
	"regexp"
	"strconv"
	"strings"
	"unicode/utf8"
)

// Limits on what a session file may contain.
const (
	MaxInput  = 64 * 1024
	MaxRowers = 40
	MaxPieces = 60
	MaxHulls  = 8
	MaxCrew   = 8
	MaxBoats  = 4
	maxLine   = 300
)

var (
	nameRe     = regexp.MustCompile(`^[A-Za-z][A-Za-z0-9'.-]{0,29}$`)
	titleRe    = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9 '.,&()/-]{0,59}$`)
	secondsRe  = regexp.MustCompile(`^\d{1,4}(\.\d{1,3})?$`)
	clockRe    = regexp.MustCompile(`^(\d{1,2}):([0-5]\d(\.\d{1,3})?)$`)
	distanceRe = regexp.MustCompile(`^\d{3,4}$`)
)

func fail(line int, msg string) *InputError { return &InputError{Line: line, Msg: msg} }

// checkText refuses invalid UTF-8, control characters (terminal escapes) and invisible
// zero-width or direction marks, which make a file read differently from how it prints.
func checkText(text string) error {
	line := 1
	for i := 0; i < len(text); {
		r, size := utf8.DecodeRuneInString(text[i:])
		switch {
		case r == utf8.RuneError && size <= 1:
			return fail(line, "is not valid UTF-8")
		case r == '\n':
			line++
		case r == '\t' || r == '\r':
		case r < 0x20 || (r >= 0x7f && r <= 0x9f):
			return fail(line, "contains a control or hidden character")
		case (r >= 0x200b && r <= 0x200f) || (r >= 0x202a && r <= 0x202e) || (r >= 0x2066 && r <= 0x2069) || r == 0xfeff:
			return fail(line, "contains a control or hidden character")
		}
		i += size
	}
	return nil
}

// parseTime reads "3:21.4" or "201.4" (seconds) into seconds.
func parseTime(s string) (float64, bool) {
	if m := clockRe.FindStringSubmatch(s); m != nil {
		mins, _ := strconv.Atoi(m[1])
		sec, err := strconv.ParseFloat(m[2], 64)
		if err != nil {
			return 0, false
		}
		v := float64(mins)*60 + sec
		return v, v <= 3600
	}
	if secondsRe.MatchString(s) {
		v, err := strconv.ParseFloat(s, 64)
		return v, err == nil && v <= 3600
	}
	return 0, false
}

// Parse reads a whole session file.
func Parse(text string) (*Session, error) {
	if len(text) > MaxInput {
		return nil, fail(0, "the file is larger than 64 KB")
	}
	text = strings.TrimPrefix(text, "\uFEFF")
	if err := checkText(text); err != nil {
		return nil, err
	}
	s := &Session{Name: "Seat racing", Noise: 1.0}
	index := map[string]int{}
	hulls := map[string]bool{}
	var piece *Piece
	sawSquad, sawSeats, sawNoise := false, false, false

	for n, raw := range strings.Split(text, "\n") {
		line := n + 1
		if len(raw) > maxLine {
			return nil, fail(line, "is longer than 300 characters")
		}
		if i := strings.IndexByte(raw, '#'); i >= 0 {
			raw = raw[:i]
		}
		w := strings.Fields(raw)
		if len(w) == 0 {
			continue
		}
		before := func(what string) error {
			if len(s.Pieces) > 0 {
				return fail(line, "'"+what+"' lines come before the first piece")
			}
			return nil
		}
		switch w[0] {
		case "squad":
			if sawSquad {
				return nil, fail(line, "'squad' comes once")
			}
			title := strings.Join(w[1:], " ")
			if !titleRe.MatchString(title) {
				return nil, fail(line, "the squad name uses letters, digits, spaces and ' . , & ( ) / - (up to 60)")
			}
			s.Name, sawSquad = title, true
		case "seats":
			if err := before("seats"); err != nil {
				return nil, err
			}
			k, err := strconv.Atoi(strings.Join(w[1:], " "))
			if sawSeats || len(w) != 2 || err != nil || k < 1 || k > MaxRowers {
				return nil, fail(line, "write 'seats N' once, with N the number of rowers who make the boat")
			}
			s.Seats, sawSeats = k, true
		case "noise":
			v, err := strconv.ParseFloat(strings.Join(w[1:], " "), 64)
			if sawNoise || len(w) != 2 || !secondsRe.MatchString(w[1]) || err != nil || v < 0.05 || v > 10 {
				return nil, fail(line, "write 'noise S' once, with S between 0.05 and 10 seconds per 1000 m")
			}
			s.Noise, sawNoise = v, true
		case "rower":
			if err := before("rower"); err != nil {
				return nil, err
			}
			if len(w) < 2 || len(w) > 3 || !nameRe.MatchString(w[1]) {
				return nil, fail(line, "write 'rower Name [bow|stroke|either]'; names are one word of letters, digits and ' . - (up to 30)")
			}
			if _, dup := index[w[1]]; dup {
				return nil, fail(line, "there is already a rower with that name")
			}
			if len(s.Rowers) >= MaxRowers {
				return nil, fail(line, "at most 40 rowers")
			}
			r := Rower{Name: w[1], Line: line}
			if len(w) == 3 {
				switch w[2] {
				case "bow":
					r.Side = Bow
				case "stroke":
					r.Side = Stroke
				case "either", "scull":
					r.Side = Either
				default:
					return nil, fail(line, "the side is bow, stroke or either")
				}
			}
			index[r.Name] = len(s.Rowers)
			s.Rowers = append(s.Rowers, r)
		case "piece":
			if len(s.Pieces) > 0 {
				if err := finishPiece(piece); err != nil {
					return nil, err
				}
			}
			if len(s.Pieces) >= MaxPieces {
				return nil, fail(line, "at most 60 pieces")
			}
			if len(w) != 3 || w[2] != "m" || !distanceRe.MatchString(w[1]) {
				return nil, fail(line, "write 'piece <distance> m', like 'piece 1000 m'")
			}
			d, _ := strconv.Atoi(w[1])
			if d < 100 || d > 6000 {
				return nil, fail(line, "piece distances are 100 to 6000 m")
			}
			s.Pieces = append(s.Pieces, Piece{Distance: float64(d), Line: line})
			piece = &s.Pieces[len(s.Pieces)-1]
		case "boat":
			if piece == nil {
				return nil, fail(line, "'boat' lines belong under a 'piece' line")
			}
			if len(w) < 4 {
				return nil, fail(line, "write 'boat <hull> <time> <rowers...>', like 'boat Blue 3:21.4 Ava Bea'")
			}
			if !nameRe.MatchString(w[1]) {
				return nil, fail(line, "hull names are one word of letters, digits and ' . - (up to 30)")
			}
			t, ok := parseTime(w[2])
			if !ok {
				return nil, fail(line, "times are seconds like 201.4 or minutes:seconds like 3:21.4 (up to an hour)")
			}
			if len(piece.Boats) >= MaxBoats {
				return nil, fail(line, "at most 4 boats in a piece")
			}
			b := Boat{Hull: w[1], Time: t, Line: line}
			for _, other := range piece.Boats {
				if other.Hull == b.Hull {
					return nil, fail(line, "this hull is already in the piece")
				}
			}
			if len(w)-3 > MaxCrew {
				return nil, fail(line, "at most 8 rowers in a boat")
			}
			for _, name := range w[3:] {
				r, known := index[name]
				if !known {
					return nil, fail(line, "every rower needs a 'rower' line first (one isn't declared)")
				}
				for _, other := range piece.Boats {
					for _, o := range other.Crew {
						if o == r {
							return nil, fail(line, "a rower can only be in one boat per piece")
						}
					}
				}
				for _, o := range b.Crew {
					if o == r {
						return nil, fail(line, "a rower is listed twice in this boat")
					}
				}
				b.Crew = append(b.Crew, r)
			}
			if !hulls[b.Hull] {
				if len(s.Hulls) >= MaxHulls {
					return nil, fail(line, "at most 8 different hulls")
				}
				hulls[b.Hull] = true
				s.Hulls = append(s.Hulls, b.Hull)
			}
			piece.Boats = append(piece.Boats, b)
		default:
			return nil, fail(line, "lines start with squad, seats, noise, rower, piece or boat")
		}
	}
	if len(s.Pieces) == 0 {
		return nil, fail(0, "the file has no pieces")
	}
	if err := finishPiece(piece); err != nil {
		return nil, err
	}
	if len(s.Rowers) < 3 {
		return nil, fail(0, "seat racing needs at least 3 rowers")
	}
	if s.Seats == 0 {
		s.Seats = len(s.Pieces[0].Boats[0].Crew)
	}
	if s.Seats >= len(s.Rowers) {
		return nil, fail(0, "seats must be fewer than the number of rowers, or there is nothing to choose")
	}
	count := map[Side]int{}
	for _, r := range s.Rowers {
		count[r.Side]++
	}
	s.Sweep = count[Bow]+count[Stroke] > 0
	if s.Sweep {
		half := s.Seats / 2
		if s.Seats%2 != 0 {
			return nil, fail(0, "a sweep boat (rowers with sides) has an even number of seats")
		}
		if count[Bow]+count[Either] < half || count[Stroke]+count[Either] < half || count[Bow]+count[Stroke]+count[Either] <= s.Seats {
			return nil, fail(0, "there aren't enough rowers on each side to choose between")
		}
	}
	return s, nil
}

func finishPiece(p *Piece) error {
	if len(p.Boats) < 2 {
		return fail(p.Line, "a piece needs at least two boats racing")
	}
	for _, b := range p.Boats[1:] {
		if len(b.Crew) != len(p.Boats[0].Crew) {
			return fail(b.Line, "every boat in a piece needs the same number of rowers")
		}
	}
	return nil
}
