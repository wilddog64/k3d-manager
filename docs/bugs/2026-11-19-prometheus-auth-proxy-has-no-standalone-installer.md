# prometheus-auth-proxy LaunchAgent has no standalone installer, so hub-deploy's "unwired" report cannot be acted on

**Status:** OPEN — captured 2026-11-19
**Priority:** P2 — the agent keeps running on its existing plist; a reinstall is only possible through `deploy_observability` (triage 2026-11-25: was P3; Argon P2, Claude agreed)
**Triage:** patch → v1.46.1 (operator, 2026-11-25: "go with patch release v1.46.1"); Argon blind classification, Claude verified
**Branch:** `k3d-manager-v1.46.1` (not cut yet)
**Introduced by:** pre-existing
**Should have been caught by:** review
**Introducing change reviewed:** unknown
**Classified:** P2 by gemini-4-argon-medium, 2026-11-22 (Missing `make install-prometheus-auth-proxy` target prevents standalone reinstallation when reported unwired, with a workaround of running `deploy_observability`.)
**Waiting on:** dispatch — since 2026-11-25
**Prior art:** none above threshold (slug `ls` empty; find-similar-docs not run, vector store context missing on the M4)

## Symptom

2026-11-19, M5, after `make hub-deploy REF=364dce31` (first reconcile, state `launchd full`), the summary said
`launchd unwired 4`. The operator said to reinstall them. webhook, hermes and vault-failover were reinstalled with their
singleton installers. `prometheus-auth-proxy` could not be:

- `scripts/etc/machine/hub-local.list:13` names `install-prometheus-auth-proxy` as its installer, but the Makefile has no such target.
- The renderer is private (`_observability_install_prometheus_auth_proxy`, `scripts/plugins/observability.sh:548`); the dispatcher refuses `_` names. Its only public callers are `deploy_observability` (`:91`), `deploy_observability_acg` (`:717`), and `observability_rotate_prometheus_basic_auth` (`:982`), which rotates the password.

None of the four templates changed between 072bcb57 and 364dce31, so this report came from the first full reconcile, not from a real change.

## Proposed change

Add a `make install-prometheus-auth-proxy` target (hub role, honours `K3DM_AGENT_LOAD=0`) that calls a public wrapper around the private renderer, matching hub-local.list.
