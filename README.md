# Hago

Hago is a local macOS menu bar app for tracking active-window time and reviewing how the day was spent.

## What It Tracks

- frontmost app name
- active window title
- Chrome active tab URL and title when Apple Events permission is granted
- reading and watching time, even without keyboard or mouse input

Recording checkpoints are saved every five seconds while tracking. Quitting
normally flushes the current interval. Sleep, display sleep, screen lock,
switching away from the user session, and explicit pause stop recording. Long
observation gaps are not counted as continuous activity. After a restart, Hago
starts a new interval rather than extending the previous one across downtime.

An unattended Mac that stays awake and unlocked can continue recording. In
**Activity → Individual**, use an activity's clock button (**Edit Time**)
to remove an entire interval, trim an edge, or remove a middle range. The
remaining time retains its classification. Time removal is permanent.

Use **Pause Tracking** in the menu bar panel or **Privacy → Tracking**. The same
settings panel offers **Open at Login**, which is off unless the user enables
it; Hago shows macOS approval requirements or registration errors.

Chrome incognito windows are detected before tab URL/title collection and treated as private/ignored.

## Local Storage

Hago stores data locally in SQLite:

```text
~/Library/Application Support/Hago/hago.sqlite
```

Hago does not operate a server. The optional AI Review feature can send grouped
Review activity to the AI service configured in a local CLI, but only after the
user selects that CLI and confirms the disclosure in the app.

Ignored activity is not persisted as detailed activity rows.

## AI Review

Hago detects supported local AI CLIs in the macOS login-shell `PATH`:

- Codex
- Claude Code
- Pi

The selected CLI receives grouped Review data through standard input; Hago does
not include the database path in that input. Each run uses an empty temporary
working directory, a limited environment, CLI flags that restrict or disable
tools, an output limit, a strict timeout, and an ephemeral session when supported.
These settings do not isolate the child process: the selected CLI runs with the
user account's ordinary filesystem permissions, so use a CLI you trust.

AI Review is recommendation-only by default. Users can opt in to automatic
application of safe Work or Personal rules with confidence of 95% or higher.
Hago applies at most 10 such rules per run, records an audit entry, and provides
Undo. Ignored, Unsure, low-confidence, stale, and unsafe results remain for
manual review.

For a CLI connection, install and sign in to a supported CLI, then select it under
**AI suggestions** in Hago. A custom executable path is available for CLIs that are
not on the login-shell `PATH`. Hago lists models reported by Codex and Pi, and
uses stable current-model aliases for Claude Code. The settings show a
recommended model and the reasoning levels supported by that model. Users can
also enter a custom model ID or keep the CLI default.

Review analysis can be stopped from the Review screen. Stopping terminates the
active CLI process or direct HTTP request and does not apply incomplete output.

Choose **AI suggestions → Profession** to set your professional role. The selected
profession informs manual and scheduled analysis through internal guidance;
only the selector is shown in the interface. Changing the profession makes
saved recommendations eligible for a new analysis. Existing rules and manual
classifications are not rewritten.

### Scheduled Review

Enable **AI suggestions → Scheduled Review** to run every two hours while Hago is
open and the Mac is awake. The interval can be one, two, four, or 24 hours.
After sleep, Hago makes one catch-up run if due; it does not replay missed
intervals. On launch, an overdue run waits one interval before running. An
interrupted run also waits one interval before retrying.

Scheduled application is a separate setting and is off by default. Start with
saved recommendations, then enable automatic application when ready. The same
95% confidence threshold, ten-rule limit, audit, and Undo apply. Existing manual
choices, project assignments, and classified activity are protected. Rule
consolidation remains a separate manual action.

Each run first checks existing rule coverage, then analyzes up to 50 new or
changed Review groups for CLI connections, or 20 for direct providers. Recommendations and evidence fingerprints are saved
locally. Counts and elapsed time alone do not cause another AI call. Changed
sample evidence, related rules, model, or reasoning can cause a new analysis.
Enabling automatic application rechecks saved advice without another AI call.
Manual **Analyze Review** can explicitly reconsider unchanged groups.

Use **Run Now**, **Pause Schedule**, or **Stop** in Scheduled Review. Manual and
scheduled runs cannot overlap. Last/next run times and the result remain visible
there. Three consecutive failures also show a warning in the menu bar panel;
normal background checks do not show popups or request system permissions.

## Permissions

Hago may request:

- Accessibility permission, used to read active window titles.
- Automation/Apple Events permission for Chrome, used to read the active tab URL and title.

Without Accessibility permission, app-level tracking remains available but
classification is less specific. Chrome recording requires a successful
Automation response: if Chrome's private-window status cannot be established,
Hago skips that observation instead of storing a potentially private window title.

Accessibility access is checked silently at startup and while tracking. If it is
missing, use **Privacy → Accessibility → Grant Access**. Hago does not request
access again when macOS reports that it is already granted.

## Build

```sh
swift test
swift build -c release --product Hago
```

## Download And Install

