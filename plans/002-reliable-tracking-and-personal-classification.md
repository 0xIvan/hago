# Plan 002: Reliable tracking and personal classification

## State and intended outcome

- Blueprint prepared 2026-10-22 at `e403e24af6f27a2d98acaea53f03ef1a19999d06`.
- Checkout was clean before blueprint preparation. Milestone A is implemented;
  verification evidence and remaining actual-system checks are recorded below.
  Milestone A committed/pushed as `54c2622`. Milestones B–E and the F packaging/update implementation have been integrated
  from isolated execution worktrees. Installed-app and distribution qualification
  remain in progress; implementation alone is not production qualification.
- Priority P0. Multi-stage effort; recording and migration changes carry high
  data-integrity risk. Individual stages should remain independently usable.
- Audience: people who want to track their time and understand their work habits.
  Freelancers are a useful future audience, not the first priority. Project
  assignment is a future extension; billing, team monitoring, and productivity
  scoring are out of scope for this revision.
- Promise: reliable computer time tracking within observable system boundaries,
  including reading and watching without input, mostly categorized without
  intervention. Users can repair unattended time in Activity when a Mac stayed
  awake and unlocked. Do not promise gaze or exact presence detection.
- Primary success criterion: users trust the record and spend progressively less
  time correcting it. Accuracy takes precedence over coverage and clearing Review.
- This is an evolution of Hago, not a second app or a database replacement.

## Decisions

1. Recording reliability precedes expanded classification and onboarding.
2. Keep local SQLite storage, the native macOS app, and existing reports.
3. Keep Work and Personal as purpose labels. Unresolved is uncertainty, not
   Personal and not evidence of wasted time. Keep the persisted `review` value
   initially for compatibility; present it as Needs review everywhere.
4. Presets provide defaults. Explicit user choices override defaults.
5. One correction changes selected records. Remembering a rule is a separate,
   explicit action; repeated corrections may suggest one but never silently
   create a broad rule.
6. Core recognition and basic correction learning work offline without AI.
   Offer optional direct connection to a user's preferred AI provider and model,
   with curated recommendations. Existing CLI integrations remain supported;
   installing a CLI must not be required for enhanced categorization.
7. Do not expand project features. Preserve existing assignments and access.
8. Start with General Work and Software Development presets. Add other roles
   after the complete correction loop works. Users may select multiple packs.
9. Keep the local 4am day boundary and full historical Review backlog.
10. Keyboard/mouse inactivity alone must not stop tracking. Reading and watching
    count automatically. Sleep, lock, shutdown and explicit pause stop tracking.
    An unattended Mac that stays awake and unlocked may continue tracking; users
    correct it in Activity. No speculative presence-detection subsystem.
11. Onboarding learns the user's roles, work contexts and mixed-use tools;
    a profession selector alone is insufficient. Make optional steps skippable.

## Requirements confirmed in conversation

The user does not need to approve this document line by line. These requirements
supersede the earlier input-idle policy in the first blueprint draft:

- Time tracking for individuals is the primary job; project assignment comes later.
- Basic learning is automatic and local; AI enhances rules and categorization,
  with insights a future extension rather than part of the first implementation.
- Users can choose a provider/model; Hago recommends suitable verified options.
- Reading and video watching are tracked without keyboard or mouse activity.
- Stop at sleep, lock, shutdown and pause; allow manual repair of unlocked absence.
- Personal onboarding should improve initial classification.

"Eyes on the screen" describes why reading and watching count, not a gaze sensor.
Do not introduce camera recording, presence inference or return-time prompts.
An awake/unlocked screen or playing video is not proof of presence; acknowledge
that limit and provide straightforward Activity edits instead of overpromising.

## Current code evidence

