// The single file to edit when copying this template to another app.
//
// Every app-specific string on the site comes from here: the components and
// pages stay generic. Values wrapped in {{ }} are placeholders that must be
// filled in before publishing; they are intentionally obvious so they cannot
// ship unnoticed.
export type SiteConfig = {
  /** Product name shown in the header, page titles and legal text. */
  appName: string;
  /** Who publishes the app. Used in the legal pages' "who we are" lines. */
  developerName: string;
  /** Address users write to for support and deletion requests. */
  supportEmail: string;
  /** Google Play listing the download button points at. */
  playStoreUrl: string;
  /** Public origin of this site; page canonical URLs are built from it. */
  siteUrl: string;
  /** Date the legal pages were last revised (YYYY-MM-DD). */
  lastUpdated: string;
  /** One-line description used under the app name on the home page. */
  tagline: string;
  /** Short "what it does" bullets on the home page. */
  features: string[];
  /** Third-party AI provider that processes transcription/parsing requests. */
  aiProviderName: string;
  /** Governing law for the terms of service. */
  governingLaw: string;
  /** Expected turnaround for an emailed deletion request. */
  deletionDays: string;
};

export const config: SiteConfig = {
  appName: "Weight Buddy",
  developerName: "Tedif",
  supportEmail: "contact@tedif.com",
  playStoreUrl: "https://play.google.com/store/apps/details?id=com.tedif.weight_buddy",
  siteUrl: "https://weightbuddy.com",
  lastUpdated: "2026-10-15",
  tagline: "Log what you eat and how you move — just by talking.",
  features: [
    "Log a meal by talking: it becomes calories, protein, carbs and fat.",
    "Log a workout the same way, with no forms to fill in.",
    "See today's calories and macros, and your weight trend over time.",
    "Everything you log stays on your phone.",
  ],
  aiProviderName: "OpenAI",
  governingLaw: "the Federal Republic of Nigeria",
  deletionDays: "30",
};
