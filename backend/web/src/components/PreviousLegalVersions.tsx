import { config } from "../config";

/** A legal document that is versioned by frozen snapshots. */
export type LegalDoc = "privacy" | "terms";

/**
 * Where the frozen snapshot of [doc] effective [date] is served from.
 * `scripts/snapshot-legal.mjs` writes the same path shape, so a change here
 * must be mirrored there (and vice versa).
 */
export function archiveHref(date: string, doc: LegalDoc): string {
  return `/legal/archive/${date}/${doc}/`;
}

const copy: Record<LegalDoc, { label: string; blurb: string }> = {
  privacy: {
    label: "Privacy policy",
    blurb:
      "When this policy changes, the earlier wording stays available so you " +
      "can see what applied at the time.",
  },
  terms: {
    label: "Terms of service",
    blurb:
      "When these terms change, the earlier wording stays available so you " +
      "can see what applied at the time.",
  },
};

/**
 * The "Previous versions" list, shared by the privacy policy and the terms so
 * the archive route and copy live in one place. Renders nothing until at least
 * one superseded version has been frozen and listed in `config.legalArchive`.
 */
export function PreviousLegalVersions({ doc }: { doc: LegalDoc }) {
  if (config.legalArchive.length === 0) return null;
  const { label, blurb } = copy[doc];
  return (
    <>
      <h2>Previous versions</h2>
      <p>{blurb}</p>
      <ul>
        {config.legalArchive.map((date) => (
          <li key={date}>
            <a href={archiveHref(date, doc)}>
              {label} effective {date}
            </a>
          </li>
        ))}
      </ul>
    </>
  );
}
