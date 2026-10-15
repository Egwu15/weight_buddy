// Package migrations embeds the SQL migration files so the migrate command can
// apply them from a single static binary, with no files to ship alongside it.
package migrations

import "embed"

// FS holds every goose migration, applied in filename order.
//
//go:embed *.sql
var FS embed.FS
