import { config } from "../config";

export function NotFound() {
  return (
    <article className="legal">
      <h1>Page not found</h1>
      <p>
        We couldn't find that page. It may have moved, or the link may be
        wrong.
      </p>
      <ul className="links">
        <li>
          <a href="/">Home</a>
        </li>
        <li>
          <a href="/privacy">Privacy policy</a>
        </li>
        <li>
          <a href="/terms">Terms of service</a>
        </li>
        <li>
          <a href="/delete-account">Delete your account</a>
        </li>
      </ul>
      <p className="muted">{config.appName}</p>
    </article>
  );
}
