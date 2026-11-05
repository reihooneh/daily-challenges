package swellmark

import (
	"errors"
	"fmt"
	"io"
	"os"
)

const usage = "usage: swellmark <design.txt>   (or - to read standard input)\n" +
	"Checks a piece of furniture for joints that seasonal wood movement will crack, bind or open,\n" +
	"and the shop humidity at which it is safe to build.\n"

// Run is the command line with its streams passed in, so tests can drive it.
// Exit codes: 0 no joint fails, 1 a joint fails, 2 bad usage or input.
func Run(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	if len(args) != 1 || args[0] == "-h" || args[0] == "--help" {
		fmt.Fprint(stderr, usage)
		return 2
	}
	text, err := read(args[0], stdin)
	if err != nil {
		fmt.Fprintf(stderr, "swellmark: %v\n", err)
		return 2
	}
	d, err := Parse(text)
	if err != nil {
		fmt.Fprintf(stderr, "swellmark: %v\n", err)
		return 2
	}
	fmt.Fprint(stdout, Render(d))
	for _, r := range Check(d) {
		if r.Verdict == Fail {
			return 1
		}
	}
	return 0
}

var errUnreadable = errors.New("the design file could not be read (it must be a regular file, not a link)")

// read takes at most MaxInput+1 bytes, so an endless stream is cut off and reported by Parse.
// Only regular files are opened (not links, folders or devices); the path is never echoed back.
func read(path string, stdin io.Reader) (string, error) {
	var r io.Reader = stdin
	if path != "-" {
		info, err := os.Lstat(path)
		if err != nil || !info.Mode().IsRegular() {
			return "", errUnreadable
		}
		f, err := os.Open(path)
		if err != nil {
			return "", errUnreadable
		}
		defer f.Close()
		r = f
	}
	data, err := io.ReadAll(io.LimitReader(r, MaxInput+1))
	if err != nil {
		return "", errUnreadable
	}
	return string(data), nil
}