| Area | Existing implementation and implication |
|------|-----------------------------------------|
| Recording | `Sources/Hago/AppState.swift`, `startTracking`, `tick`, `finalizeActiveDraft`: five-second polling, in-memory draft, save at context change/idle, no periodic save of unchanged context. |
| Lifecycle | `Sources/Hago/AppDelegate.swift`: termination invalidates appearance observation but does not flush tracking. Sleep/lock recording transitions need explicit implementation. |
| Capture | `Sources/Hago/ActiveWindowReader.swift`: AX/graphics titles and AppleScript targeting Google Chrome; other browser context is not equivalent. |
| Idle | `Sources/Hago/IdleMonitor.swift` and `AppState.idleThreshold`: input inactivity becomes idle after five minutes; not proof of absence. |
| Classification | `Sources/HagoCore/ActivityClassifier.swift`: first numeric-priority match; unknown native apps default Personal. |
| Defaults | `Sources/HagoCore/SeedData.swift`: broad app/domain defaults and an owner-specific Discord rule. |
| Learning | `Sources/HagoCore/RememberedRuleFactory.swift`: single host or literal title condition can overgeneralize or fragment learning. |
| Storage | `Sources/HagoCore/HagoStore.swift`: segments, classifications, rules, manual protection, transactional reclassification, AI audit/cache; schema setup adds missing columns and reinserts missing seeds. |
| AI | `Sources/HagoCore/ReviewAISuggestions.swift`, `ReviewAIProfession.swift`: grouped suggestions and role guidance already exist; a role currently informs AI, not starter packs. |
| Navigation | `Sources/Hago/HagoSection.swift`: retain existing surfaces; avoid a parallel interface. |
| Launch continuity | No login-item registration found in Sources; tracking currently depends on users reopening Hago. |
| Update discovery | No update-check implementation or updater dependency found in Sources/Package.swift; release installation scripts do not provide in-app discovery. |
| Report dates | `Sources/Hago/ReportsView.swift`, `periodTitle`: subtracts one second from the exclusive 4am end, which still labels the following calendar day. |

Recheck evidence before implementation. These are source observations, not a
claim that lifecycle or permission behavior has been reproduced in the app.

## Concrete readiness issues to close

These four user-supplied findings were checked against source on 2026-10-22 and
are acceptance cases, not optional future polish:

| Issue | Required result | Milestone |
|-------|-----------------|-----------|
| Owner-specific Discord work-channel default | No personal channel shipped to new users. Preserve an existing user's rule as legacy without recreating it as a universal default. | B/C |
| Unknown app becomes Personal | An unmatched Xcode snapshot is Needs Review; Software Development recognition or a confirmed user rule can classify it Work. Never fall back to Personal just because a rule is missing. | B/C |
| No open-at-login or update check | User-controlled Open at Login, with registration state/errors visible; in-app Check for Updates using published releases. | A/E/F |
| Week title includes an extra date | A Monday-start period from 19 Oct 2026 04:00 to 26 Oct 2026 04:00 displays 19–25 Oct, with all seven tracking days still included. | A |

Report labels must use the last included tracking-day label, not format
`exclusiveEnd - 1 second` directly as a civil date. Reuse HagoCalendar semantics
and calendar arithmetic; do not subtract a fixed 24 hours across daylight-saving
boundaries. Preserve the actual query range and early-morning time. Check
cross-month/year labels, weekly bucket tooltips and locale-defined week starts.

## User scenarios and screen sketches

### First launch

Use a resumable setup flow; begin tracking as soon as capture is possible rather
than waiting for every optional choice. No setup gate for returning users.

```text
Welcome: Understand where your computer time goes
  Local storage explanation / Start setup
Permissions: App tracking available / Window context missing
  Explain each permission next to its user benefit / Open system settings
  Continue with app-level tracking
Your work: General Work [selected] / Software Development [optional]
  Select multiple / Skip
Your context: What do you do? Which tools and workspaces are work or mixed-use?
  Brief structured choices / Optional plain-language context / Skip
Confirm tools: detected catalog matches only
  Tool | suggested purpose | change or leave unresolved
Optional AI: Connect provider / Choose model / See recommendation and data scope
  Skip and use local classification
Ready: Tracking status / capture limitations / Open Overview
```

Do not crawl browser history or documents. Tool detection reads application
identity metadata only. Do not automatically request every browser permission.
Persist setup progress; do not show onboarding repeatedly after updates.
Use confirmed answers to initialize local rules and context. Plain-language
answers remain local unless the user explicitly enables sharing them with the
chosen AI provider. Let users edit their profile later. This is personalized
setup inspired by the user's Wispr Flow analogy, not a claim to copy its flow.

