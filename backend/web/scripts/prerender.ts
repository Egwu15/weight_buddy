// Runs after `vite build`. It renders each route to static HTML and writes the
// files the Go server embeds, so every page is complete without JavaScript:
//
//   dist/index.html
//   dist/privacy/index.html
//   dist/terms/index.html
//   dist/delete-account/index.html
//   dist/404.html
//
// Each page gets its own <title>, meta description and canonical URL. The Vite
// asset tags from the built index.html are preserved, so the bundle still loads
// and hydrates over the static markup.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createElement } from "react";
import { renderToString } from "react-dom/server";

import { App } from "../src/app";
import { config } from "../src/config";
import type { RouteKey } from "../src/routes";

const here = dirname(fileURLToPath(import.meta.url));
const dist = join(here, "..", "dist");

type Page = {
  route: RouteKey;
  out: string;
  title: string;
  description: string;
  canonical: string;
  /** A phrase that must be present in the rendered markup, as a guard. */
  expect: string;
};

const pages: Page[] = [
  {
    route: "home",
    out: "index.html",
    title: `${config.appName} - ${config.tagline}`,
    description: config.tagline,
    canonical: `${config.siteUrl}/`,
    expect: config.tagline,
  },
  {
    route: "privacy",
    out: join("privacy", "index.html"),
    title: `Privacy policy - ${config.appName}`,
    description: `How ${config.appName} collects, uses and deletes your data.`,
    canonical: `${config.siteUrl}/privacy`,
    expect: "What the AI features send",
  },
  {
    route: "terms",
    out: join("terms", "index.html"),
    title: `Terms of service - ${config.appName}`,
    description: `The terms for using ${config.appName}.`,
    canonical: `${config.siteUrl}/terms`,
    expect: "Not medical or nutritional advice",
  },
  {
    route: "delete-account",
    out: join("delete-account", "index.html"),
    title: `Delete your account - ${config.appName}`,
    description: `How to delete your ${config.appName} account.`,
    canonical: `${config.siteUrl}/delete-account`,
    expect: "What gets deleted",
  },
  {
    route: "not-found",
    out: "404.html",
    title: `Page not found - ${config.appName}`,
    description: `Page not found.`,
    canonical: `${config.siteUrl}/`,
    expect: "Page not found",
  },
];

const template = readFileSync(join(dist, "index.html"), "utf8");
const ROOT_MARKER = '<div id="root"></div>';
const PLACEHOLDER = /\{\{[A-Z0-9_]+\}\}/g;

if (!template.includes(ROOT_MARKER)) {
  throw new Error(
    "prerender: dist/index.html has no empty <div id=\"root\"> to fill",
  );
}

const placeholders = new Set<string>();

for (const page of pages) {
  const markup = renderToString(createElement(App, { route: page.route }));
  if (!markup.includes(page.expect)) {
    throw new Error(
      `prerender: ${page.out} is missing expected content: ${page.expect}`,
    );
  }

  const html = applyHead(template, page, markup);
  for (const match of html.matchAll(PLACEHOLDER)) {
    placeholders.add(match[0]);
  }
  const target = join(dist, page.out);
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, html);
  console.log(`prerendered ${page.out}`);
}

// Draft copy ships with {{PLACEHOLDER}} markers on purpose. Always surface
// them, and let a release build refuse to publish with any left by setting
// SITE_STRICT_PLACEHOLDERS=1.
if (placeholders.size > 0) {
  const list = [...placeholders].sort().join(", ");
  const message =
    `unresolved placeholders in the built pages: ${list}. ` +
    "Fill them in web/src/config.ts before publishing.";
  if (process.env.SITE_STRICT_PLACEHOLDERS === "1") {
    throw new Error(`prerender: ${message}`);
  }
  console.warn(`warning: ${message}`);
}

function applyHead(template: string, page: Page, markup: string): string {
  let html = template;

  // Use a replacer function so any "$" in the markup is treated literally.
  html = html.replace(ROOT_MARKER, () => `<div id="root">${markup}</div>`);

  html = replaceTag(
    html,
    /<title>[\s\S]*?<\/title>/,
    `<title>${escapeHtml(page.title)}</title>`,
  );
  html = replaceTag(
    html,
    /<meta\s+name="description"[^>]*>/,
    `<meta name="description" content="${escapeHtml(page.description)}" />`,
  );
  html = replaceTag(
    html,
    /<link\s+rel="canonical"[^>]*>/,
    `<link rel="canonical" href="${escapeHtml(page.canonical)}" />`,
    "</head>",
  );

  return html;
}

/** Replaces the first match of `pattern`, or inserts `replacement` before
 * `insertBefore` when the pattern is absent. */
function replaceTag(
  html: string,
  pattern: RegExp,
  replacement: string,
  insertBefore?: string,
): string {
  if (pattern.test(html)) {
    return html.replace(pattern, () => replacement);
  }
  if (insertBefore && html.includes(insertBefore)) {
    return html.replace(insertBefore, () => `  ${replacement}\n  ${insertBefore}`);
  }
  return html;
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
