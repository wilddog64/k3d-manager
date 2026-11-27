# Review: k3d-manager PR #166 (v1.46.0 release), part b — hub, acceptance, providers, cleanup — blind diff review

**Filed:** 2026-11-27
**Repo / branch:** `k3d-manager` / `k3d-manager-v1.46.0` (head 8bca3613; diff `origin/main...8bca3613 -- bin/cleanup-stale-sandbox bin/k3dm-hub-deploy bin/k3dm-repo-sync bin/k3dm-hermes bin/k3dm-operator-acceptance bin/k3dm-test-metrics Makefile scripts/lib/acceptance scripts/lib/providers scripts/plugins/argocd.sh scripts/plugins/shopping_cart.sh scripts/etc/grafana scripts/etc/argocd scripts/etc/machine`)
**Status:** ready for dispatch
**Risk:** low (review only; no code changes)
**Agent:** Argon (agy, `gemini-4-argon-medium`), role review

## Task

Review `git diff origin/main...8bca3613 -- bin/cleanup-stale-sandbox bin/k3dm-hub-deploy bin/k3dm-repo-sync bin/k3dm-hermes bin/k3dm-operator-acceptance bin/k3dm-test-metrics Makefile scripts/lib/acceptance scripts/lib/providers scripts/plugins/argocd.sh scripts/plugins/shopping_cart.sh scripts/etc/grafana scripts/etc/argocd scripts/etc/machine` blind, with the tests under `scripts/tests/` that exercise these files.
Docs and memory-bank are out of scope. Copilot is capped until 2026-12-01, so this review is the PR's review gate (with
part a). This pass is for **correctness**: a change that does not do what is described below, a failure that
reads as success, or a test that cannot fail. Report a security defect too if you see one. The intended behaviour is:

- **Hub deploy restart** (`bin/k3dm-hub-deploy`): after a promote, the webhook and cloud-bridge are restarted when their code changed; active queued or running jobs defer the restart (exit 3) rather than kill work.
- **Repo sync** (`bin/k3dm-repo-sync`): a CI-green commit whose content is already in `deploy/hub` (a squash-merged release) is not reported as promotable.
- **Stale sandbox cleanup** (`bin/cleanup-stale-sandbox`, `scripts/plugins/argocd.sh`, `scripts/lib/providers/k3s-hostinger.sh`): deletes only ApplicationSets whose destination is exactly the dead sandbox, only with `--confirm`, only when `/readyz` is unreachable; the appset reapply skips `istio-ambient.yaml` unless a live set exists or `ISTIO_AMBIENT_APPSET_ENABLE=1`.
- **SSH fragment** (`scripts/lib/providers/k3s-gcp.sh`, `k3s-az.sh`, `scripts/plugins/shopping_cart.sh`): aliases go to `~/.ssh/k3dm-sandbox.conf` through lib-foundation `ssh_fragment.sh`; the Include is checked before any cloud call; teardown removes only that provider's alias under `_dry_guard`; host lookup uses `ssh -G`.
- **Operator acceptance** (`scripts/lib/acceptance`, `bin/k3dm-operator-acceptance`): the offline run never reads Keychain, never reaches a real endpoint, leaves no canary; the opt-in live profile is read-only.
- **Test metrics** (`Makefile` `test-all`, `bin/k3dm-test-metrics`): each `stage-complete` line carries `seconds=<n>`; `k3dm_test_stage_duration_seconds{stage}` is exported even from a cut-off log; old lines without `seconds=` still parse.

Look also for: unquoted shell expansions, input reaching a shell or `eval`; secrets in argv, logs or Slack text;
GNU-only flags (the hub runs Homebrew bash 5 with BSD coreutils); tests that cannot fail (bare `! cmd` in BATS),
touch the real `$HOME`, the real hub, network, sudo or launchctl.

## Before You Start

1. `git log --oneline -1` and confirm HEAD is 8bca3613.
2. Read the diff file by file, then the tests that cover each file.

## Files

| File | Change |
|---|---|
| every file in `git diff --name-only origin/main...8bca3613 -- bin/cleanup-stale-sandbox bin/k3dm-hub-deploy bin/k3dm-repo-sync bin/k3dm-hermes bin/k3dm-operator-acceptance bin/k3dm-test-metrics Makefile scripts/lib/acceptance scripts/lib/providers scripts/plugins/argocd.sh scripts/plugins/shopping_cart.sh scripts/etc/grafana scripts/etc/argocd scripts/etc/machine` | read only |

## What NOT to Do

- Do NOT edit, commit, push or comment on the PR.
- Do NOT use the network; do not run sudo, launchctl, kubectl, aws, ssh, or any make target that reaches a cluster.
- Do NOT update any memory-bank.

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
    intent: "An independent model checks the v1.46.0 hub, acceptance and provider code before you merge it, in place of Copilot this month."
interface: none
```

**Intent approved:** operator, 2026-11-17
**Approval words and scope:** standing rule from "Copilot reach his cap ... you might want to have Argon for code review" (operator, 2026-11-17): release PRs get a blind Argon review until 2026-12-01; v1.46.0 release PR #166 opened 2026-11-27 after the operator asked for it ("I think you can do 1, 2, 4, and 5!"). Intent text is the PR #165 spec's, version and part updated.
