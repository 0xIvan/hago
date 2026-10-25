- Applying a rule to existing activity is much faster. Hago now re-checks only the recordings the rule can affect instead of every recording, so a site rule covering thousands of recordings applies in about a quarter of a second instead of half a minute.
- Accepting AI suggestions, "Always…" choices from Review and undoing a learned rule are also much faster, and accepting several AI suggestions at once refreshes the app only once.
- Classification checks only the rules that can match each recording, which also lightens the work Hago does while it tracks.
- The database gains a few indexes the first time this version opens. Your data is unchanged.

Download the universal DMG, open it and drag Hago to Applications. The app and DMG are Developer ID signed and notarized. Requires macOS 14 or newer; supports Apple Silicon and Intel.

Existing data stays local in the Hago application-support folder. If Accessibility stays unavailable after upgrading from an older locally signed build, remove Hago from the Accessibility / Device Control and Data Access list in System Settings, add `/Applications/Hago.app` again, and enable its switch.
