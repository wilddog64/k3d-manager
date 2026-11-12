# Process rules — full text

This file holds the full original text of the rules summarised in [`CLAUDE.md`](../../CLAUDE.md):
precedents, history, rationale and dated decisions, moved here verbatim on 2026-11-12 (v1.43.15
post-merge Step 7c) so `CLAUDE.md` can stay short. `CLAUDE.md` remains the authoritative list; when a
rule changes, update both. Blocks between `<!-- shared:... -->` markers in `CLAUDE.md` are shared
verbatim with `AGENTS.md` and `GEMINI.md` (checked by `bin/k3dm-check-agent-docs`), so they were not
moved and are not copied here.

## Claude Session Rules

<a id="memory-bank-update"></a>
### Memory-bank update

- **Memory-bank update is mandatory and immediate** — after every completed action (spec written, PR created, agent assigned, merge done, task status changed), update `memory-bank/activeContext.md` and `memory-bank/progress.md` before doing anything else. Do not wait for the user to ask.

<a id="pr-creation-gate"></a>
### PR creation gate

- **PR creation gate** — do NOT create a PR until ALL of these pass: CI green, Copilot review comments addressed, Gemini live smoke test, Claude scope check. Draft PR is acceptable only as an explicit placeholder.

<a id="prove-external-behaviour"></a>
### Prove external behaviour before dispatch

- **Prove external behaviour before dispatch (operator, 2026-11-07).** If a fix depends on how something
  outside the repo behaves (a Grafana option or feature, kubectl, ArgoCD or Helm behaviour, a CLI's output
  format), the spec carries proof from the version actually deployed before it is dispatched: a read-only
  capture, the upstream source at the deployed tag, or a live probe, with host, date and version beside
  it. Offline tests share the spec's assumption and cannot catch a wrong one. Precedents: `sort: 8` on
  Grafana 11.4.0, which bundles a scenes version that ignores it; the invented `byRefId` matcher.

<a id="ideas-backlog-and-release-grooming"></a>
### Ideas backlog and release grooming

- **Ideas backlog and release grooming (operator, 2026-11-07; weekly 2026-11-08; grooming 2026-11-08).** A new
  feature idea goes in `docs/ideas.md` as one row, not a plan or a dispatch. Every Sunday afternoon and at each release
  cut, `/release-groom` checks the release order: must-do bugs, this week's dispatch queue within the WIP limit, the
  open and next release (5 plans each), the ordered backlog of written plans in `docs/roadmap.md`, and the idea rows.
  New work does not join a release by default: an idea or backlog plan enters the next release only by displacing a
  not-started plan, which goes back to the ordered backlog unnumbered. Only the open and next release carry version
  numbers; work further out is an ordered backlog with themes (v2.0.0, v3.0.0), numbered when groomed in. Rules in
  `docs/ideas.md`.

<a id="dispatch-wip-limit"></a>
### Dispatch WIP limit and P3 batching

- **Dispatch WIP limit and P3 batching (operator, 2026-11-07).** At most 3 dispatches open at once
  (running, or exited and not yet landed), and at most one open dispatch per file. A spec touching a file
  that an open dispatch edits waits, or is folded into the next dispatch for that file. P0 and P1 may exceed
  the limit. A review child (`start --parent P --role review`, which changes no files) does not count toward
  the limit (operator, 2026-11-08). A P3 is filed with `**Waiting on:** dispatch` and dispatched in a batch with other P3s on
  the same files once there is room. Precedent: four concurrent dispatches on `bin/k3dm-dispatch-metrics`
  on 2026-11-07.

<a id="verify-before-trust"></a>
### Verify before trust

- **Verify before trust** — never trust a commit SHA, BATS result, or "done" report from any agent without independently verifying via `gh api`, `gh run view`, or `git log`.

<a id="versioning-and-release-scope"></a>
### Versioning and release scope

Kept verbatim in `CLAUDE.md` (shared `plan-cap` block, identical in `AGENTS.md` and `GEMINI.md`).

<a id="no-network-path-out-of-a-cloud-session"></a>
### No network path out of a cloud session

