package planner

import (
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"
)

// ParseError is a problem with the user's text. Its message never contains
// text copied from the input, only line numbers and what was expected.
type ParseError struct {
	Line    int
	Message string
}

func (e *ParseError) Error() string {
	if e.Line == 0 {
		return e.Message
	}
	return fmt.Sprintf("line %d: %s", e.Line, e.Message)
}

func parseErr(line int, format string, args ...any) error {
	return &ParseError{Line: line, Message: fmt.Sprintf(format, args...)}
}

// Go's regexp package guarantees linear-time matching, so none of these
// patterns can be made to run slowly by a crafted input.
var (
	codePattern      = regexp.MustCompile(`^[A-Za-z][A-Za-z0-9-]{1,11}$`)
	componentPattern = regexp.MustCompile(`^[A-Za-z][A-Za-z ]{0,19}$`)
	timePattern      = regexp.MustCompile(`^(\d{1,2})(?::(\d{2}))?(am|pm)?$`)
	spaces           = regexp.MustCompile(`\s+`)

	wishNoDay      = regexp.MustCompile(`^no (?:classes? )?(?:on )?([a-z]+)s?$`)
	wishBefore     = regexp.MustCompile(`^(?:nothing|not|no classes?) before (\S+)$`)
	wishAfter      = regexp.MustCompile(`^(?:nothing|not|no classes?) after (\S+)$`)
	wishLunch      = regexp.MustCompile(`^(?:lunch|break) (\S+?) ?- ?(\S+) for (\d{1,3}) ?min(?:ute)?s?$`)
	wishMaxDays    = regexp.MustCompile(`^at most (\d) days?(?: on campus)?$`)
	wishMaxHours   = regexp.MustCompile(`^at most (\d{1,2}) hours?(?: of class)? (?:per|a) day$`)
	wishMinGap     = regexp.MustCompile(`^at least (\d{1,3}) ?min(?:ute)?s? between classes$`)
	wishBusy       = regexp.MustCompile(`^(?i)busy ([a-z]+) (\S+?) ?- ?(\S+)(?: (.{1,40}))?$`)
	wishLinePrefix = "wish:"
)

var dayLookup = map[string]int{
	"mon": 0, "monday": 0, "tue": 1, "tues": 1, "tuesday": 1, "wed": 2, "wednesday": 2,
	"thu": 3, "thur": 3, "thurs": 3, "thursday": 3, "fri": 4, "friday": 4,
	"sat": 5, "saturday": 5, "sun": 6, "sunday": 6,
}

// Parse reads the plain-text format described in the README.
func Parse(text string) (*Problem, error) {
	if len(text) > MaxInputBytes {
		return nil, parseErr(0, "input is larger than %d bytes", MaxInputBytes)
	}
	if !utf8.ValidString(text) {
		return nil, parseErr(0, "input is not valid UTF-8 text")
	}
	lines := strings.Split(strings.ReplaceAll(text, "\r\n", "\n"), "\n")
	if len(lines) > MaxLines {
		return nil, parseErr(0, "input has more than %d lines", MaxLines)
	}

	problem := &Problem{}
	seenCodes := map[string]bool{}
	for index, raw := range lines {
		number := index + 1
		if len(raw) > MaxLineLength {
			return nil, parseErr(number, "line is longer than %d characters", MaxLineLength)
		}
		if err := checkCharacters(raw, number); err != nil {
			return nil, err
		}
		if hash := strings.IndexByte(raw, '#'); hash >= 0 {
			raw = raw[:hash]
		}
		line := strings.TrimSpace(spaces.ReplaceAllString(raw, " "))
		if line == "" {
			continue
		}

		if len(line) >= len(wishLinePrefix) && strings.EqualFold(line[:len(wishLinePrefix)], wishLinePrefix) {
			wish, err := parseWish(strings.TrimSpace(line[len(wishLinePrefix):]), number)
			if err != nil {
				return nil, err
			}
			if len(problem.Wishes) >= MaxWishes {
				return nil, parseErr(number, "more than %d wishes", MaxWishes)
			}
			problem.Wishes = append(problem.Wishes, wish)
			continue
		}

		if colon := strings.IndexByte(line, ':'); colon > 0 && componentPattern.MatchString(strings.TrimSpace(line[:colon])) {
			if len(problem.Courses) == 0 {
				return nil, parseErr(number, "a class time appears before any course name")
			}
			course := &problem.Courses[len(problem.Courses)-1]
			if len(course.Components) >= MaxComponents {
				return nil, parseErr(number, "a course can have at most %d components", MaxComponents)
			}
			component, err := parseComponent(strings.TrimSpace(line[:colon]), line[colon+1:], number)
			if err != nil {
				return nil, err
			}
			course.Components = append(course.Components, component)
			continue
		}

		course, err := parseCourseHeader(line, number)
		if err != nil {
			return nil, err
		}
		key := strings.ToUpper(course.Code)
		if seenCodes[key] {
			return nil, parseErr(number, "this course code is used twice")
		}
		seenCodes[key] = true
		if len(problem.Courses) >= MaxCourses {
			return nil, parseErr(number, "more than %d courses", MaxCourses)
		}
		problem.Courses = append(problem.Courses, course)
	}

	if len(problem.Courses) == 0 {
		return nil, parseErr(0, "no courses found")
	}
	for _, course := range problem.Courses {
		if len(course.Components) == 0 {
			return nil, parseErr(0, "course %s has no class times", course.Code)
		}
	}
	return problem, nil
}

