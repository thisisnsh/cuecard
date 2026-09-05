/** Response schema version. Bump only for a breaking change to the payload shape. */
export const SCHEMA = 1;

/**
 * Behaviour the apps read silently. Only minSupportedVersion draws UI.
 * See README.md before changing minSupportedVersion — it locks people out.
 */
export const FLAGS = {
  minSupportedVersion: "0.0.0",
  updateURL: {
    ios: "https://apps.apple.com/app/id6757321325",
    android: "https://cuecard.dev/mobile",
  },
  // Every flag defaults to ON in the client, so only `false` has any effect.
  features: {
    pip: true,
    appleSignIn: true,
    googleSignIn: true,
  },
};