### Ordinary day: Overview and menu bar

```text
Tracking: Browser context available [or clear limitation]
Today: Work / Personal / Needs Review / total tracked
Timeline: persisted activity plus the live interval, counted once
Needs your input: 2 recurring contexts / Review
```

Retain the menu bar Work | total tracked convention. A live provisional interval
must not appear as finalized evidence or be counted twice after checkpointing.
Overview remains today/this week; Reports remains historical comparison.

### Correct an activity

```text
Activity detail: time, app/site, available context
Work [selected] / Personal
Why: Software Development preset → editor
Change selected activity
Optional: Remember this app/workspace/site
  Suggested scope + examples + affected historical duration
  Save rule and apply / Cancel
Undo
```

Make immediate correction fast; remembering must not require opening an advanced
rule editor. Domain-wide learning is never the automatic consequence of marking
one article or video as Work. Offer only identities supported by captured data.

### Review recurring uncertainty

```text
Company workspace | 2h 15m across 3 days
Examples: representative contexts and dates
Work / Personal / Leave unresolved
Optional remembered scope / Preview / Apply / Undo
```

Group by a safe reusable context, not just superficial title similarity. Review
covers all history. Rank recurring/high-duration contexts first, and preserve
access to one-off entries. Zero backlog is not a success metric on its own.

### Settings and returning users

Group existing controls into Tracking & Privacy, Work Profile, Remembered Rules,
and optional AI Review. Keep advanced rule editing available. Preserve existing
project/category controls without making them onboarding requirements.

Show capture capability per supported browser: available, permission missing,
unsupported, or temporarily failed. Unknown private-mode status must not be
presented as verified public browsing.

## Recording architecture

Extract recording transitions from `AppState` into a focused coordinator and a
pure interval reducer in HagoCore. `AppState` projects observable UI state; it
must not own all persistence, lifecycle, recognition, and scheduling decisions.

Inputs: successful observations, no observation, lock/sleep,
resume, pause, shutdown, and persistence failure. States should distinguish
recording, paused, suspended, unavailable, and storage failure. Permission
limitations are capabilities, not necessarily complete recording failure.

- Keep a five-second observation cadence initially; use lifecycle/app events to
  close important boundaries promptly. Do not introduce continuous high-cost AX
  or browser scripting as a substitute for measured capture quality.
- Checkpoint each successful poll using one stable interval identity. Upsert
  the bounded interval; do not append a second copy every poll.
- Eliminate automatic trimming to last input after five minutes. Lack of input
  must not erase reading or video time. Keep intervals editable for user repair
  of unattended time; do not estimate absence from input inactivity.
- Record enough checkpoint metadata to recover after restart. Never extend an
  old session to the restart time, and never equate durable capture with proof
  that the user was attending to the screen.
- Flush on orderly quit. On abrupt exit, bound potential loss by one successful
  polling interval under normal operation; explicitly surface storage failures.
- On lock/sleep close the interval. On resume sample afresh; never bridge a
  sleep or unexplained long polling gap. Unknown gaps remain gaps.
- Use monotonic elapsed time to detect clock changes, with wall-clock dates for
  persisted placement. Do not create overlapping intervals after a clock jump.
- Serialize writes and flushes. Retry failed saves with the same interval ID;
  do not discard unsaved drafts or imply tracking is healthy after failure.
- Reading and watching continue to count without requiring manual restoration
  or a special keep-awake mode. Do not infer attendance from an open meeting
  app or playback, and do not claim to detect unlocked absence. If the user left
  while tracking continued, they can trim, split or remove that time in Activity.
- Do not add uncertain-presence states or return-confirmation prompts. Reserve
  uncertainty handling for missing capture evidence and ambiguous classification.
- Provide pause/resume and a bounded manual interval correction. Prevent
  overlaps and double counting. Offline/manual time is visibly user-entered.

Privacy exclusions run before durable detailed writes, including checkpoints,
correction evidence, and AI inputs. If private-mode status cannot be established
for a browser adapter, suppress detailed browser capture until safe; an unknown
state must not leak private titles through app-level fallback. Do not persist
keystrokes, page contents, or a second hidden copy of excluded activity.

## Recognition and classification architecture