// checkCharacters rejects control and invisible formatting characters, so
// nothing that could manipulate a terminal or hide text gets any further.
func checkCharacters(line string, number int) error {
	for _, r := range line {
		if r == '\t' {
			continue
		}
		if unicode.IsControl(r) || unicode.In(r, unicode.Cf, unicode.Zl, unicode.Zp, unicode.Co, unicode.Cs) {
			return parseErr(number, "control characters are not allowed")
		}
	}
	return nil
}

func parseCourseHeader(line string, number int) (Course, error) {
	code, title, _ := strings.Cut(line, " ")
	if !codePattern.MatchString(code) {
		return Course{}, parseErr(number, "expected a course code (like COMP1010), a class time (like \"Lecture: Mon 10:00-12:00\") or a wish")
	}
	title = strings.TrimSpace(title)
	if utf8.RuneCountInString(title) > MaxTitleLength {
		return Course{}, parseErr(number, "course title is longer than %d characters", MaxTitleLength)
	}
	if !safeText(title) {
		return Course{}, parseErr(number, "course title may only contain letters, digits, spaces and . , ' & ( ) : / + -")
	}
	return Course{Code: strings.ToUpper(code), Title: title}, nil
}

// safeText is an allow-list for free text that will later be displayed.
func safeText(text string) bool {
	for _, r := range text {
		if unicode.IsLetter(r) || unicode.IsDigit(r) || r == ' ' {
			continue
		}
		if !strings.ContainsRune(".,'&():/+-", r) {
			return false
		}
	}
	return true
}

func parseComponent(name, rest string, number int) (Component, error) {
	component := Component{Name: titleCase(name)}
	for _, optionText := range strings.Split(rest, "|") {
		if len(component.Options) >= MaxOptions {
			return Component{}, parseErr(number, "a component can have at most %d options", MaxOptions)
		}
		var option Option
		for _, meetingText := range strings.Split(optionText, "+") {
			if len(option.Meetings) >= MaxMeetings {
				return Component{}, parseErr(number, "an option can have at most %d meetings", MaxMeetings)
			}
			meeting, err := parseMeeting(strings.TrimSpace(meetingText), number)
			if err != nil {
				return Component{}, err
			}
			for _, other := range option.Meetings {
				if other.Day == meeting.Day && other.Start < meeting.End && meeting.Start < other.End {
					return Component{}, parseErr(number, "two meetings of the same option overlap")
				}
			}
			option.Meetings = append(option.Meetings, meeting)
		}
		component.Options = append(component.Options, option)
	}
	return component, nil
}

func titleCase(name string) string {
	lower := strings.ToLower(name)
	return strings.ToUpper(lower[:1]) + lower[1:]
}

// parseMeeting reads "Mon 10:00-12:00", "tue 9-11" or "Wed 2pm-4:30pm".
func parseMeeting(text string, number int) (Meeting, error) {
	dayText, timesText, found := strings.Cut(text, " ")
	day, ok := dayLookup[strings.ToLower(dayText)]
	if !found || !ok {
		return Meeting{}, parseErr(number, "expected a day and a time range, like \"Mon 10:00-12:00\"")
	}
	start, end, err := parseRange(strings.ReplaceAll(timesText, " ", ""), number)
	if err != nil {
		return Meeting{}, err
	}
	return Meeting{Day: day, Start: start, End: end}, nil
}

func parseRange(text string, number int) (int, int, error) {
	startText, endText, found := strings.Cut(text, "-")
	if !found {
		return 0, 0, parseErr(number, "expected a time range, like 10:00-12:00")
	}
	start, err := parseClock(startText, number)
	if err != nil {
		return 0, 0, err
	}
	end, err := parseClock(endText, number)
	if err != nil {
		return 0, 0, err
	}
	if end <= start {
		return 0, 0, parseErr(number, "a time range must end after it starts (use 24-hour times or am/pm)")
	}
	return start, end, nil
}

