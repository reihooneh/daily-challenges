// Command bowball analyses a seat-racing session: who is fastest, who makes the boat, and which
// swap to race next.
package main

import (
	"os"

	"github.com/reihooneh/daily-challenges/bowball/internal/bowball"
)

func main() {
	os.Exit(bowball.Run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr))
}