Pipeline: capture capabilities → privacy gate → normalized context → applicable
rules/presets → classification with reason → persisted projection.

Keep raw evidence distinct from derived identities. Start with bundle ID,
normalized host, and carefully scoped URL patterns. Workspace/repository/channel
identities require app-specific extractors and representative evidence; never
infer reliable identity from arbitrary title similarity alone. Titles should be
conditioned on app/site identity so a generic title cannot match unrelated apps.

Introduce browser adapters incrementally. Harden Google Chrome first, implement
Safari next, and make unsupported browser limitations visible. Validate URL,
title, privacy state, permission denial, no-window and timeout behavior for each
adapter before advertising support. Perform potentially blocking capture away
from UI updates, with deadlines and stale-result rejection.

### Rule precedence

1. Privacy exclusions prevent capture and override other choices.
2. Explicit segment corrections remain authoritative for retained segments.
3. User rules take precedence over preset defaults.
4. Within newly scoped user rules, explicit child exceptions override their
   parent; otherwise choose structurally more specific matching contexts.
5. Equally authoritative contradictory new rules produce an explainable
   conflict needing resolution, never an alphabetical tie-break decision.
6. Remaining preset conflicts stay unresolved. Unknown activity is unresolved.

Preserve legacy numeric ordering among legacy rules until converted. A new
scope must not silently reorder existing custom rules. Track rule origin and
structured scope explicitly instead of deriving authority from display names.

### Presets

Bundle a versioned recognition catalog with stable IDs, evidence requirements,
role-specific defaults, and an ambiguity flag. General Work should emphasize
confirmed company contexts, not assume every communication tool is work.
Software Development can confidently include dedicated editors; shared tools,
social media, email, video, and AI chat require context or user confirmation.

Selecting multiple packs forms a union of compatible defaults. Conflicts remain
unresolved. Keep catalog recognition separate from enabled classification rules.
Preset updates preserve user overrides, disabled entries, and removals through
explicit tombstones; stop startup seeding from resurrecting deleted choices.

### Correction learning

- Store the explicit correction and available context; do not duplicate raw
  titles/URLs into a growing learning log.
- Offer an app scope for dedicated tools, a verified workspace scope for mixed
  apps, or a site scope when the user explicitly wants all of that site.
- Initially suggest learning after consistent corrections across at least
  three distinct tracking days. This is a tunable product heuristic, not an
  accuracy guarantee; ignore adjacent fragments as independent support.
- A contradictory correction invalidates or narrows the suggestion. Explicit
  rejection suppresses the same suggestion until material evidence changes.
- Rule application previews affected records and historical duration, protects
  manual choices and project assignments, and is transactional with undo.
- Saved AI rules retain their current opt-in contract; do not enable automatic
  application during migration. New conflict/privacy protections apply to AI.

### Optional AI provider and model connection

Provide a provider abstraction with direct API and existing CLI adapters. Keep
analysis requests, validation, scoped rule application and undo independent of
transport. Implement a small verified initial provider set behind this contract;
do not promise every provider at launch or require a CLI as the only option.

- Users choose provider/model and see curated choices by quality, latency and
  cost. Verify exact model IDs and current provider availability when building
  the integration; the conversation's `haiku-5.5` is an illustrative preference,
  not a verified model ID or a hardcoded product requirement.
- Keep direct-provider credentials in macOS Keychain, not SQLite, preferences,
  logs, exports or source. Support disconnect and credential removal.
- Before enabling, explain the grouped activity/context sent to that provider.
  Core app data remains local; explicitly enabled AI requests cross that boundary.
  Onboarding answers are shared only within the user's chosen disclosure scope.
- Send minimal relevant evidence, never private/ignored activity or the full
  database. Redact URL query secrets and sensitive context before transmission.
- Reuse cancellation, deadlines, schema validation, audit and undo. Show failed
  requests clearly and keep local tracking/classification operational offline.
- Explain provider usage costs before use, bound request sizes and scheduling,
  and avoid automatic paid retries or fallback to a different provider/model
  without the user's configured policy.
- Suggestions may enhance rule scope and categorization. Do not silently grant
  model output authority over explicit user choices. Insights remain future scope.

## Database evolution

