# CLAUDE.md

Modular Bash utility for managing local Kubernetes dev clusters (Istio, Vault, OpenLDAP, ESO).
Uses a dispatcher pattern with lazy plugin loading.
(Jenkins is a deprecated demo feature — disabled by default, not deployed; code retained but unsupported.)

**Entry point:** `./scripts/k3d-manager <function> [args]`
**Current state:** `memory-bank/activeContext.md` and `memory-bank/progress.md`
**Task specs:** `docs/plans/`

## Claude Session Rules

- **Memory-bank update is mandatory and immediate** — after every completed action (spec written, PR created, agent assigned, merge done, task status changed), update `memory-bank/activeContext.md` and `memory-bank/progress.md` before doing anything else. Do not wait for the user to ask.

- **PR creation gate** — do NOT create a PR until ALL of these pass: CI green, Copilot review comments addressed, Gemini live smoke test, Claude scope check. Draft PR is acceptable only as an explicit placeholder.
- **Prove external behaviour before dispatch (operator, 2026-11-07).** If a fix depends on how something
  outside the repo behaves (a Grafana option or feature, kubectl, ArgoCD or Helm behaviour, a CLI's output
  format), the spec carries proof from the version actually deployed before it is dispatched: a read-only
  capture, the upstream source at the deployed tag, or a live probe, with host, date and version beside
  it. Offline tests share the spec's assumption and cannot catch a wrong one. Precedents: `sort: 8` on
  Grafana 11.4.0, which bundles a scenes version that ignores it; the invented `byRefId` matcher.
- **Ideas backlog and release grooming (operator, 2026-11-07; weekly 2026-11-08; grooming 2026-11-08).** A new
  feature idea goes in `docs/ideas.md` as one row, not a plan or a dispatch. Every Sunday afternoon and at each release
  cut, `/release-groom` checks the release order: must-do bugs, this week's dispatch queue within the WIP limit, the
  open and next release (5 plans each), the ordered backlog of written plans in `docs/roadmap.md`, and the idea rows.
  New work does not join a release by default: an idea or backlog plan enters the next release only by displacing a
  not-started plan, which goes back to the ordered backlog unnumbered. Only the open and next release carry version
  numbers; work further out is an ordered backlog with themes (v2.0.0, v3.0.0), numbered when groomed in. Rules in
  `docs/ideas.md`.
- **Dispatch WIP limit and P3 batching (operator, 2026-11-07).** At most 3 dispatches open at once
  (running, or exited and not yet landed), and at most one open dispatch per file. A spec touching a file
  that an open dispatch edits waits, or is folded into the next dispatch for that file. P0 and P1 may exceed
  the limit. A review child (`start --parent P --role review`, which changes no files) does not count toward
  the limit (operator, 2026-11-08). A P3 is filed with `**Waiting on:** dispatch` and dispatched in a batch with other P3s on
  the same files once there is room. Precedent: four concurrent dispatches on `bin/k3dm-dispatch-metrics`
  on 2026-11-07.
