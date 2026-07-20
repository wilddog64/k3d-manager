# Issue: Bare `sudo` in Install Functions Bypass `_run_command`

**Date identified:** 2026-03-15  
**Functions:** `_install_redhat_kubernetes_client`, `_install_debian_kubernetes_client`, `_install_redhat_helm`, `_install_debian_helm`, `_install_debian_docker`, `_install_redhat_docker`, `_ensure_cargo`

---

## Problem

Multiple install helpers invoked `sudo` directly (`_run_command -- sudo <cmd>`, bare `sudo` in pipes, or `_run_command sudo <cmd>` without `--`). These patterns bypass `_run_command`'s privilege guardrails, making it harder to audit sudo usage and allowing commands to execute outside the `_run_command` tracing/quiet logic.

## Fix

- Replaced every instance with `_run_command --prefer-sudo -- <cmd>` so privilege escalation always flows through `_run_command`.
- Updated pipeline stages (tee/gpg) to run through `_run_command --prefer-sudo --` instead of bare `sudo`.
- Covered `_ensure_cargo` so all package install paths share the same pattern.

## Verification

- `shellcheck scripts/lib/system.sh`
- `AGENT_AUDIT_MAX_IF=8 bash scripts/lib/agent_rigor.sh scripts/lib/system.sh`
- `env -i PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" HOME="$HOME" TMPDIR="$TMPDIR" bash --norc --noprofile -c 'bats scripts/tests/lib/system.bats scripts/tests/lib/core.bats scripts/tests/lib/agent_rigor.bats'`

## Status

Fixed on `feat/v0.3.1` (commit `0d3d6f1`).
