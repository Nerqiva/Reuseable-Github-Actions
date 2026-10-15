// Command hello-world is the smallest possible real CLI: it prints a greeting
// and echoes its build version. It exists so this base repository can prove its
// own workflows work end to end — a reference implementation that is never
// executed is documentation, not a reference.
//
// The build contract the release workflow expects (see README.md) is:
//
//   the command runs with $GOOS, $GOARCH, $CGO_ENABLED, $VERSION and $OUT_DIR
//   in the environment and MUST leave a single executable at $OUT_DIR/$BINARY_NAME
package main

import (
	"flag"
	"fmt"
)

// version is injected at link time with -ldflags "-X main.version=$VERSION".
var version = "dev"

func main() {
	var (
		name    = flag.String("name", "world", "who to greet")
		shout   = flag.Bool("shout", false, "greet in upper case")
		showVer = flag.Bool("version", false, "print the version and exit")
	)
	flag.Parse()

	// The release workflow's verify job runs the binary with --version and
	// treats a non-zero exit as "this does not run on our Debian image". A CLI
	// that cannot be asked what it is cannot be smoke-tested, so --version is
	// part of the contract, not a nicety.
	if *showVer {
		fmt.Println("hello-world", version)
		return
	}

	greeting := fmt.Sprintf("hello, %s", *name)
	if *shout {
		greeting = toUpper(greeting)
	}

	fmt.Printf("%s (hello-world %s)\n", greeting, version)
}

// toUpper is hand-rolled so the binary has no dependencies beyond the standard
// library and stays trivially cross-compilable with CGO_ENABLED=0.
func toUpper(s string) string {
	out := []rune(s)
	for i, r := range out {
		if r >= 'a' && r <= 'z' {
			out[i] = r - ('a' - 'A')
		}
	}
	return string(out)
}