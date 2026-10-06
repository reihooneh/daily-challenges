// Command picktwo plans a timetable from a text file, or explains why it
// cannot be done.
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"

	"github.com/reihooneh/pick-two/internal/planner"
)

const usage = `Usage: picktwo [--json] FILE     plan the timetable described in FILE (use - for standard input)

Exit codes: 0 a timetable exists, 1 impossible as asked, 2 the input could not be read.
`

func main() {
	os.Exit(run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr))
}

func run(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	asJSON := false
	if len(args) > 0 && args[0] == "--json" {
		asJSON = true
		args = args[1:]
	}
	if len(args) == 1 && (args[0] == "-h" || args[0] == "--help") {
		fmt.Fprint(stdout, usage)
		return 0
	}
	if len(args) != 1 {
		fmt.Fprint(stderr, usage)
		return 2
	}

	text, err := readLimited(args[0], stdin)
	if err != nil {
		fmt.Fprintf(stderr, "picktwo: %s\n", err)
		return 2
	}
	response := planner.Run(text)
	if asJSON {
		encoded, _ := json.MarshalIndent(response, "", "  ")
		fmt.Fprintf(stdout, "%s\n", encoded)
	} else if response.Status == planner.StatusError || response.Status == planner.StatusUnknown {
		fmt.Fprintf(stderr, "picktwo: %s\n", response.Error)
	} else {
		fmt.Fprint(stdout, planner.RenderText(response))
	}
	switch response.Status {
	case planner.StatusOK:
		return 0
	case planner.StatusImpossible:
		return 1
	default:
		return 2
	}
}

// readLimited never reads more than the size limit plus one byte, so a huge
// file or an endless stream cannot exhaust memory.
func readLimited(path string, stdin io.Reader) (string, error) {
	source := stdin
	if path != "-" {
		info, err := os.Stat(path)
		if err != nil || !info.Mode().IsRegular() {
			return "", fmt.Errorf("cannot read that file")
		}
		file, err := os.Open(path)
		if err != nil {
			return "", fmt.Errorf("cannot read that file")
		}
		defer file.Close()
		source = file
	}
	data, err := io.ReadAll(io.LimitReader(source, planner.MaxInputBytes+1))
	if err != nil {
		return "", fmt.Errorf("cannot read that file")
	}
	if len(data) > planner.MaxInputBytes {
		return "", fmt.Errorf("input is larger than %d bytes", planner.MaxInputBytes)
	}
	return string(data), nil
}
