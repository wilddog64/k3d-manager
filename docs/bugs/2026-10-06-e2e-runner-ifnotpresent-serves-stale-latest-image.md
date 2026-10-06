# E2E runner Job uses `IfNotPresent` on `:latest`, so a hub node serves a stale test image

**Filed:** 2026-10-06
**Status:** OPEN — spec below, for Codex
**Component:** `scripts/plugins/e2e.sh` — both Playwright runner Job manifests (`imagePullPolicy: IfNotPresent`, lines 232 and 646)
**Severity:** high — the Tier 1 release gate reports failures that were already fixed upstream, and would equally report a pass for tests that were since broken
**Found by:** v1.41.0 release smoke (`make e2e`, run `1791290346-2661`)

## Symptom

`make e2e` on `k3d-manager-v1.41.0` (`f945a8e5`): 91 passed, 8 failed, all in
`tests/flows/order-management.spec.ts` with `HTTP 400 .../status: {"code":"BAD_REQUEST","message":"status is required"}`.
That is the order-status enum bug (`docs/bugs/2026-08-29-e2e-order-status-enum-mismatch.md`),
fixed in `shopping-cart-e2e-tests` PR #11 (`e5e644d`, 2026-10-05) and published to `:latest`
the same minute.

## Root cause

The harness runs `${E2E_IMAGE}:${E2E_IMAGE_TAG}` with `E2E_IMAGE_TAG` defaulting to `latest`
and `imagePullPolicy: IfNotPresent`. vCluster pods are scheduled onto the hub's k3d nodes, and
`k3d-k3d-cluster-agent-0` already had a `:latest` cached from an earlier run:

| | digest | tag |
|---|---|---|
| cached on `agent-0` | `sha256:3a09b410…` (created 2026-10-02T19:19Z) | `sha-35098ac` — pre-fix |
| GHCR `:latest` | `sha256:3b3e03d2…` (2026-10-05T11:27Z) | `sha-e5e644d` — fixed |

With `IfNotPresent` the kubelet never re-resolves the tag, so every run on that node keeps
executing the 10-02 test suite. The 10-05 run (`1791168841-15959`) was the same stale image.

`IfNotPresent` was deliberate once: the 2026-08-16 amd64-only workaround side-loaded a locally
built arm64 `:latest` via `k3d image import`
(`docs/bugs/2026-08-16-e2e-playwright-image-amd64-only.md`). The image has been multi-arch since
2026-08-24 (`shopping-cart-e2e-tests` PR #7), so nothing relies on that any more.

## Fix

In `scripts/plugins/e2e.sh`, derive the pull policy from the tag instead of hard-coding it:

- New `E2E_IMAGE_PULL_POLICY` (exported with the other `E2E_*` vars). Empty by default.
- When unset: `Always` if `E2E_IMAGE_TAG` is `latest` (a mutable tag), otherwise `IfNotPresent`
  (an immutable `sha-*` tag or digest does not need re-pulling).
- When set, use it verbatim (`Always` | `IfNotPresent` | `Never`) — `Never` keeps the
  side-load workflow available. Reject any other value.
- Substitute the resolved policy into **both** runner Job manifests (lines 232 and 646).

BATS (pure logic, `scripts/tests/plugins/`): `latest` → `Always`; `sha-abc` → `IfNotPresent`;
explicit override wins; invalid override fails. RED-check against the pre-fix source.

Docs: note `E2E_IMAGE_TAG` / `E2E_IMAGE_PULL_POLICY` where the e2e harness is documented.

## Verification

Pinned run `E2E_IMAGE_TAG=sha-e5e644d54e9a84a0f93ac52fa989eeecb310dbdf make e2e` (operator,
2026-10-06, run `1791290881-10078`, commit `f945a8e5`): **98 passed, 0 failed** of 102 — every
`order-management` failure gone. The stale cached image was the whole cause.

## Also seen: `make e2e` exits 1 after a passing run

The same pinned run wrote `exit_code=0` / `result: pass` to the summary, yet `make` ended with
`make: *** [e2e] Error 1`. macOS `script` propagates the child status correctly (checked), and
the log has no `ERROR`, `unbound` or bash runtime error. Code reading did not locate the non-zero
exit; suspects are the persistent `RETURN` / `EXIT` traps set inside `scripts/plugins/argocd.sh`
(lines 404 and 1130) reached via `_vcluster_deregister_from_hub` during teardown, after
`_e2e_exit_trap` has captured `rc=0`. Needs a traced run to confirm; tracked separately from the
pull-policy fix because it is a different defect.
