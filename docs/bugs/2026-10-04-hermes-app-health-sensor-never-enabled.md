# Bug: Hermes `app_health` sensor has been `unknown` since v1.40.0 — never enabled

**Filed:** 2026-10-04, Claude
**Branch:** `k3d-manager-v1.41.0`
**Status:** OPEN. The fix is specified below; queued for Codex after the three sandbox-recovery fixes.
**Severity:** low. Nothing is broken, but a sensor shipped in v1.40.0 has never sampled anything.

## Observed

The Grafana Hermes sensor table shows `app_health | no app health targets configured | unknown`.

## Root cause

The v1.40.0 spec (`docs/plans/v1.40.0-hermes-app-health-delta-sensor.md`) shipped the sensor
**off by default**: `_app_health_targets()` (`bin/k3dm-hermes:101`) returns `[]` unless
`K3DM_HERMES_APP_HEALTH_ENABLED=1`, and `app_health` then short-circuits to `unknown`. Enabling
it was gated on a read-only dry run that was never done, and nothing set the variables. The
installed LaunchAgent environment has only `K3DM_HERMES_JITTER`, `K3DM_REPO_ROOT` and `PATH`.

## Dry run (Claude, 2026-10-04, read-only)

Through the API server's service proxy on `ubuntu-hostinger`, the same path the sensor uses:

| Path | Result |
|---|---|
| `/api/v1/namespaces/shopping-cart-payment/services/payment-service:8084/proxy/actuator/health` | `UP` |
| `.../actuator/health/liveness` | `UP` |
| `.../actuator/health/readiness` | `UP` |

The context, proxy path and port are confirmed. One limitation: the aggregate response carries no
`components` (details hidden), so a filed delta will say "aggregate DOWN while both probe groups UP"
without naming the failing component.

## Fix

Enable the sensor in the LaunchAgent template, which `bin/k3dm-hermes-setup` renders through
`_install_hermes_agent`. Editing the installed plist by hand would be lost on the next install.

## Fix spec

**File 1 — `scripts/etc/launchd/com.k3d-manager.hermes.plist.tmpl`.** Replace

```xml
    <key>K3DM_HERMES_JITTER</key>
    <string>1</string>
```

with

```xml
    <key>K3DM_HERMES_JITTER</key>
    <string>1</string>
    <key>K3DM_HERMES_APP_HEALTH_ENABLED</key>
    <string>1</string>
    <key>K3DM_HERMES_APP_CONTEXT</key>
    <string>ubuntu-hostinger</string>
```

Use a literal context, not a new `{{...}}` placeholder: the renderer lives in lib-foundation and
only substitutes `HERMES_BIN`, `K3DM_REPO_ROOT` and `HERMES_LOG`. If the context is ever renamed,
the sensor turns `unknown`, which is visible, not silent.

**File 2 — `scripts/tests/hermes/test_app_health.py`.** Append a test that parses the template with
`plistlib` (after replacing the three `{{...}}` placeholders with dummy strings) and asserts
`EnvironmentVariables["K3DM_HERMES_APP_HEALTH_ENABLED"] == "1"` and
`EnvironmentVariables["K3DM_HERMES_APP_CONTEXT"] == "ubuntu-hostinger"`. Use the module's existing
`ROOT`.

**File 3 — `docs/guides/hermes.md`, section "App-health aggregate/probe deltas".** Replace the
sentence "The sensor is disabled by default, uses no port-forward, ..." so it says the LaunchAgent
template enables it against `ubuntu-hostinger` (dry run 2026-10-04 passed), that it uses no
port-forward and files only a debounced delta through the existing e2e-bugs path, and that unsetting
`K3DM_HERMES_APP_HEALTH_ENABLED` in the template (then re-running `bin/k3dm-hermes-setup`) turns it
off. Leave the code default in `bin/k3dm-hermes` unchanged (still off when the variable is unset).

## Rollout (operator)

`bin/k3dm-hermes-setup`, then confirm the next poll shows `app_health` `healthy` with
"1 service(s) agree with their probe groups".
