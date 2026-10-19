# Plan 001: Add local AI harness selection and safe Review automation

> **Executor instructions**: Follow this plan in order. Stop at each decision
> checkpoint until the product owner approves the recommended direction. Do not
> commit, push, or publish a release unless the product owner asks.
>
> **Drift check (run first)**:
> `git diff --stat 2b2b453..HEAD -- Sources/Hago Sources/HagoCore Tests/HagoCoreTests Package.swift`
> If the Review AI or settings code changed, compare the current implementation
> with this plan before work starts. Stop if the provider protocol, persistence
> model, or Review flow changed in a way that invalidates this plan.

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MED
- **Depends on**: none
- **Category**: implemented
- **Planned at**: commit `2b2b453`, 2026-09-01
- **Reference reviewed**: T3 Code commit `0947c30e6946b2ad6d6cd518fd44292e75e834e8`
- **Implemented**: 2026-09-01; scheduled analysis remains deferred

## Outcome

Hago detects supported AI command-line harnesses installed on the Mac and shows
them in an in-app selector. A selected harness receives grouped Review data,
returns one versioned JSON result, and cannot directly change Hago data. Hago
validates the result, applies only approved very-high-confidence Work or
Personal rules, and leaves all other recommendations for the user. Every
automatic change has an audit record and a safe Undo action.

## Decisions to approve

These are the course-change points. The recommended choice is stated first.

1. **Supported harnesses**: Replace Ollama and the user-facing local heuristic
   provider with Codex, Claude Code, and Pi. Keep Disabled as the only non-CLI
   state. Do not add Cursor, Grok Build, or OpenCode until the common adapter
   contract is proven.
2. **Automatic recognition**: Use a known harness catalog. Repair the macOS GUI
   `PATH`, resolve each known command, and run `--version` with a short timeout.
   Do not scan the full disk. Permit an advanced custom binary path.
3. **Selection behavior**: Detect all harnesses, but do not silently switch
   between them. Persist the user's selected harness. If it becomes
   unavailable, stop analysis and show a clear recovery action. Do not use a
   heuristic or another provider as a hidden fallback.
4. **Privacy disclosure**: Before the first Codex, Claude, or Pi run, state that
   a local CLI can still send activity titles and URLs to its configured cloud
   model. Require one explicit confirmation per selected harness.
5. **Automatic application**: Use `0.95` as a separate auto-apply threshold.
   Auto-apply only Work and Personal decisions whose Hago-owned rule condition
   passes all safety checks. Keep Ignored and Unsure manual. Limit one run to at
   most 10 new rules.
6. **Manual application**: A human Work or Personal choice must not be blocked
   by the model confidence. Separate rule-safety validation from confidence
   policy. The current `0.75` threshold can remain a recommendation quality
   indicator, but it must not override a direct human decision.
7. **T3 Code reuse**: Port the small discovery pattern into Swift. Do not add a
   runtime dependency on T3 Code. If implementation copies a substantial code
   portion instead of only the design, preserve its MIT copyright and license
   notice.
8. **Model selection**: Keep the CLI default available, list current Codex and
   Pi models from their local catalogs, and use current-model aliases for
   Claude Code. Show one recommended model, support a custom model ID, and
   expose only reasoning levels supported by that model. Persist each choice
   per harness.
9. **Ollama removal**: Delete the Ollama HTTP provider, request and response
    types, environment settings, prompt mapper, and Ollama-specific tests. Do
    not retain a compatibility path after the CLI adapters are working.

## Current state

- `Sources/HagoCore/ReviewAISuggestions.swift:146-202` defines one provider
  protocol and currently selects Ollama, local heuristics, or disabled state
  from process environment variables. This configuration will be replaced, not
  extended.
- `Sources/HagoCore/ReviewAISuggestions.swift:309-349` contains an
  Ollama-specific prompt even though the core Review contract is provider
  independent.
- `Sources/HagoCore/ReviewAISuggestions.swift:767-838` combines rule safety and
  the `0.75` confidence threshold in one validator.
