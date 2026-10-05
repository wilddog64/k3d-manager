# Bug: `make status` can resolve the wrong provider after switching between ACG and Hostinger

**Status:** Recurrence 3 FIXED 2026-10-05 (Codex, Claude-verified: 71 passed; dropping the template key turns the test red; operator must rerun `bin/k3dm-hermes-setup`); `_acg_resolve_provider` liveness check still open — previously FIXED 2026-06-24 set migration (v1.8.0); the 2026-09-27 recurrence (M1, `cluster-down` leaked the set entry) was fixed in `396afff8` (`_acg_unrecord_provider`, test `cluster_down_provider_marker.bats`). Recurrence items 2–3 were out of scope by design. Status line added 2026-09-30.

**Date:** 2026-06-24  
**Branch:** `feat/v1.8.0-acg-absorb-phase2-agy`  
**Files:** `scripts/lib/provider.sh`, `scripts/lib/providers/k3s-hostinger.sh`, `scripts/tests/lib/provider_contract.bats`

## Problem

`make status` is meant to report the currently active cluster provider, whether that is the ACG
sandbox (`k3s-aws`, `k3s-az`, `k3s-gcp`) or the permanent Hostinger app cluster (`k3s-hostinger`).

When both `ubuntu-k3s` and `ubuntu-hostinger` contexts are present, the current provider resolution
can still drift to the previous cluster if the shared active-provider marker is stale or missing.
That makes status switching unreliable and can send the health probe to the wrong cluster.

This is not a `/etc/hosts` problem. The failure is in provider state selection.

## Root Cause

Two gaps combine:

1. `scripts/lib/provider.sh::_acg_resolve_provider()` trusts the active-provider file without
   checking whether it still points at a live context.
2. `scripts/lib/providers/k3s-hostinger.sh` does not record Hostinger as the active provider after
   deploy/refresh, and the destroy path does not clear the shared marker.

As a result, the last provider to write the file wins, even if the user has switched to the other
cluster since then.

## Fix

- Make `_acg_resolve_provider()` validate the active-provider file before returning it.
- Record `k3s-hostinger` as active at the end of a successful Hostinger deploy/refresh.
- Clear the active-provider file when Hostinger is destroyed.
- Add provider-contract coverage for the active-provider resolution and Hostinger state hooks.

## Expected Result

- `make status` reports the current provider after switching between ACG and Hostinger.
- A stale provider file no longer forces status onto an unreachable or previous cluster.
- Hostinger refresh/deploy keeps the active-provider state current.

---

## Recurrence — 2026-09-27: `cluster-down` clears the scalar but leaks the set entry

**Branch:** `k3d-manager-v1.40.0`
**Files:** `bin/cluster-down`, `scripts/lib/provider.sh`, `bin/k3dm-webhook`, `Makefile`, `bin/cluster-status-summary`

The 2026-06-24 fix replaced the single scalar marker with a **set** —
`_ACG_ACTIVE_PROVIDERS_DIR` (`active-providers/`, one file per live provider) — keeping
`_ACG_ACTIVE_PROVIDER_FILE` (`active-provider`) as a legacy tie-break. `provider_active_set.bats:74`
still records the intent: *"prove the SET, not the scalar, drives it."*

The teardown path never joined that migration.

`bin/cluster-down:127` hardcodes the scalar path and nothing else:

```bash
_dry_guard "remove active-provider marker" rm -f "${HOME}/.local/share/k3d-manager/active-provider"
```

It never calls `_acg_unrecord_provider` and never touches `active-providers/`. So every teardown
**clears the tie-break and leaks the set entry** — the exact inverse of what the resolver needs.

Live state on 2026-09-27 confirms it:

| Path | State |
|---|---|
| `active-providers/k3s-aws` | present, **dated Sep 4 14:04** |
| `active-providers/k3s-hostinger` | present |
| `active-provider` | **absent** |

An ACG sandbox lives 4 hours. The `k3s-aws` entry had outlived its cluster by 23 days.

### Why that breaks resolution

