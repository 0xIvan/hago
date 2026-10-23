# Hago distribution qualification

The Hago repository now owns the six release secrets required by its CI: the
five Apple signing/notary credentials and Hago's own Sparkle private key. The
private update key also remains recoverable in local Keychain under account
`hago-sparkle`; its public key is in Info.plist. These secrets were explicitly
provisioned for the automatic release pipeline. Normal Hago releases no longer
run through a temporary Uso packaging branch.

Successful main checks automatically bump/tag/dispatch when the repository
variable `HAGO_AUTO_RELEASE` is `true`. Tag builds publish only after testing,
universal packaging, notarization and appcast verification. Manual dispatch on
main produces candidate artifacts without publishing. Published releases cannot
be overwritten, older versions/builds are rejected, and release jobs serialize.
Local installs retain the installed certificate; distribution uses Developer ID.

1. Normal releases follow main checks, an atomic version/build bump plus tag,
   and explicit tag dispatch. Hago's own CI signs/notarizes and publishes after
   verification. Use `HAGO_AUTO_RELEASE=false` to pause this flow.
2. Dispatch Release on main to build a candidate without publishing. Source
   version/build in Resources/Info.plist are authoritative. Candidate artifacts
   include a universal DMG/ZIP, signed appcast, final checksums and notary receipt.
3. For a local/emergency package, build with HAGO_ARCHS="arm64 x86_64", notarize
   and staple the app before packaging, then notarize/staple the DMG. Regenerate
   checksums after stapling. A locally signed DMG without these tickets is not a
   notarized release. Local appcast signing uses the Hago Keychain account.
4. Appcast verification checks version, build, immutable download URL, archive
   length and Ed25519 signature against the public key shipped in the app.
   Never substitute another app's key. Publishing fails closed on a mismatch.
5. Exercise update discovery with an older/current host and a failed endpoint;
   then qualify an actual interactive update install. A successful SDK probe is
   not proof of the installation, relaunch and permission-continuity UI.
6. Verify a fresh downloaded install under Gatekeeper, permissions, login choice,
   database migration/backup recovery and tracking after real sleep/lock/login.
   Build and notarization success alone do not establish these behaviors.

Do not overwrite artifacts or increment the released appcast independently of
its verified DMG. The terminal install script is a legacy path; direct users to
the signed/notarized DMG. An appcast signing failure blocks publishing.

Bundle identity has been `com.ivan.hago` since 0.2.0, build 2. Before loading settings,
legacy `local.hago.app` preferences are copied once, preserving any already-set
new-domain values and leaving the old domain intact. The database path is
unchanged. macOS treats the new bundle identity as a new privacy principal:
Accessibility/Automation grants must be requested normally. Login registration
may need re-registration after changing identity; never silently enable it.

New permanent preference tests protect against an upgrade resetting user choices
or an interrupted onboarding losing stable rule identities. Broader presentation
and packaging checks remain temporary rather than adding brittle UI tests.

## Pipeline qualification — 2026-10-23

- Hago CI check run https://github.com/0xIvan/hago/actions/runs/39915797280
  passed on source `367f5ba`. All 148 tests pass locally and in CI. A strict
  capture in Accessibility notification refresh was made compatible with the
  older CI Swift compiler without changing permission behavior.
- Candidate run https://github.com/0xIvan/hago/actions/runs/39915805860 passed
  with Hago's own six signing secrets: both architectures built, app and DMG
  accepted by Apple, tickets stapled, Gatekeeper accepted, appcast signed and
  verified, candidate artifacts saved, temporary signing material removed.
  Both publication steps were correctly skipped on dispatch from main.
- Downloaded candidate checksums and appcast signature verify locally; DMG
  Gatekeeper assessment reports Notarized Developer ID. No local database or
  activity records are included in release assets.
- Temporary Sparkle SDK probes using isolated bundle identifiers and a local
  copy of the signed candidate feed produced update available for build 1,
  up to date for build 2, and an error for an unreachable endpoint. They did
  not show or install updates, access the activity DB, or alter Hago settings.
- Temporary Git fixtures verified dry run, dirty/stale checkout refusal,
  nonincreasing version refusal, and the atomic default-branch/tag push.
  Installer fixtures preserved the previous app on checksum/signature failures.
  Workflow lint, shell checks and source diff checks pass.
- Automatic main releases are enabled only after this candidate qualification.
  Public delivery is subsequently verified against the live latest-feed URL,
  immutable release download, checksum and the app's bundled trust key.
- Native UI control timed out; interactive Sparkle installation and full
  fresh-machine/Intel runtime/real login or sleep transitions remain separate
  app qualification. Universal compilation is not an Intel runtime test.