- `Sources/Hago/AppState.swift:30-43` constructs one immutable provider at app
  startup, so a UI selection cannot change the provider at runtime.
- `Sources/Hago/AppState.swift:229-279` runs analysis manually and applies one
  suggestion at a time.
- `Sources/Hago/DashboardView.swift:92-159` exposes Analyze Review and the
  recommendation list, but no harness status, auto-apply summary, or Undo.
- `Sources/HagoCore/HagoStore.swift:421-445` validates, creates or reuses a
  remembered rule, and reclassifies history. It returns only a rule ID, so it
  cannot tell Undo whether the rule was new, reused, or re-enabled.
- `Sources/HagoCore/HagoStore.swift:992-1038` excludes manual classifications
  from reclassification. This is the correct base for safe Undo.

## T3 Code pattern to port

Use the following pinned source as a reference, not as a new dependency:

- [`apps/server/src/os-jank.ts`](https://github.com/pingdotgg/t3code/blob/0947c30e6946b2ad6d6cd518fd44292e75e834e8/apps/server/src/os-jank.ts)
  repairs `HOME` and merges a login-shell or `launchctl` `PATH` with the app's
  inherited `PATH`.
- [`packages/shared/src/shell.ts`](https://github.com/pingdotgg/t3code/blob/0947c30e6946b2ad6d6cd518fd44292e75e834e8/packages/shared/src/shell.ts)
  uses a bounded login-shell command, output markers, path de-duplication, and
  executable resolution.
- [`providerSnapshot.ts`](https://github.com/pingdotgg/t3code/blob/0947c30e6946b2ad6d6cd518fd44292e75e834e8/apps/server/src/provider/providerSnapshot.ts)
  models installed, version, health, authentication, timeout, and command-not-
  found states separately.
- [`CodexProvider.ts`](https://github.com/pingdotgg/t3code/blob/0947c30e6946b2ad6d6cd518fd44292e75e834e8/apps/server/src/provider/Layers/CodexProvider.ts)
  and [`ClaudeProvider.ts`](https://github.com/pingdotgg/t3code/blob/0947c30e6946b2ad6d6cd518fd44292e75e834e8/apps/server/src/provider/Layers/ClaudeProvider.ts)
  show bounded health probes and useful missing, timed-out, unauthenticated, and
  failed-to-run states.

Hago should omit T3 Code's app-server sessions, model catalog, skill discovery,
provider updates, and multi-account machinery. They do not help one-shot Review
classification.

## Process safety policy

Keep all controls, but present them as four implementation groups:

1. **Data boundary**: Send only the versioned prompt and grouped Review payload
   through stdin. Never pass the database path, raw SQL, rule IDs, or commands.
2. **Execution boundary**: Use `Foundation.Process` with an executable URL and
   argument array. Do not invoke `/bin/sh -c`. Run in an empty temporary
   directory. Use the strongest no-tools or read-only flags the harness offers.
3. **Resource boundary**: Apply a timeout, output byte limit, concurrent stdout
   and stderr draining, and forced termination on breach.
4. **Session boundary**: Disable session persistence, project instructions,
   plugins, skills, extensions, hooks, MCP servers, and browser integrations
   where the harness supports these controls.

These controls add almost no runtime cost. The real costs are launching the CLI,
model latency, and payload size. Cache discovery at app launch and on manual
Refresh. Do not probe every harness before every Review run.

## Commands and provider profiles

The executor must confirm flags against the installed CLI versions before
implementation. The current machine reported Codex `0.147.0`, Claude Code
`2.1.241`, and Pi `0.84.2` on 2026-09-01.

- **Codex**: `codex exec` with stdin, `--ephemeral`, `--sandbox read-only`,
  `--ignore-user-config`, `--ignore-rules`, `--skip-git-repo-check`, and
  `--output-schema <temporary-schema-file>`. Read the final JSON from stdout.
- **Claude Code**: `claude -p` with stdin, `--output-format json`,
  `--json-schema <schema>`, `--no-session-persistence`, `--safe-mode`,
  `--tools ""`, `--disable-slash-commands`, and `--no-chrome`. Do not use
  `--bare`, because it disables normal OAuth and keychain authentication.
- **Pi**: `pi -p` with stdin, `--mode json`, `--no-session`, `--no-tools`,
  `--no-extensions`, `--no-skills`, `--no-prompt-templates`,
  `--no-context-files`, and `--no-approve`. Pi does not expose a JSON Schema
  flag, so Hago must validate its decoded JSON strictly.

Use a minimal environment that preserves `HOME`, the repaired `PATH`, locale,
temporary-directory values, and only the selected harness's documented config
or authentication variables. Do not read general secrets from shell startup
output. The login shell probe is for `PATH` only.

## Canonical Review contract

Replace the Ollama-specific prompt, payload, response, and schema with one
harness-independent contract. The model output must have this shape:

```json
{
  "schemaVersion": 1,
  "decisions": [
    {
      "groupID": "host|equals|example.com",
      "kind": "work",
      "confidence": 0.97,
      "reason": "Development documentation"
    }
  ]
}
```

Hago, not the model, owns the proposed rule condition. Reject an unsupported
schema version, invalid JSON, extra fields, unknown or duplicate group IDs,
missing group IDs, invalid kinds, non-finite or out-of-range confidence, reasons
over the size limit, and output over the byte limit. Treat all activity text as
untrusted prompt content and state in the prompt that it is data, not
instruction.

## Scope

Expected in-scope files are:

- `Sources/HagoCore/ReviewAISuggestions.swift`
- `Sources/HagoCore/HagoStore.swift`
- `Sources/Hago/AppState.swift`
- `Sources/Hago/DashboardView.swift`
- `Sources/Hago/HagoSection.swift`
- `Sources/Hago/SettingsView.swift`
- focused new Swift files under `Sources/HagoCore/` and `Sources/Hago/`
- focused tests under `Tests/HagoCoreTests/`
- `Package.swift` only if schema resources or a new test target require it
- `README.md` for the local-CLI privacy and setup disclosure

Out of scope:

- distribution, notarization, billing, telemetry, remote sync, hosted AI, or
  scheduled/background Review analysis
- general-purpose agent sessions or allowing a harness to edit files
- direct database access by any AI CLI
- changes to the 4am day boundary or activity tracking behavior
- T3 Code provider updates, model browsing, skills, or multi-account features

## Implementation stages

### Stage 1: Define settings, discovery, and status models

Add a stable `ReviewAIHarnessKind`, persisted settings, display metadata, and
status values such as available, missing, failed, and timed out. Add a known
catalog for Codex, Claude Code, and Pi. Port the bounded macOS `PATH` hydration
and executable-resolution behavior. Probe candidates concurrently with
`--version`, cache the result, and support Refresh plus an advanced custom path.

**Verify**: Focused unit tests cover Finder-like `PATH`, login-shell precedence,
duplicate path removal, the current `~/.local/bin` and NVM-style paths, custom
paths, missing commands, non-zero exit, and timeout.

**Decision checkpoint A**: Review the harness list, status wording, default
selection rule, and custom-path UI before any activity data is sent to a CLI.

### Stage 2: Add the harness selector UI

Add an AI Review settings surface that shows each known harness, resolved path,
version, availability, selected state, and Refresh/Test controls. Keep the
Review screen focused on analysis results; show the active harness there as a
compact status and link to settings. Persist selection and the one-time privacy
confirmation. A missing selected harness must produce a clear action, not an
automatic cloud-provider switch.

**Verify**: Unit-test selection fallback and persistence. Manually launch Hago
from Finder and confirm Codex, Claude Code, and Pi are detected on this Mac.

### Stage 3: Build one bounded process runner and adapter contract

Add one reusable process runner that enforces the four safety-policy groups.
Inject it into provider adapters so tests use fixture executables instead of
real AI calls. Add provider profiles that contain executable, arguments,
environment policy, output envelope behavior, and capability flags. Keep all
provider-specific flags out of `AppState` and SwiftUI views.

**Verify**: Fixture-process tests prove stdin delivery, empty working directory,
direct process launch without a shell, environment filtering, concurrent output
drain, timeout termination, output-limit termination, and cleanup.

### Stage 4: Extract the canonical prompt and implement adapters

Create one versioned Review prompt and response schema. Send the grouped backlog
to the selected Codex, Claude Code, or Pi adapter. Decode each harness envelope
into the same Hago decision type, then run one strict provider-independent
validator. Remove the Ollama provider and the local heuristic provider after
the CLI contract tests pass.

**Verify**: Contract fixtures for all providers produce identical decisions.
Malformed, partial, duplicate, stale, oversized, and prompt-injection-shaped
fixtures fail safely and never reach the store.

**Decision checkpoint B**: Run recommendation-only analysis on a representative
copy of the current backlog. Review accuracy, latency, data disclosure, and
failure messages for each installed harness before enabling automatic changes.

### Stage 5: Split human validation from auto-apply policy

Refactor `ReviewAISuggestionValidator` into rule-safety validation plus separate
recommendation and auto-apply policies. Human Work or Personal corrections can
apply any safe rule condition. Automatic application requires confidence at or
above `0.95`, Work or Personal, an exact or otherwise approved narrow condition,
a current Review match, no higher-priority conflict, and the per-run rule cap.
Recheck freshness immediately before each apply because earlier rules can make
later decisions stale.

**Verify**: Boundary tests cover `0.949` versus `0.95`, human override below
`0.75`, browser-wide rule rejection, stale decisions, priority conflicts,
Ignored and Unsure, and the 10-rule cap.

### Stage 6: Add audit records and Undo before auto-apply

Add small SQLite tables for Review AI runs and decisions. Store provider kind,
provider version, schema version, timestamps, counts, disposition, confidence,
reason, rule ID, and whether the rule was new, reused, or re-enabled. Do not
store the raw prompt or repeat full activity titles and URLs in the audit log.
Make rule application transactional and return enough prior state for Undo.
Undo must delete only rules created by that run, restore reused rule state when
needed, and reclassify only non-manual activity using the remaining rules.

**Verify**: Store tests cover new, reused, and re-enabled rules; partial failure
rollback; idempotent Undo; preserved manual classifications; and correct
reclassification after Undo.

**Decision checkpoint C**: Review an auto-apply preview that lists what would be
applied and why. Approve the threshold, rule cap, and whether the setting is off
by default or enabled after the first privacy confirmation.

### Stage 7: Complete product verification

Run focused tests during each stage, then the full repository workflow:

1. `swift test` must pass.
2. `git diff --check` must pass.
3. `scripts/install-app.sh` must build, replace, and reopen
   `/Applications/Hago.app`.
4. Launch the installed app from Finder and confirm harness discovery.
5. Test one recommendation-only run for each installed harness.
6. With a temporary test database, test one auto-apply and Undo cycle. Do not
   use the user's live Hago database for destructive verification.
7. Confirm that no CLI receives a database path and no audit row stores the raw
   prompt.

## STOP conditions

Stop and report instead of improvising if:

- a supported CLI cannot run non-interactively without write or shell tools;
- normal CLI authentication requires importing arbitrary shell secrets;
- strict structured output cannot be obtained or validated for a provider;
- removing Ollama would leave no tested CLI adapter able to analyze Review;
- Undo would need to change manual classifications or delete a pre-existing
  human rule;
- the implementation requires giving an AI CLI the Hago database path;
- the installed app cannot detect the same harness that the login shell finds;
- T3 Code source reuse becomes substantial enough to require a licensing
  decision that the product owner has not approved.

## Maintenance notes

- Keep provider arguments in separate profiles because CLI flags change over
  time. A failed health check must show the detected version and action.
- Keep the response schema versioned. A prompt change that changes semantics
  requires contract fixtures and an explicit schema or prompt version update.
- Add new harnesses only after they meet the same discovery, no-tools,
  ephemeral-session, strict-output, timeout, and output-limit contract.
- Review false-positive and Undo rates before lowering the auto-apply threshold
  or increasing the per-run rule cap.
