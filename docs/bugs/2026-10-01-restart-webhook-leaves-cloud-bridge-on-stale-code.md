# `make restart-webhook` leaves the cloud bridge running stale code

**Filed:** 2026-10-01
**Branch:** `k3d-manager-v1.40.0`
**Severity:** medium — after a pull, the cloud bridge keeps serving the previous action allowlist
and redaction until someone remembers a second, undocumented restart.
**Status:** FIXED (Codex, 2026-10-01, `52efebde` on `k3d-manager-v1.40.0`)

## Problem

The webhook and the cloud bridge are two separate LaunchAgents:

- `com.k3d-manager.webhook` — restarted by `make restart-webhook` (`Makefile`, `restart-webhook:`).
- `com.k3d-manager.cloud-bridge` — `RunAtLoad` + `KeepAlive`, a resident Python process installed
  by `make install-cloud-bridge`. Nothing else restarts it.

The bridge imports shared webhook code at startup: `scripts/lib/webhook/cloud_actions.py`
(`ACTION_ALLOWLIST`), `redact.py` (`scrub_credentials`), `config.py` (`JOB_DIR`) and
`make_targets.py`. A change to any of them, or to `bin/k3dm-cloud-bridge`, is not live until the
bridge process restarts. The documented post-pull step is `make restart-webhook`, so the bridge
silently keeps the old allowlist and old redaction rules.

Observed 2026-10-01: the v1.40.0 test-target and diagnose actions and the artifact publishing
needed "restart the cloud bridge" as a separate operator step that no target performs.

## Fix

1. Add a `restart-cloud-bridge` target, same shape as `restart-webhook`, for
   `com.k3d-manager.cloud-bridge` / `$(HOME)/Library/LaunchAgents/com.k3d-manager.cloud-bridge.plist`.
   If the plist does not exist (bridge never installed), print
   `[restart-cloud-bridge] not installed — skipping (make install-cloud-bridge)` to stderr and exit 0.
   Do not bootstrap a missing plist.
2. `restart-webhook` restarts the webhook as today, then runs `$(MAKE) restart-cloud-bridge`.
   A machine without the bridge must still exit 0.
3. Add `restart-cloud-bridge` to `.PHONY` and to the help output if `restart-webhook` is listed there.
4. `docs/howto/cloud-session-requests.md`: state that `make restart-webhook` also restarts the bridge,
   and that `make restart-cloud-bridge` restarts the bridge alone.

## Tests

Offline only — never invoke `launchctl` for real. In `scripts/tests/bin/`, add a pytest that reads the
recipes from the `Makefile` and asserts (do NOT use `make -n`: it still executes `$(MAKE)` lines):

- `restart-webhook` invokes `restart-cloud-bridge`;
- `restart-cloud-bridge` targets the label `com.k3d-manager.cloud-bridge`;
- `restart-cloud-bridge` has a plist-existence guard that exits 0.

Then execute the `restart-cloud-bridge` recipe with `HOME` set to an empty temp dir and a `launchctl`
stub first on `PATH` that records its argv: it must exit 0, print the skip message, and the stub must
not be called. With a plist present in the temp `HOME`, the stub must receive `kickstart -k
gui/<uid>/com.k3d-manager.cloud-bridge`. Mutation-test both: remove the guard → red; drop the call
from `restart-webhook` → red.