Use ordered, transactional migrations with a schema version. Baseline the current
schema idempotently rather than replaying its startup repairs on every launch.
Use SQLite's backup API for a consistent pre-migration backup, including WAL
state; do not copy only the main database file while it is open.

Suggested additions (exact SQL belongs to the implementing stage):

| Entity | Minimum responsibility |
|--------|------------------------|
| Recording checkpoint | Stable segment ID, session ID, last observation, lifecycle boundary and recovery state. |
| Segment context | Optional normalized identity, context type, extraction version, capture capabilities; absent for unsupported historical evidence. |
| Classification metadata | Origin, reason code, rule/preset version and decision time; retain current manual protection. |
| Rule metadata | Origin, structured scope, optional parent exception, legacy precedence marker, revision and enabled state. |
| Preset selections | Pack ID/version, enabled entries and user overrides/tombstones. |
| Correction actions | Affected segment references, explicit before/after decisions, optional learned rule revision and undo state. |
| Setup progress | Versioned completion state and role selections; store alongside existing preferences unless atomic DB updates require otherwise. |
| AI connection preferences | Provider/model IDs, explicit disclosure scope and usage policy; credentials live only in Keychain. |

Extend existing tables/audit facilities where the contract fits; avoid a generic
event store or duplicated classification subsystem. Keep correction evidence
bounded, and ensure privacy deletion cascades through context and undo records.
An undo must not resurrect data removed by a later privacy action.

Migration requirements:

- Retain segment IDs, timestamps, totals, manual labels, custom rules, projects,
  categories, AI consent, schedule and audit records.
- Mark historic unknown-origin decisions as legacy; don't invent confidence.
- Stop shipping the owner-specific Discord default to new installs. Preserve
  existing use as a legacy rule rather than silently deleting it.
- Change unknown fallback for new observations first. Historical automatic
  reclassification is a separate previewed operation, not a startup side effect.
- On migration failure leave the original database usable and present recovery
  information. Detect newer unsupported schema versions and refuse writes.
- Do not promise executable downgrade after migration; recovery uses a verified
  backup and the compatible app version, with newer activity handled explicitly.

## Ordered implementation milestones

### A. Durable recording and lifecycle behavior

Depends on: none. Own recorder extraction, minimal checkpoint migration, live
totals, storage errors, lock/sleep/resume and quit/restart. Remove the input-idle
cutoff and expose bounded Activity time edits in this milestone so users can
repair unlocked absence without waiting for later learning/UI work.
Add user-controlled Open at Login through the platform login-item API, reporting
actual registration status and system approval requirements. Do not silently
enable it for existing users. Fix report period labels in this milestone; do not
wait for the classification redesign to address a misleading weekly range.

Done when: uninterrupted activity survives restart to the latest checkpoint;
quit flushes; reading and video remain tracked without input; sleep/lock and
clock changes do not invent time; users can trim, split or remove unattended
intervals without overlap or double counting; live and persisted totals agree.
Open at Login works in the installed signed app across a real login, can be
disabled, and reflects blocked/failed registration. Week titles label seven
tracking days correctly without changing included durations or the 4am cutoff.

#### Milestone A delivery evidence — 2026-10-22

- Implemented `ActivityRecorder` for stable interval identities, checkpoints,
  suspension boundaries and protection against clock-change overlaps. AppState
  retains failed writes for retry and surfaces a dedicated storage error.
- The existing segment end timestamp is the durable checkpoint. A restart
  begins a new ID at the current observation, bounded by the last persisted
  endpoint. No checkpoint table or schema migration was necessary for this
  milestone because there is no input-idle provisional tail to recover.
- Transactional checkpoint updates preserve existing classifications rather
  than replacing them. Activity can trim, split or remove an interval through
  a bounded removal range; remaining classifications/assignments are retained.
  Removal has no undo in this milestone and is labeled as permanent.
- Added pause/resume and Open at Login through SMAppService. Removed input-idle
  exclusion. Lifecycle observers close on sleep/display sleep/lock/session exit.
- Fixed report labels and local 4am cutoff arithmetic across daylight saving.
- Chrome observations fail closed if private-window status is unavailable;
  this can leave gaps when Automation access is missing, as documented.
