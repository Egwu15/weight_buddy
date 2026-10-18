import { config } from "../config";

/**
 * The landing page. Its one job is to get the app installed, so it leads with
 * the thing that is actually different: you talk, and it becomes macros. The
 * spoken card below is that promise made concrete, built from the app's own
 * palette rather than a stock hero image.
 */

/** Bar heights (percent) for the ambient voice waveform. */
const WAVE = [
  38, 64, 90, 52, 78, 100, 60, 84, 46, 70, 92, 56, 74, 42, 66, 88, 50, 96, 58,
  72,
];

const STEPS = [
  {
    title: "Say it, or type it",
    body: "Log a meal or a workout by talking. No forms and no portion puzzles.",
  },
  {
    title: "It becomes numbers",
    body: "Your words turn into calories, protein, carbs and fat, ready to check.",
  },
  {
    title: "It stays on your phone",
    body: "Your log never leaves the device. Only counts and costs reach the server.",
  },
];

const FEATURE_ICONS = [
  // mic: talk a meal in
  <path key="i0" d="M12 3.5a3 3 0 0 1 3 3v4a3 3 0 0 1-6 0v-4a3 3 0 0 1 3-3Zm-6 7a6 6 0 0 0 12 0M12 16.5v3" />,
  // pulse: log a workout the same way
  <path key="i1" d="M3 12h3.5l2-6 4 12 2.5-6H21" />,
  // bars: see the day and the trend
  <path key="i2" d="M4 20v-5M10 20V7M16 20v-9M22 20H2" />,
  // shield: private by default
  <path key="i3" d="M12 3.5 19 6v5.5c0 4-3 7-7 8.5-4-1.5-7-4.5-7-8.5V6l7-2.5Z" />,
];

export function Home() {
  return (
    <div className="home">
      <section className="hero">
        <div className="hero-copy">
          <p className="eyebrow">Voice-first calorie tracking</p>
          <h1 className="hero-title">
            Say it. <span className="hero-title-accent">It’s logged.</span>
          </h1>
          <p className="hero-tagline">{config.tagline}</p>

          <div className="hero-actions">
            <a className="button button-primary" href={config.playStoreUrl}>
              Get it on Google Play
            </a>
            <a className="button button-ghost" href="#how">
              See how it works
            </a>
          </div>

          <ul className="hero-trust">
            <li>No forms</li>
            <li>No ads or trackers</li>
            <li>Your log stays on your phone</li>
          </ul>
        </div>

        <div className="hero-demo" aria-hidden="true">
          <div className="demo-card">
            <div className="demo-heard">
              <span className="mic">
                <svg
                  viewBox="0 0 24 24"
                  width="18"
                  height="18"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  <path d="M12 3.5a3 3 0 0 1 3 3v4a3 3 0 0 1-6 0v-4a3 3 0 0 1 3-3Z" />
                  <path d="M6 10.5a6 6 0 0 0 12 0M12 16.5v3" />
                </svg>
              </span>
              <span className="wave">
                {WAVE.map((h, i) => (
                  <i
                    key={i}
                    style={{ height: `${h}%`, animationDelay: `${i * 60}ms` }}
                  />
                ))}
              </span>
            </div>

            <p className="demo-said">“Two eggs and one toast”</p>

            <div className="demo-result">
              <span className="demo-kcal">≈ 340 kcal</span>
              <span className="plate">
                <span style={{ width: "30%", background: "var(--jollof)" }} />
                <span style={{ width: "46.7%", background: "var(--plantain)" }} />
                <span style={{ width: "23.3%", background: "var(--ugu)" }} />
              </span>
              <ul className="demo-macros">
                <li>
                  <span className="dot" style={{ background: "var(--jollof)" }} />
                  Protein <b>18g</b>
                </li>
                <li>
                  <span className="dot" style={{ background: "var(--plantain)" }} />
                  Carbs <b>28g</b>
                </li>
                <li>
                  <span className="dot" style={{ background: "var(--ugu)" }} />
                  Fat <b>14g</b>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </section>

      <section className="section" id="how">
        <h2 className="section-title">From spoken to counted</h2>
        <p className="section-lead">
          Three steps, and you never fill in a form.
        </p>
        <ol className="steps">
          {STEPS.map((step, i) => (
            <li key={step.title}>
              <span className="step-num">{String(i + 1).padStart(2, "0")}</span>
              <h3>{step.title}</h3>
              <p>{step.body}</p>
            </li>
          ))}
        </ol>
      </section>

      <section className="section">
        <h2 className="section-title">What it does</h2>
        <ul className="feature-grid">
          {config.features.map((feature, i) => (
            <li key={feature}>
              <span className="feature-icon" aria-hidden="true">
                <svg
                  viewBox="0 0 24 24"
                  width="20"
                  height="20"
                  fill="none"
                  stroke="currentColor"
                  strokeWidth="2"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                >
                  {FEATURE_ICONS[i % FEATURE_ICONS.length]}
                </svg>
              </span>
              <span>{feature}</span>
            </li>
          ))}
        </ul>
      </section>

      <section className="section" id="screenshots">
        <h2 className="section-title">What it looks like</h2>
        <p className="section-lead">
          Today’s wave, the month view and your weight trend.
        </p>
        <div className="screenshots">
          {[
            {
              src: "/screenshots/today.png",
              alt: "Today's wave showing meals and a logged workout, with the day's calories and macros",
            },
            {
              src: "/screenshots/month.png",
              alt: "The month view: a calendar of logged days with logging and on-plan streaks",
            },
            {
              src: "/screenshots/weight.png",
              alt: "The weight card with a trend line and the weigh-in timeline",
            },
          ].map(({ src, alt }) => (
            <div className="phone" key={src}>
              <img
                className="phone-screen"
                src={src}
                alt={alt}
                width={540}
                height={960}
                loading="lazy"
              />
            </div>
          ))}
        </div>
      </section>

      <section className="band">
        <strong>No ads. No trackers.</strong>
        <span>Your log stays on your phone.</span>
      </section>

      <section className="final-cta">
        <h2 className="section-title">Start logging in seconds</h2>
        <a className="button button-primary" href={config.playStoreUrl}>
          Get it on Google Play
        </a>
      </section>
    </div>
  );
}
