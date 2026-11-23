# Review: k3d-manager PR #164 (v1.45.0 release) — blind diff review

**Filed:** 2026-11-23
**Repo / branch:** `k3d-manager` / `k3d-manager-v1.45.0` (head c4a97ef7; diff `origin/main...c4a97ef7 -- bin scripts Makefile`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`), role review

## Task

Review `git diff origin/main...c4a97ef7 -- bin scripts Makefile` blind. Docs and memory-bank are out of scope. Copilot is
capped until 2026-12-01, so this review is the PR's review gate. A separate security red team already reviewed the
same code; this pass is for **correctness**: a feature that does not do what is described below, a failure that
reads as success, or a test that cannot fail. Report a security defect too if you see one. The intended behaviour is:

- **Approval store** (`scripts/lib/hub_approval.py`): one pending request at a time, bound to SHA and branch with a
  record MAC, an expiry and a TOTP step; replay, expired, mismatched or reused-step approvals are refused; exclusive
  create.
- **Promote wiring** (`bin/k3dm-hub-promote`, `bin/k3dm-hub-deploy`, `bin/k3dm-promote-client`): ids validated; no
  secret in argv; the client talks to the root daemon over its socket.
- **Root daemon and installer** (`scripts/libexec/k3dm-promote-daemon.py`, `bin/k3dm-promote-authority`, the
  promote-authority plist): socket 0600 with a peer-uid check, bounded request parse, `python -IS`, isolated git
  environment, fail-closed audit log, staged-blob hash checked before running.
- **Mover** (`scripts/lib/promote_mover.py`): moves `deploy/hub` only for an unspent approval of the newest release
  branch, with `--force-with-lease` and a witness tag, re-checking before the push; "already at sha" must not be
  credited as a move.
- **CVE pin branch** (`scripts/etc/argocd/platform-ops/app-cve-scan.sh`, `cve-remediation-verify.sh`,
  `applicationsets/services-git.yaml`, `scripts/plugins/argocd.sh`, `k3s-hostinger.sh`, `bin/cluster-preflight`):
  overrides are written to `pins.json` on `cve-pins/hub` only (no live merge-patch, no `--force`, no second ref);
  any failed read is a failure, never "none"; a missing `GIT_WRITE_TOKEN` fails the run with
  `PINSYNC: FAILED — no GIT_WRITE_TOKEN` (deliberate, operator 2026-11-20); the AppSet takes the image from
  `pins.json` only when it matches the regex guard.
- **Web console** (`bin/k3dm-web-console-sshd`, `bin/k3dm-web-console-totp`, `scripts/lib/web_console_common.sh`,
  `scripts/libexec/k3dm-console-totpd.py`, `k3dm-console-gate.py`, `k3dm-console-totpctl.py`, the sshd config and
  plists): loopback-only, certificate-only sshd with ForceCommand into the gate; the gate needs a valid TOTP (replay
  guard, constant-time compare, lockout) before the tmux shell; `revoke` stops access; installers validate with
  `sshd -t` and fail closed.
- **Travel bundle** (`scripts/plugins/password_bundle.sh`, its plist and alert rule, Makefile targets): age-encrypted
  to enrolled recipients, no plaintext on disk, secrets on stdin; staleness alert.
- **Stall diagnosis and dispatch metrics** (`bin/k3dm-dispatch-stall-diagnose`, `bin/k3dm-dispatch-recover`,
  `bin/k3dm-dispatch-metrics`, `bin/k3dm-codex-dispatch`, `scripts/etc/dispatch/stall-diagnose-prompt.md`): a stalled
  dispatch is diagnosed by headless Claude, the correction is approved or denied in Slack before resuming; metric
  pushes are single-flight with retries.
- **Dashboards and metrics** (`grafana-dashboard-agent-cost.yaml`, `-agent-activity.yaml`, `-bugs.yaml`,
  `bin/k3dm-vectordb-metrics`, `prometheusrule.yaml`): quota gauges beside Fable; per-project bug metrics.

Look for:
- a failure path that exits 0 or logs success (a read error treated as empty, an ignored return code, `|| true` on a
  step that matters);
- approval or pin logic that can be satisfied by the wrong SHA, branch, step or digest;
- quoting/injection: unquoted expansions, unvalidated input reaching git, kubectl, sshd config or a shell;
- a secret (TOTP seed, token, password) in argv, xtrace, a log line or a Slack message;
- dashboard YAML whose queries, units or thresholds do not match the panel's title;
- tests that cannot fail (negated commands without `run !`, assertions on the wrong `run`, stubs that hang on stdin)
  or tests that write outside a temp dir or call real sudo/launchctl.

## Before You Start

1. `git log --oneline -1` and confirm HEAD is c4a97ef7.
2. Read the changed hunks of the files below, then enough of each surrounding function to judge them.

## Files

| File | Change |
|---|---|
| every file in `git diff --name-only origin/main...c4a97ef7 -- bin scripts Makefile` | read only |

## What NOT to Do

- Do NOT edit, commit, push or comment on the PR.
- Do NOT touch any cluster, kubectl context, Keychain or network endpoint; reason from the code.
- Do NOT run sudo, launchctl or any install target.
- Do NOT update `memory-bank/`.

## Definition of Done

- [ ] Report back one line per finding: `file:line — defect — concrete failure scenario — severity (high/medium/low)`.
      If there are none, report `no findings`. Mark each finding as verified-from-code or speculative.

## Acceptance

```yaml
must:
  - id: M1
    text: every finding cites file:line and a concrete failure scenario
must_not:
  - id: N1
    text: the reviewer changes any file
evidence:
  - id: E1
    proves: [M1, N1]
    kind: offline
    command: git status --short in the review worktree is empty; report lists findings or "no findings"
    intent: An independent model checks the v1.45.0 release code before you merge it, in place of Copilot this month.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** standing rule from "Copilot reach his cap ... you might want to have Argon for code review" (operator, 2026-11-17): release PRs get a blind Argon review until 2026-12-01; v1.45.0 release gates incl. Argon review agreed in session 2026-11-23. Intent text is the PR #163 sentence with the version changed.