- **No network path out of a cloud session** — if you are running in a Claude cloud
  environment with only the GitHub connection, you cannot reach the k3dm webhook, the cluster,
  or any host. Do not search for a token, do not attempt a tunnel, and do not ask the operator to
  place a credential in your environment — that is refused by policy. To read cluster state, file
  a request on the `cloud-requests` branch: see **`docs/howto/cloud-session-requests.md`**. The
  read-only actions listed in that how-to's table are available; everything else must be run
  by the operator.

<a id="hub-reads-deploy-hub"></a>
### The hub reads deploy/hub; promote to reach it

- **The hub reads `deploy/hub`; promote to reach it (operator, 2026-11-07; supersedes the 2026-07-24 release-branch tracking).**
  A release or feature branch does not reach the running hub until the operator runs `make hub-promote REF=<commit-ish>`
  (CI-green commit on `origin`, typed confirmation, `hub-promote/<UTC>` tag), then `make appsets-check` and
  `make platform-ops`. Before asking for a live check of anything ArgoCD or platform-ops deploys, confirm with
  `make hub-promote-status` that the commit is promoted, and ask for a promote if not: config on the release branch
  is inert until then. `make appsets-reapply` pins both stages to `deploy/hub` (hub first, `APPSETS_STAGE=hub` stops
  there to soak); rerun it only when ApplicationSet manifests change. A new ApplicationSet must carry
  `k3dm.k3d.io/rollout-stage`. `make platform-ops` applies the promoted tree, not the checkout, and fails closed when
  `deploy/hub` is missing: the first promote is the bootstrap in `docs/howto/hub-promote.md`. Run it from the
  operator's tmux (Keychain), then confirm `kubectl -n platform-ops rollout status deploy/vulnerability-inventory-exporter`.
  Rollback: `make hub-rollback`.

## Environment Constraints

<a id="environment-constraints"></a>
### Thinking budget, context management, output compression

- **Thinking Budget:** Capped at 8,192 tokens (set via .envrc).
- **Context Management:** Sessions run in a 200K context window, and auto-compaction runs at about 167K. The 2026-10-22 trial of `autoCompactWindow: 400000` never applied, because the setting cannot exceed the window; it was set back to 200000 on 2026-11-01. Run a manual `/compact` at a natural break (between tasks, never mid-step) before that point, so it never lands mid-step. The threshold is under measurement: `docs/plans/v1.43.6-claude-context-compaction-metrics.md`.
- **Output Compression:** RTK (Rust Token Killer) is active for all CLI output.

## Docs Conventions

<a id="bug-priority-and-escape-origin"></a>
### Bug priority and escape origin

Kept verbatim in `CLAUDE.md` (shared `bug-priority` block).

<a id="waiting-on-line"></a>
### Waiting on line

**Waiting on line (operator, 2026-11-06).** An open `docs/bugs/` doc says what it needs next, in its
header, with `**Waiting on:** <word>` or `**Waiting on:** <word> — since YYYY-MM-DD`. The word is one of
`dispatch`, `fix running`, `live check`, `scheduled run`, `investigation`, `operator decision`. The Bugs
table shows it; a doc without the line reads `not stated`, and any other word reads `invalid`. Update it
whenever the bug moves, and only write what you can support: leave it out rather than guess.

<a id="status-first-word"></a>
### Status first word

**Status first word (operator, 2026-11-06).** The Bugs table reads only the first word of a bug's Status. A landed fix starts `LANDED`, `VERIFIED` once independently verified; anything still open starts `OPEN`. The pre-commit hook refuses other forms when a Status changes.

<a id="acceptance-block"></a>
### Acceptance block

**Acceptance block (operator, 2026-10-17).** Every new `docs/bugs/` or `docs/plans/` spec that gets
dispatched carries an `## Acceptance` section: a YAML block with `must`, `must_not` and `evidence`
(IDs like M1/N1/E1; each evidence item names what it `proves`, and whether it is `offline` or `live`),
plus an `interface` list of the entry points a black-box test needs. Rules: every `must_not` has a
test shown red against the pre-fix code; an independent verifier (a separately tasked agent) writes
its own tests from the Acceptance section only, never the fix spec or the diff, and both test sets
must pass; live evidence is run by the operator or Claude, never Gemini. Example:
`docs/bugs/2026-10-13-e2e-sandbox-does-not-provision-missing-acg-cluster.md`.

<a id="intent-approval"></a>
### Intent approval

