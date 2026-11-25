# Review: k3d-manager PR #165 (v1.45.1 release) — blind diff review

**Filed:** 2026-11-25
**Repo / branch:** `k3d-manager` / `k3d-manager-v1.45.1` (head bc93f266; diff `origin/main...bc93f266 -- bin scripts Makefile`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`), role review

## Task

Review `git diff origin/main...bc93f266 -- bin scripts Makefile` blind. Docs and memory-bank are out of scope. Copilot is
capped until 2026-12-01, so this review is the PR's review gate. This pass is for **correctness**: a fix that does not do
what is described below, a failure that reads as success, or a test that cannot fail. Report a security defect too if
you see one. The intended behaviour is:

- **Verified-stage bootstrap** (`bin/k3dm-verified-stage`): installed root-owned; stages only a full 40-hex commit that
  is reachable from `main` (or an explicit `--ref`, printed as `UNPROTECTED REF`) into a root-owned tree with no
  symlinks, ACLs or group/other write; `run` refuses an unverified stage, runs the tool under `env -i` with a fixed
  PATH, and invalidates the sudo ticket before and after, including on signals.
- **Root installers** (`bin/k3dm-promote-authority`, `bin/k3dm-web-console-sshd`, `bin/k3dm-web-console-totp`): install
  only the staged HEAD (never fetch), call system tools by absolute path (`/bin/chmod`, the Command Line Tools git),
  sshd config enforces the RevokedKeys KRL.
- **CVE scan and verifier** (`scripts/etc/argocd/platform-ops/app-cve-scan.sh`, `cve-remediation-verify.sh`, the
  CronJob YAML): the app-cluster token goes only into a private per-run kubeconfig (one cluster/user/context, the
  secret's TLS shape); every app-cluster kubectl call uses `--kubeconfig` and nothing else for server, token or TLS.
- **CVE pin overlay** (`applicationsets/services-git.yaml`, `scripts/lib/providers/k3s-hostinger.sh`): malformed pins
  are ignored, never applied; the services AppSet does not trust the pin branch blindly.
- **Console TOTP** (`scripts/libexec/k3dm-console-gate.py`, `k3dm-console-totpd.py`, `k3dm-console-totpctl.py`):
  escalating lockout; decay counts each day once; rotate clears `lock_level`; enrolment prints a scannable QR and keeps
  recovery codes on screen; the gate filters bracketed-paste/escape sequences and maps 0/1/8 to O/I/B only for
  non-6-digit input, with a hint on local rejection.
- **DR drill** (`bin/dr-drill`, `scripts/plugins/hub_data.sh`): preflight refuses fast (rc 2, before the export clone)
  when the age identity is unreadable; after restore, `_hub_data_drill_ldap_resync` regenerates a root token (stdin
  only, never argv), rewrites Kubernetes auth config, revokes the token, waits for the SecretStore to be Ready before
  forcing the ExternalSecret, waits for a fresh refresh, restarts OpenLDAP; any failure prints the step, forces V4
  false and still runs every V check; an LDAP bind failure must not exit the drill.
- **istioctl** (`scripts/lib/core.sh`, lib-foundation subtree): pinned 1.31.4, SHA-256 verified, the version probe uses
  `--remote=false` so it cannot hang on an unreachable cluster.
- **Alerts, sync and preflight** (`prometheusrule.yaml`, `Makefile` sync targets, `bin/cluster-preflight`): the alert
  regex matches cluster-prefixed Application names; sync-branch/sync-main find the services git generator by content;
  preflight renames services Applications and refuses a render that matched nothing.
- **Dashboards** (`grafana-dashboard-agent-activity.yaml`, `-agent-dispatch.yaml`): mode labels and the continuation
  panel query match their titles.

Look for:
- a failure path that exits 0 or logs success (a read error treated as empty, an ignored return code, `|| true` on a
  step that matters);
- quoting/injection: unquoted expansions, unvalidated input reaching git, kubectl, sshd config or a shell;
- a secret (token, TOTP seed, password, recovery code) in argv, xtrace, a log line;
- a sudo ticket that can survive a stage or run, or a staged tree a non-root user can modify;
- tests that cannot fail (negated commands without `run !`, `[ a ] && [ b ]` chains where only the last link counts,
  assertions on the wrong `run`, stubs that hang on stdin) or tests that write outside a temp dir or call real
  sudo/launchctl.

## Before You Start

1. `git log --oneline -1` and confirm HEAD is bc93f266.
2. Read the changed hunks of the files below, then enough of each surrounding function to judge them.

## Files

| File | Change |
|---|---|
| every file in `git diff --name-only origin/main...bc93f266 -- bin scripts Makefile` | read only |

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
    intent: An independent model checks the v1.45.1 release code before you merge it, in place of Copilot this month.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** standing rule from "Copilot reach his cap ... you might want to have Argon for code review" (operator, 2026-11-17): release PRs get a blind Argon review until 2026-12-01; v1.45.1 release PR opened in session 2026-11-25 after the operator's live checks. Intent text is the PR #164 spec's, version updated.
