import { config } from "../config";

export function DeleteAccount() {
  const { appName } = config;
  return (
    <article className="legal">
      <h1>Delete your {appName} account</h1>
      <p className="muted">
        {appName} is the app made by {config.developerName}. This page explains
        how to delete your account and what happens to your data.
      </p>

      <h2>Delete it in the app</h2>
      <ol>
        <li>Open {appName}.</li>
        <li>
          Go to <strong>Settings &rarr; Account &amp; voice</strong>.
        </li>
        <li>
          Tap <strong>Delete account</strong> and confirm.
        </li>
      </ol>
      <p>
        You can also choose to erase the meals, workouts and weigh-ins stored on
        that device at the same time. Deleting the account takes effect
        immediately.
      </p>

      <h2>Don't have the app installed?</h2>
      <p>
        Email{" "}
        <a href={`mailto:${config.supportEmail}`}>{config.supportEmail}</a> and
        ask us to delete your account. To help us find it, include the account's
        user id (shown in the app under Settings, or in your original sign-in
        details). We aim to complete emailed deletion requests within{" "}
        {config.deletionDays} and will confirm by reply.
      </p>

      <h2>What gets deleted</h2>
      <p>
        We delete the server-side account record, its subscription entitlement
        and its usage history, along with the copies of subscription events we
        received from RevenueCat.
      </p>

      <h2>What is kept</h2>
      <ul>
        <li>
          <strong>Data on your device.</strong> Your meals, workouts, weigh-ins
          and coach history stay on your phone unless you also erase them in the
          app, or uninstall the app or clear its data.
        </li>
        <li>
          <strong>Purchase records held elsewhere.</strong> Google Play keeps
          its own record of your purchases and subscriptions, and RevenueCat
          keeps the purchase information it processed. Those records are
          governed by their own policies and are not deleted by us. Cancelling a
          subscription is done through Google Play.
        </li>
      </ul>

      <p>
        Back to <a href="/">home</a>.
      </p>
    </article>
  );
}
