# Pre-existing local-macOS BATS failures (not v1.27.0, not CI-blocking)

**Filed:** 2026-09-03
**Status:** open, low priority — separate from the v1.27.0 milestone.

## What

A single-threaded local `bats scripts/tests/ --recursive` on macOS reports 4 failures that are **not** introduced by any branch and **pass in CI**. They fail identically on `main` (which is CI-green), so they are a local-macOS-environment artifact, not a regression. They do **not** block the v1.27.0 PR.

Established by running the affected files on `main` (CI-green baseline) and on `k3d-manager-v1.27.0` in isolation — both fail these, both files byte-identical.

## The 4 tests

| Test | File | Failing assertion |
|------|------|-------------------|
| configure_vault_argocd_repos --dry-run makes no kubectl calls | `scripts/tests/plugins/argocd_deploy_keys.bats:98` | `[ ! -s "$KUBECTL_LOG_PATH" ]` — kubectl log non-empty under dry-run locally |
| configure_vault_argocd_repos --dry-run --seed-vault prints actions only | `scripts/tests/plugins/argocd_deploy_keys.bats` | same family |
| slack relay cluster-status acks before webhook completes | `scripts/tests/plugins/slack_relay_ack.bats:18` | `[ "${status}" -eq 0 ]` — relay returns non-zero locally |
| slack relay allowlist includes cluster-status and hostinger-status | `scripts/tests/plugins/slack_slash_commands.bats` | same family |

## Why not fixed now

- Not caused by v1.27.0; fixing them is a separate portability task.
- CI (Linux) passes them, so they are not a release gate.
- Fixing by weakening assertions would hide a real macOS/CI behavioral difference — a proper fix needs root-causing the macOS-specific kubectl-log write and the slack-relay non-zero exit.

## Next step (when picked up)

Root-cause the macOS vs Linux divergence (likely a tool/shell portability gap: BSD vs GNU `grep`/`sed`, or a backgrounded relay job). Do not touch these to make the v1.27.0 branch "look" green.
