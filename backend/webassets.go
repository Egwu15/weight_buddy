// Package webassets embeds the pre-rendered public site that lives in web/.
//
// The site is built by `make web` (Vite, then the prerender script) into
// web/dist. The directive sits at the module root because go:embed can only
// name files inside the directory of the file that carries it: internal/site
// is too deep to reach a sibling web/dist. internal/site imports this package
// and wraps Dist in an http.Handler.
//
// If web/dist is missing, the build fails here with a clear
// "pattern all:web/dist: no matching files found" error, which is the intended
// signal to run `make web` first.
package webassets

import "embed"

// Dist holds the built site: index.html, the four pre-rendered pages and the
// hashed asset bundle Vite emits.
//
//go:embed all:web/dist
var Dist embed.FS
