// The site has four fixed routes plus a 404 page. There is no router library;
// the server maps paths to pre-rendered files and this module maps the same
// paths to page components, so hydration renders exactly what was pre-rendered.
export type RouteKey =
  | "home"
  | "privacy"
  | "terms"
  | "delete-account"
  | "not-found";

export const NAV: { key: RouteKey; href: string; label: string }[] = [
  { key: "home", href: "/", label: "Home" },
  { key: "privacy", href: "/privacy", label: "Privacy" },
  { key: "terms", href: "/terms", label: "Terms" },
  { key: "delete-account", href: "/delete-account", label: "Delete account" },
];

/**
 * Maps a URL path to a route. The destination list comes from NAV, so adding a
 * page means editing one table, not two. Paths ending in `/index.html` (the
 * files the server actually stores) normalize to the pretty route so hydration
 * renders the same page the server served. Unknown paths resolve to the 404
 * page.
 */
export function routeFromPath(pathname: string): RouteKey {
  let clean = pathname.replace(/\/+$/, "") || "/";
  if (clean === "/index.html") {
    clean = "/";
  } else if (clean.endsWith("/index.html")) {
    clean = clean.slice(0, -"/index.html".length);
  }
  const match = NAV.find((item) => item.href === clean);
  return match ? match.key : "not-found";
}