`_resolve_provider` (`scripts/lib/provider.sh:258-266`) shortcuts only when the set holds exactly
one entry; with two it falls back to the scalar — which teardown deleted. Every consumer that reads
the scalar alone then lands on its hardcoded default, and **the two layers do not agree on what that
default is**:

| Consumer | Default when the scalar is absent |
|---|---|
| `scripts/lib/provider.sh:266` | `k3s-hostinger` |
| `bin/k3dm-webhook:149` | `k3s-aws` → context `ubuntu-k3s` |
| `Makefile:153` (`make status`) | `k3s-hostinger` |
| `bin/cluster-status-summary:7-8` | falls through to its own default |

`ubuntu-k3s` is not in the live kubeconfig. That is the upstream trigger for the D1 symptom in
`2026-09-27-hermes-eso-sensor-unknown-kubeconfig-error-as-absence.md`: the ESO smoke probe was
pointed at a context that had not existed for three weeks. That fix correctly stopped reporting the
resulting kubeconfig error as resource absence; it deliberately did **not** address why the wrong
context was chosen. This is why.

### Fix direction (not implemented — operator decision)

1. `bin/cluster-down` must call `_acg_unrecord_provider "${_cluster_provider}"` instead of the
   hardcoded `rm -f`. That removes the set entry and clears the scalar only when it names the
   provider being torn down — which is already the correct, tested behaviour.
2. Reconcile the two `_resolve_provider` defaults. They disagree today, so the same absent-marker
   state resolves to different clusters depending on which layer asks.
3. Consider a startup reconcile that drops set entries whose context is absent from the kubeconfig,
   so a leak self-heals rather than persisting for weeks.

Item 1 is the narrow fix and matches the existing tested helper. Items 2 and 3 are wider than this
defect.

### Lesson

The 2026-06-24 fix added the set and updated the *write* and *read* paths, but the teardown path
reached around the abstraction with a literal path. A migration that leaves one consumer hardcoding
the old location does not fail loudly — it degrades into stale state that reads as a plausible
answer. When replacing a state file with a state directory, grep for the **literal path**, not just
the variable name: `bin/cluster-down` referenced neither `_ACG_ACTIVE_PROVIDER_FILE` nor
`_ACG_ACTIVE_PROVIDERS_DIR`, so every variable-name search missed it.

---

## Implementation Spec — Recurrence fix (2026-09-27)

Scope is **item 1 only** from the Recurrence section above: make teardown go through the tested
helper. Items 2 and 3 (reconciling the two `_resolve_provider` defaults, kubeconfig-based
self-heal) are explicitly **out of scope** — do not touch them.

### Before You Start

- Branch: `k3d-manager-v1.40.0` — `git pull origin k3d-manager-v1.40.0` first.
- Read `memory-bank/activeContext.md` (the top dated section describes this defect).
- Read, in full, before editing anything:
  - `bin/cluster-down` (lines 25–40 for the sourcing and `_cluster_provider`; line 127 is the target)
  - `scripts/lib/provider.sh` lines 104–126 (`_acg_record_provider`, `_acg_unrecord_provider`)
  - `scripts/tests/lib/provider_active_set.bats` (the helper is already fully covered there — do
    NOT add duplicate coverage for `_acg_unrecord_provider` itself)

### M1 — `bin/cluster-down`: call the helper instead of hardcoding the legacy path

`scripts/lib/provider.sh` is already sourced at line 30, and `_cluster_provider` is already set at
line 39, so the helper is in scope at line 127 with no new sourcing.

Replace this exact line:

```bash
_dry_guard "remove active-provider marker" rm -f "${HOME}/.local/share/k3d-manager/active-provider"
```

with:

```bash
_dry_guard "clear active-provider markers for ${_cluster_provider}" \
  _acg_unrecord_provider "${_cluster_provider}"
```

Notes, so you do not "improve" this:

- `_dry_guard` runs `"$@"` in the current shell, so a shell function is a valid target — same as the
  existing `_dry_guard ... sh -c` usages elsewhere in the file.
- `_acg_unrecord_provider` normalizes its argument itself, so pass `_cluster_provider` raw. Do not
  call `_acg_normalize_provider` at the call site.
- It removes the set entry unconditionally and clears the legacy scalar **only when the scalar names
  the provider being torn down**. That asymmetry is deliberate and already tested — do not change
  `provider.sh`.
