package bowball

import (
	"errors"
	"fmt"
	"io"
	"os"
)

const usage = "usage: bowball <session.txt>   (or - to read standard input)\n" +
	"Ranks rowers from seat-racing results, gives each one's chance of making the boat,\n" +
	"and suggests the swap that would settle the selection fastest.\n"

// Run is the command line with its streams passed in, so tests can drive it.
// Exit codes: 0 report printed, 2 bad usage or input.
func Run(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	if len(args) != 1 || args[0] == "-h" || args[0] == "--help" {
		fmt.Fprint(stderr, usage)
		return 2
	}
	text, err := read(args[0], stdin)
	if err != nil {
		fmt.Fprintf(stderr, "bowball: %v\n", err)
		return 2
	}
	s, err := Parse(text)
	if err != nil {
		fmt.Fprintf(stderr, "bowball: %v\n", err)
		return 2
	}
	out, err := Render(s)
	if err != nil {
		fmt.Fprintf(stderr, "bowball: %v\n", err)
		return 2
	}
	fmt.Fprint(stdout, out)
	return 0
}

var errUnreadable = errors.New("the session file could not be read (it must be a readable file)")

// read takes at most MaxInput+1 bytes, so an endless stream is cut off and reported by Parse.
// Only regular files are opened; the path is never echoed back.
func read(path string, stdin io.Reader) (string, error) {
	var r io.Reader = stdin
	if path != "-" {
		info, err := os.Stat(path)
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
