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

Install and sign in to at least one supported CLI, then select it under
**AI Harness** in Hago. A custom executable path is available for CLIs that are
not on the login-shell `PATH`. Hago lists models reported by Codex and Pi, and
uses stable current-model aliases for Claude Code. The settings show a
recommended model and the reasoning levels supported by that model. Users can
also enter a custom model ID or keep the CLI default.

Review analysis can be stopped from the Review screen. Stopping terminates the
active CLI process and does not apply incomplete output.

Choose **AI Harness → Profession** to set your professional role. The selected
profession informs manual and scheduled analysis through internal guidance;
only the selector is shown in the interface. Changing the profession makes
saved recommendations eligible for a new analysis. Existing rules and manual
classifications are not rewritten.

### Scheduled Review

Enable **AI Harness → Scheduled Review** to run every two hours while Hago is
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
changed Review groups. Recommendations and evidence fingerprints are saved
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

Download the latest `Hago.app.zip` from [GitHub Releases](https://github.com/0xIvan/hago/releases/latest), unzip it, and move `Hago.app` to `/Applications`.

You can also install the latest release from Terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/0xIvan/hago/main/scripts/install-release.sh | bash
```

Release notes indicate whether a build is notarized. The release workflow is configured for Developer ID signing and notarization once the required Apple secrets are added. Older ad hoc signed releases may require right-clicking `Hago.app` and choosing `Open` on first launch.

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

GitHub Releases are created automatically when a version tag is pushed:

```sh
git tag v0.1.0
git push origin v0.1.0
```

After the required secrets are configured, the release workflow runs tests, packages `Hago.app`, Developer ID signs it, submits it to Apple's notary service, staples the notarization ticket, zips it, writes a checksum, and uploads both files to the GitHub release.

### Release Secrets

Notarized GitHub releases require these repository secrets:

```text
APPLE_CERTIFICATE_BASE64
APPLE_CERTIFICATE_PASSWORD
APPLE_ID
APPLE_TEAM_ID
APPLE_APP_SPECIFIC_PASSWORD
```

`APPLE_CERTIFICATE_BASE64` must be a base64-encoded `.p12` export of a Developer ID Application certificate:

```sh
base64 -i DeveloperIDApplication.p12 | pbcopy
```

`APPLE_APP_SPECIFIC_PASSWORD` is an app-specific password for the Apple ID used with the notary service.

If any release secret is missing, tag-triggered release builds fail instead of publishing an unnotarized app.

## Defaults

The app ships with editable default categories and rules for common work, personal, review, and privacy cases. Users can add, remove, or edit rules, projects, categories, and ignore patterns in the app.

## License

MIT
