import { config } from "../config";

export function Privacy() {
  const { appName } = config;
  return (
    <article className="legal">
      <h1>Privacy policy</h1>
      <p className="muted">Last updated: {config.lastUpdated}</p>

      <p>
        This policy explains what {appName} collects, why, where it goes and the
        choices you have. {appName} is made by {config.developerName}.
      </p>

      <h2>What we collect</h2>
      <ul>
        <li>
          <strong>An account identifier.</strong> When you first open the app it
          creates an anonymous account for your device from a randomly generated
          install id. If you sign in with Google, we also store the stable
          identifier for that Google account so your account survives a
          reinstall. We do not store your email address, name or photo — the
          Google sign-in token is checked and then discarded.
        </li>
        <li>
          <strong>Usage records for the AI features.</strong> Each time you use
          voice logging, meal or workout parsing, or the coach, we record that
          the call happened and an estimate of what it cost us. We record counts
          and cost estimates, not what you said and not what the AI replied.
        </li>
        <li>
          <strong>An abuse signal.</strong> To cap how many free accounts one
          device can create, we store a salted, one-way hash of your IP address
          together with a daily signup count. We never store your raw IP address
          for this, and the hash cannot be turned back into an address.
        </li>
      </ul>
      <p>
        We do not collect your meals, workouts, weigh-ins, coach conversations
        or memories. Those are stored on your device (see below).
      </p>

      <h2>What the AI features send</h2>
      <p>
        Voice logging and the coach are powered by a third-party AI provider,{" "}
        {config.aiProviderName}. When you use them, your audio or text is sent
        from your device to our server and on to {config.aiProviderName} so it
        can be transcribed, parsed or answered. The text we send may include the
        food vocabulary you have chosen to configure. Our server does not store
        that content and does not write it to logs; it records only the usage
        metadata described above.
      </p>
      <p>
        Text you type into the coach, and your recorded voice notes, are
        therefore processed by {config.aiProviderName} under its own terms and
        privacy policy. Do not use the AI features to share information you are
        not comfortable sending to a third-party service.
      </p>

      <h2>Where your data lives</h2>
      <ul>
        <li>
          <strong>On your device.</strong> Your meals, workouts, weigh-ins,
          coach history and settings are stored locally in the app. They are
          not uploaded to us as a log, and they leave the device only if you
          export or back them up yourself.
        </li>
        <li>
          <strong>On our servers.</strong> We keep your account identifier, the
          entitlement that records your subscription state, usage counts and
          cost estimates, and the abuse hash. No meal, workout or conversation
          content is stored here.
        </li>
        <li>
          <strong>Third parties.</strong> {config.aiProviderName} processes the
          audio and text described above. RevenueCat receives your account id
          and purchase information to manage subscriptions, and Google Play
          processes payments and keeps its own purchase records. These
          providers handle that data under their own privacy policies.
        </li>
      </ul>

      <h2>How long we keep it</h2>
      <p>
        Account data — the identifier, entitlement and usage records — is kept
        while your account exists and is deleted when you delete your account.
        Copies of subscription events we received are deleted too, though
        RevenueCat and Google Play keep their own billing records for as long as
        their policies require. Data on your device stays until you erase it in
        the app or uninstall the app.
      </p>

      <h2>Security</h2>
      <p>
        Traffic between the app and our servers is encrypted in transit, and API
        keys for the AI provider are held on the server, never in the app. Our
        server logs which endpoints were called — never the audio, text or
        tokens involved.
      </p>

      <h2>Children</h2>
      <p>
        {appName} is not intended for children under 13, and we do not knowingly
        collect personal information from them. If you believe a child has used
        the app, contact us and we will delete the account.
      </p>

      <h2>Your choices and rights</h2>
      <p>
        You can delete your account and the data we hold about it at any time
        from within the app or by emailing us; see{" "}
        <a href="/delete-account">how to delete your account</a>. You can also
        ask us what we hold about you, or ask us to correct it, by writing to{" "}
        <a href={`mailto:${config.supportEmail}`}>{config.supportEmail}</a>.
      </p>

      <h2>No ads or tracking</h2>
      <p>
        {appName} does not show ads and does not include third-party analytics
        or tracking in the app or on this website. This site sets no cookies and
        makes no external requests.
      </p>

      <h2>Changes</h2>
      <p>
        If this policy changes, we will update the date at the top of this page.
        Continued use of the app after a change means you accept the updated
        policy.
      </p>

      <h2>Contact</h2>
      <p>
        Questions about privacy? Email{" "}
        <a href={`mailto:${config.supportEmail}`}>{config.supportEmail}</a>.
      </p>
    </article>
  );
}
