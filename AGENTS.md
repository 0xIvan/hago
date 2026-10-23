# Hago Agent Instructions

## Project
- Work in this repo: `/Users/ivan/code/hago`.
- Do not use the Codex thread folder for Hago source changes.
- Hago is a native macOS menu bar app built with SwiftPM in the Hago source repository.
- The installed local app is `/Applications/Hago.app`.
- The local SQLite database is `~/Library/Application Support/Hago/hago.sqlite`.
- The app is fully local; do not add remote analytics, sync, or telemetry unless explicitly requested.

## Verification and Install
- For app source changes, completion includes testing, reinstalling, and reopening the local app. Do not wait for a separate install request.
- After code changes, run `swift test`.
- After tests pass, run `scripts/install-app.sh` so the app in `/Applications` is replaced and reopened.
- `scripts/install-app.sh` validates a stable signing identity, packages and signs a release app, then quits and replaces the installed app and opens it. It preserves the installed certificate, supports the legacy `Worklog Local Code Signing` certificate, and refuses ad hoc signing. Use `--check-signing` to validate without installing.
- Generated artifacts such as `.build/` and `outputs/` are ignored; clean them after commit/push with `rm -rf .build outputs`.
- If a change is documentation-only, tests and reinstall are not required; say that clearly.

## Git
- Remote: `git@github.com:0xIvan/hago.git`.
- Main branch: `main`.
- Commit messages should match the existing concise style, for example `Make report panels fill width`.
- Do not add co-author tags.
- After verifying authorized app changes, commit, push, and publish through the release workflow by default. Follow the release through successful publication unless the user explicitly limits the task to local work, review, or planning.
- If unrelated uncommitted changes exist, do not overwrite or revert them. Work around them and mention them.

## Product Rules
- Hago day starts at local 4am.
- Review should represent the full review backlog, not just today.
- Review classification should create/reuse remembered rules and reclassify all history so review can move toward zero.
- Activity is the editable raw activity surface.
- Overview is the current day/current week snapshot.
- Reports is the historical weekly/monthly comparison surface.
- Reports should not show a standalone Review KPI card; review time can remain in charts and total.
- Menu bar title shows work time and total tracked time for today.

## Data and Privacy
- Avoid destructive local database operations unless explicitly requested.
- For local DB inspections, use read-only `sqlite3` queries when possible.
- Incognito/private browser activity and ignored rules should not be persisted as normal activity.
- Keep local user data, generated app bundles, and build outputs out of commits.
