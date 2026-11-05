// Command swellmark checks a furniture design for joints that seasonal wood movement will break.
package main

import (
	"os"

	"github.com/reihooneh/daily-challenges/swellmark/internal/swellmark"
)

func main() {
	os.Exit(swellmark.Run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr))
}
