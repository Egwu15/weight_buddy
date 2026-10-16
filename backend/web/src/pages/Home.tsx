import { config } from "../config";
import { NAV } from "../routes";

export function Home() {
  return (
    <>
      <section className="hero">
        <h1>{config.appName}</h1>
        <p className="tagline">{config.tagline}</p>
        <ul className="features">
          {config.features.map((feature) => (
            <li key={feature}>{feature}</li>
          ))}
        </ul>
        <a className="button" href={config.playStoreUrl}>
          Get it on Google Play
        </a>
      </section>

      <section>
        <h2>What it looks like</h2>
        {/* Screenshots are placeholders until final captures are added. */}
        <div className="screenshots">
          <div className="screenshot" aria-hidden="true">
            Screenshot coming soon
          </div>
          <div className="screenshot" aria-hidden="true">
            Screenshot coming soon
          </div>
          <div className="screenshot" aria-hidden="true">
            Screenshot coming soon
          </div>
        </div>
      </section>

      <section>
        <h2>The details</h2>
        <ul className="links">
          {NAV.filter((item) => item.key !== "home").map((item) => (
            <li key={item.key}>
              <a href={item.href}>{item.label}</a>
            </li>
          ))}
        </ul>
      </section>
    </>
  );
}