- **Verify before trust** — never trust a commit SHA, BATS result, or "done" report from any agent without independently verifying via `gh api`, `gh run view`, or `git log`.
<!-- shared:begin plan-cap -->
- **Versioning and release scope (operator, 2026-11-07; supersedes the 2026-10-10 split-early-into-a-patch rule)** — `X.0.0` is a breaking change. `X.Y.0` is a feature release, a sprint story of at most 5 plan docs in `docs/plans/`. A 6th plan, or a release growing too big or too fast, splits into the next minor `X.(Y+1).0`, never into a patch. `X.Y.N` (N ≥ 1) is **bug-fix only**: specs from `docs/bugs/`, no `docs/plans/`, branch `k3d-manager-vX.Y.N` cut from `main` after the previous release merges. **Bugs before features (operator, 2026-11-07).** A P0 is fixed at once, whatever the release: a hotfix `X.Y.N` from `main` if the open release is not about to merge. A P1 blocks the open release's PR. **Capture first, triage later (operator, 2026-11-11; supersedes the 2026-11-08 P2 rules, effective now incl. v1.43.15).** A bug found live or anywhere else is captured as a short `docs/bugs/` doc (symptom, evidence, Priority, `**Introduced by:**`, `**Waiting on:** operator decision`): no fix spec, Acceptance block or dispatch yet. **Second-agent classification (operator, 2026-11-11):** Claude's Priority is a proposal; Gemini 4.0 Argon (`gemini-4-argon-medium`, cross-vendor) reads only the bug doc, not Claude's reasoning, and gives a Priority with one line of reason, recorded as `**Classified:** <P> by <agent>, YYYY-MM-DD`. When they differ the higher Priority stands until the operator decides; Fable breaks a P1/P2 tie when asked. Only P0 and P1 are fixed without triage. P2 and P3 wait for triage and never block a release PR by themselves. **Triage trigger (operator, 2026-11-11; from v1.44.0, after v1.43.15's post-merge grooming clears the backlog):** triage runs when 20 bugs have been captured since the last triage, or when the oldest of them is 7 days old, whichever comes first, and at each post-merge `/release-groom`. Claude checks at session start and says "triage due"; it brings a one-line recommendation per bug. Related bugs from one live session are captured as one doc. The rules here are expected to be tuned as data comes in. If Claude judges a P2 costly to leave (e.g. it bypasses a safety gate), Claude says why and the operator decides. The full spec rigor (Acceptance, Contract readers, independent verifier, cross-vendor review) applies once a bug is chosen for a fix. Measured in docs/process-metrics.md. Patches are optional: after `/post-merge`, `/release-groom` triages every open bug as `patch` (cut `X.Y.N+1`), `carry` (into `X.(Y+1).0`) or `close`, and the operator decides. A P2 goes to the patch if its workaround costs something now, otherwise it carries; a carried P2 lands in that release and is not carried twice without the operator saying so. P3s are batched into a release or a patch, at most 10 per release; a P3 passed over at two groomings is closed as won't-fix unless the operator gives a reason to keep it, the doc stays, and a recurrence reopens it. When bug work crowds a release, the lowest-priority plan not yet started moves to the next minor: plans move out, bugs stay. Bug specs never count toward the 5-plan cap. Claude decides splits, records them in `docs/roadmap.md`, and tells the operator. The queue after v1.43.15 was renumbered to this scheme on 2026-11-07 (old → new table in `docs/roadmap.md`).
<!-- shared:end plan-cap -->
- **No network path out of a cloud session** — if you are running in a Claude cloud
  environment with only the GitHub connection, you cannot reach the k3dm webhook, the cluster,
  or any host. Do not search for a token, do not attempt a tunnel, and do not ask the operator to
  place a credential in your environment — that is refused by policy. To read cluster state, file
  a request on the `cloud-requests` branch: see **`docs/howto/cloud-session-requests.md`**. The
  read-only actions listed in that how-to's table are available; everything else must be run
  by the operator.

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
- **Thinking Budget:** Capped at 8,192 tokens (set via .envrc).
- **Context Management:** Sessions run in a 200K context window, and auto-compaction runs at about 167K. The 2026-10-22 trial of `autoCompactWindow: 400000` never applied, because the setting cannot exceed the window; it was set back to 200000 on 2026-11-01. Run a manual `/compact` at a natural break (between tasks, never mid-step) before that point, so it never lands mid-step. The threshold is under measurement: `docs/plans/v1.43.6-claude-context-compaction-metrics.md`.
- **Output Compression:** RTK (Rust Token Killer) is active for all CLI output.

---

## Layout

```
scripts/k3d-manager          # dispatcher
scripts/lib/                 # core libraries (system.sh, core.sh, cluster_provider.sh, ...)
scripts/plugins/             # lazy-loaded feature modules (vault.sh, jenkins.sh, eso.sh, ...)
scripts/etc/                 # config templates and vars (*.yaml.tmpl, vars.sh)
scripts/tests/               # BATS suites (pure logic only — no cluster mocks)
```

Provider selected by `CLUSTER_PROVIDER` env var (`orbstack` / `k3d` / `k3s`).
Directory service selected by `DIRECTORY_SERVICE_PROVIDER` (`openldap` / `activedirectory`).

---

## Plugin Development

New plugins go in `scripts/plugins/`. Public functions: no underscore. Private: `_` prefix.

```bash
#!/usr/bin/env bash
# scripts/plugins/mytool.sh

function mytool_do_something() {
  _kubectl apply -f my.yaml
}

function _mytool_helper() {
  :
}
```

**`_run_command` wrapper — always use this for privileged or external commands:**

```bash
_run_command --prefer-sudo -- apt-get install -y jq   # prefer sudo, fall back to user
_run_command --require-sudo -- mkdir /etc/myapp        # fail if sudo unavailable
_run_command --probe 'config current-context' -- kubectl get nodes  # probe to decide sudo
_run_command --quiet -- command_that_might_fail        # suppress stderr, still returns exit code
```

Do NOT call `sudo` directly. Do NOT use `command sudo`. Route through `_run_command`.

---

## Code Style

- Minimal patches — no unsolicited refactors
- Maintain existing indentation, quoting, and naming
- LF line endings only — no CRLF
- No inline comments in shell blocks unless explicitly requested
- Use `${PLACEHOLDER}` for secrets — never hardcode
- `set -euo pipefail` on all new bash scripts

---

## Docs Conventions

<!-- shared:begin bug-priority -->
Bug priority is urgency, separate from Severity: P0 outage/data loss/security now; P1 broken
without a workaround; P2 degraded with a workaround; P3 cosmetic, hygiene or test-only. Every
new `docs/bugs/` file must carry `**Priority:** P0`, `P1`, `P2`, or `P3` directly under Status.
**Escape origin (operator, 2026-11-07).** Every bug filed from 2026-11-07 also carries
`**Introduced by:** <commit or release | pre-existing | unknown>` and `**Should have been caught by:**`
one of `spec`, `offline test`, `review`, `deploy step`, `live check` or `none`: the first safety net that
should have stopped it. Write `unknown` rather than guess. Each retro counts them by release and by net.
<!-- shared:end bug-priority -->

