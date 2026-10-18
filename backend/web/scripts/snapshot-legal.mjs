// Freezes the current legal pages into the public archive, so that updating the
// copy never overwrites what a user already saw and agreed to.
//
// Run it BEFORE editing the privacy policy or the terms, while the build still
// holds the outgoing version:
//
//   cd backend && make legal-snapshot              # effective date = today
//   cd backend && make legal-snapshot DATE=2026-09-01
//
// It reads the freshly built pages (dist/privacy, dist/terms), inlines the CSS
// and drops the JavaScript so each snapshot is a self-contained, immutable HTML
// file, then writes:
//
//   public/legal/archive/<date>/privacy/index.html
//   public/legal/archive/<date>/terms/index.html
//
// Vite copies public/ verbatim into the build and the Go server serves any
// <path>/index.html, so /legal/archive/<date>/<doc>/ keeps serving the exact
// wording that was in force on <date>. Those files are committed; never edit
// one after it is written. Add the date to config.legalArchive so the current
// pages link back to it.
//
// The archive route is declared in two places on purpose: the path shape below
// and `archiveHref` in src/components/PreviousLegalVersions.tsx. Keep them in
// step. Re-running for a date whose snapshot already exists is refused unless
// FORCE=1 is set, so a published version is never silently replaced.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const web = join(here, "..");
const dist = join(web, "dist");
const publicDir = join(web, "public");

const date = process.argv[2] ?? new Date().toISOString().slice(0, 10);
if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
  throw new Error(`snapshot-legal: expected a YYYY-MM-DD date, got "${date}"`);
}

const docs = ["privacy", "terms"];

for (const doc of docs) {
  const source = join(dist, doc, "index.html");
  let html = readFileSync(source, "utf8");

  // Inline the built stylesheet. Its filename is content-hashed and disappears
  // on the next build, so a frozen page must not depend on it.
  html = html.replace(
    /<link\b[^>]*rel="stylesheet"[^>]*>/g,
    (tag) => {
      const href = /href="([^"]+)"/.exec(tag)?.[1];
      if (!href) return tag;
      const css = readFileSync(join(dist, href.replace(/^\//, "")), "utf8");
      return `<style>${css}</style>`;
    },
  );

  // Drop scripts and module preloads: a frozen document needs no hydration, and
  // the hashed bundle they referenced will be gone after the next build.
  html = html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script>/g, "")
    .replace(/<script\b[^>]*\/>/g, "")
    .replace(/<link\b[^>]*rel="modulepreload"[^>]*>/g, "");

  // A banner so a reader knows this is superseded and can reach the current one.
  const banner =
    '<div style="position:sticky;top:0;z-index:9;padding:10px 16px;' +
    "background:#3a2a1a;color:#f5e9d6;font:13px/1.4 system-ui,sans-serif;" +
    'text-align:center">Archived version, effective ' +
    `${date}. <a style="color:#f0b429" href="/${doc}">See the current version</a>.</div>`;
  html = html.replace(/<body([^>]*)>/i, (open) => `${open}\n${banner}`);

  const out = join(publicDir, "legal", "archive", date, doc, "index.html");
  // A frozen snapshot is the wording a user already accepted, so it must never
  // be rewritten by accident. Overwriting takes an explicit FORCE=1.
  if (existsSync(out) && process.env.FORCE !== "1") {
    throw new Error(
      `snapshot-legal: ${out} already exists. ` +
        `Re-run with FORCE=1 only if you intend to replace a published version.`,
    );
  }
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, html);
  console.log(`frozen ${doc} as of ${date} -> public/legal/archive/${date}/${doc}/`);
}
