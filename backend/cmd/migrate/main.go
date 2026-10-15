// Command migrate applies database migrations. The goose wiring and the
// migration files themselves land with the data-model task; this entry point
// exists now so the module layout is complete and buildable.
package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Fprintln(os.Stderr, "migrate: not implemented yet")
	os.Exit(1)
}