- `swift test` passed: 136 core tests and 5 app tests. Nine new permanent tests
  protect consequential loss/overlap of recorded time, persisted manual choice,
  rollback/retry, bounded edits, and tracking-day boundaries. Temporary manual
  checks alone would not guard those integrity failures against later changes.
- Release install via `scripts/install-app.sh` succeeded with the existing stable
  certificate. The installed app was reopened; signature verification passed.
- Actual-app checks: live checkpoint writes; pause stops writes and resume
  restarts them; login registration toggles on/off (restored to off); report
  title is 19–25 Oct; time-edit sheet renders and cancels; normal quit/relaunch
  retains recording. No real activity was removed to test editing.
- Pre-install consistent SQLite backup was created outside the repository.
  Read-only comparison: all 91,606 baseline segment IDs and boundaries retained,
  baseline manual classifications unchanged, and no overlap in new intervals.
  SQLite quick_check passed. No private data was committed or uploaded.
- Remaining actual-system qualification: real sleep/lock and logout/login,
  abrupt power loss, and permission revocation. Reducer/storage recovery is
  covered automatically; installed UI/registration checks are not proof of
  those full OS transitions. This is not yet a production-readiness claim.

### B. Explainable classification and compatible storage

Depends on A. Add migration framework/provenance and new scoped rule contracts;
retain legacy ordering, preserve manual choices, change new unknown fallback.

Done when: existing database fixtures retain history and assignments; migration
rerun is harmless; every new decision explains its source; unknown apps remain
unresolved and contradictory new rules cannot silently choose a winner.

### C. Recognition and two starter presets

Depends on B. Separate catalog from preferences, support tombstones and multiple
packs, harden Chrome capture and expose capability state. Scope Safari support
as its own adapter increment before advertising it.

Done when: confirmed tool choices activate stable rules; shared domains remain
ambiguous; disabled defaults stay disabled after restart/update; missing browser
permissions and unsupported contexts are visible and privacy-safe.

### D. Corrections that teach and Review that reduces effort

Depends on B/C. Reuse Activity and Review; add scoped remember preview,
transactional correction/undo, consistent-context grouping, learning suggestions
and manual interval repair. Preserve the full backlog and existing AI controls.

Done when: one confirmed reusable rule fixes matching past/future automatic
activity without changing manual choices or unrelated contexts; undo restores
the action safely, including after restart; rejected suggestions stay dismissed.

### E. Personalized onboarding, optional AI connection and navigation

Depends on C/D. Implement the resumable profile flow, direct-provider connection,
provider/model recommendations and detailed states described above. The provider
adapter can be built independently after B. Refine existing native views instead
of shipping a second UI shell.
Offer Open at Login during setup and expose it in Tracking settings; declining
it must not block onboarding or reset the choice on later launches.

Done when: a fresh user reaches useful tracking without AI; skipped permissions
produce understandable limitations; returning users retain their configuration;
all correction/learning actions are reachable without advanced rule editing;
provider/model selection works without a CLI; connection failure never stops
tracking; secrets remain in Keychain and AI transmission matches disclosure.

### F. Release qualification and distribution

Depends on A–E. Validate Developer ID identity, hardened runtime/entitlements,
notarization and permission continuity on the packaged app. Extend existing ZIP
release automation with a DMG, checksum, fresh-machine install and upgrade QA.
Implement user-initiated Check for Updates using Sparkle, following the user's
explicit mac-mirrorly reference. This supersedes the earlier metadata-only
GitHub check design. Pin the dependency, use a Hago-specific Ed25519 trust key,
and verify the appcast signature/artifact pipeline. No automatic background
download/install; user-facing checks must handle offline, error, current and
newer-version states, including the initial absence of a published appcast.
Version the app bundle from the release version so comparisons are meaningful.
Review/package Sparkle's nested helpers and signing as part of distribution.
Fresh local Hago update-signing key generation is authorized; private material
stays in Keychain, only its public trust key is committed. No public release,
tag publication, or unrelated credential changes. Update checks are disclosed
release requests, not analytics or activity sync; never attach tracking data.

Done when: the actual downloaded build installs and launches under Gatekeeper,
captures through granted permissions, upgrades existing data, and has a tested
way to discover and obtain subsequent releases from the installed app. Check
for Updates handles current, newer and offline cases. Do not infer this from CI
success alone.