**Waiting on line (operator, 2026-11-06).** An open `docs/bugs/` doc says what it needs next, in its
header, with `**Waiting on:** <word>` or `**Waiting on:** <word> — since YYYY-MM-DD`. The word is one of
`dispatch`, `fix running`, `live check`, `scheduled run`, `investigation`, `operator decision`. The Bugs
table shows it; a doc without the line reads `not stated`, and any other word reads `invalid`. Update it
whenever the bug moves, and only write what you can support: leave it out rather than guess.
**Status first word (operator, 2026-11-06).** The Bugs table reads only the first word of a bug's Status. A landed fix starts `LANDED`, `VERIFIED` once independently verified; anything still open starts `OPEN`. The pre-commit hook refuses other forms when a Status changes.
**Acceptance block (operator, 2026-10-17).** Every new `docs/bugs/` or `docs/plans/` spec that gets
dispatched carries an `## Acceptance` section: a YAML block with `must`, `must_not` and `evidence`
(IDs like M1/N1/E1; each evidence item names what it `proves`, and whether it is `offline` or `live`),
plus an `interface` list of the entry points a black-box test needs. Rules: every `must_not` has a
test shown red against the pre-fix code; an independent verifier (a separately tasked agent) writes
its own tests from the Acceptance section only, never the fix spec or the diff, and both test sets
must pass; live evidence is run by the operator or Claude, never Gemini. Example:
`docs/bugs/2026-10-13-e2e-sandbox-does-not-provision-missing-acg-cluster.md`.
<!-- shared:begin intent-approval -->
Every evidence item carries an operator-facing `intent`, and the spec carries `**Intent approved:**` before dispatch.
<!-- shared:end intent-approval -->

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

- **`docs/bugs/`** — unplanned bug fix specs filed by agents or Claude during a session.
- **`docs/issues/`** — Copilot PR findings and post-incident notes.
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

---

<!-- shared:begin security -->
## Security Rules (treat violations as bugs — catch before commit)

**Shell Injection (OWASP A03)**
- Always double-quote variable expansions: `"$var"`, never bare `$var` in command arguments.
- Never pass external or user-supplied input to `eval`.
- Use `--` to separate options from arguments in CLI calls where arguments may contain hyphens.
- Variables expanded via `envsubst` in `*.yaml.tmpl` must not contain shell metacharacters — validate before substitution.

**Least Privilege (OWASP A01)**
- New Vault policies must grant only the minimum required paths (`read` unless `write` is explicitly needed).
- New Kubernetes ServiceAccounts must not use `cluster-admin`. Use namespace-scoped Role + RoleBinding.
- New ClusterRoles must be justified — prefer namespace-scoped resources.
- GitHub Actions workflows must use `permissions: contents: read` unless elevated access is explicitly required.

**Cryptographic Failures (OWASP A02)**
- `AD_TLS_CONFIG=TRUST_ALL_CERTIFICATES` and `insecureSkipVerify: true` are dev-only. Never introduce in production config paths.
- Vault PKI leaf cert TTL must stay short (≤720h). Do not increase `VAULT_PKI_ROLE_TTL` without justification.
- Never add `--insecure` or `-k` to scripts that may run against production endpoints.

**Secret Hygiene (OWASP A02)**
- Vault tokens must never appear in script arguments visible in shell history or CI logs. Use env vars or stdin.
- New sensitive CLI flags must be registered in `_args_have_sensitive_flag` in lib-foundation's `scripts/lib/system.sh` (change it upstream, then subtree-pull; `scripts/lib/system.sh` here only loads it).
- Test credentials (`alice/password`, etc.) are dev-only — never reference in production config paths.
- No secrets in `kubectl exec` command strings that appear in logs.

**Security Misconfiguration (OWASP A05)**
- Every new deployed service must use its own namespace — never `default`.
- New Helm chart installations must pin chart versions explicitly — no floating `latest`.

**Supply Chain Integrity (OWASP A08)**
- GitHub Actions steps must pin to a version tag (`@v4`) — never `@main` or `@latest`.
- New container image references in `*.yaml.tmpl` must use a pinned tag, not `latest`.
- **Pins get reviewed, not only set (operator, 2026-11-07).** A pinned chart or image never moves by itself: the
  observability stack sat at kube-prometheus-stack `67.9.0` (Grafana 11.4.0) for nearly two years. Severity sets the
  response. A critical or high CVE in a pinned image calls for a patch release. An upstream bug that hurts us and has a
  cheap workaround gets the workaround, with `**Fixed upstream in:** <component> <version>` in its bug doc. An upstream
  bug with no workaround, or several fixed-upstream bugs piling up, calls for an upgrade release. Absent any of those,
  review the pinned stack versions once a quarter and plan an upgrade when one is more than about two minor versions
  behind.

**Existing protections — do not remove or weaken:**
- `_run_command` handles sudo probing and escalation safely.
- `_args_have_sensitive_flag` disables trace for commands with `--password`, `--token`, `--username`.
- ESO syncs credentials from Vault without exposing them in git.
<!-- shared:end security -->
