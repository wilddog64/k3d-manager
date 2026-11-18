# Review: k3d-manager PR #163 (v1.44.2 release) — blind diff review

**Filed:** 2026-11-17
**Repo / branch:** `k3d-manager` / `k3d-manager-v1.44.2` (head 2a7ac38c; diff `666b27b7..2a7ac38c -- bin scripts`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`), role review

## Task

Review `git diff 666b27b7..2a7ac38c -- bin scripts` blind (docs and memory-bank are out of scope). Copilot is capped
until 2026-12-01, so this review is the PR's review gate. Intended behaviour:

- **Hermes `vault_seal` sensor** (`scripts/lib/hermes/sensors.py`): reads Vault pod labels only (no exec, no Vault API,
  no Secret read). Label `vault-sealed` `"true"` → sealed, `"false"` → unsealed, anything else or missing → unknown.
  Sealed is reported as degraded from the second sealed cycle (debounce).
- **r7 gating** (`scripts/lib/hermes/repairs.py`, `approvals.py`): the cosign restore is offered only when Vault is
  unsealed (non-empty pod list, every pod unsealed) and at most 2 ExternalSecrets fail; approval re-checks and refuses
  if that no longer holds.
- **Cards** (`bin/k3dm-hermes`, `correlator.py`): a sealed incident leads with "Root cause: Vault sealed" and skips the
  LLM summary; it names only the contributors other than `vault_seal`. Repair cards carry a "Recommended:" line. A
  resolved incident lists withdrawn proposals, shows the time as `HH:MMZ` and names the repairs that ran.
- **Webhook** (`bin/k3dm-webhook`, `_run_analyze`): once per job, two read-only kubectl reads with
  `--request-timeout=10s` (Vault server pods in `secrets`, ClusterSecretStore `vault-backend`); `Warning:` lines dropped
  before JSON parse; a partly labelled pod is `<name> state unavailable` and not counted as sealed; when any fully
  labelled pod is sealed, every analysed alert gets the sealed sentence and no AI call or per-alert diagnostics run;
  `--` before the ArgoCD app name.
- **Watchdog stage 2** (`scripts/plugins/hub_data.sh`, `_hub_data_repoint_vault`, non-drill branch): writes the whole
  `vault-unseal` Secret from stdin JSON (replace if it exists, else create); no shard in argv or logs; a failed write
  fails the step; the drill branch is unchanged.
- **Stall-watch** (`bin/k3dm-dispatch-stall-watch`): the Slack notice prints the evidence path with `$HOME` replaced by
  `~`.
- **codex-dispatch `--project`** (`bin/k3dm-codex-dispatch`, `scripts/etc/projects.list`): registry lookup; `--project`
  needs `--branch`; `--repo` must match the registry path; `--version` only for a non-k3d-manager project; tag scheme =
  latest `v*` tag + 1 patch; ledger events carry `project`; verify/land/handoff/resume/abandon resolve the version;
  `open --project/--count`. k3d-manager tasks unchanged.
- **Dashboard** (`grafana-dashboard-agent-dispatch.yaml`): Stall recovery row expanded, panels at top level, plain-word
  legend names; no query semantics changed.

Look for:
- any path where a sealed Vault reads as unsealed or healthy (Hermes or webhook), or an unknown state enables r7;
- a shard, token or other secret reaching argv, xtrace, a log line or a Slack message (`_args_have_sensitive_flag`,
  `set -x` regions in `hub_data.sh`);
- the Secret write leaving a stale `shard-N` key, or succeeding silently after a kubectl failure;
- quoting/injection: unquoted expansions in shell, a project name or path from `projects.list` used unvalidated,
  a missing `--` before a user-supplied argument;
- a k3d-manager dispatch whose behaviour changes because of the `--project` code (version resolution, ledger rows);
- dashboard JSON that changes a query, unit or threshold while moving panels;
- tests that cannot fail (negated commands without `run !`, assertions on output from the wrong `run`, stubs that
  read stdin and hang), or tests that write outside a temp dir.

## Before You Start

1. `git log --oneline -1` and confirm HEAD is 2a7ac38c.
2. Read the changed hunks of the files below, then enough of each surrounding function to judge them.

## Files

| File | Change |
|---|---|
| `bin/k3dm-webhook` | read only |
| `bin/k3dm-hermes` | read only |
| `bin/k3dm-codex-dispatch` | read only |
| `scripts/plugins/hub_data.sh` | read only |
| `scripts/lib/hermes/sensors.py` | read only |
| `scripts/lib/hermes/repairs.py` | read only |

## What NOT to Do

- Do NOT edit, commit, push or comment on the PR.
- Do NOT touch any cluster, kubectl context, Keychain or network endpoint; reason from the code.
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
    intent: An independent model checks the v1.44.2 release code before you merge it, in place of Copilot this month.
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** "/create-pr" for v1.44.2; "Copilot reach his cap ... you might want to have Argon for code review" (operator, 2026-11-17) — release PRs get a blind Argon review until 2026-12-01.
