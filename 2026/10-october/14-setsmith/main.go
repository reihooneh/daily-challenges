// Command setsmith plans a band's running order. Usage: setsmith GIGFILE (or - for stdin).
package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"

	"setsmith/setlist"
)

const usage = "usage: setsmith GIGFILE   (use - for standard input)"

// readLimited reads at most MaxBytes+1 bytes, so a huge file or endless stream is refused.
func readLimited(path string, stdin io.Reader) (string, error) {
	var r io.Reader = stdin
	if path != "-" {
		info, err := os.Stat(path)
		if err != nil || !info.Mode().IsRegular() {
			return "", &setlist.InputError{Msg: "the gig file could not be read"}
		}
		f, err := os.Open(path)
		if err != nil {
			return "", &setlist.InputError{Msg: "the gig file could not be read"}
		}
		defer f.Close()
		r = f
	}
	data, err := io.ReadAll(io.LimitReader(r, setlist.MaxBytes+1))
	if err != nil {
		return "", &setlist.InputError{Msg: "the gig file could not be read"}
	}
	if len(data) > setlist.MaxBytes {
		return "", &setlist.InputError{Msg: "the file is larger than 16 KB"}
	}
	return string(data), nil
}

// safeName keeps only plain characters of a file name for printing.
func safeName(path string) string {
	if path == "-" {
		return "standard input"
	}
	name := []rune(filepath.Base(path))
	for i, r := range name {
		ok := (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || strings.ContainsRune("._- ", r)
		if !ok {
			name[i] = '?'
		}
	}
	if len(name) > 60 {
		name = name[:60]
	}
	return string(name)
}

// run returns the exit code: 0 a plan, 1 nothing fits, 2 bad input.
func run(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	if len(args) == 1 && (args[0] == "-h" || args[0] == "--help") {
		fmt.Fprintln(stdout, usage)
		return 0
	}
	if len(args) != 1 || (strings.HasPrefix(args[0], "-") && args[0] != "-") {
		fmt.Fprintln(stderr, "setsmith: give exactly one gig file\n"+usage)
		return 2
	}
	text, err := readLimited(args[0], stdin)
	if err == nil {
		var g *setlist.Gig
		if g, err = setlist.Parse(text); err == nil {
			plan, perr := g.Solve()
			var none *setlist.NoPlanError
			if errors.As(perr, &none) {
				fmt.Fprintf(stdout, "SETSMITH  %s\n\nNo running order fits:\n", safeName(args[0]))
				for _, r := range none.Reasons {
					fmt.Fprintf(stdout, "  - %s\n", r)
				}
				return 1
			}
			fmt.Fprint(stdout, setlist.Render(g, plan, safeName(args[0])))
			return 0
		}
	}
	fmt.Fprintf(stderr, "setsmith: %s\n%s\n", err, usage)
	return 2
}

func main() {
	os.Exit(run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr))
}
