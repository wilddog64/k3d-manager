# Bug: `cluster-up` step 4.1 hits the launchd reload race (error 5), fails the run, and leaves the hub's Vault port-forward unloaded

**Status:** OPEN
**Priority:** P2 — `/cluster-up aws` on the hub fails at step 4.1 whenever `com.k3d-manager.vault-port-forward` is already loaded (the hub build loads it), and the hub loses `127.0.0.1:18200`; workaround: `make install-vault-port-forward` on the M5 restores :18200 (operator ran it 2026-11-11, http 200), then rerun `/cluster-up aws`
**Waiting on:** operator decision — since 2026-11-11 (intent approval; release placement)
**Introduced by:** pre-existing (the bootout-then-bootstrap pair at `bin/cluster-up:733-734` predates the 2026-10-31 and 2026-11-03 reload-race fixes)
**Should have been caught by:** review — the 2026-10-31 and 2026-11-03 fixes repaired the same race in their own files without sweeping the other callers
**Severity:** medium — an unattended cluster-up fails after the AWS stack is created and k3s and ArgoCD are installed; meanwhile hub readers of :18200 lose Vault (webhook smoke `scripts/lib/webhook/smoke.py:184`, `scripts/plugins/observability.sh:98,351`, `bin/argocd-app-sync:112`, `bin/hub-restore:78`, `bin/rotate-ghcr-pat`, `bin/restore-hub-ghcr-pat`)
**Approval:** operator 2026-11-11: "can you investigate this and file bug if necessary" (same session, ACG cluster-up investigation)
**Intent approved:** pending
**Prior art:** `docs/bugs/2026-10-31-hub-port-forward-reload-race-and-hub-migrate-entrypoint.md`, `docs/bugs/2026-11-03-observability-launchd-reload-race-and-direnv-python.md`, `docs/bugs/v1.7.1-bugfix-launchd-ensure-bootout-before-bootstrap.md`, `docs/issues/2026-09-16-restart-webhook-bootstrap-io-error.md` — read; same race, different callers, all fixed locally; this is a recurrence at a caller none of them changed (`make find-similar-docs` not run: vector store unreachable from the M4)
**Filed:** 2026-11-11
**Detected by:** Claude, reading operator Slack job `c998511f` on the M5
**Affected:** `bin/cluster-up` (`:722-736`)
**Branch:** `k3d-manager-v1.43.15`

## Observed (M5, 2026-11-10 18:34 PST, `~/.local/share/k3d-manager/webhook-jobs/c998511f/output:395-410`)

    INFO: [acg-up] Vault is unsealed and reachable.
    INFO: [acg-up] Step 4.1/12 — Installing Vault port-forward LaunchAgent (localhost:18200, auto-restart)...
    Bootstrap failed: 5: Input/output error
    WARN: [acg-up] failed (exit 5) — cleaning up local processes...
    WARN: [acg-up] CloudFormation stack 'k3d-manager-cluster' (us-west-2) was created by this run and is still running — billable. Reclaim it with: make down
    ERROR: make up CLUSTER_PROVIDER=k3s-aws exited 2

Read-only checks on the M5 right after:
- `~/Library/LaunchAgents/com.k3d-manager.vault-port-forward.plist` was rewritten at 18:34. `plutil -lint` says OK, `launchctl print-disabled` says `enabled`, and `/opt/homebrew/bin/kubectl` exists.
- The label is **absent** from `launchctl list`, and nothing listens on :18200.
- `~/Library/Logs/k3dm-vault-port-forward.log` ends in `Handling connection for 18200`, so the agent had been loaded and serving before this run.

## Root cause

`bin/cluster-up:733-734`:

    launchctl bootout "gui/$(id -u)/${_vault_pf_label}" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "${_vault_pf_plist}"

`launchctl bootout` returns before launchd has finished removing a running job. A `bootstrap` of the same label sent during that window fails with `5: Input/output error`. The 2026-10-31 doc records this on the M5 (`launchctl print` of an unloaded label exits 113), and fixed it by polling until the label is gone. The 2026-11-03 doc fixed it with a retry loop (`_observability_launchd_reload`, `scripts/plugins/observability.sh:229`). `cluster-up` has neither: the bootout succeeds, the bootstrap fails, and `set -e` ends the run with the agent gone.

## Fix

In `bin/cluster-up` step 4.1 only, replace the raw pair at `:733-734` with the repo's existing helper, which the Makefile already uses for this same agent (`Makefile:687`, `make install-vault-port-forward`) and five others:

    "${REPO_ROOT}/bin/launchd-reload" "${_vault_pf_label}" "${_vault_pf_plist}"

