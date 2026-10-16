import { config } from "../config";

export function Terms() {
  const { appName } = config;
  return (
    <article className="legal">
      <h1>Terms of service</h1>
      <p className="muted">Last updated: {config.lastUpdated}</p>

      <p>
        These terms govern your use of {appName}, made by {config.developerName}
        . By installing or using the app you agree to them. If you do not agree,
        do not use the app.
      </p>

      <h2>Using the app</h2>
      <p>
        {appName} is a personal tracking tool. You must be old enough to consent
        to its use in your country. You agree not to misuse the service, attempt
        to disrupt it, or access it through automated means other than the app
        itself.
      </p>

      <h2>Not medical or nutritional advice</h2>
      <p>
        <strong>
          {appName} is not a medical device and does not provide medical,
          nutritional or professional health advice.
        </strong>{" "}
        The calorie and macro estimates come from automatic transcription and
        parsing of what you say, and can be wrong. Always use your own judgement
        and, for anything relating to a medical condition, diet or exercise
        program, consult a qualified professional. Do not rely on the app to
        diagnose, treat or manage any health condition.
      </p>

      <h2>AI features and limits</h2>
      <p>
        The voice logging, parsing and coaching features are powered by a
        third-party AI service. Their output is generated automatically and may
        be inaccurate or incomplete; you are responsible for checking it before
        relying on it. To keep the service available and affordable, these
        features have daily fair-use limits that differ between the free and
        paid tiers, and we may change those limits. When you reach a limit, the
        feature pauses until it resets.
      </p>

      <h2>Subscriptions and billing</h2>
      <p>
        The app is free, with an optional subscription that raises the AI
        limits. Subscriptions are sold and billed through Google Play. Payments,
        renewals, price changes, cancellations and refunds are handled by Google
        Play under its own terms; we do not process your payment details.
        Manage or cancel your subscription in the Google Play store. A
        subscription stays active until the end of the period you have paid
        for, including after you cancel.
      </p>

      <h2>Availability and changes</h2>
      <p>
        We aim to keep the app and its backend running, but we do not promise
        uninterrupted or error-free service. Features may change, and the AI
        features depend on third-party providers that may be temporarily
        unavailable.
      </p>

      <h2>Limitation of liability</h2>
      <p>
        To the fullest extent permitted by law, {config.developerName} is not
        liable for any indirect or consequential loss, or for any loss arising
        from your reliance on the app's estimates, including calorie, macro or
        exercise figures. Nothing in these terms limits liability that cannot be
        limited by law.
      </p>

      <h2>Changes to these terms</h2>
      <p>
        We may update these terms from time to time and will change the date at
        the top of this page when we do. Continued use of the app after an
        update means you accept the revised terms.
      </p>

      <h2>Governing law</h2>
      <p>These terms are governed by the laws of {config.governingLaw}.</p>

      <h2>Contact</h2>
      <p>
        Questions about these terms? Email{" "}
        <a href={`mailto:${config.supportEmail}`}>{config.supportEmail}</a>.
      </p>
    </article>
  );
}