Kept verbatim in `CLAUDE.md` (shared `intent-approval` block).

<a id="contract-readers"></a>
### Contract readers and writers

**Contract readers (operator, 2026-11-08).** A spec that changes a shared contract (a git ref, a Keychain item, a
Slack app or webhook, a port, an env var, a file path another component reads) lists every reader under
`## Contract readers`, found by grep, with file:line, and says for each whether it changes or why it doesn't. A reader
found after dispatch is a spec defect. Precedent: the hub deploy-ref change moved the expected ref to `deploy/hub`
without listing `sensors.py:114`, so Hermes paged on it and offered a harmful repair.
**Writers too (operator, 2026-11-10).** The same list names every component that writes to the contract (commits to
the ref, sets the key, posts to the webhook), marked `writer`, with what happens to its writes after the change.
Precedent: the same deploy-ref change missed the CVE promoter (`app-cve-scan.sh:514-591`), which commits pins to the
branch its app tracks; `make hub-promote` would have discarded them
(`docs/bugs/2026-11-10-hub-promote-discards-cve-promoter-commits.md`).

<a id="test-controls"></a>
### Test controls

**Test controls (operator, 2026-10-30; from "Four ways a test can lie").** Three more rules for
dispatched tests:
- **Paired positive control.** A test that asserts "X has no effect" (nothing loaded, nothing
  written, no call made) is paired with a test showing the effect does happen when X is enabled.
  Without the pair, a stub that never makes the call passes the negative test vacuously.
- **Stubs are captured, not imagined.** A stub that imitates an external tool's output (`pmset`,
  `docker`, `kubectl`, `launchctl`, `security`) takes that output from a real read-only capture,
  with the host and date in a comment beside it. Mutation tests cannot catch a wrong contract,
  because the code and the test share it: v1.43.12 `hub-new` passed every test against a
  `disablesleep` pmset line, a `kine` pod and an `identity` app that the real hub does not have.
- **Verify the target before the result.** A fixture first asserts what it is pointed at: a fake
  repo root rather than the real tree, a stub endpoint rather than the live hub, a scratch HOME
  rather than `~/Library/LaunchAgents`. Code under test resolves paths from its own root, never
  from the caller's current directory.

<a id="bug-and-issue-folders"></a>
### docs/bugs and docs/issues

- **`docs/bugs/`** — unplanned bug fix specs filed by agents or Claude during a session.
- **`docs/issues/`** — Copilot PR findings and post-incident notes.

<a id="dedup-before-filing"></a>
### Dedup before filing — two passes

- **Dedup before filing — two passes.** The exact-slug glob only matches a slug someone already
  guessed correctly; this repo has refiled the same ESO defect under a name the glob could not
  match. Run both:
  - **Pass 1 — exact slug (authoritative).** Shell: `ls docs/bugs/*-<slug>.md 2>/dev/null` or
    `ls docs/issues/*-<slug>.md 2>/dev/null`; Python:
    `list(Path("docs/bugs").glob(f"*-{slug}.md"))`. If any match exists, use the existing path —
    do NOT create a second file.
  - **Pass 2 — similarity (advisory).** `make find-similar-docs Q="<the symptom in prose>"`. A high
    score means **read that file before filing**, not *do not file*: a recurrence is worth
    recording, and often belongs as a `Recurrence` section appended to the existing doc rather than
    as a new file. The command always exits 0 — a store that is down or an unset credential must
    never block filing. The v1.40.0 live eval found a modest recall gain on bugs only and more
    intrusion than a TF-IDF control, so scores stay advisory — never a filing gate.
    See `docs/howto/find-prior-art.md`.
  - **Record the result (operator, 2026-11-08).** Every new `docs/bugs/` doc carries
    `**Prior art:** <path> (<score>) — <what was done>` in its header: `read, different root cause`,
    `appended Recurrence` (then no new file), or `none above threshold`. Write `not run` rather than
    skip the line. Started 2026-11-08 to measure whether Pass 2 changes decisions; review at the first
    grooming after 2026-12-08 (keep, retune or drop the pass).

## Security Rules

<a id="security-rules"></a>
Kept verbatim in `CLAUDE.md` (shared `security` block, including **Pins get reviewed, not only set (operator, 2026-11-07)**).