Download the universal DMG from [GitHub Releases](https://github.com/0xIvan/hago/releases/latest), open it, and drag Hago to Applications. Release apps and DMGs are Developer ID signed and notarized. Requires macOS 14 or newer on Apple Silicon or Intel.

Choose **Hago → Check for Updates…** in the app menu, or select **Tracking & Updates** in Hago's sidebar. **Hago → Settings…** (⌘,) opens that section in the same window. Sparkle verifies the signed update feed and download before asking to install. Checks are manual; activity and profile data are never sent to the release service.

The optional Terminal installer verifies the release checksum, bundle identity, signing team, notarization ticket and Gatekeeper assessment before replacing the installed app:

```sh
curl -fsSL https://raw.githubusercontent.com/0xIvan/hago/main/scripts/install-release.sh | bash
```

## Local Package And Install

```sh
scripts/install-app.sh
```

The install script packages the app, signs it, replaces `/Applications/Hago.app`, and opens Hago.

The installer preserves the installed app's signing certificate. On the first
signed install, it looks for `Hago Local Code Signing`, then the existing
`Worklog Local Code Signing` certificate from before the rename. The certificate
label does not change the app's name. Override the certificate with:

```sh
HAGO_CODE_SIGN_IDENTITY="Your Identity Name" scripts/install-app.sh
```

If no unique valid identity is found, installation stops without changing the
installed app. Ad hoc signing is not allowed: a changing code identity can cause
macOS to request permissions again after each update. Moving from an older ad hoc
build to the stable signature may require one new permission approval.

Run `scripts/install-app.sh --check-signing` to check the certificate without
building, installing, or opening Hago.

## Releasing

Hago uses the same automatic release flow as Uso:

1. A push to `main` runs script/metadata validation and `swift test`.
2. Once checks pass, the auto-release job bumps the patch version and integer build number, atomically pushes the version commit and tag, and explicitly dispatches the release workflow. Superseded pushes are skipped.
3. Release CI reruns tests, builds both architectures, Developer ID signs the app and Sparkle helpers, notarizes/staples the app and DMG, and checks Gatekeeper.
4. It signs the Sparkle appcast with Hago's own key and verifies the signature against the public key shipped in the app.
5. CI uploads everything to a draft release, then publishes it and updates the latest-download/feed URLs. Published versions cannot be overwritten; both version and build must increase.

`HAGO_AUTO_RELEASE=true` in repository Actions variables enables automatic releases. Set it to `false` to pause them without disabling checks. Pull requests never publish or access signing secrets.

For a candidate without creating a public release, dispatch **Release** on `main`:

```sh
gh workflow run release.yml --ref main
```

For an explicit patch/minor/major version, run from a clean checkout matching the remote default branch:

```sh
scripts/release.sh --dry-run
scripts/release.sh minor
```

Manual version tags trigger the same verified release pipeline. Source versions are authoritative; the tag must match `Resources/Info.plist`. The appcast lives at `https://github.com/0xIvan/hago/releases/latest/download/appcast.xml` and points to the immutable versioned DMG.

### Release Secrets

Hago's repository owns these Actions secrets:

```text
APPLE_CERTIFICATE_BASE64
APPLE_CERTIFICATE_PASSWORD
APPLE_ID
APPLE_TEAM_ID
APPLE_APP_SPECIFIC_PASSWORD
SPARKLE_PRIVATE_KEY
```

The Apple secrets belong to the existing Developer ID/notary account. The update key is Hago-specific and must match `SUPublicEDKey`; do not substitute Uso's or mac-mirrorly's update key. Local Keychain retains the recovery copy under `hago-sparkle`. CI uses an ephemeral signing keychain and removes imported certificate material after every run. Never print or commit credential values.

See [distribution qualification](plans/release-qualification.md) for validation boundaries.

## Defaults

**Rules** contains both **Specific Rules** and **Work Defaults**. More specific site, title, and project rules take precedence over whole-app defaults. Ignore rules always win; manual corrections are preserved. Projects and Categories remain available under **Advanced** in the sidebar.

The app ships with editable default categories and rules for common work, personal, review, and privacy cases. Users can add, remove, or edit rules, projects, categories, and ignore patterns in the app.

## License

MIT

### Optional direct AI providers

AI suggestions supports Anthropic and OpenAI without installing a CLI. Choose a
provider, save your own API key in macOS Keychain, and explicitly accept the data
disclosure before analysis. Provider API usage is billed separately; Hago never
retries against another model or provider automatically. Disconnect removes the
selected provider key and disables sharing and scheduling. Existing CLI choices,
consent, and schedules are preserved. Model/reasoning controls live under Advanced.

Starting models verified against official documentation on 2026-10-22:
[Claude Haiku 5.5](https://platform.claude.com/docs/en/models/haiku-5-5/migration-guide)
and [GPT-5.6 Terra](https://developers.openai.com/api/docs/models/gpt-5.6-terra).
These are starting recommendations, not a measured Hago accuracy benchmark.
Custom model IDs must support the selected provider's text/JSON API.

Direct requests include at most 20 Review groups with 3 samples per group.
App identities, domains, group counts/minutes, profession and relevant rule
labels/values are sent; full URLs and original group IDs are not. Window titles
are withheld by default. Optional titles are shortened and common secret patterns
are redacted, but can still contain sensitive text; inspect the disclosure before
enabling them. Free-text profile answers are not shared. Responses are bounded,
validated, audited and applied through the existing opt-in/undo flow. Tracking
continues locally on provider failures. No live paid API call was used to verify
this implementation; transport fixtures cover privacy and failure handling.