## Additional user findings accepted during implementation

These requirements supersede narrower earlier proposals and are included in
the active implementation, not a backlog requiring another confirmation:

- P0: migrate the owner-specific Discord rule to custom (`isBuiltIn = false`)
  for existing users, omit it for new installs, and remove Discord-specific
  Accessibility permission copy. Unknown native apps default Needs review only
  for new observations; never silently relabel existing history.
- P0: Open at Login (A) and manual Sparkle update checks (F); week date fix (A).
- P1: compare a partial current report with the same elapsed portion of the
  prior period. Historical complete periods still compare complete periods.
- P1: dashboard sidebar contains Overview, Reports, Needs review and Activity.
  A real Settings scene, available through Command-comma, contains Rules,
  Projects, Categories, Privacy and AI suggestions, plus profile/general needs.
  Rename popover action Open Hago and open Overview.
- P1: missing Accessibility permission is a permission state with Grant Access…
  in the popover, not an error. Menu durations use `2h46 · 11h50` rather than
  clock-like colon notation.
- P1: AI suggestions replaces AI Harness as the user-facing name. Connection
  choice and consent lead; model/reasoning/custom model live under Advanced.
  Direct provider setup remains an alternative to existing CLI setup.
- P1: use the display label Needs review consistently across navigation,
  categories and headings without changing persisted `review` identities.
- P2: Review groups lead with site/title, with the app as metadata. Keyboard
  W/P/I actions must not fire while typing into a text field.
- P2: built-in rules collapse by default; attention indicators identify actual
  conflicts/duplicates rather than treating built-in defaults as problems.
- P2: default today timeline includes the whole Hago day from 04:00 and all
  captured data, instead of a hardcoded 08:00 start. Preserve zoom/pan behavior.

## Verification and measurement

Implementation requires `swift test`, then `scripts/install-app.sh` to reinstall
and reopen, per repository instructions. Check signing separately with
`scripts/install-app.sh --check-signing` when needed. Review diffs and run
`git diff --check`. Keep private databases and build outputs out of commits.

Add permanent tests only for consequential interval/data integrity, migration,
privacy, classification authority and undo failures. Prefer existing tests and
temporary checks for presentation and straightforward catalog changes.

Use synthetic snapshots and temporary database copies for migration/recovery
verification. Any real database inspection is read-only; migration exercises
must not modify the user's live database. Verify backup restoration as well as
backup creation.

Actual-app checklist: uninterrupted session, quick switches, no-input reading,
video watching, meetings, leaving an unlocked Mac and repairing that interval
in Activity, pause/resume, lock/sleep/wake, orderly quit, abrupt termination,
permission revocation, browser privacy transition, storage error, 4am boundary,
timezone/clock change, rule correction, history preview, undo and upgrade.
Also verify personalized setup, direct-provider credentials/disconnect, selected
model use, disclosure/redaction, cancellation and offline/provider-failure paths.
Record observed limits of polling; do not claim second-perfect capture.

Keep evaluation local with synthetic/labeled scenarios and opt-in manual pilot
feedback. No remote analytics. Primary outcomes are trust in the record and
decreasing correction effort over repeated use. Measure duration-weighted agreement with explicit
user labels, automatic coverage, correction time, and repeated mistakes after
learning. Report sample size and uncertainty; absence of corrections does not
prove correctness. Treat 80% correct duration as a pilot hypothesis, not a launch
claim. Assess reliability separately from classification quality.

## Execution boundaries and delivery

This file is the concrete preparation deliverable. It does not mark application
behavior as implemented or authorize a public release. Future implementation
milestones use verification checkpoints as progress updates, not repeated user
confirmation gates. Resolve routine design/code choices within these decisions.

Each milestone should report changed behavior, migration impact, automated and
actual-app verification, and known limitations. Update the plan index as work
lands. Do not require a single monolithic PR or rewrite to deliver this revision.


## Integrated delivery evidence — 2026-10-22

- B/C: ordered schema v1 migration with a consistent SQLite backup, rule origin
  and conflict handling, privacy exclusions, unknown-to-review for new activity,
  versioned General Work/Software Development packs and user override tombstones.
  Shared tools need confirmed user context. No 80 percent coverage claim.
