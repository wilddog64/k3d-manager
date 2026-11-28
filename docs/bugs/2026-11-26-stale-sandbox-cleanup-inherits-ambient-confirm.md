# Bug: webhook stale-sandbox cleanup inherits an ambient `CONFIRM=1`, so a preview can apply

**Status:** OPEN — captured, not triaged
**Priority:** P2 (proposed) — a "preview" could run the destructive local cleanup; exposure today is limited (see Severity)
**Introduced by:** `d48e465f` (2026-08-19, `bin/cleanup-stale-sandbox` reads `CONFIRM`) meeting `scripts/lib/webhook/proc.py:23` (child env defaults to the parent's)
**Should have been caught by:** offline test
**Introducing change reviewed:** unknown
**Waiting on:** operator decision — since 2026-11-26
**Classified:** pending (Argon, from this doc alone)
**Prior art:** exact-slug glob: none; `docs/bugs/2026-09-25-deploy-app-cluster-confirm-bats-mutates-live-cluster.md` read — same class (ambient confirm reaching a live action), different command; `make find-similar-docs` not run
**Severity:** medium if reached, low exposure: the webhook LaunchAgent template does not set `CONFIRM` (no match in `scripts/etc/launchd/com.k3d-manager.webhook.plist.tmpl`), so it takes a webhook started by hand or by a test harness with `CONFIRM=1` in its environment. The cleanup boots out three LaunchAgents, removes their plists and deletes a kube context (`bin/cleanup-stale-sandbox:35-57`); it does not touch AWS
**Filed:** 2026-11-26, found in the blind reviews of v1.46.0 plan 3 (Fable subagent; Neon dispatch `v1460-plan3-review-neon`), Claude confirmed in code; operator: "File as bugs (Recommended)"
**Component:** `bin/k3dm-webhook` `_run_stale_sandbox_cleanup` (`:549-552`), `bin/cleanup-stale-sandbox:4-5,18`

## Symptom (from code)

`_run_stale_sandbox_cleanup` builds `[cleanup-stale-sandbox]` and appends `--confirm` only when confirm is true
(`bin/k3dm-webhook:549-551`), then calls `_spawn_capture_text(cmd, timeout=30)` with no `env` (`:552`), which copies
`os.environ` (`scripts/lib/webhook/proc.py:23`). The script starts with `confirm="${CONFIRM:-0}"`
(`bin/cleanup-stale-sandbox:5`), so a preview applies whenever the webhook's environment has `CONFIRM=1`. The script
also reads `CLUSTER_PROVIDER` and `ACG_KUBE_CONTEXT` from the same environment (`:4`, `:18`).

## Fix (for triage)

Pass an explicit environment without `CONFIRM` (or `CONFIRM=0` for preview), or make the script ignore `CONFIRM` when
called with `--dry-run` and have the webhook always pass `--dry-run` or `--confirm`. Test: preview with `CONFIRM=1` in
the parent environment and a stub `launchctl`; the stub log must show no `bootout` (red on current code).