- It returns 0 always, so it is safe under `set -euo pipefail`.

### M2 — new test: `scripts/tests/lib/cluster_down_provider_marker.bats`

`bin/cluster-down` executes teardown at source time under `set -euo pipefail`, so it cannot be
sourced in a test. This gate is therefore **structural, and the spec says so rather than dressing it
up as behavioural**: the behaviour it protects is already covered in `provider_active_set.bats`;
what rotted for three months was the *call site*, and a call-site gate is what was missing.

Write a two-test file following the existing `setup()` style in `provider_active_set.bats`
(`REPO_ROOT` derived from `BATS_TEST_FILENAME`):

1. A **disappearance gate** — `bin/cluster-down` must no longer contain the literal legacy path
   `share/k3d-manager/active-provider` followed by nothing else. Assert on the meaningful token,
   not a whole source line: grep the file for `active-provider"` preceded by `rm -f` and require
   zero matches. Remember `command grep -c` exits 1 on zero matches, so use `run` and assert on
   `status`/`output` rather than letting a nonzero exit fail the test.
2. A **presence gate** — `bin/cluster-down` must call `_acg_unrecord_provider` with
   `"${_cluster_provider}"`. Assert both tokens, not the full line.

Do NOT use a whole-line `grep -F` assertion in either test — that pattern rots on any reformat.

### M3 — CHANGELOG

Add under the existing `## [Unreleased]` heading (line 3), in a `### Fixed` subsection (create it if
absent). Write prose explaining the defect class, not a shortlog line: teardown hardcoded the legacy
scalar marker path, so it cleared the resolver's tie-break while leaking the per-provider set entry,
leaving a torn-down provider registered indefinitely and sending provider-scoped probes at a kube
context that no longer existed.

### Rules

- `shellcheck bin/cluster-down` must pass with **zero new warnings** versus before your change.
  Paste the before/after output.
- Run and paste the output of:
  - `bats scripts/tests/lib/cluster_down_provider_marker.bats`
  - `bats scripts/tests/lib/provider_active_set.bats`
  - `bats scripts/tests/lib/provider_contract.bats`
- **Mutation-test M2 before reporting done.** Revert the M1 line to the old hardcoded `rm -f`,
  re-run the new BATS file, and confirm **both** tests fail. Restore M1 and confirm they pass
  again. Paste both runs. A gate that cannot fail is not a gate.
- Do not reformat, re-indent or refactor anything else in `bin/cluster-down`.
- Minimal patch. No unsolicited refactors. LF endings. No inline comments in the shell change.

### Definition of Done

- [ ] `bin/cluster-down` line 127 replaced exactly as in M1
- [ ] `scripts/tests/lib/cluster_down_provider_marker.bats` added, 2 tests, both passing
- [ ] Mutation test performed and both directions pasted
- [ ] CHANGELOG `[Unreleased]` → `### Fixed` entry added
- [ ] shellcheck before/after pasted, zero new warnings
- [ ] All three BATS files pasted green
- [ ] Commit message, verbatim:
      `fix(cluster-down): unrecord the provider set entry instead of the legacy scalar`
- [ ] Pushed to `origin/k3d-manager-v1.40.0`; report the SHA and confirm
      `git rev-parse origin/k3d-manager-v1.40.0` matches
- [ ] `memory-bank/activeContext.md` and `memory-bank/progress.md` updated with the SHA and status;
      paste the lines you wrote

### What NOT to Do

- Do NOT create a PR.
- Do NOT merge, and do NOT commit to `main` — work only on `k3d-manager-v1.40.0`.
- Do NOT force-push.
- Do NOT use `--no-verify`; the pre-commit `check-doc-links` hook must run.
- Do NOT modify `scripts/lib/provider.sh` — the helper is already correct and tested.
- Do NOT touch `bin/k3dm-webhook`, `scripts/lib/webhook/config.py`, `Makefile` or
  `bin/cluster-status-summary`. The two disagreeing `_resolve_provider` defaults are a separate,
  unapproved change.