- D: scoped remembered-rule preview, transactional correction and bounded
  persistent undo, repeated-correction suggestions and dismissals. Review leads
  with site/title, supports focused W/P/I, and retains the entire backlog.
- E: resumable work profile, detected installed tools, real Settings scene,
  optional direct Anthropic/OpenAI connections alongside existing CLIs, Keychain
  credentials and explicit disclosure. Titles are excluded by default, outgoing
  evidence is bounded/redacted, redirects and automatic paid fallback are denied.
- Reports compare elapsed local time against the equivalent prior period; the
  timeline begins at the Hago day boundary and menu durations use hour/minute units.
- F implementation: com.ivan.hago, version 0.2.0 build 2; one-time preference
  domain migration; pinned Sparkle with manual checks; Developer ID/notarization,
  DMG, checksum and appcast-verification scripts. No public tag/release created.
- Integrated swift test passed 139 core and 9 app tests. Permanent additions cover
  migration/data integrity, classification authority, privacy/disclosure, undo,
  calendar comparisons and preserving upgrade/onboarding choices. Temporary
  Keychain checks exercised save/read/update/delete under a unique fixture service.
- A consistent copy of the real database upgraded/reopened with 91,659 records,
  zero missing IDs or changed boundaries/classifications, custom owner Discord
  rule, normalized stock Needs review category and SQLite quick_check = ok.
  Live upgrade preserved existing classifications and AI preferences.
- The installed app is signed with the existing stable local certificate and has
  com.ivan.hago. Installation exposed Launch Services selecting a staged copy;
  the installer now opens a new instance at the explicit /Applications path.
  An installed UI launch exposed a Charts crash. LLDB caught the missing Review
  colour-scale lookup; marks/scales now share ActivityKind.displayName. All 148
  tests passed again and the reinstalled /Applications process remains running.
- Remaining qualification: finish installed UI checks (the native tool currently
  resolves the old bundle identity after the rename), produce/verify the
  notarized candidate, sign its final
  appcast, and exercise an old-to-new update using two notarized versions. Real
  logout/login, fresh-machine, minimum-OS and Intel qualification are not proven.
  No real provider API request was made without a configured user connection.


### Final candidate verification — 2026-10-22

- Source commit `7b9cae6dad4239b4f7ce0efa70c8b4281e17efbc`. CI additionally
  caught and prompted a local-variable rename for compatibility with its older
  Swift compiler. All 148 tests passed locally again; CI test/package passed.
- Artifact-only run https://github.com/0xIvan/uso/actions/runs/39842690032 reused
  the existing authorized Apple signing secrets without exporting them. Only a
  temporary branch workflow was added; neither Uso default branch was changed
  nor a Hago public tag/release created. Hago still has no provisioned CI secrets;
  repeat notarization currently uses this existing signing environment.
- Apple accepted app and DMG notarization. Downloaded arm64 artifacts retained
  at `~/Downloads/Hago-0.2.0-7b9cae6/`, outside ignored/generated source outputs.
  Both checksums match CI, both stapled tickets validate, both Gatekeeper
  assessments report Notarized Developer ID, deep strict codesign verifies,
  and the bundle is com.ivan.hago, version 0.2.0 build 2, team AB879DAVK8.
- The actual downloaded notarized app replaced /Applications/Hago.app and was
  reopened. Its process remains running. SQLite quick_check passes, schema1,
  with no nonpositive recorded intervals. No claim of full UI verification: the
  native tool retained the former identity and then its connection closed.
- Final appcast was signed locally using Hago's Keychain key and verified against
  the public key in the downloaded app. A modified signature was rejected.
  No private signing key was exported or added to GitHub. Feed and artifacts
  remain unpublished, so production Check for Updates has no published feed yet.
- Remaining release qualification: actual screen-by-screen checks after restoring
  native control, a private two-version Sparkle update install, fresh-machine,
  minimum-OS/Intel, real sleep/wake and logout/login. Direct provider adapters
  and Keychain behavior passed synthetic checks; no real paid API call was made.
  These are explicit limitations rather than a production-ready certification.