`bin/launchd-reload` boots out the label (treating exit 3, not loaded, as fine), polls `launchctl print` until the label is gone (`LAUNCHD_RELOAD_TRIES`, default 30, `LAUNCHD_RELOAD_WAIT` 0.5 s), then bootstraps. When it fails, step 4.1 fails with: `Vault port-forward LaunchAgent reload failed; reinstall: make install-vault-port-forward`. Do not add a bootstrap retry. The operator ran `make install-vault-port-forward` on the M5 on 2026-11-11 with the agent unloaded, and it reloaded cleanly: `launchctl list` shows the label at PID 10215, and :18200 `/v1/sys/health` returns http 200.

Do not change `bin/launchd-reload`, the plist template, the label, the transient port-forward (`:690-720`), or any other file's launchctl calls.

## Files

- `bin/cluster-up`
- `scripts/tests/bin/cluster_up_vault_pf_agent.bats` (new)

## Contract readers

The LaunchAgent label `com.k3d-manager.vault-port-forward` and its plist path (found with `git grep -n "vault-port-forward"` outside tests and docs):
- `bin/cluster-up:724-735` — **writer**; changes: waits and retries. The label and the plist are unchanged.
- `bin/k3dm-machine-setup:636`, `scripts/etc/machine/agents.hub.list:7`, `scripts/etc/machine/hub-local.list:6`, `bin/hub-restore:81` (`make install-vault-port-forward`) — **writers** through the machine-setup installer. Unchanged: they install the same label, and only cluster-up raced.
- `bin/cluster-down:250` — **writer** (bootout on down). Unchanged.
- `scripts/etc/launchd/com.k3d-manager.vault-port-forward.plist.tmpl` — unchanged.
- The :18200 readers listed under Severity are unchanged; they benefit from the agent staying loaded.

## Not in scope (same raw pattern, not seen failing)

The same raw bootout-then-bootstrap pair is at `bin/k3dm-webhook-setup:105-106`, `scripts/plugins/hub_data.sh:517-518`, `scripts/plugins/hub_snapshot.sh:354-355` and `scripts/plugins/vault.sh:1408-1409`. The shared helper already exists (`bin/launchd-reload`); moving those four callers to it goes in `docs/ideas.md` as a row, not in this spec.

## Acceptance

```yaml
must:
  - id: M1
    text: "when the label is still listed for a few polls after bootout (stub launchctl print exits 0 twice, then 113), step 4.1 waits, bootstraps once, and prints 'installed' (paired positive control for N1)"
  - id: M2
    text: "when the label is not loaded (bootout exits 3, print exits 113 at once), bootstrap runs once"
  - id: M3
    text: "step 4.1 calls bin/launchd-reload with the label and the plist path, and makes no direct launchctl bootstrap call of its own"
must_not:
  - id: N1
    text: "bootstrap is called while launchctl print still reports the label loaded (red on pre-fix cluster-up: the stub records bootstrap right after bootout)"
  - id: N2
    text: "step 4.1 prints 'installed' when bin/launchd-reload exits non-zero (label never drops, or bootstrap exits 5); it fails naming make install-vault-port-forward"
evidence:
  - id: E1
    proves: [M1, M2, M3, N1, N2]
    kind: offline
    intent: "tests run the real step 4.1 with a fake launchctl that is slow to drop the old agent: cluster-up waits until it is gone before starting the new one, and if the reload still fails the step stops and tells you to run make install-vault-port-forward instead of claiming success"
  - id: E2
    proves: [M1, N1]
    kind: live
    intent: "on the M5, with the Vault port-forward agent already loaded, /cluster-up aws from Slack passes step 4.1 and :18200 still answers afterwards"
interface:
  - "bin/cluster-up step 4.1 block, run with PATH stubs for launchctl (print/bootout/bootstrap, exit codes scripted per call, argv logged), kubectl, curl; scratch HOME (fixture asserts HOME is the scratch dir before running); _is_mac forced true"
```

## Definition of done (worker)

1. Run `bats scripts/tests/bin/cluster_up_vault_pf_agent.bats` and every existing suite that sources `bin/cluster-up`, with the command, exit code and every error line.
2. For each `must_not`: break the guard, show its test red, restore it, show it green.
3. "No read-only real-data run possible": step 4.1 mutates launchd.
4. List every choice the spec did not decide.

## Stub provenance

`launchctl print` of an unloaded label exits 113 (M5, recorded in `docs/bugs/2026-10-31-hub-port-forward-reload-race-and-hub-migrate-entrypoint.md:27`). `Bootstrap failed: 5: Input/output error` with exit 5 is from the M5 job above (2026-11-10 18:34 PST).
