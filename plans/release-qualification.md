# Hago distribution qualification

The release workflow builds a notarized candidate on explicit dispatch. Tag builds
publish only after notarization and appcast signature verification. CI requires an
explicitly provisioned SPARKLE_PRIVATE_KEY secret matching the public key; without
it publishing fails closed. No CI secret is created or private key exported by
this implementation. The Hago-specific
Ed25519 signing key stays in macOS Keychain under account `hago-sparkle`. Only
its public key is in Info.plist. Local installs retain their existing signing
certificate; distribution uses Developer ID separately.

1. Set `HAGO_VERSION` to a stable three-part version and `HAGO_BUILD_NUMBER` to a
   strictly increasing build number. Build/package, then run notarize-app.sh
   using an existing authorized Developer ID/notary configuration. Never place
   credential values in source or command history.
2. Run `scripts/package-dmg.sh outputs/Hago.app outputs`. Notarize and staple
   the DMG too, then regenerate checksums after stapling. A locally signed DMG
   without these tickets is not a notarized release.
3. Run `scripts/appcast.sh outputs/Hago.app outputs/Hago-VERSION-ARCH.dmg NOTES.md`
   locally. This uses the Hago Keychain signing account, with no private-key
   export. Cryptographic verification checks the appcast signature against the
   public key shipped in the app and validates version, URL and archive length.
4. Qualify an old-to-new update using a private test feed and both signed,
   notarized builds; check offline, current/newer versions and a missing feed.
   Sparkle provides user-facing errors and version comparisons. Automatic checks,
   profiling and downloads are disabled; Check for Updates is user initiated.
5. Verify a fresh downloaded install under Gatekeeper, permissions, login choice,
   database migration/backup recovery and tracking after real sleep/lock/login.
   Build and notarization success alone do not establish these behaviors.
6. After explicit public release authorization, publish the verified versioned
   DMG, ZIP, final checksums and locally signed `appcast.xml` together in the
   matching GitHub `vVERSION` release. The first published appcast establishes
   the production feed; before then Check for Updates reports a feed error.

Do not overwrite artifacts or increment the released appcast independently of
its verified DMG. The terminal install script is a legacy path; direct users to
the signed/notarized DMG. An appcast signing failure blocks publishing.

Bundle identity is `com.ivan.hago` (0.2.0, build 2). Before loading settings,
legacy `local.hago.app` preferences are copied once, preserving any already-set
new-domain values and leaving the old domain intact. The database path is
unchanged. macOS treats the new bundle identity as a new privacy principal:
Accessibility/Automation grants must be requested normally. Login registration
may need re-registration after changing identity; never silently enable it.

New permanent preference tests protect against an upgrade resetting user choices
or an interrupted onboarding losing stable rule identities. Broader presentation
and packaging checks remain temporary rather than adding brittle UI tests.