- Do NOT add a kubeconfig-based self-heal or a startup reconcile.
- Do NOT run `bin/cluster-down`, `make down`, or any live teardown. This change is verified by
  BATS and shellcheck only.
- Do NOT edit `scripts/lib/foundation/` or `scripts/lib/acg/` (subtrees).
- Do NOT modify files outside the four named above.

## Recurrence 3 — Hermes `data_layer` (2026-10-05)

**Symptom.** The Hermes `data_layer` sensor has reported `unknown — data layer status source
unavailable: TimeoutError` on every poll since 2026-10-04 03:56Z.

**Evidence (Claude, read-only):**
- `~/.local/share/k3d-manager/active-provider` contains `k3s-aws`. It was written on Oct 3 at 13:42 by the sandbox
  `make up`. The sandbox then expired without a `make down`, so `_acg_unrecord_provider` never ran.
- Hermes sends no `provider=` (`K3DM_HERMES_PROVIDER` is unset in the LaunchAgent). The webhook
  therefore resolves the provider to `k3s-aws` and probes the dead `ubuntu-k3s` cluster
  (`54.187.188.234:6443` times out).
- In the webhook log, `GET /api/v1/health` takes 98–159 s, against about 1 s normally. Hermes gives
  up before then. It stayed at about 99 s even after the Hostinger frontend was repaired at about 11:20Z.
- Hermes is a Hostinger monitor by design: its template already pins
  `K3DM_HERMES_APP_CONTEXT=ubuntu-hostinger`.

**Cause.** The marker is correct while a sandbox runs. A sandbox that **expires** instead of being
torn down leaves it pointing at a dead context. Item 1 of the original root cause
(`_acg_resolve_provider` trusts the file without checking that the context is live) was left out
of scope in 2026-09 and is still open. Hermes inherits that gap because it does not pin its
provider.

### Fix spec (Claude, 2026-10-05) — pin Hermes to Hostinger

**File 1 — `scripts/etc/launchd/com.k3d-manager.hermes.plist.tmpl`.** Directly after the
`K3DM_HERMES_APP_CONTEXT` pair, add:

```xml
    <key>K3DM_HERMES_PROVIDER</key>
    <string>k3s-hostinger</string>
```

**File 2 — `scripts/tests/hermes/test_app_health.py`.** In
`test_launchagent_template_enables_app_health_for_ubuntu_hostinger`, add
`assert environment["K3DM_HERMES_PROVIDER"] == "k3s-hostinger"`. Add one more test: call
`_run_cycle`'s `webhook_fetch` path with `K3DM_HERMES_PROVIDER=k3s-hostinger` set (monkeypatch
`_http_json` to record the URL, and `_keychain_secret` to return a dummy value), and assert that the requested
URL ends with `provider=k3s-hostinger`. If `webhook_fetch` cannot be reached without running the
whole cycle, extract it into a module-level `_webhook_url(host, path, provider)` helper used by
`webhook_fetch`, and test that helper instead.

**File 3 — `docs/guides/hermes.md:390`.** Change the default column of the `K3DM_HERMES_PROVIDER`
row from `(unset)` to `k3s-hostinger (set by the LaunchAgent template)`, and add one sentence: an
unset value falls back to the shared active-provider marker, which a sandbox that expired without
`make down` leaves pointing at a dead cluster.

**Rules.**
- Modify only Files 1–3. Do not edit the installed plist, the active-provider file, or
  `scripts/lib/provider.sh`.
- Do not commit or push; leave the changes unstaged.
- Run and paste `python3 -m pytest -q scripts/tests/hermes/test_app_health.py scripts/tests/hermes/test_hermes.py`
  and `plutil -lint` on the template with its placeholders replaced, as the test does.
- Mutation: delete the new template key, show that the test goes red, then restore it and prove the
  restore with `cmp`.

**Operator, after this lands:** run `bin/k3dm-hermes-setup` to reinstall the agent.

**Interim workaround:** `printf 'k3s-hostinger\n' > ~/.local/share/k3d-manager/active-provider`.
This corrects the stale marker; the next sandbox `make up` rewrites it.

**Still open (separate):** `_acg_resolve_provider` should verify that the marker's context answers
before trusting it.