// parseClock reads "9", "09:30", "2pm" or "14:00" as minutes after midnight.
func parseClock(text string, number int) (int, error) {
	match := timePattern.FindStringSubmatch(strings.ToLower(text))
	if match == nil {
		return 0, parseErr(number, "expected a time, like 09:30 or 2pm")
	}
	hour, _ := strconv.Atoi(match[1])
	minute := 0
	if match[2] != "" {
		minute, _ = strconv.Atoi(match[2])
	}
	switch match[3] {
	case "am":
		if hour < 1 || hour > 12 {
			return 0, parseErr(number, "expected a time, like 09:30 or 2pm")
		}
		hour %= 12
	case "pm":
		if hour < 1 || hour > 12 {
			return 0, parseErr(number, "expected a time, like 09:30 or 2pm")
		}
		hour = hour%12 + 12
	}
	total := hour*60 + minute
	if minute > 59 || total > minutesPerDay {
		return 0, parseErr(number, "expected a time between 00:00 and 24:00")
	}
	return total, nil
}

func parseWish(text string, number int) (Wish, error) {
	lower := strings.ToLower(text)
	if m := wishBefore.FindStringSubmatch(lower); m != nil {
		minutes, err := parseClock(m[1], number)
		return Wish{Kind: NotBefore, Minutes: minutes}, err
	}
	if m := wishAfter.FindStringSubmatch(lower); m != nil {
		minutes, err := parseClock(m[1], number)
		return Wish{Kind: NotAfter, Minutes: minutes}, err
	}
	if m := wishLunch.FindStringSubmatch(lower); m != nil {
		start, end, err := parseRange(m[1]+"-"+m[2], number)
		if err != nil {
			return Wish{}, err
		}
		length, _ := strconv.Atoi(m[3])
		if length < 1 || length > end-start {
			return Wish{}, parseErr(number, "the break must fit inside its time window")
		}
		return Wish{Kind: Lunch, Minutes: length, Start: start, End: end}, nil
	}
	if m := wishMaxDays.FindStringSubmatch(lower); m != nil {
		days, _ := strconv.Atoi(m[1])
		if days < 1 || days > daysPerWeek {
			return Wish{}, parseErr(number, "days must be between 1 and 7")
		}
		return Wish{Kind: MaxDays, Minutes: days}, nil
	}
	if m := wishMaxHours.FindStringSubmatch(lower); m != nil {
		hours, _ := strconv.Atoi(m[1])
		if hours < 1 || hours > 24 {
			return Wish{}, parseErr(number, "hours per day must be between 1 and 24")
		}
		return Wish{Kind: MaxDayLength, Minutes: hours * 60}, nil
	}
	if m := wishMinGap.FindStringSubmatch(lower); m != nil {
		gap, _ := strconv.Atoi(m[1])
		if gap < 1 || gap > 240 {
			return Wish{}, parseErr(number, "the gap must be between 1 and 240 minutes")
		}
		return Wish{Kind: MinGap, Minutes: gap}, nil
	}
	if m := wishBusy.FindStringSubmatch(text); m != nil {
		day, ok := dayLookup[strings.ToLower(m[1])]
		if !ok {
			return Wish{}, parseErr(number, "expected a day after \"busy\", like \"busy Tue 14:00-18:00 work\"")
		}
		start, end, err := parseRange(m[2]+"-"+m[3], number)
		if err != nil {
			return Wish{}, err
		}
		label := strings.TrimSpace(strings.Trim(strings.TrimSpace(m[4]), "()"))
		if !safeText(label) {
			return Wish{}, parseErr(number, "the note after a busy time may only contain letters, digits, spaces and . , ' & ( ) : / + -")
		}
		return Wish{Kind: Busy, Day: day, Start: start, End: end, Label: label}, nil
	}
	if m := wishNoDay.FindStringSubmatch(lower); m != nil {
		if day, ok := dayLookup[m[1]]; ok {
			return Wish{Kind: NoDay, Day: day}, nil
		}
		if day, ok := dayLookup[strings.TrimSuffix(m[1], "s")]; ok { // "no Fridays"
			return Wish{Kind: NoDay, Day: day}, nil
		}
	}
	return Wish{}, parseErr(number, "wish not understood (see the README for the list of wishes)")
}

// IsParseError reports whether err came from bad user input.
func IsParseError(err error) bool {
	var target *ParseError
	return errors.As(err, &target)
}
