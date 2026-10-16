import type { ReactNode } from "react";

import { config } from "../config";
import { NAV, type RouteKey } from "../routes";

/**
 * Shared chrome: a header with the app name and links to every page, and a
 * footer repeating the legal links and the support address.
 */
export function Layout({
  route,
  children,
}: {
  route: RouteKey;
  children: ReactNode;
}) {
  return (
    <div className="site">
      <header className="site-header">
        <a className="brand" href="/">
          {config.appName}
        </a>
        <nav className="site-nav" aria-label="Main">
          {NAV.map((item) => (
            <a
              key={item.key}
              href={item.href}
              aria-current={item.key === route ? "page" : undefined}
            >
              {item.label}
            </a>
          ))}
        </nav>
      </header>

      <main className="site-main">{children}</main>

      <footer className="site-footer">
        <p>
          {config.appName} is made by {config.developerName}.
        </p>
        <nav className="footer-nav" aria-label="Footer">
          {NAV.map((item) => (
            <a key={item.key} href={item.href}>
              {item.label}
            </a>
          ))}
        </nav>
        <p>
          Contact:{" "}
          <a href={`mailto:${config.supportEmail}`}>{config.supportEmail}</a>
        </p>
      </footer>
    </div>
  );
}
